#!/usr/bin/env python3
"""Controls for affected-suite evidence, diagnostics and process cleanup."""
from contextlib import redirect_stderr
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_targeted as runner


def stream():
    return [
        {'type': 'start'},
        {'type': 'suite', 'suite': {'id': 0, 'path': 'sample_test.dart'}},
        {'type': 'testStart', 'test': {'id': 1, 'name': 'loading sample_test.dart', 'suiteID': 0}},
        {'type': 'testDone', 'testID': 1, 'result': 'success', 'hidden': True, 'skipped': False},
        {'type': 'testStart', 'test': {'id': 2, 'name': '(setUpAll)', 'suiteID': 0}},
        {'type': 'testDone', 'testID': 2, 'result': 'success', 'hidden': False, 'skipped': False},
        {'type': 'testStart', 'test': {'id': 3, 'name': 'keeps editing state', 'suiteID': 0}},
        {'type': 'testDone', 'testID': 3, 'result': 'success', 'hidden': False, 'skipped': False},
        {'type': 'done', 'success': True},
    ]


class TargetedEvidenceControls(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='targeted-controls-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.log = self.root / 'tests.jsonl'

    def parse(self, events, requested=None):
        self.log.write_text('\n'.join(json.dumps(e) for e in events) + '\n')
        return runner.parse_cases(self.log, self.root, requested or ['sample_test.dart'])

    def test_complete_exact_suite_excludes_successful_lifecycle_counts(self):
        result, cases = self.parse(stream())
        self.assertTrue(result['valid'])
        self.assertEqual(result['passed'], 1)
        self.assertEqual([c['name'] for c in cases], ['keeps editing state'])

    def test_hidden_failure_or_skip_cannot_be_excluded_from_acceptance(self):
        for update in ({'result': 'failure'}, {'skipped': True}):
            with self.subTest(update=update):
                events = stream()
                events[3].update(update)
                self.assertFalse(self.parse(events)[0]['valid'])

    def test_malformed_suite_records_return_rejected_evidence(self):
        for suite in (None, [], 'suite', {}, {'id': True, 'path': 'sample_test.dart'},
                      {'id': 0, 'path': ''}, {'id': 0, 'path': 9}):
            with self.subTest(suite=suite):
                events = stream()
                events[1]['suite'] = suite
                result, _ = self.parse(events)
                self.assertFalse(result['valid'])
                self.assertIn('Malformed suite registration', result['suite_registration_issues'])

    def test_nonobject_and_truncated_records_return_rejected_evidence(self):
        for record in ('[]', '[{"type":"error"}]', 'null', '{"type":"error",'):
            with self.subTest(record=record):
                lines = [json.dumps(e) for e in stream()]
                lines.insert(-1, record)
                self.log.write_text('\n'.join(lines) + '\n')
                result, _ = runner.parse_cases(self.log, self.root, ['sample_test.dart'])
                self.assertFalse(result['valid'])
                self.assertGreater(result['protocol_errors'], 0)

    def test_invalid_test_suite_identifier_cannot_crash_the_audit(self):
        for identifier in ([], {}, True, None):
            with self.subTest(identifier=identifier):
                events = stream()
                events[6]['test']['suiteID'] = identifier
                self.assertFalse(self.parse(events)[0]['valid'])

    def test_duplicate_suite_registration_is_rejected(self):
        events = stream()
        events.insert(2, dict(events[1]))
        result, _ = self.parse(events)
        self.assertFalse(result['valid'])
        self.assertIn('Duplicate suite identifier', result['suite_registration_issues'])

    def test_wrong_suite_or_missing_requested_suite_is_rejected(self):
        result, _ = self.parse(stream(), ['another_test.dart'])
        self.assertFalse(result['valid'])
        self.assertTrue(result['missing_suites'])
        self.assertTrue(result['unexpected_suites'])

    def test_lifecycle_only_suite_cannot_satisfy_the_plan(self):
        events = stream()
        del events[6:8]
        result, _ = self.parse(events)
        self.assertFalse(result['valid'])
        self.assertEqual(result['passed'], 0)
        self.assertTrue(result['empty_suites'])

    def test_layout_and_missed_tap_prints_reject_otherwise_successful_tests(self):
        messages = ['A RenderFlex overflowed by 12 pixels on the right.',
                    'The derived Offset would not hit test on the specified widget.',
                    'The target does not receive pointer events.']
        for message in messages:
            with self.subTest(message=message):
                events = stream()
                events.insert(-1, {'type': 'print', 'testID': 3, 'message': message})
                result, _ = self.parse(events)
                self.assertFalse(result['valid'])
                self.assertEqual(len(result['layout_or_tap_diagnostics']), 1)

    def test_stderr_diagnostic_scan_distinguishes_regular_tool_output(self):
        self.log.write_text('Font assets loaded.\nA RenderFlex overflowed by 9 pixels.\n')
        self.assertEqual(runner.layout_diagnostics(self.log),
                         [{'line': 2, 'text': 'A RenderFlex overflowed by 9 pixels.'}])

    def test_preflight_failure_leaves_a_failed_receipt(self):
        out = self.root / 'failed-attempt'
        argv = ['run_targeted.py', '--runtime', str(self.root / 'missing-runtime'),
                '--output', str(out), '--concurrency', '3']
        with patch.object(sys, 'argv', argv), redirect_stderr(io.StringIO()):
            code = runner.main()
        receipt = json.loads((out / 'receipt.json').read_text())
        self.assertEqual(code, 1)
        self.assertEqual(receipt['status'], 'failed')
        self.assertFalse(receipt['success'])
        self.assertEqual(receipt['runs'], [])
        self.assertEqual(receipt['concurrency'], 3)
        self.assertIn('FileNotFoundError', receipt['runner_error'])
        self.assertIn('finished_utc', receipt)

    def test_existing_evidence_is_never_overwritten(self):
        out = self.root / 'existing'
        out.mkdir()
        receipt = out / 'receipt.json'
        receipt.write_text('{"status":"preserve this previous attempt"}\n')
        before = receipt.read_bytes()
        argv = ['run_targeted.py', '--runtime', str(self.root / 'runtime'), '--output', str(out)]
        with patch.object(sys, 'argv', argv), self.assertRaises(FileExistsError):
            runner.main()
        self.assertEqual(receipt.read_bytes(), before)

    def test_nonpositive_execution_limits_are_rejected_before_output(self):
        for flag, value in (('--concurrency', '0'), ('--concurrency', '-1'), ('--timeout', '0')):
            with self.subTest(flag=flag, value=value):
                out = self.root / 'unused'
                argv = ['run_targeted.py', '--runtime', str(self.root / 'runtime'),
                        '--output', str(out), flag, value]
                with patch.object(sys, 'argv', argv), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                    runner.main()
                self.assertEqual(error.exception.code, 2)
                self.assertFalse(out.exists())

    @unittest.skipUnless(os.name == 'posix' and Path('/proc').is_dir(), 'POSIX process-group control')
    def test_timeout_stops_children_even_if_they_ignore_sigterm(self):
        marker = self.root / 'child.pid'
        child = ('import os, signal\nfrom pathlib import Path\n'
                 'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                 f'Path({str(marker)!r}).write_text(str(os.getpid()))\n'
                 'while True: signal.pause()\n')
        parent = ('import signal, subprocess, sys\n'
                  f'subprocess.Popen([sys.executable, "-c", {child!r}])\n'
                  'signal.pause()\n')
        pid = None
        try:
            with (self.root / 'child.stdout').open('wb') as stdout, (self.root / 'child.stderr').open('wb') as stderr:
                with self.assertRaises(subprocess.TimeoutExpired):
                    runner.execute_process([sys.executable, '-c', parent], cwd=self.root,
                                           env=os.environ.copy(), stdout=stdout, stderr=stderr, timeout=1)
            self.assertTrue(marker.exists(), 'Child started before timeout')
            pid = int(marker.read_text())
            status = Path(f'/proc/{pid}/status')
            if status.exists():
                state = next(line for line in status.read_text().splitlines() if line.startswith('State:'))
                self.assertIn('Z', state, 'A timed-out descendant must no longer execute')
        finally:
            if pid is not None:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


if __name__ == '__main__':
    unittest.main()
