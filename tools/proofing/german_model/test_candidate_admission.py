"""Admission failures must precede native imports or publisher code execution."""
import hashlib
import json
import os
from pathlib import Path
import py_compile
import subprocess
import sys
import tempfile
import unittest


class CandidateAdmissionTest(unittest.TestCase):
    def run_verified_source(self, *, cache_mode=None, change_after_admission=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = root / "quickstart.py"
            reviewed = (
                "from pathlib import Path\n"
                "assert __name__ == 'pinned_publisher_reference'\n"
                "assert Path(__file__).name == 'quickstart.py'\n"
                "class Gector:\n"
                "    def __init__(self, model):\n"
                "        assert Path(model).is_dir()\n"
                "    def correct(self, text):\n"
                "        return 'reviewed', ['Grüße']\n"
            ).encode("utf-8")
            unreviewed = reviewed.replace(b"reviewed", b"cached!!")
            self.assertEqual(len(reviewed), len(unreviewed))
            if cache_mode is not None:
                runner.write_bytes(unreviewed)
                os.utime(runner, (1700000000, 1700000000))
                py_compile.compile(str(runner), doraise=True,
                                   invalidation_mode=cache_mode)
            runner.write_bytes(reviewed)
            os.utime(runner, (1700000000, 1700000000))
            # The evaluator's native import is a deliberate local test double.
            # No ONNX installation, inference or external code is required.
            fake_ort = "__version__ = 'admission-test-only'\nInferenceSession = object\n"
            if change_after_admission:
                fake_ort += (
                    "from pathlib import Path\n"
                    f"Path({str(runner)!r}).write_bytes({unreviewed!r})\n"
                )
            (root / "onnxruntime.py").write_text(fake_ort)
            payload = {"model.onnx": b"not a model", "LICENSE": b"license",
                       "NOTICE": b"notice", "quickstart.py": reviewed}
            manifest = []
            for name, data in payload.items():
                if name != "quickstart.py":
                    (root / name).write_bytes(data)
                manifest.append({"file": name, "size": len(data),
                                 "sha256": hashlib.sha256(data).hexdigest()})
            (root / "manifest.json").write_text(json.dumps(manifest))
            (root / "cases.json").write_text(json.dumps([
                {"id": "source-admission", "input": "original",
                 "expected": "reviewed", "kind": "error"},
            ]))
            environment = dict(os.environ, PYTHONPATH=str(root))
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name("evaluate_candidate.py")),
                "--manifest", str(root / "manifest.json"), "--model-dir", str(root),
                "--cases", str(root / "cases.json"), "--output", str(root / "result.json"),
            ], capture_output=True, text=True, timeout=10, env=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((root / "result.json").read_text())
            case = report["suites"][0]["cases"][0]
            self.assertEqual(case["output"], "reviewed")
            self.assertEqual(case["suggestions"], ["Grüße"])
            self.assertTrue(case["exact"])
            self.assertEqual(report["runner_sha256"], hashlib.sha256(reviewed).hexdigest())
            self.assertFalse(report["application_enabled"])

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

    def test_executes_reviewed_source_without_native_inference(self):
        self.run_verified_source()

    def test_ignores_timestamp_valid_unreviewed_bytecode(self):
        self.run_verified_source(cache_mode=py_compile.PycInvalidationMode.TIMESTAMP)

    def test_ignores_unchecked_hash_unreviewed_bytecode(self):
        self.run_verified_source(cache_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)

    def test_executes_bytes_verified_before_native_import(self):
        self.run_verified_source(change_after_admission=True)


if __name__ == "__main__":
    unittest.main()
