"""A2R offline item processing; retained sources are never rewritten.

Only Pillow/stdlib. No generator, paid API, model call or production JSON write.
The receipt is a proposed manifest/config fragment, never visual art approval.
"""
from __future__ import annotations

import argparse
import colorsys
import copy
from fractions import Fraction
import hashlib
import io
import json
import math
from pathlib import Path
import re
import sys

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline as common

CONFIG = ROOT / "data/art/item_pipeline.json"
SCRIPT = "tools/art/item_pipeline.py"


def require(value, message):
    if not value:
        raise ValueError(message)


def integer(value, low, high):
    return type(value) is int and low <= value <= high


def number(value, low, high):
    return type(value) in (int, float) and math.isfinite(value) and low <= value <= high


def identifier(value):
    return isinstance(value, str) and re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]*", value) is not None


def _ranges(value):
    return isinstance(value, list) and bool(value) and all(isinstance(row, list) and len(row) == 2 and
        all(number(n, 0, 1) for n in row) and row[0] <= row[1] for row in value)


def validate_config(config):
    require(isinstance(config, dict) and type(config.get("version")) is int and config["version"] == 1 and
            config.get("kind") == "magenta_keyed_item_art", "invalid item pipeline version/kind")
    for field in ("source_root", "output_root"):
        common.safe_path(ROOT, config.get(field))
    require(config["source_root"].startswith("assets/_incoming/") and
            (config["output_root"] == "assets/items" or config["output_root"].startswith("assets/items/")) and
            not config["output_root"].startswith(config["source_root"] + "/") and
            not config["source_root"].startswith(config["output_root"] + "/") and
            config["source_root"] != config["output_root"], "source/output roots must be separate designated item directories")
    ids = config.get("required_ids")
    require(isinstance(ids, list) and ids and all(identifier(n) for n in ids) and len(set(ids)) == len(ids), "invalid required item IDs")
    require(integer(config.get("maximum_generation_attempts"), 1, 4), "invalid generation attempt cap")
    generation = config.get("generation", {})
    require(generation.get("tool") == "image_gen.imagegen", "only the session builtin image generator is allowed")
    for field in ("target_size_prompt", "not_callable_message"):
        require(isinstance(generation.get(field), str) and generation[field].strip(), "missing builtin generation explanation")
    for field in ("runtime_size", "icon_size"):
        size = config.get(field)
        require(isinstance(size, list) and len(size) == 2 and all(integer(n, 1, 4096) for n in size) and size[0] == size[1], "invalid " + field)
    require(config["runtime_size"][0] > config["icon_size"][0], "icon must be derived smaller than runtime")
    for group in ("layout", "color_key", "mask", "icon", "alpha_qa", "support"):
        require(isinstance(config.get(group), dict), "invalid parameter object: " + group)
    layout = config.get("layout", {})
    for field in ("maximum_width_fraction", "maximum_height_fraction"):
        require(number(layout.get(field), 0.01, 1), "invalid layout " + field)
    require(integer(layout.get("bottom_margin_pixels"), 0, config["runtime_size"][1] - 1), "invalid bottom margin")
    key = config.get("color_key", {})
    require(_ranges(key.get("hue_ranges")), "invalid key hue ranges")
    for field in ("minimum_saturation", "minimum_value"):
        require(number(key.get(field), 0, 1), "invalid key " + field)
    mask = config.get("mask", {})
    for field in ("erode_pixels", "feather_pixels", "color_bleed_pixels"):
        require(integer(mask.get(field), 0, 16), "invalid mask " + field)
    require(integer(mask.get("color_seed_alpha"), 1, 255), "invalid mask color seed alpha")
    require(mask["color_bleed_pixels"] >= mask["feather_pixels"], "edge color bleed must cover feather radius")
    icon = config.get("icon", {})
    require(integer(icon.get("outline_radius_pixels"), 0, 8) and number(icon.get("outline_darkening_fraction"), 0, 1), "invalid icon contour parameters")
    require(integer(icon.get("color_bleed_pixels"), 0, 16) and integer(icon.get("color_seed_alpha"), 1, 255), "invalid icon edge color parameters")
    qa = config.get("alpha_qa", {})
    require(_ranges(qa.get("red_yellow_hue_ranges")) and _ranges(qa.get("magenta_hue_ranges")), "invalid alpha QA hue ranges")
    for field in ("saturation_threshold", "maximum_bad_edge_fraction", "magenta_minimum_value"):
        require(number(qa.get(field), 0, 1), "invalid alpha QA " + field)
    require(integer(qa.get("maximum_visible_magenta_pixels"), 0, 4096) and type(qa.get("require_transparent_pixels")) is bool, "invalid alpha QA transparency parameters")
    support = config.get("support", {})
    require(integer(support.get("alpha_threshold"), 1, 255) and integer(support.get("contact_band_rows"), 1, config["runtime_size"][1]) and
            integer(support.get("maximum_bottom_gap_pixels"), 0, config["runtime_size"][1] - 1) and
            integer(support.get("minimum_bottom_width_pixels"), 1, config["runtime_size"][0]), "invalid support parameters")
    require(layout["bottom_margin_pixels"] <= support["maximum_bottom_gap_pixels"], "requested bottom margin exceeds support allowance")
    for text in (config.get("processing_prompt"), support.get("semantics")):
        require(isinstance(text, str) and text.strip(), "missing processing/support explanation")
    return config


