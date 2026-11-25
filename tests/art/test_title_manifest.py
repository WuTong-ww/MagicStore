"""TITLE provenance stays exact while its compact central rows fit the old cap."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("title_manifest_pipeline", ROOT / "tools/art_pipeline.py")
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


class TitleManifestTests(unittest.TestCase):
    def test_title_provenance_has_a_strict_explicit_resolver(self):
        self.assertTrue(callable(getattr(pipeline, "resolve_title_provenance", None)),
                        "TITLE compact references require a strict workspace-bound resolver")
        self.assertTrue(callable(getattr(pipeline, "validate_title_prompts", None)),
                        "the new tracked provenance JSON requires its own validator")

    def inputs(self):
        self.test_title_provenance_has_a_strict_explicit_resolver()
        manifest = json.loads((ROOT / "assets/ART_ASSET_MANIFEST.json").read_text(encoding="utf-8"))
        catalog = json.loads((ROOT / "data/art/title_prompts.json").read_text(encoding="utf-8"))
        rows = [r for r in manifest["assets"] if r.get("group") == "title_sources"]
        self.assertEqual(len(rows), 6)
        return manifest, catalog, rows

    def temporary_workspace(self):
        base = ROOT / ".tools/r3-title/provenance-packing/test-runs"
        base.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=base)
        self.addCleanup(temporary.cleanup)
        return Path(temporary.name)

    def write_catalog(self, workspace, catalog):
        path = workspace / "data/art/title_prompts.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(catalog, ensure_ascii=False), encoding="utf-8")
        return path

    def test_resolver_recovers_every_full_row_and_never_mutates_metadata(self):
        manifest, catalog, rows = self.inputs()
        before = copy.deepcopy((manifest, catalog))
        self.assertIs(pipeline.validate_title_prompts(catalog), catalog)
        for row in rows:
            expected = catalog["entries"][row["prompt_reference"]["key"]]
            self.assertEqual(pipeline.resolve_title_provenance(ROOT, row), expected)
            canonical = json.dumps(expected, sort_keys=True, ensure_ascii=False,
                                   separators=(",", ":"), allow_nan=False).encode("utf-8")
            self.assertEqual(row["prompt_reference"]["sha256"], hashlib.sha256(canonical).hexdigest())
            self.assertTrue(expected["prompt"].strip())
            self.assertEqual(expected["source"]["generator"], "builtin_imagegen")
        self.assertEqual((manifest, catalog), before)

    def test_pure_expand_and_compact_preserve_refs_without_any_sidecar_io(self):
        manifest, _, rows = self.inputs()
        before = copy.deepcopy(manifest)
        with mock.patch.object(pipeline, "read_json", side_effect=AssertionError("pure metadata must not read files")), \
             mock.patch.object(pipeline, "resolve_title_provenance", side_effect=AssertionError("pure metadata must not resolve")):
            expanded = pipeline.expand_compact_metadata(manifest)
            packed = pipeline.compact_formal_metadata(manifest)
        self.assertEqual([r for r in expanded["assets"] if r.get("group") == "title_sources"], rows)
        self.assertEqual(pipeline.expand_compact_metadata(packed), expanded)
        self.assertEqual(manifest, before)
        self.assertLess(len((json.dumps(packed, ensure_ascii=False, separators=(",", ":")) + "\n").encode()), 500000)

    def test_title_rows_do_not_enter_existing_five_group_regeneration_queue(self):
        manifest, _, _ = self.inputs()
        without = copy.deepcopy(manifest)
        without["assets"] = [r for r in without["assets"] if r.get("group") != "title_sources"]
        self.assertEqual(pipeline._compact_resources(manifest), pipeline._compact_resources(without))
        self.assertIs(pipeline.validate_compact_manifest(ROOT, manifest), manifest)

    def test_missing_sidecar_cannot_fall_back_to_repository_or_local_history(self):
        _, _, rows = self.inputs()
        workspace = self.temporary_workspace()
        with self.assertRaises(ValueError):
            pipeline.resolve_title_provenance(workspace, rows[0])

    def test_new_catalog_rejects_bad_shapes_types_scope_and_missing_full_provenance(self):
        _, catalog, _ = self.inputs()
        for value in (None, [], True, {}, {**catalog, "type": "other"}, {**catalog, "version": True},
                      {**catalog, "version": 1.0}, {**catalog, "extra": 1}):
            with self.subTest(value=type(value).__name__), self.assertRaises(ValueError):
                pipeline.validate_title_prompts(value)
        key = next(iter(catalog["entries"]))
        for mutation in ("missing_entry", "extra_entry", "missing_prompt", "bad_prompt", "bad_source",
                         "bad_version", "bad_dim", "bad_native", "wrong_path", "wrong_group"):
            value = copy.deepcopy(catalog)
            row = value["entries"][key]
            if mutation == "missing_entry": del value["entries"][key]
            elif mutation == "extra_entry": value["entries"]["other"] = copy.deepcopy(row)
            elif mutation == "missing_prompt": del row["prompt"]
            elif mutation == "bad_prompt": row["prompt"] = ""
            elif mutation == "bad_source": row["source"] = []
            elif mutation == "bad_version": row["version"] = True
            elif mutation == "bad_dim": row["dim"] = [True, 941]
            elif mutation == "bad_native": row["native_size"] = [True, 941]
            elif mutation == "wrong_path": row["path"] = "assets/ui/unregistered.png"
            else: row["group"] = "scenes"
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                pipeline.validate_title_prompts(value)

    def test_reference_shape_scope_and_identity_cannot_bypass_title_validation(self):
        _, _, rows = self.inputs()
        for mutation in ("missing_ref", "wrong_key", "escape_path", "wrong_catalog", "bad_hash",
                         "extra_ref", "wrong_dim", "wrong_version", "wrong_asset_hash", "wrong_group",
                         "case_changed_path", "inline_prompt"):
            value = copy.deepcopy(rows[0])
            ref = value["prompt_reference"]
            if mutation == "missing_ref": del value["prompt_reference"]
            elif mutation == "wrong_key": ref["key"] = "other"
            elif mutation == "escape_path": ref["path"] = "../title_prompts.json"
            elif mutation == "wrong_catalog": ref["path"] = "data/art/other.json"
            elif mutation == "bad_hash": ref["sha256"] = "0" * 64
            elif mutation == "extra_ref": ref["type"] = "unknown"
            elif mutation == "wrong_dim": value["dim"] = [1, 1]
            elif mutation == "wrong_version": value["version"] += 1
            elif mutation == "wrong_asset_hash": value["sha256"] = "0" * 64
            elif mutation == "wrong_group": value["group"] = "scenes"
            elif mutation == "case_changed_path": value["path"] = value["path"].upper()
            else: value["prompt"] = "conflicting inline provenance"
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                pipeline.validate_compact_manifest(ROOT, {"schema_version": 3, "assets": [value]})
        outside = copy.deepcopy(rows[0])
        outside["path"] = "assets/unrelated.png"
        outside["group"] = "scenes"
        with self.assertRaises(ValueError):
            pipeline.validate_compact_manifest(ROOT, {"schema_version": 3, "assets": [outside]})

    def test_renaming_reserved_title_asset_and_removing_every_marker_cannot_bypass_validation(self):
        for path in ("assets/generated_scenes/runtime/title/unregistered.png", "assets/ui/title_unregistered.png",
                     "ASSETS/GENERATED_SCENES/RUNTIME/TITLE/unregistered.png", "ASSETS/UI/TITLE_unregistered.png"):
            row = {"path": path, "sha256": "0" * 64, "dim": [1, 1], "version": 1, "group": "legacy_runtime"}
            with self.subTest(path=path), self.assertRaises(ValueError):
                pipeline.validate_compact_manifest(ROOT, {"schema_version": 3, "assets": [row]})

    def test_full_prompt_source_status_and_usage_are_bound_by_canonical_entry_hash(self):
        _, catalog, rows = self.inputs()
        key = rows[0]["prompt_reference"]["key"]
        workspace = self.temporary_workspace()
        for field in ("prompt", "source", "status", "runtime_usage"):
            value = copy.deepcopy(catalog)
            if field == "source": value["entries"][key][field]["original_path"] += ".changed"
            else: value["entries"][key][field] += " changed"
            self.write_catalog(workspace, value)
            with self.subTest(field=field), self.assertRaises(ValueError):
                pipeline.resolve_title_provenance(workspace, rows[0])

    def test_sidecar_duplicate_fields_are_rejected_before_json_resolution(self):
        _, catalog, rows = self.inputs()
        workspace = self.temporary_workspace()
        path = self.write_catalog(workspace, catalog)
        encoded = path.read_text(encoding="utf-8")
        path.write_text(encoded.replace('"version": 1,', '"version": 1, "version": 1,', 1), encoding="utf-8")
        with self.assertRaises(ValueError):
            pipeline.resolve_title_provenance(workspace, rows[0])


if __name__ == "__main__":
    unittest.main()
