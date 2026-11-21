"""Propose measured v2-background runtime copies for legacy/compact manifests.

Native PNGs and central JSON inputs are read-only. Runtime binaries and the
two independent proposed JSON outputs are exclusive/idempotent. Aligned v3
layer processing belongs to real_scene_layers, not this old v2 resize tool.
"""
import argparse
import copy
import hashlib
import io
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def require(value, message):
    if not value:
        raise ValueError(message)


def safe_path(workspace, value):
    require(isinstance(value, str), "path must be text")
    value = value.removeprefix("res://")
    require(value and ":" not in value and "\\" not in value and not PurePosixPath(value).is_absolute() and
            not PureWindowsPath(value).is_absolute() and all(part not in ("", ".", "..") for part in value.split("/")), "unsafe workspace path")
    root = Path(workspace).resolve()
    target = (root / value).resolve()
    require(target.is_relative_to(root) and target != root, "path escapes workspace")
    return target


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"), parse_constant=lambda value: (_ for _ in ()).throw(ValueError("nonfinite JSON: " + value)))


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def propose_runtime(workspace, config, manifest):
    workspace = Path(workspace).resolve()
    require(isinstance(config, dict) and isinstance(config.get("scenes"), dict) and isinstance(manifest, dict), "invalid configuration/manifest")
    require(config.get("scene_settings", {}).get("version", 2) == 2, "aligned v3 sources require real_scene_layers; this importer only handles v2 background copies")
    compact = manifest.get("schema_version") == 3
    proposed, configuration = copy.deepcopy(manifest), copy.deepcopy(config)
    assets = {}
    if compact:
        require(isinstance(manifest.get("assets"), list), "compact manifest requires canonical assets[]")
        for row in manifest["assets"]:
            require(isinstance(row, dict) and isinstance(row.get("path"), str), "invalid canonical asset")
            safe_path(workspace, row["path"])
            require(row["path"] not in assets, "duplicate canonical path")
            assets[row["path"]] = copy.deepcopy(row)
    old_records = {}
    for row in manifest.get("runtime_copies", []):
        require(isinstance(row, dict) and isinstance(row.get("path"), str) and row["path"] not in old_records, "duplicate/invalid runtime provenance")
        old_records[row["path"]] = copy.deepcopy(row)
    outputs, native_paths, fresh_records = {}, set(), {}
    for scene in configuration["scenes"].values():
        require(isinstance(scene, dict), "invalid scene")
        for period in ("day", "night", "closed"):
            if period not in scene:
                continue
            configured = scene[period].removeprefix("res://")
            safe_path(workspace, configured)
            old = old_records.get(configured)
            require(old is not None or "/runtime/" not in configured, "existing runtime image lacks retained native-source provenance")
            source_relative = old["source_path"] if old else configured
            source_path = safe_path(workspace, source_relative)
            require(source_path.is_file(), "native source is missing")
            source_bytes = source_path.read_bytes()
            source_sha = hashlib.sha256(source_bytes).hexdigest()
            with Image.open(io.BytesIO(source_bytes)) as source:
                require(source.format == "PNG", "native source must be an actual PNG")
                source.load()
                native = list(source.size)
                buffer = io.BytesIO()
                source.resize((1920, 1080), Image.Resampling.LANCZOS).save(buffer, format="PNG")
            if source_relative in assets:
                require(assets[source_relative].get("sha256", "").lower() == source_sha and
                        assets[source_relative].get("dim") == native, "canonical source hash/dimensions differ from retained PNG")
            if old:
                require(old.get("native_size") == native and ("source_sha256" not in old or old["source_sha256"].lower() == source_sha), "runtime provenance source hash/dimensions mismatch")
            target_relative = "assets/generated_scenes/runtime/v2/" + source_path.name
            target = safe_path(workspace, target_relative)
            require(target != source_path, "runtime target cannot overwrite native source")
            data = buffer.getvalue()
            record = {"path": target_relative, "source_path": source_relative, "native_size": native,
                      "runtime_size": [1920, 1080], "scale_x": 1920 / native[0], "scale_y": 1080 / native[1],
                      "native_resolution_met": False, "method": "Lanczos runtime copy", "script": "tools/import_scene_runtime.py",
                      "source_sha256": source_sha, "sha256": hashlib.sha256(data).hexdigest()}
            require(target_relative not in fresh_records or fresh_records[target_relative] == record, "different native sources collide at one runtime path")
            fresh_records[target_relative] = record
            outputs[target] = data
            native_paths.add(source_path)
            if compact:
                assets[source_relative] = {**assets.get(source_relative, {}), "path": source_relative, "dim": native, "sha256": source_sha}
                assets[target_relative] = {**assets.get(target_relative, {}), "path": target_relative,
                    "dim": [1920, 1080], "sha256": record["sha256"], "inputs": [source_relative]}
            scene[period] = "res://" + target_relative
    require(bool(fresh_records), "no v2 backgrounds were selected")
    require(not set(outputs) & native_paths, "output aliases another retained native source")
    proposed["runtime_copies"] = list({**old_records, **fresh_records}.values())
    if compact:
        proposed["assets"] = [assets[path] for path in sorted(assets)]
        require(len(encoded(proposed)) < 500000, "compact runtime proposal exceeds 500000 bytes")
    else:
        proposed["scenes"] = copy.deepcopy(configuration["scenes"])
    return {"manifest": proposed, "config": configuration, "outputs": outputs, "protected_paths": native_paths,
            "runtime_count": len(fresh_records)}


def import_runtime(workspace, config_path="data/shop/visuals.json", manifest_path="assets/ART_ASSET_MANIFEST.json", output=".tools/art/runtime_import"):
    workspace = Path(workspace).resolve()
    config_file, manifest_file = safe_path(workspace, config_path), safe_path(workspace, manifest_path)
    result = propose_runtime(workspace, read_json(config_file), read_json(manifest_file))
    directory = safe_path(workspace, output)
    metadata = {directory / "ART_ASSET_MANIFEST.json": encoded(result["manifest"]), directory / "visuals.json": encoded(result["config"])}
    protected = result["protected_paths"] | {config_file, manifest_file}
    outputs = {**result["outputs"], **metadata}
    for target, data in outputs.items():
        safe_path(workspace, target.relative_to(workspace).as_posix())
        require(target not in protected, "proposed output cannot overwrite retained inputs")
        require(not target.exists() or target.is_file() and target.read_bytes() == data, "immutable output has different bytes: " + str(target))
    for target, data in outputs.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            with target.open("xb") as stream: stream.write(data)
    return {"runtime_copies": result["runtime_count"], "proposed_manifest": (directory / "ART_ASSET_MANIFEST.json").relative_to(workspace).as_posix(),
            "proposed_config": (directory / "visuals.json").relative_to(workspace).as_posix(), "central_files_modified": False, "art_passed": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--config", default="data/shop/visuals.json")
    parser.add_argument("--manifest", default="assets/ART_ASSET_MANIFEST.json")
    parser.add_argument("--output", default=".tools/art/runtime_import")
    args = parser.parse_args(argv)
    try:
        print(json.dumps(import_runtime(args.workspace, args.config, args.manifest, args.output)))
        return 0
    except (ValueError, OSError, KeyError, TypeError) as error:
        print("RUNTIME IMPORT ERROR: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