def load_config(path=CONFIG):
    return validate_config(common.read_json(path))


def _in_ranges(hue, ranges):
    return any(low <= hue <= high for low, high in ranges)


def alpha_report(image, config=None):
    """Hue ratios use only 0<alpha<255. Exactly the configured limit passes."""
    config = validate_config(config or load_config())
    qa = config["alpha_qa"]
    has_alpha = "A" in image.getbands() or image.mode == "P" and "transparency" in image.info
    rgba = image.convert("RGBA")
    edge = bad = magenta = visible = transparent = 0
    for red, green, blue, alpha in rgba.getdata():
        transparent += alpha == 0
        visible += alpha > 0
        if alpha == 0:
            continue
        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        if saturation > qa["saturation_threshold"] and value >= qa["magenta_minimum_value"] and _in_ranges(hue, qa["magenta_hue_ranges"]):
            magenta += 1
        if alpha < 255:
            edge += 1
            bad += saturation > qa["saturation_threshold"] and _in_ranges(hue, qa["red_yellow_hue_ranges"])
    fraction = Fraction(str(qa["maximum_bad_edge_fraction"]))
    errors = []
    if not has_alpha: errors.append("missing_alpha_channel")
    if not visible: errors.append("empty_image")
    if qa["require_transparent_pixels"] and not transparent: errors.append("no_transparent_pixels")
    if bad * fraction.denominator > edge * fraction.numerator: errors.append("red_yellow_edge_fraction_exceeds_limit")
    if magenta > qa["maximum_visible_magenta_pixels"]: errors.append("visible_magenta_residue")
    return {"passed": not errors, "errors": errors, "size": list(image.size), "has_alpha": has_alpha,
            "visible_pixels": visible, "transparent_pixels": transparent, "edge_pixels": edge,
            "red_yellow_pixels": bad, "red_yellow_fraction": bad / edge if edge else 0,
            "magenta_pixels": magenta, "edge_denominator": "pixels with 0 < alpha < 255",
            "limits": copy.deepcopy(qa)}


def measure_support(image, config=None):
    config = validate_config(config or load_config())
    support = config["support"]
    alpha = image.convert("RGBA").getchannel("A")
    hard = alpha.point(lambda n: 255 if n >= support["alpha_threshold"] else 0)
    box = hard.getbbox()
    require(box is not None, "item has no opaque support pixels")
    bottom = box[3] - 1
    first_row = max(0, bottom - support["contact_band_rows"] + 1)
    band = hard.crop((0, first_row, image.width, bottom + 1)).getbbox()
    require(band is not None, "item contact band is empty")
    return {"bbox": list(box), "alpha_bbox": list(alpha.getbbox()), "bottom_y": bottom,
            "bottom_left": band[0], "bottom_width": band[2] - band[0],
            "alpha_threshold": support["alpha_threshold"], "contact_band_rows": support["contact_band_rows"]}


