"""Validate the compact formal asset table without loading local art history."""
import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--manifest", default="assets/ART_ASSET_MANIFEST.json")
    args = parser.parse_args()
    workspace = Path(args.workspace).resolve()
    path = art_pipeline.safe_path(workspace, args.manifest, must_exist=True)
    manifest = art_pipeline.read_json(path)
    art_pipeline.validate_compact_manifest(workspace, manifest)
    print("FORMAL ART MANIFEST: valid; %d formal records; local history excluded" % len(manifest["assets"]))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print("FORMAL ART MANIFEST ERROR: " + str(error), file=sys.stderr)
        raise SystemExit(1)
