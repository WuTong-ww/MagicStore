"""Create explicitly labelled Lanczos runtime copies. Originals stay untouched."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    config_path = ROOT / "data/shop/visuals.json"
    manifest_path = ROOT / "assets/ART_ASSET_MANIFEST.json"
    config = json.loads(config_path.read_text(encoding="utf-8-sig"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    records = []
    for scene in config["scenes"].values():
        for period in ("day", "night", "closed"):
            if period not in scene:
                continue
            configured = scene[period].removeprefix("res://")
            old = next((r for r in manifest.get("runtime_copies", []) if r["path"] == configured), None)
            source_path = ROOT / (old["source_path"] if old else configured)
            target = ROOT / "assets/generated_scenes/runtime/v2" / source_path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            with Image.open(source_path) as source:
                native = list(source.size)
                source.resize((1920, 1080), Image.Resampling.LANCZOS).save(target)
            relative = target.relative_to(ROOT).as_posix()
            records.append({"path": relative, "source_path": source_path.relative_to(ROOT).as_posix(),
                            "native_size": native, "runtime_size": [1920, 1080],
                            "scale_x": 1920 / native[0], "scale_y": 1080 / native[1],
                            "native_resolution_met": False, "method": "Lanczos runtime copy",
                            "script": "tools/import_scene_runtime.py", "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
            scene[period] = "res://" + relative
    manifest["runtime_copies"] = records
    manifest["scenes"] = config["scenes"]
    manifest["runtime_note"] = "运行副本：1672×941 源图以 Lanczos 放大约 1.15 倍至 1920×1080；不是原生分辨率。"
    for path, value in ((config_path, config), (manifest_path, manifest)):
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Runtime copies: {len(records)}; source originals retained.")


if __name__ == "__main__":
    main()
