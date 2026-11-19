#!/usr/bin/env python3
"""Acceptance tests for the local Mail store runner's Dart event accounting."""
from __future__ import annotations

from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_store import direct_launcher, execute, main, test_summary


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

    def test_build_and_link_progress_can_share_a_line_with_an_event(self):
        lines = event_lines(dart_events())
        lines[0] = '  Running build hooks... Running link hooks...  ' + lines[0]
        lines.insert(0, '  Running build hooks... Running link hooks...  ')
        lines.insert(1, '  ')
        self.assertTrue(self.summary(lines)['valid'])

    def test_missing_opening_brace_is_rejected_with_or_without_hook_progress(self):
        for prefix in ('', 'Running build hooks...'):
            with self.subTest(prefix=prefix):
                lines = event_lines(dart_events())
                lines.insert(-1, prefix + '"type":"error","testID":3}')
                self.assertFalse(self.summary(lines)['valid'])

    def test_non_object_json_records_are_rejected(self):
        for record in ('[]', '["type", "error"]', '[{"type":"error"}]',
                       'null', 'true', '42', '"truncated event"'):
            with self.subTest(record=record):
                lines = event_lines(dart_events())
                lines.insert(-1, record)
                summary = self.summary(lines)
                self.assertFalse(summary['valid'])
                self.assertGreater(summary['protocol_errors'], 0)

    def test_unrecognized_prefix_cannot_hide_event_data(self):
        lines = event_lines(dart_events())
        lines[0] = 'unexpected output before event ' + lines[0]
        self.assertFalse(self.summary(lines)['valid'])

    def test_unstructured_output_after_terminal_prevents_qualification(self):
        lines = event_lines(dart_events())
        lines.append('Unhandled exception: failed to flush test output')
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

    def test_malformed_completion_result_is_rejected_without_raising(self):
        for result in [None, 1, ['failure'], {'result': 'failure'}]:
            with self.subTest(result=result):
                events = dart_events()
                events[4]['result'] = result
                summary = self.summary(event_lines(events))
                self.assertFalse(summary['valid'])
                self.assertEqual(summary['protocol_errors'], 1)

    def test_incomplete_loader_is_rejected(self):
        self.assert_rejected([
            event for event in dart_events()
            if not (event['type'] == 'testDone' and event['testID'] == 1)
        ])

    def test_hidden_and_loading_failures_cannot_hide_behind_terminal_success(self):
        for name, hidden in [
            ('loading sample_test.dart', True),
            ('loading sample_test.dart', False),
            ('(setUpAll)', True),
            ('(tearDownAll)', True),
        ]:
            for result in ['failure', 'error']:
                with self.subTest(name=name, hidden=hidden, result=result):
                    events = dart_events()
                    events[2]['test']['name'] = name
                    events[4].update(result=result, hidden=hidden)
                    summary = self.summary(event_lines(events))
                    self.assertFalse(summary['valid'])
                    self.assertEqual(summary['passed'], 2)
                    self.assertEqual(summary['failed'], 0)
                    self.assertEqual(summary['all_failed'], 1)
                    self.assertEqual(len(summary['cases']), 2)

    def test_hidden_and_loading_skips_prevent_qualification(self):
        for name, hidden in [
            ('loading sample_test.dart', True),
            ('loading sample_test.dart', False),
            ('(setUpAll)', True),
            ('(tearDownAll)', True),
        ]:
            with self.subTest(name=name, hidden=hidden):
                events = dart_events()
                events[2]['test']['name'] = name
                events[4].update(skipped=True, hidden=hidden)
                summary = self.summary(event_lines(events))
                self.assertFalse(summary['valid'])
                self.assertEqual(summary['passed'], 2)
                self.assertEqual(summary['skipped'], 0)
                self.assertEqual(summary['all_skipped'], 1)
                self.assertEqual(len(summary['cases']), 2)

    def test_incomplete_lifecycle_events_prevent_qualification(self):
        for name in ['loading sample_test.dart', '(setUpAll)', '(tearDownAll)']:
            with self.subTest(name=name):
                events = dart_events()
                events[2]['test']['name'] = name
                events = [event for event in events
                          if not (event['type'] == 'testDone' and event['testID'] == 1)]
                summary = self.summary(event_lines(events))
                self.assertFalse(summary['valid'])
                self.assertEqual(summary['passed'], 2)
                self.assertEqual(summary['incomplete'], 1)

    def test_successful_hidden_and_loading_events_do_not_inflate_passes(self):
        for name, hidden in [
            ('loading sample_test.dart', True),
            ('loading sample_test.dart', False),
            ('(setUpAll)', True),
            ('(tearDownAll)', True),
        ]:
            with self.subTest(name=name, hidden=hidden):
                events = dart_events()
                events[2]['test']['name'] = name
                events[4]['hidden'] = hidden
                summary = self.summary(event_lines(events))
                self.assertTrue(summary['valid'])
                self.assertEqual(summary['passed'], 2)
                self.assertEqual(summary['all_failed'], 0)
                self.assertEqual(summary['all_skipped'], 0)
                self.assertEqual(len(summary['cases']), 2)

    def test_skipped_case_is_counted_and_prevents_qualification(self):
        events = dart_events()
        events[7]['skipped'] = True
        summary = self.summary(event_lines(events))
        self.assertFalse(summary['valid'])
        self.assertEqual(summary['passed'], 1)
        self.assertEqual(summary['skipped'], 1)

    def test_failed_loader_prevents_qualification_without_inflating_case_counts(self):
        for result in ('failure', 'error'):
            with self.subTest(result=result):
                events = dart_events()
                events[4]['result'] = result
                summary = self.summary(event_lines(events))
                self.assertFalse(summary['valid'])
                self.assertEqual(summary['passed'], 2)
                self.assertEqual(summary['failed'], 0)
                self.assertEqual(summary['excluded_failed'], 1)

    def test_skipped_loader_prevents_qualification_without_inflating_case_counts(self):
        events = dart_events()
        events[4]['skipped'] = True
        summary = self.summary(event_lines(events))
        self.assertFalse(summary['valid'])
        self.assertEqual(summary['passed'], 2)
        self.assertEqual(summary['skipped'], 0)
        self.assertEqual(summary['excluded_skipped'], 1)

    def test_hidden_non_loader_failure_also_prevents_qualification(self):
        events = dart_events()
        events[2]['test']['name'] = '(tearDownAll)'
        events[4]['result'] = 'failure'
        summary = self.summary(event_lines(events))
        self.assertFalse(summary['valid'])
        self.assertEqual(summary['excluded_failed'], 1)

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


