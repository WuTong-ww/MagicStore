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
