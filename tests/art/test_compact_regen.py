"""Compact manifests queue approved edits without reviving retired recipes."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/art_pipeline.py"


def implementation():
    spec = importlib.util.spec_from_file_location("compact_art_pipeline", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CompactRegenTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.rows = []
        for path in ("assets/generated_scenes/v2/S02_day.png", "assets/generated_scenes/v2/S02_night.png",
                     "assets/generated_scenes/v2/slices/S02_door.png", "assets/items/inventory-atlas-v2.png",
                     "assets/items/inventory-reference.png", "assets/portraits/npc_lin_neutral.png",
                     "assets/portraits/npc_character_reference_sheet.png"):
            self.rows.append(self.image_record(path))
        runtime = self.image_record("assets/generated_scenes/runtime/v2/S02_day.png")
        runtime["inputs"] = [self.rows[0]["path"]]
        self.rows.append(runtime)
        self.style = self.image_record("assets/styles/v3_selected.png")
        self.manifest = {"schema_version": 3, "assets": self.rows,
                         "runtime_copies": [{"path": runtime["path"], "source_path": self.rows[0]["path"]}],
                         "style_profiles": {"v3": {"status": "selected", "reference": {
                             "path": self.style["path"], "sha256": self.style["sha256"]}, "revision": "draft1",
                             "templates": {"edit": "USER V3 EDIT. No text.",
                                           "night": "USER V3 NIGHT. Preserve composition.",
                                           "item": "USER V3 ITEM. No labels.",
                                           "portrait": "USER V3 PORTRAIT. Retain the guest."}}}}

    def image_record(self, path):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (16, 12), (120, 130, 140)).save(target)
        return {"path": path, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                "dim": [16, 12], "prompt": "RETIRED OLD STYLE INSTRUCTIONS MUST NOT BE USED"}

    def formal_scene(self, scene, period, state=None):
        suffix = period + ("_" + state if state else "")
        row = self.image_record(f"assets/generated_scenes/v3_final/{scene}/{suffix}/v3r1/C.png")
        row.update(group="scenes", scene_id=scene, period=period)
        if state:
            row["state"] = state
        return row

    def formal_slice(self, composite, operation="extract_layer"):
        suffix = "layers/door_open.png" if operation == "extract_layer" else "B_all.png"
        row = self.image_record(composite["path"].removesuffix("C.png") + suffix)
        row.update(group="slices", operation=operation, composite_source=composite["path"],
                   processing_script="tools/art/real_scene_layers.py", local_spec=".tools/day_layers.json")
        return row

    def use_formal_rows(self, *rows):
        self.manifest["assets"] = list(rows)
        self.manifest["runtime_copies"] = []

    def test_formal_c_night_metadata_pairs_the_same_scene_and_state_day(self):
        module = implementation()
        rows = [self.formal_scene("S04", period, state)
                for state in ("open", "closed") for period in ("day", "night")]
        self.use_formal_rows(*rows)
        tasks = module.build_queue(self.root, self.manifest, "v3", "scenes")["tasks"]
        for state in ("open", "closed"):
            day = next(t for t in tasks if f"/day_{state}/" in t["previous_source_path"])
            night = next(t for t in tasks if f"/night_{state}/" in t["previous_source_path"])
            with self.subTest(state=state):
                self.assertTrue(night["arguments"]["prompt"].startswith("USER V3 NIGHT"))
                self.assertEqual(night["depends_on"], [day["source_destination"]])
                self.assertFalse(night["can_generate"])
                self.assertIn(str((self.root / day["source_destination"]).resolve()),
                              night["arguments"]["referenced_image_paths"])

    def test_formal_s01_closed_uses_closed_template_and_new_night(self):
        module = implementation()
        self.use_formal_rows(*(self.formal_scene("S01", p) for p in ("day", "night", "closed")))
        self.manifest["style_profiles"]["v3"]["templates"]["closed"] = "USER V3 CLOSED. Shut the shop."
        tasks = module.build_queue(self.root, self.manifest, "v3", "scenes")["tasks"]
        night = next(t for t in tasks if "/night/" in t["previous_source_path"])
        closed = next(t for t in tasks if "/closed/" in t["previous_source_path"])
        self.assertTrue(closed["arguments"]["prompt"].startswith("USER V3 CLOSED"))
        self.assertEqual(closed["depends_on"], [night["source_destination"]])
        self.assertFalse(closed["can_generate"])

    def test_formal_closed_missing_template_is_pending_not_day_repaint(self):
        module = implementation()
        self.use_formal_rows(*(self.formal_scene("S01", p) for p in ("day", "night", "closed")))
        queue = module.build_queue(self.root, self.manifest, "v3", "scenes")
        self.assertEqual(queue["status"], "pending_templates")
        self.assertEqual(queue["missing_templates"], ["closed"])
        self.assertEqual(queue["tasks"], [])

    def test_formal_night_never_borrows_day_from_another_state(self):
        module = implementation()
        self.use_formal_rows(self.formal_scene("S04", "day", "closed"),
                             self.formal_scene("S04", "night", "open"))
        with self.assertRaisesRegex(ValueError, "day"):
            module.build_queue(self.root, self.manifest, "v3", "scenes")

    def test_formal_processing_rows_are_offline_without_room_templates(self):
        module = implementation()
        composite = self.formal_scene("S04", "day", "open")
        layer = self.formal_slice(composite)
        cleanplate = self.formal_slice(composite, "inpaint_cleanplate")
        layer["mask_path"] = ".tools/missing_mask.png"
        layer["source_receipt"] = ".tools/missing_old_audit.json"
        self.use_formal_rows(composite, layer, cleanplate)
        self.manifest["style_profiles"]["v3"]["templates"] = {}
        queue = module.build_queue(self.root, self.manifest, "v3", "slices")
        self.assertEqual(queue["tasks"], [])
        self.assertEqual(queue["status"], "needs_mask_review")
        self.assertEqual({t["operation"] for t in queue["offline_tasks"]},
                         {"extract_layer", "inpaint_cleanplate"})
        task = next(t for t in queue["offline_tasks"] if t["operation"] == "extract_layer")
        self.assertEqual(task["status"], "needs_mask_review")
        self.assertEqual(task["phase"], "awaiting_composite")
        self.assertFalse(task["can_process"])
        self.assertEqual(task["processing_script"], "tools/art/real_scene_layers.py")
        self.assertEqual(task["local_spec"], ".tools/day_layers.json")
        self.assertIn(".tools/day_layers.json", task["missing_paths"])
        self.assertIn(".tools/missing_mask.png", task["missing_paths"])
        self.assertIn(".tools/missing_old_audit.json", task["missing_paths"])
        self.assertEqual(task["depends_on"], [
            "assets/art_versions/v3/draft1/generated_scenes/v3_final/S04/day_open/v3r1/C.png"])

    def test_formal_runtime_waits_for_its_processed_layer_not_composite(self):
        module = implementation()
        composite = self.formal_scene("S04", "day", "open")
        layer = self.formal_slice(composite)
        runtime = self.image_record("assets/generated_scenes/runtime/v3_final/S04/day_open/v3r1/layers/door_open.png")
        self.use_formal_rows(composite, layer, runtime)
        self.manifest["runtime_copies"] = [{"path": runtime["path"], "source_path": layer["path"]}]
        queue = module.build_queue(self.root, self.manifest, "v3", "all")
        self.assertEqual(len(queue["tasks"]), 1)
        processed = next(t for t in queue["offline_tasks"] if t["operation"] == "extract_layer")
        copied = next(t for t in queue["offline_tasks"] if t["operation"] == "runtime_copy")
        self.assertEqual(processed["source_destination"],
                         "assets/generated_scenes/v3_regen/draft1/S04/day_open/v3r1/layers/door_open.png")
        self.assertEqual(copied["source_path"], processed["source_destination"])
        self.assertEqual(copied["depends_on"], [processed["source_destination"]])
        self.assertEqual(copied["runtime_path"],
                         "assets/generated_scenes/runtime/v3_regen/draft1/S04/day_open/v3r1/layers/door_open.png")
        self.assertNotEqual(copied["source_path"], queue["tasks"][0]["source_destination"])

    def test_processing_runtime_aliases_preserve_additional_copy_destinations(self):
        module = implementation()
        composite = self.formal_scene("S04", "day", "open")
        layer = self.formal_slice(composite)
        runtime = self.image_record("assets/generated_scenes/runtime/v3_final/S04/day_open/v3r1/layers/door_open.png")
        alias = self.image_record("assets/generated_scenes/runtime/extra/S04/day_open/v3r1/layers/door_open.png")
        self.use_formal_rows(composite, layer, runtime, alias)
        self.manifest["runtime_copies"] = [{"path": runtime["path"], "source_path": layer["path"]},
                                           {"path": alias["path"], "source_path": runtime["path"]}]
        queue = module.build_queue(self.root, self.manifest, "v3", "slices")
        copies = [t for t in queue["offline_tasks"] if t["operation"] == "runtime_copy"]
        self.assertEqual(len(copies), 2)
        self.assertEqual(len({t["runtime_path"] for t in copies}), 2)
        self.assertEqual({t["source_path"] for t in copies}, {
            "assets/generated_scenes/v3_regen/draft1/S04/day_open/v3r1/layers/door_open.png"})
        self.assertIn("assets/generated_scenes/runtime/v3_regen/draft1/S04/day_open/v3r1/layers/door_open.png",
                      {t["runtime_path"] for t in copies})

    def test_new_composite_and_old_spec_still_require_manual_mask_review(self):
        module = implementation()
        composite = self.formal_scene("S04", "day", "open")
        layer = self.formal_slice(composite)
        self.use_formal_rows(composite, layer)
        for path, text in ((layer["processing_script"], "# existing offline CLI"),
                           (layer["local_spec"], json.dumps({"original_path": composite["path"]}))):
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")
        self.image_record("assets/art_versions/v3/draft1/generated_scenes/v3_final/S04/day_open/v3r1/C.png")
        queue = module.build_queue(self.root, self.manifest, "v3", "slices")
        self.assertEqual(len(queue["offline_tasks"]), 1)
        task = queue["offline_tasks"][0]
        self.assertEqual(task["phase"], "mask_review")
        self.assertEqual(task["status"], "needs_mask_review")
        self.assertFalse(task["can_process"])
        self.assertEqual(task["missing_paths"], [])

    def test_formal_processing_references_keep_existing_safe_path_boundary(self):
        module = implementation()
        composite = self.formal_scene("S04", "day", "open")
        for field in ("composite_source", "processing_script", "local_spec", "mask_path", "source_receipt"):
            layer = self.formal_slice(composite)
            layer[field] = "../escape"
            self.use_formal_rows(composite, layer)
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "path"):
                module.build_queue(self.root, self.manifest, "v3", "slices")

    def test_scene_generation_appends_constraints_from_asset_data(self):
        module = implementation()
        for scene, state, constraints in (
                ("S04", "open", "Keep every shelf empty and both cabinet doors open."),
                ("S02", None, "Preserve the room-specific window layout.")):
            row = self.formal_scene(scene, "day", state)
            row["regeneration_constraints"] = constraints
            self.use_formal_rows(row)
            queue = module.build_queue(self.root, self.manifest, "v3", "scenes")
            prompt = queue["tasks"][0]["arguments"]["prompt"]
            with self.subTest(scene=scene):
                self.assertTrue(prompt.startswith("USER V3 EDIT"))
                self.assertTrue(prompt.endswith(constraints))

    def test_scene_constraints_reject_non_string_data(self):
        module = implementation()
        row = self.formal_scene("S04", "day", "open")
        row["regeneration_constraints"] = {"shelves": "empty"}
        self.use_formal_rows(row)
        with self.assertRaisesRegex(ValueError, "constraints"):
            module.build_queue(self.root, self.manifest, "v3", "scenes")

    def test_new_native_c_requires_scene_and_period_metadata(self):
        module = implementation()
        for period in ("day", "night"):
            for removed in (("scene_id",), ("period",), ("scene_id", "period")):
                row = self.formal_scene("S02", period)
                for field in removed:
                    row.pop(field)
                self.use_formal_rows(row)
                with self.subTest(period=period, removed=removed), self.assertRaisesRegex(ValueError, "identity|metadata"):
                    module.build_queue(self.root, self.manifest, "v3", "scenes")

    def test_native_c_metadata_validation_uses_asset_path_with_style_inputs(self):
        module = implementation()
        row = self.formal_scene("S02", "night")
        row["inputs"] = [self.style["path"]]
        for field in ("scene_id", "period", "state"):
            row.pop(field, None)
        self.use_formal_rows(row)
        with self.assertRaisesRegex(ValueError, "identity|metadata"):
            module.build_queue(self.root, self.manifest, "v3", "scenes")

    def test_s04_native_c_requires_explicit_open_or_closed_state(self):
        module = implementation()
        for period in ("day", "night"):
            for value in (None, "missing"):
                row = self.formal_scene("S04", period, "open")
                if value == "missing":
                    row.pop("state")
                else:
                    row["state"] = value
                self.use_formal_rows(row)
                with self.subTest(period=period, state=value), self.assertRaisesRegex(ValueError, "state"):
                    module.validate_compact_manifest(self.root, self.manifest)

    def test_explicit_slice_operation_never_falls_back_to_imagegen(self):
        module = implementation()
        composite = self.formal_scene("S04", "day", "open")
        for operation in ("extract_layer_typo", "generate", None):
            layer = self.formal_slice(composite)
            if operation is None:
                layer.pop("operation")
            else:
                layer["operation"] = operation
            self.use_formal_rows(composite, layer)
            with self.subTest(operation=operation), self.assertRaisesRegex(ValueError, "operation"):
                module.build_queue(self.root, self.manifest, "v3", "slices")

    def test_missing_or_unselected_v3_profile_is_explicit_pending_without_generation(self):
        module = implementation()
        for profile in (None, {"status": "pending"}, {"status": "retired"}):
            value = copy.deepcopy(self.manifest)
            value["style_profiles"] = {} if profile is None else {"v3": profile}
            before = copy.deepcopy(value)
            result = module.run_pipeline(self.root, value, "v3", "scenes")
            self.assertEqual(result["status"], "pending_style_reference")
            self.assertEqual(result["queue"]["tasks"], [])
            self.assertFalse(result["generation_performed"])
            self.assertFalse(result["art_passed"])
            self.assertEqual(value, before)
            self.assertNotIn("round2_art", result)

    def test_selected_profile_missing_file_is_pending_but_wrong_sha_is_an_error(self):
        module = implementation()
        profile = self.manifest["style_profiles"]["v3"]
        profile["reference"]["path"] = "assets/styles/not-yet-selected.png"
        result = module.build_queue(self.root, self.manifest, "v3", "scenes")
        self.assertEqual(result["status"], "pending_style_reference")
        profile["reference"]["path"] = self.style["path"]
        profile["reference"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "sha256|SHA256"):
            module.build_queue(self.root, self.manifest, "v3", "scenes")

    def test_missing_templates_never_fall_back_to_rejected_old_prompts(self):
        module = implementation()
        self.manifest["style_profiles"]["v3"]["templates"] = {"edit": "USER V3 EDIT"}
        result = module.build_queue(self.root, self.manifest, "v3", "all")
        self.assertEqual(result["status"], "pending_templates")
        self.assertEqual(set(result["missing_templates"]), {"night", "item", "portrait"})
        self.assertEqual(result["tasks"], [])

    def test_portraits_require_their_own_template_and_never_use_no_people_room_edit(self):
        module = implementation()
        templates = self.manifest["style_profiles"]["v3"]["templates"]
        templates.pop("portrait", None)
        templates["edit"] = "ROOM TEMPLATE. No people. Draw the counter and shelves."
        pending = module.build_queue(self.root, self.manifest, "v3", "portraits")
        self.assertEqual(pending["status"], "pending_templates")
        self.assertEqual(pending["missing_templates"], ["portrait"])
        self.assertEqual(pending["tasks"], [])
        self.assertEqual(module.build_queue(self.root, self.manifest, "v3", "slices")["status"], "needs_builtin_generation")
        templates["portrait"] = "PORTRAIT TEMPLATE. Retain the guest and facial features."
        tasks = module.build_queue(self.root, self.manifest, "v3", "portraits")["tasks"]
        self.assertEqual(len(tasks), 1)
        self.assertTrue(tasks[0]["arguments"]["prompt"].startswith(templates["portrait"]))
        self.assertNotIn("ROOM TEMPLATE", tasks[0]["arguments"]["prompt"])
        self.assertNotIn("No people", tasks[0]["arguments"]["prompt"])

    def test_explicit_style_path_overrides_profile_reference_using_actual_new_sha(self):
        module = implementation()
        alternate = self.image_record("assets/styles/alternate.png")
        Image.new("RGB", (16, 12), (90, 100, 110)).save(self.root / alternate["path"])
        actual = hashlib.sha256((self.root / alternate["path"]).read_bytes()).hexdigest()
        self.manifest["style_profiles"]["v3"]["reference"]["sha256"] = "0" * 64
        queue = module.build_queue(self.root, self.manifest, alternate["path"], "items")
        self.assertEqual(queue["active_style"]["path"], alternate["path"])
        self.assertEqual(queue["active_style"]["sha256"], actual)
        self.assertEqual(queue["active_style"]["selection"], "explicit_path")
        self.assertTrue(queue["tasks"][0]["arguments"]["prompt"].startswith("USER V3 ITEM"))

    def test_canonical_queue_deduplicates_runtime_and_keeps_all_outputs_versioned(self):
        module = implementation()
        before = {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        result = module.run_pipeline(self.root, self.manifest, "v3", "all")
        tasks = result["queue"]["tasks"]
        self.assertEqual(len(tasks), 5)
        self.assertEqual({t["group"] for t in tasks}, {"scenes", "slices", "items", "portraits"})
        self.assertEqual(len({t["previous_source_path"] for t in tasks}), 5)
        for task in tasks:
            self.assertEqual(task["tool"], "image_gen.imagegen")
            self.assertTrue(task["source_destination"].startswith("assets/art_versions/v3/draft1/"))
            self.assertNotEqual(task["previous_source_path"], task["source_destination"])
            self.assertNotIn("RETIRED OLD STYLE", task["arguments"]["prompt"])
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()})
        self.assertEqual(len(result["queue"]["offline_tasks"]), 1)
        self.assertNotIn("round2_art", result)

    def test_night_uses_new_day_edit_target_and_waits_for_it(self):
        module = implementation()
        tasks = module.build_queue(self.root, self.manifest, "v3", "scenes")["tasks"]
        day = next(t for t in tasks if t["previous_source_path"].endswith("_day.png"))
        night = next(t for t in tasks if t["previous_source_path"].endswith("_night.png"))
        self.assertTrue(day["can_generate"])
        self.assertFalse(night["can_generate"])
        self.assertIn(day["source_destination"], night["depends_on"])
        self.assertIn(str((self.root / day["source_destination"]).resolve()), night["arguments"]["referenced_image_paths"])
        self.assertTrue(night["arguments"]["prompt"].startswith("USER V3 NIGHT"))

    def test_chained_runtime_aliases_keep_one_generation_and_all_runtime_copies(self):
        module = implementation()
        row = self.image_record("assets/generated_scenes/runtime/second/S02_day.png")
        previous_runtime = self.rows[-1]["path"]
        row["inputs"] = [previous_runtime]
        self.manifest["assets"].append(row)
        self.manifest["runtime_copies"].append({"path": row["path"], "source_path": previous_runtime})
        queue = module.build_queue(self.root, self.manifest, "v3", "scenes")
        self.assertEqual(len(queue["tasks"]), 2)
        self.assertEqual(len(queue["offline_tasks"]), 2)
        self.assertEqual(len({t["source_path"] for t in queue["offline_tasks"]}), 1)

    def test_only_groups_and_template_selection_match_formal_resources(self):
        module = implementation()
        for group, count, prefix in (("scenes", 2, "USER V3"), ("slices", 1, "USER V3 EDIT"),
                                     ("items", 1, "USER V3 ITEM"), ("portraits", 1, "USER V3 PORTRAIT")):
            tasks = module.build_queue(self.root, self.manifest, "v3", group)["tasks"]
            self.assertEqual(len(tasks), count)
            self.assertTrue(all(t["group"] == group and t["arguments"]["prompt"].startswith(prefix) for t in tasks))
        with self.assertRaisesRegex(ValueError, "group"):
            module.build_queue(self.root, self.manifest, "v3", "unknown")

    def test_candidate_and_retired_asset_rows_never_enter_canonical_queue(self):
        module = implementation()
        retired = self.image_record("assets/portraits/npc_old_rejected.png")
        retired["status"] = "rejected_style_v2"
        candidate = self.image_record("assets/_incoming/candidate.png")
        candidate["group"] = "scenes"
        self.manifest["assets"].extend([retired, candidate])
        tasks = module.build_queue(self.root, self.manifest, "v3", "all")["tasks"]
        self.assertEqual(len(tasks), 5)
        self.assertFalse(any(t["previous_source_path"] in (retired["path"], candidate["path"]) for t in tasks))

    def test_profile_escape_rejected_reference_and_runtime_cycle_are_rejected(self):
        module = implementation()
        for path in ("../escape.png", "C:/escape.png", "assets/_incoming/a1r_pilot/candidate_3.png"):
            bad = copy.deepcopy(self.manifest)
            bad["style_profiles"]["v3"]["reference"]["path"] = path
            with self.subTest(path=path), self.assertRaises(ValueError):
                module.build_queue(self.root, bad, "v3", "scenes")
        bad = copy.deepcopy(self.manifest)
        bad["runtime_copies"].append({"path": self.rows[0]["path"], "source_path": self.rows[-1]["path"]})
        with self.assertRaisesRegex(ValueError, "cycle"):
            module.build_queue(self.root, bad, "v3", "scenes")

    def test_actual_source_hash_and_dimensions_are_verified_before_queue(self):
        module = implementation()
        for field, value in (("sha256", "0" * 64), ("dim", [2560, 1440])):
            bad = copy.deepcopy(self.manifest)
            bad["assets"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.build_queue(self.root, bad, "v3", "scenes")

    def test_existing_versioned_target_and_compact_import_cannot_overwrite_resources(self):
        module = implementation()
        queue = module.build_queue(self.root, self.manifest, "v3", "items")
        path = self.root / queue["tasks"][0]["source_destination"]
        path.parent.mkdir(parents=True)
        path.write_bytes(b"keep existing generated bytes")
        with self.assertRaises(FileExistsError):
            module.build_queue(self.root, self.manifest, "v3", "items")
        self.assertEqual(path.read_bytes(), b"keep existing generated bytes")
        with self.assertRaisesRegex(ValueError, "queue|ImportMap"):
            module.run_pipeline(self.root, self.manifest, "v3", "scenes", import_map={"version": 1, "outputs": {}})

    def test_cli_emits_pending_queue_without_changing_manifest(self):
        value = copy.deepcopy(self.manifest)
        value.pop("style_profiles")
        path = self.root / "assets/manifest.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        before = path.read_bytes()
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--workspace", str(self.root),
                                 "--manifest", "assets/manifest.json", "--style", "v3", "--only", "all",
                                 "--output", ".tools/queue-v3.json"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads((self.root / ".tools/queue-v3.json").read_text(encoding="utf-8"))
        self.assertEqual(receipt["status"], "pending_style_reference")
        self.assertFalse(receipt["generation_performed"])
        self.assertEqual(path.read_bytes(), before)

    def test_default_queue_receipts_are_versioned_and_identical_reruns_are_idempotent(self):
        path = self.root / "assets/manifest.json"
        path.write_text(json.dumps(self.manifest), encoding="utf-8")
        args = [sys.executable, "-B", str(SCRIPT), "--workspace", str(self.root),
                "--manifest", "assets/manifest.json", "--style", "v3", "--only", "scenes"]
        first = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        first_path = json.loads(first.stdout)["receipt"]
        self.assertTrue(first_path.startswith(".tools/art/compact-queues/"))
        before = (self.root / first_path).read_bytes()
        repeated = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(json.loads(repeated.stdout)["receipt"], first_path)
        changed = copy.deepcopy(self.manifest)
        changed["style_profiles"]["v3"]["status"] = "pending"
        path.write_text(json.dumps(changed), encoding="utf-8")
        second = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertNotEqual(json.loads(second.stdout)["receipt"], first_path)
        self.assertEqual((self.root / first_path).read_bytes(), before)

    def test_powershell_alias_generates_only_local_queue(self):
        if not shutil.which("powershell.exe"):
            self.skipTest("PowerShell is a Windows integration surface")
        temporary = tempfile.TemporaryDirectory(dir=ROOT / ".tools")
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        relative = directory.relative_to(ROOT).as_posix()
        manifest = directory / "manifest.json"
        manifest.write_text(json.dumps({"schema_version": 3, "assets": [], "runtime_copies": []}), encoding="utf-8")
        result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                 str(ROOT / "tools/regen_art.ps1"), "-Style", "v3", "-Only", "scenes",
                                 "-Manifest", relative + "/manifest.json", "-Output", relative + "/queue.json",
                                 "-Python", sys.executable], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads((directory / "queue.json").read_text(encoding="utf-8"))
        self.assertEqual(receipt["status"], "pending_style_reference")


if __name__ == "__main__":
    unittest.main()
