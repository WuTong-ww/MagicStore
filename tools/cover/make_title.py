"""Rebuild COVER typography, composites and review boards with Pillow + numpy.

Run from any directory: python tools/cover/make_title.py
Native key art is read only. --check performs the single, explicit asset audit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/cover"
CONFIG = Path(__file__).with_name("title_layout.json")
LANCZOS = Image.Resampling.LANCZOS


def validate_layout(c: dict) -> None:
    """Validate the only new JSON; fail before writing any output."""
    assert c["version"] == 1
    assert c["title"] == "".join(g["char"] for g in c["glyphs"])
    assert "".join(c["square_lines"]) == c["title"]
    assert c["output_width"] == 1600 and 100 <= c["em"] <= 1000
    assert 0.5 <= c["advance_em"] <= 1.2 and 0 < c["line_height_em"] <= 2
    assert c["padding"] >= 12 and c["thumbnail_width"] == 300
    for g in c["glyphs"]:
        assert len(g["char"]) == 1 and abs(g["angle"]) <= 3
        assert abs(g["dx"]) <= c["em"] / 4 and abs(g["dy"]) <= c["em"] / 4
    assert 0.03 <= c["ink"]["variation"] <= 0.05
    assert 0 < c["ink"]["dry_threshold"] < 1
    assert 0 <= c["ink"]["dry_strength"] <= 1
    assert c["webp_quality"] == 85
    assert set(c["fonts"]) == {"zhimangxing", "mashanzheng", "longcang"}
    for spec in c["fonts"].values():
        assert Path(spec["file"]).name == spec["file"]
        assert spec["page"].startswith("https://fonts.google.com/specimen/")
        assert spec["repo"].startswith("https://github.com/google/fonts/")
        assert (OUT / "fonts" / spec["file"]).is_file(), spec["file"]
    for key in ("subtitle_font",):
        assert (ROOT / c[key]).is_file() and (ROOT / c[key]).resolve().is_relative_to(ROOT)
    assert (ROOT / c["seal"]["font"]).is_file()
    assert abs(c["seal"]["angle"]) <= 3
    for spec in c["composites"].values():
        assert len(spec["size"]) == 2 and min(spec["size"]) >= 300
        assert len(spec["crop"]) == 4
        a, b, d, e = spec["crop"]
        assert 0 <= a < d <= 1 and 0 <= b < e <= 1
        assert 0 < spec["title_height"] < spec["size"][1] / 2
        assert len(spec["title_xy"]) == 2
    for ref in c["style_references"]:
        assert (ROOT / ref).is_file()
    for section in (c["ink"], c["readability"], c["seal"]):
        for key in ("color", "paper", "shadow"):
            if key in section:
                rgb(section[key])


def rgb(value: str) -> tuple[int, int, int]:
    assert len(value) == 7 and value[0] == "#"
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def save_pair(im: Image.Image, path: Path, c: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, optimize=True)
    im.save(path.with_suffix(".webp"), quality=c["webp_quality"], method=6, exact=True)


def glyph_mask(char: str, font: ImageFont.FreeTypeFont, angle: float) -> Image.Image:
    box = font.getbbox(char)
    mask = Image.new("L", (box[2] - box[0] + 24, box[3] - box[1] + 24))
    ImageDraw.Draw(mask).text((12 - box[0], 12 - box[1]), char, font=font, fill=255)
    return mask.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)


def field(rng: np.random.Generator, size: tuple[int, int], grid: tuple[int, int]) -> np.ndarray:
    small = Image.fromarray(rng.integers(0, 256, (grid[1], grid[0]), dtype=np.uint8))
    return np.asarray(small.resize(size, Image.Resampling.BILINEAR), dtype=np.float32) / 255


def ink_texture(mask: Image.Image, c: dict) -> Image.Image:
    settings = c["ink"]
    rng = np.random.default_rng(settings["seed"])
    w, h = mask.size
    alpha = np.asarray(mask, dtype=np.float32)
    eroded = np.asarray(mask.filter(ImageFilter.MinFilter(settings["edge_width"] * 2 + 1)), dtype=np.float32)
    edge = (alpha - eroded) / 255
    # Streaks follow a brush direction; edge/tip support keeps holes nonuniform.
    streaks = field(rng, mask.size, (max(2, w // 70), max(2, h // 3)))
    patches = field(rng, mask.size, (max(2, w // 48), max(2, h // 48)))
    thin = np.asarray(mask.filter(ImageFilter.GaussianBlur(7)), dtype=np.float32) / 255
    support = np.maximum(edge, (1 - thin) * (alpha > 0))
    dry = (streaks > settings["dry_threshold"]) * (patches > 0.52) * support
    alpha *= 1 - settings["dry_strength"] * dry
    # Variation affects the ink colour only; opaque stroke interiors stay legible.
    tone = 1 + (field(rng, mask.size, (max(2, w // 22), max(2, h // 22))) * 2 - 1) * settings["variation"]
    color = np.array(rgb(settings["color"]), dtype=np.float32)
    result = np.empty((h, w, 4), dtype=np.uint8)
    result[:, :, :3] = np.clip(color[None, None, :] * tone[:, :, None], 0, 255).astype(np.uint8)
    result[:, :, 3] = alpha.astype(np.uint8)
    return Image.fromarray(result)


def make_seal(c: dict) -> Image.Image:
    spec = c["seal"]
    side = round(c["em"] * spec["size_em"])
    scale = 3
    s = side * scale
    mask = Image.new("L", (s, s), 255)
    draw = ImageDraw.Draw(mask)
    rng = np.random.default_rng(spec["seed"])
    for _ in range(side // 2):
        x, y = rng.integers(0, s, 2)
        if min(x, y, s - x, s - y) < 7 * scale:
            radius = int(rng.integers(1, 3 * scale))
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=0)
    for _ in range(side // 4):
        x, y = rng.integers(0, s, 2)
        draw.ellipse((x, y, x + scale, y + scale), fill=150)
    im = Image.new("RGBA", (s, s), rgb(spec["color"]) + (0,))
    im.putalpha(mask)
    draw = ImageDraw.Draw(im)
    margin = 6 * scale
    draw.rectangle((margin, margin, s - margin, s - margin), outline=rgb(spec["paper"]), width=scale)
    font = ImageFont.truetype(str(ROOT / spec["font"]), round(side * 0.46) * scale)
    for idx, char in enumerate(spec["text"]):
        draw.text((s / 2, s * (0.30 + idx * 0.42)), char, font=font, anchor="mm", fill=rgb(spec["paper"]))
    im.putalpha(ImageChops.multiply(im.getchannel("A"), mask))
    im = im.resize((side, side), LANCZOS)
    return im.rotate(spec["angle"], resample=Image.Resampling.BICUBIC, expand=True)


def title(c: dict, key: str, arrangement: str = "horizontal") -> Image.Image:
    font = ImageFont.truetype(str(OUT / "fonts" / c["fonts"][key]["file"]), c["em"])
    em = c["em"]
    lines = c["square_lines"] if arrangement == "square" else [c["title"]]
    if arrangement == "vertical":
        lines = list(c["title"])
    canvas = Image.new("L", (em * 8, em * 8))
    specs = {g["char"]: g for g in c["glyphs"]}
    longest = max(len(line) for line in lines)
    for row, line in enumerate(lines):
        for col, char in enumerate(line):
            g = specs[char]
            glyph = glyph_mask(char, font, g["angle"])
            center_x = em + (col + (longest - len(line)) / 2) * em * c["advance_em"]
            center_y = em + row * em * c["line_height_em"]
            xy = (round(center_x - glyph.width / 2 + g["dx"]), round(center_y - glyph.height / 2 + g["dy"]))
            canvas.paste(ImageChops.lighter(canvas.crop((*xy, xy[0] + glyph.width, xy[1] + glyph.height)), glyph), xy)
    box = canvas.getbbox()
    assert box
    pad = c["padding"]
    crop = canvas.crop((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad))
    lettering = ink_texture(crop, c)
    seal = make_seal(c)
    result = Image.new("RGBA", (lettering.width + seal.width + pad // 2, max(lettering.height, seal.height + pad)))
    result.alpha_composite(lettering)
    result.alpha_composite(seal, (lettering.width, result.height - seal.height - pad // 2))
    target = c["vertical"]["width"] if arrangement == "vertical" else c["output_width"]
    return result.resize((target, round(result.height * target / result.width)), LANCZOS)


def outline(im: Image.Image, c: dict, factor: float = 1) -> Image.Image:
    spec = c["readability"]
    pad = math.ceil((spec["shadow_blur"] * 3 + max(spec["shadow_offset"])) * factor)
    padded = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2))
    alpha = Image.new("L", padded.size)
    alpha.paste(im.getchannel("A"), (pad, pad))
    blur = alpha.filter(ImageFilter.GaussianBlur(spec["shadow_blur"] * factor))
    shadow = Image.new("RGBA", padded.size, rgb(spec["shadow"]) + (0,))
    shadow.putalpha(blur.point(lambda x: round(x * spec["shadow_opacity"])))
    offset = tuple(round(x * factor) for x in spec["shadow_offset"])
    padded.alpha_composite(shadow, offset)
    radius = max(1, round(spec["outline_px"] * factor))
    rim = alpha.filter(ImageFilter.MaxFilter(radius * 2 + 1)).filter(ImageFilter.GaussianBlur(spec["outline_blur"] * factor))
    paper = Image.new("RGBA", padded.size, rgb(spec["paper"]) + (0,))
    paper.putalpha(rim.point(lambda x: round(x * spec["outline_opacity"])))
    padded.alpha_composite(paper)
    padded.alpha_composite(im, (pad, pad))
    return padded, pad


def crop_background(art: Image.Image, spec: dict) -> Image.Image:
    a, b, d, e = spec["crop"]
    region = art.crop((round(a * art.width), round(b * art.height), round(d * art.width), round(e * art.height)))
    return ImageOps.fit(region, tuple(spec["size"]), method=LANCZOS).convert("RGBA")


def subtitle(text: str, pixels: int, c: dict) -> Image.Image:
    font = ImageFont.truetype(str(ROOT / c["subtitle_font"]), pixels)
    box = font.getbbox(text)
    im = Image.new("RGBA", (box[2] - box[0] + 8, box[3] - box[1] + 8))
    ImageDraw.Draw(im).text((4 - box[0], 4 - box[1]), text, font=font, fill=rgb(c["ink"]["color"]))
    return im


def compose(art: Image.Image, raw: Image.Image, spec: dict, c: dict) -> Image.Image:
    im = crop_background(art, spec)
    height = spec["title_height"]
    raw = raw.resize((round(raw.width * height / raw.height), height), LANCZOS)
    x, y = spec["title_xy"]
    if spec.get("align") == "center":
        x = round(x - raw.width / 2)
    assert x >= 0 and x + raw.width <= im.width, (spec["size"], raw.size, x)
    decorated, pad = outline(raw, c)
    im.alpha_composite(decorated, (x - pad, y - pad))
    caption = subtitle(c["subtitle"], round(height * c["subtitle_ratio"]), c)
    if caption.width > im.width - 48:
        caption = caption.resize((im.width - 48, round(caption.height * (im.width - 48) / caption.width)), LANCZOS)
    cx = round(im.width / 2 - caption.width / 2) if spec.get("align") == "center" else x
    caption, pad = outline(caption, c, factor=0.5)
    im.alpha_composite(caption, (cx - pad, y + height + spec["subtitle_gap"] - pad))
    return im.convert("RGB")


def label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, c: dict, size: int = 22) -> None:
    font = ImageFont.truetype(str(ROOT / c["subtitle_font"]), size)
    draw.text(xy, text, font=font, fill="#514337")


def boards(c: dict) -> None:
    # Neutral paper is confined to review sheets, never added to the paintings.
    for letter in ("a", "b"):
        paths = [OUT / f"key_art_{letter}_2560x1440.png"] + [ROOT / ref for ref in c["style_references"]]
        sheet = Image.new("RGB", (1440, 332), "#EEE6D6")
        draw = ImageDraw.Draw(sheet)
        for idx, (path, text) in enumerate(zip(paths, [f"封面插画 {letter.upper()}", "游戏场景 S01 · 夜间", "游戏场景 S02 · 夜间"])):
            label(draw, (idx * 480 + 16, 10), text, c)
            sheet.paste(ImageOps.contain(Image.open(path).convert("RGB"), (468, 270), LANCZOS), (idx * 480 + 6, 49))
        save_pair(sheet, OUT / "review" / f"style_comparison_{letter}.png", c)
    font_sheet = Image.new("RGB", (1440, 332), "#EEE6D6")
    for idx, (key, spec) in enumerate(c["fonts"].items()):
        label(ImageDraw.Draw(font_sheet), (idx * 480 + 16, 10), spec["name"], c)
        im = Image.open(OUT / "compare" / f"loading_{key}_1920x1080.png")
        font_sheet.paste(im.resize((468, 263), LANCZOS), (idx * 480 + 6, 49))
    save_pair(font_sheet, OUT / "review/font_comparison.png", c)
    composites = list(c["composites"])
    composites += [f"compare/loading_{key}_1920x1080" for key in c["fonts"]]
    composites += ["loading_vertical_1920x1080"]
    thumb_sheet = Image.new("RGB", (1320, 660), "#EEE6D6")
    for idx, name in enumerate(composites):
        im = Image.open(OUT / (name + ".png"))
        thumb = im.resize((c["thumbnail_width"], round(im.height * c["thumbnail_width"] / im.width)), LANCZOS)
        save_pair(thumb, OUT / "review" / (Path(name).stem + "_300w.png"), c)
        col, row = idx % 4, idx // 4
        label(ImageDraw.Draw(thumb_sheet), (col * 330 + 12, row * 330 + 7), Path(name).stem, c, 14)
        thumb_sheet.paste(thumb, (col * 330 + 12, row * 330 + 28))
    save_pair(thumb_sheet, OUT / "review/thumbnails_300w.png", c)


def process_scan(c: dict) -> bool:
    path = OUT / "title_handwritten_scan.png"
    if not path.exists():
        return False
    scan = Image.open(path).convert("RGBA")
    gray = np.asarray(ImageOps.grayscale(scan), dtype=np.float32)
    alpha = np.clip((238 - gray) * 255 / 160, 0, 255).astype(np.uint8)
    mask = Image.fromarray(alpha)
    mask = ImageChops.multiply(mask, scan.getchannel("A"))
    box = mask.getbbox()
    if not box:
        raise ValueError("手写扫描没有可识别的深色笔画")
    ink = ink_texture(mask.crop(box), c)
    seal = make_seal(c)
    result = Image.new("RGBA", (ink.width + seal.width + 28, max(ink.height + 24, seal.height)))
    result.alpha_composite(ink, (12, 12))
    result.alpha_composite(seal, (ink.width + 24, result.height - seal.height))
    result = result.resize((c["output_width"], round(result.height * c["output_width"] / result.width)), LANCZOS)
    save_pair(result, OUT / "title_handwritten.png", c)
    scan.save(path.with_suffix(".webp"), quality=c["webp_quality"], method=6, exact=True)
    return True


def build(c: dict) -> None:
    for letter in ("a", "b"):
        # Preserve original PNG bytes and native pixel dimensions.
        p = OUT / f"key_art_{letter}_2560x1440.png"
        with Image.open(p) as im:
            im.save(p.with_suffix(".webp"), quality=c["webp_quality"], method=6, exact=True)
    art = Image.open(OUT / "key_art_a_2560x1440.png").convert("RGB")
    for key in c["fonts"]:
        raw = title(c, key)
        save_pair(raw, OUT / f"title_{key}.png", c)
        spec = c["composites"]["loading_1920x1080"]
        save_pair(compose(art, raw, spec, c), OUT / "compare" / f"loading_{key}_1920x1080.png", c)
    for name, spec in c["composites"].items():
        raw = title(c, "zhimangxing", spec.get("arrangement", "horizontal"))
        save_pair(compose(art, raw, spec, c), OUT / (name + ".png"), c)
    vertical = title(c, "zhimangxing", "vertical")
    save_pair(vertical, OUT / "title_zhimangxing_vertical.png", c)
    background = crop_background(art, c["composites"]["loading_1920x1080"])
    height = c["vertical"]["loading_height"]
    vertical = vertical.resize((round(vertical.width * height / vertical.height), height), LANCZOS)
    decorated, pad = outline(vertical, c)
    x, y = c["vertical"]["loading_xy"]
    background.alpha_composite(decorated, (x - pad, y - pad))
    caption = subtitle(c["subtitle"], 30, c)
    caption, pad = outline(caption, c, 0.5)
    background.alpha_composite(caption, (84 - pad, 860 - pad))
    save_pair(background.convert("RGB"), OUT / "loading_vertical_1920x1080.png", c)
    scan = process_scan(c)
    boards(c)
    write_inventory(c)
    print(f"Built COVER: {len(list(OUT.rglob('*.png')))} PNG / matching WebP quality 85; handwritten scan: {scan}")


def write_inventory(c: dict) -> None:
    lines = ["# COVER 文件与 SHA256", "", "由 `python tools/cover/make_title.py` 生成；相对仓库根目录。", "", "| 文件 | 实际尺寸 | 字节 | SHA256 |", "|---|---|---:|---|"]
    for path in sorted(OUT.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {".png", ".webp", ".ttf", ".md"}:
            continue
        dimensions = "—"
        if path.suffix.lower() in {".png", ".webp"}:
            with Image.open(path) as im:
                dimensions = f"{im.width}×{im.height}"
        lines.append(f"| `{path.relative_to(ROOT).as_posix()}` | {dimensions} | {path.stat().st_size} | `{hashlib.sha256(path.read_bytes()).hexdigest()}` |")
    Path(__file__).with_name("file_inventory.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def audit(c: dict) -> None:
    """One review pass: dimensions, transparency, exported pairs and glyph coverage."""
    from fontTools.ttLib import TTFont
    checks = 0
    failures = []

    def check(ok: bool, message: str) -> None:
        nonlocal checks
        checks += 1
        if not ok:
            failures.append(message)

    for path in sorted(OUT.rglob("*.png")):
        with Image.open(path) as im:
            im.load()
            pair = path.with_suffix(".webp")
            check(pair.is_file(), f"missing WebP: {path.name}")
            if pair.is_file():
                with Image.open(pair) as wp:
                    check(wp.size == im.size, f"WebP dimensions: {path.name}")
                    check(wp.mode == im.mode, f"WebP alpha/mode: {path.name}")
                    if im.mode == "RGBA":
                        check(ImageChops.difference(im.getchannel("A"), wp.getchannel("A")).getbbox() is None, f"WebP alpha fidelity: {path.name}")
            if path.name.startswith("title_") and "scan" not in path.name:
                check(im.mode == "RGBA" and im.getextrema()[3][0] == 0, f"transparent title: {path.name}")
                check(im.getbbox() is not None, f"empty title: {path.name}")
                if "vertical" not in path.name:
                    check(im.width == 1600, f"title width: {path.name}")
                check(im.getbbox()[0] > 0 and im.getbbox()[2] < im.width, f"title horizontal clipping: {path.name}")
                check(im.getbbox()[1] > 0 and im.getbbox()[3] < im.height, f"title vertical clipping: {path.name}")
            if path.name.endswith("_300w.png") and path.name != "thumbnails_300w.png":
                check(im.width == 300, f"thumbnail width: {path.name}")
    for key, spec in c["fonts"].items():
        with TTFont(OUT / "fonts" / spec["file"]) as font:
            cmap = font.getBestCmap()
            check(all(ord(char) in cmap for char in c["title"]), f"title glyph coverage: {key}")
    for font_path, text in [(c["subtitle_font"], c["subtitle"]), (c["seal"]["font"], c["seal"]["text"])]:
        with TTFont(ROOT / font_path) as font:
            check(all(ord(char) in font.getBestCmap() for char in text), f"subtitle/seal glyph coverage: {font_path}")
    for name, spec in c["composites"].items():
        with Image.open(OUT / (name + ".png")) as im:
            check(im.size == tuple(spec["size"]), f"composite dimensions: {name}")
    for key in c["fonts"]:
        with Image.open(OUT / "compare" / f"loading_{key}_1920x1080.png") as im:
            check(im.size == (1920, 1080), f"font comparison dimensions: {key}")
    for letter in ("a", "b"):
        with Image.open(OUT / f"key_art_{letter}_2560x1440.png") as im:
            check(im.size == (1672, 941), f"native art dimensions changed: {letter}")
    result = f"COVER ASSET RESULT: {checks} checks, {len(failures)} failures\n" + "\n".join(failures)
    (OUT / "review/asset_check.txt").write_text(result + "\n", encoding="utf-8")
    print(result)
    if failures:
        raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Audit existing exports without rebuilding")
    args = parser.parse_args()
    c = json.loads(CONFIG.read_text(encoding="utf-8"))
    validate_layout(c)
    if args.check:
        audit(c)
    else:
        build(c)


if __name__ == "__main__":
    main()
