"""Extract real full-canvas layers from C and an AI all-object cleanplate.

No generator, API, or procedural object drawing is used here. Polygon masks
select actual source pixels; only mask-local raw-B patches replace C. Outputs
and a proposed manifest receipt are exclusive/idempotent, never overwrites.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline as pipeline

SCRIPT = "tools/art/real_scene_layers.py"
CONFIG = ROOT / "data/art/real_scene_layers.json"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def identifier(value):
    return isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", value)


def size_valid(value):
    return isinstance(value, list) and len(value) == 2 and all(type(n) is int and n > 0 for n in value)


def validate_config(config):
    require(isinstance(config, dict) and config.get("version") == 1 and config.get("kind") == "real_pixel_extraction", "invalid real layer config")
    for field in ("pipeline_config", "output_root", "runtime_root"):
        pipeline.safe_path(ROOT, config.get(field))
    require(config["output_root"].startswith("assets/generated_scenes/") and config["runtime_root"].startswith("assets/generated_scenes/runtime/"), "outputs must be in designated scene art directories")
    require(config["output_root"] != config["runtime_root"], "source/runtime directories must differ")
    require(size_valid(config.get("logical_canvas")), "invalid logical canvas")
    require(config.get("required_mask") == {"feather_pixels": 1, "inpaint_dilation_pixels": 6}, "real masks require 1px feather and 6px authorization")
    require(config.get("motion_types") == ["static", "sway_shader", "pendulum", "flow"], "invalid motion type contract")
    require(type(config.get("maximum_polygon_vertices")) is int and config["maximum_polygon_vertices"] >= 3, "invalid polygon vertex limit")
    for field in ("processing_prompt", "cleanplate_method", "mask_usage_notice"):
        require(isinstance(config.get(field), str) and config[field].strip(), "missing processing explanation")
    require(isinstance(config.get("jobs"), list), "jobs must be an array")
    for job in config["jobs"]:
        validate_spec(job, config)
    return config


def load_config(path=CONFIG):
    return validate_config(pipeline.read_json(path))


def _cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _segments_intersect(a, b, c, d):
    def between(p, q, r):
        return min(p[0], r[0]) <= q[0] <= max(p[0], r[0]) and min(p[1], r[1]) <= q[1] <= max(p[1], r[1])
    x, y, z, w = _cross(a, b, c), _cross(a, b, d), _cross(c, d, a), _cross(c, d, b)
    return ((x > 0) != (y > 0) and (z > 0) != (w > 0) and x != 0 and y != 0 and z != 0 and w != 0 or
            x == 0 and between(a, c, b) or y == 0 and between(a, d, b) or
            z == 0 and between(c, a, d) or w == 0 and between(c, b, d))


def validate_polygon(points, native, maximum):
    require(isinstance(points, list) and 3 <= len(points) <= maximum, "polygon needs at least three vertices")
    for point in points:
        require(isinstance(point, list) and len(point) == 2 and all(number(v) for v in point), "polygon coordinates must be finite numbers")
        require(0 <= point[0] < native[0] and 0 <= point[1] < native[1], "polygon outside native canvas")
    if points[-1] == points[0]:
        points = points[:-1]
    require(len(points) >= 3 and len({tuple(p) for p in points}) == len(points), "polygon has duplicate vertices")
    area = sum(p[0] * points[(i + 1) % len(points)][1] - p[1] * points[(i + 1) % len(points)][0] for i, p in enumerate(points))
    require(area != 0, "polygon has zero area or self intersection")
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            if j in (i, (i + 1) % len(points)) or i == (j + 1) % len(points):
                continue
            require(not _segments_intersect(points[i], points[(i + 1) % len(points)], points[j], points[(j + 1) % len(points)]), "polygon self intersection")


def validate_spec(spec, config=None):
    config = config or load_config()
    require(isinstance(spec, dict) and spec.get("version") == 1, "invalid scene spec version")
    require(spec.get("scene_id") in [f"S{i:02}" for i in range(1, 8)] and spec.get("period") in ("day", "night", "closed"), "invalid scene or period")
    require(spec.get("period") != "closed" or spec["scene_id"] == "S01", "closed period belongs to exterior")
    require("state" not in spec or spec["scene_id"] == "S04" and spec["state"] in ("open", "closed"), "invalid cabinet state")
    require(identifier(spec.get("revision")), "invalid revision path")
    require(size_valid(spec.get("native_size")), "invalid source native size")
    for field in ("original_path", "raw_cleanplate_path", "style_reference"):
        pipeline.safe_path(ROOT, spec.get(field))
    for field in ("composite_prompt", "cleanplate_prompt"):
        require(isinstance(spec.get(field), str) and spec[field].strip(), "actual generation prompt is required")
    if "mask_usage_notice" in spec:
        require(isinstance(spec["mask_usage_notice"], str) and spec["mask_usage_notice"].strip(), "actual mask reference usage notice must be text")
    require(isinstance(spec.get("layers"), list) and spec["layers"], "scene needs real object masks")
    ids, orders = set(), set()
    for layer in spec["layers"]:
        require(isinstance(layer, dict) and identifier(layer.get("id")), "invalid layer id")
        require(layer["id"] not in ids, "duplicate layer id")
        ids.add(layer["id"])
        z = layer.get("z_index")
        require(type(z) is int and -4096 <= z <= 4096 and z not in orders, "invalid or duplicate layer z")
        orders.add(z)
        pivot = layer.get("pivot_px")
        require(isinstance(pivot, list) and len(pivot) == 2 and all(number(n) and 0 <= n <= spec["native_size"][i] for i, n in enumerate(pivot)), "invalid native pivot")
        motion = layer.get("motion")
        require(isinstance(motion, dict) and motion.get("type") in config["motion_types"] and isinstance(motion.get("parameters"), dict), "invalid motion metadata")
        require(all(isinstance(key, str) and key and number(value) for key, value in motion["parameters"].items()), "motion parameters must be finite numbers")
        require(isinstance(layer.get("polygons"), list) and layer["polygons"], "layer needs manual polygons")
        require("holes" not in layer or isinstance(layer["holes"], list), "holes must be an array of polygons")
        require("preserve_base" not in layer or type(layer["preserve_base"]) is bool, "preserve_base must be boolean")
        for polygon in layer["polygons"] + layer.get("holes", []):
            validate_polygon(polygon, spec["native_size"], config["maximum_polygon_vertices"])
    return spec


def validate_generation_receipt(workspace, receipt):
    """Validate known metadata against retained bytes; preserve extension data."""
    workspace = Path(workspace)
    require(isinstance(receipt, dict) and receipt.get("version") == 1, "invalid generation receipt version")
    require(receipt.get("scene_id") in [f"S{i:02}" for i in range(1, 8)], "invalid receipt scene")
    style = pipeline.safe_path(workspace, receipt.get("style_reference"), must_exist=True)
    pipeline.read_image(style)
    require(isinstance(receipt.get("style_sha256"), str) and receipt["style_sha256"].lower() == pipeline.sha256(style), "style sha256 mismatch")
    require(isinstance(receipt.get("records"), list) and receipt["records"], "generation receipt requires records")
    ids, paths = set(), set()
    statuses = pipeline.load_config()["statuses"]
    for record in receipt["records"]:
        require(isinstance(record, dict) and identifier(record.get("id")) and record["id"] not in ids, "invalid or duplicate generation id")
        ids.add(record["id"])
        path = pipeline.safe_path(workspace, record.get("path"), must_exist=True)
        require(path not in paths, "duplicate generation output path")
        paths.add(path)
        require(isinstance(record.get("prompt"), str) and record["prompt"].strip(), "actual generation prompt is required")
        require(isinstance(record.get("ref_paths"), list), "ref_paths must record actual references")
        for reference in record["ref_paths"]:
            pipeline.read_image(pipeline.safe_path(workspace, reference, must_exist=True))
        image = pipeline.read_image(path)
        require(size_valid(record.get("native_size")) and record["native_size"] == list(image.size), "actual native size mismatch")
        require(isinstance(record.get("sha256"), str) and record["sha256"].lower() == pipeline.sha256(path), "generation sha256 mismatch")
        require(record.get("status") in statuses, "invalid generation status")
        require(record.get("generator", record.get("generation_tool")) in ("builtin", "builtin_imagegen", "image_gen.imagegen"), "generation receipt must identify the actual builtin tool")
        attempts = record.get("attempts")
        require(isinstance(attempts, list) and 1 <= len(attempts) <= 4, "attempt count must be within one to four")
        numbers = set()
        for attempt in attempts:
            require(isinstance(attempt, dict) and type(attempt.get("attempt")) is int and 1 <= attempt["attempt"] <= 4 and attempt["attempt"] not in numbers, "invalid or duplicate attempt number")
            numbers.add(attempt["attempt"])
            require(attempt.get("status") in statuses, "invalid attempt status")
            if "elapsed_ms" in attempt:
                require(type(attempt["elapsed_ms"]) is int and attempt["elapsed_ms"] >= 0, "invalid elapsed milliseconds")
        if record["status"] == "complete":
            require(any(attempt["status"] == "complete" for attempt in attempts), "complete output needs an actual completed attempt")
        if "source_path" in record:
            require(record["source_path"] == record["path"], "retained source_path differs from actual output")
        if "native_resolution_met" in record:
            runtime = pipeline.load_config()["runtime_size"]
            require(type(record["native_resolution_met"]) is bool and record["native_resolution_met"] == (image.width >= runtime[0] and image.height >= runtime[1]), "native resolution claim disagrees with actual pixels")
    return receipt


def cover(image, target_size):
    width, height = image.size
    out_width, out_height = target_size
    scale = max(out_width / width, out_height / height)
    cw, ch = out_width / scale, out_height / scale
    crop = [(width - cw) / 2, (height - ch) / 2, (width + cw) / 2, (height + ch) / 2]
    return image.resize(tuple(target_size), Image.Resampling.LANCZOS, box=tuple(crop)), {
        "method": "equal_aspect_cover", "filter": "Lanczos", "scale": scale,
        "source_crop": crop, "runtime_size": list(target_size)}


def hard_mask(native_size, layer):
    mask = Image.new("L", tuple(native_size), 0)
    draw = ImageDraw.Draw(mask)
    for points in layer["polygons"]:
        draw.polygon([tuple(p) for p in points], fill=255)
    for points in layer.get("holes", []):
        draw.polygon([tuple(p) for p in points], fill=0)
    require(mask.getbbox() is not None, "manual mask is empty")
    return mask


def matte_layer(original, clean, mask):
    """Unassociate F=(C-(1-a)B)/a; no pixels are independently painted."""
    box = mask.getbbox()
    cp = original.convert("RGB").crop(box).tobytes()
    bp = clean.convert("RGB").crop(box).tobytes()
    ap = mask.crop(box).tobytes()
    pixels = bytearray(len(ap) * 4)
    clipped_pixels = clipped_channels = 0
    maximum_clamp = 0.0
    for index, alpha in enumerate(ap):
        if not alpha:
            continue
        clipped = False
        for channel in range(3):
            raw = (cp[index * 3 + channel] * 255 - bp[index * 3 + channel] * (255 - alpha)) / alpha
            bounded = max(0, min(255, round(raw)))
            pixels[index * 4 + channel] = bounded
            if raw < 0 or raw > 255:
                clipped = True
                clipped_channels += 1
                maximum_clamp = max(maximum_clamp, abs(raw - max(0, min(255, raw))))
        pixels[index * 4 + 3] = alpha
        clipped_pixels += clipped
    result = Image.new("RGBA", original.size, (0, 0, 0, 0))
    result.paste(Image.frombytes("RGBA", (box[2] - box[0], box[3] - box[1]), bytes(pixels)), box[:2])
    return result, {"clipped_pixels": clipped_pixels, "clipped_channels": clipped_channels,
                    "maximum_unassociated_clamp": maximum_clamp}


def validate_processing_receipt(workspace, receipt):
    """Recheck retained files, full-canvas masks and strict ROI evidence."""
    workspace = Path(workspace)
    require(isinstance(receipt, dict) and receipt.get("version") == 1 and receipt.get("kind") == "real_pixel_extraction", "invalid processing receipt")
    require(receipt.get("art_passed") is False and receipt.get("manifest_modified") is False, "offline processing cannot approve art or modify the manifest")
    spec = validate_spec(receipt.get("specification"))
    settings = pipeline.load_config()
    require(receipt.get("qa_bounds") == settings["qa"] and receipt.get("mask_parameters") == settings["mask"], "processing receipt weakened strict QA or mask parameters")
    require(isinstance(receipt.get("inputs"), dict) and isinstance(receipt.get("artifacts"), list), "missing file provenance")

    def checked_image(record, size_key="native_size"):
        require(isinstance(record, dict), "invalid image provenance")
        path = pipeline.safe_path(workspace, record.get("path"), must_exist=True)
        require(record.get("sha256") == pipeline.sha256(path), "processing sha256 mismatch")
        image = pipeline.read_image(path, "RGBA")
        require(size_valid(record.get(size_key)) and record[size_key] == list(image.size), "processing image size mismatch")
        return image

    for role in ("original", "raw_cleanplate", "style"):
        require(role in receipt["inputs"], "missing processing input")
        checked_image(receipt["inputs"][role])
    artifact_paths = set()
    for record in receipt["artifacts"]:
        checked_image(record)
        require(record["path"] not in artifact_paths, "duplicate processing artifact")
        artifact_paths.add(record["path"])
    original_path = pipeline.safe_path(workspace, receipt.get("original_path"), must_exist=True)
    require(original_path.read_bytes() == pipeline.safe_path(workspace, spec["original_path"], must_exist=True).read_bytes(), "retained C differs from its original bytes")
    original = pipeline.read_image(original_path, "RGBA")
    raw = pipeline.read_image(pipeline.safe_path(workspace, spec["raw_cleanplate_path"], must_exist=True), "RGBA")
    normalized, transform = cover(raw, original.size)
    normalization = receipt.get("raw_cleanplate_normalization", {})
    require(normalization.get("native_size") == list(raw.size) and normalization.get("normalized_size") == list(original.size) and normalization.get("transform") == transform, "raw cleanplate normalization metadata mismatch")
    normalized_actual = pipeline.read_image(pipeline.safe_path(workspace, normalization.get("normalized_path"), must_exist=True), "RGBA")
    require(ImageChops.difference(normalized, normalized_actual).getbbox(alpha_only=False) is None, "normalized cleanplate pixels differ from equal-aspect cover")
    require(isinstance(receipt.get("runtime_copies"), list), "missing runtime copies")
    runtime_paths = set()
    for record in receipt["runtime_copies"]:
        runtime = checked_image(record, "runtime_size")
        source = pipeline.safe_path(workspace, record.get("source_path"), must_exist=True)
        require(record.get("source_sha256") == pipeline.sha256(source), "runtime source sha256 mismatch")
        source_image = pipeline.read_image(source, "RGBA")
        expected_runtime, expected_transform = cover(source_image, settings["runtime_size"])
        require(record.get("native_size") == list(source_image.size) and list(runtime.size) == settings["runtime_size"], "runtime source/native pixels mismatch")
        require(record.get("transform") == expected_transform and record.get("scale_x") == record.get("scale_y") == expected_transform["scale"], "runtime cover geometry mismatch")
        require(ImageChops.difference(runtime, expected_runtime).getbbox(alpha_only=False) is None, "runtime pixels differ from the declared Lanczos cover")
        require(record["path"] not in runtime_paths, "duplicate runtime copy")
        runtime_paths.add(record["path"])
    require(isinstance(receipt.get("layers"), list) and len(receipt["layers"]) == len(spec["layers"]), "missing processing layers")
    union = Image.new("L", original.size, 0)
    combined = Image.new("RGBA", original.size, (0, 0, 0, 0))
    layers = []
    single_results = []
    declared = {row["id"]: row for row in spec["layers"]}
    seen = set()
    for row in sorted(receipt["layers"], key=lambda value: value["z_index"]):
        require(row.get("id") in declared and row["id"] not in seen, "unknown or duplicate processing layer")
        seen.add(row["id"])
        layer_spec = declared[row["id"]]
        hard = hard_mask(original.size, layer_spec)
        soft = hard.filter(ImageFilter.BoxBlur(settings["mask"]["feather_pixels"]))
        target = hard.filter(ImageFilter.MaxFilter(settings["mask"]["inpaint_dilation_pixels"] * 2 + 1))
        for field, expected in (("hard_mask_path", hard), ("soft_mask_path", soft), ("inpaint_mask_path", target)):
            image = pipeline.read_image(pipeline.safe_path(workspace, row.get(field), must_exist=True), "L")
            require(image.size == original.size and ImageChops.difference(image, expected).getbbox() is None, "processing mask differs from its declared polygons or 1px/6px settings")
        clean = pipeline.read_image(pipeline.safe_path(workspace, row.get("cleanplate_path"), must_exist=True), "RGBA")
        expected_clean = original if layer_spec.get("preserve_base", False) else Image.composite(normalized, original, soft)
        require(clean.size == original.size and ImageChops.difference(clean, expected_clean).getbbox(alpha_only=False) is None, "single cleanplate is not a mask-local raw B patch")
        layer = pipeline.read_image(pipeline.safe_path(workspace, row.get("layer_path"), must_exist=True), "RGBA")
        require(layer.size == original.size and ImageChops.difference(layer.getchannel("A"), soft).getbbox() is None, "layer alpha or full-canvas geometry differs from its mask")
        qa = pipeline.compare_regions(original, Image.alpha_composite(clean, layer), soft, settings)
        require(row.get("single_layer_qa") == qa, "single layer QA evidence differs from actual pixels")
        single_results.append(qa["passed"])
        if not layer_spec.get("preserve_base", False):
            union = ImageChops.lighter(union, soft)
        combined = Image.alpha_composite(combined, layer)
        layers.append(layer)
    base = pipeline.read_image(pipeline.safe_path(workspace, receipt.get("base_path"), must_exist=True), "RGBA")
    require(ImageChops.difference(base, Image.composite(normalized, original, union)).getbbox(alpha_only=False) is None, "all-object base differs from the declared removal union")
    rebuilt = base
    for image in layers:
        rebuilt = Image.alpha_composite(rebuilt, image)
    whole = pipeline.compare_regions(original, rebuilt, combined.getchannel("A"), settings)
    require(receipt.get("recomposition_qa") == whole, "all layer QA evidence differs from actual pixels")
    require(type(receipt.get("geometry_passed")) is bool and receipt["geometry_passed"] == (whole["passed"] and all(single_results)), "geometry summary disagrees with strict QA")
    return receipt


def process_scene(workspace, spec, config=None):
    config = validate_config(copy.deepcopy(config)) if config is not None else load_config()
    validate_spec(spec, config)
    workspace = Path(workspace).resolve()
    pipeline_file = pipeline.safe_path(workspace, config["pipeline_config"])
    settings = pipeline.load_config(pipeline_file if pipeline_file.is_file() else ROOT / config["pipeline_config"])
    require(all(settings["mask"][key] == value for key, value in config["required_mask"].items()), "pipeline mask differs from required 1px/6px")
    inputs = {}
    images = {}
    for role, field in (("original", "original_path"), ("raw_cleanplate", "raw_cleanplate_path"), ("style", "style_reference")):
        path = pipeline.safe_path(workspace, spec[field], must_exist=True)
        image = pipeline.read_image(path, "RGBA")
        inputs[role] = {"path": spec[field], "native_size": list(image.size), "sha256": pipeline.sha256(path)}
        images[role] = image
    original = images["original"]
    require(list(original.size) == spec["native_size"], "actual C native dimensions do not match spec")
    require(original.getchannel("A").getextrema() == (255, 255) and images["raw_cleanplate"].getchannel("A").getextrema() == (255, 255), "C and AI cleanplate must be opaque")
    normalized, normalization = cover(images["raw_cleanplate"], original.size)
    suffix = spec["period"] + ("_" + spec["state"] if "state" in spec else "")
    relative = f"{spec['scene_id']}/{suffix}/{spec['revision']}"
    output = config["output_root"] + "/" + relative
    runtime = config["runtime_root"] + "/" + relative
    blobs, artifacts, runtime_copies = {}, [], []

    def remember(path, image, role, *, source_bytes=None, make_runtime=False):
        data = source_bytes if source_bytes is not None else pipeline._png(image)
        blobs[path] = data
        artifacts.append({"path": path, "role": role, "native_size": list(image.size), "sha256": hashlib.sha256(data).hexdigest()})
        if make_runtime:
            picture, transform = cover(image, settings["runtime_size"])
            runtime_path = runtime + "/" + path.removeprefix(output + "/")
            encoded = pipeline._png(picture)
            blobs[runtime_path] = encoded
            runtime_copies.append({"path": runtime_path, "source_path": path, "native_size": list(image.size),
                                   "runtime_size": list(picture.size), "scale_x": transform["scale"], "scale_y": transform["scale"],
                                   "method": "equal-aspect cover crop, Lanczos runtime copy", "transform": transform,
                                   "source_sha256": hashlib.sha256(data).hexdigest(), "sha256": hashlib.sha256(encoded).hexdigest(),
                                   "native_resolution_met": image.width >= picture.width and image.height >= picture.height,
                                   "origin": "real_C_pixel_extraction", "art_passed": False})
            return runtime_path, transform
        return path, None

    original_path = output + "/C.png"
    remember(original_path, original, "retained_original_C", source_bytes=pipeline.safe_path(workspace, spec["original_path"]).read_bytes(), make_runtime=True)
    normalized_path = output + "/raw_cleanplate_normalized.png"
    remember(normalized_path, normalized, "normalized_AI_cleanplate")
    rows, masks = [], []
    union = Image.new("L", original.size, 0)
    for layer in sorted(spec["layers"], key=lambda row: row["z_index"]):
        hard = hard_mask(original.size, layer)
        soft = hard.filter(ImageFilter.BoxBlur(settings["mask"]["feather_pixels"]))
        authorized = hard.filter(ImageFilter.MaxFilter(settings["mask"]["inpaint_dilation_pixels"] * 2 + 1))
        # Restore AI-changed context from C. Only actual removal pixels and the
        # explicit one-pixel edge use raw B; the six-pixel ring remains audited.
        clean = original.copy() if layer.get("preserve_base", False) else Image.composite(normalized, original, soft)
        image, clamping = matte_layer(original, clean, soft)
        layer_path = output + f"/layers/{layer['id']}.png"
        clean_path = output + f"/cleanplates/{layer['id']}.png"
        hard_path = output + f"/masks/{layer['id']}_hard.png"
        soft_path = output + f"/masks/{layer['id']}_soft.png"
        inpaint_path = output + f"/masks/{layer['id']}_inpaint6.png"
        runtime_path, transform = remember(layer_path, image, "actual_C_matted_layer", make_runtime=True)
        for path, picture, role in ((clean_path, clean, "single_object_cleanplate_B_i"), (hard_path, hard, "manual_hard_mask"),
                                    (soft_path, soft, "one_pixel_feather_mask"), (inpaint_path, authorized, "six_pixel_AI_authorization_mask")):
            remember(path, picture, role)
        qa = pipeline.compare_regions(original, Image.alpha_composite(clean, image), soft, settings)
        canvas = config["logical_canvas"]
        rows.append({**copy.deepcopy(layer), "native_size": list(original.size), "layer_path": layer_path,
                     "cleanplate_path": clean_path, "hard_mask_path": hard_path, "soft_mask_path": soft_path,
                     "inpaint_mask_path": inpaint_path, "single_layer_qa": qa, "matte_clamping": clamping,
                     "descriptor": {"path": "res://" + runtime_path, "rect": [0, 0, *canvas], "hotspot": [0, 0, *canvas],
                                    "native_size": list(original.size), "pivot_px": layer["pivot_px"], "z_index": layer["z_index"],
                                    "motion": layer["motion"], "source_transform": {**transform, "native_size": list(original.size)}}})
        masks.append({"id": layer["id"], "hard": hard, "soft": soft, "image": image})
        if not layer.get("preserve_base", False):
            union = ImageChops.lighter(union, soft)
    base = Image.composite(normalized, original, union)
    base_path = output + "/B_all.png"
    base_runtime, _ = remember(base_path, base, "all_object_cleanplate_B_all", make_runtime=True)
    combined = Image.new("RGBA", original.size, (0, 0, 0, 0))
    rebuilt = base.copy()
    for row in masks:
        rebuilt = Image.alpha_composite(rebuilt, row["image"])
        combined = Image.alpha_composite(combined, row["image"])
    remember(output + "/recomposed_all.png", rebuilt, "all_layers_recomposition")
    whole_qa = pipeline.compare_regions(original, rebuilt, combined.getchannel("A"), settings)
    overlaps = []
    for index, left in enumerate(masks):
        for right in masks[index + 1:]:
            hard_overlap = ImageChops.multiply(left["hard"], right["hard"]).histogram()[255]
            positive = lambda image: image.point(lambda value: 255 if value else 0)
            soft_overlap = ImageChops.multiply(positive(left["soft"]), positive(right["soft"])).histogram()[255]
            if soft_overlap:
                overlaps.append({"layers": [left["id"], right["id"]], "hard_overlap_pixels": hard_overlap,
                                 "soft_overlap_pixels": soft_overlap, "note": "B_i retains C outside its own soft mask; occluded ownership is not inferred. B_all recomposition remains an independent strict check."})
    receipt = {"version": 1, "kind": "real_pixel_extraction", "processing_script": SCRIPT,
               "scene_id": spec["scene_id"], "period": spec["period"], "revision": spec["revision"],
               "inputs": inputs, "specification": copy.deepcopy(spec), "processing_prompt": config["processing_prompt"],
               "cleanplate_method": config["cleanplate_method"], "mask_usage_notice": spec.get("mask_usage_notice", config["mask_usage_notice"]),
               "configuration": {key: copy.deepcopy(value) for key, value in config.items() if key != "jobs"},
               "mask_parameters": copy.deepcopy(settings["mask"]), "qa_bounds": copy.deepcopy(settings["qa"]),
               "raw_cleanplate_normalization": {"source_path": spec["raw_cleanplate_path"], "native_size": inputs["raw_cleanplate"]["native_size"],
                                               "normalized_path": normalized_path, "normalized_size": list(normalized.size), "transform": normalization},
               "original_path": original_path, "base_path": base_path, "base_runtime_path": base_runtime,
               "artifacts": artifacts, "runtime_copies": runtime_copies, "layers": rows, "overlap_pairs": overlaps,
               "recomposition_qa": whole_qa, "geometry_passed": whole_qa["passed"] and all(row["single_layer_qa"]["passed"] for row in rows),
               "art_passed": False, "visual_review": "not_evaluated", "manifest_modified": False}
    if "state" in spec:
        receipt["state"] = spec["state"]
    # Thin registration fragments: the caller merges period/state variants and
    # the explicit legacy S04 slot, never overwriting the central manifest here.
    stem = f"{spec['scene_id']}_{suffix}_{spec['revision']}"
    common = {"status": "complete", "version": spec["revision"], "style_reference": spec["style_reference"],
              "attempts": [], "processing_script": SCRIPT, "qa_kind": "art", "generator": "real_C_pixel_extraction"}
    receipt["recipes"] = [{**common, "id": stem + "_base", "group": "scenes", "operation": "runtime_copy",
                           "prompt": spec["cleanplate_prompt"] + "\n" + config["processing_prompt"],
                           "source_path": base_path, "runtime_path": base_runtime}]
    descriptors = {}
    for row in rows:
        descriptor = copy.deepcopy(row["descriptor"])
        descriptor["variants"] = {spec["period"]: descriptor["path"]}
        descriptor["variant_transforms"] = {spec["period"]: descriptor["source_transform"]}
        if "state" in spec and row["id"].startswith("door_"):
            descriptor["state"] = spec["state"]
        descriptors[row["id"]] = descriptor
        receipt["recipes"].append({**common, "id": stem + "_" + row["id"], "group": "layers", "operation": "extract_layer",
                                   "prompt": config["processing_prompt"], "source_path": row["layer_path"],
                                   "runtime_path": row["descriptor"]["path"].removeprefix("res://"),
                                   "original_path": original_path, "mask_path": row["soft_mask_path"],
                                   "cleanplate_path": row["cleanplate_path"], "processing_parameters": copy.deepcopy(spec)})
    receipt["recompositions"] = [{"id": stem, "qa_kind": "art", "original_path": original_path,
                                  "base_path": base_path, "layers": [{"path": row["layer_path"], "z_index": row["z_index"]} for row in rows]}]
    receipt["scene_descriptors"] = {spec["scene_id"]: {"layer_format": "aligned_full_canvas", spec["period"]: "res://" + base_runtime, "layers": descriptors}}
    receipt_path = output + "/receipt.json"
    receipt["receipt_path"] = receipt_path
    blobs[receipt_path] = (json.dumps(receipt, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
    source_paths = {pipeline.safe_path(workspace, row["path"]) for row in inputs.values()}
    # Full byte preflight before any mutation. _write_new also uses exclusive
    # creation to catch races; rerunning identical inputs is idempotent.
    targets = {}
    for path, data in blobs.items():
        target = pipeline.safe_path(workspace, path)
        require(target not in source_paths, "output cannot overwrite an input")
        if target.exists() and (not target.is_file() or target.read_bytes() != data):
            raise FileExistsError("existing output is never overwritten: " + str(target))
        require(target not in targets, "resolved output paths collide")
        targets[target] = data
    for path, data in targets.items():
        pipeline._write_new(path, data)
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--config", default=str(CONFIG))
    parser.add_argument("--spec", help="one standalone scene/period/state JSON spec")
    parser.add_argument("--only", help="configured scene or scene:period")
    args = parser.parse_args(argv)
    config = load_config(args.config)
    jobs = [pipeline.read_json(pipeline.safe_path(args.workspace, args.spec, must_exist=True))] if args.spec else config["jobs"]
    if args.only:
        jobs = [job for job in jobs if args.only in (job["scene_id"], job["scene_id"] + ":" + job["period"])]
    require(jobs, "no matching real scene specs")
    all_passed = True
    for spec in jobs:
        result = process_scene(args.workspace, spec, config)
        print(json.dumps({"scene": result["scene_id"], "period": result["period"], "state": result.get("state"),
                          "geometry_passed": result["geometry_passed"], "receipt": result["receipt_path"],
                          "layers": len(result["layers"]), "overlap_pairs": len(result["overlap_pairs"])}, ensure_ascii=False))
        all_passed &= result["geometry_passed"]
    return 0 if all_passed else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, FileExistsError) as error:
        print("REAL SCENE LAYERS: " + str(error), file=sys.stderr)
        raise SystemExit(2)