def _bleed_colors(image, alpha, radius, seed_alpha):
    original = image.convert("RGBA")
    pixels = original.load()
    target = alpha.load()
    result = Image.new("RGBA", image.size)
    output = result.load()
    offsets = sorted(((x*x+y*y, x, y) for x in range(-radius, radius+1) for y in range(-radius, radius+1)), key=lambda row: row[0])
    for y in range(image.height):
        for x in range(image.width):
            if not target[x, y]:
                continue
            color = pixels[x, y][:3]
            # Lanczos premultiply/unpremultiply byte quantization can turn
            # tiny-alpha muted colors into saturated RGB. Extend nearby
            # substantial foreground colors, without selecting hue or
            # changing the alpha mask, instead of ignoring those pixels.
            if pixels[x, y][3] < seed_alpha:
                for _distance, dx, dy in offsets:
                    nx, ny = x+dx, y+dy
                    if 0 <= nx < image.width and 0 <= ny < image.height and pixels[nx, ny][3] >= seed_alpha:
                        color = pixels[nx, ny][:3]
                        break
            output[x, y] = (*color, target[x, y])
    return result


def process_source(source, config=None):
    config = validate_config(config or load_config())
    key = config["color_key"]
    rgba = source.convert("RGBA")
    cleaned = []
    removed = 0
    for red, green, blue, alpha in rgba.getdata():
        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        keyed = saturation >= key["minimum_saturation"] and value >= key["minimum_value"] and _in_ranges(hue, key["hue_ranges"])
        removed += bool(keyed and alpha)
        cleaned.append((0, 0, 0, 0) if keyed or alpha == 0 else (red, green, blue, alpha))
    require(removed > 0, "source has no declared magenta background")
    rgba.putdata(cleaned)
    crop = rgba.getchannel("A").getbbox()
    require(crop is not None, "magenta removal left an empty item")
    foreground = rgba.crop(crop)
    size = config["runtime_size"]
    layout = config["layout"]
    scale = min(size[0] * layout["maximum_width_fraction"] / foreground.width,
                size[1] * layout["maximum_height_fraction"] / foreground.height)
    dimensions = [max(1, int(math.floor(n * scale + 0.5))) for n in foreground.size]
    resized = foreground.resize(dimensions, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size)
    position = [(size[0] - dimensions[0]) // 2, (size[1] - dimensions[1]) // 2]
    canvas.paste(resized, tuple(position))  # Pillow may expand a mutable box in place.
    alpha = canvas.getchannel("A")
    mask = config["mask"]
    if mask["erode_pixels"]:
        alpha = alpha.filter(ImageFilter.MinFilter(mask["erode_pixels"] * 2 + 1))
    if mask["feather_pixels"]:
        alpha = alpha.filter(ImageFilter.GaussianBlur(mask["feather_pixels"]))
    canvas = _bleed_colors(canvas, alpha, mask["color_bleed_pixels"], mask["color_seed_alpha"])
    bottom = measure_support(canvas, config)["bottom_y"]
    shift = size[1] - 1 - layout["bottom_margin_pixels"] - bottom
    shifted = Image.new("RGBA", size)
    shifted.paste(canvas, (0, shift))
    position[1] += shift
    transform = {"method": "magenta_key_contain_erode_feather", "filter": "Lanczos",
                 "source_crop": list(crop), "object_resized_size": dimensions, "nominal_scale": scale,
                 "paste_xy": position, "runtime_size": list(size), "mask": copy.deepcopy(mask),
                 "color_key": copy.deepcopy(key), "support_alignment": copy.deepcopy(layout)}
    return shifted, transform


def make_icon(image, config=None):
    config = validate_config(config or load_config())
    icon = image.convert("RGBA").resize(config["icon_size"], Image.Resampling.LANCZOS)
    radius = config["icon"]["outline_radius_pixels"]
    alpha = icon.getchannel("A")
    icon = _bleed_colors(icon, alpha, config["icon"]["color_bleed_pixels"], config["icon"]["color_seed_alpha"])
    inner = alpha.filter(ImageFilter.MinFilter(radius * 2 + 1)) if radius else alpha
    contour = ImageChops.subtract(alpha, inner)
    strength = config["icon"]["outline_darkening_fraction"]
    icon.putdata([(int(round(r * (1-strength*c/255))), int(round(g * (1-strength*c/255))),
                   int(round(b * (1-strength*c/255))), a) if a else (0, 0, 0, 0)
                  for (r, g, b, a), c in zip(icon.getdata(), contour.getdata())])
    return icon


def _status(value):
    aliases = {"selected": "complete", "success": "complete", "failed": "generation_failed"}
    return aliases.get(value, value) if isinstance(value, str) else None


def _hash(value):
    return isinstance(value, str) and re.fullmatch(r"[a-fA-F0-9]{64}", value) is not None


def _actual_image(workspace, path, digest=None, size=None):
    resolved = common.safe_path(workspace, path, must_exist=True)
    image = common.read_image(resolved)
    if digest is not None: require(_hash(digest) and common.sha256(resolved) == digest.lower(), "source sha256 mismatch: " + path)
    if size is not None: require(isinstance(size, list) and all(type(n) is int for n in size) and list(image.size) == size, "source native size mismatch: " + path)
    return image


def validate_generation_receipt(workspace, receipt, config=None):
    config = validate_config(config or load_config())
    require(isinstance(receipt, dict) and type(receipt.get("version")) is int and receipt["version"] == 1, "invalid item generation receipt")
    style = receipt.get("style_reference")
    _actual_image(workspace, style, receipt.get("style_sha256"))
    require(_hash(receipt.get("style_sha256")), "style sha256 is required")
    rows = receipt.get("records")
    require(isinstance(rows, list) and rows, "item generation receipt requires records")
    ids, sources = set(), set()
    source_root = common.safe_path(workspace, config["source_root"])
    for row in rows:
        require(isinstance(row, dict) and row.get("id") in config["required_ids"] and row["id"] not in ids, "unknown or duplicate item ID")
        ids.add(row["id"])
        source = common.safe_path(workspace, row.get("source_path"))
        require(source.is_relative_to(source_root) and source != source_root and source not in sources, "source must be unique retained A2R original")
        sources.add(source)
        require(isinstance(row.get("prompt"), str) and row["prompt"].strip(), "missing item generation prompt")
        references = row.get("ref_paths")
        require(isinstance(references, list) and all(isinstance(ref, str) for ref in references) and
                style in references and len(set(references)) == len(references), "actual references must include selected style")
        for ref in references: _actual_image(workspace, ref)
        attempts = row.get("attempts")
        require(isinstance(attempts, list) and 1 <= len(attempts) <= config["maximum_generation_attempts"], "invalid item generation attempts")
        numbers = set()
        successful_hashes = set()
        for attempt in attempts:
            require(isinstance(attempt, dict) and integer(attempt.get("attempt"), 1, config["maximum_generation_attempts"]) and attempt["attempt"] not in numbers and
                    _status(attempt.get("status")) in ("complete", "generation_failed"), "invalid generation attempt")
            numbers.add(attempt["attempt"])
            if _status(attempt["status"]) == "complete":
                require(isinstance(attempt.get("output_path"), str) and attempt["output_path"],
                        "successful attempt requires a retained output_path")
                require(_hash(attempt.get("sha256")) and "native_size" in attempt, "successful attempt requires actual hash/dimensions")
                _actual_image(workspace, attempt["output_path"], attempt["sha256"], attempt["native_size"])
                successful_hashes.add(attempt["sha256"].lower())
            elif attempt.get("output_path"):
                common.safe_path(workspace, attempt["output_path"])
        status = _status(row.get("status"))
        require(status in ("complete", "generation_failed", "needs_builtin_generation", "placeholder"), "invalid item generation state")
        if status in ("complete", "placeholder"):
            require(status == "placeholder" or any(_status(attempt["status"]) == "complete" for attempt in attempts), "completed item requires a successful generation attempt")
            require(_hash(row.get("sha256")) and "native_size" in row, "completed item requires actual source hash/dimensions")
            _actual_image(workspace, row["source_path"], row["sha256"], row["native_size"])
            require(not successful_hashes or row["sha256"].lower() in successful_hashes, "selected item does not match retained successful attempt")
    return receipt


def _png(image):
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    return stream.getvalue()


def _digest(data):
    return hashlib.sha256(data).hexdigest()


def _json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def _prepare(workspace, generation, config, revision, only):
    validate_generation_receipt(workspace, generation, config)
    require(not revision or identifier(revision), "revision must be a single safe identifier")
    selected = set(only or [row["id"] for row in generation["records"]])
    require(selected and selected <= set(config["required_ids"]), "unknown item selection")
    rows = [row for row in generation["records"] if row["id"] in selected]
    require({row["id"] for row in rows} == selected, "selected item lacks generation record")
    output_root = config["output_root"] + ("/" + revision if revision else "")
    prepared, pending = [], []
    for row in rows:
        if _status(row["status"]) not in ("complete", "placeholder"):
            pending.append({"id": row["id"], "status": "needs_builtin_generation", "source_status": row["status"], "prompt": row["prompt"], "ref_paths": row["ref_paths"]})
            continue
        source = _actual_image(workspace, row["source_path"], row["sha256"], row["native_size"])
        main, transform = process_source(source, config)
        icon = make_icon(main, config)
        support = measure_support(main, config)
        reports = {"runtime": alpha_report(main, config), "icon": alpha_report(icon, config)}
        require(all(report["passed"] for report in reports.values()), "item alpha QA failed: " + row["id"] + " " + json.dumps(reports))
        require(main.height - 1 - support["bottom_y"] <= config["support"]["maximum_bottom_gap_pixels"] and
                support["bottom_width"] >= config["support"]["minimum_bottom_width_pixels"], "item bottom support does not meet configured bounds")
        main_path, icon_path = output_root + "/" + row["id"] + ".png", output_root + "/" + row["id"] + "_64.png"
        main_bytes, icon_bytes = _png(main), _png(icon)
        entry = {"item_id": row["id"], "version": 3, "source": "procedural_placeholder" if _status(row["status"]) == "placeholder" else "builtin_imagegen",
                 "reference": "res://" + generation["style_reference"], "path": "res://" + main_path, "icon_path": "res://" + icon_path,
                 "size": list(main.size), "icon_size": list(icon.size), **support, "sha256": _digest(main_bytes),
                 "icon_sha256": _digest(icon_bytes), "source_runtime_sha256": _digest(main_bytes),
                 "source_path": row["source_path"], "source_sha256": row["sha256"].lower(), "source_native_size": list(source.size)}
        prepared.append({"row": row, "entry": entry, "main_bytes": main_bytes, "icon_bytes": icon_bytes, "transform": transform,
                         "reports": reports, "main_path": main_path, "icon_path": icon_path})
    return prepared, pending


def process_items(workspace, generation, revision="", only=None, config=None):
    config = validate_config(config or load_config())
    prepared, pending = _prepare(workspace, generation, config, revision, only)
    # Validate every collision before writing any output. Existing bytes are
    # idempotent; different bytes require a new explicit revision directory.
    outputs = [(row[field + "_path"], row[field + "_bytes"]) for row in prepared for field in ("main", "icon")]
    protected = {common.safe_path(workspace, row["source_path"]) for row in generation["records"]}
    protected |= {common.safe_path(workspace, ref) for row in generation["records"] for ref in row["ref_paths"]}
    for path, data in outputs:
        target = common.safe_path(workspace, path)
        require(target not in protected, "output cannot overwrite a source or style reference")
        require(not target.exists() or target.is_file() and target.read_bytes() == data, "immutable output already exists with different bytes: " + path)
    for path, data in outputs: common._write_new(common.safe_path(workspace, path), data)
    return _receipt_from_prepared(generation, config, revision, only, prepared, pending)


def _receipt_from_prepared(generation, config, revision, only, prepared, pending):
    entries, runtime, recipes, checks = {}, [], [], {}
    for row in prepared:
        entry, original = row["entry"], row["row"]
        item_id = original["id"]
        entries[item_id] = entry
        checks[item_id] = row["reports"]
        runtime.append({"path": row["main_path"], "source_path": original["source_path"], "native_size": original["native_size"],
                        "runtime_size": config["runtime_size"], "sha256": entry["sha256"], "source_sha256": entry["source_sha256"],
                        "method": row["transform"]["method"], "transform": row["transform"]})
        runtime.append({"path": row["icon_path"], "source_path": row["main_path"], "native_size": config["runtime_size"],
                        "runtime_size": config["icon_size"], "sha256": entry["icon_sha256"], "source_sha256": entry["sha256"],
                        "method": "Lanczos_with_contour_darkening", "transform": copy.deepcopy(config["icon"])})
        recipes.append({"id": "A2R_" + item_id + ("_" + revision if revision else ""), "group": "items", "version": 1,
                        "prompt": original["prompt"], "style_reference": generation["style_reference"], "source_path": original["source_path"],
                        "runtime_path": row["main_path"], "operation": "runtime_copy", "status": "placeholder" if entry["source"] == "procedural_placeholder" else "complete",
                        "attempts": original["attempts"], "processing_script": SCRIPT, "processing_parameters": copy.deepcopy(config),
                        "reference_paths": original["ref_paths"], "source_sha256": entry["source_sha256"], "runtime_sha256": entry["sha256"]})
    return {"version": 1, "kind": "processed_item_art", "status": "needs_builtin_generation" if pending else "complete",
            "revision": revision, "selection": [row["id"] for row in generation["records"] if row["id"] in set(only or [r["id"] for r in generation["records"]])],
            "generation_receipt": copy.deepcopy(generation), "processing_config": copy.deepcopy(config), "processing_script": SCRIPT,
            "item_entries": entries, "runtime_copies": runtime, "recipes": recipes, "alpha_checks": checks, "pending": pending,
            "manifest_modified": False, "art_passed": False, "visual_review": "not_evaluated",
            "support_semantics": config["support"]["semantics"]}


def validate_processing_receipt(workspace, receipt, config=None, *, _check_fragment=True):
    require(isinstance(receipt, dict) and receipt.get("version") == 1 and receipt.get("kind") == "processed_item_art", "invalid processed item receipt")
    registered = validate_config(receipt.get("processing_config"))
    require(registered == validate_config(config or load_config()), "processing parameters differ from requested contract")
    prepared, pending = _prepare(workspace, receipt.get("generation_receipt"), registered, receipt.get("revision", ""), receipt.get("selection"))
    expected = _receipt_from_prepared(receipt["generation_receipt"], registered, receipt.get("revision", ""), receipt.get("selection"), prepared, pending)
    for field, value in expected.items():
        require(receipt.get(field) == value, "processed receipt field differs from source derivation: " + field)
    require(receipt.get("pending") == pending and set(receipt.get("item_entries", {})) == {row["row"]["id"] for row in prepared}, "processing status/item coverage mismatch")
    require(receipt.get("status") == ("needs_builtin_generation" if pending else "complete") and receipt.get("art_passed") is False and receipt.get("manifest_modified") is False, "processing cannot approve art or modify production manifest")
    expected_copies = []
    for row in prepared:
        item_id = row["row"]["id"]
        require(receipt["item_entries"][item_id] == row["entry"], "measured item metadata differs from retained source pixels")
        for field in ("main", "icon"):
            path = common.safe_path(workspace, row[field + "_path"], must_exist=True)
            require(path.read_bytes() == row[field + "_bytes"], "runtime pixels/hash are not the declared source derivation")
        expected_copies += [row["main_path"], row["icon_path"]]
    copies = receipt.get("runtime_copies")
    require(isinstance(copies, list) and [row.get("path") for row in copies] == expected_copies, "runtime copy coverage/order mismatch")
    for record in copies:
        image = _actual_image(workspace, record["path"], record.get("sha256"), record.get("runtime_size"))
        source = _actual_image(workspace, record.get("source_path"), record.get("source_sha256"), record.get("native_size"))
        require(bool(image) and bool(source), "missing runtime/source image")
    if _check_fragment and "manifest_fragment" in receipt:
        validate_manifest_fragment(workspace, receipt["manifest_fragment"], processing_receipt=receipt)
    return True


def build_manifest_fragment(workspace, receipt, generation_receipt_path, processing_receipt_path):
    """Keep items out of the landscape-only round2_art section."""
    generation_path = common.safe_path(workspace, generation_receipt_path, must_exist=True)
    processing_path = common.safe_path(workspace, processing_receipt_path)
    require(generation_path != processing_path and processing_path.suffix == ".json", "processing receipt must be a separate JSON output")
    require(common.read_json(generation_path) == receipt["generation_receipt"], "generation receipt changed during processing; rerun the selected snapshot")
    config_relative = "data/art/item_pipeline.json"
    config_path = common.safe_path(workspace, config_relative, must_exist=True)
    require(load_config(config_path) == receipt["processing_config"], "registered item config is not the processing contract")
    script = common.safe_path(workspace, SCRIPT, must_exist=True)
    generation = receipt["generation_receipt"]
    required = receipt["processing_config"]["required_ids"]
    coverage = {"required": list(required), "processed": list(receipt["item_entries"]),
                "complete": set(receipt["item_entries"]) == set(required)}
    return {"round2_items": {"version": 1, "status": receipt["status"], "coverage": coverage,
        "generation_receipt": generation_receipt_path, "generation_receipt_sha256": common.sha256(generation_path),
        "processing_receipt": processing_receipt_path,
        "active_style": {"path": generation["style_reference"], "sha256": generation["style_sha256"].lower(), "status": "complete"},
        "processing_script": SCRIPT, "processing_script_sha256": common.sha256(script),
        "processing_config_path": config_relative, "processing_config_sha256": common.sha256(config_path),
        "item_entries": copy.deepcopy(receipt["item_entries"]), "recipes": copy.deepcopy(receipt["recipes"]),
        "runtime_copies": copy.deepcopy(receipt["runtime_copies"]), "art_passed": False,
        "support_semantics": receipt["support_semantics"]}}


def validate_manifest_fragment(workspace, fragment, *, processing_receipt=None):
    require(isinstance(fragment, dict) and isinstance(fragment.get("round2_items"), dict), "round2_items fragment is required")
    section = fragment["round2_items"]
    processing_path = common.safe_path(workspace, section.get("processing_receipt"), must_exist=processing_receipt is None)
    receipt = processing_receipt if processing_receipt is not None else common.read_json(processing_path)
    validate_processing_receipt(workspace, receipt, _check_fragment=False)
    expected = build_manifest_fragment(workspace, receipt, section.get("generation_receipt"), section.get("processing_receipt"))
    require(fragment == expected, "item manifest fragment differs from verified sources/runtime pixels")
    return True


def build_queue(workspace, generation, style, revision="", only=None, config=None):
    """A new style creates real builtin tasks, never relabels existing bytes."""
    config = validate_config(config or load_config())
    validate_generation_receipt(workspace, generation, config)
    style = common.relative_input(workspace, style)
    _actual_image(workspace, style)
    digest = common.sha256(common.safe_path(workspace, style, must_exist=True))
    revision = revision or "style_" + digest[:12]
    require(identifier(revision), "generation revision must be a safe single identifier")
    selected = set(only or [row["id"] for row in generation["records"]])
    require(selected and selected <= set(config["required_ids"]), "unknown queued item selection")
    records = [row for row in generation["records"] if row["id"] in selected]
    require({row["id"] for row in records} == selected, "queued item lacks a registered prompt")
    tasks = []
    protected = {common.safe_path(workspace, row["source_path"]) for row in generation["records"]}
    for row in records:
        destination = config["source_root"] + "/" + revision + "/" + row["id"] + "_source.png"
        target = common.safe_path(workspace, destination)
        require(target not in protected and not target.exists(), "new generation destination is immutable/already exists; select another revision")
        references = list(dict.fromkeys(style if ref == generation["style_reference"] else ref for ref in row["ref_paths"]))
        if style not in references: references.insert(0, style)
        tasks.append({"id": row["id"], "group": "items", "tool": config["generation"]["tool"],
                      "status": "needs_builtin_generation", "prompt": row["prompt"], "ref_paths": references,
                      "source_destination": destination, "attempt_cap": config["maximum_generation_attempts"],
                      "target_size_prompt": config["generation"]["target_size_prompt"],
                      "old_source_path": row["source_path"], "old_source_status": row["status"]})
    return {"version": 1, "kind": "item_generation_queue", "status": "needs_builtin_generation",
            "style_reference": style, "style_sha256": digest, "revision": revision,
            "generation_receipt": copy.deepcopy(generation), "processing_config": copy.deepcopy(config),
            "selection": [row["id"] for row in records], "tasks": tasks, "manifest_modified": False, "art_passed": False,
            "generation_performed": False, "message": config["generation"]["not_callable_message"],
            "import_contract": "Retain each generated source at source_destination, then supply --receipt with the same records[] schema, selected style, actual prompts/ref_paths/attempts/native_size/SHA. Process using the same --revision; ImportMap is not supported."}


def validate_queue(workspace, queue):
    require(isinstance(queue, dict) and queue.get("kind") == "item_generation_queue", "invalid item builtin queue")
    require(queue.get("processing_config") == load_config(), "builtin queue differs from current item contract")
    expected = build_queue(workspace, queue.get("generation_receipt"), queue.get("style_reference"),
                           queue.get("revision"), queue.get("selection"), queue.get("processing_config"))
    for field, value in expected.items():
        require(queue.get(field) == value, "builtin queue field differs from registered generation recipe: " + field)
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--receipt", required=True, help="workspace-relative retained generation receipt")
    parser.add_argument("--output-receipt", default=".tools/a2r-item-processing.json")
    parser.add_argument("--revision", default="")
    parser.add_argument("--style", help="workspace-contained relative or absolute style reference")
    parser.add_argument("--queue-only", action="store_true", help="only write builtin tasks for new versioned sources")
    parser.add_argument("--only", help="comma-separated item IDs; default all records")
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args(argv)
    try:
        workspace = Path(args.workspace).resolve()
        input_path = common.safe_path(workspace, args.receipt, must_exist=True)
        payload = common.read_json(input_path)
        if args.validate_only:
            if payload.get("kind") == "item_generation_queue":
                validate_queue(workspace, payload)
            else:
                validate_processing_receipt(workspace, payload)
            print("A2R processed receipt: validated; no files written")
            return 0
        output = common.safe_path(workspace, args.output_receipt)
        require(output != input_path and output.suffix == ".json", "output receipt must be separate JSON, never a source image")
        config = load_config()
        validate_generation_receipt(workspace, payload, config)
        only = args.only.split(",") if args.only else None
        style = common.relative_input(workspace, args.style) if args.style else payload["style_reference"]
        _actual_image(workspace, style)
        style_changed = common.sha256(common.safe_path(workspace, style)) != payload["style_sha256"].lower()
        if args.queue_only or style_changed:
            result = build_queue(workspace, payload, style, args.revision, only, config)
            validate_queue(workspace, result)
            common._write_new(output, _json_bytes(result))
            print(json.dumps({"status": result["status"], "tasks": len(result["tasks"]), "receipt": args.output_receipt, "generation_performed": False}))
            return 2
        result = process_items(workspace, payload, args.revision, only, config)
        validate_processing_receipt(workspace, result)
        result["manifest_fragment"] = build_manifest_fragment(workspace, result, args.receipt, args.output_receipt)
        common._write_new(output, _json_bytes(result))
        validate_manifest_fragment(workspace, result["manifest_fragment"])
        print(json.dumps({"status": result["status"], "items": len(result["item_entries"]), "pending": len(result["pending"]), "receipt": args.output_receipt, "art_passed": False}))
        return 0 if not result["pending"] else 2
    except (ValueError, OSError) as error:
        print("A2R ITEM ERROR: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
