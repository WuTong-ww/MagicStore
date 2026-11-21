"""Local evidence remains optional, immutable and separate from active art."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/art/local_audit.py"


def implementation(test):
    test.assertTrue(SCRIPT.is_file(), "Independent local art audit reader is missing")
    spec = importlib.util.spec_from_file_location("local_art_audit_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LocalAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)
        self.path = ".tools/archive/art.jsonl"
        self.runtime = {"path": "assets/generated_scenes/runtime/v3/S01_day.png",
                        "source_path": "assets/_incoming/a1r_placeholders/S01_day.png",
                        "native_size": [2560, 1440], "runtime_size": [1920, 1080],
                        "method": "equal-aspect cover crop, Lanczos runtime copy",
                        "sha256": "a" * 64, "source_sha256": "b" * 64,
                        "status": "placeholder"}
        self.rows = [
            {"type": "manifest_section", "key": "pack_version", "value": "old-v2"},
            {"type": "manifest_section", "key": "round2_art",
             "value": {"version": 1, "active_style": {"status": "complete"},
                       "recipes": [{"prompt": "旧绘本提示词", "status": "complete"}]},
             "status": "rejected_style_v2", "reason": "策划否决：太冷清"},
            {"type": "runtime_copy", "key": self.runtime["path"], "value": self.runtime,
             "status": "rejected_style_v2", "reason": "策划否决：太冷清"}]

    def put_rows(self, rows=None):
        target = self.workspace / self.path
        target.parent.mkdir(parents=True, exist_ok=True)
        data = "".join(json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n"
                       for row in (self.rows if rows is None else rows)).encode("utf-8")
        target.write_bytes(data)
        return hashlib.sha256(data).hexdigest()

    def descriptor(self, digest="0" * 64, **changes):
        value = {"version": 1, "kind": "local_art_audit", "path": self.path,
                 "sha256": digest, "source_commit": "1" * 40, "optional": True,
                 "status": "retired", "reason": "策划否决：太冷清"}
        value.update(changes)
        return value

    def test_reader_preserves_original_section_values_and_unicode_reason(self):
        module = implementation(self)
        digest = self.put_rows()
        rows = module.read_jsonl(self.workspace, self.path, expected_sha256=digest)
        self.assertEqual(rows, self.rows)
        self.assertEqual(rows[1]["value"]["active_style"]["status"], "complete")
        self.assertEqual(rows[1]["reason"], "策划否决：太冷清")

    def test_writer_is_idempotent_and_refuses_conflicting_existing_bytes(self):
        module = implementation(self)
        result = module.write_jsonl(self.workspace, self.path, self.rows)
        target = self.workspace / self.path
        before = target.read_bytes()
        self.assertEqual(result["sha256"], hashlib.sha256(before).hexdigest())
        self.assertEqual(module.write_jsonl(self.workspace, self.path, self.rows), result)
        changed = copy.deepcopy(self.rows)
        changed[0]["value"] = "different bytes"
        with self.assertRaises(FileExistsError):
            module.write_jsonl(self.workspace, self.path, changed)
        self.assertEqual(target.read_bytes(), before)

    def test_writer_validates_all_rows_before_creating_any_output_directory(self):
        module = implementation(self)
        bad = copy.deepcopy(self.rows)
        bad[-1]["value"]["sha256"] = "not-a-hash"
        with self.assertRaises(ValueError):
            module.write_jsonl(self.workspace, self.path, bad)
        self.assertEqual(list(self.workspace.iterdir()), [])

    def test_malformed_json_duplicate_keys_blank_lines_and_nonfinite_values_fail(self):
        module = implementation(self)
        target = self.workspace / "malformed.jsonl"
        samples = [b"", b"{}\n", b"{bad json}\n", b"\xff\n",
                   b'{"type":"manifest_section","key":"x","value":1,"value":2}\n',
                   b'{"type":"manifest_section","key":"x","value":NaN}\n',
                   b'{"type":"manifest_section","key":"x","value":Infinity}\n',
                   b'{"type":"manifest_section","key":"x","value":1}\n\n']
        for data in samples:
            target.write_bytes(data)
            with self.subTest(data=data), self.assertRaises(ValueError):
                module.read_jsonl(self.workspace, "malformed.jsonl")

    def test_duplicate_record_identity_and_unknown_envelope_fields_are_rejected(self):
        module = implementation(self)
        cases = [self.rows + [copy.deepcopy(self.rows[0])],
                 [{**self.rows[0], "unrecognized": True}],
                 [{**self.rows[0], "type": "activate_art"}],
                 [{**self.rows[0], "key": []}]]
        for rows in cases:
            self.put_rows(rows)
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                module.read_jsonl(self.workspace, self.path)

    def test_runtime_rows_validate_paths_hashes_dimensions_and_identity_without_opening_pngs(self):
        module = implementation(self)
        self.put_rows()
        self.assertEqual(len(module.read_jsonl(self.workspace, self.path)), 3)
        for field, value in [("path", "../escape.png"), ("source_path", "C:/outside.png"),
                             ("sha256", "z" * 64), ("source_sha256", "0"),
                             ("native_size", [True, 1440]), ("runtime_size", [1920, 0])]:
            rows = copy.deepcopy(self.rows)
            rows[-1]["value"][field] = value
            if field == "path":
                rows[-1]["key"] = value
            self.put_rows(rows)
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.read_jsonl(self.workspace, self.path)
        rows = copy.deepcopy(self.rows)
        rows[-1]["key"] = "safe/different.png"
        self.put_rows(rows)
        with self.assertRaises(ValueError):
            module.read_jsonl(self.workspace, self.path)

    def test_rejection_requires_an_intact_reason_instead_of_garbled_metadata(self):
        module = implementation(self)
        for reason in ("", "   ", "\ufffdmissing text", None):
            rows = copy.deepcopy(self.rows)
            rows[1]["reason"] = reason
            self.put_rows(rows)
            with self.subTest(reason=reason), self.assertRaises(ValueError):
                module.read_jsonl(self.workspace, self.path)

    def test_optional_missing_audit_is_an_explicit_skip_and_writes_nothing(self):
        module = implementation(self)
        report = module.inspect_audit(self.workspace, self.descriptor())
        self.assertEqual(report["status"], "skipped")
        self.assertEqual(report["code"], "SKIP_LOCAL_AUDIT_MISSING")
        self.assertFalse(report["active"])
        self.assertFalse(report["validated"])
        self.assertEqual(report["missing"], [self.path])
        self.assertEqual(list(self.workspace.iterdir()), [])
        with self.assertRaises(FileNotFoundError):
            module.inspect_audit(self.workspace, self.descriptor(optional=False))

    def test_rejected_archive_is_retired_even_if_original_value_says_complete(self):
        module = implementation(self)
        digest = self.put_rows()
        report = module.inspect_audit(self.workspace, self.descriptor(digest, status="local_only", reason=""))
        self.assertEqual((report["status"], report["records"], report["retired_records"]), ("retired", 3, 2))
        self.assertFalse(report["active"])
        self.assertTrue(report["validated"])
        self.assertEqual(report["types"], {"manifest_section": 2, "runtime_copy": 1})
        self.assertFalse((self.workspace / "assets").exists())

    def test_present_archive_with_wrong_sha_fails_instead_of_becoming_a_skip(self):
        module = implementation(self)
        self.put_rows()
        with self.assertRaisesRegex(ValueError, "SHA256"):
            module.inspect_audit(self.workspace, self.descriptor())

    def test_descriptor_rejects_unsafe_paths_invalid_sha_and_unknown_schema(self):
        module = implementation(self)
        for changes in ({"path": "../outside.jsonl"}, {"path": "C:/outside.jsonl"},
                        {"path": "folder\\outside.jsonl"}, {"path": "/outside.jsonl"},
                        {"path": "audit.png"}, {"sha256": "not-a-hash"},
                        {"version": True}, {"optional": 1}, {"kind": "active_art"},
                        {"source_commit": "x" * 40}, {"unexpected": "field"},
                        {"status": "local_only", "reason": []}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                module.inspect_audit(self.workspace, self.descriptor(**changes))

    def test_resolved_directory_link_cannot_read_or_write_outside_workspace(self):
        module = implementation(self)
        # The Windows application sandbox's redirected TEMP rejects even
        # unprivileged junction creation. Use the project's explicit scratch
        # root for this real filesystem test, with two sibling directories.
        with tempfile.TemporaryDirectory(dir=ROOT / ".tools") as temporary:
            workspace = Path(temporary) / "workspace"
            outside = Path(temporary) / "outside"
            workspace.mkdir()
            outside.mkdir()
            link = workspace / "link"
            junction = os.name == "nt"
            if junction:
                # A native directory junction needs no symlink privilege.
                # Both paths are explicit temporary-directory boundaries;
                # cleanup removes only the link itself, never its target.
                self.assertEqual(link.parent.resolve(), workspace.resolve())
                result = subprocess.run(["cmd", "/d", "/c", "mklink", "/J", str(link), str(Path(outside).resolve())],
                                        capture_output=True)
                self.assertEqual(result.returncode, 0,
                                 "Directory junction creation failed: " + repr(result.stdout + result.stderr))
            else:
                link.symlink_to(outside, target_is_directory=True)
            try:
                self.assertEqual(link.resolve(), Path(outside).resolve())
                with self.assertRaises(ValueError):
                    module.write_jsonl(workspace, "link/escape.jsonl", self.rows)
                with self.assertRaises(ValueError):
                    module.inspect_audit(workspace, self.descriptor(path="link/missing.jsonl"))
                self.assertEqual(list(Path(outside).iterdir()), [])
            finally:
                if junction:
                    os.rmdir(link)
                else:
                    link.unlink()

    def test_cli_reports_skip_retired_and_errors_without_writing_other_files(self):
        module = implementation(self)
        descriptor_path = self.workspace / "descriptor.json"
        descriptor_path.write_text(json.dumps(self.descriptor()), encoding="utf-8")
        arguments = ["--workspace", str(self.workspace), "--descriptor", "descriptor.json"]
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(module.main(arguments), 0)
        self.assertEqual(json.loads(output.getvalue())["code"], "SKIP_LOCAL_AUDIT_MISSING")
        digest = self.put_rows()
        descriptor_path.write_text(json.dumps(self.descriptor(digest)), encoding="utf-8")
        before = {p: p.read_bytes() for p in self.workspace.rglob("*") if p.is_file()}
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), *arguments],
                                capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "retired")
        self.assertEqual(before, {p: p.read_bytes() for p in self.workspace.rglob("*") if p.is_file()})
        descriptor_path.write_text(json.dumps(self.descriptor()), encoding="utf-8")
        with redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
            self.assertEqual(module.main(arguments), 1)


if __name__ == "__main__":
    unittest.main()
