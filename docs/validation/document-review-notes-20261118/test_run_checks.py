#!/usr/bin/env python3
"""Small offline preflight for the recovered local-gate runner."""

import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.parse import quote


spec = importlib.util.spec_from_file_location(
    "notes_review_gate", Path(__file__).with_name("run_checks.py")
)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class TextLog:
    def __init__(self, events):
        self.events = events

    def read_text(self, **_):
        return "Running build hooks...\n" + "\n".join(
            event if isinstance(event, str) else json.dumps(event) for event in self.events
        )


def case(ident, name, **result):
    return [
        {"type": "testStart", "test": {"id": ident, "suiteID": 0, "name": name}},
        {"type": "testDone", "testID": ident, "result": "success", "skipped": False,
         "hidden": False, **result},
    ]


class ReporterTests(unittest.TestCase):
    def parse(self, *events, include_start=True):
        cwd = Path("/synthetic/package")
        return gate.parse_reporter(
            TextLog([
                *([{"type": "start"}] if include_start else []),
                {"type": "suite", "suite": {"id": 0, "path": str(cwd / "test/example_test.dart")}},
                *events,
            ]),
            cwd,
            ["test/example_test.dart"],
        )

    def test_count_only_completed_user_cases(self):
        result = self.parse(
            *case(0, "loading test/example_test.dart", hidden=True),
            *case(1, "group (setUpAll)"),
            *case(2, "actual user case"),
            *case(3, "group (tearDownAll)"),
            {"type": "done", "success": True},
        )
        self.assertEqual(result["passed"], 1)
        self.assertEqual(len(result["cases"]), 1)
        self.assertTrue(gate.reporter_passed(result))

    def test_skips_and_error_events_block_acceptance(self):
        for extra, completion in [
            ([], {"skipped": True}),
            ([{"type": "error", "error": "failure outside case completion"}], {}),
            ([], {"result": "failure"}),
        ]:
            with self.subTest(extra=extra, completion=completion):
                result = self.parse(
                    *case(0, "actual user case", **completion),
                    *extra,
                    {"type": "done", "success": True},
                )
                self.assertFalse(gate.reporter_passed(result))

    def test_empty_or_unfinished_suites_block_acceptance(self):
        for events in [
            [],
            [{"type": "testStart", "test": {"id": 0, "suiteID": 0, "name": "unfinished"}}],
        ]:
            with self.subTest(events=events):
                result = self.parse(*events, {"type": "done", "success": True})
                self.assertFalse(gate.reporter_passed(result))

    def test_duplicate_completion_blocks_acceptance(self):
        events = case(0, "actual user case")
        result = self.parse(*events, events[-1], {"type": "done", "success": True})
        self.assertEqual(result["passed"], 1)
        self.assertFalse(gate.reporter_passed(result))

    def test_build_hook_prefix_preserves_reporter_start(self):
        events = [
            'Running build hooks...{"type":"start"}',
            {"type": "suite", "suite": {"id": 0, "path": "test/example_test.dart"}},
            *case(0, "actual user case"),
            {"type": "done", "success": True},
        ]
        result = gate.parse_reporter(
            TextLog(events), Path("/synthetic/package"), ["test/example_test.dart"]
        )
        self.assertTrue(gate.reporter_passed(result))

    def test_malformed_and_truncated_events_never_disappear(self):
        for event in [
            '{"type":"testStart","test":malformed}',
            '{"type":"error","testID":0,"error":',
            'Running build hooks...{"type":"error",',
            {"missing": "event type"},
        ]:
            with self.subTest(event=event):
                result = self.parse(
                    *case(0, "actual user case"), event, {"type": "done", "success": True}
                )
                self.assertTrue(result["protocol_anomalies"])
                self.assertFalse(gate.reporter_passed(result))

    def test_start_and_terminal_order_is_required(self):
        passed = case(0, "actual user case")
        done = {"type": "done", "success": True}
        for events, include_start in [
            ([*passed, done], False),
            ([{"type": "start"}, *passed, done], True),
            (passed, True),
            ([*passed, done, done], True),
            ([done, *passed], True),
            ([*passed, {"type": "done", "success": False}], True),
        ]:
            with self.subTest(events=events, include_start=include_start):
                result = self.parse(*events, include_start=include_start)
                self.assertFalse(gate.reporter_passed(result))

    def test_invalid_case_flags_and_payloads_are_rejected(self):
        for events in [
            case(0, "case", skipped="false"),
            case(0, "case", hidden="false"),
            case(0, "case", result=[]),
            [{"type": "testStart", "test": {"id": "0", "suiteID": 0, "name": "case"}}],
            [{"type": "suite", "suite": {"id": 3, "path": 42}}],
        ]:
            with self.subTest(events=events):
                result = self.parse(*events, {"type": "done", "success": True})
                self.assertTrue(result["protocol_anomalies"])
                self.assertFalse(gate.reporter_passed(result))


