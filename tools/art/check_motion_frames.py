"""Audit actual production-water GPU RGBA readbacks without changing art assets."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline as pipeline


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def relative(value):
    require(isinstance(value, str), "path must be a string")
    return value.removeprefix("res://")


def config_valid(data):
    require(isinstance(data, dict) and data.get("version") == 1, "invalid preview configuration")
    require(isinstance(data.get("output_prefix"), str) and data["output_prefix"].startswith("res://.tools/art/a6/preview-round"), "preview evidence prefix missing")
    require(type(data.get("max_rounds")) is int and data["max_rounds"] > 0, "invalid capture round limit")
    require(data.get("periods") == ["day", "night"], "both actual water periods are required")
    require(isinstance(data.get("pixel"), dict), "pixel parameters missing")
    pixel = data["pixel"]
    require(pixel.get("scene_id") == "S07" and pixel.get("layer_id") == "water_mask", "production water identity required")
    require(pixel.get("texture_filter") == "linear", "actual feather validation requires LINEAR filtering")
    require(pixel.get("unshaded_control") is True, "same-filter original-alpha GPU control required")
    require(isinstance(pixel.get("viewport_size"), list) and len(pixel["viewport_size"]) == 2 and all(type(v) is int and v > 0 for v in pixel["viewport_size"]), "invalid GPU readback dimensions")
    require(pixel.get("transparent_alpha") == 0 and pixel.get("opaque_alpha") == 255 and pixel.get("feather_alpha_range") == [1, 254], "all byte alpha classes must be covered")
    for key in ("shore_radius_px", "minimum_opaque_changed_pixels", "difference_gain"):
        require(type(pixel.get(key)) is int and pixel[key] > 0, "invalid integer pixel criterion: " + key)
    require(number(pixel.get("loop_offset_seconds")) and pixel["loop_offset_seconds"] > 0, "invalid long-period offset")
    require(isinstance(data.get("capture_times_seconds"), list) and len(data["capture_times_seconds"]) == 2 and all(number(v) and v >= 0 for v in data["capture_times_seconds"]) and data["capture_times_seconds"][1] > data["capture_times_seconds"][0], "invalid explicit sample times")
    return data


def mask_count(mask):
    return mask.histogram()[255]


def classify(before, parameters):
    alpha = before.getchannel("A")
    transparent = alpha.point([255 if v == parameters["transparent_alpha"] else 0 for v in range(256)])
    lo, hi = parameters["feather_alpha_range"]
    feather = alpha.point([255 if lo <= v <= hi else 0 for v in range(256)])
    opaque = alpha.point([255 if v == parameters["opaque_alpha"] else 0 for v in range(256)])
    neighbor_min = alpha.filter(ImageFilter.MinFilter(2 * parameters["shore_radius_px"] + 1))
    boundary = neighbor_min.point([255 if v < parameters["opaque_alpha"] else 0 for v in range(256)])
    shore = ImageChops.multiply(opaque, boundary)
    interior = ImageChops.subtract(opaque, shore)
    return {"transparent": transparent, "feather": feather, "shore": shore, "interior": interior}


def compare(before, after, parameters, diff_path=None, *, require_motion=True):
    require(before.mode == after.mode == "RGBA" and before.size == after.size, "paired actual GPU images must be same-size RGBA")
    rgba_diff = ImageChops.difference(before, after)
    rgb = rgba_diff.convert("RGB")
    channels = rgb.split()
    largest = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
    changed = largest.point([0] + [255] * 255)
    masks = classify(before, parameters)
    regions = {}
    for name, mask in masks.items():
        regions[name] = {"pixels": mask_count(mask),
                         "rgb_changed_pixels": mask_count(ImageChops.multiply(changed, mask)),
                         "rgb_max_delta": ImageChops.multiply(largest, mask).getextrema()[1]}
    alpha_delta = rgba_diff.getchannel("A")
    errors = []
    if alpha_delta.getextrema()[1] != 0:
        errors.append("alpha_bytes_changed")
    for name in ("transparent", "feather", "shore", "interior"):
        if regions[name]["pixels"] == 0:
            errors.append("vacuous_" + name + "_region")
    for name in ("transparent", "feather", "shore"):
        if regions[name]["rgb_changed_pixels"]:
            errors.append(name + "_rgb_changed")
    if require_motion and regions["interior"]["rgb_changed_pixels"] < parameters["minimum_opaque_changed_pixels"]:
        errors.append("opaque_water_did_not_change")
    gain = parameters["difference_gain"]
    result = {"passed": not errors, "errors": errors, "size": list(before.size),
            "alpha_all_bytes_equal": before.getchannel("A").tobytes() == after.getchannel("A").tobytes(),
            "alpha_max_delta": alpha_delta.getextrema()[1], "regions": regions,
            "requires_internal_motion": require_motion}
    if diff_path is not None:
        display = rgb.point([min(255, value * gain) for value in range(256)] * 3)
        display.save(diff_path)
        result.update(difference_gain=gain, difference_sha256=digest(diff_path))
    return result


def protect_outputs(outputs, inputs):
    require(len(set(outputs)) == len(outputs), "audit output paths collide with one another")
    require(not set(outputs).intersection(inputs), "audit output collides with input evidence")


def audit(workspace, receipt_path, config_path, output_path):
    workspace = Path(workspace).resolve()
    config_file = pipeline.safe_path(workspace, relative(config_path), must_exist=True)
    config = config_valid(json.loads(config_file.read_text(encoding="utf-8")))
    receipt_file = pipeline.safe_path(workspace, relative(receipt_path), must_exist=True)
    destination = pipeline.safe_path(workspace, relative(output_path))
    protect_outputs([destination], {config_file, receipt_file})
    receipt = json.loads(receipt_file.read_text(encoding="utf-8"))
    require(receipt.get("version") == 1 and receipt.get("kind") == "production_motion_preview", "invalid production preview receipt")
    require(type(receipt.get("round")) is int and 1 <= receipt["round"] <= config["max_rounds"], "invalid actual capture round")
    round_directory = pipeline.safe_path(workspace, relative(config["output_prefix"])+str(receipt["round"]))
    require(receipt_file.parent == round_directory, "receipt must be inside its designated preview round")
    require(receipt.get("display") != "headless" and receipt.get("renderer") == "gl_compatibility", "actual Compatibility GPU readback required")
    require(receipt.get("config_sha256") == digest(config_file), "preview configuration changed after capture")
    require(receipt.get("protected_files_unchanged") is True, "capture did not preserve protected resource SHA")
    require(isinstance(receipt.get("protected_shas"), dict), "protected-source hashes must be a mapping")
    manifest = json.loads((workspace / "assets/ART_ASSET_MANIFEST.json").read_text(encoding="utf-8"))
    expected_protected = set(config["protected_paths"]) | {asset["path"] for asset in manifest["assets"]}
    require(set(receipt.get("protected_shas", {})) == expected_protected, "formal/config/source SHA coverage is incomplete")
    for path, sha in receipt.get("protected_shas", {}).items():
        require(digest(pipeline.safe_path(workspace, relative(path), must_exist=True)) == sha, "protected source changed: " + path)
    require(bool(receipt.get("protected_shas")), "actual protected-source hashes missing")
    visuals = json.loads((workspace / "data/shop/visuals.json").read_text(encoding="utf-8"))
    layer = visuals["scenes"][config["pixel"]["scene_id"]]["layers"][config["pixel"]["layer_id"]]
    motion = json.loads((workspace / "data/ui/motion.json").read_text(encoding="utf-8"))
    actual_parameters = dict(motion["layer_defaults"]["flow"])
    actual_parameters.update(layer["motion"]["parameters"])
    frames = receipt.get("pixel_readbacks")
    require(isinstance(frames, list) and len(frames) == len(config["periods"]), "all actual day/night readbacks are mandatory")
    require(destination.is_relative_to(receipt_file.parent), "pixel output must stay inside this capture round")
    require(destination.suffix.lower() == ".json", "pixel report must be JSON, never an image overwrite")
    inputs = {config_file, receipt_file} | {pipeline.safe_path(workspace, relative(path), must_exist=True) for path in receipt["protected_shas"]}
    for frame in frames:
        require(isinstance(frame, dict) and isinstance(frame.get("samples"), dict) and isinstance(frame.get("control"), dict), "all capture input paths must be declared before writing")
        for sample in list(frame["samples"].values()) + [frame["control"]]:
            require(isinstance(sample, dict), "invalid GPU sample record")
            inputs.add(pipeline.safe_path(workspace, relative(sample.get("path")), must_exist=True))
    for preview in receipt.get("previews", []):
        inputs.add(pipeline.safe_path(workspace, relative(preview.get("path")), must_exist=True))
    derived = {}
    for period in config["periods"]:
        for name in ("normal", "long_wrap"):
            path = receipt_file.parent / ("pixel-diff-"+period+"-"+name+".png")
            derived[period, name] = pipeline.safe_path(workspace, path.relative_to(workspace).as_posix())
    protect_outputs([destination, *derived.values()], inputs)
    reports = []
    controls = []
    periods = set()
    for frame in frames:
        period = frame.get("period")
        require(period in config["periods"] and period not in periods, "invalid/duplicate actual water period")
        periods.add(period)
        require(frame.get("kind") == "actual_water_gpu" and frame.get("filter") == "linear", "synthetic/nearest samples cannot establish real feather QA")
        expected = relative(layer["variants"][period])
        require(relative(frame.get("source_texture")) == expected, "wrong actual water Li selected")
        source = pipeline.safe_path(workspace, expected, must_exist=True)
        require(frame.get("source_sha256") == digest(source), "water source SHA mismatch")
        require(frame.get("size") == config["pixel"]["viewport_size"], "unexpected GPU readback dimensions")
        require(frame.get("motion_factor") == 1, "formal feather audit must use the actual normal-motion material")
        for key in ("speed_px_s", "distortion_px", "noise_frequency", "edge_fade_px"):
            require(number(frame.get(key)) and math.isclose(frame[key], actual_parameters[key], rel_tol=0, abs_tol=1e-7), "readback did not preserve actual material parameter: " + key)
        require(number(frame.get("speed_px_s")) and frame["speed_px_s"] > 0, "actual configured positive water speed required")
        native = frame.get("uniform_native_size")
        require(isinstance(native, list) and len(native) == 2 and all(number(v) and v > 0 for v in native), "actual material native-size uniform missing")
        transform = layer.get("variant_transforms", {}).get(period, layer["source_transform"])
        crop = transform["source_crop"]
        require(all(math.isclose(native[index], crop[index+2]-crop[index], rel_tol=0, abs_tol=1e-7) for index in range(2)), "actual crop/native coordinate uniform changed")
        require(frame.get("shader_path") == "res://shaders/scene_flow.gdshader", "readback must use production flow shader")
        samples = frame.get("samples", {})
        require(set(samples) == {"start", "one_second", "loop_before", "loop_after"}, "explicit normal/long-period samples missing")
        loop = native[0] / frame["speed_px_s"]
        expected_times = dict(zip(("start", "one_second"), config["capture_times_seconds"]))
        expected_times.update(loop_before=loop-config["pixel"]["loop_offset_seconds"], loop_after=loop+config["pixel"]["loop_offset_seconds"])
        images = {}
        for label, sample in samples.items():
            require(number(sample.get("time_seconds")) and math.isclose(sample["time_seconds"], expected_times[label], rel_tol=0, abs_tol=1e-7), "wrong actual sample time: " + label)
            image_path = pipeline.safe_path(workspace, relative(sample.get("path")), must_exist=True)
            require(image_path.is_relative_to(receipt_file.parent) and digest(image_path) == sample.get("sha256"), "readback evidence path/SHA mismatch")
            with Image.open(image_path) as image:
                require(image.format == "PNG" and image.mode == "RGBA" and list(image.size) == frame["size"], "real RGBA PNG readback required")
                images[label] = image.copy()
        control_record = frame["control"]
        require(control_record.get("kind") == "unshaded_formal_gpu" and control_record.get("filter") == "linear", "same-LINEAR formal texture control is mandatory")
        control_file = pipeline.safe_path(workspace, relative(control_record.get("path")), must_exist=True)
        require(control_file.is_relative_to(receipt_file.parent) and digest(control_file) == control_record.get("sha256"), "original-alpha control path/SHA mismatch")
        with Image.open(control_file) as image:
            require(image.format == "PNG" and image.mode == "RGBA" and list(image.size) == frame["size"], "RGBA unshaded GPU control required")
            control = image.copy()
        for label, image in images.items():
            control_report = compare(control, image, config["pixel"], require_motion=False)
            control_report.update(period=period, sample=label, control=control_record, image=samples[label])
            controls.append(control_report)
        for name, first, second in (("normal", "start", "one_second"), ("long_wrap", "loop_before", "loop_after")):
            diff_path = derived[period, name]
            report = compare(images[first], images[second], config["pixel"], diff_path)
            report.update(period=period, comparison=name, before=samples[first], after=samples[second],
                          source_texture=expected, source_sha256=digest(source),
                          difference_path=diff_path.relative_to(workspace).as_posix())
            reports.append(report)
    result = {"version": 1, "kind": "actual_water_pixel_audit", "passed": all(row["passed"] for row in reports+controls),
              "receipt": receipt_file.relative_to(workspace).as_posix(), "receipt_sha256": digest(receipt_file),
              "config_sha256": digest(config_file), "reports": reports, "original_alpha_controls": controls,
              "visual_status": "仅验证实际GPU逐像素不变式；长周期连续性与最终美术仍待人工检查。"}
    result["preview_failures"] = receipt.get("failures", [])
    result["preview_checks_passed"] = not result["preview_failures"]
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--config", default="data/art/motion_preview.json")
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    try:
        result = audit(args.workspace, args.receipt, args.config, args.output)
        print(json.dumps({"passed": result["passed"], "comparisons": len(result["reports"]),
                          "original_alpha_controls": len(result["original_alpha_controls"]),
                          "errors": [{"period": r["period"], "comparison": r["comparison"], "errors": r["errors"]} for r in result["reports"] if not r["passed"]]}, ensure_ascii=False))
        return 0 if result["passed"] else 1
    except (ValueError, KeyError, TypeError, OSError) as error:
        print("MOTION PIXEL AUDIT ERROR: "+str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
