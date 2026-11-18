#!/usr/bin/env python3
"""Small offline preflight for the recovered local-gate runner."""

import importlib.util
import json
import os
from pathlib import Path
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