class NativeStderrTests(unittest.TestCase):
    def capture(self, *, malformed=False, exit_code=0):
        temporary = tempfile.TemporaryDirectory(prefix="reporter streams ")
        self.addCleanup(temporary.cleanup)
        cwd = Path(temporary.name)
        events = [
            {"type": "start"},
            {"type": "suite", "suite": {"id": 0, "path": str(cwd / "test/example_test.dart")}},
            *case(1, "actual user case"),
            {"type": "done", "success": True},
        ]
        stdout_bytes = ("\n".join(json.dumps(event) for event in events) + "\n").encode()
        if malformed:
            stdout_bytes = b'{"type":"error",broken}\n' + stdout_bytes
        stderr_bytes = b'error: /missing/ar.aff: cannot open\nerror: /missing/ar.dic: cannot open\n'
        program = ("import os,sys; os.write(1," + repr(stdout_bytes) + "); "
                   "os.write(2," + repr(stderr_bytes) + "); sys.exit(" + str(exit_code) + ")")
        sys.path.insert(0, str(gate.repository_root() / "tools/mail"))
        from check_store import execute
        log, errors = cwd / "stdout.jsonl", cwd / "stderr.log"
        with log.open("wb") as output, errors.open("wb") as diagnostics:
            code = execute([sys.executable, "-c", program], cwd=cwd, env=os.environ.copy(),
                           stdout=output, stderr=diagnostics, timeout=10)
        self.assertEqual(log.read_bytes(), stdout_bytes)
        self.assertEqual(errors.read_bytes(), stderr_bytes)
        return code, gate.parse_reporter(log, cwd, ["test/example_test.dart"])

    def test_native_stderr_is_retained_without_corrupting_reporter_stdout(self):
        code, result = self.capture()
        self.assertEqual(code, 0)
        self.assertEqual(result["passed"], 1)
        self.assertTrue(gate.reporter_passed(result))

    def test_separate_stderr_does_not_hide_malformed_reporter_stdout(self):
        code, result = self.capture(malformed=True)
        self.assertEqual(code, 0)
        self.assertFalse(gate.reporter_passed(result))

    def test_separate_stderr_preserves_nonzero_exit_with_successful_reporter(self):
        code, result = self.capture(exit_code=7)
        self.assertEqual(code, 7)
        self.assertTrue(gate.reporter_passed(result))
        self.assertFalse(code == 0 and gate.reporter_passed(result))


class CommandTests(unittest.TestCase):
    def command(self, **options):
        return gate.test_command(
            Path("/verified/runtime"),
            {"runner": "dart", "tests": ["test/example_test.dart"], **options},
            package_config=Path("/workspace/.dart_tool/package_config.json"),
            test_entrypoint=Path("/verified/runtime/pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart"),
        )

    def test_vm_is_the_default(self):
        self.assertEqual(self.command(), [
            "/verified/runtime/bin/dart", "--disable-dart-dev",
            "--packages=/workspace/.dart_tool/package_config.json",
            "/verified/runtime/pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart",
            "--compiler=kernel", "--concurrency=1",
            "--reporter=json", "test/example_test.dart",
        ])

    def test_node_is_requested_explicitly(self):
        self.assertEqual(self.command(platform="node"), [
            "/verified/runtime/bin/dart", "--disable-dart-dev",
            "--packages=/workspace/.dart_tool/package_config.json",
            "/verified/runtime/pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart",
            "--platform=node",
            "--concurrency=1", "--reporter=json", "test/example_test.dart",
        ])

    def test_flutter_keeps_offline_dependency_resolution(self):
        self.assertEqual(self.command(runner="flutter"), [
            "/verified/runtime/bin/flutter", "test", "--no-pub",
            "--concurrency=1", "--reporter=json", "test/example_test.dart",
        ])

    def test_unsupported_runners_and_platforms_are_rejected(self):
        for options in [
            {"runner": "other"},
            {"platform": "chrome"},
            {"runner": "flutter", "platform": "node"},
        ]:
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.command(**options)


