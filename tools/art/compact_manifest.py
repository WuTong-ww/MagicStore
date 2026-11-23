"""Propose a lossless compact art manifest without changing central metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline


def propose(workspace, manifest):
    art_pipeline.validate_compact_manifest(workspace, manifest)
    packed = art_pipeline.compact_formal_metadata(manifest)
    art_pipeline._require(art_pipeline.expand_compact_metadata(packed) ==
                          art_pipeline.expand_compact_metadata(manifest), "compaction changed formal provenance")
    art_pipeline.validate_compact_manifest(workspace, packed)
    return packed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--manifest", default="assets/ART_ASSET_MANIFEST.json")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    workspace = Path(args.workspace).resolve()
    source = art_pipeline.safe_path(workspace, args.manifest, must_exist=True)
    target = art_pipeline.safe_path(workspace, args.output)
    art_pipeline._require(args.output.startswith((".tools/", "assets/_incoming/")), "proposal must remain local")
    manifest = art_pipeline.read_json(source)
    packed = propose(workspace, manifest)
    output = (json.dumps(packed, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
    art_pipeline._require(not target.exists() or target.read_bytes() == output, "immutable proposal already differs")
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        with target.open("xb") as stream:
            stream.write(output)
    print(json.dumps({"source_sha256": art_pipeline.sha256(source), "source_bytes": source.stat().st_size,
                      "proposed_sha256": hashlib.sha256(output).hexdigest(), "proposed_bytes": len(output),
                      "formal_records": len(packed["assets"]), "exact_expansion": True,
                      "central_manifest_modified": False, "output": args.output}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        print("COMPACT MANIFEST ERROR: " + str(error), file=sys.stderr)
        raise SystemExit(1)
