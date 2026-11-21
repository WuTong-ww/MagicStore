"""Validate real A1R evidence and write two immutable proposed JSON files.

No central manifest, production visuals, image bytes, or renderer is modified.
Example: python tools/art/register_real_scenes.py --output .tools/art/real-review-v1
The output directory contains proposed_manifest.json and scene_review.json.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline as pipeline
import real_scene_layers as real_layers

REGISTRY = "data/art/real_scene_registry.json"
SCENES = tuple(f"S{i:02}" for i in range(1, 8))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _finite_json(value):
    if isinstance(value, dict):
        return all(isinstance(key, str) and _finite_json(item) for key, item in value.items())
    if isinstance(value, list):
        return all(_finite_json(item) for item in value)
    return value is None or type(value) in (str, bool) or number(value)


def expected_slots():
    return {(scene, period, state) for scene in SCENES
            for period in (("day", "night", "closed") if scene == "S01" else ("day", "night"))
            for state in (("open", "closed") if scene == "S04" else (None,))}


def validate_registry(workspace, value):
    """Structural validation permits not-yet-produced receipts; build is strict."""
    require(isinstance(value, dict) and value.get("version") == 1 and
            value.get("kind") == "real_scene_registry", "invalid registry version or kind")
    require(value.get("preview_only") is True and value.get("art_passed") is False,
            "registry must remain preview_only with art_passed false")
    for field in ("manifest", "baseline", "style_reference"):
        pipeline.safe_path(workspace, value.get(field))
    digest = value.get("style_sha256")
    require(isinstance(digest, str) and len(digest) == 64 and
            all(char in "0123456789abcdefABCDEF" for char in digest), "invalid style sha256")
    generation = value.get("generation_receipts")
    require(isinstance(generation, list) and len(generation) == len(SCENES),
            "registry needs seven generation receipts")
    for path in generation:
        pipeline.safe_path(workspace, path)
    require(len({path.casefold() for path in generation}) == len(generation), "duplicate generation receipt")
    selected = value.get("selected_receipts")
    require(isinstance(selected, list) and len(selected) == len(expected_slots()),
            "registry needs exactly 17 complete scene/period/state receipts")
    slots, paths = set(), set()
    for entry in selected:
        require(isinstance(entry, dict), "selected receipt must be an object")
        slot = (entry.get("scene_id"), entry.get("period"), entry.get("state"))
        require(slot in expected_slots() and slot not in slots, "invalid or duplicate selected scene/period/state")
        slots.add(slot)
        pipeline.safe_path(workspace, entry.get("receipt_path"))
        require(entry["receipt_path"].casefold() not in paths, "duplicate selected receipt path")
        paths.add(entry["receipt_path"].casefold())
    require(slots == expected_slots(), "selected receipts are not complete")
    overrides = value.get("scene_overrides", {})
    require(isinstance(overrides, dict) and set(overrides).issubset(SCENES), "invalid scene_overrides")
    allowed = {"hotspots", "safe_rect", "seat_rect", "seat_scale", "seat_compact_rect", "seat_narrow_rect", "shelves", "notes"}
    for override in overrides.values():
        require(isinstance(override, dict) and set(override).issubset(allowed) and _finite_json(override),
                "scene_overrides must contain finite presentation data, not resource paths/layers")
    seats = value.get("seat_source_overrides", {})
    require(isinstance(seats, dict) and set(seats).issubset(SCENES), "invalid seat_source_overrides")
    for seat in seats.values():
        require(isinstance(seat, dict) and real_layers.size_valid(seat.get("native_size")), "invalid seat source native size")
        rect = seat.get("rect")
        require(isinstance(rect, list) and len(rect) == 4 and all(number(n) for n in rect) and
                rect[0] >= 0 and rect[1] >= 0 and rect[2] > 0 and rect[3] > 0 and
                rect[0] + rect[2] <= seat["native_size"][0] and rect[1] + rect[3] <= seat["native_size"][1],
                "invalid seat source rect")
        require(number(seat.get("scale", 1)) and seat.get("scale", 1) > 0, "invalid seat source scale")
    require(_finite_json(value), "registry contains nonfinite JSON")
    return value


def _deep_merge(first, second):
    result = copy.deepcopy(first)
    for key, value in second.items():
        result[key] = _deep_merge(result[key], value) if isinstance(value, dict) and isinstance(result.get(key), dict) else copy.deepcopy(value)
    return result


def _deduplicate(records, key):
    result = {}
    for record in records:
        require(isinstance(record, dict) and isinstance(record.get(key), str), "invalid merge record: " + key)
        result[record[key].casefold()] = copy.deepcopy(record)
    return list(result.values())


def _strict_qa(qa, bounds):
    require(isinstance(qa, dict) and qa.get("passed") is True and qa.get("bounds") == bounds, "strict QA/bounds did not pass")
    regions = qa.get("regions", {})
    for name in ("core", "feather", "inpaint_ring", "unedited"):
        region = regions.get(name)
        require(isinstance(region, dict) and all(number(region.get(key)) and region[key] >= 0
                for key in ("mae", "p95", "max_error")), "invalid QA region: " + name)
    for name, field in (("core", "core_max_error"), ("inpaint_ring", "inpaint_ring_max_error"), ("unedited", "unedited_max_error")):
        require(regions[name]["max_error"] <= bounds[field], "strict QA core/ring/unedited failure: " + name)
    require(regions["feather"]["mae"] <= bounds["feather_mae"] and
            regions["feather"]["p95"] <= bounds["feather_p95"], "strict QA feather failure")


def _transform_valid(transform, native, runtime):
    require(isinstance(transform, dict) and transform.get("method") == "equal_aspect_cover" and
            transform.get("filter") == "Lanczos", "invalid runtime transform")
    crop = transform.get("source_crop")
    require(isinstance(crop, list) and len(crop) == 4 and all(number(n) for n in crop) and
            0 <= crop[0] < crop[2] <= native[0] and 0 <= crop[1] < crop[3] <= native[1], "invalid source crop")
    scale = transform.get("scale")
    require(number(scale) and scale > 0 and transform.get("runtime_size") == runtime and
            math.isclose(scale, runtime[0] / (crop[2] - crop[0]), rel_tol=1e-7) and
            math.isclose(scale, runtime[1] / (crop[3] - crop[1]), rel_tol=1e-7), "runtime transform scale/size mismatch")
    require(transform.get("native_size", native) == native, "transform native size mismatch")


def _compact_preview(workspace, manifest, actual, selected, copies, generated_outputs):
    """Canonical metadata only; full recipes/ROI history stay in local JSONL."""
    proposed = copy.deepcopy(manifest)
    require(isinstance(proposed.get("assets"), list), "compact manifest requires canonical assets[]")
    assets = {}
    for row in proposed["assets"]:
        require(isinstance(row, dict) and isinstance(row.get("path"), str), "invalid compact asset")
        pipeline.safe_path(workspace, row["path"])
        require(row["path"].casefold() not in assets, "duplicate compact asset path")
        assets[row["path"].casefold()] = copy.deepcopy(row)
    descriptions, dependencies = {}, {}
    for selected_row in selected:
        receipt = selected_row["receipt"]
        spec = receipt["specification"]
        original, raw = spec["original_path"], spec["raw_cleanplate_path"]
        for path in (original, raw):
            digest = actual[pipeline.safe_path(workspace, path, must_exist=True)][0]
            record = generated_outputs[selected_row["entry"]["scene_id"]][digest]
            descriptions[path] = {"prompt": record["prompt"], "references": copy.deepcopy(record["ref_paths"])}
        for artifact in receipt["artifacts"]:
            if artifact["path"] not in (original, raw, spec["style_reference"]):
                dependencies[artifact["path"]] = [original, raw]
    for row in copies:
        dependencies[row["path"]] = [row["source_path"]]
    for file, (digest, size) in actual.items():
        path = file.relative_to(workspace).as_posix()
        key = path.casefold()
        current = assets.get(key, {})
        require(not current or current.get("sha256", "").lower() == digest and current.get("dim") == size,
                "compact registered path changed bytes/dimensions; use a new revision: " + path)
        asset = {**current, "path": path, "sha256": digest, "dim": list(size)}
        if path in descriptions: asset.update(descriptions[path])
        if path in dependencies: asset["inputs"] = dependencies[path]
        assets[key] = asset
    proposed["assets"] = sorted(assets.values(), key=lambda row: row["path"])
    proposed["runtime_copies"] = _deduplicate(proposed.get("runtime_copies", []) + copies, "path")
    proposed.pop("round2_art", None)
    proposed.update(preview_only=True, art_passed=False)
    size = len((json.dumps(proposed, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8"))
    require(size < 500000, "compact registration proposal exceeds 500000 bytes")
    return proposed


def build_proposals(workspace, registry, *, registry_path=None):
    workspace = Path(workspace).resolve()
    validate_registry(workspace, registry)
    protected, actual = set(), {}

    def input_path(path):
        resolved = pipeline.safe_path(workspace, path, must_exist=True)
        protected.add(resolved)
        return resolved

    def check_image(path, digest, size):
        resolved = input_path(path)
        if resolved not in actual:
            with Image.open(resolved) as image:
                dimensions = list(image.size)
                image.verify()
            actual[resolved] = (pipeline.sha256(resolved), dimensions)
        require(isinstance(digest, str) and digest.lower() == actual[resolved][0], "actual image sha256 mismatch: " + path)
        require(size == actual[resolved][1], "actual image size mismatch: " + path)
        return actual[resolved]

    manifest = pipeline.read_json(input_path(registry["manifest"]))
    baseline = pipeline.read_json(input_path(registry["baseline"]))
    require(isinstance(manifest, dict) and isinstance(baseline, dict) and isinstance(baseline.get("scenes"), dict), "invalid manifest/baseline")
    if registry_path is not None:
        input_path(registry_path)
    style_file = input_path(registry["style_reference"])
    with Image.open(style_file) as image:
        style_size = list(image.size)
    check_image(registry["style_reference"], registry["style_sha256"], style_size)
    generations, generation_scenes = [], set()
    generated_outputs = {scene: {} for scene in SCENES}
    for path in registry["generation_receipts"]:
        file = input_path(path)
        generation = pipeline.read_json(file)
        real_layers.validate_generation_receipt(workspace, generation)
        require(generation["scene_id"] not in generation_scenes, "duplicate generation scene identity")
        generation_scenes.add(generation["scene_id"])
        require(generation["style_reference"] == registry["style_reference"] and
                generation["style_sha256"].lower() == registry["style_sha256"].lower(), "generation style differs from registry")
        for record in generation["records"]:
            check_image(record["path"], record["sha256"], record["native_size"])
            for reference in record["ref_paths"]:
                input_path(reference)
            if record["status"] == "complete":
                generated_outputs[generation["scene_id"]][record["sha256"].lower()] = record
            for attempt in record["attempts"]:
                if attempt["status"] != "complete" or "output_path" not in attempt:
                    continue
                # Historical default-tool absolute paths may remain in logs;
                # only retained workspace outputs certify a processing source.
                try:
                    retained = pipeline.safe_path(workspace, attempt["output_path"])
                except ValueError:
                    continue
                require(retained.is_file(), "retained successful generation attempt is missing")
                with Image.open(retained) as image:
                    native = list(image.size)
                digest = pipeline.sha256(retained)
                check_image(attempt["output_path"], attempt.get("sha256", digest), attempt.get("native_size", native))
                prompt = attempt.get("prompt", record["prompt"])
                references = attempt.get("ref_paths", record["ref_paths"])
                require(isinstance(prompt, str) and prompt.strip(), "retained generation attempt prompt must be nonempty text")
                require(isinstance(references, list) and all(isinstance(ref, str) for ref in references),
                        "retained generation attempt references must be an array of paths")
                for reference in references:
                    pipeline.read_image(input_path(reference))
                generated_outputs[generation["scene_id"]][digest] = {**record, "path": attempt["output_path"],
                    "sha256": digest, "native_size": native, "attempt": attempt["attempt"],
                    "prompt": prompt, "ref_paths": copy.deepcopy(references)}
        generations.append({"path": path, "sha256": pipeline.sha256(file), "scene_id": generation["scene_id"]})
    require(generation_scenes == set(SCENES), "seven generation scenes are not complete")
    bounds = pipeline.load_config()["qa"]
    selected, all_copies, all_recipes, all_recompositions, real_sources, completed_artifacts = [], [], [], [], [], []
    for entry in registry["selected_receipts"]:
        file = input_path(entry["receipt_path"])
        receipt = pipeline.read_json(file)
        require(isinstance(receipt, dict) and receipt.get("version") == 1 and receipt.get("kind") == "real_pixel_extraction", "invalid real scene receipt")
        require((receipt.get("scene_id"), receipt.get("period"), receipt.get("state")) ==
                (entry["scene_id"], entry["period"], entry.get("state")), "receipt scene/period/state identity mismatch")
        require(receipt.get("geometry_passed") is True and receipt.get("art_passed") is False, "receipt geometry failed or art approval is unsupported")
        _strict_qa(receipt.get("recomposition_qa"), bounds)
        require(isinstance(receipt.get("inputs"), dict) and isinstance(receipt.get("artifacts"), list) and
                isinstance(receipt.get("runtime_copies"), list) and isinstance(receipt.get("layers"), list) and receipt["layers"], "missing real scene evidence")
        for record in list(receipt["inputs"].values()) + receipt["artifacts"]:
            check_image(record["path"], record["sha256"], record["native_size"])
        style = receipt["inputs"].get("style", {})
        require(style.get("path") == registry["style_reference"] and style.get("sha256", "").lower() == registry["style_sha256"].lower(), "receipt style differs from registry")
        specification = receipt.get("specification")
        require(isinstance(specification, dict) and isinstance(specification.get("layers"), list), "missing source annotation")
        for field, role in (("original_path", "original"), ("raw_cleanplate_path", "raw_cleanplate")):
            source = receipt["inputs"][role]
            digest, _ = check_image(specification[field], source["sha256"], source["native_size"])
            require(digest in generated_outputs[entry["scene_id"]],
                    "processing source has no same-scene builtin generation provenance: " + specification[field])
        for row in receipt["layers"]:
            _strict_qa(row.get("single_layer_qa"), bounds)
        runtime_by_path = {}
        for record in receipt["runtime_copies"]:
            check_image(record["source_path"], record["source_sha256"], record["native_size"])
            check_image(record["path"], record["sha256"], record["runtime_size"])
            require(record["runtime_size"] == pipeline.load_config()["runtime_size"], "runtime size differs from configured target")
            _transform_valid(record.get("transform"), record["native_size"], record["runtime_size"])
            require(record.get("scale_x") == record.get("scale_y") == record["transform"]["scale"], "nonuniform runtime scale")
            runtime_by_path[record["path"]] = record
        fragment = receipt.get("scene_descriptors", {}).get(entry["scene_id"])
        require(isinstance(fragment, dict) and fragment.get("layer_format") == "aligned_full_canvas" and
                fragment.get(entry["period"]) == "res://" + receipt["base_runtime_path"] and
                receipt["base_runtime_path"] in runtime_by_path, "missing or unverified scene descriptor background")
        require(isinstance(fragment.get("layers"), dict), "missing scene descriptor layers")
        annotations = {row["id"]: row for row in specification["layers"]}
        actual_layers = {row["id"]: row for row in receipt["layers"]}
        require(set(fragment["layers"]) == set(annotations) == set(actual_layers), "descriptor layer IDs differ from source annotation")
        canvas = baseline.get("scene_settings", {}).get("canvas")
        for key, descriptor in fragment["layers"].items():
            require(isinstance(descriptor, dict) and descriptor.get("path", "").removeprefix("res://") in runtime_by_path,
                    "unverified layer descriptor path: " + key)
            require(descriptor.get("variants", {}).get(entry["period"]) == descriptor["path"], "descriptor variant does not match receipt")
            runtime_record = runtime_by_path[descriptor["path"].removeprefix("res://")]
            annotation, actual_layer = annotations[key], actual_layers[key]
            row_descriptor = actual_layer.get("descriptor")
            require(isinstance(row_descriptor, dict), "invalid processing row descriptor")
            # The common fragment only adds period lookups and door state.
            # Bind its complete descriptor back to the independently read row.
            expected_descriptor = copy.deepcopy(row_descriptor)
            expected_descriptor.setdefault("variants", {entry["period"]: row_descriptor.get("path")})
            expected_descriptor.setdefault("variant_transforms", {entry["period"]: row_descriptor.get("source_transform")})
            if entry.get("state") and key.startswith("door_"):
                expected_descriptor.setdefault("state", entry["state"])
            require(expected_descriptor == descriptor, "processing row descriptor differs from verified scene fragment")
            require(descriptor["path"].startswith("res://") and runtime_record["source_path"] == actual_layer["layer_path"],
                    "descriptor runtime source is not its verified layer")
            require(all(descriptor.get(field) == annotation[field] for field in ("pivot_px", "z_index", "motion")) and
                    descriptor.get("rect") == [0, 0, *canvas] and descriptor.get("hotspot") == [0, 0, *canvas],
                    "descriptor geometry/motion differs from its source annotation")
            require(set(descriptor.get("variants", {})) == {entry["period"]} and
                    set(descriptor.get("variant_transforms", {})) == {entry["period"]}, "descriptor contains unrelated period variants")
            expected_transform = {**runtime_record["transform"], "native_size": runtime_record["native_size"]}
            require(descriptor.get("native_size") == runtime_record["native_size"] and
                    descriptor.get("source_transform") == expected_transform and
                    descriptor.get("variant_transforms", {}).get(entry["period"]) == expected_transform,
                    "descriptor crop/transform differs from its verified runtime copy")
        # Recompute masks, mask-local B_i/B_all and every strict ROI from actual
        # retained pixels. Hashes and a declared successful flag are not enough.
        real_layers.validate_processing_receipt(workspace, receipt)
        # Registration fragments are also bound to the verified files. An
        # otherwise valid receipt cannot smuggle unrelated/escaping recipes.
        suffix = entry["period"] + ("_" + entry["state"] if "state" in entry else "")
        stem = entry["scene_id"] + "_" + suffix + "_" + receipt["revision"]
        recipe_by_source = {row["source_path"]: row for row in receipt.get("recipes", [])}
        expected_sources = {receipt["base_path"], *[row["layer_path"] for row in receipt["layers"]]}
        require(len(receipt.get("recipes", [])) == len(expected_sources) and set(recipe_by_source) == expected_sources,
                "recipe source paths differ from verified processing outputs")
        base_recipe = recipe_by_source[receipt["base_path"]]
        require(base_recipe.get("id") == stem + "_base" and base_recipe.get("group") == "scenes" and
                base_recipe.get("runtime_path") == receipt["base_runtime_path"], "base recipe differs from verified background")
        expected_composition = {"id": stem, "qa_kind": "art", "original_path": receipt["original_path"],
            "base_path": receipt["base_path"], "layers": [{"path": row["layer_path"], "z_index": row["z_index"]} for row in receipt["layers"]]}
        require(receipt.get("recompositions") == [expected_composition], "recomposition paths/order differ from actual processing")

        def completed(identifier, path, generator, prompt, input_paths):
            resolved = input_path(path)
            digest, dimensions = actual[resolved]
            completed_artifacts.append({"id": identifier, "path": path, "status": "complete", "sha256": digest,
                "source_size": dimensions, "generator": generator, "prompt": prompt, "input_paths": input_paths,
                "style_reference": registry["style_reference"], "style_sha256": registry["style_sha256"],
                "art_passed": False, "receipt_path": entry["receipt_path"]})

        original_digest = actual[input_path(receipt["original_path"])][0]
        generation_record = generated_outputs[entry["scene_id"]][original_digest]
        completed(stem + "__composite", receipt["original_path"], "builtin_imagegen",
                  specification["composite_prompt"], generation_record["ref_paths"])
        for row in receipt["layers"]:
            recipe = recipe_by_source[row["layer_path"]]
            require(recipe.get("id") == stem + "_" + row["id"] and recipe.get("group") == "layers" and
                    recipe.get("runtime_path") == row["descriptor"]["path"].removeprefix("res://") and
                    recipe.get("original_path") == receipt["original_path"] and recipe.get("mask_path") == row["soft_mask_path"] and
                    recipe.get("cleanplate_path") == row["cleanplate_path"] and recipe.get("processing_parameters") == specification,
                    "layer recipe provenance differs from actual processing")
            completed(recipe["id"] + "__cleanplate", row["cleanplate_path"], "builtin_assisted_C_pixel_processing",
                specification["cleanplate_prompt"] + "\nMask-local B_i is derived from the retained AI raw-B; it is not a separately generated image.",
                [specification["original_path"], specification["raw_cleanplate_path"], row["soft_mask_path"]])
        selected.append({"entry": copy.deepcopy(entry), "receipt": receipt, "sha256": pipeline.sha256(file)})
        all_copies.extend(receipt["runtime_copies"])
        # The processing receipt's base recipe describes an existing runtime
        # copy. Its cleanplate instructions must never become the C prompt.
        # Register C explicitly, then let base_specs supply C/masks to B_all.
        original_copies = [row for row in receipt["runtime_copies"] if row["source_path"] == receipt["original_path"]]
        require(len(original_copies) == 1, "complete C needs its verified runtime copy")
        composite_recipe = {**copy.deepcopy(base_recipe), "id": stem + "__composite", "operation": "generate",
            "prompt": specification["composite_prompt"], "source_path": receipt["original_path"],
            "runtime_path": original_copies[0]["path"], "reference_path": specification["original_path"],
            "generator": "builtin_imagegen"}
        registered_recipes = copy.deepcopy(receipt["recipes"])
        for recipe in registered_recipes:
            if recipe["source_path"] == receipt["base_path"]:
                recipe["operation"] = "generate"
        all_recipes.extend([composite_recipe, *registered_recipes])
        all_recompositions.extend(receipt.get("recompositions", []))
        real_sources.extend({**record, "receipt_path": entry["receipt_path"]} for record in receipt["artifacts"])

    review = copy.deepcopy(baseline)
    canvas = review.get("scene_settings", {}).get("canvas")
    require(real_layers.size_valid(canvas), "baseline logical canvas is invalid")
    slot = copy.deepcopy(review.get("scenes", {}).get("S04", {}).get("layers", {}).get("slot"))
    require(isinstance(slot, dict) and slot.get("legacy") is True and slot.get("display") == "cell", "baseline must retain explicit legacy S04 slot")
    for scene in SCENES:
        require(scene in review["scenes"], "baseline scene is missing: " + scene)
        review["scenes"][scene]["layers"] = {}
        review["scenes"][scene]["layer_format"] = "aligned_full_canvas"
    review["scenes"]["S04"]["layers"]["slot"] = slot
    period_order = {"day": 0, "night": 1, "closed": 2}
    selected.sort(key=lambda row: (row["entry"]["scene_id"], period_order[row["entry"]["period"]], row["entry"].get("state", "")))
    seat_transforms = {}
    for selected_row in selected:
        entry, receipt = selected_row["entry"], selected_row["receipt"]
        scene, period, state = entry["scene_id"], entry["period"], entry.get("state")
        target = review["scenes"][scene]
        fragment = receipt["scene_descriptors"][scene]
        if state:
            target.setdefault("state_backgrounds", {}).setdefault(state, {})[period] = fragment[period]
            if state == "open":
                target[period] = fragment[period]
        else:
            target[period] = fragment[period]
        for key, descriptor in fragment["layers"].items():
            descriptor = copy.deepcopy(descriptor)
            if state:
                if not key.startswith("door_"):
                    key += "_" + state
                descriptor["state"] = state
            current = target["layers"].get(key)
            if current is None:
                target["layers"][key] = descriptor
            else:
                require(current.get("state") == descriptor.get("state"), "layer state collision")
                for nested in ("variants", "variant_transforms"):
                    current[nested] = _deep_merge(current.get(nested, {}), descriptor.get(nested, {}))
            target["layers"][key]["path"] = target["layers"][key]["variants"].get("day", descriptor["path"])
        if period == "day" and scene not in seat_transforms:
            record = next(row for row in receipt["runtime_copies"] if row["path"] == receipt["base_runtime_path"])
            seat_transforms[scene] = record
    for scene in SCENES:
        for key, layer in review["scenes"][scene]["layers"].items():
            if not layer.get("legacy"):
                require(set(layer.get("variants", {})).issuperset({"day", "night"}), "incomplete day/night layer variants: " + scene + "/" + key)
    backgrounds = review["scenes"]["S04"].get("state_backgrounds", {})
    require(set(backgrounds) == {"open", "closed"} and all(set(row) == {"day", "night"} for row in backgrounds.values()), "S04 four state backgrounds are incomplete")
    require(len({path for row in backgrounds.values() for path in row.values()}) == 4, "S04 states must retain their four independent B_all paths")
    for scene, override in registry.get("scene_overrides", {}).items():
        review["scenes"][scene] = _deep_merge(review["scenes"][scene], override)
    for scene, seat in registry.get("seat_source_overrides", {}).items():
        source = seat_transforms[scene]
        require(source["native_size"] == seat["native_size"], "seat source size differs from actual scene")
        crop = source["transform"]["source_crop"]
        x, y, width, height = seat["rect"]
        review["scenes"][scene]["seat_rect"] = [(x - crop[0]) / (crop[2] - crop[0]) * canvas[0],
            (y - crop[1]) / (crop[3] - crop[1]) * canvas[1], width / (crop[2] - crop[0]) * canvas[0],
            height / (crop[3] - crop[1]) * canvas[1]]
        review["scenes"][scene]["seat_scale"] = seat.get("scale", 1)
    review.update(preview_only=True, art_passed=False, art_status="real_builtin_generated_partial",
                  source_receipts=[row["entry"]["receipt_path"] for row in selected],
                  generation_receipts=copy.deepcopy(registry["generation_receipts"]))
    review.pop("source_receipt", None)
    review.pop("local_audit_descriptor", None)

    proposed = copy.deepcopy(manifest)
    proposed["runtime_copies"] = _deduplicate(proposed.get("runtime_copies", []) + all_copies, "path")
    compact = manifest.get("schema_version") == 3
    # A compact formal manifest may carry only an external retired audit.
    # Never use that history's active_style/recipes as a new work default.
    section = {} if compact else proposed.setdefault("round2_art", {})
    if compact:
        proposed["round2_art"] = section
    old_recipes = copy.deepcopy(section.get("recipes", []))
    for recipe in old_recipes:
        if recipe.get("generator") == "procedural_placeholder" or recipe.get("qa_kind") == "geometry_only":
            group = recipe.get("group", "")
            recipe["group"] = group if group.startswith("engineering_") else "engineering_" + group
    section["recipes"] = _deduplicate(old_recipes + all_recipes, "source_path")
    require(len({row["id"] for row in section["recipes"]}) == len(section["recipes"]), "recipe IDs collide across different source paths")
    section["recompositions"] = _deduplicate(section.get("recompositions", []) + all_recompositions, "id")
    section["real_sources"] = _deduplicate(section.get("real_sources", []) + real_sources, "path")
    section["artifacts"] = _deduplicate(section.get("artifacts", []) + completed_artifacts, "id")
    section.update(version=1, preview_only=True, art_passed=False,
        active_style={"path": registry["style_reference"], "sha256": registry["style_sha256"].lower(),
                      "status": "complete", "actual_size": style_size, "origin": "builtin_imagegen"},
        real_generation_receipts=generations,
        real_scene_registry={"path": registry_path, "selected_receipts": [{**row["entry"], "sha256": row["sha256"]} for row in selected],
                             "preview_only": True, "art_passed": False})
    pipeline.validate_manifest(workspace, {"round2_art": section})
    result = {"manifest": proposed, "scene_review": review, "protected_paths": protected,
            "summary": {"scene_period_states": len(selected), "generation_receipts": len(generations),
                        "runtime_copies": len(_deduplicate(all_copies, "path")), "geometry_passed": True,
                        "art_passed": False, "preview_only": True, "central_files_modified": False}}
    if compact:
        section["geometry_passed"] = True
        result["registration_audit"] = {"round2_art": section, "geometry_passed": True, "art_passed": False, "preview_only": True}
        result["manifest"] = _compact_preview(workspace, manifest, actual, selected, all_copies, generated_outputs)
    return result


def register_registry(workspace, registry, output, *, registry_path=None):
    workspace = Path(workspace).resolve()
    result = build_proposals(workspace, registry, registry_path=registry_path)
    directory = pipeline.safe_path(workspace, output)
    require(not directory.exists() or directory.is_dir(), "output must be a proposed-file directory")
    targets = {directory / "proposed_manifest.json": result["manifest"], directory / "scene_review.json": result["scene_review"]}
    encoded = {}
    for target, value in targets.items():
        pipeline.safe_path(workspace, target.relative_to(workspace).as_posix())
        require(target.resolve() not in result["protected_paths"], "proposed output cannot overwrite a source/input")
        data = (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
        if target.exists() and (not target.is_file() or target.read_bytes() != data):
            raise FileExistsError("existing proposed output is never overwritten: " + str(target))
        encoded[target] = data
    if "registration_audit" in result:
        target = directory / "registration_audit.jsonl"
        pipeline.safe_path(workspace, target.relative_to(workspace).as_posix())
        require(target.resolve() not in result["protected_paths"], "audit output cannot overwrite a retained input")
        row = {"type": "manifest_section", "key": "round2_art", "value": result["registration_audit"]["round2_art"]}
        data = (json.dumps(row, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
        if target.exists() and (not target.is_file() or target.read_bytes() != data):
            raise FileExistsError("existing audit output is never overwritten: " + str(target))
        encoded[target] = data
    for target, data in encoded.items():
        pipeline._write_new(target, data)
    summary = {**result["summary"], "proposed_manifest": (directory / "proposed_manifest.json").relative_to(workspace).as_posix(),
               "scene_review": (directory / "scene_review.json").relative_to(workspace).as_posix()}
    if "registration_audit" in result:
        summary["registration_audit"] = (directory / "registration_audit.jsonl").relative_to(workspace).as_posix()
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--registry", default=REGISTRY)
    parser.add_argument("--output", default=".tools/art/real_scene_registration")
    parser.add_argument("--validate-only", action="store_true", help="recheck all retained bytes, pixels and registry data without writing any output")
    args = parser.parse_args(argv)
    registry = pipeline.read_json(pipeline.safe_path(args.workspace, args.registry, must_exist=True))
    if args.validate_only:
        result = {**build_proposals(args.workspace, registry, registry_path=args.registry)["summary"], "validate_only": True}
    else:
        result = register_registry(args.workspace, registry, args.output, registry_path=args.registry)
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print("REAL SCENE REGISTRY: " + str(error), file=sys.stderr)
        raise SystemExit(2)
