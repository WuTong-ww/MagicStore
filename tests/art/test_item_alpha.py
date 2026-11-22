"""Pixel-level alpha regression cases, without generated or external art."""
import importlib.util
from pathlib import Path
import unittest

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]


def implementation(test):
    path = ROOT / "tools/art/item_pipeline.py"
    test.assertTrue(path.is_file(), "A2R item pipeline is missing")
    spec = importlib.util.spec_from_file_location("item_pipeline", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ItemAlphaTests(unittest.TestCase):
    def test_saturated_red_yellow_uses_only_semitransparent_denominator_and_strict_two_percent(self):
        module = implementation(self)
        config = module.load_config()
        image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        for index in range(100):
            image.putpixel((index, 0), (130, 130, 130, 128))
        image.putpixel((0, 0), (255, 0, 0, 128))
        image.putpixel((1, 0), (255, 255, 0, 128))
        exact = module.alpha_report(image, config)
        self.assertTrue(exact["passed"], exact)
        self.assertEqual((exact["edge_pixels"], exact["red_yellow_pixels"]), (100, 2))
        image.putpixel((2, 0), (255, 0, 0, 128))
        over = module.alpha_report(image, config)
        self.assertFalse(over["passed"])
        self.assertEqual(over["red_yellow_fraction"], 0.03)

    def test_missing_alpha_empty_and_opaque_images_fail(self):
        module = implementation(self)
        for image in (Image.new("RGB", (256, 256), "grey"),
                      Image.new("RGBA", (256, 256)),
                      Image.new("RGBA", (256, 256), (120, 120, 120, 255))):
            with self.subTest(mode=image.mode, extrema=image.getextrema()):
                self.assertFalse(module.alpha_report(image, module.load_config())["passed"])

    def test_visible_magenta_fails_even_if_it_is_not_a_semitransparent_edge(self):
        module = implementation(self)
        image = Image.new("RGBA", (256, 256))
        image.putpixel((128, 128), (255, 0, 255, 255))
        report = module.alpha_report(image, module.load_config())
        self.assertFalse(report["passed"])
        self.assertEqual(report["magenta_pixels"], 1)

    def test_support_is_zero_based_last_three_rows_union_and_ignores_faint_halo(self):
        module = implementation(self)
        image = Image.new("RGBA", (256, 256))
        for point in ((10, 250), (14, 251), (12, 252)):
            image.putpixel(point, (130, 130, 130, 128))
        image.putpixel((230, 255), (130, 130, 130, 127))
        support = module.measure_support(image, module.load_config())
        self.assertEqual(support["bottom_y"], 252)
        self.assertEqual(support["bottom_left"], 10)
        self.assertEqual(support["bottom_width"], 5)
        self.assertEqual(support["bbox"], [10, 250, 15, 253])
        self.assertEqual(support["alpha_bbox"], [10, 250, 231, 256])

    def test_config_rejects_nonfinite_boolean_and_invalid_ranges(self):
        import copy
        module = implementation(self)
        config = module.load_config()
        for group, key, value in (("alpha_qa", "maximum_bad_edge_fraction", float("nan")),
                                  ("support", "alpha_threshold", True),
                                  ("mask", "erode_pixels", -1),
                                  ("color_key", "hue_ranges", [[0.9, 0.1]])):
            bad = copy.deepcopy(config)
            bad[group][key] = value
            with self.subTest(group=group, key=key), self.assertRaises(ValueError):
                module.validate_config(bad)

    def test_antialiased_magenta_matte_does_not_reappear_in_either_runtime_size(self):
        module = implementation(self)
        source = Image.new("RGB", (1200, 1200), (255, 0, 255))
        draw = ImageDraw.Draw(source)
        draw.ellipse((250, 100, 900, 750), fill=(180, 170, 135))
        draw.polygon(((580, 350), (650, 350), (680, 1100), (570, 1100)), fill=(115, 130, 115))
        source = source.resize((420, 420), Image.Resampling.LANCZOS)
        main, _transform = module.process_source(source)
        for image in (main, module.make_icon(main)):
            with self.subTest(size=image.size):
                report = module.alpha_report(image)
                self.assertTrue(report["passed"], report)
                self.assertEqual(report["magenta_pixels"], 0)


if __name__ == "__main__":
    unittest.main()