class TestStoreRunnerExitAccounting(unittest.TestCase):
    """The aggregate gate requires both a sound event stream and exit zero."""

    def run_gate(self, *, cohort_exit: int = 0,
                 cohort_events: list[str] | None = None,
                 timed_out: bool = False,
                 direct_shadow: bool = False) -> tuple[int, dict[str, object]]:
        with tempfile.TemporaryDirectory(prefix='mail-store-runner-') as directory:
            root = Path(directory)
            sdk = root / 'flutter'
            dart = sdk / 'bin/cache/dart-sdk/bin/dart'
            dart.parent.mkdir(parents=True)
            dart.touch()
            output = root / 'qualification'
            shadow = root / 'new-native-mapping.yaml'

            def run(command, *, cwd, env, stdout, timeout):
                code = 0
                if '--reporter' in command:
                    lines = event_lines(dart_events())
                    if cwd.name == 'quds_mail_core' and 'vm' in command:
                        code = cohort_exit
                        if direct_shadow:
                            shadow.write_text('{}')
                        if cohort_events is not None:
                            lines = cohort_events
                    stdout.write(('\n'.join(lines) + '\n').encode('utf-8'))
                    if timed_out and cwd.name == 'quds_mail_core' and 'vm' in command:
                        raise subprocess.TimeoutExpired(command, timeout)
                return code

            with (patch.object(sys, 'argv', ['check_store.py', '--flutter-sdk', str(sdk),
                                            '--output', str(output)] +
                               (['--direct-tests'] if direct_shadow else [])),
                  patch('check_store.hashes', return_value={'fixture.dart': 'unchanged'}),
                  patch('check_store.shutil.which', return_value='/fixture/node'),
                  patch('check_store.subprocess.check_output', return_value='fixture-head\n'),
                  patch('check_store.direct_launcher', return_value=(root / 'package_config.json',
                                                                     root / 'test.dart', {str(shadow): None})),
                  patch('check_store.execute', side_effect=run),
                  redirect_stdout(io.StringIO())):
                code = main()
            return code, json.loads((output / 'receipt.json').read_text())

    def test_successful_events_and_exit_zero_allow_the_aggregate_gate(self):
        code, receipt = self.run_gate()
        self.assertEqual(code, 0)
        self.assertEqual(receipt['status'], 'PASS')
        self.assertTrue(receipt['source_unchanged'])

    def test_successful_events_cannot_override_nonzero_or_signal_exit(self):
        for process_exit in (1, -9):
            with self.subTest(process_exit=process_exit):
                code, receipt = self.run_gate(cohort_exit=process_exit)
                self.assertNotEqual(code, 0)
                self.assertEqual(receipt['status'], 'FAIL')
                cohort = next(item for item in receipt['checks'] if item['name'] == 'core-vm')
                self.assertEqual(cohort['exit_code'], process_exit)
                self.assertTrue(cohort['tests']['valid'])
                self.assertEqual(cohort['status'], 'FAIL')

    def test_exit_zero_cannot_override_invalid_events(self):
        code, receipt = self.run_gate(cohort_events=event_lines(dart_events()[:-1]))
        self.assertNotEqual(code, 0)
        self.assertEqual(receipt['status'], 'FAIL')
        cohort = next(item for item in receipt['checks'] if item['name'] == 'core-vm')
        self.assertEqual(cohort['exit_code'], 0)
        self.assertFalse(cohort['tests']['valid'])
        self.assertEqual(cohort['status'], 'FAIL')


    def test_timeout_cannot_accept_even_a_complete_success_stream(self):
        code, receipt = self.run_gate(timed_out=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(receipt['status'], 'FAIL')
        cohort = next(item for item in receipt['checks'] if item['name'] == 'core-vm')
        self.assertEqual(cohort['exit_code'], 124)
        self.assertTrue(cohort['timed_out'])
        self.assertTrue(cohort['tests']['valid'])
        self.assertEqual(cohort['status'], 'FAIL')

    def test_new_native_mapping_invalidates_a_passing_direct_run(self):
        code, receipt = self.run_gate(direct_shadow=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(receipt['status'], 'FAIL')
        self.assertTrue(receipt['runtime_inputs_changed'])
        self.assertTrue(all(check['status'] == 'PASS' for check in receipt['checks']))


class TestDirectLauncher(unittest.TestCase):
    def fixture(self, root: Path) -> tuple[Path, Path, Path]:
        config = root / '.dart_tool/package_config.json'
        config.parent.mkdir()
        entry = root / 'cache/test-1.31.1/bin/test.dart'
        entry.parent.mkdir(parents=True)
        entry.write_text('// resolved test entry\n')
        config.write_text(json.dumps({'packages': [
            {'name': 'test', 'rootUri': entry.parent.parent.as_uri() + '/'}]}))
        asset = root / 'libsqlite3.so'
        asset.write_bytes(b'fixture native asset')
        manifest = root / '.dart_tool/native_assets.yaml'
        manifest.write_text('# generated mapping\n' + json.dumps({'native-assets': {
            'linux_x64': {'package:sqlite3/src/ffi/libsqlite3.g.dart': ['absolute', str(asset)]}}}))
        return config, entry, manifest

    def test_resolves_local_entry_and_binds_native_mapping_and_asset(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, entry, manifest = self.fixture(root)
            actual_config, actual_entry, inputs = direct_launcher(root)
            self.assertEqual(actual_config, config)
            self.assertEqual(actual_entry, entry)
            self.assertEqual({name for name, value in inputs.items() if value is not None},
                             {str(config), str(entry), str(manifest), str(root / 'libsqlite3.so')})
            self.assertIn(str(root / 'packages/quds_mail_store/.dart_tool/native_assets.yaml'), inputs)

    def test_rejects_ambiguous_or_nonlocal_test_package(self):
        for packages in ([], [{'name': 'test', 'rootUri': 'https://example.test/'}],
                         [{'name': 'test', 'rootUri': 'file://remote/test/'}],
                         [{'name': 'test', 'rootUri': 'file:///test/'}] * 2):
            with self.subTest(packages=packages), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                config, _, _ = self.fixture(root)
                config.write_text(json.dumps({'packages': packages}))
                with self.assertRaises(ValueError):
                    direct_launcher(root)

    def test_rejects_absent_sqlite_mapping_and_missing_or_relative_assets(self):
        for assets in ({}, {'unrelated': ['absolute', '/missing']},
                       {'package:sqlite3/src/ffi/libsqlite3.g.dart': ['relative', 'libsqlite3.so']},
                       {'package:sqlite3/src/ffi/libsqlite3.g.dart': ['absolute', '/missing']}):
            with self.subTest(assets=assets), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                _, _, manifest = self.fixture(root)
                manifest.write_text(json.dumps({'native-assets': {'linux_x64': assets}}))
                with self.assertRaises(ValueError):
                    direct_launcher(root)

    def test_rejects_package_local_native_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            shadow = root / 'packages/quds_mail_store/.dart_tool/native_assets.yaml'
            shadow.parent.mkdir(parents=True)
            shadow.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'shadows'):
                direct_launcher(root)


class TestCommandBounds(unittest.TestCase):
    def test_process_timeout_preserves_output_and_reaps_launcher(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / 'output.log'
            with log.open('wb') as stream, self.assertRaises(subprocess.TimeoutExpired):
                execute([sys.executable, '-u', '-c',
                         'import time; print("started", flush=True); time.sleep(20)'],
                        cwd=root, env=dict(os.environ), stdout=stream, timeout=0.3)
            self.assertEqual(log.read_text().strip(), 'started')

    @unittest.skipUnless(os.name == 'posix', 'Process groups are a POSIX guarantee')
    def test_timeout_terminates_a_spawned_child_even_if_parent_exits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / 'output.log'
            child = 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(20)'
            parent = ('import subprocess,sys,time; '
                      f'p=subprocess.Popen([sys.executable,"-c",{child!r}]); '
                      'print(p.pid,flush=True); time.sleep(20)')
            with log.open('wb') as stream, self.assertRaises(subprocess.TimeoutExpired):
                execute([sys.executable, '-u', '-c', parent], cwd=root,
                        env=dict(os.environ), stdout=stream, timeout=0.3)
            pid = int(log.read_text().strip())
            # A killed orphan may briefly remain a zombie until the host reaps it.
            state = Path(f'/proc/{pid}/stat')
            deadline = time.monotonic() + 2
            while True:
                try:
                    process_state = state.read_text().split()[2]
                except (FileNotFoundError, ProcessLookupError):
                    # Reaping may remove the process before or during read.
                    break
                if process_state == 'Z':
                    break
                if time.monotonic() >= deadline:
                    self.fail('Timed-out launcher left a running child process')
                time.sleep(0.01)


if __name__ == '__main__':
    unittest.main()
