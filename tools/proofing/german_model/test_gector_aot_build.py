"""Source binding and failure controls; no real compilation or network."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
from subprocess import CompletedProcess
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import build_gector_aot as build


class AotBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "source"
        for relative in build.SOURCE_FILES:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(relative + "\n")
        for directory in build.SOURCE_DIRECTORIES:
            path = self.root / directory / "nested" / "selected.dart"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(directory)
            path.with_suffix(".txt").write_text("not an input")
        self.dart = self.base / "sdk" / "bin" / "dart"
        for path in (self.dart, self.dart.with_name("dartaotruntime"),
                     self.dart.parent / "utils" / "gen_snapshot"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(path.name.encode())
            path.chmod(0o755)
        self.output = self.base / "output" / "runner.aot"
        self.receipt = self.base / "evidence" / "build.json"
        self.dependency = self.base / "dependency" / "lib" / "outside_selected_sources.dart"
        self.dependency.parent.mkdir(parents=True)
        self.dependency.write_text("dependency before compilation")
        config = self.root / ".dart_tool/package_config.json"
        config.parent.mkdir()
        config.write_text(json.dumps({"configVersion": 2, "packages": [{
            "name": "actual_dependency", "rootUri": "../../dependency/", "packageUri": "lib/",
        }, {
            "name": "native_only_plugin", "rootUri": "../../native_plugin/", "packageUri": "lib/",
        }]}))

    def run_build(self):
        status = build.build(self.dart, self.root, self.output, self.receipt)
        return status, json.loads(self.receipt.read_text())

    def compile_success(self, command, **kwargs):
        staged = Path(command[-1])
        staged.write_bytes(b"compiled AOT snapshot")
        return CompletedProcess(command, 0, f"Generated: {staged}\n".encode(), b"")

    def test_source_selection_matches_dart_and_hashes_nested_files(self):
        runner = Path(__file__).with_name("run_gector_dart.dart").read_text()
        contract = runner[runner.index("Future<Map<String, String>> _sources("):]
        fixed = re.search(r"final paths = <String>\[(.*?)\];", contract, re.S).group(1)
        directories = re.search(r"for \(final directory in \[(.*?)\]\)", contract, re.S).group(1)
        self.assertEqual(list(build.SOURCE_FILES), re.findall(r"'([^']+)'", fixed))
        self.assertEqual(list(build.SOURCE_DIRECTORIES), re.findall(r"'([^']+)'", directories))
        sources = build.source_snapshot(self.root)
        self.assertEqual(list(sources), sorted(sources))
        self.assertEqual(len(sources), len(build.SOURCE_FILES) + 3)
        self.assertFalse(any(path.endswith(".txt") for path in sources))
        self.assertEqual(sources[build.ENTRYPOINT],
                         hashlib.sha256((build.ENTRYPOINT + "\n").encode()).hexdigest())

    def test_success_binds_sources_sdk_and_snapshot_without_host_paths(self):
        before = build.source_snapshot(self.root)
        with patch.dict(os.environ, {"TMPDIR": str(self.base)}):
            with patch.object(build.subprocess, "run", side_effect=self.compile_success) as run:
                status, receipt = self.run_build()
        self.assertEqual(status, 0)
        self.assertTrue(receipt["completed"] and receipt["passed"])
        self.assertTrue(receipt["source_stable"] and receipt["sdk_stable"])
        self.assertTrue(receipt["dependencies_stable"])
        self.assertEqual(receipt["source_files"], before)
        self.assertEqual(receipt["source_files_after"], before)
        self.assertEqual(receipt["compiler"]["executable"], build.file_pin(self.dart))
        self.assertEqual(receipt["runtime"]["executable"],
                         build.file_pin(self.dart.with_name("dartaotruntime")))
        self.assertEqual(receipt["runtime"]["entrypoint"], build.file_pin(self.output))
        self.assertEqual(receipt["dependency_inputs"]["packages"]["actual_dependency"]["dart_file_count"], 1)
        self.assertFalse(receipt["dependency_inputs"]["packages"]["native_only_plugin"]["library_directory_present"])
        self.assertNotIn("staging_directory", receipt)
        self.assertNotIn(str(self.base), json.dumps(receipt))
        run.assert_called_once()
        self.assertIsInstance(run.call_args.args[0], list)
        self.assertEqual(run.call_args.kwargs["cwd"], self.root)
        self.assertFalse(run.call_args.kwargs["shell"])
        self.assertNotIn("env", run.call_args.kwargs)

    def test_compile_failure_retains_diagnostics_and_partial_output(self):
        before = build.source_snapshot(self.root)
        def fail(command, **kwargs):
            Path(command[-1]).write_bytes(b"partial snapshot")
            return CompletedProcess(command, 42, b"compiler started\n",
                                    b"Error in /private/package-cache/broken.dart: missing type\n")
        with patch.object(build.subprocess, "run", side_effect=fail):
            status, receipt = self.run_build()
        self.assertEqual(status, 1)
        self.assertFalse(receipt["passed"] or receipt["completed"])
        self.assertEqual(receipt["compile"]["returncode"], 42)
        self.assertIn("missing type", receipt["compile"]["stderr"])
        self.assertNotIn("/private/package-cache", json.dumps(receipt))
        partial = self.output.parent / receipt["staging_directory"] / self.output.name
        self.assertEqual(receipt["runtime"]["entrypoint"], build.file_pin(partial))
        self.assertFalse(self.output.exists())
        self.assertEqual(build.source_snapshot(self.root), before)

    def test_changed_source_cannot_receive_a_successful_build_receipt(self):
        def change_source(command, **kwargs):
            (self.root / build.ENTRYPOINT).write_text("changed during compilation")
            return self.compile_success(command, **kwargs)
        with patch.object(build.subprocess, "run", side_effect=change_source):
            status, receipt = self.run_build()
        self.assertEqual(status, 1)
        self.assertFalse(receipt["source_stable"] or receipt["passed"])
        self.assertIn("changed during compilation", receipt["error"])
        self.assertFalse(self.output.exists())
        self.assertTrue((self.output.parent / receipt["staging_directory"] / self.output.name).exists())

    def test_changed_dependency_fails_even_when_selected_sources_are_stable(self):
        def change_dependency(command, **kwargs):
            self.dependency.write_text("changed dependency implementation")
            return self.compile_success(command, **kwargs)
        with patch.object(build.subprocess, "run", side_effect=change_dependency):
            status, receipt = self.run_build()
        self.assertEqual(status, 1)
        self.assertTrue(receipt["source_stable"] and receipt["sdk_stable"])
        self.assertFalse(receipt["dependencies_stable"] or receipt["passed"])
        self.assertFalse(self.output.exists())

    def test_racing_output_is_not_replaced_and_compiler_result_is_preserved(self):
        def racing_output(command, **kwargs):
            self.output.write_bytes(b"another process owns this output")
            return self.compile_success(command, **kwargs)
        with patch.object(build.subprocess, "run", side_effect=racing_output):
            status, receipt = self.run_build()
        self.assertEqual(status, 1)
        self.assertFalse(receipt["passed"])
        self.assertEqual(self.output.read_bytes(), b"another process owns this output")
        staged = self.output.parent / receipt["staging_directory"] / self.output.name
        self.assertEqual(staged.read_bytes(), b"compiled AOT snapshot")
        self.assertEqual(receipt["error_type"], "FileExistsError")

    def test_destinations_cannot_overwrite_inputs_or_each_other(self):
        original = (self.root / build.ENTRYPOINT).read_bytes()
        for output, receipt in (
            (self.root / build.ENTRYPOINT, self.receipt),
            (self.root / "new.aot", self.receipt),
            (self.dart, self.receipt),
            (self.output, self.output),
            (self.output, self.output / "receipt.json"),
        ):
            with self.subTest(output=output, receipt=receipt):
                with patch.object(build.subprocess, "run") as run:
                    with self.assertRaises(ValueError):
                        build.build(self.dart, self.root, output, receipt)
                    run.assert_not_called()
        self.assertEqual((self.root / build.ENTRYPOINT).read_bytes(), original)
        self.receipt.parent.mkdir(parents=True)
        self.receipt.write_text("previous receipt")
        with self.assertRaises(ValueError):
            self.run_build()
        self.assertEqual(self.receipt.read_text(), "previous receipt")


if __name__ == "__main__":
    unittest.main()
