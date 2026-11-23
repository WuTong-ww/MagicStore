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
import importlib.util
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


def _retired_compact_path(path):
    lower = path.casefold()
    return lower.startswith(("assets/_incoming/", "assets/generated_scenes/v3_real/",
                             "assets/generated_scenes/runtime/v3/", "assets/generated_scenes/runtime/v3_real/"))


PORTRAIT_SHARED_FIELDS = frozenset({
    "group", "art_pack", "operation", "category", "processing_script", "local_config",
    "processing_config_digest", "inputs", "mask_path", "mask_sha256",
})


def expand_compact_metadata(manifest):
    """Resolve lossless shared provenance; identities and prompts stay on each row.

    This table is in the tracked manifest, never in optional local audit files.
    Reject overlapping keys rather than choosing between two provenance claims.
    """
    result = copy.deepcopy(manifest)
    profiles = result.pop("asset_metadata_profiles", {})
    _require(isinstance(profiles, dict), "asset metadata profiles must be an object")
    for key, value in profiles.items():
        _require(isinstance(key, str) and re.fullmatch(r"A4_[a-f0-9]{12}", key) and
                 isinstance(value, dict) and bool(value) and set(value) <= PORTRAIT_SHARED_FIELDS and
                 value.get("group") == "portraits" and value.get("art_pack") == "A4_v3",
                 "invalid shared portrait metadata profile")
    for row in result.get("assets", []):
        _require(isinstance(row, dict), "invalid compact asset")
        if "metadata_profile" not in row:
            continue
        key = row.pop("metadata_profile")
        _require(isinstance(key, str) and key in profiles, "missing asset metadata profile")
        shared = profiles[key]
        _require(not set(row).intersection(shared), "asset metadata profile overlaps explicit provenance")
        row.update(copy.deepcopy(shared))
    return result