class WhitespaceInputTests(unittest.TestCase):
    def setUp(self):
        self.path = "docs/validation/example/checks/raw.log"
        self.blob = "a" * 40
        self.tracked = {self.path: {"mode": "100644", "git_blob": self.blob}}
        self.entry = {"path": self.path, "git_blob": self.blob, "reason": "Raw captured log"}

    def test_exact_frozen_evidence_becomes_an_exact_path_exclusion(self):
        for path in [self.path, "docs/validation/example/build.txt",
                     "docs/validation/example/notices/LICENSE.md",
                     "docs/validation/example/recovery/raw.patch"]:
            with self.subTest(path=path):
                entry = {**self.entry, "path": path}
                tracked = {path: {"mode": "100644", "git_blob": self.blob}}
                preserved = gate.validate_whitespace_preserved_inputs([entry], tracked)
                self.assertEqual(preserved, [entry])
                self.assertEqual(gate.whitespace_command("base", "head", preserved), [
                    "git", "diff", "--check", "base", "head", "--", ".",
                    ":(exclude)" + path,
                ])
        self.assertEqual(gate.whitespace_command("base", "head", []), [
            "git", "diff", "--check", "base", "head", "--", ".",
        ])

    def test_changed_blob_path_duplicate_or_missing_reason_is_rejected(self):
        for entries in [
            [{**self.entry, "git_blob": "b" * 40}],
            [{**self.entry, "path": "docs/validation/example/checks/different.log"}],
            [self.entry, self.entry],
            [{**self.entry, "reason": ""}],
        ]:
            with self.subTest(entries=entries), self.assertRaises(RuntimeError):
                gate.validate_whitespace_preserved_inputs(entries, self.tracked)

    def test_exact_hunspell_release_notice_pins_are_accepted(self):
        for name, blob in [
            ("COPYING.MPL", "7714141d154290f53e9e60c615a8edc9b51a8df7"),
            ("license.hunspell", "fad5a162300e7d1719ff6b7ba3713aaaa501a4bc"),
            ("license.myspell", "2da533075026777f93882fdeb11ff02a711d4b81"),
        ]:
            path = "packages/quds_proofing_hunspell/licenses/upstream/" + name
            entry = {"path": path, "git_blob": blob, "reason": "Verbatim pinned upstream notice"}
            tracked = {path: {"mode": "100644", "git_blob": blob}}
            with self.subTest(name=name):
                preserved = gate.validate_whitespace_preserved_inputs([entry], tracked)
                self.assertEqual(preserved, [entry])
                self.assertEqual(gate.whitespace_command("base", "head", preserved)[-1],
                                 ":(exclude)" + path)

    def test_changed_upstream_notice_pin_is_rejected_even_when_tracked(self):
        path = "packages/quds_proofing_hunspell/licenses/upstream/COPYING.MPL"
        expected = "7714141d154290f53e9e60c615a8edc9b51a8df7"
        changed = "b" * 40
        for entry_blob, tracked_blob in [(changed, changed), (expected, changed),
                                         (changed, expected)]:
            entry = {"path": path, "git_blob": entry_blob, "reason": "Verbatim upstream"}
            tracked = {path: {"mode": "100644", "git_blob": tracked_blob}}
            with self.subTest(entry_blob=entry_blob, tracked_blob=tracked_blob), self.assertRaises(RuntimeError):
                gate.validate_whitespace_preserved_inputs([entry], tracked)

    def test_upstream_notice_exception_does_not_extend_to_other_package_files(self):
        for path in [
            "packages/quds_proofing_hunspell/licenses/upstream/OTHER.txt",
            "packages/quds_proofing_hunspell/licenses/upstream/LICENSE.md",
            "packages/quds_proofing_hunspell/licenses/upstream/COPYING.MPL.copy",
            "packages/other/licenses/upstream/COPYING.MPL",
        ]:
            blob = "7714141d154290f53e9e60c615a8edc9b51a8df7"
            entry = {"path": path, "git_blob": blob, "reason": "Copied pinned notice"}
            tracked = {path: {"mode": "100644", "git_blob": blob}}
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                gate.validate_whitespace_preserved_inputs([entry], tracked)

    def test_product_paths_globs_and_traversal_cannot_be_excluded(self):
        for path in [
            "packages/quds_office_editor/lib/editor.dart",
            "docs/validation/**/*.log",
            "docs/validation/../../packages/editor.dart",
            "docs/validation/example/checks/raw?.log",
            "docs/validation/example/run_checks.py",
            "docs/validation/example/native_asset_smoke.dart",
            "docs/validation/example/test-plan.json",
            "docs/validation/example/README.md",
        ]:
            tracked = {path: {"mode": "100644", "git_blob": self.blob}}
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                gate.validate_whitespace_preserved_inputs([{**self.entry, "path": path}], tracked)


class RuntimeInputTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="review gate ")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.repo = self.base / "workspace"
        self.runtime = self.base / "runtime"
        self.root = self.runtime / "pub-cache/hosted/pub.dev/test-1.31.1"
        self.launcher = self.root / "bin/test.dart"
        self.launcher.parent.mkdir(parents=True)
        self.launcher.write_text("void main() {}\n")
        self.config = self.repo / ".dart_tool/package_config.json"
        self.config.parent.mkdir(parents=True)
        self.configure(self.root.as_uri())
        gate.write_json(self.runtime / "pub-cache-receipt.json", [
            {"name": "test", "version": "1.31.1", "verified": True},
        ])
        self.retained = {
            self.launcher.relative_to(self.runtime).as_posix(): {
                "sha256": gate.sha256(self.launcher),
            },
        }

    def configure(self, uri, *, duplicate=False):
        package = {"name": "test", "rootUri": uri}
        gate.write_json(self.config, {"packages": [package] * (2 if duplicate else 1)})

    def test_absolute_and_relative_encoded_file_uris_resolve(self):
        for uri in [self.root.as_uri(), quote(os.path.relpath(self.root, self.config.parent))]:
            with self.subTest(uri=uri):
                self.configure(uri)
                self.assertEqual(
                    gate.resolve_test_launcher(self.repo, self.runtime, self.retained),
                    (self.config, self.launcher),
                )

    def test_ambiguous_remote_or_unverified_roots_are_rejected(self):
        for uri, duplicate in [
            (self.root.as_uri(), True),
            ("https://example.invalid/test", False),
            ("file://remote/hosted/test-1.31.1", False),
            (self.root.as_uri() + "?other", False),
            ((self.base / "unverified/test-1.31.1").as_uri(), False),
            (self.root.with_name("test-9.0.0").as_uri(), False),
        ]:
            with self.subTest(uri=uri, duplicate=duplicate):
                self.configure(uri, duplicate=duplicate)
                with self.assertRaises(RuntimeError):
                    gate.resolve_test_launcher(self.repo, self.runtime, self.retained)

    def test_launcher_requires_retained_content_binding(self):
        with self.assertRaisesRegex(RuntimeError, "retained"):
            gate.resolve_test_launcher(self.repo, self.runtime, {})
        self.launcher.write_text("changed launcher\n")
        with self.assertRaisesRegex(RuntimeError, "retained"):
            gate.resolve_test_launcher(self.repo, self.runtime, self.retained)

    def test_node_and_native_assets_require_recorded_hashes(self):
        node = self.base / "node"
        node.write_text("pinned node executable\n")
        library = self.repo / ".dart_tool/libsqlite3.so"
        library.write_text("pinned native asset\n")
        manifest = self.repo / ".dart_tool/native_assets.yaml"
        manifest.write_text("# Generated by Dart\n" + json.dumps({
            "native-assets": {"linux_x64": {"package:sqlite3": ["absolute", str(library)]}},
        }))
        inputs = {str(path): gate.sha256(path) for path in (node, library, manifest)}
        groups = [{"cwd": "packages/mail", "platform": "node"}]
        recorded, optional = gate.additional_runtime_inputs(
            {"additional_inputs": inputs}, self.repo, groups, node_executable=str(node),
        )
        self.assertEqual(set(recorded.values()), {node, library, manifest})
        self.assertIn("workspace/packages/mail/.dart_tool/native_assets.yaml", optional)
        for missing in (node, library, manifest):
            with self.subTest(missing=missing), self.assertRaises(RuntimeError):
                gate.additional_runtime_inputs(
                    {"additional_inputs": {name: digest for name, digest in inputs.items()
                                           if name != str(missing)}},
                    self.repo, groups, node_executable=str(node),
                )
        library.write_text("changed native asset\n")
        with self.assertRaisesRegex(RuntimeError, "missing or changed"):
            gate.additional_runtime_inputs(
                {"additional_inputs": inputs}, self.repo, groups, node_executable=str(node),
            )

    def test_absent_optional_maps_are_bound_and_nearer_maps_rejected(self):
        groups = [{"cwd": "packages/mail"}]
        recorded, optional = gate.additional_runtime_inputs(
            {}, self.repo, groups, node_executable=None,
        )
        self.assertEqual(recorded, {})
        self.assertEqual(len(optional), 3)
        self.assertTrue(all(not path.exists() for path in optional.values()))
        shadow = self.repo / "packages/mail/.dart_tool/native_assets.yaml"
        shadow.parent.mkdir(parents=True)
        shadow.write_text("{}")
        with self.assertRaisesRegex(RuntimeError, "shadows"):
            gate.additional_runtime_inputs({}, self.repo, groups, node_executable=None)


if __name__ == "__main__":
    unittest.main()
