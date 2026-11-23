"""Shared portrait metadata must preserve exact provenance, not hide changes."""
import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("compact_metadata_pipeline", ROOT / "tools/art_pipeline.py")
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


class CompactMetadataTests(unittest.TestCase):
    def fixture(self):
        common = {"group": "portraits", "art_pack": "A4_v3", "operation": "portrait_part",
                  "processing_script": "tools/art/portrait_pipeline.py", "local_config": "data/art/portrait_pipeline.json",
                  "inputs": ["assets/base.png", "assets/mask.png", "assets/style.png"],
                  "mask_path": "assets/mask.png", "mask_sha256": "d" * 64,
                  "processing_config_digest": "c" * 64}
        rows = [{"path": "assets/portraits/v3/part_%d.png" % i, "dim": [768, 1024],
                 "sha256": str(i) * 64, "portrait_asset_id": "part_%d" % i,
                 "source_raw": "assets/_incoming/raw_%d.png" % i, "prompt_params": {"description": "exact %d" % i},
                 **copy.deepcopy(common)} for i in range(1, 4)]
        return {"schema_version": 3, "assets": rows, "runtime_copies": []}

    def test_lossless_expansion_preserves_provenance_and_does_not_mutate_input(self):
        original = self.fixture()
        before = copy.deepcopy(original)
        packed = pipeline.compact_portrait_metadata(original)
        self.assertEqual(original, before)
        self.assertTrue(packed["asset_metadata_profiles"])
        self.assertEqual(pipeline.expand_compact_metadata(packed), before)
        for row in packed["assets"]:
            self.assertTrue(all(k in row for k in ("path", "sha256", "dim", "source_raw", "prompt_params")))

    def test_profile_cannot_change_retained_bytes_or_prompt(self):
        for key in ("path", "sha256", "dim", "source_raw", "prompt", "prompt_params", "metadata_profile"):
            packed = pipeline.compact_portrait_metadata(self.fixture())
            next(iter(packed["asset_metadata_profiles"].values()))[key] = "tampered"
            with self.subTest(key=key), self.assertRaises(ValueError):
                pipeline.expand_compact_metadata(packed)

    def test_conflicting_or_missing_profile_fails_instead_of_silently_overriding(self):
        packed = pipeline.compact_portrait_metadata(self.fixture())
        packed["assets"][0]["group"] = "scenes"
        with self.assertRaises(ValueError):
            pipeline.expand_compact_metadata(packed)
        packed = pipeline.compact_portrait_metadata(self.fixture())
        packed["assets"][0]["metadata_profile"] = "missing"
        with self.assertRaises(ValueError):
            pipeline.expand_compact_metadata(packed)

    def test_nonportrait_rows_remain_literal_and_packing_is_idempotent(self):
        original = self.fixture()
        ordinary = {"path": "assets/items/v3/old.png", "group": "items", "sha256": "f" * 64,
                    "dim": [256, 256], "inputs": ["assets/raw.png"], "prompt": "Exact old prompt"}
        original["assets"].append(ordinary)
        packed = pipeline.compact_portrait_metadata(original)
        self.assertEqual(packed["assets"][-1], ordinary)
        self.assertEqual(pipeline.compact_portrait_metadata(packed), packed)


if __name__ == "__main__":
    unittest.main()
