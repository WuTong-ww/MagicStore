"""The formal-manifest CLI must verify retained sources, not only JSON shape."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/art/validate_formal_manifest.py"


class FormalManifestValidationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        (self.workspace / "assets").mkdir()
        self.text = self.workspace / "assets/license.txt"
        self.text.write_bytes(b"retained license\n")
        self.image = self.workspace / "assets/scene.png"
        Image.new("RGBA", (8, 6), (90, 120, 130, 255)).save(self.image)
        self.manifest = {"schema_version": 3, "assets": [
            {"path": "assets/license.txt", "sha256": hashlib.sha256(self.text.read_bytes()).hexdigest()},
            {"path": "assets/scene.png", "sha256": hashlib.sha256(self.image.read_bytes()).hexdigest(),
             "dim": [8, 6]},
        ]}

    def run_cli(self):
        (self.workspace / "manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")
        return subprocess.run([sys.executable, "-B", str(SCRIPT), "--workspace", str(self.workspace),
                               "--manifest", "manifest.json"], capture_output=True, text=True,
                              encoding="utf-8", errors="replace")

    def test_cli_rejects_changed_source_bytes_including_line_endings(self):
        self.text.write_bytes(b"retained license\r\n")
        result = self.run_cli()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("assets/license.txt", result.stderr)
        self.assertIn("sha256", result.stderr.lower())

    def test_cli_rejects_png_dimensions_even_when_sha_matches(self):
        self.manifest["assets"][1]["dim"] = [8, 7]
        result = self.run_cli()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("assets/scene.png", result.stderr)
        self.assertIn("dimensions", result.stderr.lower())

    def test_cli_rejects_missing_formal_source(self):
        self.image.unlink()
        result = self.run_cli()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("assets/scene.png", result.stderr)
        self.assertIn("missing", result.stderr.lower())

    def test_cli_accepts_exact_text_and_png_sources(self):
        self.text.write_bytes(b"retained license\r\n")
        self.manifest["assets"][0]["sha256"] = hashlib.sha256(self.text.read_bytes()).hexdigest().upper()
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("valid", result.stdout.lower())
        self.assertEqual(result.stderr, "")

    def test_cli_checks_svg_sha_without_treating_svg_as_raster(self):
        source = self.workspace / "assets/reference.svg"
        source.write_bytes(b'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="6"/>\n')
        self.manifest["assets"].append({"path": "assets/reference.svg",
                                        "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                                        "dim": [8, 6]})
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")

    def test_alias_only_runtime_is_a_real_formal_file_not_optional_metadata(self):
        self.manifest["runtime_copies"] = [{"path":"assets/runtime-only.png","source_path":"assets/scene.png",
            "sha256":"a"*64,"runtime_size":[16,9]}]
        result = self.run_cli()
        self.assertEqual(result.returncode,1,result.stdout+result.stderr)
        self.assertIn("assets/runtime-only.png",result.stderr)

    def test_alias_only_runtime_checks_exact_sha_and_dimensions(self):
        target=self.workspace/"assets/runtime-only.png";Image.new("RGB",(16,9)).save(target)
        alias={"path":"assets/runtime-only.png","source_path":"assets/scene.png",
               "sha256":hashlib.sha256(target.read_bytes()).hexdigest(),"runtime_size":[16,9]}
        self.manifest["runtime_copies"]=[alias]
        good=self.run_cli();self.assertEqual(good.returncode,0,good.stdout+good.stderr)
        alias["runtime_size"]=[16,10]
        bad=self.run_cli();self.assertEqual(bad.returncode,1,bad.stdout+bad.stderr)
        self.assertIn("dimensions",bad.stderr)


if __name__ == "__main__":
    unittest.main()
