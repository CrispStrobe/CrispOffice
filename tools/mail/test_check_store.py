#!/usr/bin/env python3
"""Acceptance tests for the local Mail store runner's Dart event accounting."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_store import test_summary


def dart_events() -> list[dict[str, object]]:
    """A Dart JSON reporter stream with one hidden loader and two real cases."""
    return [
        {'type': 'start', 'protocolVersion': '0.1.1', 'runnerVersion': '1.31.1',
         'pid': 123, 'time': 0},
        {'type': 'suite', 'suite': {'id': 0, 'platform': 'vm', 'path': 'sample_test.dart'},
         'time': 0},
        {'type': 'testStart',
         'test': {'id': 1, 'name': 'loading sample_test.dart', 'suiteID': 0,
                  'groupIDs': [], 'metadata': {'skip': False, 'skipReason': None}},
         'time': 1},
        {'type': 'allSuites', 'count': 1, 'time': 1},
        {'type': 'testDone', 'testID': 1, 'result': 'success', 'skipped': False,
         'hidden': True, 'time': 2},
        {'type': 'group',
         'group': {'id': 2, 'suiteID': 0, 'parentID': None, 'name': '',
                   'metadata': {'skip': False, 'skipReason': None}, 'testCount': 2},
         'time': 2},
        {'type': 'testStart',
         'test': {'id': 3, 'name': 'committed state survives reopening', 'suiteID': 0,
                  'groupIDs': [2], 'metadata': {'skip': False, 'skipReason': None}},
         'time': 3},
        {'type': 'testDone', 'testID': 3, 'result': 'success', 'skipped': False,
         'hidden': False, 'time': 4},
        {'type': 'testStart',
         'test': {'id': 4, 'name': 'rolled back state remains absent', 'suiteID': 0,
                  'groupIDs': [2], 'metadata': {'skip': False, 'skipReason': None}},
         'time': 5},
        {'type': 'testDone', 'testID': 4, 'result': 'success', 'skipped': False,
         'hidden': False, 'time': 6},
        {'type': 'done', 'success': True, 'time': 7},
    ]


def event_lines(events: list[dict[str, object]]) -> list[str]:
    return [json.dumps(event) for event in events]


class TestStoreEventAccounting(unittest.TestCase):
    def summary(self, lines: list[str]) -> dict[str, object]:
        with tempfile.TemporaryDirectory(prefix='mail-store-events-') as directory:
            path = Path(directory) / 'events.jsonl'
            path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
            return test_summary(path)

    def assert_rejected(self, events: list[dict[str, object]]) -> None:
        self.assertFalse(self.summary(event_lines(events))['valid'])

    def test_valid_stream_tolerates_native_hook_progress_and_excludes_loader(self):
        lines = event_lines(dart_events())
        lines[0] = 'Running build hooks...Running build hooks...' + lines[0]
        lines.insert(0, 'Running build hooks...')
        summary = self.summary(lines)
        self.assertTrue(summary['valid'])
        self.assertEqual(summary['passed'], 2)
        self.assertEqual(summary['failed'], 0)
        self.assertEqual(summary['skipped'], 0)
        self.assertEqual(summary['errors'], 0)
        self.assertIs(summary['terminal_success'], True)
        self.assertEqual(len(summary['cases']), 2)

    def test_malformed_event_cannot_disappear_from_otherwise_passing_stream(self):
        lines = event_lines(dart_events())
        lines.insert(-1, '{"type":"testStart","test":malformed}')
        self.assertFalse(self.summary(lines)['valid'])

    def test_truncated_event_is_rejected_even_when_terminal_success_is_present(self):
        lines = event_lines(dart_events())
        lines.insert(-1, '{"type":"error","testID":3,"error":')
        self.assertFalse(self.summary(lines)['valid'])

    def test_malformed_event_after_hook_progress_is_not_ignored(self):
        lines = event_lines(dart_events())
        lines.insert(-1, 'Running build hooks...{"type":"error",')
        self.assertFalse(self.summary(lines)['valid'])

    def test_missing_runner_start_is_rejected(self):
        self.assert_rejected([event for event in dart_events() if event['type'] != 'start'])

    def test_duplicate_runner_start_is_rejected(self):
        events = dart_events()
        events.insert(1, dict(events[0]))
        self.assert_rejected(events)

    def test_missing_terminal_is_rejected(self):
        self.assert_rejected([event for event in dart_events() if event['type'] != 'done'])

    def test_duplicate_terminal_is_rejected(self):
        events = dart_events()
        events.append(dict(events[-1]))
        self.assert_rejected(events)

    def test_failure_terminal_is_rejected_even_if_cases_pass(self):
        events = dart_events()
        events[-1]['success'] = False
        self.assert_rejected(events)

    def test_test_events_after_terminal_are_rejected(self):
        events = dart_events()
        terminal = events.pop()
        events.insert(6, terminal)
        self.assert_rejected(events)

    def test_orphan_test_completion_is_rejected(self):
        events = dart_events()
        events.insert(-1, {'type': 'testDone', 'testID': 99, 'result': 'success',
                           'skipped': False, 'hidden': False})
        self.assert_rejected(events)

    def test_duplicate_test_start_id_is_rejected(self):
        events = dart_events()
        events.insert(7, dict(events[6]))
        self.assert_rejected(events)

    def test_duplicate_test_completion_id_is_rejected(self):
        events = dart_events()
        events.insert(8, dict(events[7]))
        self.assert_rejected(events)

    def test_incomplete_visible_case_is_rejected(self):
        self.assert_rejected([
            event for event in dart_events()
            if not (event['type'] == 'testDone' and event['testID'] == 3)
        ])

    def test_incomplete_loader_is_rejected(self):
        self.assert_rejected([
            event for event in dart_events()
            if not (event['type'] == 'testDone' and event['testID'] == 1)
        ])

    def test_skipped_case_is_counted_and_prevents_qualification(self):
        events = dart_events()
        events[7]['skipped'] = True
        summary = self.summary(event_lines(events))
        self.assertFalse(summary['valid'])
        self.assertEqual(summary['passed'], 1)
        self.assertEqual(summary['skipped'], 1)

    def test_error_event_prevents_acceptance_even_with_successful_case_results(self):
        events = dart_events()
        events.insert(-1, {'type': 'error', 'testID': 3, 'error': 'asynchronous error',
                           'isFailure': False, 'stackTrace': ''})
        summary = self.summary(event_lines(events))
        self.assertFalse(summary['valid'])
        self.assertEqual(summary['errors'], 1)

    def test_no_substantive_cases_cannot_qualify(self):
        events = dart_events()
        self.assert_rejected(events[:6] + events[-1:])


if __name__ == '__main__':
    unittest.main()
