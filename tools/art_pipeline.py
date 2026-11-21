"""Offline art recipes, safe import, and local-ROI reconstruction evidence.

Only Pillow and the Python standard library are used. This program never calls
an image generation service, edits the production manifest, or overwrites an
existing image. Its JSON receipt is a proposed manifest fragment for review.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import math
import re
from pathlib import Path, PurePosixPath, PureWindowsPath
import sys

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "data/art/pipeline.json"


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _integer(value, minimum=0, maximum=None):
    return (type(value) is int and value >= minimum and
            (maximum is None or value <= maximum))


def _number(value, minimum=0, maximum=255):
    return (type(value) in (int, float) and math.isfinite(value) and minimum <= value <= maximum)


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"),
                      parse_constant=lambda text: (_ for _ in ()).throw(ValueError("nonfinite JSON: " + text)))


def validate_config(config):
    _require(isinstance(config, dict) and config.get("version") == 1, "invalid pipeline config version")
    _require(isinstance(config.get("runtime_size"), list) and len(config["runtime_size"]) == 2 and
             all(_integer(v, 1) for v in config["runtime_size"]), "invalid runtime size")
    _require(_integer(config.get("maximum_generation_attempts"), 1), "invalid attempt limit")
    for field in ("statuses", "operations"):
        values = config.get(field)
        _require(isinstance(values, list) and values and all(isinstance(v, str) and v for v in values)
                 and len(set(values)) == len(values), "invalid " + field)
    mask = config.get("mask", {})
    _require(_integer(mask.get("feather_pixels"), 0, 32) and
             _integer(mask.get("inpaint_dilation_pixels"), 0, 64) and
             _integer(mask.get("hard_recovery_threshold"), 1, 254), "invalid mask parameters")
    qa = config.get("qa", {})
    for field in ("core_max_error", "unedited_max_error", "inpaint_ring_max_error", "feather_mae", "feather_p95"):
        _require(_number(qa.get(field)), "invalid QA bound: " + field)
    _require(_number(qa.get("percentile"), 0.000001, 1), "invalid percentile")
    generation = config.get("generation", {})
    for field in ("tool", "target_size_prompt", "style_prompt", "inpaint_prompt", "not_callable_message", "composite_prompt", "all_cleanplate_prompt", "mask_prompt"):
        _require(isinstance(generation.get(field), str) and generation[field].strip(), "invalid generation config: " + field)
    return config


def load_config(path=CONFIG):
    return validate_config(read_json(path))


def safe_path(workspace, value, *, must_exist=False):
    """Manifest paths are relative POSIX paths; resolve catches symlink escapes."""
    _require(isinstance(value, str) and value and "\\" not in value and ":" not in value and
             not PureWindowsPath(value).is_absolute() and not PurePosixPath(value).is_absolute() and
             all(part not in ("", ".", "..") for part in value.split("/")), "unsafe workspace path: " + str(value))
    root = Path(workspace).resolve()
    result = (root / value).resolve()
    _require(result.is_relative_to(root) and result != root, "path escapes workspace: " + value)
    if must_exist:
        _require(result.is_file(), "missing path: " + value)
    return result


def relative_input(workspace, value):
    """A command-line absolute style path is allowed only inside the workspace."""
    path = Path(value)
    if path.is_absolute():
        root = Path(workspace).resolve()
        _require(path.resolve().is_relative_to(root), "input path escapes workspace")
        return path.resolve().relative_to(root).as_posix()
    return safe_path(workspace, value).relative_to(Path(workspace).resolve()).as_posix()


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_image(path, mode=None):
    try:
        with Image.open(path) as image:
            image.load()
            return image.convert(mode) if mode else image.copy()
    except (OSError, ValueError) as error:
        raise ValueError("unreadable image: " + str(path)) from error


def _qa_kind(value):
    _require(value in ("geometry_only", "art"), "invalid qa_kind")


def validate_manifest(workspace, manifest, config=None):
    config = config or load_config()
    _require(isinstance(manifest, dict), "manifest must be an object")
    section = manifest.get("round2_art")
    _require(isinstance(section, dict) and section.get("version") == 1, "round2_art version must be 1")
    style = section.get("active_style", {})
    safe_path(workspace, style.get("path"))
    _require(style.get("status") in config["statuses"], "invalid style status")
    _require(isinstance(style.get("sha256"), str) and re.fullmatch(r"[a-fA-F0-9]{64}", style["sha256"]), "invalid style sha256")
    recipes = section.get("recipes")
    _require(isinstance(recipes, list), "recipes must be an array")
    ids, source_paths, runtime_paths = set(), set(), set()
    for recipe in recipes:
        _require(isinstance(recipe, dict), "recipe must be an object")
        for field in ("id", "group"):
            _require(isinstance(recipe.get(field), str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", recipe[field]), "invalid recipe " + field)
        _require(recipe["id"] not in ids, "duplicate recipe id")
        ids.add(recipe["id"])
        for field in ("prompt", "version"):
            _require(isinstance(recipe.get(field), (str, int)) and str(recipe[field]).strip(), "invalid recipe " + field)
        _require(isinstance(recipe.get("prompt"), str), "prompt must be text")
        _require(recipe.get("status") in config["statuses"], "invalid recipe status")
        _require(recipe.get("operation") in config["operations"], "invalid recipe operation")
        for field in ("style_reference", "source_path", "runtime_path"):
            safe_path(workspace, recipe.get(field))
        _require(recipe["source_path"].casefold() != recipe["runtime_path"].casefold(), "runtime cannot overwrite source")
        _require(recipe["runtime_path"].casefold() not in runtime_paths, "duplicate runtime path")
        runtime_paths.add(recipe["runtime_path"].casefold())
        source_paths.add(recipe["source_path"].casefold())
        optional_paths = ("mask_path", "original_path", "cleanplate_path", "inpaint_mask_path", "processing_script", "reference_path")
        for field in optional_paths:
            if field in recipe:
                safe_path(workspace, recipe[field])
        trio = [field in recipe for field in ("mask_path", "original_path", "cleanplate_path")]
        _require(not (trio[0] or trio[2]) or all(trio), "layer QA needs mask, original, and cleanplate paths")
        if "qa_kind" in recipe:
            _qa_kind(recipe["qa_kind"])
        attempts = recipe.get("attempts")
        _require(isinstance(attempts, list) and len(attempts) <= config["maximum_generation_attempts"], "invalid attempts")
        indices = set()
        for attempt in attempts:
            _require(isinstance(attempt, dict) and _integer(attempt.get("attempt"), 1, config["maximum_generation_attempts"]), "invalid attempt record")
            _require(attempt["attempt"] not in indices, "duplicate attempt number")
            indices.add(attempt["attempt"])
            _require(attempt.get("status") in config["statuses"], "invalid attempt status")
            for field in ("output_path", "reference_path"):
                if field in attempt:
                    safe_path(workspace, attempt[field])
        if recipe["status"] in ("complete", "placeholder"):
            safe_path(workspace, recipe["source_path"], must_exist=True)
    _require(not source_paths.intersection(runtime_paths), "runtime path collides with source path")
    recompositions = section.get("recompositions")
    _require(isinstance(recompositions, list), "recompositions must be an array")
    recomposition_ids = set()
    for spec in recompositions:
        _validate_recomposition(workspace, spec)
        _require(spec["id"] not in recomposition_ids, "duplicate recomposition id")
        recomposition_ids.add(spec["id"])
    artifacts = section.get("artifacts", [])
    _require(isinstance(artifacts, list), "artifacts must be an array")
    artifact_ids = set()
    for artifact in artifacts:
        _require(isinstance(artifact, dict) and isinstance(artifact.get("id"), str) and artifact["id"], "invalid artifact id")
        _require(artifact["id"] not in artifact_ids, "duplicate artifact id")
        artifact_ids.add(artifact["id"])
        path = safe_path(workspace, artifact.get("path"))
        _require(artifact.get("status") in config["statuses"], "invalid artifact status")
        if "sha256" in artifact:
            _require(path.is_file() and artifact["sha256"] == sha256(path), "artifact sha256 mismatch")
        if "source_size" in artifact:
            with Image.open(path) as image:
                _require(artifact["source_size"] == list(image.size), "artifact source size mismatch")
        if "style_reference" in artifact:
            safe_path(workspace, artifact["style_reference"])
        if "input_paths" in artifact:
            _require(isinstance(artifact["input_paths"], list), "invalid artifact input paths")
            for input_path in artifact["input_paths"]:
                safe_path(workspace, input_path)
        if artifact["status"] == "complete":
            _require("sha256" in artifact, "complete artifact needs actual sha256")
    return section


def _validate_recomposition(workspace, spec):
    _require(isinstance(spec, dict) and isinstance(spec.get("id"), str) and spec["id"], "invalid recomposition id")
    _qa_kind(spec.get("qa_kind"))
    for field in ("original_path", "base_path"):
        safe_path(workspace, spec.get(field))
    if "reference_path" in spec:
        safe_path(workspace, spec["reference_path"], must_exist=True)
    _require(isinstance(spec.get("layers"), list) and spec["layers"], "recomposition needs layers")
    orders, paths = set(), set()
    for layer in spec["layers"]:
        _require(isinstance(layer, dict) and type(layer.get("z_index")) is int, "invalid layer z_index")
        safe_path(workspace, layer.get("path"))
        _require(layer["z_index"] not in orders and layer["path"].casefold() not in paths, "duplicate layer path or z_index")
        orders.add(layer["z_index"])
        paths.add(layer["path"].casefold())


def build_queue(workspace, manifest, style_path, only, config=None):
    config = config or load_config()
    section = validate_manifest(workspace, manifest, config)
    style_path = relative_input(workspace, style_path)
    style_file = safe_path(workspace, style_path, must_exist=True)
    style_image = read_image(style_file)
    if safe_path(workspace, section["active_style"]["path"]) == style_file:
        _require(sha256(style_file) == section["active_style"]["sha256"].lower(), "active style sha256 does not match file")
    _require(only == "all" or any(recipe["group"] == only for recipe in section["recipes"]), "unknown resource group: " + only)
    tasks, offline_tasks = [], []
    selected = [recipe for recipe in section["recipes"] if only == "all" or recipe["group"] == only]
    recipes_by_path = {recipe["source_path"]: recipe for recipe in section["recipes"]}
    selected_paths = {recipe["source_path"] for recipe in selected}
    relevant = [spec for spec in section["recompositions"] if
                spec["base_path"] in selected_paths or any(layer["path"] in selected_paths for layer in spec["layers"])]
    base_specs = {spec["base_path"]: spec for spec in relevant}
    artifacts = {artifact["id"]: artifact for artifact in section.get("artifacts", [])}
    task_ids = set()

    def generation_task(recipe, destination, prompt, reference_paths=(), task_id=None, dependencies=()):
        identifier = task_id or recipe["id"]
        _require(identifier not in task_ids, "duplicate generation task id: " + identifier)
        task_ids.add(identifier)
        references = [str(style_file)]
        for reference in reference_paths:
            path = safe_path(workspace, reference)
            if path.is_file():
                read_image(path)
            if str(path) not in references:
                references.append(str(path))
        state = artifacts.get(identifier, {})
        _require(not state or state["path"] == destination, "artifact path differs from declared task output")
        declared_status = state.get("status", recipe["status"] if identifier == recipe["id"] else "needs_builtin_generation")
        status = "complete" if declared_status == "complete" and safe_path(workspace, destination).is_file() else "needs_builtin_generation"
        required = list(dict.fromkeys([*reference_paths, *dependencies]))
        missing = [path for path in required if not safe_path(workspace, path).is_file()]
        tasks.append({"recipe_id": identifier, "owner_recipe_id": recipe["id"], "group": recipe["group"], "version": recipe["version"],
                      "status": status, "previous_status": recipe["status"],
                      "operation": recipe["operation"], "tool": config["generation"]["tool"],
                      "arguments": {"prompt": prompt, "referenced_image_paths": references,
                                    "transparent_background": bool(recipe.get("transparent_background", False))},
                      "source_destination": destination, "runtime_destination": recipe["runtime_path"],
                      "style_reference": style_path, "style_sha256": sha256(style_file),
                      "attempts_used": len(recipe["attempts"]),
                      "can_generate": not missing and status != "complete" and len(recipe["attempts"]) < config["maximum_generation_attempts"],
                      "ready": not missing, "missing_dependencies": missing, "depends_on": required,
                      "prerequisite": "Inspect local references with view_image before the built-in call. Never overwrite original sources; use versioned recipe paths for replacement outputs."})

    generated_composites = set()
    for spec in relevant:
        if spec["original_path"] in recipes_by_path or spec["original_path"] in generated_composites:
            continue
        recipe = recipes_by_path.get(spec["base_path"]) or next(recipes_by_path[layer["path"]] for layer in spec["layers"] if layer["path"] in recipes_by_path)
        prompt = config["generation"]["composite_prompt"] + "\n" + recipe["prompt"] + "\n" + config["generation"]["target_size_prompt"]
        reference = spec.get("reference_path", recipe.get("reference_path"))
        if reference is None and spec["id"] + "__composite" not in artifacts and safe_path(workspace, spec["original_path"]).is_file():
            reference = spec["original_path"]  # Legacy reference-only preview.
        if reference:
            safe_path(workspace, reference, must_exist=True)
        generation_task(recipe, spec["original_path"], prompt, [reference] if reference else [], spec["id"] + "__composite")
        generated_composites.add(spec["original_path"])

    for recipe in selected:
        operation = recipe["operation"]
        if "mask_path" in recipe:
            # A layer is an actual same-position extraction, including when its
            # previous source was a procedural placeholder.
            offline_tasks.append({"recipe_id": recipe["id"], "operation": "extract_layer", "tool": "tools/art_pipeline.py",
                                  "arguments": {field: recipe[field] for field in ("original_path", "mask_path", "source_path")},
                                  "cli_args": ["--extract-layer", recipe["original_path"], recipe["mask_path"], recipe["source_path"]],
                                  "source_destination": recipe["source_path"],
                                  "depends_on": [recipe["original_path"], recipe["mask_path"], recipe["cleanplate_path"]], "local_repaint_performed": False})
            target_mask = str(PurePosixPath(recipe["mask_path"]).with_suffix("")) + "_inpaint_target.png"
            offline_tasks.append({"recipe_id": recipe["id"] + "__inpaint_mask", "operation": "prepare_inpaint_target",
                                  "mask_path": recipe["mask_path"], "dilation_pixels": config["mask"]["inpaint_dilation_pixels"],
                                  "feather_pixels": config["mask"]["feather_pixels"], "output_path": target_mask,
                                  "depends_on": [recipe["mask_path"]], "source_destination": target_mask,
                                  "cli_args": ["--prepare-inpaint-target", recipe["mask_path"], target_mask]})
            prompt = config["generation"]["inpaint_prompt"] + "\n" + config["generation"]["mask_prompt"] + "\n" + recipe["prompt"]
            generation_task(recipe, recipe["cleanplate_path"], prompt, [recipe["original_path"], recipe["mask_path"]],
                            recipe["id"] + "__cleanplate", [recipe["original_path"], target_mask])
            tasks[-1]["arguments"]["referenced_image_paths"].append(str(safe_path(workspace, target_mask)))
            tasks[-1]["prepared_inpaint_mask"] = target_mask
            continue
        # Extraction is deterministic; it must never independently redraw Li.
        if operation in ("extract_layer", "runtime_copy"):
            continue
        inputs = []
        if "reference_path" in recipe:
            safe_path(workspace, recipe["reference_path"], must_exist=True)
            inputs.append(recipe["reference_path"])
        prompt = recipe["prompt"] + "\n" + config["generation"]["style_prompt"] + "\n" + config["generation"]["target_size_prompt"]
        if recipe["source_path"] in base_specs:
            spec = base_specs[recipe["source_path"]]
            prompt = config["generation"]["all_cleanplate_prompt"] + "\n" + config["generation"]["mask_prompt"] + "\n" + prompt
            inputs.append(spec["original_path"])
            inputs.extend(recipes_by_path[layer["path"]]["mask_path"] for layer in spec["layers"]
                          if layer["path"] in recipes_by_path and "mask_path" in recipes_by_path[layer["path"]])
        if operation == "inpaint_cleanplate":
            _require("original_path" in recipe and "inpaint_mask_path" in recipe, "inpaint recipe needs original and inpaint mask paths")
            for field in ("original_path", "inpaint_mask_path"):
                path = safe_path(workspace, recipe[field])
                if path.is_file():
                    read_image(path)
                inputs.append(recipe[field])
            prompt += "\n" + config["generation"]["inpaint_prompt"]
        generation_task(recipe, recipe["source_path"], prompt, inputs, dependencies=inputs[:1])
    return {"version": 1, "status": "needs_builtin_generation" if any(task["status"] != "complete" for task in tasks) else "complete",
            "message": config["generation"]["not_callable_message"],
            "active_style": {"path": style_path, "sha256": sha256(style_file), "status": section["active_style"]["status"],
                             "actual_size": list(style_image.size)}, "tasks": tasks, "offline_tasks": offline_tasks}


def _write_new(path, data):
    path = Path(path)
    if path.exists():
        if path.is_file() and path.read_bytes() == data:
            return
        raise FileExistsError("existing output is never overwritten: " + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation also protects against races with another task.
    with path.open("xb") as stream:
        stream.write(data)


def _png(image):
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    return stream.getvalue()


def import_recipe(workspace, recipe, config=None):
    config = config or load_config()
    source = safe_path(workspace, recipe["source_path"], must_exist=True)
    target = safe_path(workspace, recipe["runtime_path"])
    _require(source != target, "runtime cannot overwrite source")
    image = read_image(source)
    # Palette/CMYK sources normalize explicitly, retaining alpha if present.
    image = image.convert("RGBA" if "A" in image.getbands() or "transparency" in image.info else "RGB")
    width, height = image.size
    out_width, out_height = config["runtime_size"]
    scale = max(out_width / width, out_height / height)
    crop_width, crop_height = out_width / scale, out_height / scale
    crop = [(width - crop_width) / 2, (height - crop_height) / 2,
            (width + crop_width) / 2, (height + crop_height) / 2]
    runtime = image.resize((out_width, out_height), Image.Resampling.LANCZOS, box=tuple(crop))
    _write_new(target, _png(runtime))
    return {"id": recipe["id"], "status": recipe["status"], "source_path": recipe["source_path"],
            "runtime_path": recipe["runtime_path"], "source_size": [width, height],
            "runtime_size": list(runtime.size), "source_sha256": sha256(source), "runtime_sha256": sha256(target),
            "native_resolution_met": width >= out_width and height >= out_height,
            "origin": recipe.get("generator", "unspecified"),
            "transform": {"method": "equal_aspect_cover", "filter": "Lanczos", "scale": scale,
                          "source_crop": crop, "runtime_size": list(runtime.size)},
            "processing_script": "tools/art_pipeline.py", "art_passed": False, "visual_review": "not_evaluated"}


def prepare_masks(workspace, hard_mask_path, feather_path, inpaint_path, config=None):
    config = config or load_config()
    source = safe_path(workspace, hard_mask_path, must_exist=True)
    targets = [safe_path(workspace, value) for value in (feather_path, inpaint_path)]
    _require(len({source, *targets}) == 3, "mask outputs cannot overwrite source or each other")
    mask = read_image(source, "L")
    histogram = mask.histogram()
    _require(sum(histogram[1:255]) == 0 and histogram[255] > 0, "hard mask must be nonempty binary grayscale")
    feather = mask.filter(ImageFilter.BoxBlur(config["mask"]["feather_pixels"]))
    dilation = config["mask"]["inpaint_dilation_pixels"]
    target = mask.filter(ImageFilter.MaxFilter(2 * dilation + 1)) if dilation else mask.copy()
    for path, image in zip(targets, (feather, target)):
        _write_new(path, _png(image))
    return {"mask_path": feather_path, "inpaint_mask_path": inpaint_path,
            "feather_pixels": config["mask"]["feather_pixels"], "inpaint_dilation_pixels": dilation,
            "local_repaint_performed": False}


def extract_layer(workspace, original_path, mask_path, output_path):
    original_file = safe_path(workspace, original_path, must_exist=True)
    mask_file = safe_path(workspace, mask_path, must_exist=True)
    output_file = safe_path(workspace, output_path)
    _require(output_file not in (original_file, mask_file), "extraction cannot overwrite source")
    original, mask = read_image(original_file, "RGBA"), read_image(mask_file, "L")
    _require(original.size == mask.size, "extraction mask size mismatch")
    _require(original.getchannel("A").getextrema() == (255, 255), "original composite must be opaque")
    _require(mask.getbbox() is not None, "extraction mask is empty")
    original.putalpha(mask)
    _write_new(output_file, _png(original))
    return {"source_path": output_path, "source_sha256": sha256(output_file),
            "mask_path": mask_path, "original_path": original_path, "local_repaint_performed": False}


def prepare_inpaint_target(workspace, soft_mask_path, output_path, config=None):
    config = config or load_config()
    source = safe_path(workspace, soft_mask_path, must_exist=True)
    output = safe_path(workspace, output_path)
    _require(source != output, "target mask cannot overwrite source")
    soft = read_image(source, "L")
    threshold = config["mask"]["hard_recovery_threshold"]
    hard = soft.point(lambda value: 255 if value >= threshold else 0)
    _require(hard.getbbox() is not None, "target mask has no hard region")
    dilation = config["mask"]["inpaint_dilation_pixels"]
    target = hard.filter(ImageFilter.MaxFilter(2 * dilation + 1)) if dilation else hard
    _write_new(output, _png(target))
    return {"inpaint_mask_path": output_path, "soft_mask_path": soft_mask_path,
            "inpaint_dilation_pixels": dilation, "hard_mask_recovery_threshold": threshold,
            "local_repaint_performed": False}


def _metric(difference, region, percentile):
    histogram = difference.histogram(mask=region)
    merged = [sum(histogram[channel * 256 + index] for channel in range(3)) for index in range(256)]
    count = sum(merged)
    if not count:
        return {"pixels": 0, "samples": 0, "mae": 0.0, "p95": 0, "max_error": 0}
    position, cumulative, p95 = math.ceil(count * percentile), 0, 0
    for value, frequency in enumerate(merged):
        cumulative += frequency
        if cumulative >= position:
            p95 = value
            break
    return {"pixels": count // 3, "samples": count, "mae": sum(i * n for i, n in enumerate(merged)) / count,
            "p95": p95, "max_error": max(i for i, n in enumerate(merged) if n)}


def compare_regions(original, rebuilt, mask, config=None):
    config = config or load_config()
    _require(original.size == rebuilt.size == mask.size, "QA size mismatch")
    mask = mask.convert("L")
    core = mask.point(lambda alpha: 255 if alpha == 255 else 0)
    feather = mask.point(lambda alpha: 255 if 0 < alpha < 255 else 0)
    positive = mask.point(lambda alpha: 255 if alpha else 0)
    dilation = config["mask"]["inpaint_dilation_pixels"]
    affected = positive.filter(ImageFilter.MaxFilter(dilation * 2 + 1)) if dilation else positive
    ring = ImageChops.subtract(affected, positive)
    unedited = ImageChops.invert(affected)
    difference = ImageChops.difference(original.convert("RGB"), rebuilt.convert("RGB"))
    regions = {name: _metric(difference, roi, config["qa"]["percentile"])
               for name, roi in (("core", core), ("feather", feather), ("inpaint_ring", ring), ("unedited", unedited))}
    limits = config["qa"]
    passed = (regions["core"]["max_error"] <= limits["core_max_error"] and
              regions["unedited"]["max_error"] <= limits["unedited_max_error"] and
              regions["inpaint_ring"]["max_error"] <= limits["inpaint_ring_max_error"] and
              regions["feather"]["mae"] <= limits["feather_mae"] and
              regions["feather"]["p95"] <= limits["feather_p95"])
    return {"passed": passed, "regions": regions, "bounds": copy.deepcopy(limits),
            "metric": "absolute RGB byte differences; MAE/P95 over channels within each nonempty ROI"}


def qa_recipe(workspace, recipe, config=None):
    config = config or load_config()
    images = {field: read_image(safe_path(workspace, recipe[field], must_exist=True), "L" if field == "mask_path" else "RGBA")
              for field in ("original_path", "source_path", "cleanplate_path", "mask_path")}
    original, layer, clean, mask = [images[field] for field in ("original_path", "source_path", "cleanplate_path", "mask_path")]
    _require(len({image.size for image in images.values()}) == 1, "single-layer QA size mismatch")
    _require(mask.getbbox() is not None, "layer mask is empty")
    alpha = layer.getchannel("A")
    alpha_matches = ImageChops.difference(alpha, mask).getbbox() is None
    transparent_present = alpha.getextrema()[0] == 0
    positive = mask.point(lambda value: 255 if value else 0)
    core = mask.point(lambda value: 255 if value == 255 else 0)
    extracted = _metric(ImageChops.difference(original.convert("RGB"), layer.convert("RGB")), core, config["qa"]["percentile"])
    comparison = compare_regions(original, Image.alpha_composite(clean, layer), mask, config)
    return {"id": recipe["id"], "qa_kind": recipe.get("qa_kind", "art"),
            "geometry_passed": comparison["passed"] and alpha_matches and transparent_present and extracted["max_error"] == 0,
            "art_passed": False, "visual_review": "not_evaluated", "regions": comparison["regions"],
            "bounds": comparison["bounds"], "alpha_matches_mask": alpha_matches,
            "has_transparent_pixels": transparent_present, "extracted_pixels": extracted,
            "inputs": {field: {"path": recipe[field], "sha256": sha256(safe_path(workspace, recipe[field]))}
                       for field in images}}


def qa_recomposition(workspace, spec, config=None):
    config = config or load_config()
    _validate_recomposition(workspace, spec)
    original = read_image(safe_path(workspace, spec["original_path"], must_exist=True), "RGBA")
    rebuilt = read_image(safe_path(workspace, spec["base_path"], must_exist=True), "RGBA")
    _require(original.size == rebuilt.size, "recomposition base size mismatch")
    combined = Image.new("RGBA", original.size, (0, 0, 0, 0))
    inputs = [spec["original_path"], spec["base_path"]]
    for layer in sorted(spec["layers"], key=lambda value: value["z_index"]):
        image = read_image(safe_path(workspace, layer["path"], must_exist=True), "RGBA")
        _require(image.size == original.size, "recomposition layer size mismatch")
        rebuilt = Image.alpha_composite(rebuilt, image)
        combined = Image.alpha_composite(combined, image)
        inputs.append(layer["path"])
    comparison = compare_regions(original, rebuilt, combined.getchannel("A"), config)
    return {"id": spec["id"], "qa_kind": spec["qa_kind"], "geometry_passed": comparison["passed"],
            "art_passed": False, "visual_review": "not_evaluated", "regions": comparison["regions"],
            "bounds": comparison["bounds"], "inputs": [{"path": path, "sha256": sha256(safe_path(workspace, path))} for path in inputs]}


def validate_import_map(workspace, value, recipe_ids):
    _require(isinstance(value, dict) and value.get("version") == 1 and isinstance(value.get("outputs"), dict), "invalid import map")
    for recipe_id, entry in value["outputs"].items():
        _require(recipe_id in recipe_ids, "unknown import recipe id: " + recipe_id)
        _require(isinstance(entry, dict), "import output must be an object")
        safe_path(workspace, entry.get("path"), must_exist=True)
        _require(entry.get("status") in load_config()["statuses"], "invalid import status")
        if "generator" in entry:
            _require(isinstance(entry["generator"], str) and entry["generator"], "invalid import generator")
    return value


def validate_receipt(workspace, receipt, config=None):
    """Validate emitted JSON against the actual files, including encoded bytes."""
    config = config or load_config()
    _require(isinstance(receipt, dict) and receipt.get("version") == 1, "invalid pipeline receipt")
    _require(receipt.get("status") in config["statuses"] and receipt.get("manifest_modified") is False, "invalid receipt status")
    _require(receipt.get("art_passed") is False and receipt.get("visual_review") == "not_evaluated", "offline receipt cannot approve art")
    validate_manifest(workspace, {"round2_art": receipt.get("round2_art")}, config)
    records = receipt.get("imports")
    _require(isinstance(records, list) and isinstance(receipt.get("runtime_copies"), list), "invalid import records")
    by_runtime = {}
    for record in records:
        _require(isinstance(record, dict), "invalid import record")
        for prefix, field in (("source", "source_path"), ("runtime", "runtime_path")):
            path = safe_path(workspace, record.get(field), must_exist=True)
            _require(record.get(prefix + "_sha256") == sha256(path), prefix + " sha256 mismatch")
            with Image.open(path) as image:
                _require(record.get(prefix + "_size") == list(image.size), prefix + " size mismatch")
        transform = record.get("transform", {})
        _require(transform.get("method") == "equal_aspect_cover" and transform.get("filter") == "Lanczos", "invalid runtime transform")
        _require(record["runtime_size"] == config["runtime_size"] and _number(transform.get("scale"), 0.000001, float("inf")), "invalid runtime geometry")
        _require(isinstance(transform.get("source_crop"), list) and len(transform["source_crop"]) == 4 and
                 all(_number(v, 0, max(record["source_size"])) for v in transform["source_crop"]), "invalid source crop")
        _require(record["runtime_path"] not in by_runtime, "duplicate runtime import")
        by_runtime[record["runtime_path"]] = record
    _require(len(receipt["runtime_copies"]) == len(records), "missing runtime copies")
    for record in receipt["runtime_copies"]:
        imported = by_runtime.get(record.get("path"))
        _require(imported is not None, "runtime copy has no imported source")
        _require(record.get("sha256") == imported["runtime_sha256"] and record.get("source_sha256") == imported["source_sha256"], "runtime copy sha256 mismatch")
        _require(record.get("native_size") == imported["source_size"] and record.get("runtime_size") == imported["runtime_size"], "runtime copy size mismatch")
        _require(record.get("scale_x") == record.get("scale_y") == imported["transform"]["scale"] and record.get("transform") == imported["transform"], "runtime copy transform mismatch")
    for field in ("single_layer_qa", "recomposition_qa"):
        _require(isinstance(receipt.get(field), list), "invalid QA records")
        for record in receipt[field]:
            _require(type(record.get("geometry_passed")) is bool and record.get("art_passed") is False and
                     record.get("visual_review") == "not_evaluated", "invalid QA approval claims")
            for name in ("core", "feather", "inpaint_ring", "unedited"):
                region = record.get("regions", {}).get(name, {})
                _require(_integer(region.get("pixels")) and _integer(region.get("samples")) and
                         all(_number(region.get(key)) for key in ("mae", "p95", "max_error")), "invalid QA region metrics")
    pending = receipt.get("pending_qa", [])
    _require(isinstance(pending, list), "invalid pending QA records")
    _require(not pending or receipt.get("geometry_passed") is not True, "pending QA cannot pass geometry")
    for record in pending:
        _require(isinstance(record, dict) and record.get("kind") in ("single_layer", "recomposition") and
                 isinstance(record.get("missing_paths"), list) and record["missing_paths"], "invalid pending QA record")
        for path in record["missing_paths"]:
            safe_path(workspace, path)
    return receipt


def run_pipeline(workspace, manifest, style, only, *, import_map=None, config=None):
    config = config or load_config()
    queue = build_queue(workspace, manifest, style, only, config)
    section = copy.deepcopy(manifest["round2_art"])
    selected = [recipe for recipe in section["recipes"] if only == "all" or recipe["group"] == only]
    by_id = {recipe["id"]: recipe for recipe in selected}
    artifacts = {record["id"]: record for record in section.get("artifacts", [])}
    jobs = {task["recipe_id"]: task for task in queue["tasks"]}
    for recipe in selected:
        if recipe["id"] not in jobs:
            offline = next((task for task in queue["offline_tasks"] if task["recipe_id"] == recipe["id"]), None)
            jobs[recipe["id"]] = offline or {"recipe_id": recipe["id"], "source_destination": recipe["source_path"], "depends_on": []}
        else:
            _require(jobs[recipe["id"]]["source_destination"] == recipe["source_path"], "task id collides with recipe id")

    def exists(path):
        return safe_path(workspace, path).is_file()

    def remember(identifier, path, status, *, generator=None, task=None):
        file = safe_path(workspace, path, must_exist=True)
        image = read_image(file)
        record = copy.deepcopy(artifacts.get(identifier, {}))
        record.update(id=identifier, path=path, status=status, sha256=sha256(file), source_size=list(image.size),
                      style_reference=queue["active_style"]["path"], style_sha256=queue["active_style"]["sha256"])
        if generator:
            record["generator"] = generator
        if task:
            record["operation"] = task.get("operation", "generate")
            record["input_paths"] = list(task.get("depends_on", []))
            if "arguments" in task and "prompt" in task["arguments"]:
                record["prompt"] = task["arguments"]["prompt"]
        artifacts[identifier] = record

    if import_map is not None:
        validate_import_map(workspace, import_map, set(jobs))
    entries = {} if import_map is None else import_map["outputs"]
    # Complete preflight precedes every write, including automatic mask output.
    payloads = {}
    for identifier, entry in entries.items():
        source = safe_path(workspace, entry["path"], must_exist=True)
        read_image(source)
        target = safe_path(workspace, jobs[identifier]["source_destination"])
        data = source.read_bytes()
        if target.exists() and (not target.is_file() or target.read_bytes() != data):
            raise FileExistsError("existing output is never overwritten: " + str(target))
        payloads[identifier] = data
    # Topologically schedule imported and deterministic outputs. Declared future
    # destinations are dependencies, never silently treated as old references.
    available, scheduled, remaining = set(), [], list(entries)
    while remaining:
        progress = True
        while progress:
            progress = False
            for task in queue["offline_tasks"]:
                destination = task["source_destination"]
                if destination not in available and all(exists(path) or path in available for path in task.get("depends_on", [])):
                    available.add(destination)
                    progress = True
        ready = [identifier for identifier in remaining if all(exists(path) or path in available for path in jobs[identifier].get("depends_on", []))]
        _require(ready, "unresolved import dependencies: " + ", ".join(remaining))
        for identifier in ready:
            scheduled.append(identifier)
            available.add(jobs[identifier]["source_destination"])
            remaining.remove(identifier)

    def execute_offline():
        for task in queue["offline_tasks"]:
            destination = task["source_destination"]
            if exists(destination) or not all(exists(path) for path in task.get("depends_on", [])):
                continue
            if task["operation"] == "prepare_inpaint_target":
                prepare_inpaint_target(workspace, task["mask_path"], destination, config)
                remember(task["recipe_id"], destination, "complete", generator="deterministic_mask", task=task)
            elif task["operation"] == "extract_layer":
                arguments = task["arguments"]
                extract_layer(workspace, arguments["original_path"], arguments["mask_path"], destination)
                dependencies = [record for record in artifacts.values() if record["path"] in task["depends_on"]]
                recipe = by_id[task["recipe_id"]]
                status = "complete" if dependencies and all(record["status"] == "complete" for record in dependencies) else recipe["status"]
                recipe.update(status=status, generator="deterministic_extraction")
                remember(task["recipe_id"], destination, status, generator="deterministic_extraction", task=task)

    execute_offline()
    for identifier in scheduled:
        task, entry = jobs[identifier], entries[identifier]
        _require(all(exists(path) for path in task.get("depends_on", [])), "missing import dependency: " + identifier)
        _write_new(safe_path(workspace, task["source_destination"]), payloads[identifier])
        remember(identifier, task["source_destination"], entry["status"], generator=entry.get("generator"), task=task)
        if identifier in by_id:
            by_id[identifier]["status"] = entry["status"]
            if "generator" in entry:
                by_id[identifier]["generator"] = entry["generator"]
        execute_offline()

    imports, single_qa, whole_qa, missing, pending_qa = [], [], [], [], []
    for recipe in selected:
        if exists(recipe["source_path"]):
            imported = import_recipe(workspace, recipe, config)
            imports.append(imported)
            recipe.update(imported)
        else:
            missing.append({"id": recipe["id"], "status": recipe["status"], "source_path": recipe["source_path"]})
        if "mask_path" in recipe:
            absent = [recipe[field] for field in ("source_path", "original_path", "mask_path", "cleanplate_path") if not exists(recipe[field])]
            if absent:
                pending_qa.append({"id": recipe["id"], "kind": "single_layer", "missing_paths": absent})
            else:
                single_qa.append(qa_recipe(workspace, recipe, config))
    selected_paths = {recipe["source_path"] for recipe in selected}
    for spec in section["recompositions"]:
        if only == "all" or spec["base_path"] in selected_paths or any(layer["path"] in selected_paths for layer in spec["layers"]):
            absent = [path for path in [spec["original_path"], spec["base_path"], *[layer["path"] for layer in spec["layers"]]] if not exists(path)]
            if absent:
                pending_qa.append({"id": spec["id"], "kind": "recomposition", "missing_paths": absent})
            else:
                whole_qa.append(qa_recomposition(workspace, spec, config))
    for identifier, task in jobs.items():
        destination = task["source_destination"]
        if exists(destination) and identifier not in artifacts:
            owner = by_id.get(identifier, by_id.get(task.get("owner_recipe_id"), {}))
            remember(identifier, destination, owner.get("status", "needs_builtin_generation"), generator=owner.get("generator"), task=task)
    section.update(active_style=queue["active_style"], artifacts=list(artifacts.values()), art_passed=False)
    queue = build_queue(workspace, {"round2_art": section}, style, only, config)
    runtime_copies = [{"path": record["runtime_path"], "source_path": record["source_path"],
                       "native_size": record["source_size"], "runtime_size": record["runtime_size"],
                       "scale_x": record["transform"]["scale"], "scale_y": record["transform"]["scale"],
                       "method": "equal-aspect cover crop, Lanczos runtime copy",
                       "sha256": record["runtime_sha256"], "source_sha256": record["source_sha256"],
                       "transform": record["transform"], "status": record["status"], "origin": record["origin"],
                       "native_resolution_met": record["native_resolution_met"]} for record in imports]
    evaluated = single_qa + whole_qa
    geometry = False if any(not item["geometry_passed"] for item in evaluated) else None if pending_qa or not evaluated else True
    receipt = {"version": 1, "status": "needs_builtin_generation" if missing or pending_qa else queue["status"], "queue": queue, "imports": imports, "runtime_copies": runtime_copies,
            "single_layer_qa": single_qa, "recomposition_qa": whole_qa, "missing_sources": missing,
            "pending_qa": pending_qa, "geometry_passed": geometry,
            "art_passed": False, "visual_review": "not_evaluated", "manifest_modified": False,
            "round2_art": section}
    return validate_receipt(workspace, receipt, config)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--manifest", default="assets/ART_ASSET_MANIFEST.json")
    parser.add_argument("--style")
    parser.add_argument("--only")
    parser.add_argument("--output", default=".tools/art/regen_receipt.json")
    parser.add_argument("--import-map")
    helpers = parser.add_mutually_exclusive_group()
    helpers.add_argument("--prepare-masks", nargs=3, metavar=("HARD", "FEATHER", "INPAINT"))
    helpers.add_argument("--extract-layer", nargs=3, metavar=("ORIGINAL", "MASK", "OUTPUT"))
    helpers.add_argument("--prepare-inpaint-target", nargs=2, metavar=("SOFT", "OUTPUT"))
    args = parser.parse_args(argv)
    try:
        workspace = Path(args.workspace).resolve()
        if args.prepare_masks or args.extract_layer or args.prepare_inpaint_target:
            if args.prepare_masks:
                result = prepare_masks(workspace, *args.prepare_masks)
            elif args.extract_layer:
                result = extract_layer(workspace, *args.extract_layer)
            else:
                result = prepare_inpaint_target(workspace, *args.prepare_inpaint_target)
            print(json.dumps(result, ensure_ascii=False))
            return 0
        _require(args.style and args.only, "--style and --only are required for recipe processing")
        manifest = read_json(safe_path(workspace, args.manifest, must_exist=True))
        import_map = read_json(safe_path(workspace, args.import_map, must_exist=True)) if args.import_map else None
        output = safe_path(workspace, args.output)
        receipt = run_pipeline(workspace, manifest, args.style, args.only, import_map=import_map)
        _write_new(output, (json.dumps(receipt, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8"))
        print(json.dumps({"status": receipt["status"], "tasks": len(receipt["queue"]["tasks"]),
                          "imports": len(receipt["imports"]), "geometry_passed": receipt["geometry_passed"],
                          "art_passed": False, "receipt": args.output}, ensure_ascii=False))
        return 0 if receipt["geometry_passed"] is not False else 2
    except (ValueError, OSError, KeyError, TypeError) as error:
        print("Art pipeline validation failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
