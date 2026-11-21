"""Real C/raw-B extraction contracts; no procedural art is synthesized."""
import copy
import importlib.util
import hashlib
from pathlib import Path
import tempfile
import unittest

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/art/real_scene_layers.py"


def implementation(test):
    test.assertTrue(SCRIPT.is_file(), "real same-position layer processing is missing")
    spec = importlib.util.spec_from_file_location("real_scene_layers", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RealSceneLayersTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = self.root / "assets/_incoming/a1r_real/S02"
        source.mkdir(parents=True)
        self.original = Image.new("RGB", (40, 30), (110, 120, 130))
        draw = ImageDraw.Draw(self.original)
        draw.rectangle((8, 9, 14, 15), fill=(150, 145, 140))
        draw.rectangle((26, 9, 32, 15), fill=(140, 150, 145))
        self.original.save(source / "day_C.png")
        Image.new("RGB", (40, 30), (95, 100, 105)).save(source / "day_raw_cleanplate.png")
        self.original.save(source / "reference.png")
        self.spec = {"version": 1, "scene_id": "S02", "period": "day", "revision": "real1",
                     "native_size": [40, 30], "original_path": "assets/_incoming/a1r_real/S02/day_C.png",
                     "raw_cleanplate_path": "assets/_incoming/a1r_real/S02/day_raw_cleanplate.png",
                     "style_reference": "assets/_incoming/a1r_real/S02/reference.png",
                     "composite_prompt": "真实完整场景，无字。", "cleanplate_prompt": "移除两个指定物件，保留背景。",
                     "layers": [
                         {"id": "left", "polygons": [[[7, 8], [15, 8], [15, 16], [7, 16]]],
                          "pivot_px": [11, 8], "z_index": 1, "motion": {"type": "pendulum", "parameters": {"amplitude": 1.5}}},
                         {"id": "right", "polygons": [[[25, 8], [33, 8], [33, 16], [25, 16]]],
                          "pivot_px": [29, 8], "z_index": 2, "motion": {"type": "static", "parameters": {}}}]}

    def test_same_position_single_and_all_layers_recompose_without_approving_art(self):
        module = implementation(self)
        before = {path: path.read_bytes() for path in self.root.rglob("*.png")}
        result = module.process_scene(self.root, self.spec)
        self.assertTrue(result["geometry_passed"])
        self.assertFalse(result["art_passed"])
        self.assertFalse(result["manifest_modified"])
        self.assertEqual(len(result["layers"]), 2)
        self.assertTrue(all(row["single_layer_qa"]["passed"] for row in result["layers"]))
        for row in result["layers"]:
            with Image.open(self.root / row["layer_path"]) as layer:
                self.assertEqual(layer.size, (40, 30))
                self.assertEqual(layer.getchannel("A").getextrema(), (0, 255))
            with Image.open(self.root / row["hard_mask_path"]) as hard, Image.open(self.root / row["soft_mask_path"]) as soft, Image.open(self.root / row["inpaint_mask_path"]) as target:
                self.assertEqual(target.getbbox()[0], max(0, hard.getbbox()[0] - 6))
                self.assertEqual(soft.getbbox()[0], hard.getbbox()[0] - 1)
        self.assertEqual({path: path.read_bytes() for path in before}, before)

    def test_final_cleanplate_retains_unmodified_ring_and_other_object(self):
        module = implementation(self)
        result = module.process_scene(self.root, self.spec)
        left = result["layers"][0]
        with Image.open(self.root / left["cleanplate_path"]) as clean, Image.open(self.root / left["soft_mask_path"]) as mask:
            clean = clean.convert("RGB")
            unchanged = mask.point(lambda value: 255 if value == 0 else 0)
            self.assertIsNone(ImageChops.difference(self.original, clean).getbbox() if unchanged.getextrema() == (255, 255) else ImageChops.multiply(ImageChops.difference(self.original, clean).convert("RGB"), Image.merge("RGB", [unchanged] * 3)).getbbox())
            self.assertEqual(clean.getpixel((28, 12)), self.original.getpixel((28, 12)))
        self.assertEqual(left["single_layer_qa"]["regions"]["inpaint_ring"]["max_error"], 0)
        self.assertEqual(left["single_layer_qa"]["regions"]["unedited"]["max_error"], 0)

    def test_raw_size_difference_is_normalized_as_cover_and_recorded_truthfully(self):
        module = implementation(self)
        raw = self.root / self.spec["raw_cleanplate_path"]
        Image.new("RGB", (39, 30), (95, 100, 105)).save(raw)
        before = raw.read_bytes()
        result = module.process_scene(self.root, self.spec)
        record = result["raw_cleanplate_normalization"]
        self.assertEqual(record["native_size"], [39, 30])
        self.assertEqual(record["normalized_size"], [40, 30])
        self.assertAlmostEqual(record["transform"]["scale"], 40 / 39)
        self.assertEqual(record["transform"]["filter"], "Lanczos")
        self.assertGreater(record["transform"]["source_crop"][1], 0)
        self.assertEqual(raw.read_bytes(), before)

    def test_overlapping_layers_are_reported_and_all_layer_qa_cannot_hide_difference(self):
        module = implementation(self)
        altered = copy.deepcopy(self.spec)
        altered["layers"][1]["polygons"] = altered["layers"][0]["polygons"]
        result = module.process_scene(self.root, altered)
        self.assertGreater(result["overlap_pairs"][0]["hard_overlap_pixels"], 0)
        self.assertFalse(result["recomposition_qa"]["passed"])
        self.assertFalse(result["geometry_passed"])

    def test_invalid_polygons_parameters_and_paths_fail_before_outputs(self):
        module = implementation(self)
        for change in ("out_of_bounds", "self_intersection", "nonfinite", "boolean", "escape", "duplicate_id"):
            altered = copy.deepcopy(self.spec)
            if change == "out_of_bounds":
                altered["layers"][0]["polygons"][0][0] = [-1, 8]
            elif change == "self_intersection":
                altered["layers"][0]["polygons"] = [[[7, 8], [15, 16], [15, 8], [7, 16]]]
            elif change == "nonfinite":
                altered["layers"][0]["motion"]["parameters"]["amplitude"] = float("nan")
            elif change == "boolean":
                altered["layers"][0]["pivot_px"] = [True, 8]
            elif change == "escape":
                altered["revision"] = "../../escape"
            else:
                altered["layers"][1]["id"] = "left"
            with self.subTest(change=change), self.assertRaises(ValueError):
                module.process_scene(self.root, altered)
            self.assertFalse((self.root / "assets/generated_scenes").exists())

    def test_output_collision_never_replaces_prior_art_or_source(self):
        module = implementation(self)
        first = module.process_scene(self.root, self.spec)
        output = self.root / first["layers"][0]["layer_path"]
        output.write_bytes(b"reviewed existing art")
        with self.assertRaises(FileExistsError):
            module.process_scene(self.root, self.spec)
        self.assertEqual(output.read_bytes(), b"reviewed existing art")

    def test_pure_processing_has_no_implicit_art_generation(self):
        module = implementation(self)
        result = module.process_scene(self.root, self.spec)
        self.assertEqual(result["kind"], "real_pixel_extraction")
        self.assertIn("soft-mask patch", result["cleanplate_method"])
        self.assertNotIn("procedural_placeholder", str(result))
        self.assertTrue(all(row["runtime_size"] == [1920, 1080] for row in result["runtime_copies"]))
        self.assertEqual(result["inputs"]["original"]["native_size"], [40, 30])

    def test_flow_overlay_can_retain_its_original_base_pixels(self):
        module = implementation(self)
        altered = copy.deepcopy(self.spec)
        altered["layers"][0]["preserve_base"] = True
        altered["layers"][0]["motion"]["type"] = "flow"
        result = module.process_scene(self.root, altered)
        with Image.open(self.root / result["base_path"]) as base:
            self.assertEqual(base.convert("RGB").getpixel((10, 12)), self.original.getpixel((10, 12)))
        self.assertTrue(result["geometry_passed"])

    def test_generation_receipt_checks_actual_files_prompts_and_attempts(self):
        module = implementation(self)
        source = self.root / self.spec["original_path"]
        style = self.root / self.spec["style_reference"]
        receipt = {"version": 1, "scene_id": "S02", "style_reference": self.spec["style_reference"],
                   "style_sha256": hashlib.sha256(style.read_bytes()).hexdigest(), "records": [
                       {"id": "S02_day", "path": self.spec["original_path"], "ref_paths": [self.spec["style_reference"]],
                        "prompt": "实际生成提示词。", "native_size": [40, 30],
                        "sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "generator": "builtin_imagegen",
                        "status": "complete", "attempts": [{"attempt": 1, "status": "complete"}],
                        "extension_note": "preserved"}]}
        self.assertEqual(module.validate_generation_receipt(self.root, receipt)["records"][0]["extension_note"], "preserved")
        for key, value in (("path", "../escape.png"), ("native_size", [1920, 1080]), ("prompt", ""),
                           ("sha256", "0" * 64), ("attempts", [{"attempt": 1, "status": "complete"}] * 2),
                           ("attempts", [{"attempt": 5, "status": "complete"}])):
            invalid = copy.deepcopy(receipt)
            invalid["records"][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                module.validate_generation_receipt(self.root, invalid)

    def test_processing_receipt_is_revalidated_from_files_and_strict_qa(self):
        module = implementation(self)
        receipt = module.process_scene(self.root, self.spec)
        module.validate_processing_receipt(self.root, receipt)
        for field in ("sha256", "qa", "geometry"):
            altered = copy.deepcopy(receipt)
            if field == "sha256":
                altered["artifacts"][0]["sha256"] = "0" * 64
            elif field == "qa":
                altered["layers"][0]["single_layer_qa"]["regions"]["core"]["max_error"] = 99
            else:
                altered["geometry_passed"] = False
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.validate_processing_receipt(self.root, altered)

    def test_actual_mask_reference_notice_can_override_the_default_batch_method(self):
        module = implementation(self)
        altered = copy.deepcopy(self.spec)
        altered["mask_usage_notice"] = "实际第二次调用传C和union mask作参考图，没有专用mask API。"
        receipt = module.process_scene(self.root, altered)
        self.assertEqual(receipt["mask_usage_notice"], altered["mask_usage_notice"])

    def test_runtime_cannot_replace_cover_pixels_and_forge_an_updated_hash(self):
        module = implementation(self)
        receipt = module.process_scene(self.root, self.spec)
        record = receipt["runtime_copies"][0]
        path = self.root / record["path"]
        Image.new("RGBA", tuple(record["runtime_size"]), (255, 0, 0, 255)).save(path)
        record["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        with self.assertRaisesRegex(ValueError, "runtime.*pixels"):
            module.validate_processing_receipt(self.root, receipt)


if __name__ == "__main__":
    unittest.main()
