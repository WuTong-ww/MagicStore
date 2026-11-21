"""Geometry-only placeholder production; never an art approval test."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/art/placeholder_scenes.py"
CONFIG = ROOT / "data/art/placeholder_scenes.json"


def producer(test):
    test.assertTrue(SCRIPT.is_file(), "A1R placeholder producer is not implemented")
    spec = importlib.util.spec_from_file_location("placeholder_scenes", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PlaceholderScenesTests(unittest.TestCase):
    def test_configuration_rejects_escape_and_invalid_geometry(self):
        module = producer(self)
        config = module.load_config(CONFIG)
        escaped = copy.deepcopy(config)
        escaped["output_dir"] = "../escape"
        with self.assertRaisesRegex(ValueError, "path"):
            module.validate_config(escaped)
        invalid = copy.deepcopy(config)
        invalid["scenes"]["S02"]["layers"][0]["shapes"][0]["points"][0][0] = -50
        with self.assertRaisesRegex(ValueError, "canvas"):
            module.validate_config(invalid)

    def test_configuration_rejects_missing_and_invalid_drawing_parameters(self):
        module = producer(self)
        config = module.load_config(CONFIG)
        for field, value in [("paper_grid", [0, 180]), ("outline_step_px", 0), ("night_mix", 2)]:
            invalid = copy.deepcopy(config)
            invalid["render"][field] = value
            with self.assertRaises(ValueError):
                module.validate_config(invalid)
        invalid = copy.deepcopy(config)
        invalid["scenes"]["S02"]["layers"][0]["id"] = "../../outside"
        with self.assertRaisesRegex(ValueError, "path|id"):
            module.validate_config(invalid)

    def test_receipt_rejects_invalid_full_frame_descriptor(self):
        module = producer(self)
        receipt = module.build_receipt(module.load_config(CONFIG))
        receipt["scene_descriptors"]["S03"]["layers"]["sofa_mask"]["rect"] = [0, 0, 12, 12]
        with self.assertRaisesRegex(ValueError, "descriptor|canvas|frame"):
            module.validate_receipt(receipt)

    def test_nonfinite_and_boolean_geometry_produce_no_outputs(self):
        module = producer(self)
        config = module.load_config(CONFIG)
        for value in (float("nan"), float("inf"), float("-inf"), True):
            invalid = copy.deepcopy(config)
            invalid["scenes"]["S02"]["layers"][0]["shapes"][0]["points"][0][0] = value
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                with self.assertRaisesRegex(ValueError, "numeric|finite|canvas"):
                    module.generate(invalid, root=root)
                self.assertEqual(list(root.iterdir()), [])

    def test_output_preflight_rejects_existing_junction_escape(self):
        module = producer(self)
        self.assertTrue(hasattr(module, "validate_output_paths"), "resolved output path preflight is not implemented")
        import os
        import subprocess
        with tempfile.TemporaryDirectory(dir=ROOT / ".tools") as temporary:
            root = Path(temporary) / "project"
            outside = Path(temporary) / "outside"
            outside.mkdir()
            parent = root / "assets/_incoming"
            parent.mkdir(parents=True)
            link = parent / "a1r_placeholders"
            if os.name == "nt":
                result = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(outside)], capture_output=True)
                if result.returncode:
                    reason = result.stderr.decode(errors="replace").strip()
                    self.skipTest(f"Windows denied temporary junction creation: {reason}")
            else:
                link.symlink_to(outside, target_is_directory=True)
            try:
                with self.assertRaisesRegex(ValueError, "resolved|path"):
                    module.generate(module.load_config(CONFIG), root=root)
                self.assertEqual(list(outside.iterdir()), [])
            finally:
                if os.name == "nt":
                    os.rmdir(link)
                else:
                    link.unlink()

    def test_fifteen_backgrounds_and_all_handbook_layers_are_declared(self):
        module = producer(self)
        config = module.load_config(CONFIG)
        expected = {
            "S01": {"tree_canopy", "vine", "hanging_sign", "cloud"},
            "S02": {"outside_leaves", "inside_leaves", "window_vine", "dried_flowers", "wind_chime", "curtain_left", "curtain_right", "incense_burner", "incense_smoke"},
            "S03": {"lamp", "curtain", "teacup", "tea_steam", "sofa_mask"},
            "S04": {"door_open", "door_closed", "lamp"},
            "S05": {"dried_grass", "steam"},
            "S06": {"street_leaves", "cloth_curtain"},
            "S07": {"grass", "tree_canopy", "water_mask"},
        }
        self.assertEqual(sum(len(s["periods"]) for s in config["scenes"].values()), 15)
        for scene_id, ids in expected.items():
            self.assertEqual({layer["id"] for layer in config["scenes"][scene_id]["layers"]}, ids)
        sofa = next(layer for layer in config["scenes"]["S03"]["layers"] if layer["id"] == "sofa_mask")
        self.assertGreater(sofa["z_index"], 10)
        self.assertLess(sofa["z_index"], 30)

    def test_scene_is_deterministic_and_empty_of_guest_geometry(self):
        module = producer(self)
        config = module.load_config(CONFIG)
        first = module.render_scene(config, "S03", "day")
        second = module.render_scene(config, "S03", "day")
        self.assertEqual(first["original"].tobytes(), second["original"].tobytes())
        sofa = first["layers"]["sofa_mask"]["mask"]
        self.assertEqual(sofa.crop((950, 410, 1440, 850)).getbbox(), None)
        self.assertIsNotNone(sofa.crop((950, 850, 1440, 1140)).getbbox())

    def test_each_extraction_recomposes_against_its_own_cleanplate(self):
        module = producer(self)
        config = module.load_config(CONFIG)
        for scene_id, period, state in [("S02", "day", None), ("S04", "night", "open"), ("S04", "night", "closed")]:
            rendered = module.render_scene(config, scene_id, period, state)
            original = rendered["original"].convert("RGB")
            rebuilt = rendered["base"].convert("RGBA")
            for layer in rendered["layers"].values():
                readded = Image.alpha_composite(layer["cleanplate"].convert("RGBA"), layer["image"]).convert("RGB")
                difference = ImageChops.difference(original, readded)
                self.assertLessEqual(max(channel[1] for channel in difference.getextrema()), 2)
                core = layer["mask"].point(lambda alpha: 255 if alpha == 255 else 0)
                self.assertIsNone(ImageChops.multiply(difference, core.convert("RGB")).getbbox())
                extracted_core = ImageChops.multiply(ImageChops.difference(original, layer["image"].convert("RGB")), core.convert("RGB"))
                self.assertIsNone(extracted_core.getbbox(), "opaque core must retain actual C pixels")
                rebuilt = Image.alpha_composite(rebuilt, layer["image"])
            error = ImageChops.difference(original, rebuilt.convert("RGB"))
            self.assertLessEqual(max(channel[1] for channel in error.getextrema()), 2)
            self.assertEqual(original.size, (2560, 1440))

    def test_receipt_rejects_non_placeholder_claims_and_unknown_paths(self):
        module = producer(self)
        config = module.load_config(CONFIG)
        receipt = module.build_receipt(config)
        module.validate_receipt(receipt)
        altered = copy.deepcopy(receipt)
        altered["recipes"][0]["status"] = "approved"
        with self.assertRaisesRegex(ValueError, "placeholder"):
            module.validate_receipt(altered)
        altered = copy.deepcopy(receipt)
        altered["recompositions"][0]["qa_kind"] = "art_approved"
        with self.assertRaisesRegex(ValueError, "geometry_only"):
            module.validate_receipt(altered)
        altered = copy.deepcopy(receipt)
        altered["recipes"][0]["source_path"] = "assets/other/user.png"
        with self.assertRaisesRegex(ValueError, "path"):
            module.validate_receipt(altered)

    def test_full_bleed_shape_does_not_draw_a_canvas_border(self):
        module = producer(self)
        config = module.load_config(CONFIG)
        shapes = [{"type": "rectangle", "box": [0, 0, 2560, 1440], "fill": "sage", "outline_width": 0}]
        image = module._draw_shapes(config, shapes, "day", 7)
        for point in [(0, 0), (0, 700), (2559, 700), (1200, 1439)]:
            self.assertEqual(image.getpixel(point), (138, 152, 122, 255))

    def test_unknown_existing_output_is_never_overwritten(self):
        module = producer(self)
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "user.png"
            target.write_bytes(b"unknown user bytes")
            with self.assertRaisesRegex(FileExistsError, "existing"):
                module.write_image(target, Image.new("RGB", (4, 4), "white"))
            self.assertEqual(target.read_bytes(), b"unknown user bytes")


if __name__ == "__main__":
    unittest.main()
