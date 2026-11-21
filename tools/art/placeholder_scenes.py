"""Deterministic picture-book engineering placeholders, never AI art approval.

The soft-alpha layer is extracted from the actual composite C, using the known
procedural B_i only for alpha matting. B_i retains every other visible layer;
B_all is the original drawn static background. All geometry lives in JSON.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import random
import re

from PIL import Image, ImageChops, ImageDraw, ImageFilter, PngImagePlugin

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = "tools/art/placeholder_scenes.py"
CONFIG = ROOT / "data/art/placeholder_scenes.json"


def _relative_path(value):
    if not isinstance(value, str):
        raise ValueError("path must be a relative POSIX string")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or "\\" in value or ":" in value:
        raise ValueError("path must stay inside its authorized relative directory")
    return path


def _pair(value, maximum, label):
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{label} requires two coordinates")
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v)
           or v < 0 or v > maximum[i] for i, v in enumerate(value)):
        raise ValueError(f"{label} is outside canvas")


def _validate_numbers(value):
    if isinstance(value, bool) or isinstance(value, (int, float)) and not math.isfinite(value):
        raise ValueError("numeric parameters must be finite numbers, never booleans")
    if isinstance(value, dict):
        for child in value.values():
            _validate_numbers(child)
    elif isinstance(value, list):
        for child in value:
            _validate_numbers(child)


def validate_config(config):
    _validate_numbers(config)
    if config.get("version") != 1 or config.get("kind") != "procedural_placeholder":
        raise ValueError("unsupported procedural placeholder version")
    if config.get("qa_kind") != "geometry_only" or not config.get("placeholder_notice"):
        raise ValueError("placeholder requires geometry_only notice")
    if config.get("canvas") != [2560, 1440]:
        raise ValueError("placeholder canvas must be native 2560x1440")
    for field, expected in (("output_dir", "assets/_incoming/a1r_placeholders"), ("pilot_dir", "assets/_incoming/a1r_pilot"), ("runtime_dir", "assets/generated_scenes/runtime/v3")):
        _relative_path(config.get(field))
        if config[field] != expected:
            raise ValueError(f"{field} path is outside the authorized directory")
    palette = config.get("palette", {})
    if len(palette) != 7 or any(not isinstance(v, str) or len(v) != 7 or v[0] != "#" for v in palette.values()):
        raise ValueError("palette requires seven hexadecimal color families")
    for value in palette.values():
        try:
            int(value[1:], 16)
        except ValueError as error:
            raise ValueError("palette contains invalid hexadecimal color") from error
    settings = config.get("render", {})
    if settings.get("feather_px") != 1:
        raise ValueError("layers require a one-pixel feather")
    for field in ("outline_width", "outline_step_px", "paper_amplitude"):
        if not isinstance(settings.get(field), (int, float)) or settings[field] <= 0:
            raise ValueError(f"invalid drawing parameter {field}")
    for field in ("paper_opacity", "night_mix", "closed_mix"):
        if not isinstance(settings.get(field), (int, float)) or not 0 <= settings[field] <= 1:
            raise ValueError(f"invalid drawing parameter {field}")
    grid = settings.get("paper_grid", [])
    if len(grid) != 2 or any(not isinstance(v, int) or v <= 0 for v in grid):
        raise ValueError("invalid paper drawing grid")
    for field in ("outline_color", "night_mix_color", "light_surface_color"):
        if settings.get(field) not in palette:
            raise ValueError("unknown drawing color family")
    if not isinstance(config.get("seed"), int) or settings.get("outline_jitter_px", -1) < 0:
        raise ValueError("invalid deterministic seed or outline jitter")
    defaults = config.get("scene_defaults", {})
    safe = defaults.get("safe_rect", [])
    if len(safe) != 4 or defaults.get("seat_scale", 0) <= 0:
        raise ValueError("missing scene layout defaults")
    _pair(safe[:2], config["canvas"], "safe rectangle")
    _pair([safe[0] + safe[2], safe[1] + safe[3]], config["canvas"], "safe rectangle")
    for field in ("background_prompt_template", "layer_prompt_template", "pilot_prompt_suffix", "native_size_note", "prompt_template"):
        if not isinstance(config.get("receipt_text", {}).get(field), str) or not config["receipt_text"][field]:
            raise ValueError("missing placeholder receipt text template")
    if set(config.get("scenes", {})) != {f"S{i:02}" for i in range(1, 8)}:
        raise ValueError("all seven scenes are required")
    for scene_id, scene in config["scenes"].items():
        wanted = ["day", "night", "closed"] if scene_id == "S01" else ["day", "night"]
        if scene.get("periods") != wanted or scene.get("background") not in palette or not scene.get("subject"):
            raise ValueError(f"invalid periods, background or subject for {scene_id}")
        seen = set()
        for layer in scene["layers"]:
            if not re.fullmatch(r"[a-z][a-z0-9_]*", layer.get("id", "")) or layer["id"] in seen:
                raise ValueError("duplicate or missing layer id")
            seen.add(layer["id"])
            _pair(layer.get("pivot_px"), config["canvas"], "layer pivot")
            if not isinstance(layer.get("z_index"), int) or layer["z_index"] < 0 or layer["z_index"] >= 30:
                raise ValueError("invalid layer z_index")
            if layer.get("motion", {}).get("type") not in ("static", "flow", "pendulum", "sway_shader"):
                raise ValueError("invalid layer motion")
            if layer.get("state") not in (None, "open", "closed"):
                raise ValueError("invalid cabinet state")
        for shape in scene["static"] + [shape for layer in scene["layers"] for shape in layer["shapes"]]:
            if shape.get("type") not in ("polygon", "rectangle", "ellipse", "line") or shape.get("fill") not in palette:
                raise ValueError("unsupported drawing primitive or color family")
            if "points" in shape:
                if len(shape["points"]) < 2:
                    raise ValueError("drawing primitive needs points")
                for point in shape["points"]:
                    _pair(point, config["canvas"], "shape canvas position")
            else:
                box = shape.get("box", [])
                if len(box) != 4 or box[0] >= box[2] or box[1] >= box[3]:
                    raise ValueError("invalid shape canvas box")
                _pair(box[:2], config["canvas"], "shape canvas position")
                _pair(box[2:], config["canvas"], "shape canvas position")
            if not 0 <= shape.get("opacity", 255) <= 255 or shape.get("width", 1) <= 0:
                raise ValueError("invalid primitive opacity or width")
            if not isinstance(shape.get("outline_width", 0), int) or shape.get("outline_width", 0) < 0:
                raise ValueError("invalid primitive outline width")
    if len(config.get("pilot_variants", [])) != 3:
        raise ValueError("three engineering layout references required")
    for variant in config["pilot_variants"]:
        if variant["scene"] != "S02" or variant["period"] != "day" or not re.fullmatch(r"engineering_[123]", variant["id"]):
            raise ValueError("pilot variants must be explicitly engineering references")
    return config


def load_config(path=CONFIG):
    return validate_config(json.loads(Path(path).read_text(encoding="utf-8-sig")))


def _rgb(config, family, period):
    color = tuple(bytes.fromhex(config["palette"][family][1:]))
    if period == "day":
        return color
    settings = config["render"]
    if family == settings["light_surface_color"]:
        return color
    shadow = tuple(bytes.fromhex(config["palette"][settings["night_mix_color"]][1:]))
    amount = settings["closed_mix"] if period == "closed" else settings["night_mix"]
    return tuple(round(c * (1 - amount) + s * amount) for c, s in zip(color, shadow))


def _rough_path(points, settings, rng, closed=False):
    result = []
    pairs = list(zip(points, points[1:] + (points[:1] if closed else [])))
    for start, end in pairs:
        distance = math.dist(start, end)
        steps = max(1, math.ceil(distance / settings["outline_step_px"]))
        for step in range(steps):
            t = step / steps
            jitter = settings["outline_jitter_px"]
            result.append((start[0] + (end[0] - start[0]) * t + rng.uniform(-jitter, jitter),
                           start[1] + (end[1] - start[1]) * t + rng.uniform(-jitter, jitter)))
    if closed and result:
        result.append(result[0])
    elif points:
        result.append(points[-1])
    return result


def _draw_shapes(config, shapes, period, seed):
    canvas = Image.new("RGBA", tuple(config["canvas"]))
    draw = ImageDraw.Draw(canvas)
    settings = config["render"]
    rng = random.Random(seed)
    for shape in shapes:
        alpha = shape.get("opacity", 255)
        fill = _rgb(config, shape["fill"], period) + (alpha,)
        outline = _rgb(config, settings["outline_color"], period) + (alpha,)
        width = shape.get("width", settings["outline_width"])
        kind = shape["type"]
        if kind == "line":
            points = [tuple(p) for p in shape["points"]]
            draw.line(_rough_path(points, settings, rng), fill=fill, width=width, joint="curve")
            continue
        if kind == "polygon":
            points = [tuple(p) for p in shape["points"]]
            draw.polygon(points, fill=fill)
        elif kind == "rectangle":
            box = shape["box"]
            draw.rectangle(box, fill=fill)
            points = [(box[0], box[1]), (box[2], box[1]), (box[2], box[3]), (box[0], box[3])]
        else:
            box = shape["box"]
            draw.ellipse(box, fill=fill)
            cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
            rx, ry = (box[2] - box[0]) / 2, (box[3] - box[1]) / 2
            count = max(4, math.ceil(math.pi * (rx + ry) / settings["outline_step_px"]))
            points = [(cx + rx * math.cos(math.tau * n / count), cy + ry * math.sin(math.tau * n / count)) for n in range(count)]
        outline_width = shape.get("outline_width", settings["outline_width"])
        if outline_width:
            draw.line(_rough_path(points, settings, rng, closed=True), fill=outline,
                      width=outline_width, joint="curve")
    return canvas


def _paper(config, rgb, seed):
    settings = config["render"]
    rng = random.Random(seed + settings["paper_seed_offset"])
    amplitude = settings["paper_amplitude"]
    grain = Image.new("L", tuple(settings["paper_grid"]))
    grain.putdata([rng.randint(128 - amplitude, 128 + amplitude) for _ in range(grain.width * grain.height)])
    grain = grain.resize(rgb.size, Image.Resampling.BILINEAR).convert("RGB")
    textured = ImageChops.add(rgb.convert("RGB"), grain, offset=-128)
    return Image.blend(rgb.convert("RGB"), textured, settings["paper_opacity"])


def _feathered(config, raw, period, seed):
    alpha = raw.getchannel("A").filter(ImageFilter.GaussianBlur(config["render"]["feather_px"]))
    # Extend the original unassociated foreground colors into the feather ring.
    # This is construction of C; exported L_i is separately extracted from C.
    bands = [band.filter(ImageFilter.MaxFilter(3)) for band in raw.convert("RGB").split()]
    foreground = _paper(config, Image.merge("RGB", bands), seed).convert("RGBA")
    foreground.putalpha(alpha)
    return foreground


def extract_layer(original, cleanplate, mask):
    """Recover unassociated FG from actual C and its known B_i, retaining core C."""
    result = Image.new("RGBA", original.size)
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("empty layer mask")
    c_pixels = list(original.convert("RGB").crop(bbox).getdata())
    b_pixels = list(cleanplate.convert("RGB").crop(bbox).getdata())
    alpha_pixels = list(mask.crop(bbox).getdata())
    pixels = []
    for composite, background, alpha in zip(c_pixels, b_pixels, alpha_pixels):
        if alpha == 0:
            pixels.append((0, 0, 0, 0))
        elif alpha == 255:
            pixels.append(composite + (alpha,))
        else:
            pixels.append(tuple(max(0, min(255, round((c * 255 - b * (255 - alpha)) / alpha)))
                                for c, b in zip(composite, background)) + (alpha,))
    patch = Image.new("RGBA", (bbox[2] - bbox[0], bbox[3] - bbox[1]))
    patch.putdata(pixels)
    result.paste(patch, bbox[:2])
    return result


def render_scene(config, scene_id, period, state=None, seed_offset=0):
    scene = config["scenes"][scene_id]
    if period not in scene["periods"]:
        raise ValueError("unknown scene period")
    state = state or scene.get("default_state")
    seed = config["seed"] + int(scene_id[1:]) + seed_offset
    base = Image.new("RGBA", tuple(config["canvas"]), _rgb(config, scene["background"], period) + (255,))
    base = Image.alpha_composite(base, _draw_shapes(config, scene["static"], period, seed))
    base = _paper(config, base, seed).convert("RGBA")
    visible = sorted((layer for layer in scene["layers"] if layer.get("state", state) == state), key=lambda layer: layer["z_index"])
    source_layers = {}
    coverage = Image.new("L", tuple(config["canvas"]))
    for index, layer in enumerate(visible):
        layer_seed = seed + index
        image = _feathered(config, _draw_shapes(config, layer["shapes"], period, layer_seed), period, layer_seed)
        mask = image.getchannel("A")
        if ImageChops.multiply(coverage, mask).getbbox():
            raise ValueError(f"overlapping dynamic layers in {scene_id}/{state}: {layer['id']}")
        coverage = ImageChops.lighter(coverage, mask)
        source_layers[layer["id"]] = image
    original = base.copy()
    for image in source_layers.values():
        original = Image.alpha_composite(original, image)
    layers = {}
    for layer in visible:
        cleanplate = base.copy()
        for other_id, image in source_layers.items():
            if other_id != layer["id"]:
                cleanplate = Image.alpha_composite(cleanplate, image)
        mask = source_layers[layer["id"]].getchannel("A")
        layers[layer["id"]] = dict(image=extract_layer(original, cleanplate, mask), mask=mask,
                                    cleanplate=cleanplate, z_index=layer["z_index"])
    return dict(base=base, original=original, layers=layers)


def _paths(config, scene_id, period, layer_id=None, state=None):
    directory = config["output_dir"]
    stem = f"{scene_id}_{period}"
    values = dict(base=f"{directory}/{stem}_base.png", original=f"{directory}/composites/{stem}{'_' + state if state else ''}.png")
    if layer_id:
        values.update(image=f"{directory}/layers/{stem}_{layer_id}.png", mask=f"{directory}/masks/{stem}_{layer_id}.png",
                      cleanplate=f"{directory}/cleanplates/{stem}_{layer_id}.png")
    return values


def _recipe(config, id, group, source, runtime, subject, **extra):
    prompt = config["receipt_text"]["prompt_template"].format(style=config["style"], subject=subject,
                    negative=config["negative"], notice=config["placeholder_notice"])
    return dict(id=id, group=group, prompt=prompt, requested_prompt=prompt, version=1,
                style_reference=f"{config['pilot_dir']}/engineering_2.png", source_path=source,
                runtime_path=runtime, status="placeholder", operation="procedural_placeholder", attempts=[],
                generator="procedural_placeholder", processing_script=SCRIPT, qa_kind="geometry_only",
                native_size=config["canvas"], native_size_note=config["receipt_text"]["native_size_note"], **extra)


def build_receipt(config):
    recipes, recompositions, descriptors = [], [], {}
    for scene_id, scene in config["scenes"].items():
        descriptor = dict(layers={}, safe_rect=config["scene_defaults"]["safe_rect"])
        if "seat_rect" in scene:
            descriptor.update(seat_rect=scene["seat_rect"], seat_scale=config["scene_defaults"]["seat_scale"])
        for period in scene["periods"]:
            paths = _paths(config, scene_id, period)
            runtime = f"{config['runtime_dir']}/{scene_id}_{period}.png"
            descriptor[period] = runtime
            recipes.append(_recipe(config, f"{scene_id}_{period}", "scenes", paths["base"], runtime,
                                   config["receipt_text"]["background_prompt_template"].format(subject=scene["subject"], period=period),
                                   cleanplate_method="known_procedural_background_no_AI_inpainting"))
            for layer in scene["layers"]:
                state = layer.get("state") or scene.get("default_state")
                paths = _paths(config, scene_id, period, layer["id"], state)
                runtime = f"{config['runtime_dir']}/layers/{scene_id}_{period}_{layer['id']}.png"
                recipes.append(_recipe(config, f"{scene_id}_{period}_{layer['id']}", "layers", paths["image"], runtime,
                                       config["receipt_text"]["layer_prompt_template"].format(subject=scene["subject"], period=period, layer_id=layer["id"]),
                                       mask_path=paths["mask"], original_path=paths["original"], cleanplate_path=paths["cleanplate"],
                                       feather_px=config["render"]["feather_px"], cleanplate_method="known_procedural_background_no_AI_inpainting"))
                if layer["id"] not in descriptor["layers"]:
                    full = [0, 0] + config["canvas"]
                    item = dict(path=runtime, variants={}, rect=full, hotspot=full, native_size=config["canvas"],
                                pivot_px=layer["pivot_px"], z_index=layer["z_index"], motion=layer["motion"])
                    if layer.get("state"):
                        item["state"] = layer["state"]
                    descriptor["layers"][layer["id"]] = item
                descriptor["layers"][layer["id"]]["variants"][period] = runtime
            states = ["open", "closed"] if scene_id == "S04" else [None]
            for state in states:
                paths = _paths(config, scene_id, period, state=state)
                visible = [layer for layer in scene["layers"] if layer.get("state", state) == state]
                recompositions.append(dict(id=f"{scene_id}_{period}{'_' + state if state else ''}", original_path=paths["original"], base_path=paths["base"],
                                           layers=[dict(path=_paths(config, scene_id, period, layer["id"])["image"], z_index=layer["z_index"]) for layer in sorted(visible, key=lambda layer: layer["z_index"])], qa_kind="geometry_only"))
        descriptors[scene_id] = descriptor
    for pilot in config["pilot_variants"]:
        recipes.append(_recipe(config, pilot["id"], "pilot", f"{config['pilot_dir']}/{pilot['id']}.png",
                               f"{config['runtime_dir']}/pilot/{pilot['id']}.png", config["scenes"][pilot["scene"]]["subject"] +
                               config["receipt_text"]["pilot_prompt_suffix"], review_status="engineering_layout_reference_only"))
    receipt = dict(version=1, kind="procedural_placeholder", recipes=recipes, recompositions=recompositions,
                   scene_descriptors=descriptors, notice=config["placeholder_notice"], generator=SCRIPT)
    validate_receipt(receipt)
    return receipt


def validate_receipt(receipt):
    _validate_numbers(receipt)
    if receipt.get("version") != 1 or receipt.get("kind") != "procedural_placeholder":
        raise ValueError("unsupported placeholder receipt")
    if set(receipt.get("scene_descriptors", {})) != {f"S{i:02}" for i in range(1, 8)}:
        raise ValueError("receipt requires all scene descriptors")
    ids, sources = set(), set()
    for recipe in receipt.get("recipes", []):
        if recipe.get("id") in ids or not recipe.get("id"):
            raise ValueError("duplicate or missing receipt recipe")
        ids.add(recipe["id"])
        if recipe.get("status") != "placeholder" or recipe.get("operation") != "procedural_placeholder" or recipe.get("generator") != "procedural_placeholder":
            raise ValueError("receipt cannot claim anything beyond placeholder production")
        if recipe.get("group") not in ("scenes", "layers", "pilot") or not recipe.get("prompt") or recipe.get("attempts") != []:
            raise ValueError("invalid placeholder recipe contract")
        for field in ("source_path", "style_reference", "mask_path", "original_path", "cleanplate_path"):
            if field not in recipe:
                continue
            path = _relative_path(recipe[field])
            if not (path.is_relative_to("assets/_incoming/a1r_placeholders") or path.is_relative_to("assets/_incoming/a1r_pilot")):
                raise ValueError("receipt source path must remain in authorized incoming directory")
        runtime = _relative_path(recipe.get("runtime_path"))
        if not runtime.is_relative_to("assets/generated_scenes/runtime/v3"):
            raise ValueError("receipt runtime path must target v3")
        if recipe["group"] == "layers" and any(field not in recipe for field in ("mask_path", "original_path", "cleanplate_path")):
            raise ValueError("layer recipe requires mask, original C, cleanplate B_i")
        sources.add(recipe["source_path"])
    if not ids:
        raise ValueError("placeholder receipt cannot be empty")
    for record in receipt.get("recompositions", []):
        if record.get("qa_kind") != "geometry_only":
            raise ValueError("placeholder recompositions require geometry_only")
        for field in ("original_path", "base_path"):
            path = _relative_path(record[field])
            if not path.is_relative_to("assets/_incoming/a1r_placeholders"):
                raise ValueError("recomposition evidence path is outside incoming")
        if record["base_path"] not in sources or not record.get("layers"):
            raise ValueError("recomposition references a missing background or no layers")
        for layer in record["layers"]:
            if layer["path"] not in sources:
                raise ValueError("recomposition layer path has no recipe")
    runtime_paths = {recipe["runtime_path"] for recipe in receipt["recipes"]}
    for scene_id, descriptor in receipt["scene_descriptors"].items():
        for period in ("day", "night") + (("closed",) if scene_id == "S01" else ()):
            if descriptor.get(period) not in runtime_paths:
                raise ValueError("scene descriptor references a missing background")
        for layer_id, layer in descriptor.get("layers", {}).items():
            if layer.get("rect") != [0, 0, 2560, 1440] or layer.get("hotspot") != layer["rect"] or layer.get("native_size") != [2560, 1440]:
                raise ValueError("layer descriptor must retain a full canvas frame")
            if layer.get("path") != layer.get("variants", {}).get("day"):
                raise ValueError("layer descriptor requires its day fallback")
            if any(layer.get("variants", {}).get(period) not in runtime_paths for period in ("day", "night")):
                raise ValueError("layer descriptor references missing period variants")
            _pair(layer.get("pivot_px"), [2560, 1440], "layer descriptor pivot")
            z = layer.get("z_index", -1)
            if layer_id == "sofa_mask":
                if not 10 < z < 30:
                    raise ValueError("sofa descriptor must cover guest below dialogue")
            elif not 0 <= z <= 8:
                raise ValueError("ordinary layer descriptor has invalid z_index")
    return receipt


def write_image(path, image, notice="procedural placeholder; geometry_only"):
    path = Path(path)
    metadata = PngImagePlugin.PngInfo()
    metadata.add_text("generator", "procedural_placeholder")
    metadata.add_text("processing_script", SCRIPT)
    metadata.add_text("status", "placeholder")
    metadata.add_text("qa_kind", "geometry_only")
    metadata.add_text("notice", notice)
    if path.exists():
        try:
            with Image.open(path) as old:
                ours = old.info.get("generator") == "procedural_placeholder" and old.info.get("processing_script") == SCRIPT
        except (OSError, ValueError):
            ours = False
        if not ours:
            raise FileExistsError(f"refusing to overwrite existing unknown output: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, pnginfo=metadata)


def validate_output_paths(config, receipt, root):
    """Resolve before mutation, so an existing junction cannot redirect writes."""
    root = Path(root).resolve()
    allowed = [root / config["output_dir"], root / config["pilot_dir"]]
    targets = {recipe[field] for recipe in receipt["recipes"]
               for field in ("source_path", "mask_path", "cleanplate_path", "original_path") if field in recipe}
    targets.update(record["original_path"] for record in receipt["recompositions"])
    targets.add(config["output_dir"] + "/receipt.json")
    for target in targets:
        _relative_path(target)
        resolved = (root / target).resolve()
        if not any(resolved.is_relative_to(directory) for directory in allowed):
            raise ValueError(f"resolved output path escaped authorized incoming directory: {target}")


def generate(config, root=ROOT):
    validate_config(config)
    root = Path(root)
    receipt = build_receipt(config)
    validate_output_paths(config, receipt, root)
    notice = config["placeholder_notice"]
    for scene_id, scene in config["scenes"].items():
        for period in scene["periods"]:
            states = ["open", "closed"] if scene_id == "S04" else [None]
            saved_layers = set()
            for state in states:
                rendered = render_scene(config, scene_id, period, state)
                paths = _paths(config, scene_id, period, state=state)
                if state != "closed":
                    write_image(root / paths["base"], rendered["base"], notice)
                write_image(root / paths["original"], rendered["original"], notice)
                for layer_id, images in rendered["layers"].items():
                    if layer_id in saved_layers:
                        continue
                    paths = _paths(config, scene_id, period, layer_id, state)
                    for key in ("image", "mask", "cleanplate"):
                        write_image(root / paths[key], images[key], notice)
                    saved_layers.add(layer_id)
                print(f"placeholder {scene_id}/{period}/{state or 'default'}", flush=True)
    for variant in config["pilot_variants"]:
        rendered = render_scene(config, variant["scene"], variant["period"], seed_offset=variant["seed_offset"])
        shifted = Image.new("RGBA", tuple(config["canvas"]), _rgb(config, config["scenes"][variant["scene"]]["background"], variant["period"]) + (255,))
        shifted.paste(rendered["original"], tuple(variant["offset_px"]))
        write_image(root / config["pilot_dir"] / (variant["id"] + ".png"), shifted, notice)
    hashes = {}
    for recipe in receipt["recipes"]:
        recipe["sha256"] = hashlib.sha256((root / recipe["source_path"]).read_bytes()).hexdigest()
    for path in sorted((root / config["output_dir"]).rglob("*.png")):
        hashes[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    receipt["evidence_sha256"] = hashes
    receipt_path = root / config["output_dir"] / "receipt.json"
    if receipt_path.exists():
        old = json.loads(receipt_path.read_text(encoding="utf-8"))
        if old.get("kind") != "procedural_placeholder" or old.get("generator") != SCRIPT:
            raise FileExistsError(f"refusing to overwrite existing unknown receipt: {receipt_path}")
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return receipt_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--validate-only", action="store_true")
    arguments = parser.parse_args()
    config = load_config(arguments.config)
    if arguments.validate_only:
        build_receipt(config)
        print("placeholder configuration and receipt contract valid")
    else:
        print(generate(config))


if __name__ == "__main__":
    main()
