"""Retained-source, measured-support and immutable output A2R integration."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stdout
from contextlib import redirect_stderr

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[2]


def implementation(test):
    path = ROOT / "tools/art/item_pipeline.py"
    test.assertTrue(path.is_file(), "A2R item pipeline is missing")
    spec = importlib.util.spec_from_file_location("item_pipeline", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ItemPipelineTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        self.source = "assets/_incoming/a2r_v3/lavender.png"
        source = self.workspace / self.source
        source.parent.mkdir(parents=True)
        image = Image.new("RGB", (420, 600), (255, 0, 255))
        ImageDraw.Draw(image).rectangle((110, 80, 309, 539), fill=(115, 130, 115))
        image.save(source)
        self.style = "assets/generated_scenes/v3_final/style_reference.png"
        (self.workspace / self.style).parent.mkdir(parents=True)
        Image.new("RGB", (100, 80), (150, 140, 130)).save(self.workspace / self.style)
        digest = lambda path: hashlib.sha256((self.workspace / path).read_bytes()).hexdigest()
        self.generation = {"version": 1, "style_reference": self.style, "style_sha256": digest(self.style),
            "records": [{"id": "lavender", "source_path": self.source, "prompt": "A single muted gouache herb on magenta, no text.",
                "ref_paths": [self.style], "attempts": [{"attempt": 1, "status": "complete", "output_path": self.source,
                    "sha256": digest(self.source), "native_size": [420, 600]}],
                "status": "complete", "sha256": digest(self.source), "native_size": [420, 600]}]}
        for relative in ("data/art/item_pipeline.json", "tools/art/item_pipeline.py"):
            self.assertTrue((ROOT / relative).is_file(), "A2R required implementation is missing: " + relative)
            target = self.workspace / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / relative).read_bytes())

    def test_process_measures_real_256_and_64_derivation_without_modifying_source(self):
        module = implementation(self)
        before = (self.workspace / self.source).read_bytes()
        receipt = module.process_items(self.workspace, self.generation)
        self.assertEqual((self.workspace / self.source).read_bytes(), before)
        entry = receipt["item_entries"]["lavender"]
        self.assertEqual(entry["path"], "res://assets/items/v3/lavender.png")
        self.assertEqual(entry["icon_path"], "res://assets/items/v3/lavender_64.png")
        with Image.open(self.workspace / entry["path"][6:]) as main, Image.open(self.workspace / entry["icon_path"][6:]) as icon:
            self.assertEqual((main.size, icon.size), ((256, 256), (64, 64)))
            self.assertEqual(main.mode, "RGBA")
            self.assertEqual(entry["bottom_y"], module.measure_support(main, module.load_config())["bottom_y"])
            self.assertEqual(entry["bottom_y"], 252)
            self.assertTrue(module.alpha_report(main, module.load_config())["passed"])
            self.assertTrue(module.alpha_report(icon, module.load_config())["passed"])
            self.assertIsNone(ImageChops.difference(icon, module.make_icon(main, module.load_config())).getbbox())
        self.assertEqual(entry["source_native_size"], [420, 600])
        self.assertFalse(receipt["manifest_modified"])
        self.assertFalse(receipt["art_passed"])
        self.assertEqual(receipt["runtime_copies"][1]["source_sha256"], entry["sha256"])
        self.assertTrue(module.validate_processing_receipt(self.workspace, receipt))

    def test_real_pillow_paste_records_only_xy_and_keeps_measured_support_aligned(self):
        module = implementation(self)
        source = module.common.read_image(self.workspace / self.source)
        image, transform = module.process_source(source)
        self.assertEqual(transform["paste_xy"], [83, 49])
        self.assertEqual(len(transform["paste_xy"]), 2)
        support = module.measure_support(image)
        self.assertEqual(support["bottom_y"], 252)
        self.assertEqual(support["bottom_left"], 84)
        self.assertEqual(support["bottom_width"], 87)

    def test_idempotence_conflicting_output_refused_and_revision_keeps_old_bytes(self):
        module = implementation(self)
        first = module.process_items(self.workspace, self.generation)
        self.assertEqual(module.process_items(self.workspace, self.generation), first)
        main = self.workspace / first["item_entries"]["lavender"]["path"][6:]
        original = main.read_bytes()
        main.write_bytes(b"conflicting bytes")
        with self.assertRaises(ValueError):
            module.process_items(self.workspace, self.generation)
        self.assertEqual(main.read_bytes(), b"conflicting bytes")
        main.write_bytes(original)
        newer = module.process_items(self.workspace, self.generation, revision="real2")
        self.assertEqual(main.read_bytes(), original)
        self.assertEqual(newer["item_entries"]["lavender"]["path"], "res://assets/items/v3/real2/lavender.png")

    def test_receipt_rejects_forged_source_hash_dimensions_refs_and_duplicate_ids(self):
        module = implementation(self)
        for mutation in ("sha", "size", "ref", "duplicate", "escape", "attempt_limit", "unknown", "no_success"):
            bad = copy.deepcopy(self.generation)
            row = bad["records"][0]
            if mutation == "sha": row["sha256"] = "0" * 64
            elif mutation == "size": row["native_size"] = [256, 256]
            elif mutation == "ref": row["ref_paths"] = []
            elif mutation == "duplicate": bad["records"].append(copy.deepcopy(row))
            elif mutation == "escape": row["source_path"] = "../outside.png"
            elif mutation == "attempt_limit": row["attempts"] = [{"attempt": i, "status": "complete"} for i in range(1, 6)]
            elif mutation == "unknown": row["id"] = "invented_game_item"
            elif mutation == "no_success": row["attempts"][0]["status"] = "generation_failed"
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                module.validate_generation_receipt(self.workspace, bad)

    def test_completed_attempt_requires_actual_retained_output_metadata(self):
        module = implementation(self)
        for field in ("output_path", "sha256", "native_size"):
            bad = copy.deepcopy(self.generation)
            bad["records"][0]["attempts"][0].pop(field)
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.validate_generation_receipt(self.workspace, bad)

    def test_pending_generation_is_explicit_and_never_becomes_a_completed_item(self):
        module = implementation(self)
        pending = copy.deepcopy(self.generation)
        row = pending["records"][0]
        row.update(status="generation_failed", source_path="assets/_incoming/a2r_v3/missing.png")
        row.pop("sha256")
        row.pop("native_size")
        receipt = module.process_items(self.workspace, pending)
        self.assertEqual(receipt["status"], "needs_builtin_generation")
        self.assertEqual(receipt["item_entries"], {})
        self.assertFalse((self.workspace / "assets/items/v3/lavender.png").exists())

    def test_processing_receipt_rejects_forged_support_and_pixel_data_even_with_new_sha(self):
        module = implementation(self)
        receipt = module.process_items(self.workspace, self.generation)
        bad = copy.deepcopy(receipt)
        bad["item_entries"]["lavender"]["bottom_y"] -= 1
        with self.assertRaises(ValueError):
            module.validate_processing_receipt(self.workspace, bad)
        entry = receipt["item_entries"]["lavender"]
        path = self.workspace / entry["path"][6:]
        with Image.open(path) as old:
            image = old.copy()
        image.putpixel((128, 150), (120, 121, 122, 255))
        image.save(path)
        entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        receipt["runtime_copies"][0]["sha256"] = entry["sha256"]
        with self.assertRaises(ValueError):
            module.validate_processing_receipt(self.workspace, receipt)

    def test_source_cannot_be_an_output_and_revision_cannot_escape(self):
        module = implementation(self)
        for revision in ("../escape", "C:/escape", "nested/path"):
            with self.subTest(revision=revision), self.assertRaises(ValueError):
                module.process_items(self.workspace, self.generation, revision=revision)
        config = module.load_config()
        config["output_root"] = "assets/_incoming/a2r_v3"
        with self.assertRaises(ValueError):
            module.process_items(self.workspace, self.generation, config=config)

    def test_style_change_queues_new_sources_without_relabeling_old_art(self):
        module = implementation(self)
        new_style = "assets/generated_scenes/v3_final/alternate.png"
        Image.new("RGB", (100, 80), (125, 145, 135)).save(self.workspace / new_style)
        queued = module.build_queue(self.workspace, self.generation, new_style, revision="style2")
        self.assertEqual(queued["status"], "needs_builtin_generation")
        self.assertEqual(queued["tasks"][0]["source_destination"], "assets/_incoming/a2r_v3/style2/lavender_source.png")
        self.assertEqual(queued["tasks"][0]["ref_paths"], [new_style])
        self.assertEqual(queued["tasks"][0]["prompt"], self.generation["records"][0]["prompt"])
        self.assertFalse((self.workspace / "assets/items/v3/lavender.png").exists())
        self.assertTrue(module.validate_queue(self.workspace, queued))
        bad = copy.deepcopy(queued)
        bad["tasks"][0]["source_destination"] = self.source
        with self.assertRaises(ValueError):
            module.validate_queue(self.workspace, bad)

    def test_cli_routes_new_style_to_builtin_queue_and_same_style_to_processing(self):
        module = implementation(self)
        receipt_path = "assets/_incoming/a2r_v3/receipt.json"
        (self.workspace / receipt_path).write_text(json.dumps(self.generation), encoding="utf-8")
        args = ["--workspace", str(self.workspace), "--receipt", receipt_path]
        with redirect_stdout(io.StringIO()):
            code = module.main(args + ["--style", str(self.workspace / self.style), "--output-receipt", ".tools/same.json"])
        self.assertEqual(code, 0)
        processed = json.loads((self.workspace / ".tools/same.json").read_text(encoding="utf-8"))
        self.assertEqual(processed["kind"], "processed_item_art")
        with redirect_stdout(io.StringIO()):
            code = module.main(args + ["--style", self.style, "--queue-only", "--revision", "real2", "--output-receipt", ".tools/queue.json"])
        self.assertEqual(code, 2)
        queued = json.loads((self.workspace / ".tools/queue.json").read_text(encoding="utf-8"))
        self.assertEqual(queued["kind"], "item_generation_queue")
        self.assertFalse((self.workspace / "assets/_incoming/a2r_v3/real2/lavender_source.png").exists())

    def test_processing_receipt_rejects_forged_runtime_transform_and_recipe_provenance(self):
        module = implementation(self)
        receipt = module.process_items(self.workspace, self.generation)
        for mutation in ("transform", "recipe", "copy_source"):
            bad = copy.deepcopy(receipt)
            if mutation == "transform": bad["runtime_copies"][0]["transform"]["nominal_scale"] = 12
            elif mutation == "recipe": bad["recipes"][0]["source_path"] = self.style
            elif mutation == "copy_source": bad["runtime_copies"][0]["source_path"] = self.style
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                module.validate_processing_receipt(self.workspace, bad)

    def test_processing_receipt_cannot_weaken_authoritative_alpha_limits(self):
        module = implementation(self)
        weakened = module.load_config()
        weakened["alpha_qa"]["maximum_bad_edge_fraction"] = 1
        receipt = module.process_items(self.workspace, self.generation, config=weakened)
        with self.assertRaises(ValueError):
            module.validate_processing_receipt(self.workspace, receipt)

    def test_generation_malformed_reference_and_status_fail_as_validation_errors(self):
        module = implementation(self)
        for mutation in ("reference", "status"):
            bad = copy.deepcopy(self.generation)
            if mutation == "reference": bad["records"][0]["ref_paths"].append([])
            else: bad["records"][0]["status"] = {}
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                module.validate_generation_receipt(self.workspace, bad)

    def test_cli_validate_only_does_not_write_and_check_alpha_scans_actual_pngs(self):
        module = implementation(self)
        receipt = module.process_items(self.workspace, self.generation)
        payload_path = self.workspace / "processed.json"
        payload_path.write_text(json.dumps(receipt), encoding="utf-8")
        before = {p: p.read_bytes() for p in self.workspace.rglob("*") if p.is_file()}
        with redirect_stdout(io.StringIO()):
            code = module.main(["--workspace", str(self.workspace), "--receipt", "processed.json", "--validate-only"])
        self.assertEqual(code, 0)
        self.assertEqual(before, {p: p.read_bytes() for p in self.workspace.rglob("*") if p.is_file()})
        spec = importlib.util.spec_from_file_location("item_alpha_cli", ROOT / "tools/check_alpha.py")
        checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(checker)
        with redirect_stdout(io.StringIO()):
            code = checker.main([str(self.workspace / "assets/items/v3")])
        self.assertEqual(code, 0)
        Image.new("RGB", (64, 64), (130, 130, 130)).save(self.workspace / "rgb.png")
        with redirect_stdout(io.StringIO()):
            self.assertEqual(checker.main([str(self.workspace / "rgb.png")]), 1)

    def test_manifest_fragment_binds_generation_processing_and_both_runtime_sizes(self):
        module = implementation(self)
        source_receipt = "assets/_incoming/a2r_v3/receipt.json"
        processed_path = ".tools/processed.json"
        (self.workspace / source_receipt).write_text(json.dumps(self.generation), encoding="utf-8")
        with redirect_stdout(io.StringIO()):
            self.assertEqual(module.main(["--workspace", str(self.workspace), "--receipt", source_receipt,
                                         "--output-receipt", processed_path]), 0)
        receipt = json.loads((self.workspace / processed_path).read_text(encoding="utf-8"))
        self.assertIn("manifest_fragment", receipt)
        fragment = receipt["manifest_fragment"]
        self.assertTrue(module.validate_manifest_fragment(self.workspace, fragment))
        section = fragment["round2_items"]
        self.assertEqual((section["generation_receipt"], section["processing_receipt"]), (source_receipt, processed_path))
        self.assertEqual(len(section["runtime_copies"]), 2)
        self.assertFalse(section["coverage"]["complete"])
        for mutation in ("source_sha", "runtime_source", "item_bottom", "processing_pointer"):
            bad = copy.deepcopy(fragment)
            if mutation == "source_sha": bad["round2_items"]["generation_receipt_sha256"] = "0" * 64
            elif mutation == "runtime_source": bad["round2_items"]["runtime_copies"][1]["source_path"] = self.source
            elif mutation == "item_bottom": bad["round2_items"]["item_entries"]["lavender"]["bottom_y"] -= 1
            else: bad["round2_items"]["processing_receipt"] = ".tools/missing.json"
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                module.validate_manifest_fragment(self.workspace, bad)

    def test_production_alpha_cli_checks_every_mapped_large_and_small_png(self):
        module = implementation(self)
        receipt = module.process_items(self.workspace, self.generation)
        original = receipt["item_entries"]["lavender"]
        items = {}
        for item_id in module.load_config()["required_ids"]:
            row = {"item_id": item_id}
            for field, template in (("path", original["path"]), ("icon_path", original["icon_path"])):
                suffix = "_64" if field == "icon_path" else ""
                relative = "assets/items/v3/" + item_id + suffix + ".png"
                (self.workspace / relative).write_bytes((self.workspace / template[6:]).read_bytes())
                row[field] = "res://" + relative
            items[item_id] = row
        mapping = self.workspace / "visuals.json"
        mapping.write_text(json.dumps({"selected_version": 3, "items": items}), encoding="utf-8")
        spec = importlib.util.spec_from_file_location("item_alpha_production_cli", ROOT / "tools/check_alpha.py")
        checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(checker)
        arguments = ["--workspace", str(self.workspace), "--visuals", "visuals.json"]
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(checker.main(arguments), 0)
        report = json.loads(output.getvalue())
        self.assertEqual(report["checked"], 18)
        self.assertEqual(len({row["path"] for row in report["reports"]}), 18)
        last_icon = self.workspace / items["silver_leaf"]["icon_path"][6:]
        Image.new("RGB", (64, 64), "grey").save(last_icon)
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(checker.main(arguments), 1)
        report = json.loads(output.getvalue())
        self.assertEqual(report["checked"], 18)
        self.assertIn("missing_alpha_channel", next(row for row in report["reports"]
                                                    if Path(row["path"]) == last_icon.resolve())["errors"])

    def test_production_alpha_cli_rejects_legacy_or_incomplete_independent_mapping(self):
        spec = importlib.util.spec_from_file_location("item_alpha_invalid_mapping", ROOT / "tools/check_alpha.py")
        checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(checker)
        arguments = ["--workspace", str(self.workspace), "--visuals", "visuals.json"]
        for mapping in ({"selected_version": 2, "items": {}}, {"selected_version": 3, "items": {}}):
            (self.workspace / "visuals.json").write_text(json.dumps(mapping), encoding="utf-8")
            with self.subTest(mapping=mapping), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(checker.main(arguments), 1)


if __name__ == "__main__":
    unittest.main()
