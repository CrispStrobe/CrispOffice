"""Admission failures must precede native imports or publisher code execution."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class CandidateAdmissionTest(unittest.TestCase):
    def run_rejected(self, mutate, expected):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = {"model.onnx": b"not a model", "LICENSE": b"license",
                       "NOTICE": b"notice", "quickstart.py": b"raise RuntimeError('EXECUTED_PUBLISHER')"}
            manifest = []
            for name, data in payload.items():
                (root / name).write_bytes(data)
                manifest.append({"file": name, "size": len(data),
                                 "sha256": hashlib.sha256(data).hexdigest()})
            mutate(root, manifest)
            (root / "manifest.json").write_text(json.dumps(manifest))
            (root / "cases.json").write_text("[]")
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name("evaluate_candidate.py")),
                "--manifest", str(root / "manifest.json"), "--model-dir", str(root),
                "--cases", str(root / "cases.json"), "--output", str(root / "result.json"),
            ], capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(expected, result.stderr)
            self.assertNotIn("EXECUTED_PUBLISHER", result.stderr)
            self.assertNotIn("ModuleNotFoundError", result.stderr)
            self.assertFalse((root / "result.json").exists())

    def test_modified_model(self):
        self.run_rejected(lambda r, _: (r / "model.onnx").write_bytes(b"bad"),
                          "Changed reviewed artifact: model.onnx")

    def test_modified_publisher_code_with_same_size(self):
        def mutate(root, _):
            path = root / "quickstart.py"
            path.write_bytes(b"x" * path.stat().st_size)
        self.run_rejected(mutate, "Changed reviewed artifact: quickstart.py")

    def test_duplicate_artifact(self):
        self.run_rejected(lambda _, m: m.append(m[0]), "Incomplete or duplicate artifact manifest")

    def test_path_escape(self):
        self.run_rejected(lambda _, m: m.append({"file": "../outside"}), "Unsafe artifact path")

    def test_missing_notice(self):
        self.run_rejected(lambda _, m: m.pop(2), "Incomplete or duplicate artifact manifest")


if __name__ == "__main__":
    unittest.main()
