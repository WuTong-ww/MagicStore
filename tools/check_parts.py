"""Actual A4 raster checks. A technical pass never signs visual art approval."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline as common

CONFIG = ROOT / "data/art/portrait_pipeline.json"


def require(value, message):
    if not value:
        raise ValueError(message)


def rectangle(value, canvas):
    return (isinstance(value, list) and len(value) == 4 and all(type(n) is int for n in value)
            and 0 <= value[0] < value[2] <= canvas[0] and 0 <= value[1] < value[3] <= canvas[1])


def validate_config(config):
    require(isinstance(config, dict) and config.get("version") == 1 and
            config.get("kind") == "A4_v3_modular_portrait_pipeline", "invalid portrait config")
    require(config.get("canvas") == [768, 1024], "portrait canvas must be 768x1024")
    qa = config.get("qa", {})
    for key in ("visible_alpha_threshold", "minimum_foreground_pixels", "minimum_transparent_pixels", "minimum_roi_pixels",
                "maximum_gray_channel_spread", "maximum_non_gray_pixels", "maximum_outside_mask_pixels"):
        require(type(qa.get(key)) is int and qa[key] >= 0, "invalid portrait QA: " + key)
    require(qa["visible_alpha_threshold"] < 255 and all(qa[k] > 0 for k in
            ("minimum_foreground_pixels", "minimum_transparent_pixels", "minimum_roi_pixels")), "empty portrait QA gate")
    require(all(qa[k] == 0 for k in ("maximum_gray_channel_spread", "maximum_non_gray_pixels", "maximum_outside_mask_pixels")),
            "formal portraits require exact grayscale and no region leakage")
    require(isinstance(config.get("regions"), dict) and config["regions"], "missing portrait regions")
    for name, region in config["regions"].items():
        require(isinstance(name, str) and isinstance(region, dict), "invalid portrait region")
        shape = region.get("shape", {})
        require(isinstance(shape, dict) and set(shape) in ({"rect"}, {"polygon"}), "invalid region shape")
        if "rect" in shape:
            require(rectangle(shape["rect"], config["canvas"]), "invalid region rectangle")
        else:
            polygon = shape["polygon"]
            require(isinstance(polygon, list) and len(polygon) >= 3 and all(isinstance(p, list) and len(p) == 2
                    and all(type(n) is int for n in p) and 0 <= p[0] < config["canvas"][0] and 0 <= p[1] < config["canvas"][1]
                    for p in polygon), "invalid region polygon")
        require(region.get("review_status") in ("root_coordinates", "reviewed", "provisional"), "missing mask review state")
        require(isinstance(region.get("required_rois"), list) and region["required_rois"] and
                all(rectangle(roi, config["canvas"]) for roi in region["required_rois"]), "invalid anchor ROI")
    require(isinstance(config.get("assets"), list) and config["assets"], "missing portrait identities")
    ids = set()
    for row in config["assets"]:
        require(isinstance(row, dict) and isinstance(row.get("id"), str) and row["id"] not in ids and
                row.get("region") in config["regions"], "invalid/duplicate portrait identity")
        ids.add(row["id"])
    processing = config.get("processing",{})
    require(isinstance(processing,dict) and type(processing.get("prevent_core_clipping",False)) is bool, "invalid source core clipping policy")
    if processing.get("prevent_core_clipping",False):
        require(type(processing.get("source_core_alpha_threshold")) is int and processing["source_core_alpha_threshold"]==128, "invalid source core threshold")
    overrides = processing.get("region_overrides",{})
    require(isinstance(overrides,dict), "invalid source-specific processing regions")
    for asset_id,rule in overrides.items():
        require(asset_id in ids and isinstance(rule,dict) and isinstance(rule.get("region"),str) and rule["region"] in config["regions"] and
                rule.get("reviewed_isolated") is True and isinstance(rule.get("reviewed_source_sha256"),str) and
                len(rule["reviewed_source_sha256"])==64 and all(c in "0123456789abcdef" for c in rule["reviewed_source_sha256"]),
                "processing region requires an exact reviewed source")
    return config


def load_config(path=CONFIG):
    return validate_config(common.read_json(path))


def mask_image(config, region_name):
    region = config["regions"][region_name]
    image = Image.new("L", tuple(config["canvas"]), 0)
    draw = ImageDraw.Draw(image)
    shape = region["shape"]
    if "rect" in shape:
        x0, y0, x1, y1 = shape["rect"]
        draw.rectangle((x0, y0, x1 - 1, y1 - 1), fill=255)
    else:
        draw.polygon([tuple(p) for p in shape["polygon"]], fill=255)
    return image


def processing_mask(config, row):
    override = config.get("processing",{}).get("region_overrides",{}).get(row["id"])
    return mask_image(config,override["region"] if override else row["region"])


def report_image(image, asset_id, config, *, actual_format="PNG", actual_mode=None):
    config = validate_config(config)
    if asset_id == "mannequin":
        return report_reference(image, config, actual_format=actual_format, actual_mode=actual_mode)
    found = [x for x in config["assets"] if x["id"] == asset_id]
    require(len(found) == 1, "unknown portrait asset ID: " + str(asset_id))
    row = found[0]
    qa = config["qa"]
    errors = []
    if actual_format != "PNG": errors.append("not_actual_png")
    if (actual_mode or image.mode) != "RGBA": errors.append("not_rgba")
    if list(image.size) != config["canvas"]: errors.append("canvas_mismatch")
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    hist = alpha.histogram()
    foreground = sum(hist[qa["visible_alpha_threshold"] + 1:])
    transparent = hist[0]
    if foreground < qa["minimum_foreground_pixels"]: errors.append("empty_or_too_small_foreground")
    if transparent < qa["minimum_transparent_pixels"]: errors.append("missing_transparency")
    non_gray = 0
    maximum_spread = 0
    for red, green, blue, opacity in rgba.getdata():
        if opacity > qa["visible_alpha_threshold"]:
            spread = max(red, green, blue) - min(red, green, blue)
            maximum_spread = max(maximum_spread, spread)
            non_gray += spread > qa["maximum_gray_channel_spread"]
    if non_gray > qa["maximum_non_gray_pixels"]: errors.append("non_gray_pixels")
    mask = processing_mask(config, row)
    outside = sum(opacity > 0 and allowed == 0 for opacity, allowed in zip(alpha.getdata(), mask.getdata())) if rgba.size == mask.size else None
    if outside is not None and outside > qa["maximum_outside_mask_pixels"]: errors.append("outside_authorized_region")
    rois = []
    for roi in config["regions"][row["region"]]["required_rois"]:
        rois.append(sum(alpha.crop(tuple(roi)).histogram()[qa["visible_alpha_threshold"] + 1:]))
    if any(n < qa["minimum_roi_pixels"] for n in rois): errors.append("missing_category_anchor_pixels")
    report = {"id": asset_id, "category": row["category"], "part_id": row["part_id"], "mood": row["mood"],
            "passed": not errors, "art_passed": False, "errors": errors, "size": list(image.size),
            "mode": actual_mode or image.mode, "actual_format": actual_format, "foreground_pixels": foreground,
            "transparent_pixels": transparent, "feather_pixels": sum(hist[1:255]), "non_gray_pixels": non_gray,
            "maximum_rgb_channel_spread": maximum_spread, "outside_mask_pixels": outside, "roi_pixels": rois,
            "region": row["region"], "alpha_bbox": list(alpha.getbbox()) if alpha.getbbox() else None,
            "review_scope": "真实像素/锚点区域技术检查，不证明部件内容、风格、接缝或人物辨识美术通过。"}
    override = config.get("processing",{}).get("region_overrides",{}).get(asset_id)
    if override:
        report.update(generation_region=row["region"],processing_region=override["region"],region=override["region"])
    return report


def report_reference(image, config, *, actual_format="PNG", actual_mode=None):
    errors = []
    if actual_format != "PNG": errors.append("not_actual_png")
    if list(image.size) != config["canvas"]: errors.append("canvas_mismatch")
    if (actual_mode or image.mode) != "RGB": errors.append("mannequin_reference_must_be_rgb_magenta")
    foreground = Image.new("L", image.size)
    pixels = []
    spread = 0
    background = 0
    for red, green, blue in image.convert("RGB").getdata():
        keyed = (red + blue) / 2.0 - green >= config["processing"]["key_full_removal_excess"]
        background += keyed
        pixels.append(0 if keyed else 255)
        if not keyed: spread = max(spread, max(red, green, blue) - min(red, green, blue))
    foreground.putdata(pixels)
    roi_pixels = [sum(foreground.crop(tuple(roi)).histogram()[1:]) for roi in config["regions"]["mannequin"]["required_rois"]]
    if background < config["processing"]["key_minimum_background_pixels"]: errors.append("reference_missing_magenta_background")
    if any(n < config["qa"]["minimum_roi_pixels"] for n in roi_pixels): errors.append("missing_reference_anchor_pixels")
    return {"id":"mannequin","passed":not errors,"art_passed":False,"errors":errors,"size":list(image.size),
            "mode":actual_mode or image.mode,"reference_background":"magenta","transparent_asset":False,
            "background_pixels":background,"roi_pixels":roi_pixels,"maximum_rgb_channel_spread":spread,
            "strict_grayscale":spread == 0,"review_scope":"已选RGB/magenta位置基准；如实记录原色差，不冒充透明灰阶部件。"}


def check_part(workspace, asset_id, path, config=None):
    config = validate_config(config or load_config())
    file = common.safe_path(workspace, path)
    if not file.is_file():
        return {"id": asset_id, "path": path, "passed": False, "art_passed": False, "errors": ["missing_file"]}
    try:
        with Image.open(file) as source:
            source.load()
            report = report_image(source, asset_id, config, actual_format=source.format, actual_mode=source.mode)
    except (OSError, SyntaxError) as error:
        return {"id": asset_id, "path": path, "passed": False, "art_passed": False, "errors": ["invalid_image"], "detail": str(error)}
    return {**report, "path": path, "sha256": common.sha256(file), "bytes": file.stat().st_size}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--config", default="data/art/portrait_pipeline.json")
    parser.add_argument("--id", required=True)
    parser.add_argument("--path", required=True)
    args = parser.parse_args(argv)
    try:
        config = load_config(common.safe_path(args.workspace, args.config, must_exist=True))
        report = check_part(args.workspace, args.id, args.path, config)
        print(json.dumps(report, ensure_ascii=False))
        return 0 if report["passed"] else 1
    except ValueError as error:
        print(json.dumps({"passed": False, "error": str(error)}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
