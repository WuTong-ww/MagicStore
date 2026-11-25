import copy
import importlib.util
import json
from pathlib import Path
import unittest
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("portrait_clipping_checker", ROOT / "tools/check_portrait_clipping.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


def catalog():
    return json.loads((ROOT / "data/people/appearance_parts.json").read_text(encoding="utf-8"))


def with_rendering():
    value = catalog()
    value["rendering"] = {
        "version": 1,
        "render_order": value["layer_order"][:3] + ["neckwear"] + value["layer_order"][3:],
        "accessories": {row["id"]: {"layer": "neckwear" if row["id"] == "accessory_07" else "accessory", "hides": [], "incompatible_with": []} for row in value["parts"]["accessory"]},
    }
    return value


class PortraitClippingContract(unittest.TestCase):
    def test_production_rendering_exists(self):
        CHECKER.validate_rendering(catalog())

    def test_full_matrix_never_skips_old_exclusions(self):
        value = with_rendering()
        rows, reachable = CHECKER.matrix(value, CHECKER.validate_rendering(value))
        self.assertEqual((len(rows), sum(x["appearance_valid"] for x in rows), sum(x["new_selection_valid"] for x in rows)), (1800, 1780, 1746))
        self.assertEqual(sum(x["selected"]["accessory"] == "none" for x in rows), 120)
        self.assertTrue(all(reachable.values()))

    def test_bad_metadata_containers_fail_cleanly(self):
        for bad in (None, [], {}, True, 7, "rendering"):
            value = with_rendering()
            value["rendering"] = bad
            with self.subTest(value=bad), self.assertRaises(ValueError):
                CHECKER.validate_rendering(value)

    def test_cycles_unknown_parts_and_blanket_exclusions_rejected(self):
        value = with_rendering()
        original = copy.deepcopy(value)
        rules = value["rendering"]["accessories"]["accessory_12"]
        rules["hides"] = [
            {"mode": "replace", "layer": "hair_back", "when_ids": ["hair_back_06"], "replacement_id": "hair_back_05"},
            {"mode": "replace", "layer": "hair_back", "when_ids": ["hair_back_05"], "replacement_id": "hair_back_06"},
        ]
        with self.assertRaisesRegex(ValueError, "CYCLE"):
            CHECKER.validate_rendering(value)
        for field, replacement in (("layer", "body"), ("when_ids", ["unknown"]), ("mode", "erase")):
            value = copy.deepcopy(original)
            rule = {"mode": "replace", "layer": "hair_back", "when_ids": ["hair_back_06"], "replacement_id": "hair_back_05"}
            rule[field] = replacement
            value["rendering"]["accessories"]["accessory_12"]["hides"] = [rule]
            with self.subTest(field=field), self.assertRaises(ValueError):
                CHECKER.validate_rendering(value)
        value = copy.deepcopy(original)
        value["rendering"]["accessories"]["accessory_12"]["incompatible_with"] = [{"layer": "hair_back", "ids": [x["id"] for x in value["parts"]["hair_back"]]}]
        with self.assertRaisesRegex(ValueError, "BLANKET"):
            CHECKER.validate_rendering(value)

    def test_source_files_match_manifest_and_are_not_empty(self):
        sources, alphas = CHECKER.audit_sources(catalog())
        self.assertGreater(len(sources), 100)
        self.assertTrue(all(x["nonzero_alpha_pixels"] > 0 for x in sources))
        self.assertEqual(sum(layer == "accessory" for layer, _part in alphas), 14)
        self.assertEqual(sum(layer == "hair_front" for layer, _part in alphas), 12)
        self.assertEqual(sum(layer == "hair_back" for layer, _part in alphas), 10)

    def test_press_preserves_lower_hair_and_caller_pixels(self):
        pixels = np.zeros((32, 24, 4), dtype=np.uint8)
        pixels[2:31, 3:22] = (90, 90, 90, 255)
        original = pixels.copy()
        rule = {"center_x": 12, "top_offset": 4, "top_scale": 0.6, "end_y": 24}
        prepared = CHECKER.press_pixels(pixels, rule)
        self.assertTrue(np.array_equal(pixels, original))
        self.assertTrue(np.array_equal(prepared[24:], pixels[24:]))
        self.assertGreater(np.count_nonzero(prepared[..., 3]), 0)
        self.assertFalse(np.any(prepared[:4, :, 3]))


if __name__ == "__main__":
    unittest.main()
