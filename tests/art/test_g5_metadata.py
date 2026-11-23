"""G5 capacity extends two typed G4 profiles without losing old provenance."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result
common = module("g5_metadata_common", "tools/art_pipeline.py")
portrait = module("g5_metadata_portrait", "tools/art/portrait_pipeline.py")
FIELDS = ({"group", "version", "operation", "references", "source_raw_native_size", "processing_script", "local_config"},
          {"group", "version", "prompt", "references"})

def typed_candidate(manifest):
    result = copy.deepcopy(manifest)
    for icon, fields in enumerate(FIELDS):
        rows = [r for r in result["assets"] if r["path"].startswith("assets/items/v3/g4r1/") and r["path"].endswith("_64.png") == bool(icon)]
        shared = {k: rows[0][k] for k in sorted(fields)}
        assert all(all(r[k] == v for k, v in shared.items()) for r in rows)
        code = json.dumps(shared, sort_keys=True, separators=(",", ":"))
        key = "G4_" + hashlib.sha256(code.encode()).hexdigest()[:12]
        result["asset_metadata_profiles"][key] = shared
        for row in rows:
            for field in shared: del row[field]
            row["metadata_profile"] = key
    return result

class G5MetadataTests(unittest.TestCase):
    def setUp(self):
        self.raw = (ROOT / "assets/ART_ASSET_MANIFEST.json").read_bytes()
        self.manifest = json.loads(self.raw)
        # Root may already have applied this packing and added G5 rows. Rebuild
        # only the old G4 literal input fixture; retain every other current row.
        profiles = self.manifest.get("asset_metadata_profiles", {})
        for row in self.manifest["assets"]:
            key = row.get("metadata_profile", "")
            if key.startswith("G4_"):
                shared = profiles[key]
                self.assertFalse(set(row).intersection(shared))
                del row["metadata_profile"]; row.update(copy.deepcopy(shared))
        self.manifest["asset_metadata_profiles"] = {k:v for k,v in profiles.items() if not k.startswith("G4_")}
        self.expanded = common.expand_compact_metadata(self.manifest)

    def test_two_typed_profiles_expand_all_361_exactly_and_no_mutation(self):
        candidate = typed_candidate(self.manifest); before = copy.deepcopy(candidate)
        self.assertEqual(common.expand_compact_metadata(candidate), self.expanded)
        self.assertEqual(candidate, before)
        common.validate_compact_manifest(ROOT, candidate)

    def test_typed_profiles_reject_unknown_missing_overlap_and_bad_types(self):
        base = typed_candidate(self.manifest)
        key = next(k for k, v in base["asset_metadata_profiles"].items() if k.startswith("G4_") and v["group"] == "items")
        for kind in ("unknown", "missing", "overlap", "bad_size", "bad_version", "bad_reference", "bad_script"):
            value = copy.deepcopy(base); shared = value["asset_metadata_profiles"][key]
            if kind == "unknown": shared["sha256"] = "a" * 64
            elif kind == "missing": del shared["operation"]
            elif kind == "overlap": next(r for r in value["assets"] if r.get("metadata_profile") == key)["version"] = 3
            elif kind == "bad_size": shared["source_raw_native_size"] = [True, 1254]
            elif kind == "bad_version": shared["version"] = "3"
            elif kind == "bad_reference": shared["references"] = [17]
            else: shared["processing_script"] = "tools/art/other.py"
            with self.subTest(kind=kind), self.assertRaises(ValueError): common.expand_compact_metadata(value)

    def test_packing_preserves_legacy_stored_rows_a4_table_aliases_and_budget(self):
        self.assertTrue(callable(getattr(common, "compact_formal_metadata", None)), "typed formal packer missing")
        before = copy.deepcopy(self.manifest); packed = common.compact_formal_metadata(self.manifest)
        self.assertEqual(self.manifest, before)
        self.assertEqual(common.expand_compact_metadata(packed), self.expanded)
        old = [r for r in self.manifest["assets"] if not r["path"].startswith("assets/items/v3/g4r1/")]
        self.assertEqual([r for r in packed["assets"] if not r["path"].startswith("assets/items/v3/g4r1/")], old)
        self.assertEqual({k:v for k,v in packed["asset_metadata_profiles"].items() if k.startswith("A4_")}, self.manifest["asset_metadata_profiles"])
        self.assertEqual(packed["runtime_copies"], self.manifest["runtime_copies"])
        self.assertEqual(len(packed["runtime_copies"]), len(self.manifest["runtime_copies"]))
        encoded = (json.dumps(packed, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
        literal = (json.dumps(self.manifest, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
        self.assertEqual(len(literal)-len(encoded), 10086)
        if hashlib.sha256(self.raw).hexdigest() == "b7ca9f61797f2fece5fc8c320e7d16ef1ea37a0f546c6575f991501a491152f1":
            self.assertEqual(len(encoded), 489759)
        self.assertEqual(common.compact_formal_metadata(packed), packed)
        self.assertEqual((ROOT / "assets/ART_ASSET_MANIFEST.json").read_bytes(), self.raw)

    def test_partial_and_full_portrait_proposals_preserve_g4_profiles_and_exact_rows(self):
        base = typed_candidate(self.manifest)
        originals = [r for r in self.expanded["assets"] if r.get("art_pack") == "A4_v3"]
        self.assertEqual(len(originals), 140)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / "assets").mkdir()
            central = root / "assets/ART_ASSET_MANIFEST.json"
            raw = json.dumps(base, ensure_ascii=False).encode(); central.write_bytes(raw)
            for full in (False, True):
                rows = copy.deepcopy(originals if full else originals[:1])
                for row in rows: row["processing_config_digest"] = "b" * 64
                fragment = {"assets": rows, "templates": {}}
                before = copy.deepcopy(fragment)
                with self.subTest(full=full):
                    proposed = portrait.proposed_manifest(root, fragment)
                    expected = copy.deepcopy(self.expanded)
                    replace = {r["path"]:r for r in rows}
                    expected["assets"] = [replace.get(r["path"], r) for r in expected["assets"]]
                    self.assertEqual(common.expand_compact_metadata(proposed), expected)
                    self.assertEqual(len(proposed["assets"]), len(self.expanded["assets"]))
                    self.assertEqual(proposed["runtime_copies"], base["runtime_copies"])
                    self.assertTrue(any(k.startswith("G4_") for k in proposed["asset_metadata_profiles"]))
                    budget = portrait.manifest_budget(root, fragment, {"maximum_manifest_bytes":500000})
                    self.assertLess(budget["proposed_bytes"], 500000)
                    self.assertEqual(fragment, before); self.assertEqual(central.read_bytes(), raw)

if __name__ == "__main__": unittest.main()
