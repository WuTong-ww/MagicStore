"""Real-file contracts for proposed A1R registration; production stays untouched."""
import copy
import hashlib
import importlib.util
import io
import json
import shutil
from functools import lru_cache
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/art/register_real_scenes.py"
REGISTRY = ROOT / "data/art/real_scene_registry.json"


def implementation(test):
    test.assertTrue(SCRIPT.is_file(), "Thin real-scene registration is not implemented")
    spec = importlib.util.spec_from_file_location("real_scene_registry_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@lru_cache(maxsize=None)
def png_bytes(kind):
    if kind == "runtime":
        image = Image.new("RGB", (1920, 1080), (120, 130, 140))
    elif kind == "layer":
        image = Image.new("RGBA", (16, 9), (0, 0, 0, 0))
        image.putpixel((4, 4), (120, 130, 140, 255))
    else:
        image = Image.new("RGB", (16, 9), (120, 130, 140))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def file_record(workspace, path, kind="source"):
    target = workspace / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(png_bytes(kind))
    return {"path": path, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "native_size": [1920, 1080] if kind == "runtime" else [16, 9]}


def dump(workspace, path, value):
    target = workspace / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def strict_qa():
    return {"passed": True, "regions": {name: {"pixels": 1, "samples": 3, "mae": 0.0,
            "p95": 0, "max_error": 0} for name in ("core", "feather", "inpaint_ring", "unedited")},
            "bounds": {"core_max_error": 0, "unedited_max_error": 0, "inpaint_ring_max_error": 0,
                       "feather_mae": 3, "feather_p95": 12, "percentile": 0.95}}


class RealSceneRegistryTests(unittest.TestCase):
    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "_template"):
            cls._template.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)

    def fixture(self):
        workspace = self.workspace
        if hasattr(type(self), "_template"):
            shutil.copytree(type(self)._template.name, workspace, dirs_exist_ok=True)
            return copy.deepcopy(type(self)._template_values)
        style = file_record(workspace, "assets/style.png")
        file_record(workspace, "assets/legacy-slot.png")
        file_record(workspace, "assets/engineering.png")
        baseline = {"scene_settings": {"version": 3, "canvas": [2560, 1440]},
                    "scenes": {f"S{i:02}": {"layer_format": "aligned_full_canvas", "layers": {},
                        "hotspots": {}, "safe_rect": [0, 0, 2560, 1440]} for i in range(1, 8)},
                    "items": {"kept": {"asset": "old-atlas.png"}}, "preview_only": True,
                    "art_passed": False}
        baseline["scenes"]["S04"]["layers"]["slot"] = {"path": "res://assets/legacy-slot.png",
            "display": "cell", "legacy": True, "rect": [0, 0, 100, 100], "hotspot": [0, 0, 100, 100]}
        dump(workspace, "data/baseline.json", baseline)
        manifest = {"keep_old_field": {"source": "unchanged"}, "runtime_copies": [],
            "round2_art": {"version": 1, "recipes": [{"id": "engineering_old", "group": "scenes",
                "source_path": "assets/engineering.png", "runtime_path": "old/engineering-runtime.png",
                "style_reference": style["path"], "prompt": "Engineering fixture", "version": "engineering1",
                "status": "placeholder", "operation": "procedural_placeholder", "attempts": [],
                "generator": "procedural_placeholder", "qa_kind": "geometry_only"}], "recompositions": []}}
        dump(workspace, "assets/manifest.json", manifest)
        registry = {"version": 1, "kind": "real_scene_registry", "preview_only": True,
            "art_passed": False, "manifest": "assets/manifest.json", "baseline": "data/baseline.json",
            "style_reference": style["path"], "style_sha256": style["sha256"],
            "generation_receipts": [], "selected_receipts": [], "scene_overrides": {},
            "seat_source_overrides": {}}
        for index in range(1, 8):
            scene = f"S{index:02}"
            generated = file_record(workspace, f"incoming/{scene}/generated.png")
            generation_path = f"incoming/{scene}/receipt.json"
            generation = {"version": 1, "scene_id": scene, "style_reference": style["path"],
                "style_sha256": style["sha256"], "records": [{**generated, "id": scene + "_native",
                    "prompt": "Test fixture, not generated production art", "ref_paths": [style["path"]],
                    "generator": "builtin_imagegen", "status": "complete",
                    "attempts": [{"attempt": 1, "status": "complete"}]}]}
            dump(workspace, generation_path, generation)
            registry["generation_receipts"].append(generation_path)
            periods = ["day", "night", "closed"] if scene == "S01" else ["day", "night"]
            for period in periods:
                for state in ["open", "closed"] if scene == "S04" else [None]:
                    suffix = period + ("_" + state if state else "")
                    directory = f"real/{scene}/{suffix}"
                    original = file_record(workspace, directory + "/C.png")
                    raw = file_record(workspace, directory + "/raw.png")
                    base = file_record(workspace, directory + "/B_all.png")
                    runtime_base = file_record(workspace, directory + "/runtime/B_all.png", "runtime")
                    transform = {"method": "equal_aspect_cover", "filter": "Lanczos", "scale": 120,
                        "source_crop": [0, 0, 16, 9], "runtime_size": [1920, 1080], "native_size": [16, 9]}
                    artifacts = [{**original, "role": "retained_original_C"}, {**base, "role": "all_object_cleanplate_B_all"}]
                    copies = [{"path": runtime_base["path"], "source_path": base["path"], "native_size": [16, 9],
                        "runtime_size": [1920, 1080], "source_sha256": base["sha256"],
                        "sha256": runtime_base["sha256"], "scale_x": 120, "scale_y": 120,
                        "transform": transform, "native_resolution_met": False, "origin": "real_C_pixel_extraction"}]
                    recipes = [{"id": scene + "_" + suffix + "_base", "source_path": base["path"],
                                "runtime_path": runtime_base["path"], "group": "scenes", "status": "complete"}]
                    rows, descriptors = [], {}
                    names = ["door_" + state, "lamp"] if state else ["sofa_mask"] if scene == "S03" else ["moving"]
                    for z, name in enumerate(names, 1):
                        layer = file_record(workspace, directory + "/" + name + ".png", "layer")
                        runtime_layer = file_record(workspace, directory + "/runtime/" + name + ".png", "runtime")
                        artifacts.append({**layer, "role": "actual_C_matted_layer"})
                        copies.append({"path": runtime_layer["path"], "source_path": layer["path"],
                            "native_size": [16, 9], "runtime_size": [1920, 1080], "source_sha256": layer["sha256"],
                            "sha256": runtime_layer["sha256"], "scale_x": 120, "scale_y": 120,
                            "transform": transform, "native_resolution_met": False, "origin": "real_C_pixel_extraction"})
                        descriptor = {"path": "res://" + runtime_layer["path"], "rect": [0, 0, 2560, 1440],
                            "hotspot": [0, 0, 2560, 1440], "native_size": [16, 9], "pivot_px": [8, 4],
                            "z_index": z, "motion": {"type": "static", "parameters": {}},
                            "source_transform": transform, "variants": {period: "res://" + runtime_layer["path"]},
                            "variant_transforms": {period: transform}}
                        if state and name.startswith("door_"):
                            descriptor["state"] = state
                        descriptors[name] = descriptor
                        rows.append({"id": name, "layer_path": layer["path"], "descriptor": descriptor,
                            "single_layer_qa": strict_qa()})
                        recipes.append({"id": scene + "_" + suffix + "_" + name,
                            "source_path": layer["path"], "runtime_path": runtime_layer["path"],
                            "group": "layers", "status": "complete"})
                    recompositions = [{"id": scene + "_" + suffix, "qa_kind": "art", "original_path": original["path"],
                        "base_path": base["path"], "layers": [{"path": row["layer_path"], "z_index": row["descriptor"]["z_index"]} for row in rows]}]
                    receipt_path = directory + "/receipt.json"
                    receipt = {"version": 1, "kind": "real_pixel_extraction", "scene_id": scene,
                        "period": period, "revision": "fixture", "inputs": {"original": original,
                            "raw_cleanplate": raw, "style": style}, "original_path": original["path"],
                        "base_path": base["path"], "base_runtime_path": runtime_base["path"],
                        "artifacts": artifacts, "runtime_copies": copies, "layers": rows,
                        "geometry_passed": True, "art_passed": False, "recomposition_qa": strict_qa(),
                        "recipes": recipes, "recompositions": recompositions,
                        "scene_descriptors": {scene: {"layer_format": "aligned_full_canvas",
                            period: "res://" + runtime_base["path"], "layers": descriptors}}}
                    entry = {"scene_id": scene, "period": period, "receipt_path": receipt_path}
                    if state:
                        receipt["state"] = state
                        entry["state"] = state
                    dump(workspace, receipt_path, receipt)
                    registry["selected_receipts"].append(entry)
        # Use authentic processing receipts for the registry's shared pixel
        # validator, not a mocked QA summary. The small native fixture keeps
        # all source geometry checks real; cached encoded files isolate tests.
        module = implementation(self)
        for entry in registry["selected_receipts"]:
            old = json.loads((workspace / entry["receipt_path"]).read_text(encoding="utf-8"))
            spec = {"version": 1, "scene_id": entry["scene_id"], "period": entry["period"],
                "revision": "fixture", "native_size": [16, 9], "original_path": old["original_path"],
                "raw_cleanplate_path": old["inputs"]["raw_cleanplate"]["path"],
                "style_reference": style["path"], "composite_prompt": "Keep every object in the complete C.",
                "cleanplate_prompt": "Remove all movable objects and fill the background.", "layers": []}
            if "state" in entry:
                spec["state"] = entry["state"]
            for index, row in enumerate(old["layers"]):
                x = 2 + index * 7
                spec["layers"].append({"id": row["id"], "polygons": [[[x, 2], [x + 3, 2], [x + 3, 6], [x, 6]]],
                    "pivot_px": [x, 2], "z_index": index + 1, "motion": {"type": "static", "parameters": {}}})
            receipt = module.real_layers.process_scene(workspace, spec)
            entry["receipt_path"] = receipt["receipt_path"]
        type(self)._template = tempfile.TemporaryDirectory()
        shutil.copytree(workspace, type(self)._template.name, dirs_exist_ok=True)
        type(self)._template_values = copy.deepcopy((registry, manifest, baseline))
        return registry, manifest, baseline

    def test_registry_requires_exactly_seventeen_unique_scene_period_states(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        module.validate_registry(self.workspace, registry)
        for records in (registry["selected_receipts"][:-1], registry["selected_receipts"] + [registry["selected_receipts"][0]]):
            invalid = copy.deepcopy(registry)
            invalid["selected_receipts"] = records
            with self.assertRaisesRegex(ValueError, "17|complete|duplicate"):
                module.validate_registry(self.workspace, invalid)

    def test_variants_merge_nested_transforms_and_preserve_legacy_slot(self):
        module = implementation(self)
        registry, _, baseline = self.fixture()
        result = module.build_proposals(self.workspace, registry)
        scene = result["scene_review"]
        self.assertEqual(scene["scenes"]["S04"]["layers"]["slot"], baseline["scenes"]["S04"]["layers"]["slot"])
        moving = scene["scenes"]["S01"]["layers"]["moving"]
        self.assertEqual(set(moving["variants"]), {"day", "night", "closed"})
        self.assertEqual(set(moving["variant_transforms"]), {"day", "night", "closed"})
        self.assertEqual(moving["path"], moving["variants"]["day"])
        self.assertEqual(scene["items"], baseline["items"])
        self.assertTrue(scene["preview_only"])
        self.assertFalse(scene["art_passed"])

    def test_s04_uses_four_state_backgrounds_and_state_specific_lamps(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        cabinet = module.build_proposals(self.workspace, registry)["scene_review"]["scenes"]["S04"]
        self.assertEqual(set(cabinet["state_backgrounds"]), {"open", "closed"})
        paths = [cabinet["state_backgrounds"][state][period] for state in ("open", "closed") for period in ("day", "night")]
        self.assertEqual(len(set(paths)), 4)
        self.assertEqual(cabinet["day"], cabinet["state_backgrounds"]["open"]["day"])
        for state in ("open", "closed"):
            lamp = cabinet["layers"]["lamp_" + state]
            self.assertEqual(lamp["state"], state)
            self.assertEqual(set(lamp["variants"]), {"day", "night"})
            self.assertEqual(cabinet["layers"]["door_" + state]["state"], state)
        self.assertNotIn("lamp", cabinet["layers"])

    def test_manifest_replaces_duplicate_paths_and_separates_engineering_groups(self):
        module = implementation(self)
        registry, manifest, _ = self.fixture()
        first = json.loads((self.workspace / registry["selected_receipts"][0]["receipt_path"]).read_text(encoding="utf-8"))
        path = first["runtime_copies"][0]["path"]
        manifest["runtime_copies"] = [{"path": path, "sha256": "stale"}, {"path": path, "sha256": "older"}]
        dump(self.workspace, registry["manifest"], manifest)
        result = module.build_proposals(self.workspace, registry)["manifest"]
        copies = [row for row in result["runtime_copies"] if row["path"] == path]
        self.assertEqual(len(copies), 1)
        self.assertEqual(copies[0]["sha256"], first["runtime_copies"][0]["sha256"])
        self.assertEqual(result["keep_old_field"], manifest["keep_old_field"])
        old = next(row for row in result["round2_art"]["recipes"] if row["id"] == "engineering_old")
        self.assertEqual(old["group"], "engineering_scenes")
        paths = [row["source_path"] for row in result["round2_art"]["recipes"]]
        self.assertEqual(len(paths), len(set(paths)))

    def test_bad_actual_sha_prevents_all_proposed_writes(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["selected_receipts"][0]["receipt_path"]
        receipt = json.loads(path.read_text(encoding="utf-8"))
        receipt["artifacts"][0]["sha256"] = "0" * 64
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, "sha256|SHA"):
            module.register_registry(self.workspace, registry, "proposal")
        self.assertFalse((self.workspace / "proposal").exists())

    def test_actual_dimensions_and_claimed_geometry_are_verified(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["selected_receipts"][0]["receipt_path"]
        original = json.loads(path.read_text(encoding="utf-8"))
        for change in ("size", "geometry", "strict_core"):
            receipt = copy.deepcopy(original)
            if change == "size": receipt["runtime_copies"][0]["runtime_size"] = [123, 456]
            if change == "geometry": receipt["geometry_passed"] = False
            if change == "strict_core": receipt["recomposition_qa"]["regions"]["core"]["max_error"] = 1
            path.write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ValueError, "size|geometry|core|QA"):
                module.build_proposals(self.workspace, registry)

    def test_generation_style_and_scene_identity_cannot_be_substituted(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["generation_receipts"][0]
        receipt = json.loads(path.read_text(encoding="utf-8"))
        receipt["style_sha256"] = "0" * 64
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, "style|sha256"):
            module.build_proposals(self.workspace, registry)

    def test_json_overrides_and_source_seat_use_common_cover_transform(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        registry["scene_overrides"] = {"S02": {"hotspots": {"door": {"rect": [10, 20, 30, 40], "label": "店外", "target": "exterior"}}}}
        registry["seat_source_overrides"] = {"S03": {"native_size": [16, 9], "rect": [4, 2, 8, 4], "scale": 1.2}}
        scenes = module.build_proposals(self.workspace, registry)["scene_review"]["scenes"]
        self.assertEqual(scenes["S02"]["hotspots"]["door"]["label"], "店外")
        self.assertEqual(scenes["S03"]["seat_rect"], [640, 320, 1280, 640])
        self.assertEqual(scenes["S03"]["seat_scale"], 1.2)

    def test_outputs_cannot_overwrite_a_manifest_source(self):
        module = implementation(self)
        registry, manifest, _ = self.fixture()
        registry["manifest"] = "output/proposed_manifest.json"
        dump(self.workspace, registry["manifest"], manifest)
        original = (self.workspace / registry["manifest"]).read_bytes()
        with self.assertRaisesRegex(ValueError, "source|input|overwrite"):
            module.register_registry(self.workspace, registry, "output")
        self.assertEqual((self.workspace / registry["manifest"]).read_bytes(), original)
        self.assertFalse((self.workspace / "output/scene_review.json").exists())

    def test_registration_is_idempotent_and_never_changes_central_inputs(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        original = {key: (self.workspace / registry[key]).read_bytes() for key in ("manifest", "baseline")}
        first = module.register_registry(self.workspace, registry, "proposals/v1")
        second = module.register_registry(self.workspace, registry, "proposals/v1")
        self.assertEqual(first, second)
        self.assertTrue((self.workspace / "proposals/v1/proposed_manifest.json").is_file())
        self.assertTrue((self.workspace / "proposals/v1/scene_review.json").is_file())
        for key, data in original.items(): self.assertEqual((self.workspace / registry[key]).read_bytes(), data)

    def test_output_collision_is_preflighted_before_the_other_file_is_written(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        directory = self.workspace / "proposals"
        directory.mkdir()
        (directory / "proposed_manifest.json").write_text("keep existing bytes")
        with self.assertRaises(FileExistsError): module.register_registry(self.workspace, registry, "proposals")
        self.assertFalse((directory / "scene_review.json").exists())

    def test_checked_in_registry_lists_selected_sources_without_requiring_pending_files(self):
        module = implementation(self)
        self.assertTrue(REGISTRY.is_file(), "Explicit real-scene registry is missing")
        value = json.loads(REGISTRY.read_text(encoding="utf-8-sig"))
        module.validate_registry(ROOT, value)
        self.assertEqual(len(value["selected_receipts"]), 17)
        self.assertEqual(len(value["generation_receipts"]), 7)
        self.assertEqual(value["baseline"], "data/art/scene_preview.json")

    def test_validate_only_cli_checks_all_files_without_creating_outputs(self):
        implementation(self)
        registry, _, _ = self.fixture()
        dump(self.workspace, "registry.json", registry)
        command = [sys.executable, "-B", str(SCRIPT), "--workspace", str(self.workspace),
                   "--registry", "registry.json", "--output", "must-not-exist", "--validate-only"]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["validate_only"])
        self.assertFalse((self.workspace / "must-not-exist").exists())

    def test_recomputed_pixel_qa_rejects_forged_recorded_success(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["selected_receipts"][0]["receipt_path"]
        receipt = json.loads(path.read_text(encoding="utf-8"))
        mask_path = receipt["layers"][0]["soft_mask_path"]
        Image.new("L", (16, 9), 0).save(self.workspace / mask_path)
        for artifact in receipt["artifacts"]:
            if artifact["path"] == mask_path:
                artifact["sha256"] = hashlib.sha256((self.workspace / mask_path).read_bytes()).hexdigest()
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, "mask|polygons|alpha|pixels"):
            module.build_proposals(self.workspace, registry)

    def test_unverified_descriptor_crop_cannot_move_the_runtime_pivot(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["selected_receipts"][0]["receipt_path"]
        receipt = json.loads(path.read_text(encoding="utf-8"))
        descriptor = next(iter(receipt["scene_descriptors"]["S01"]["layers"].values()))
        descriptor["variant_transforms"]["day"]["source_crop"] = [1, 0, 16, 9]
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, "descriptor|transform|crop"):
            module.build_proposals(self.workspace, registry)

    def test_descriptor_geometry_cannot_override_the_verified_source_annotation(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["selected_receipts"][0]["receipt_path"]
        original = json.loads(path.read_text(encoding="utf-8"))
        for field, value in (("pivot_px", [0, 0]), ("z_index", 3999),
            ("motion", {"type": "pendulum", "parameters": {"amplitude": 999}}),
            ("rect", [10, 20, 30, 40]), ("hotspot", [10, 20, 30, 40])):
            receipt = copy.deepcopy(original)
            next(iter(receipt["scene_descriptors"]["S01"]["layers"].values()))[field] = value
            path.write_text(json.dumps(receipt), encoding="utf-8")
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "descriptor|annotation|geometry"):
                module.build_proposals(self.workspace, registry)

    def test_descriptor_cannot_substitute_an_opaque_verified_background_for_a_layer(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["selected_receipts"][0]["receipt_path"]
        receipt = json.loads(path.read_text(encoding="utf-8"))
        descriptor = next(iter(receipt["scene_descriptors"]["S01"]["layers"].values()))
        descriptor["path"] = "res://" + receipt["base_runtime_path"]
        descriptor["variants"]["day"] = descriptor["path"]
        path.write_text(json.dumps(receipt), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "descriptor|layer|source"):
            module.build_proposals(self.workspace, registry)

    def test_row_descriptor_and_recipe_cannot_jointly_redirect_the_verified_fragment(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["selected_receipts"][0]["receipt_path"]
        receipt = json.loads(path.read_text(encoding="utf-8"))
        row = receipt["layers"][0]
        fragment = receipt["scene_descriptors"]["S01"]["layers"][row["id"]]
        self.assertIsNot(row["descriptor"], fragment)
        original_fragment = copy.deepcopy(fragment)
        target = "safe/not-yet-existing-runtime.png"
        self.assertFalse((self.workspace / target).exists())
        row["descriptor"]["path"] = "res://" + target
        recipe = next(item for item in receipt["recipes"] if item["source_path"] == row["layer_path"])
        recipe["runtime_path"] = target
        self.assertEqual(fragment, original_fragment)
        path.write_text(json.dumps(receipt), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "descriptor|fragment|layer"):
            module.build_proposals(self.workspace, registry)

    def test_unrelated_generation_records_cannot_certify_processing_sources(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["generation_receipts"][0]
        generation = json.loads(path.read_text(encoding="utf-8"))
        other = self.workspace / "incoming/S01/unrelated.png"
        Image.new("RGB", (16, 9), "red").save(other)
        generation["records"][0].update(path="incoming/S01/unrelated.png",
            sha256=hashlib.sha256(other.read_bytes()).hexdigest())
        path.write_text(json.dumps(generation), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "generation|provenance|source"):
            module.build_proposals(self.workspace, registry)

    def test_source_join_allows_retained_successful_attempt_bytes_at_another_path(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["generation_receipts"][0]
        generation = json.loads(path.read_text(encoding="utf-8"))
        record = generation["records"][0]
        original_path, original_sha = record["path"], record["sha256"]
        other = self.workspace / "incoming/S01/other-attempt.png"
        Image.new("RGB", (16, 9), "red").save(other)
        record.update(path="incoming/S01/other-attempt.png", sha256=hashlib.sha256(other.read_bytes()).hexdigest(),
            attempts=[{"attempt": 1, "status": "complete", "output_path": original_path,
                       "sha256": original_sha, "native_size": [16, 9]}, {"attempt": 2, "status": "complete"}])
        path.write_text(json.dumps(generation), encoding="utf-8")
        self.assertTrue(module.build_proposals(self.workspace, registry)["summary"]["geometry_passed"])

    def test_compact_matched_alternate_uses_its_actual_prompt_and_mask_references(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        dump(self.workspace, registry["manifest"], {"schema_version": 3, "assets": [], "runtime_copies": []})
        generation_path = self.workspace / registry["generation_receipts"][0]
        generation = json.loads(generation_path.read_text(encoding="utf-8"))
        record = generation["records"][0]
        receipt = json.loads((self.workspace / registry["selected_receipts"][0]["receipt_path"]).read_text(encoding="utf-8"))
        matched = receipt["specification"]["original_path"]
        matched_sha = hashlib.sha256((self.workspace / matched).read_bytes()).hexdigest()
        mask = file_record(self.workspace, "incoming/S01/alternate-mask.png", "layer")
        other = self.workspace / "incoming/S01/outer-selected.png"
        Image.new("RGB", (16, 9), "red").save(other)
        actual_prompt = "Second actual attempt: repair only the supplied masked area."
        actual_references = [registry["style_reference"], mask["path"]]
        record.update(path="incoming/S01/outer-selected.png", sha256=hashlib.sha256(other.read_bytes()).hexdigest(),
            prompt="Outer selected candidate has a different prompt.", ref_paths=[registry["style_reference"]],
            attempts=[{"attempt": 1, "status": "complete", "output_path": matched, "sha256": matched_sha,
                       "native_size": [16, 9], "prompt": actual_prompt, "ref_paths": actual_references},
                      {"attempt": 2, "status": "complete"}])
        generation_path.write_text(json.dumps(generation), encoding="utf-8")
        result = module.build_proposals(self.workspace, registry)
        asset = next(row for row in result["manifest"]["assets"] if row["path"] == matched)
        self.assertEqual(asset["prompt"], actual_prompt)
        self.assertEqual(asset["references"], actual_references)
        for field, invalid in (("prompt", None), ("ref_paths", "not-an-array")):
            bad = copy.deepcopy(generation)
            bad["records"][0]["attempts"][0][field] = invalid
            generation_path.write_text(json.dumps(bad), encoding="utf-8")
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.build_proposals(self.workspace, registry)

    def test_completed_real_artifacts_keep_scene_and_layer_regen_queues_complete(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        manifest = module.build_proposals(self.workspace, registry)["manifest"]
        for group in ("scenes", "layers"):
            queue = module.pipeline.build_queue(self.workspace, manifest, registry["style_reference"], group)
            self.assertEqual(queue["status"], "complete")
            self.assertTrue(all(task["status"] == "complete" for task in queue["tasks"]))

    def test_scene_regen_keeps_complete_C_prompt_and_schedules_its_all_object_cleanplate(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        receipt = json.loads((self.workspace / registry["selected_receipts"][0]["receipt_path"]).read_text(encoding="utf-8"))
        manifest = module.build_proposals(self.workspace, registry)["manifest"]
        queue = module.pipeline.build_queue(self.workspace, manifest, registry["style_reference"], "scenes")
        tasks = {task["source_destination"]: task for task in queue["tasks"]}
        composite = tasks[receipt["original_path"]]
        self.assertIn("Keep every object in the complete C.", composite["arguments"]["prompt"])
        self.assertNotIn("Remove all movable objects", composite["arguments"]["prompt"])
        self.assertEqual(composite["operation"], "generate")
        self.assertIn((self.workspace / receipt["specification"]["original_path"]).resolve(),
            [Path(path).resolve() for path in composite["arguments"]["referenced_image_paths"]])
        cleanplate = tasks[receipt["base_path"]]
        self.assertEqual(cleanplate["operation"], "generate")
        self.assertIn("Remove all movable objects and fill the background.", cleanplate["arguments"]["prompt"])
        self.assertIn((self.workspace / receipt["original_path"]).resolve(),
            [Path(path).resolve() for path in cleanplate["arguments"]["referenced_image_paths"]])
        for layer in receipt["layers"]:
            self.assertIn((self.workspace / layer["soft_mask_path"]).resolve(),
                [Path(path).resolve() for path in cleanplate["arguments"]["referenced_image_paths"]])
            self.assertNotIn(layer["layer_path"], tasks)
        self.assertEqual(queue["status"], "complete")
        self.assertTrue(all(task["status"] == "complete" and not task["can_generate"] for task in queue["tasks"]))

    def test_escaped_recipe_and_recomposition_fragments_are_rejected(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        path = self.workspace / registry["selected_receipts"][0]["receipt_path"]
        original = json.loads(path.read_text(encoding="utf-8"))
        for kind in ("recipe", "recomposition"):
            receipt = copy.deepcopy(original)
            if kind == "recipe": receipt["recipes"][0]["source_path"] = "../outside.png"
            else: receipt["recompositions"][0]["base_path"] = "../outside.png"
            path.write_text(json.dumps(receipt), encoding="utf-8")
            with self.subTest(fragment=kind), self.assertRaisesRegex(ValueError, "recipe|recomposition|path|escape"):
                module.build_proposals(self.workspace, registry)

    def test_compact_proposal_keeps_detailed_work_outside_the_canonical_manifest(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        fallback = file_record(self.workspace, "assets/fallback.png")
        compact = {"schema_version": 3, "scene_status": "fallback", "assets": [{"path": fallback["path"],
            "sha256": fallback["sha256"], "dim": fallback["native_size"], "prompt": "Original fallback prompt"}],
            "runtime_copies": [], "style_profiles": {"v3": {"status": "pending"}}}
        dump(self.workspace, registry["manifest"], compact)
        result = module.build_proposals(self.workspace, registry)
        manifest = result["manifest"]
        self.assertNotIn("round2_art", manifest)
        self.assertNotIn("scenes", manifest)
        self.assertTrue(manifest["preview_only"])
        self.assertFalse(manifest["art_passed"])
        self.assertLess(len(json.dumps(manifest, ensure_ascii=False).encode("utf-8")), 500000)
        assets = {row["path"]: row for row in manifest["assets"]}
        self.assertEqual(assets[fallback["path"]]["prompt"], "Original fallback prompt")
        for copy_record in manifest["runtime_copies"]:
            self.assertEqual(assets[copy_record["path"]]["sha256"], copy_record["sha256"])
            self.assertEqual(assets[copy_record["path"]]["inputs"], [copy_record["source_path"]])
        self.assertEqual(manifest["style_profiles"], compact["style_profiles"])
        self.assertTrue(result["registration_audit"]["round2_art"]["recipes"])
        self.assertFalse(result["registration_audit"]["art_passed"])
        baseline = json.loads((self.workspace / registry["baseline"]).read_text(encoding="utf-8"))
        baseline["local_audit_descriptor"] = "res://data/art/old_rejected.json"
        dump(self.workspace, registry["baseline"], baseline)
        self.assertNotIn("local_audit_descriptor", module.build_proposals(self.workspace, registry)["scene_review"])

    def test_compact_registration_writes_independent_immutable_audit_and_never_reads_retired_style(self):
        module = implementation(self)
        registry, _, _ = self.fixture()
        compact = {"schema_version": 3, "assets": [], "runtime_copies": [],
            "local_audit": {"status": "retired", "path": "absent/rejected.jsonl"}}
        dump(self.workspace, registry["manifest"], compact)
        before = (self.workspace / registry["manifest"]).read_bytes()
        summary = module.register_registry(self.workspace, registry, "compact-proposals")
        self.assertEqual((self.workspace / registry["manifest"]).read_bytes(), before)
        audit_path = self.workspace / summary["registration_audit"]
        audit = json.loads(audit_path.read_text(encoding="utf-8"))
        self.assertEqual((audit["type"], audit["key"]), ("manifest_section", "round2_art"))
        self.assertEqual(audit["value"]["active_style"]["path"], registry["style_reference"])
        self.assertTrue(audit["value"]["preview_only"])
        self.assertFalse((self.workspace / "absent").exists())
        original = audit_path.read_bytes()
        module.register_registry(self.workspace, registry, "compact-proposals")
        self.assertEqual(audit_path.read_bytes(), original)
        audit_path.write_text("do not overwrite", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            module.register_registry(self.workspace, registry, "compact-proposals")


if __name__ == "__main__":
    unittest.main()
