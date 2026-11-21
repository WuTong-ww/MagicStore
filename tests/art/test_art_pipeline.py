"""Behavioral contracts for the offline A1R import and reconstruction pipeline."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/art_pipeline.py"


def implementation(test):
    test.assertTrue(SCRIPT.is_file(), "A1R offline pipeline is not implemented")
    spec = importlib.util.spec_from_file_location("art_pipeline", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ArtPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)

    def image(self, name, size=(16, 12), color="white", mode="RGB"):
        path = self.workspace / name
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.new(mode, size, color).save(path)
        return path

    def recipe(self, **changes):
        value = dict(id="s02_day", group="scenes", prompt="朴素手绘前台，无字。", version="v2",
                     style_reference="style.png", source_path="source.png", runtime_path="runtime.png",
                     status="needs_builtin_generation", operation="generate", attempts=[])
        value.update(changes)
        return value

    def manifest(self, recipes=None):
        style = self.image("style.png")
        return {"legacy": {"keep": True}, "round2_art": {
            "version": 1, "active_style": {"path": "style.png", "sha256": hashlib.sha256(style.read_bytes()).hexdigest(),
                                            "status": "placeholder"},
            "recipes": recipes if recipes is not None else [self.recipe()], "recompositions": []}}

    def fixture(self):
        original = Image.new("RGB", (32, 24), (130, 145, 150))
        ImageDraw.Draw(original).rectangle((10, 8, 15, 13), fill=(80, 95, 100))
        original.save(self.workspace / "original.png")
        mask = Image.new("L", original.size, 0)
        ImageDraw.Draw(mask).rectangle((9, 7, 16, 14), fill=255)
        mask.save(self.workspace / "mask.png")
        layer = original.convert("RGBA")
        layer.putalpha(mask)
        layer.save(self.workspace / "layer.png")
        # C under the feather region is a legal exact cleanplate fixture.
        original.save(self.workspace / "clean.png")
        return self.recipe(id="layer", group="layers", operation="extract_layer", source_path="layer.png",
                           runtime_path="layer-runtime.png", original_path="original.png", mask_path="mask.png",
                           cleanplate_path="clean.png", status="placeholder", qa_kind="geometry_only")

    def test_missing_implementation_has_user_actionable_queue(self):
        module = implementation(self)
        manifest = self.manifest()
        queue = module.build_queue(self.workspace, manifest, "style.png", "scenes")
        self.assertEqual(queue["status"], "needs_builtin_generation")
        task = queue["tasks"][0]
        self.assertEqual(task["recipe_id"], "s02_day")
        self.assertEqual(task["tool"], "image_gen.imagegen")
        self.assertEqual([Path(path).resolve() for path in task["arguments"]["referenced_image_paths"]],
                         [(self.workspace / "style.png").resolve()])
        self.assertIn("朴素手绘前台", task["arguments"]["prompt"])
        self.assertNotIn("api_key", json.dumps(queue))

    def test_unknown_group_and_non_image_style_fail_before_writes(self):
        module = implementation(self)
        manifest = self.manifest()
        with self.assertRaisesRegex(ValueError, "group"):
            module.build_queue(self.workspace, manifest, "style.png", "absent")
        (self.workspace / "bad.png").write_text("not image")
        with self.assertRaisesRegex(ValueError, "image"):
            module.build_queue(self.workspace, manifest, "bad.png", "scenes")
        self.assertEqual(len(list(self.workspace.iterdir())), 2)

    def test_manifest_rejects_escape_absolute_windows_paths_and_duplicate_ids(self):
        module = implementation(self)
        manifest = self.manifest()
        for path in ("../outside.png", "/outside.png", "C:/outside.png", "nested\\file.png"):
            altered = copy.deepcopy(manifest)
            altered["round2_art"]["recipes"][0]["source_path"] = path
            with self.assertRaisesRegex(ValueError, "path"):
                module.validate_manifest(self.workspace, altered)
        manifest["round2_art"]["recipes"] *= 2
        with self.assertRaisesRegex(ValueError, "duplicate"):
            module.validate_manifest(self.workspace, manifest)

    def test_generation_failure_is_valid_but_never_complete(self):
        module = implementation(self)
        manifest = self.manifest([self.recipe(status="generation_failed", attempts=[
            {"attempt": n, "status": "generation_failed", "error": "connection failed"} for n in range(1, 5)])])
        module.validate_manifest(self.workspace, manifest)
        queue = module.build_queue(self.workspace, manifest, "style.png", "scenes")
        self.assertEqual(queue["tasks"][0]["attempts_used"], 4)
        self.assertFalse(queue["tasks"][0]["can_generate"])
        self.assertEqual(queue["status"], "needs_builtin_generation")

    def test_attempt_limits_status_and_source_claims_are_validated(self):
        module = implementation(self)
        manifest = self.manifest()
        for change in ({"status": "art_approved"}, {"attempts": [{}]}, {"status": "complete"},
                       {"attempts": [{"attempt": 1, "status": "complete"}] * 5}):
            altered = copy.deepcopy(manifest)
            altered["round2_art"]["recipes"][0].update(change)
            with self.assertRaises(ValueError):
                module.validate_manifest(self.workspace, altered)

    def test_import_records_real_dimensions_hash_cover_and_preserves_source(self):
        module = implementation(self)
        self.image("source.png", size=(100, 100), color=(20, 40, 60))
        before = (self.workspace / "source.png").read_bytes()
        record = module.import_recipe(self.workspace, self.recipe(status="placeholder"))
        self.assertEqual(record["source_size"], [100, 100])
        self.assertEqual(record["runtime_size"], [1920, 1080])
        self.assertEqual(record["transform"]["source_crop"], [0.0, 21.875, 100.0, 78.125])
        self.assertAlmostEqual(record["transform"]["scale"], 19.2)
        self.assertEqual(record["transform"]["filter"], "Lanczos")
        self.assertFalse(record["native_resolution_met"])
        self.assertEqual(record["source_sha256"], hashlib.sha256(before).hexdigest())
        self.assertEqual(record["runtime_sha256"], hashlib.sha256((self.workspace / "runtime.png").read_bytes()).hexdigest())
        self.assertEqual(record["status"], "placeholder")
        self.assertEqual((self.workspace / "source.png").read_bytes(), before)

    def test_existing_runtime_or_source_cannot_be_overwritten(self):
        module = implementation(self)
        self.image("source.png")
        self.image("runtime.png", color="red")
        before = (self.workspace / "runtime.png").read_bytes()
        with self.assertRaisesRegex(FileExistsError, "existing"):
            module.import_recipe(self.workspace, self.recipe())
        self.assertEqual((self.workspace / "runtime.png").read_bytes(), before)
        with self.assertRaisesRegex(ValueError, "source"):
            module.import_recipe(self.workspace, self.recipe(runtime_path="source.png"))

    def test_prepare_masks_has_one_pixel_feather_and_six_pixel_target(self):
        module = implementation(self)
        hard = Image.new("L", (40, 40), 0)
        ImageDraw.Draw(hard).rectangle((15, 15, 24, 24), fill=255)
        hard.save(self.workspace / "hard.png")
        paths = module.prepare_masks(self.workspace, "hard.png", "soft.png", "target.png")
        with Image.open(self.workspace / paths["mask_path"]) as feather:
            self.assertEqual(feather.getpixel((13, 20)), 0)
            self.assertGreater(feather.getpixel((14, 20)), 0)
            self.assertEqual(feather.getpixel((16, 20)), 255)
        with Image.open(self.workspace / paths["inpaint_mask_path"]) as target:
            self.assertEqual(target.getbbox(), (9, 9, 31, 31))
        self.assertFalse(paths["local_repaint_performed"])

    def test_per_layer_geometry_pass_does_not_claim_art_approval(self):
        module = implementation(self)
        recipe = self.fixture()
        qa = module.qa_recipe(self.workspace, recipe)
        self.assertTrue(qa["geometry_passed"])
        self.assertFalse(qa["art_passed"])
        self.assertEqual(qa["visual_review"], "not_evaluated")
        self.assertEqual(qa["regions"]["core"]["max_error"], 0)
        self.assertEqual(qa["regions"]["unedited"]["max_error"], 0)

    def test_tiny_missing_layer_cannot_hide_in_global_mean(self):
        module = implementation(self)
        recipe = self.fixture()
        with Image.open(self.workspace / "layer.png") as source:
            changed = source.copy()
        changed.putalpha(Image.new("L", changed.size, 0))
        changed.save(self.workspace / "layer.png")
        qa = module.qa_recipe(self.workspace, recipe)
        self.assertFalse(qa["geometry_passed"])
        self.assertFalse(qa["alpha_matches_mask"])

    def test_single_unchanged_region_pixel_fails_exactness(self):
        module = implementation(self)
        recipe = self.fixture()
        with Image.open(self.workspace / "clean.png") as source:
            changed = source.copy()
        changed.putpixel((0, 0), (131, 145, 150))
        changed.save(self.workspace / "clean.png")
        qa = module.qa_recipe(self.workspace, recipe)
        self.assertFalse(qa["geometry_passed"])
        self.assertEqual(qa["regions"]["unedited"]["max_error"], 1)

    def test_mask_size_misalignment_is_rejected(self):
        module = implementation(self)
        recipe = self.fixture()
        self.image("mask.png", size=(31, 24), color=0, mode="L")
        with self.assertRaisesRegex(ValueError, "size"):
            module.qa_recipe(self.workspace, recipe)

    def test_feather_percentile_rejects_local_bad_repaint(self):
        module = implementation(self)
        original = Image.new("RGB", (100, 100), "white")
        changed = original.copy()
        # Only ten pixels: globally negligible, but the entire feather ROI is wrong.
        feather = Image.new("L", original.size, 0)
        for x in range(10):
            feather.putpixel((x, 10), 128)
            changed.putpixel((x, 10), (240, 240, 240))
        qa = module.compare_regions(original, changed, feather)
        self.assertFalse(qa["passed"])
        self.assertEqual(qa["regions"]["feather"]["p95"], 15)

    def test_all_layers_recompose_sorted_and_reject_duplicate_z(self):
        module = implementation(self)
        recipe = self.fixture()
        spec = dict(id="whole", original_path="original.png", base_path="clean.png",
                    layers=[dict(path="layer.png", z_index=2)], qa_kind="geometry_only")
        qa = module.qa_recomposition(self.workspace, spec)
        self.assertTrue(qa["geometry_passed"])
        self.assertFalse(qa["art_passed"])
        spec["layers"].append(dict(path="layer.png", z_index=2))
        with self.assertRaisesRegex(ValueError, "duplicate"):
            module.qa_recomposition(self.workspace, spec)

    def test_new_config_has_finite_validated_bounds(self):
        module = implementation(self)
        config = module.load_config()
        for key, bad in (("feather_mae", float("nan")), ("feather_p95", 256), ("core_max_error", -1)):
            altered = copy.deepcopy(config)
            altered["qa"][key] = bad
            with self.assertRaises(ValueError):
                module.validate_config(altered)

    def test_cli_queue_is_executable_and_does_not_mutate_manifest(self):
        implementation(self)
        manifest = self.manifest()
        path = self.workspace / "manifest.json"
        path.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
        before = path.read_bytes()
        result = subprocess.run([__import__("sys").executable, str(SCRIPT), "--workspace", str(self.workspace),
            "--manifest", "manifest.json", "--style", "style.png", "--only", "scenes", "--output", "receipt.json"],
            capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads((self.workspace / "receipt.json").read_text(encoding="utf-8"))
        self.assertEqual(receipt["status"], "needs_builtin_generation")
        self.assertEqual(path.read_bytes(), before)

    def test_active_style_hash_tampering_is_rejected(self):
        module = implementation(self)
        manifest = self.manifest()
        manifest["round2_art"]["active_style"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "sha256"):
            module.build_queue(self.workspace, manifest, "style.png", "scenes")

    def test_inpaint_queue_accepts_original_without_extraction_trio(self):
        module = implementation(self)
        self.image("original.png")
        self.image("target.png", color=0, mode="L")
        manifest = self.manifest([self.recipe(operation="inpaint_cleanplate", original_path="original.png",
                                              inpaint_mask_path="target.png")])
        queue = module.build_queue(self.workspace, manifest, "style.png", "scenes")
        self.assertEqual(len(queue["tasks"][0]["arguments"]["referenced_image_paths"]), 3)
        self.assertIn("保持原画布尺寸", queue["tasks"][0]["arguments"]["prompt"])

    def test_extraction_uses_original_pixels_and_actual_mask_without_inpainting(self):
        module = implementation(self)
        recipe = self.fixture()
        result = module.extract_layer(self.workspace, "original.png", "mask.png", "extracted.png")
        with Image.open(self.workspace / "extracted.png") as layer, Image.open(self.workspace / "original.png") as original:
            self.assertEqual(layer.getpixel((10, 10))[:3], original.getpixel((10, 10)))
            self.assertEqual(layer.getpixel((0, 0))[3], 0)
        self.assertFalse(result["local_repaint_performed"])

    def test_import_map_copies_real_builtin_output_and_emits_runtime_copies(self):
        module = implementation(self)
        manifest = self.manifest()
        self.image("incoming.png", size=(200, 100), color=(35, 65, 85))
        receipt = module.run_pipeline(self.workspace, manifest, "style.png", "scenes", import_map={
            "version": 1, "outputs": {"s02_day": {"path": "incoming.png", "status": "complete", "generator": "builtin_imagegen"}}})
        copy_record = receipt["runtime_copies"][0]
        self.assertEqual(copy_record["native_size"], [200, 100])
        self.assertEqual(copy_record["path"], "runtime.png")
        self.assertAlmostEqual(copy_record["scale_x"], 10.8)
        self.assertEqual(copy_record["scale_x"], copy_record["scale_y"])
        self.assertEqual(copy_record["source_sha256"], hashlib.sha256((self.workspace / "incoming.png").read_bytes()).hexdigest())
        self.assertEqual(receipt["round2_art"]["recipes"][0]["status"], "complete")
        self.assertEqual(manifest["round2_art"]["recipes"][0]["status"], "needs_builtin_generation")

    def test_runtime_metadata_is_read_from_files_instead_of_trusting_claims(self):
        module = implementation(self)
        self.image("source.png", size=(30, 20))
        record = module.import_recipe(self.workspace, self.recipe(source_size=[9999, 9999], source_sha256="fake", native_resolution_met=True))
        self.assertEqual(record["source_size"], [30, 20])
        self.assertNotEqual(record["source_sha256"], "fake")
        self.assertFalse(record["native_resolution_met"])

    def test_powershell_wrapper_runs_real_queue_without_generation_service(self):
        implementation(self)
        manifest = self.manifest()
        (self.workspace / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        # The wrapper uses its repository as workspace; fixture inputs are copied
        # into a scoped temporary directory within that workspace for this run.
        with tempfile.TemporaryDirectory(dir=ROOT / ".tools") as inside:
            directory = Path(inside)
            prefix = directory.relative_to(ROOT).as_posix()
            self.image("style.png")
            (directory / "style.png").write_bytes((self.workspace / "style.png").read_bytes())
            for entry in manifest["round2_art"]["recipes"]:
                for field in ("style_reference", "source_path", "runtime_path"):
                    entry[field] = prefix + "/" + entry[field]
            manifest["round2_art"]["active_style"]["path"] = prefix + "/style.png"
            (directory / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "tools/regen_art.ps1"),
                "-Style", prefix + "/style.png", "-Only", "scenes", "-Manifest", prefix + "/manifest.json", "-Output", prefix + "/receipt.json",
                "-Python", __import__("sys").executable], capture_output=True, text=True, encoding="utf-8", errors="replace")
            self.assertEqual(result.returncode, 0, result.stderr)
            receipt = json.loads((directory / "receipt.json").read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "needs_builtin_generation")
            self.assertEqual(receipt["imports"], [])

    def test_layer_queue_extracts_pixels_instead_of_redrawing_detached_object(self):
        module = implementation(self)
        layer = self.fixture()
        manifest = self.manifest([layer])
        queue = module.build_queue(self.workspace, manifest, "style.png", "layers")
        self.assertTrue(any(task["operation"] == "extract_layer" for task in queue["offline_tasks"]))
        self.assertTrue(all(task["source_destination"] != "layer.png" for task in queue["tasks"]))
        self.assertTrue(any(task["source_destination"] == "clean.png" for task in queue["tasks"]))

    def test_feather_decontamination_does_not_weaken_opaque_core_check(self):
        module = implementation(self)
        recipe = self.fixture()
        # An edge may be decontaminated using its known cleanplate. Opaque
        # pixels must still be exact C; RGB in a feather pixel is not that core.
        mask = Image.new("L", (32, 24), 0)
        ImageDraw.Draw(mask).rectangle((9, 7, 16, 14), fill=255)
        mask.putpixel((8, 7), 128)
        mask.save(self.workspace / "mask.png")
        with Image.open(self.workspace / "original.png") as original:
            layer = original.convert("RGBA")
        layer.putalpha(mask)
        layer.putpixel((8, 7), (131, 145, 150, 128))
        layer.save(self.workspace / "layer.png")
        self.assertTrue(module.qa_recipe(self.workspace, recipe)["geometry_passed"])
        layer.putpixel((10, 10), (1, 2, 3, 255))
        layer.save(self.workspace / "layer.png")
        self.assertFalse(module.qa_recipe(self.workspace, recipe)["geometry_passed"])

    def test_receipt_validator_rejects_changed_runtime_bytes(self):
        module = implementation(self)
        manifest = self.manifest()
        self.image("source.png", size=(40, 30))
        receipt = module.run_pipeline(self.workspace, manifest, "style.png", "scenes")
        module.validate_receipt(self.workspace, receipt)
        self.image("runtime.png", size=(1920, 1080), color="red")
        with self.assertRaisesRegex(ValueError, "sha256"):
            module.validate_receipt(self.workspace, receipt)

    def test_mask_and_extraction_helpers_are_executable_from_queue(self):
        implementation(self)
        self.fixture()
        command = [__import__("sys").executable, str(SCRIPT), "--workspace", str(self.workspace)]
        result = subprocess.run(command + ["--extract-layer", "original.png", "mask.png", "extracted-cli.png"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.workspace / "extracted-cli.png").is_file())
        result = subprocess.run(command + ["--prepare-masks", "mask.png", "soft-cli.png", "target-cli.png"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        with Image.open(self.workspace / "target-cli.png") as target:
            self.assertEqual(target.getbbox(), (3, 1, 23, 21))

    def versioned_scene(self):
        self.fixture()
        base = self.recipe(id="scene", source_path="v4/base.png", runtime_path="v4/runtime/base.png")
        layer = self.recipe(id="leaf", group="layers", operation="extract_layer", source_path="v4/leaf.png",
            runtime_path="v4/runtime/leaf.png", original_path="v4/composite.png", mask_path="mask.png",
            cleanplate_path="v4/clean.png", qa_kind="geometry_only")
        manifest = self.manifest([base, layer])
        manifest["round2_art"].update(preview_only=True, art_passed=False, recompositions=[dict(
            id="whole", original_path="v4/composite.png", reference_path="original.png", base_path="v4/base.png",
            layers=[dict(path="v4/leaf.png", z_index=1)], qa_kind="geometry_only")])
        incoming = Image.new("RGB", (32, 24), (131, 146, 151))
        ImageDraw.Draw(incoming).rectangle((10, 8, 15, 13), fill=(80, 95, 100))
        incoming.save(self.workspace / "incoming-c.png")
        self.image("incoming-clean.png", size=(32, 24), color=(131, 146, 151))
        return manifest

    def test_versioned_queue_separates_old_reference_from_deferred_output(self):
        module = implementation(self)
        manifest = self.versioned_scene()
        queue = module.build_queue(self.workspace, manifest, "style.png", "all")
        tasks = {task["recipe_id"]: task for task in queue["tasks"]}
        composite = tasks["whole__composite"]
        self.assertTrue(composite["ready"])
        self.assertEqual(composite["source_destination"], "v4/composite.png")
        self.assertIn((self.workspace / "original.png").resolve(),
            [Path(path).resolve() for path in composite["arguments"]["referenced_image_paths"]])
        self.assertNotIn((self.workspace / "v4/composite.png").resolve(),
            [Path(path).resolve() for path in composite["arguments"]["referenced_image_paths"]])
        self.assertFalse(tasks["leaf__cleanplate"]["ready"])
        self.assertIn("v4/composite.png", tasks["leaf__cleanplate"]["missing_dependencies"])
        self.assertFalse((self.workspace / "v4").exists())

    def test_versioned_import_closes_composite_cleanplate_extraction_base_workflow(self):
        module = implementation(self)
        manifest = self.versioned_scene()
        old_sha = hashlib.sha256((self.workspace / "original.png").read_bytes()).hexdigest()
        first = module.run_pipeline(self.workspace, manifest, "style.png", "all", import_map={"version": 1,
            "outputs": {"whole__composite": {"path": "incoming-c.png", "status": "complete", "generator": "builtin_imagegen"}}})
        self.assertIsNone(first["geometry_passed"])
        self.assertTrue(first["pending_qa"])
        self.assertFalse((self.workspace / "v4/leaf.png").exists())
        composite = next(item for item in first["round2_art"]["artifacts"] if item["id"] == "whole__composite")
        self.assertEqual(composite["sha256"], hashlib.sha256((self.workspace / "incoming-c.png").read_bytes()).hexdigest())
        second = module.run_pipeline(self.workspace, {"round2_art": first["round2_art"]}, "style.png", "all", import_map={"version": 1,
            "outputs": {"leaf__cleanplate": {"path": "incoming-clean.png", "status": "complete", "generator": "builtin_imagegen"}}})
        self.assertTrue((self.workspace / "v4/leaf.png").is_file())
        self.assertTrue(second["single_layer_qa"][0]["geometry_passed"])
        self.assertTrue(second["pending_qa"])
        third = module.run_pipeline(self.workspace, {"round2_art": second["round2_art"]}, "style.png", "all", import_map={"version": 1,
            "outputs": {"scene": {"path": "incoming-clean.png", "status": "complete", "generator": "builtin_imagegen"}}})
        self.assertTrue(third["geometry_passed"])
        self.assertFalse(third["pending_qa"])
        self.assertEqual(third["status"], "complete")
        self.assertEqual(len(third["runtime_copies"]), 2)
        self.assertTrue(third["round2_art"]["preview_only"])
        self.assertFalse(third["art_passed"])
        self.assertFalse(third["round2_art"]["art_passed"])
        self.assertEqual(len(third["round2_art"]["recipes"]), 2)
        self.assertEqual(hashlib.sha256((self.workspace / "original.png").read_bytes()).hexdigest(), old_sha)
        for artifact in third["round2_art"]["artifacts"]:
            self.assertEqual(artifact["sha256"], hashlib.sha256((self.workspace / artifact["path"]).read_bytes()).hexdigest())
        module.validate_receipt(self.workspace, third)

    def test_unknown_import_id_is_rejected_before_any_valid_output_is_copied(self):
        module = implementation(self)
        manifest = self.versioned_scene()
        with self.assertRaisesRegex(ValueError, "unknown"):
            module.run_pipeline(self.workspace, manifest, "style.png", "all", import_map={"version": 1, "outputs": {
                "whole__composite": {"path": "incoming-c.png", "status": "complete"},
                "unknown_task": {"path": "incoming-clean.png", "status": "complete"}}})
        self.assertFalse((self.workspace / "v4").exists())

    def test_dependent_import_before_composite_is_rejected_without_writes(self):
        module = implementation(self)
        manifest = self.versioned_scene()
        with self.assertRaisesRegex(ValueError, "dependenc"):
            module.run_pipeline(self.workspace, manifest, "style.png", "all", import_map={"version": 1, "outputs": {
                "leaf__cleanplate": {"path": "incoming-clean.png", "status": "complete"}}})
        self.assertFalse((self.workspace / "v4").exists())

    def test_derived_composite_import_never_overwrites_old_reference(self):
        module = implementation(self)
        manifest = self.versioned_scene()
        manifest["round2_art"]["recipes"][1]["original_path"] = "original.png"
        manifest["round2_art"]["recompositions"][0]["original_path"] = "original.png"
        old_bytes = (self.workspace / "original.png").read_bytes()
        with self.assertRaisesRegex(FileExistsError, "existing"):
            module.run_pipeline(self.workspace, manifest, "style.png", "all", import_map={"version": 1, "outputs": {
                "whole__composite": {"path": "incoming-c.png", "status": "complete"}}})
        self.assertEqual((self.workspace / "original.png").read_bytes(), old_bytes)

    def test_partial_group_receipt_keeps_other_recipes_and_preview_contract(self):
        module = implementation(self)
        manifest = self.versioned_scene()
        receipt = module.run_pipeline(self.workspace, manifest, "style.png", "scenes")
        self.assertEqual({recipe["id"] for recipe in receipt["round2_art"]["recipes"]}, {"scene", "leaf"})
        self.assertTrue(receipt["round2_art"]["preview_only"])
        self.assertFalse(receipt["round2_art"]["art_passed"])
        self.assertIsNone(receipt["geometry_passed"])

    def test_s04_two_composites_share_base_and_lamp_without_old_fallback(self):
        module = implementation(self)
        background = Image.new("RGB", (40, 30), (130, 140, 150))
        boxes = {"lamp": (2, 2, 5, 5), "open": (12, 8, 15, 18), "closed": (24, 8, 27, 18)}
        colors = {"lamp": (70, 80, 90), "open": (80, 95, 100), "closed": (100, 105, 110)}
        originals = {}
        for state in ("open", "closed"):
            image = background.copy()
            for name in ("lamp", state):
                ImageDraw.Draw(image).rectangle(boxes[name], fill=colors[name])
            image.save(self.workspace / ("incoming-" + state + ".png"))
            image.save(self.workspace / ("old-" + state + ".png"))
            originals[state] = image
        background.save(self.workspace / "incoming-base.png")
        recipes = [self.recipe(id="base", source_path="v4/base.png", runtime_path="v4/runtime/base.png")]
        for name, state in (("lamp", "open"), ("open", "open"), ("closed", "closed")):
            mask = Image.new("L", background.size, 0)
            ImageDraw.Draw(mask).rectangle(boxes[name], fill=255)
            mask.save(self.workspace / (name + "-mask.png"))
            clean = originals[state].copy()
            ImageDraw.Draw(clean).rectangle(boxes[name], fill=(130, 140, 150))
            clean.save(self.workspace / ("incoming-" + name + "-clean.png"))
            recipes.append(self.recipe(id=name, group="layers", operation="extract_layer", source_path="v4/" + name + ".png",
                runtime_path="v4/runtime/" + name + ".png", original_path="v4/" + state + "-c.png",
                mask_path=name + "-mask.png", cleanplate_path="v4/" + name + "-clean.png", qa_kind="geometry_only"))
        manifest = self.manifest(recipes)
        manifest["round2_art"]["recompositions"] = [dict(id="S04_" + state, original_path="v4/" + state + "-c.png",
            reference_path="old-" + state + ".png", base_path="v4/base.png", qa_kind="geometry_only",
            layers=[dict(path="v4/lamp.png", z_index=1), dict(path="v4/" + state + ".png", z_index=2)]) for state in ("open", "closed")]
        first = module.run_pipeline(self.workspace, manifest, "style.png", "all", import_map={"version": 1, "outputs": {
            "S04_open__composite": {"path": "incoming-open.png", "status": "complete"}}})
        self.assertFalse((self.workspace / "v4/closed-c.png").exists())
        self.assertTrue(any("v4/closed-c.png" in qa["missing_paths"] for qa in first["pending_qa"]))
        self.assertIsNone(first["geometry_passed"])
        outputs = {"S04_closed__composite": {"path": "incoming-closed.png", "status": "complete"},
                   "base": {"path": "incoming-base.png", "status": "complete"}}
        for name in ("lamp", "open", "closed"):
            outputs[name + "__cleanplate"] = {"path": "incoming-" + name + "-clean.png", "status": "complete"}
        final = module.run_pipeline(self.workspace, {"round2_art": first["round2_art"]}, "style.png", "all",
                                    import_map={"version": 1, "outputs": outputs})
        self.assertTrue(final["geometry_passed"])
        self.assertEqual(len(final["single_layer_qa"]), 3)
        self.assertEqual(len(final["recomposition_qa"]), 2)
        self.assertEqual(final["status"], "complete")
        self.assertFalse(final["pending_qa"])

    def test_powershell_versioned_three_stage_import_is_executable(self):
        implementation(self)
        with tempfile.TemporaryDirectory(dir=ROOT / ".tools") as temporary:
            directory = Path(temporary)
            prefix = directory.relative_to(ROOT).as_posix()
            saved_workspace = self.workspace
            self.workspace = directory
            try:
                manifest = self.versioned_scene()
            finally:
                self.workspace = saved_workspace

            def prefix_paths(value):
                if isinstance(value, dict):
                    return {key: prefix + "/" + item if key in ("path", "source_path", "runtime_path", "original_path", "reference_path",
                        "base_path", "mask_path", "cleanplate_path", "style_reference") and isinstance(item, str)
                        else prefix_paths(item) for key, item in value.items()}
                if isinstance(value, list):
                    return [prefix_paths(item) for item in value]
                return value

            manifest = prefix_paths(manifest)
            for step, (identifier, incoming) in enumerate((("whole__composite", "incoming-c.png"),
                ("leaf__cleanplate", "incoming-clean.png"), ("scene", "incoming-clean.png")), 1):
                manifest_name = "manifest-1.json" if step == 1 else f"receipt-{step - 1}.json"
                if step == 1:
                    (directory / manifest_name).write_text(json.dumps(manifest), encoding="utf-8")
                (directory / f"import-{step}.json").write_text(json.dumps({"version": 1, "outputs": {
                    identifier: {"path": prefix + "/" + incoming, "status": "complete", "generator": "builtin_imagegen"}}}), encoding="utf-8")
                result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "tools/regen_art.ps1"),
                    "-Style", prefix + "/style.png", "-Only", "all", "-Manifest", prefix + "/" + manifest_name,
                    "-ImportMap", prefix + f"/import-{step}.json", "-Output", prefix + f"/receipt-{step}.json",
                    "-Python", __import__("sys").executable], capture_output=True, text=True, encoding="utf-8", errors="replace")
                self.assertEqual(result.returncode, 0, result.stderr)
                receipt = json.loads((directory / f"receipt-{step}.json").read_text(encoding="utf-8"))
                manifest = {"round2_art": receipt["round2_art"]}
            self.assertTrue(receipt["geometry_passed"])
            self.assertEqual(receipt["status"], "complete")
            self.assertEqual(len(receipt["runtime_copies"]), 2)

    def test_malformed_import_map_fails_validation_before_any_outputs(self):
        module = implementation(self)
        manifest = self.versioned_scene()
        for value in ([], "wrong JSON type", {"version": 1, "outputs": []}):
            with self.assertRaisesRegex(ValueError, "import map"):
                module.run_pipeline(self.workspace, manifest, "style.png", "all", import_map=value)
        self.assertFalse((self.workspace / "v4").exists())


if __name__ == "__main__":
    unittest.main()
