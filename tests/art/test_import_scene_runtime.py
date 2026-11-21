"""Runtime copies are immutable, measured and proposed in either manifest format."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def implementation():
    spec = importlib.util.spec_from_file_location("import_scene_runtime", ROOT / "tools/import_scene_runtime.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RuntimeImportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)
        source = self.workspace / "assets/generated_scenes/v2/S01_day.png"
        source.parent.mkdir(parents=True)
        Image.new("RGB", (32, 18), (120, 130, 140)).save(source)
        self.source = source.relative_to(self.workspace).as_posix()
        self.digest = hashlib.sha256(source.read_bytes()).hexdigest()
        self.config = {"scene_settings": {"version": 2}, "scenes": {"S01": {"day": "res://" + self.source, "layers": {}}}}
        self.compact = {"schema_version": 3, "assets": [{"path": self.source, "sha256": self.digest,
            "dim": [32, 18], "prompt": "Preserve this native prompt"}], "runtime_copies": []}

    def write_inputs(self, manifest):
        for path, value in (("data/shop/visuals.json", self.config), ("assets/ART_ASSET_MANIFEST.json", manifest)):
            target = self.workspace / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(value), encoding="utf-8")

    def test_compact_updates_canonical_paths_and_real_sizes_without_overwriting_inputs(self):
        module = implementation()
        self.write_inputs(self.compact)
        before = {p: p.read_bytes() for p in self.workspace.rglob("*") if p.is_file()}
        result = module.import_runtime(self.workspace, output="proposals")
        self.assertEqual({p: p.read_bytes() for p in before}, before)
        manifest = json.loads((self.workspace / result["proposed_manifest"]).read_text(encoding="utf-8"))
        self.assertNotIn("scenes", manifest)
        self.assertNotIn("round2_art", manifest)
        assets = {row["path"]: row for row in manifest["assets"]}
        self.assertEqual(assets[self.source]["prompt"], "Preserve this native prompt")
        runtime = manifest["runtime_copies"][0]
        self.assertEqual(runtime["native_size"], [32, 18])
        self.assertEqual(runtime["runtime_size"], [1920, 1080])
        self.assertEqual(runtime["source_sha256"], self.digest)
        self.assertEqual(assets[runtime["path"]]["dim"], [1920, 1080])
        self.assertEqual(assets[runtime["path"]]["inputs"], [self.source])
        self.assertFalse(result["art_passed"])
        self.assertEqual(module.import_runtime(self.workspace, output="proposals"), result)

    def test_legacy_keeps_old_manifest_fields_and_scene_map(self):
        module = implementation()
        self.write_inputs({"keep": "unchanged", "runtime_copies": []})
        result = module.import_runtime(self.workspace, output="legacy-proposals")
        manifest = json.loads((self.workspace / result["proposed_manifest"]).read_text(encoding="utf-8"))
        self.assertEqual(manifest["keep"], "unchanged")
        self.assertIn("scenes", manifest)

    def test_conflicting_runtime_bytes_are_refused_before_any_proposal_write(self):
        module = implementation()
        self.write_inputs(self.compact)
        target = self.workspace / "assets/generated_scenes/runtime/v2/S01_day.png"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"keep previous version")
        with self.assertRaises(ValueError):
            module.import_runtime(self.workspace, output="proposals")
        self.assertEqual(target.read_bytes(), b"keep previous version")
        self.assertFalse((self.workspace / "proposals").exists())

    def test_forged_source_hash_or_dimensions_are_rejected(self):
        module = implementation()
        for field, value in (("sha256", "0" * 64), ("dim", [1920, 1080])):
            bad = copy.deepcopy(self.compact)
            bad["assets"][0][field] = value
            self.write_inputs(bad)
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.import_runtime(self.workspace, output="proposals")

    def test_output_path_cannot_escape_or_alias_a_retained_input(self):
        module = implementation()
        self.write_inputs(self.compact)
        for output in ("../escape", "assets"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                module.import_runtime(self.workspace, output=output)


if __name__ == "__main__":
    unittest.main()
