#!/usr/bin/env python3
"""Adversarial evidence tests: incomplete or duplicated runs must not qualify."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from run_local import (
    counts, python_counts, validate_plan, verified_whitespace_exceptions,
)


def events():
    result = [
        {'type': 'start', 'protocolVersion': '0.1.1'},
        {'type': 'suite', 'suite': {'id': 0, 'path': 'test/sample_test.dart'}},
    ]
    for identifier, name, hidden in (
        (1, 'loading test/sample_test.dart', True),
        (2, '(setUpAll)', False),
        (3, 'insertion preserves active fields', False),
        (4, 'undo restores the source', False),
        (5, '(tearDownAll)', False),
    ):
        result += [
            {'type': 'testStart', 'test': {'id': identifier, 'suiteID': 0, 'name': name}},
            {'type': 'testDone', 'testID': identifier, 'result': 'success',
             'skipped': False, 'hidden': hidden},
        ]
    result.append({'type': 'done', 'success': True})
    return result


class ReporterAccountingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='zotero-accounting-')
        self.addCleanup(self.directory.cleanup)
        self.cwd = Path(self.directory.name).resolve()
        self.path = self.cwd / 'events.jsonl'

    def parse(self, value=None, *, requested=None, lines=None):
        if lines is None:
            lines = [json.dumps(event) for event in (events() if value is None else value)]
        self.path.write_text('\n'.join(lines) + '\n')
        return counts(self.path, self.cwd, requested or ['test/sample_test.dart'])

    def rejected(self, value):
        self.assertFalse(self.parse(value)['valid'])

    def test_complete_stream_counts_two_cases_and_excludes_loader_and_fixtures(self):
        result = self.parse()
        self.assertTrue(result['valid'])
        self.assertEqual(result['passed'], 2)
        self.assertEqual(result['failed'], 0)
        self.assertEqual(result['skipped'], 0)
        self.assertEqual(len(result['cases']), 2)
        self.assertEqual(sum(result['excluded_events'].values()), 3)
        self.assertEqual(set(result['per_suite']), {str(self.cwd / 'test/sample_test.dart')})

    def test_progress_prefix_and_file_uri_preserve_reporter_identity(self):
        value = events()
        value[1]['suite']['path'] = (self.cwd / 'test/sample_test.dart').as_uri()
        lines = [json.dumps(event) for event in value]
        lines[0] = 'Running build hooks...Running build hooks...' + lines[0]
        lines.insert(0, 'Compiling application tests...')
        self.assertTrue(self.parse(lines=lines)['valid'])

    def test_suite_relative_paths_use_the_test_process_directory(self):
        result = self.parse()
        self.assertEqual(result['cases'][0]['suite'], str(self.cwd / 'test/sample_test.dart'))

    def test_malformed_and_truncated_events_are_never_discarded(self):
        for line in ('{"type":"testStart","test":bad}', '{"type":"error",',
                     'Running build hooks...{"type":"error",'):
            with self.subTest(line=line):
                lines = [json.dumps(event) for event in events()]
                lines.insert(-1, line)
                self.assertFalse(self.parse(lines=lines)['valid'])

    def test_nonobject_events_cannot_be_accepted(self):
        for value in ([], 5, True, None):
            with self.subTest(value=value):
                stream = events()
                stream.insert(-1, value)
                self.rejected(stream)

    def test_missing_or_duplicate_runner_start_is_rejected(self):
        self.rejected(events()[1:])
        value = events()
        value.insert(1, copy.deepcopy(value[0]))
        self.rejected(value)

    def test_missing_duplicate_and_unsuccessful_terminal_are_rejected(self):
        self.rejected(events()[:-1])
        value = events()
        value.append(copy.deepcopy(value[-1]))
        self.rejected(value)
        value = events()
        value[-1]['success'] = False
        self.rejected(value)
        value[-1]['success'] = 'true'
        self.rejected(value)

    def test_events_after_terminal_are_rejected(self):
        value = events()
        value.insert(2, value.pop())
        self.rejected(value)

    def test_orphan_completion_cannot_add_a_passing_case(self):
        value = events()
        value.insert(-1, {'type': 'testDone', 'testID': 99, 'result': 'success',
                          'skipped': False, 'hidden': False})
        result = self.parse(value)
        self.assertFalse(result['valid'])
        self.assertEqual(result['passed'], 2)

    def test_duplicate_test_start_and_completion_are_rejected(self):
        for kind in ('testStart', 'testDone'):
            with self.subTest(kind=kind):
                value = events()
                duplicate = next(e for e in value if e['type'] == kind)
                value.insert(-1, copy.deepcopy(duplicate))
                self.rejected(value)

    def test_unfinished_visible_case_and_loader_are_rejected(self):
        for identifier in (1, 3):
            with self.subTest(identifier=identifier):
                value = [e for e in events()
                         if not (e['type'] == 'testDone' and e['testID'] == identifier)]
                result = self.parse(value)
                self.assertFalse(result['valid'])
                self.assertIn(identifier, result['unfinished'])

    def test_skipped_or_failed_user_case_prevents_qualification(self):
        for change in ({'skipped': True}, {'result': 'failure'}, {'result': 'error'}):
            with self.subTest(change=change):
                value = events()
                next(e for e in value if e.get('testID') == 3).update(change)
                result = self.parse(value)
                self.assertFalse(result['valid'])
                self.assertEqual(result['passed'], 1)

    def test_error_event_invalidates_otherwise_successful_cases(self):
        value = events()
        value.insert(-1, {'type': 'error', 'testID': 3, 'error': 'asynchronous failure'})
        result = self.parse(value)
        self.assertFalse(result['valid'])
        self.assertEqual(result['errors'], 1)

    def test_hidden_or_fixture_failure_cannot_disappear(self):
        for identifier in (1, 2, 5):
            with self.subTest(identifier=identifier):
                value = events()
                next(e for e in value if e.get('testID') == identifier)['result'] = 'failure'
                self.rejected(value)

    def test_invalid_completion_metadata_is_rejected(self):
        for field, replacement in (('hidden', None), ('skipped', 0), ('result', 'passed')):
            with self.subTest(field=field):
                value = events()
                next(e for e in value if e.get('testID') == 3)[field] = replacement
                self.rejected(value)

    def test_unknown_suite_cannot_provide_a_passing_case(self):
        value = events()
        next(e['test'] for e in value if e['type'] == 'testStart' and e['test']['id'] == 3)['suiteID'] = 99
        self.rejected(value)

    def test_duplicate_suite_id_or_path_is_rejected(self):
        for suite in ({'id': 0, 'path': 'test/other_test.dart'},
                      {'id': 99, 'path': 'test/sample_test.dart'}):
            with self.subTest(suite=suite):
                value = events()
                value.insert(2, {'type': 'suite', 'suite': suite})
                self.rejected(value)

    def test_missing_requested_suite_is_rejected(self):
        result = self.parse(requested=['test/sample_test.dart', 'test/missing_test.dart'])
        self.assertFalse(result['valid'])
        self.assertEqual(result['missing_requested_suites'], [str(self.cwd / 'test/missing_test.dart')])

    def test_unexpected_suite_is_rejected(self):
        value = events()
        value.insert(2, {'type': 'suite', 'suite': {'id': 99, 'path': 'test/unrequested_test.dart'}})
        result = self.parse(value)
        self.assertFalse(result['valid'])
        self.assertEqual(result['unexpected_suites'], [str(self.cwd / 'test/unrequested_test.dart')])

    def test_empty_suite_does_not_qualify_by_finishing_its_loader(self):
        value = [event for event in events()
                 if event.get('testID') not in (3, 4)
                 and event.get('test', {}).get('id') not in (3, 4)]
        result = self.parse(value)
        self.assertFalse(result['valid'])
        self.assertEqual(result['passed'], 0)
        self.assertEqual(result['empty_requested_suites'], [str(self.cwd / 'test/sample_test.dart')])

    def test_malformed_schema_or_unknown_event_is_rejected(self):
        for event in ({'type': 'testStart', 'test': None}, {'type': 'done'},
                      {'type': 'somethingUnexpected'}, {'no_type': True}):
            with self.subTest(event=event):
                value = events()
                value.insert(-1, event)
                self.rejected(value)

    def test_python_support_counts_remain_separate(self):
        self.path.write_text('test_sample ... ok\n\nRan 18 tests in 0.001s\n\nOK\n')
        self.assertEqual(python_counts(self.path), {'python_passed': 18, 'valid': True})

    def test_python_empty_skipped_failed_or_partial_support_run_is_rejected(self):
        for content in ('Ran 0 tests in 0.001s\n\nOK\n',
                        'Ran 18 tests in 0.001s\n\nOK (skipped=1)\n',
                        'Ran 18 tests in 0.001s\n\nFAILED (failures=1)\n',
                        'test_example ... ok\n',
                        'Ran 1 test in 0.001s\nRan 1 test in 0.001s\nOK\n'):
            with self.subTest(content=content):
                self.path.write_text(content)
                self.assertFalse(python_counts(self.path)['valid'])


class FrozenPlanTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='zotero-plan-')
        self.addCleanup(self.directory.cleanup)
        self.repo = Path(self.directory.name).resolve()
        self.tracked = {'pkg/test/a_test.dart', 'pkg/lib/a.dart', 'tools/support_test.py'}
        for name in self.tracked:
            source = self.repo / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text('fixture\n')
        self.plan = {
            'test_gates': {'example': {'package': 'pkg', 'runner': 'dart',
                                      'concurrency': 1, 'tests': ['test/a_test.dart']}},
            'analysis_targets': ['pkg/lib/a.dart'],
            'support_tests': {'support': 'tools/support_test.py'},
        }

    def test_plan_binds_each_requested_suite_and_support_input_once(self):
        requested, inputs = validate_plan(self.plan, self.repo, self.tracked)
        self.assertEqual(requested, ['pkg/test/a_test.dart'])
        self.assertEqual(inputs, self.tracked)

    def test_duplicate_suite_within_or_between_gates_is_rejected(self):
        self.plan['test_gates']['example']['tests'].append('test/../test/a_test.dart')
        with self.assertRaises(ValueError):
            validate_plan(self.plan, self.repo, self.tracked)
        self.plan['test_gates']['example']['tests'].pop()
        self.plan['test_gates']['second'] = copy.deepcopy(self.plan['test_gates']['example'])
        with self.assertRaises(ValueError):
            validate_plan(self.plan, self.repo, self.tracked)

    def test_untracked_missing_or_outside_inputs_are_rejected(self):
        for name in ('pkg/lib/missing.dart', '../outside.dart', str(self.repo / 'pkg/lib/a.dart')):
            with self.subTest(name=name):
                self.plan['analysis_targets'] = [name]
                with self.assertRaises(ValueError):
                    validate_plan(self.plan, self.repo, self.tracked)
        self.plan['analysis_targets'] = ['pkg/lib/a.dart']
        with self.assertRaises(ValueError):
            validate_plan(self.plan, self.repo, self.tracked - {'pkg/lib/a.dart'})

    def test_empty_gate_invalid_runner_or_duplicate_name_is_rejected(self):
        for change in ({'tests': []}, {'runner': 'custom'}, {'concurrency': 0}):
            with self.subTest(change=change):
                plan = copy.deepcopy(self.plan)
                plan['test_gates']['example'].update(change)
                with self.assertRaises(ValueError):
                    validate_plan(plan, self.repo, self.tracked)
        self.plan['support_tests'] = {'example': 'tools/support_test.py'}
        with self.assertRaises(ValueError):
            validate_plan(self.plan, self.repo, self.tracked)


class VerbatimWhitespaceTests(unittest.TestCase):
    def setUp(self):
        self.entry = {
            'path': 'docs/unmaterialized/original-notice.txt',
            'git_blob': 'a' * 40,
            'reason': 'Preserve the distributed notice byte-for-byte.',
        }
        self.tracked = {self.entry['path']}

    def test_pinned_tracked_blob_needs_no_materialized_file(self):
        lookups = []

        def head_blob(path):
            lookups.append(path)
            return 'a' * 40

        self.assertFalse(Path(self.entry['path']).exists())
        result = verified_whitespace_exceptions([self.entry], self.tracked, head_blob)
        self.assertEqual(result, [self.entry])
        self.assertEqual(lookups, [self.entry['path']])

    def test_changed_blob_cannot_reuse_the_whitespace_exception(self):
        with self.assertRaisesRegex(ValueError, 'Excepted blob changed'):
            verified_whitespace_exceptions([self.entry], self.tracked, lambda _: 'b' * 40)

    def test_duplicate_exception_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate whitespace exception'):
            verified_whitespace_exceptions(
                [self.entry, dict(self.entry)], self.tracked, lambda _: 'a' * 40)

    def test_absolute_traversal_backslash_and_noncanonical_paths_are_rejected(self):
        for path in ('../outside.txt', '/absolute.txt', 'docs/./notice.txt',
                     'docs/../notice.txt', 'docs//notice.txt', 'docs\\notice.txt', ''):
            with self.subTest(path=path):
                entry = {**self.entry, 'path': path}
                # Even an alleged tracked name cannot bypass path validation.
                with self.assertRaisesRegex(ValueError, 'canonical relative path'):
                    verified_whitespace_exceptions([entry], {path}, lambda _: 'a' * 40)

    def test_untracked_unpinned_or_unexplained_exception_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'not a tracked file'):
            verified_whitespace_exceptions([self.entry], set(), lambda _: 'a' * 40)
        for change in ({'git_blob': 'HEAD'}, {'git_blob': None}, {'reason': ''}, {'reason': None}):
            with self.subTest(change=change):
                with self.assertRaises(ValueError):
                    verified_whitespace_exceptions(
                        [{**self.entry, **change}], self.tracked, lambda _: 'a' * 40)


if __name__ == '__main__':
    unittest.main()
