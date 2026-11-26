"""Read-only portrait source, metadata and complete combination audit.

This is a CPU/alpha contract, never a substitute for the real Godot renderer or
visual acceptance. No source image, appearance ID, exclusion or state is edited.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
HAIR = ("hair_front", "hair_back")


def need(ok, message):
    if not ok:
        raise ValueError(message)


def exact(value, keys):
    return type(value) is dict and set(value) == set(keys)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def whole(value):
    return number(value) and value == math.floor(value)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def press_pixels(pixels, rule):
    """Nearest native-space inverse warp, mirrored exactly by the GD leaf.

    The quadratic map is monotone, joins the untouched lower hair with zero
    displacement/derivative, and never crops along a horizontal cutoff line.
    Accepts RGBA or alpha-only arrays; the caller retains its original source.
    """
    height, width = pixels.shape[:2]
    end = int(rule["end_y"])
    offset, center = float(rule["top_offset"]), float(rule["center_x"])
    result = np.zeros_like(pixels)
    result[end:] = pixels[end:]
    a, b = offset / (end * end), 1.0 - 2.0 * offset / end
    for y in range(math.ceil(offset), end):
        source_y = (-b + math.sqrt(b * b - 4.0 * a * (offset - y))) / (2.0 * a)
        sy = min(end - 1, max(0, math.floor(source_y + 0.5)))
        scale = 1.0 - (1.0 - float(rule["top_scale"])) * (1.0 - source_y / end) ** 2
        left = max(0, math.ceil(center - center * scale))
        right = min(width - 1, math.floor(center + (width - 1 - center) * scale))
        x = np.arange(left, right + 1)
        sx = np.floor(center + (x - center) / scale + 0.5).astype(np.int64).clip(0, width - 1)
        result[y, x] = pixels[sy, sx]
    return result


def validate_rendering(config):
    """Strict render-only metadata; it cannot change saved part legality."""
    need(type(config) is dict and type(config.get("parts")) is dict, "PARTS_INVALID")
    catalog = config["parts"]
    order = config.get("layer_order")
    need(type(order) is list and all(type(x) is str for x in order), "IDENTITY_ORDER_INVALID")
    layers = {}
    for layer, rows in catalog.items():
        need(type(layer) is str and type(rows) is list, "PART_ROWS_INVALID")
        need(all(type(row) is dict and type(row.get("id")) is str and type(row.get("ages")) is list for row in rows), "PART_ROW_INVALID")
        layers[layer] = {row["id"]: row for row in rows}
        need(len(layers[layer]) == len(rows), "PART_ID_DUPLICATE")
    policy = config.get("rendering")
    need(type(policy) is dict, "RENDER_METADATA_MISSING")
    need(exact(policy, ("version", "render_order", "accessories")) and whole(policy["version"]) and policy["version"] == 1, "RENDER_METADATA_SHAPE")
    render_order = policy["render_order"]
    need(type(render_order) is list and all(type(x) is str for x in render_order), "RENDER_ORDER_TYPE")
    need(len(render_order) == len(set(render_order)) and set(render_order) == set(order) | {"neckwear"}, "RENDER_ORDER_MEMBERS")
    need(render_order.index("hair_back") < render_order.index("outfit") < render_order.index("neckwear") < render_order.index("hair_front"), "SCARF_DEPTH_INVALID")
    accessories = policy["accessories"]
    need(type(accessories) is dict and set(accessories) == set(layers["accessory"]), "ACCESSORY_RENDER_ROWS_INVALID")
    canvas = config.get("canvas")
    need(type(canvas) is list and len(canvas) == 2 and all(whole(x) and x > 0 for x in canvas), "CANVAS_INVALID")
    for accessory_id, render in accessories.items():
        need(exact(render, ("layer", "hides", "incompatible_with")) and render["layer"] in ("accessory", "neckwear"), "ACCESSORY_RENDER_SHAPE")
        need(type(render["hides"]) is list and type(render["incompatible_with"]) is list, "RENDER_RULE_ARRAYS")
        seen, graph = set(), {}
        for rule in render["hides"]:
            need(type(rule) is dict and rule.get("layer") in HAIR, "HIDE_LAYER_INVALID")
            layer = rule["layer"]
            selected = rule.get("when_ids")
            need(type(selected) is list and selected and all(type(x) is str and x in layers[layer] for x in selected), "HIDE_IDS_INVALID")
            need(len(selected) == len(set(selected)), "HIDE_IDS_DUPLICATE")
            for part_id in selected:
                need((layer, part_id) not in seen, "HIDE_OVERLAP")
                seen.add((layer, part_id))
            if rule.get("mode") == "replace":
                need(exact(rule, ("mode", "layer", "when_ids", "replacement_id")), "REPLACE_SHAPE")
                replacement = rule["replacement_id"]
                need(type(replacement) is str and replacement in layers[layer] and replacement not in selected, "REPLACE_ID_INVALID")
                for part_id in selected:
                    need(set(layers[layer][part_id]["ages"]) <= set(layers[layer][replacement]["ages"]), "REPLACE_AGE_INVALID")
                    graph[(layer, part_id)] = (layer, replacement)
            elif rule.get("mode") == "press":
                need(exact(rule, ("mode", "layer", "when_ids", "center_x", "top_offset", "top_scale", "end_y")), "PRESS_SHAPE")
                need(all(number(rule[k]) for k in ("center_x", "top_offset", "top_scale", "end_y")), "PRESS_NUMBER_INVALID")
                need(0 <= rule["center_x"] < canvas[0] and whole(rule["end_y"]) and 0 < rule["end_y"] < canvas[1], "PRESS_BOUNDS_INVALID")
                need(0 < rule["top_scale"] <= 1 and 0 < rule["top_offset"] * 2 < rule["end_y"], "PRESS_MONOTONICITY_INVALID")
            else:
                raise ValueError("HIDE_MODE_INVALID")
        for start in graph:
            visited, node = set(), start
            while node in graph:
                need(node not in visited, "REPLACE_CYCLE")
                visited.add(node)
                node = graph[node]
        incompatible = set()
        for rule in render["incompatible_with"]:
            need(exact(rule, ("layer", "ids")) and rule["layer"] in HAIR, "INCOMPATIBLE_SHAPE")
            values = rule["ids"]
            need(type(values) is list and values and all(type(x) is str and x in layers[rule["layer"]] for x in values), "INCOMPATIBLE_IDS_INVALID")
            need(len(values) == len(set(values)), "INCOMPATIBLE_DUPLICATE")
            for part_id in values:
                need((rule["layer"], part_id) not in incompatible, "INCOMPATIBLE_RULE_DUPLICATE")
                incompatible.add((rule["layer"], part_id))
        need(accessory_id != "none" or (not render["hides"] and not render["incompatible_with"] and render["layer"] == "accessory"), "NONE_MUST_BE_IDENTITY")
        for layer in HAIR:
            need(any((layer, part_id) not in incompatible for part_id in layers[layer]), "BLANKET_HAIR_EXCLUSION")
    need(accessories.get("accessory_07", {}).get("layer") == "neckwear", "SCARF_LAYER_INVALID")
    return policy


def audit_sources(config, root=ROOT):
    manifest_path = root / "assets/ART_ASSET_MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    registered = {}
    for row in manifest["assets"]:
        if type(row) is dict and type(row.get("path")) is str and type(row.get("sha256")) is str:
            need(row["path"] not in registered or registered[row["path"]] == row["sha256"], "SOURCE_MANIFEST_AMBIGUOUS")
            registered[row["path"]] = row["sha256"]
    paths, alphas = {}, {}
    for layer, rows in config["parts"].items():
        for row in rows:
            if row.get("optional", False):
                need(row["id"] == "none" and row.get("path") == "", "OPTIONAL_PART_INVALID")
                continue
            entries = row.get("paths", {"neutral": row.get("path")})
            need(type(entries) is dict and entries, "SOURCE_PATHS_INVALID")
            for mood, value in entries.items():
                need(type(value) is str and value.startswith("res://") and value.endswith(".png"), "SOURCE_PATH_INVALID")
                rel = value.removeprefix("res://")
                path = root / rel
                need(".." not in Path(rel).parts and not Path(rel).is_absolute() and path.resolve().is_relative_to(root.resolve()), "SOURCE_PATH_ESCAPE")
                need(path.is_file() and rel in registered and digest(path) == registered[rel], "SOURCE_MISSING_OR_CHANGED: " + rel)
                with Image.open(path) as image:
                    need(image.format == "PNG" and image.mode == "RGBA" and list(image.size) == config["canvas"], "SOURCE_NATIVE_RGBA_INVALID: " + rel)
                    alpha = np.asarray(image.getchannel("A"))
                    count = int(np.count_nonzero(alpha))
                    need(count > 0, "BLANK_SOURCE_NOT_A_FIX: " + rel)
                    if layer in (*HAIR, "accessory", "outfit", "body"):
                        alphas[(layer, row["id"])] = alpha.copy()
                paths[rel] = {"path": rel, "sha256": registered[rel], "bytes": path.stat().st_size, "dimensions": config["canvas"], "nonzero_alpha_pixels": count}
    for preset in config.get("presets", {}).values():
        for value in preset["paths"].values():
            rel = value.removeprefix("res://")
            path = root / rel
            need(path.is_file() and rel in registered and digest(path) == registered[rel], "PRESET_SOURCE_CHANGED: " + rel)
            with Image.open(path) as image:
                need(image.format == "PNG" and list(image.size) == preset["canvas"], "PRESET_SOURCE_NATIVE_INVALID: " + rel)
                count = int(np.count_nonzero(np.asarray(image.getchannel("A"))))
                need(count > 0, "BLANK_PRESET_SOURCE")
            paths[rel] = {"path": rel, "sha256": registered[rel], "bytes": path.stat().st_size, "dimensions": preset["canvas"], "nonzero_alpha_pixels": count}
    need(all(digest(root / rel) == row["sha256"] for rel, row in paths.items()), "SOURCE_CHANGED_DURING_AUDIT")
    return list(paths.values()), alphas


def matrix(config, policy=None):
    ids = {layer: [row["id"] for row in config["parts"][layer]] for layer in ("accessory", *HAIR)}
    need(len(ids["accessory"]) == 15 and "none" in ids["accessory"] and len(ids["hair_front"]) == 12 and len(ids["hair_back"]) == 10, "MATRIX_DIMENSIONS_CHANGED")
    rows, reachable = [], {part_id: 0 for part_id in ids["accessory"]}
    for accessory, front, back in itertools.product(ids["accessory"], ids["hair_front"], ids["hair_back"]):
        selected = {"accessory": accessory, "hair_front": front, "hair_back": back}
        mutual = any(all(selected.get(k) == v for k, v in rule.items()) for rule in config["mutual_exclusions"])
        excluded = any(all(selected.get(k) == v for k, v in rule.items()) for rule in config.get("selection_exclusions", []))
        render = policy["accessories"][accessory] if policy else {"hides": [], "incompatible_with": []}
        display = selected.copy()
        for rule in render["hides"]:
            if rule["mode"] == "replace" and selected[rule["layer"]] in rule["when_ids"]:
                display[rule["layer"]] = rule["replacement_id"]
        incompatible = any(selected[rule["layer"]] in rule["ids"] for rule in render["incompatible_with"])
        valid = not (mutual or excluded or incompatible)
        reachable[accessory] += int(valid)
        rows.append({"selected": selected, "display": display, "appearance_valid": not mutual, "new_selection_valid": valid, "saved_ids_changed": False})
    need(len(rows) == 1800 and sum(row["selected"]["accessory"] != "none" for row in rows) == 1680, "INCOMPLETE_MATRIX")
    need(all(reachable.values()), "ACCESSORY_HAS_NO_REACHABLE_HAIR")
    return rows, reachable


def audit_prepared_hair(config, policy, alphas):
    results = []
    for accessory, render in policy["accessories"].items():
        for rule in render["hides"]:
            if rule["mode"] != "press":
                continue
            for part_id in rule["when_ids"]:
                source = alphas[(rule["layer"], part_id)]
                prepared = press_pixels(source, rule)
                need(np.count_nonzero(prepared) > 0, "EMPTY_PREPARED_HAIR")
                need(np.array_equal(source[int(rule["end_y"]):], prepared[int(rule["end_y"]):]), "LOWER_HAIR_IDENTITY_CROPPED")
                results.append({"accessory": accessory, "layer": rule["layer"], "selected_id": part_id, "display_id": part_id, "alpha_sha256": hashlib.sha256(prepared.tobytes()).hexdigest(), "nonzero_source": int(np.count_nonzero(source)), "nonzero_prepared": int(np.count_nonzero(prepared)), "lower_hair_unchanged": True})
    return results


def validate_godot_parity(config, receipt, root=ROOT):
    need(exact(receipt, ("schema", "config_sha256", "test_sha256", "samples", "checks", "failures")) and receipt["schema"] == "portrait_clipping_parity_v1", "PARITY_SHAPE_INVALID")
    need(receipt["config_sha256"] == digest(root / "data/people/appearance_parts.json") and receipt["test_sha256"] == digest(root / "tests/people/portrait_clipping.gd"), "PARITY_SOURCE_DRIFT")
    need(whole(receipt["checks"]) and receipt["checks"] > 0 and type(receipt["failures"]) is int and receipt["failures"] == 0, "PARITY_TARGET_FAILED")
    samples = receipt["samples"]
    need(type(samples) is list and len(samples) == 8, "PARITY_SAMPLES_MISSING")
    parts = {layer: {row["id"]: row for row in rows} for layer, rows in config["parts"].items()}
    actual, expected = set(), {(hat, "hair_front_01", back) for hat in ("accessory_10", "accessory_11", "accessory_12") for back in ("hair_back_06", "hair_back_10")}
    expected |= {("accessory_07", "hair_front_12", "hair_back_10"), ("none", "hair_front_01", "hair_back_06")}
    verified = []
    for sample in samples:
        need(exact(sample, ("appearance", "mood", "plan_digest", "layers")), "PARITY_SAMPLE_SHAPE")
        value = sample["appearance"]
        need(exact(value, ("version", "parts", "colors", "age_stage")) and value["version"] == 2 and exact(value["parts"], config["layer_order"]), "PARITY_IDENTITY_SHAPE")
        selected = value["parts"]
        need(all(type(part_id) is str and part_id in parts[layer] and value["age_stage"] in parts[layer][part_id]["ages"] for layer, part_id in selected.items()), "PARITY_IDENTITY_PARTS")
        key = tuple(selected[layer] for layer in ("accessory", "hair_front", "hair_back"))
        need(key not in actual, "PARITY_SAMPLE_DUPLICATE")
        actual.add(key)
        need(sample["mood"] in config["moods"] and type(sample["plan_digest"]) is str and len(sample["plan_digest"]) == 64, "PARITY_PLAN_INVALID")
        need(type(sample["layers"]) is list and len(sample["layers"]) == 2 and {x["layer"] for x in sample["layers"]} == set(HAIR), "PARITY_HAIR_LAYERS_MISSING")
        for row in sample["layers"]:
            need(exact(row, ("layer", "id", "display_id", "render_layer", "path", "operations", "source_sha256", "prepared_rgba_sha256", "live_rgba_sha256", "png_path", "png_sha256")), "PARITY_LAYER_SHAPE")
            layer = row["layer"]
            need(row["id"] == selected[layer] and row["render_layer"] == layer, "PARITY_SAVED_ID_CHANGED")
            display = row["id"]
            operations = []
            for rule in config["rendering"]["accessories"][selected["accessory"]]["hides"]:
                if rule["layer"] == layer and row["id"] in rule["when_ids"]:
                    if rule["mode"] == "replace":
                        display = rule["replacement_id"]
                    else:
                        operations.append(rule)
            source_row = parts[layer][display]
            source_path = source_row["paths"][sample["mood"]] if "paths" in source_row else source_row["path"]
            need(row["display_id"] == display and row["path"] == source_path and row["operations"] == operations, "PARITY_RULE_OR_PATH_DRIFT")
            path = root / source_path.removeprefix("res://")
            need(digest(path) == row["source_sha256"], "PARITY_ORIGINAL_SOURCE_DRIFT")
            with Image.open(path) as source:
                pixels = np.array(source.convert("RGBA"))
            for rule in operations:
                pixels = press_pixels(pixels, rule)
            rgba_sha = hashlib.sha256(pixels.tobytes()).hexdigest()
            need(rgba_sha == row["prepared_rgba_sha256"] == row["live_rgba_sha256"], "PYTHON_GODOT_RGBA_PARITY_FAILED")
            measured = root / row["png_path"]
            need(measured.resolve().is_relative_to((root / ".tools/r3-polish/portrait-runtime").resolve()) and measured.is_file() and digest(measured) == row["png_sha256"], "PARITY_MEASURED_IMAGE_INVALID")
            with Image.open(measured) as image:
                need(image.format == "PNG" and image.mode == "RGBA" and np.array_equal(np.array(image), pixels), "PARITY_MEASURED_PIXELS_DIFFER")
            verified.append({"sample": key, "layer": layer, "rgba_sha256": rgba_sha})
    need(actual == expected, "PARITY_REQUIRED_COMBINATIONS_MISSING")
    return verified


def audit_face_layers(config, alphas):
    """Verify the mask/order contract used by the actual runtime paint layers.

    Pixel alpha containment is exercised against the generated buffers by
    tests/people/face_details.gd; this static audit does not claim visual QA.
    """
    face = config.get("face_variation")
    if face is None:
        return {"legacy_catalog": True, "layers": []}
    expected = [{"id":"makeup","after":"face_shape","mask":"face_shape"},
                {"id":"lip_color","after":"mouth_expr","mask":"mouth_expr"},
                {"id":"face_marks","after":"mouth_expr","mask":"face_shape"}]
    need(face.get("overlays") == expected, "FACE_OVERLAY_ORDER_OR_MASK_INVALID")
    order = config["rendering"]["render_order"]
    need(order.index("face_shape") < order.index("eyes_expr"), "FACE_MAKEUP_ORDER_INVALID")
    need(order.index("mouth_expr") < order.index("hair_front"), "FACE_LIP_ORDER_INVALID")
    masks = []
    for layer in ("face_shape", "mouth_expr"):
        for row in config["parts"][layer]:
            # All expression files were already verified against the manifest.
            paths = row.get("paths", {"neutral": row.get("path")})
            for mood, path in paths.items():
                need(isinstance(path, str) and path.startswith("res://"), "FACE_MASK_PATH_INVALID")
                with Image.open(ROOT/path[6:]) as image:
                    alpha = np.asarray(image.convert("RGBA"))[:, :, 3]
                    need(image.size == tuple(config["canvas"]) and np.any(alpha), "FACE_MASK_EMPTY_OR_SIZE_INVALID")
                masks.append({"layer":layer,"id":row["id"],"mood":mood,"path":path})
    return {"layers":expected,"source_masks":masks,"pixel_containment_target":"tests/people/face_details.gd","visual_acceptance":False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "data/people/appearance_parts.json")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--production-contract", action="store_true", help="Explicit form of the default strict metadata contract")
    parser.add_argument("--godot-parity", type=Path, help="Actual receipt printed by tests/people/portrait_clipping.gd; never synthesized by this checker")
    args = parser.parse_args()
    need(args.report.resolve().is_relative_to((ROOT / ".tools").resolve()), "REPORT_MUST_BE_IGNORED_LOCAL_OUTPUT")
    failures, result = [], {"schema": "portrait_clipping_alpha_audit_v1", "godot_runs": 0, "source_writes": 0, "overall_visual_acceptance": False}
    try:
        config = json.loads(args.config.read_text(encoding="utf-8-sig"))
        sources, alphas = audit_sources(config)
        policy = None
        try:
            policy = validate_rendering(config)
        except ValueError as error:
            failures.append(str(error))
        rows, reachable = matrix(config, policy)
        result.update(config_sha256=digest(args.config), sources=sources, source_count=len(sources), source_sha_all_match_manifest=True, matrix=rows, matrix_count=len(rows), primary_count=1680, accessory_none_count=120, appearance_valid_count=sum(x["appearance_valid"] for x in rows), selection_valid_count=sum(x["new_selection_valid"] for x in rows), selection_reachability=reachable)
        if policy is not None:
            result["prepared_hair"] = audit_prepared_hair(config, policy, alphas)
            result["face_layers"] = audit_face_layers(config, alphas)
            if args.godot_parity is not None:
                result["godot_parity"] = validate_godot_parity(config, json.loads(args.godot_parity.read_text(encoding="utf-8-sig")))
                result["godot_parity_receipt"] = {"path": str(args.godot_parity), "sha256": digest(args.godot_parity)}
    except (ValueError, KeyError, TypeError, OSError) as error:
        failures.append(type(error).__name__ + ": " + str(error))
    result.update(status="STATIC_CONTRACT_RED" if failures else "STATIC_CONTRACT_PASS_NOT_RENDER_ACCEPTANCE", failures=failures, godot_renderer_parity_required_separately=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("status", "failures", "overall_visual_acceptance")}, ensure_ascii=True))
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
