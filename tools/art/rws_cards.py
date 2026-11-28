"""Build/validate the pinned public-domain 1909 RWS deck; never downloads assets.

Usage: python tools/art/rws_cards.py --source PATH --receipt PATH
Only the 78 deck IDs are exported. Source PNGs and alternate covers stay external.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageOps, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
REVISION = "840b84d012c6b74dc1634fa2d00d1b21f5b28093"
MAJORS = ("Fool Magician High_Priestess Empress Emperor Hierophant Lovers Chariot "
          "Strength Hermit Wheel_of_Fortune Justice Hanged_Man Death Temperance "
          "Devil Tower Star Moon Sun Judgement World").split()
SIZE = (360, 617)  # round(360 * 12 / 7); less than half a pixel of ratio error.


def need(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def source_name(card, index):
    if index < 22:
        return f"{index:02}_{MAJORS[index]}.png"
    suit, rank = card["id"].rsplit("_", 1)
    return f"{dict(wands='Wands', cups='Cups', swords='Swords', pentacles='Pents')[suit]}{int(rank):02}.png"


def validate_index(value, deck, root=ROOT):
    need(type(value) is dict and set(value) == {"version", "tarot"}, "INDEX_SHAPE")
    need(type(value["version"]) is int and value["version"] == 1, "INDEX_VERSION")
    ids = [card["id"] for card in deck["tarot"]]
    need(len(ids) == 78 and len(set(ids)) == 78, "DECK_IDS")
    need(type(value["tarot"]) is dict and set(value["tarot"]) == set(ids), "INDEX_IDS")
    total = 0
    for card_id, path in value["tarot"].items():
        need(path == f"res://assets/oracle/rws/{card_id}.webp", "INDEX_PATH")
        file = root / path.removeprefix("res://")
        need(file.is_file(), "CARD_MISSING: " + card_id)
        need(0 < file.stat().st_size <= 60_000, "CARD_SIZE: " + card_id)
        with Image.open(file) as image:
            need(image.format == "WEBP" and image.size == SIZE, "CARD_DIMENSIONS: " + card_id)
            image.load()
        total += file.stat().st_size
    need(total <= 4_000_000, "DECK_SIZE")
    return total


def validate_provenance(value, index, root=ROOT):
    need(type(value) is dict and value.get("version") == 1 and value.get("revision") == REVISION, "PROVENANCE_VERSION")
    need(value.get("license") == "Public domain — original 1909 artwork", "PROVENANCE_LICENSE")
    records = value.get("cards")
    need(type(records) is list and len(records) == 78, "PROVENANCE_CARDS")
    need({r["id"] for r in records} == set(index["tarot"]), "PROVENANCE_IDS")
    for row in records:
        need(row["output"] == index["tarot"][row["id"]], "PROVENANCE_PATH")
        need(row["output_sha256"] == sha(root / row["output"].removeprefix("res://")), "PROVENANCE_DIGEST")
        need(all(type(row.get(k)) is str and len(row[k]) == n and all(c in '0123456789abcdef' for c in row[k])
                 for k, n in (("source_sha256", 64), ("source_git_blob", 40))), "SOURCE_DIGEST")
        box = row.get("crop_box")
        need(type(box) is list and len(box) == 4 and all(type(x) is int for x in box)
             and 0 <= box[0] < box[2] <= row["source_size"][0]
             and 0 <= box[1] < box[3] <= row["source_size"][1], "CROP_BOX")


def build(source, receipt_path):
    receipt = read(receipt_path)
    need(receipt.get("revision") == REVISION, "SOURCE_REVISION")
    files = {Path(row["path"]).name: row for row in receipt["files"]}
    deck = read(ROOT / "data/oracle/decks.json")
    index = {"version": 1, "tarot": {}}
    records = []
    for i, card in enumerate(deck["tarot"]):
        name = source_name(card, i)
        info = files[name]
        file = source / "tarot/rider-waite/full-png" / name
        need(sha(file) == info["sha256"], "SOURCE_SHA: " + name)
        raw = file.read_bytes()
        need(hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest() == info["git_blob"], "SOURCE_GIT_SHA")
        with Image.open(file) as original:
            image = original.convert("RGB")
        source_size = image.size
        # Trim only nearly white exterior paper. Preserve every non-white mark,
        # black frame, printed caption and original illustration; add 3px safety.
        points = np.argwhere(np.min(np.asarray(image), axis=2) < 235)
        need(len(points) > 0, "EMPTY_SOURCE")
        y0, x0 = points.min(axis=0)
        y1, x1 = points.max(axis=0) + 1
        box = [max(0, int(x0)-3), max(0, int(y0)-3), min(image.width, int(x1)+3), min(image.height, int(y1)+3)]
        image = ImageEnhance.Color(image.crop(box)).enhance(0.9)
        rgb = np.asarray(image, dtype=np.float32)
        rgb *= np.array([1.004, 1.0, 0.987], dtype=np.float32)
        image = Image.fromarray(np.rint(rgb).clip(0, 255).astype(np.uint8), "RGB")
        # Contain rather than stretch/crop the historical picture into 7:12.
        # The scans contain dense print dots. A fixed subpixel antialias filter
        # avoids ringing/moire at game resolution while keeping quality at 80.
        image = ImageOps.pad(image, SIZE, method=Image.Resampling.BILINEAR, color=(254, 253, 250))
        image = image.filter(ImageFilter.GaussianBlur(0.7))
        relative = f"assets/oracle/rws/{card['id']}.webp"
        output = ROOT / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        image.save(output, "WEBP", quality=80, method=6, exact=True)
        index["tarot"][card["id"]] = "res://" + relative
        records.append(dict(id=card["id"], source_path=info["path"], source_sha256=info["sha256"],
                            source_git_blob=info["git_blob"], source_size=list(source_size), crop_box=box,
                            output="res://" + relative, output_sha256=sha(output), bytes=output.stat().st_size))
    provenance = dict(version=1, repository="https://github.com/mixvlad/TarotCards", revision=REVISION,
                      original_source="https://steve-p.org/cards/RWSa.html", artist="Pamela Colman Smith (1878–1951)",
                      publisher="Rider & Company, 1909; Pam-A", license="Public domain — original 1909 artwork",
                      processing=dict(script="tools/art/rws_cards.py", size=list(SIZE), webp_quality=80,
                                      saturation=0.9, rgb_multipliers=[1.004, 1.0, 0.987], crop_threshold=235,
                                      crop_safety_pixels=3, resampling="bilinear; fixed 0.7px Gaussian antialias",
                                      fit="contain; warm ivory padding; no distortion"), cards=records)
    total = validate_index(index, deck)
    validate_provenance(provenance, index)
    write(ROOT / "data/oracle/card_art.json", index)
    write(ROOT / "assets/oracle/rws/provenance.json", provenance)
    print(json.dumps(dict(cards=len(records), bytes=total, largest=max(r["bytes"] for r in records))))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    build(args.source, args.receipt)
