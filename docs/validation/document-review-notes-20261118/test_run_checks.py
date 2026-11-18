#!/usr/bin/env python3
"""Small offline preflight for the recovered local-gate runner."""

import importlib.util
import json
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "notes_review_gate", Path(__file__).with_name("run_checks.py")
)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class TextLog:
    def __init__(self, events):
        self.events = events

    def read_text(self, **_):
        return "ordinary build output\n" + "\n".join(
            event if isinstance(event, str) else json.dumps(event) for event in self.events
        )


def case(ident, name, **result):
    return [
        {"type": "testStart", "test": {"id": ident, "suiteID": 0, "name": name}},
        {"type": "testDone", "testID": ident, "result": "success", "skipped": False, **result},
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
        )

    def test_vm_is_the_default(self):
        self.assertEqual(self.command(), [
            "/verified/runtime/bin/dart", "test", "--concurrency=1",
            "--reporter=json", "test/example_test.dart",
        ])

    def test_node_is_requested_explicitly(self):
        self.assertEqual(self.command(platform="node"), [
            "/verified/runtime/bin/dart", "test", "--platform=node",
            "--concurrency=1", "--reporter=json", "test/example_test.dart",
        ])

    def test_flutter_keeps_offline_dependency_resolution(self):
        self.assertIn("--no-pub", self.command(runner="flutter"))

    def test_unsupported_runners_and_platforms_are_rejected(self):
        for options in [
            {"runner": "other"},
            {"platform": "chrome"},
            {"runner": "flutter", "platform": "node"},
        ]:
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.command(**options)


if __name__ == "__main__":
    unittest.main()
