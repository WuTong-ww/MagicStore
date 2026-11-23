"""Validate the compact formal asset table without loading local art history."""
import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline


RASTER_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tif", ".tiff", ".ico"}


def validate_formal_sources(workspace, manifest):
    """Check exact retained bytes; only raster assets have Pillow dimensions."""
    sources=list(manifest["assets"])
    known={row["path"].casefold()for row in sources}
    for alias in manifest.get("runtime_copies",[]):
        if alias["path"].casefold() not in known:
            sources.append({"path":alias["path"],"sha256":alias["sha256"],"dim":alias["runtime_size"]})
            known.add(alias["path"].casefold())
    for asset in sources:
        path = art_pipeline.safe_path(workspace, asset["path"], must_exist=True)
        if art_pipeline.sha256(path) != asset["sha256"].lower():
            raise ValueError("formal source SHA256 mismatch: " + asset["path"])
        if "dim" in asset and path.suffix.lower() in RASTER_SUFFIXES:
            actual = list(art_pipeline.read_image(path).size)
            if actual != asset["dim"]:
                raise ValueError("formal source dimensions mismatch: %s (expected %s, actual %s)" %
                                 (asset["path"], asset["dim"], actual))
    return len(sources)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--manifest", default="assets/ART_ASSET_MANIFEST.json")
    args = parser.parse_args()
    workspace = Path(args.workspace).resolve()
    path = art_pipeline.safe_path(workspace, args.manifest, must_exist=True)
    manifest = art_pipeline.read_json(path)
    art_pipeline.validate_compact_manifest(workspace, manifest)
    files=validate_formal_sources(workspace, manifest)
    print("FORMAL ART MANIFEST: valid; %d formal records; %d retained files; source bytes/dimensions verified; local history excluded" % (len(manifest["assets"]),files))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print("FORMAL ART MANIFEST ERROR: " + str(error), file=sys.stderr)
        raise SystemExit(1)