def compact_portrait_metadata(manifest):
    """Deduplicate only identical A4 provenance, preserving every other old row."""
    result = expand_compact_metadata(manifest)
    groups = {}
    for row in result.get("assets", []):
        if row.get("group") != "portraits" or row.get("art_pack") != "A4_v3":
            continue
        shared = {key: row[key] for key in sorted(PORTRAIT_SHARED_FIELDS) if key in row}
        encoded = json.dumps(shared, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        groups.setdefault(encoded, []).append(row)
    profiles = {}
    for encoded, rows in groups.items():
        if len(rows) < 2:
            continue
        key = "A4_" + hashlib.sha256(encoded.encode("utf-8")).hexdigest()[:12]
        shared = json.loads(encoded)
        _require(key not in profiles or profiles[key] == shared, "shared metadata profile hash collision")
        profiles[key] = shared
        for row in rows:
            for field in shared:
                row.pop(field)
            row["metadata_profile"] = key
    if profiles:
        result["asset_metadata_profiles"] = profiles
    return result


def exact_item_prompt(row, profile):
    """Recover the actual reviewed item prompt, including later corrections."""
    key, params = row.get("prompt_template"), row.get("prompt_params")
    templates = profile.get("templates", {})
    template = templates.get(key) if isinstance(templates, dict) and isinstance(key, str) else None
    _require(isinstance(template, str) and "{object}" in template and isinstance(params, dict) and
             all(isinstance(k, str) and isinstance(v, str) for k, v in params.items()) and "object" not in params,
             "item requires its exact formal prompt recipe")
    expected = row.get("actual_prompt_sha256")
    _require(isinstance(expected, str) and re.fullmatch(r"[a-fA-F0-9]{64}", expected), "missing item prompt SHA256")
    try:
        prompt = template.format(object=row["object_description"], **params)
    except (KeyError, IndexError, TypeError, ValueError) as error:
        raise ValueError("item prompt recipe cannot render its exact parameters") from error
    _require(hashlib.sha256(prompt.encode("utf-8")).hexdigest() == expected.lower(), "item prompt recipe SHA mismatch")
    return prompt


def validate_compact_manifest(workspace, manifest):
    """Validate metadata, not the optional retired audit or absent style draft."""
    _require(type(manifest.get("schema_version")) is int and manifest["schema_version"] == 3,
             "compact manifest schema_version must be 3")
    _require("round2_art" not in manifest, "compact manifest cannot inline retired round2_art")
    profiles = manifest.get("style_profiles", {})
    _require(isinstance(profiles, dict) and isinstance(profiles.get("v3", {}), dict), "invalid v3 style profile")
    assets = expand_compact_metadata(manifest).get("assets")
    _require(isinstance(assets, list), "compact assets must be an array")
    paths, item_ids = set(), set()
    for asset in assets:
        _require(isinstance(asset, dict), "invalid compact asset")
        path = asset.get("path")
        safe_path(workspace, path)
        _require(path.casefold() not in paths, "duplicate compact asset path")
        paths.add(path.casefold())
        _require(isinstance(asset.get("sha256"), str) and re.fullmatch(r"[a-fA-F0-9]{64}", asset["sha256"]),
                 "invalid compact asset sha256")
        if "dim" in asset:
            _require(isinstance(asset["dim"], list) and len(asset["dim"]) == 2 and
                     all(_integer(n, 1) for n in asset["dim"]), "invalid compact asset dimensions")
        if "inputs" in asset:
            _require(isinstance(asset["inputs"], list), "compact asset inputs must be an array")
            for input_path in asset["inputs"]:
                safe_path(workspace, input_path)
        if asset.get("group") == "scenes" and PurePosixPath(path).name == "C.png":
            scene, period = asset.get("scene_id"), asset.get("period")
            _require(isinstance(scene, str) and re.fullmatch(r"S\d{2}", scene) and period in ("day", "night", "closed"),
                     "native C requires complete formal scene identity metadata")
            _require(scene != "S04" or asset.get("state") in ("open", "closed"), "S04 native C requires an open/closed state")
        if "regeneration_constraints" in asset:
            _require(isinstance(asset["regeneration_constraints"], str) and asset["regeneration_constraints"].strip(),
                     "regeneration_constraints must be nonempty text")
        if asset.get("group") == "slices":
            _require(asset.get("operation") in ("extract_layer", "inpaint_cleanplate"), "unsupported formal slice operation")
        if path.startswith("assets/portraits/v3/") or asset.get("art_pack") == "A4_v3":
            _require(asset.get("group") == "portraits" and asset.get("art_pack") == "A4_v3" and
                     asset.get("operation") in ("portrait_part", "portrait_mannequin"), "A4 portrait requires explicit pack/group/operation")
            _require(asset.get("local_config") == "data/art/portrait_pipeline.json" and
                     asset.get("processing_script") == "tools/art/portrait_pipeline.py", "A4 portrait processing contract mismatch")
            _require(isinstance(asset.get("portrait_asset_id"), str) and asset["portrait_asset_id"] and
                     asset.get("dim") == [768, 1024], "A4 portrait identity/canvas missing")
        if asset.get("group") == "items":
            item_id = asset.get("item_id")
            _require(asset.get("operation") == "item_chromakey", "unsupported formal item operation")
            _require(isinstance(item_id, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", item_id) and
                     item_id not in item_ids, "invalid or duplicate item_id")
            item_ids.add(item_id)
            _require(isinstance(asset.get("object_description"), str) and asset["object_description"].strip(), "missing object_description")
            for field in ("source_raw", "processing_script", "local_config"):
                safe_path(workspace, asset.get(field))
            _require(isinstance(asset.get("source_raw_sha256"), str) and re.fullmatch(r"[a-fA-F0-9]{64}", asset["source_raw_sha256"]), "invalid item raw sha256")
            size = asset.get("source_raw_native_size")
            _require(isinstance(size, list) and len(size) == 2 and all(_integer(n, 1) for n in size), "invalid item raw native size")
            if "prompt_template" in asset:
                exact_item_prompt(asset, profiles.get("v3", {}))
        if asset.get("group") == "slices" and asset.get("operation") in ("extract_layer", "inpaint_cleanplate"):
            for field in ("composite_source", "processing_script", "local_spec", "local_config", "mask_path",
                          "inpaint_mask_path", "source_receipt"):
                if field in asset:
                    safe_path(workspace, asset[field])
    copies = manifest.get("runtime_copies", [])
    _require(isinstance(copies, list), "compact runtime_copies must be an array")
    for row in copies:
        _require(isinstance(row, dict), "invalid compact runtime copy")
        safe_path(workspace, row.get("path"))
        safe_path(workspace, row.get("source_path"))
    return manifest


def _compact_resources(manifest):
    assets = {row["path"]: row for row in expand_compact_metadata(manifest)["assets"]}
    aliases = {}
    for row in manifest.get("runtime_copies", []):
        target = assets.get(row["path"], {})
        if target.get("operation") == "item_chromakey":
            _require(row["source_path"] == target["source_raw"], "item processing raw source mismatch")
            continue  # Chromakey raw->256 is processing provenance, not an alias.
        _require(row["path"] not in aliases or aliases[row["path"]] == row["source_path"], "conflicting runtime source")
        aliases[row["path"]] = row["source_path"]
    for row in assets.values():
        if row["path"].startswith("assets/generated_scenes/runtime/") and len(row.get("inputs", [])) == 1:
            source = row["inputs"][0]
            _require(row["path"] not in aliases or aliases[row["path"]] == source, "runtime inputs conflict with source")
            aliases[row["path"]] = source

    def original(path):
        visited = set()
        while path in aliases:
            _require(path not in visited, "compact runtime source cycle")
            visited.add(path)
            path = aliases[path]
        return path

    for path in aliases:
        original(path)
    resources = {}
    rejected = {"candidate", "retired", "rejected", "rejected_style_v2", "placeholder", "pending"}
    for path in assets:
        source = original(path)
        _require(source in assets, "runtime source is absent from compact assets: " + source)
        row = assets[source]
        state = row.get("status", "fallback")
        generator = row.get("source", {}).get("generator", "") if isinstance(row.get("source", {}), dict) else ""
        if state in rejected or generator == "procedural_placeholder" or _retired_compact_path(source):
            continue
        name = PurePosixPath(source).name
        if not source.endswith(".png") or "candidate" in name.casefold() or "reference_sheet" in name.casefold():
            continue
        group = row.get("group")
        if group is None:
            if source.startswith("assets/generated_scenes/v2/slices/"):
                group = "slices"
            elif re.fullmatch(r"assets/generated_scenes/v2/S\d{2}_(day|night|closed)\.png", source):
                group = "scenes"
            elif source.startswith("assets/items/") and "reference" not in name.casefold():
                group = "items"
            # Complete legacy NPC/past-life images are not modular A4 parts.
        if group == "portraits" and row.get("art_pack") != "A4_v3":
            continue
        if group in ("scenes", "slices", "items", "portraits"):
            _require(group != "items" or not name.endswith("_64.png"), "64 item icon requires its canonical 256 alias")
            resources[source] = (group, row)
    return resources, {path: original(path) for path in aliases}


def build_compact_queue(workspace, manifest, style, only, config=None):
    """Queue explicit v3 templates against canonical formal sources only."""
    config = config or load_config()
    validate_compact_manifest(workspace, manifest)
    _require(only in ("scenes", "slices", "items", "portraits", "all"), "unknown resource group: " + str(only))
    resources, aliases = _compact_resources(manifest)
    selected = {path: value for path, value in resources.items() if only == "all" or value[0] == only}
    portrait_rows = [row for group, row in selected.values() if group == "portraits"]
    selected = {path: value for path, value in selected.items() if value[0] != "portraits"}
    profile = manifest.get("style_profiles", {}).get("v3", {})
    queue = {"version": 1, "kind": "compact_builtin_queue", "style_profile": "v3", "requested_style": style,
             "status": "pending_style_reference", "tasks": [], "offline_tasks": [], "pending": [],
             "generation_performed": False, "manifest_modified": False, "art_passed": False,
             "canonical_resource_count": len(selected), "message": config["generation"]["not_callable_message"]}

    def pending(status, reason, **fields):
        return {**queue, "status": status, "pending": [{"reason": reason, **fields}], **fields}

    alias = style == "v3"
    if alias and profile.get("status") != "selected":
        return pending("pending_style_reference", "v3 profile has no selected final reference")
    reference = profile.get("reference", {}) if alias else {"path": relative_input(workspace, style)}
    _require(isinstance(reference, dict), "invalid selected v3 reference")
    path = reference.get("path")
    if not path:
        return pending("pending_style_reference", "v3 final reference path is not configured")
    file = safe_path(workspace, path)
    _require(not _retired_compact_path(path), "retired/candidate art cannot be the active v3 style reference")
    if alias:
        _require(isinstance(reference.get("sha256"), str) and re.fullmatch(r"[a-fA-F0-9]{64}", reference["sha256"]),
                 "selected v3 reference requires sha256")
    if not file.is_file():
        return pending("pending_style_reference", "selected v3 reference file is missing", missing_paths=[path])
    read_image(file)
    digest = sha256(file)
    if alias:
        _require(digest == reference["sha256"].lower(), "selected v3 reference sha256 mismatch")
    queue["active_style"] = {"path": path, "sha256": digest, "status": "selected",
                             "selection": "profile_alias" if alias else "explicit_path"}
    templates = profile.get("templates", {})
    _require(isinstance(templates, dict), "v3 templates must be an object")

    def processing(group, row):
        return group == "slices" and row.get("operation") in ("extract_layer", "inpaint_cleanplate")

    def scene_identity(source, row):
        if any(field in row for field in ("scene_id", "period", "state")):
            scene, period, state = row.get("scene_id"), row.get("period"), row.get("state")
            _require(isinstance(scene, str) and re.fullmatch(r"S\d{2}", scene) and
                     period in ("day", "night", "closed"), "invalid formal scene identity")
            _require(state is None or scene == "S04" and state in ("open", "closed"), "invalid formal scene state")
            _require(period != "closed" or scene == "S01", "closed period belongs to S01")
            return scene, period, state
        legacy = re.fullmatch(r"assets/generated_scenes/v2/(S\d{2})_(day|night|closed)\.png", source)
        return (legacy[1], legacy[2], None) if legacy else None

    def template_key(source, group, row):
        if group == "portraits":
            return "portrait"
        identity = scene_identity(source, row) if group == "scenes" else None
        return "item" if group == "items" else identity[1] if identity and identity[1] in ("night", "closed") else "edit"

    required = {template_key(source, group, row) for source, (group, row) in selected.items() if not processing(group, row)}
    missing = sorted(key for key in required if not isinstance(templates.get(key), str) or not templates[key].strip())
    if missing:
        return pending("pending_templates", "explicit v3 templates are missing", missing_templates=missing)
    revision = profile.get("revision", "style_" + digest[:12])
    _require(isinstance(revision, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", revision), "invalid v3 output revision")
    # An explicit new image gets a distinct revision even when a profile kept
    # its human revision label, so changing only -Style cannot reuse outputs.
    if not alias:
        revision += "_" + digest[:12]
    if only in ("portraits", "all"):
        portrait_config = "data/art/portrait_pipeline.json"
        catalog_path = "data/people/appearance_parts.json"
        missing_portrait = [p for p in (portrait_config, catalog_path) if not safe_path(workspace, p).is_file()]
        if missing_portrait and only == "portraits":
            return pending("pending_portrait_pipeline", "A4 configuration/catalog is missing; legacy portraits are excluded", missing_paths=missing_portrait)
        if not missing_portrait:
            spec = importlib.util.spec_from_file_location("magic_portrait_pipeline", Path(__file__).parent / "art/portrait_pipeline.py")
            portrait = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(portrait)
            values = portrait.load_config(safe_path(workspace, portrait_config), workspace)
            portrait_catalog = {row["id"]: row for row in portrait._selected(values, None)}
            previous_missing = set()
            portrait_prompts = {}
            for row in portrait_rows:
                asset_id = row["portrait_asset_id"]
                _require(asset_id in portrait_catalog, "unknown A4 portrait identity")
                slot = portrait_catalog[asset_id]
                _require(row["path"] == slot["formal_path"] and all(row.get(key) == slot[key] for key in ("part_id", "category", "mood")),
                         "A4 formal portrait identity differs from selected catalog")
                _require(row["operation"] == ("portrait_mannequin" if asset_id == "mannequin" else "portrait_part"), "A4 operation/identity mismatch")
                template_key, params = row.get("prompt_template"), row.get("prompt_params")
                template = profile.get("templates", {}).get(template_key) if isinstance(template_key, str) else None
                actual_sha = row.get("actual_prompt_sha256")
                _require(isinstance(template, str) and template.strip() and isinstance(params, dict) and
                         isinstance(actual_sha, str) and re.fullmatch(r"[a-fA-F0-9]{64}", actual_sha),
                         "A4 portrait requires its exact formal prompt recipe")
                try:
                    actual_prompt = template.format(**params)
                except (KeyError, IndexError, TypeError, ValueError) as error:
                    raise ValueError("A4 portrait prompt recipe cannot render its exact parameters") from error
                _require(hashlib.sha256(actual_prompt.encode("utf-8")).hexdigest() == actual_sha.lower(),
                         "A4 portrait prompt recipe SHA mismatch")
                portrait_prompts[asset_id] = (actual_prompt, template_key, params, actual_sha.lower())
                source_file = safe_path(workspace, row["path"])
                if not source_file.is_file():
                    previous_missing.add(asset_id)
                else:
                    _require(sha256(source_file) == row["sha256"].lower(), "A4 formal source sha256 mismatch")
                    _require(list(read_image(source_file).size) == row["dim"], "A4 formal source dimensions mismatch")
            ids = [row["portrait_asset_id"] for row in portrait_rows] or None
            portrait_queue = portrait.build_queue(workspace, revision, ids, path, values,
                                                   mask_revision=profile.get("revision", revision))
            previous_rows = {row["portrait_asset_id"]: row for row in portrait_rows}
            for task in portrait_queue["tasks"]:
                if task["id"] in previous_rows:
                    task["previous_source_path"] = previous_rows[task["id"]]["path"]
                    task["previous_source_sha256"] = previous_rows[task["id"]]["sha256"]
                    prompt, template_key, params, actual_sha = portrait_prompts[task["id"]]
                    task["arguments"]["prompt"] = prompt
                    task.update(template_key=template_key, prompt_parameters=copy.deepcopy(params),
                                prompt_sha256=actual_sha, prompt_origin="formal_manifest_exact_template")
                if task["id"] in previous_missing:
                    task["pending_reasons"].append("previous_source")
                    task.update(can_generate=False, ready=False, status="pending_previous_source")
            if portrait_queue["tasks"] and not any(task["can_generate"] for task in portrait_queue["tasks"]):
                portrait_queue["status"] = "pending_portrait_inputs"
            portrait_queue.update({"active_style":queue["active_style"],"style_profile":"v3","requested_style":style})
            if only == "portraits":
                return portrait_queue
            queue["tasks"].extend(portrait_queue["tasks"])
            queue["offline_tasks"].extend(portrait_queue["offline_tasks"])
            queue["portrait_status"] = portrait_queue["status"]
            queue["portrait_origin_audit"] = portrait_queue.get("origin_audit")
            queue["canonical_resource_count"] += len(portrait_queue["tasks"])
    processing_root = "assets/generated_scenes/v3_regen/" + revision

    def item_config(row):
        _require(row["local_config"] == "data/art/item_pipeline.json", "item CLI requires its registered local_config")
        values = read_json(safe_path(workspace, row["local_config"], must_exist=True))
        for field in ("source_root", "output_root"):
            safe_path(workspace, values.get(field))
        _require(values["source_root"].startswith("assets/_incoming/") and values["output_root"].startswith("assets/items/"), "invalid item output roots")
        _require(row["item_id"] in values["required_ids"], "unknown configured item_id")
        return values

    def destination(source):
        group, row = resources.get(source, (None, {}))
        if row.get("operation") == "item_chromakey":
            return item_config(row)["output_root"] + "/" + revision + "/" + row["item_id"] + ".png"
        if processing(group, row):
            composite = row.get("composite_source")
            _require(composite in resources and resources[composite][0] == "scenes",
                     "processing requires its canonical composite source")
            identity = scene_identity(composite, resources[composite][1])
            parts = PurePosixPath(source).parts
            _require(identity and source.startswith("assets/generated_scenes/") and identity[0] in parts,
                     "processing requires a formal scene path")
            return processing_root + "/" + "/".join(parts[parts.index(identity[0]):])
        return "assets/art_versions/v3/" + revision + "/" + source.removeprefix("assets/")

    for source, (group, row) in selected.items():
        source_file = safe_path(workspace, source, must_exist=True)
        image = read_image(source_file)
        _require(sha256(source_file) == row["sha256"].lower(), "formal source sha256 mismatch: " + source)
        _require("dim" in row and list(image.size) == row["dim"], "formal source dimensions mismatch: " + source)
        target = destination(source)
        if safe_path(workspace, target).exists():
            raise FileExistsError("versioned output already exists; select a new revision: " + target)
        edit_target = source
        dependencies = []
        if group == "items" and row.get("operation") == "item_chromakey":
            values = item_config(row)
            _require(row["dim"] == values["runtime_size"], "canonical item dimensions differ from processing config")
            old_raw = safe_path(workspace, row["source_raw"])
            missing_previous = [] if old_raw.is_file() else [row["source_raw"]]
            if old_raw.is_file():
                _require(sha256(old_raw) == row["source_raw_sha256"].lower(), "item raw sha256 mismatch")
                _require(list(read_image(old_raw).size) == row["source_raw_native_size"], "item raw native size mismatch")
            item_id = row["item_id"]
            raw = values["source_root"] + "/" + revision + "/" + item_id + "_source.png"
            icon = values["output_root"] + "/" + revision + "/" + item_id + "_64.png"
            generation_receipt = values["source_root"] + "/" + revision + "/generation_receipt.json"
            raw_exists = safe_path(workspace, raw).is_file()
            receipt_exists = safe_path(workspace, generation_receipt).is_file()
            script_exists = safe_path(workspace, row["processing_script"]).is_file()
            if raw_exists and receipt_exists:
                generation = read_json(safe_path(workspace, generation_receipt))
                _require(isinstance(generation, dict) and generation.get("style_reference") == path and
                         isinstance(generation.get("style_sha256"), str) and generation["style_sha256"].lower() == digest,
                         "item generation receipt must use the selected style")
                records = generation.get("records")
                _require(isinstance(records, list), "item generation receipt requires records")
                matches = [record for record in records if isinstance(record, dict) and record.get("id") == item_id]
                _require(len(matches) == 1 and matches[0].get("source_path") == raw,
                         "item generation receipt must select this item's new raw")
            prompt = exact_item_prompt(row, profile) if "prompt_template" in row else templates["item"].replace("{object}", row["object_description"])
            if "prompt_template" not in row and "{object}" not in templates["item"]:
                prompt += "\nObject: " + row["object_description"]
            prompt += "\n" + values["generation"]["target_size_prompt"]
            prompt += "\nThe input image is a style reference only. Generate the single described object; do not edit or reproduce the reference scene."
            queue["tasks"].append({"recipe_id": "A2R_" + item_id, "item_id": item_id, "group": "items", "version": revision,
                "status": "needs_builtin_generation", "operation": "generate", "tool": config["generation"]["tool"],
                "previous_source_path": source, "previous_source_sha256": row["sha256"], "previous_source_raw": row["source_raw"],
                "source_destination": raw, "processed_destination": target, "style_reference": path, "style_sha256": digest,
                "missing_previous_inputs": missing_previous, "depends_on": [], "missing_dependencies": [],
                "ready": not raw_exists, "can_generate": not raw_exists, "attempts_used": 0,
                "generation_receipt_destination": generation_receipt,
                "arguments": {"prompt": prompt, "referenced_image_paths": [str(file)], "transparent_background": False}})
            can_process = raw_exists and receipt_exists and script_exists
            command = ["python", row["processing_script"], "--workspace", str(Path(workspace).resolve()),
                       "--receipt", generation_receipt, "--revision", revision, "--only", item_id,
                       "--output-receipt", ".tools/art/a2r_v3/" + revision + "/" + item_id + "_processing.json"]
            queue["offline_tasks"].append({"operation": "item_chromakey", "item_id": item_id, "source_path": raw,
                "source_destination": target, "icon_destination": icon, "depends_on": [raw],
                "status": "needs_item_processing", "phase": "awaiting_raw_generation" if not raw_exists else
                    "awaiting_generation_receipt" if not receipt_exists else "ready_for_processing",
                "ready": can_process, "can_process": can_process, "processing_script": row["processing_script"],
                "local_config": row["local_config"], "generation_receipt": generation_receipt,
                "missing_paths": [p for p in (raw, generation_receipt, row["processing_script"]) if not safe_path(workspace, p).is_file()],
                "processing_validation": "CLI must verify the new receipt, raw bytes, dimensions, alpha and support; art approval remains separate.",
                "command_after_generation": command})
            continue
        if processing(group, row):
            composite = row["composite_source"]
            edit_target = destination(composite)
            fields = ("processing_script", "local_spec", "local_config", "mask_path", "inpaint_mask_path", "source_receipt")
            missing_paths = [row[field] for field in fields if field in row and not safe_path(workspace, row[field]).is_file()]
            command = ["python", row["processing_script"], "--workspace", str(Path(workspace).resolve()), "--spec", row["local_spec"]] if all(row.get(f) for f in ("processing_script", "local_spec")) else None
            if command and row.get("local_config"):
                command += ["--config", row["local_config"]]
            queue["offline_tasks"].append({"operation": row["operation"], "previous_source_path": source,
                "source_destination": target, "previous_composite_source": composite, "composite_source": edit_target,
                "depends_on": [edit_target], "missing_dependencies": [] if safe_path(workspace, edit_target).is_file() else [edit_target],
                "status": "needs_mask_review", "phase": "mask_review" if safe_path(workspace, edit_target).is_file() else "awaiting_composite",
                "ready": False, "can_process": False, "processing_script": row.get("processing_script"),
                "local_spec": row.get("local_spec"), "command_after_review": command, "missing_paths": missing_paths,
                "missing_metadata": [f for f in ("processing_script", "local_spec") if not row.get(f)],
                "processing_output_root": processing_root,
                "processing_runtime_root": "assets/generated_scenes/runtime/v3_regen/" + revision,
                "review_required": "新C就绪后重新确认原生轮廓、支点和1px/6px mask，更新本地spec的C/rawB与配置输出根，再执行已有CLI；旧mask或审计不能批准新画风，不保证生成器逐像素不变。"})
            continue
        identity = scene_identity(source, row) if group == "scenes" else None
        if identity and identity[1] in ("night", "closed"):
            previous_period = "day" if identity[1] == "night" else "night"
            matches = [p for p, (g, r) in selected.items() if g == "scenes" and
                       scene_identity(p, r) == (identity[0], previous_period, identity[2])]
            _require(len(matches) == 1, identity[1] + " regeneration requires its canonical " + previous_period + " source in the same scene/state")
            edit_target = destination(matches[0])
            dependencies.append(edit_target)
        references = list(dict.fromkeys([str(file), str(safe_path(workspace, edit_target))]))
        missing_dependencies = [p for p in dependencies if not safe_path(workspace, p).is_file()]
        key = template_key(source, group, row)
        prompt = templates[key] + "\nResource identity: " + PurePosixPath(source).stem
        prompt += "\nInput roles: first image is the selected v3 style reference; second image is the edit target."
        if group == "scenes" and "regeneration_constraints" in row:
            prompt += "\n" + row["regeneration_constraints"]
        queue["tasks"].append({"recipe_id": PurePosixPath(source).stem + "_" + hashlib.sha256(source.encode()).hexdigest()[:8],
            "group": group, "version": revision, "status": "needs_builtin_generation", "operation": "generate",
            "tool": config["generation"]["tool"], "previous_source_path": source, "previous_source_sha256": row["sha256"],
            "source_destination": target, "style_reference": path, "style_sha256": digest,
            "depends_on": dependencies, "missing_dependencies": missing_dependencies, "ready": not missing_dependencies,
            "can_generate": not missing_dependencies, "attempts_used": 0,
            "arguments": {"prompt": prompt, "referenced_image_paths": references, "transparent_background": group == "slices"}})
    for runtime, source in aliases.items():
        if source not in selected:
            continue
        native = destination(source)
        if resources[source][1].get("operation") == "item_chromakey":
            row = resources[source][1]
            values = item_config(row)
            target = values["output_root"] + "/" + revision + "/" + row["item_id"] + "_64.png"
            _require(manifest["assets"] and next(a for a in manifest["assets"] if a["path"] == runtime)["dim"] == values["icon_size"], "item alias must be the configured icon size")
            if safe_path(workspace, target).exists():
                raise FileExistsError("versioned item icon already exists; select a new revision: " + target)
            queue["offline_tasks"].append({"operation": "item_icon_derivation", "item_id": row["item_id"],
                "source_path": native, "runtime_path": target, "depends_on": [native],
                "runtime_size": values["icon_size"], "method": "Lanczos_with_contour_darkening",
                "processing_script": row["processing_script"], "performed_with": "item_chromakey", "can_process": False})
            continue
        target = destination(runtime)
        if processing(*resources[source]) and runtime == source.replace("assets/generated_scenes/", "assets/generated_scenes/runtime/", 1):
            target = native.replace("assets/generated_scenes/", "assets/generated_scenes/runtime/", 1)
        if safe_path(workspace, target).exists():
            raise FileExistsError("versioned runtime already exists; select a new revision: " + target)
        queue["offline_tasks"].append({"operation": "runtime_copy", "source_path": native,
                                       "runtime_path": target, "depends_on": [native]})
    queue["status"] = ("needs_builtin_generation" if queue["tasks"] else "needs_mask_review"
                       if any(task["operation"] != "runtime_copy" for task in queue["offline_tasks"]) else "no_matching_resources")
    return queue


def validate_manifest(workspace, manifest, config=None):
    config = config or load_config()
    _require(isinstance(manifest, dict), "manifest must be an object")
    if manifest.get("schema_version") == 3:
        return validate_compact_manifest(workspace, manifest)
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
    if manifest.get("schema_version") == 3:
        return build_compact_queue(workspace, manifest, style_path, only, config)
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
    if manifest.get("schema_version") == 3:
        _require(import_map is None, "compact manifests are queue-only; use an explicit work manifest for ImportMap")
        queue = build_compact_queue(workspace, manifest, style, only, config)
        return {"version": 1, "kind": "compact_art_queue_receipt", "status": queue["status"], "queue": queue,
                "imports": [], "runtime_copies": [], "geometry_passed": None, "art_passed": False,
                "generation_performed": False, "manifest_modified": False}
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
    parser.add_argument("--output", help="receipt path; compact queues default to an immutable versioned local file")
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
        compact = manifest.get("schema_version") == 3
        if not args.output and not compact:
            args.output = ".tools/art/regen_receipt.json"
        output = safe_path(workspace, args.output) if args.output else None
        if compact and args.output:
            _require(args.output.startswith(".tools/") and args.output.endswith(".json"),
                     "compact queue output must be a local .tools JSON, never a formal resource")
        receipt = run_pipeline(workspace, manifest, args.style, args.only, import_map=import_map)
        if output is None:
            identity = json.dumps({"manifest": manifest, "style": args.style, "only": args.only,
                                   "active_style": receipt["queue"].get("active_style")},
                                  sort_keys=True, ensure_ascii=True, allow_nan=False).encode("utf-8")
            args.output = ".tools/art/compact-queues/" + args.only + "_" + hashlib.sha256(identity).hexdigest()[:16] + ".json"
            output = safe_path(workspace, args.output)
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
