#!/usr/bin/env python3
"""Exercise acceptance gates using synthetic events; no product tests run."""
from pathlib import Path
import copy
import hashlib
import importlib.util
import json
import sys

sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('qualification_harness', BASE / 'run_qualification.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
CWD = BASE / 'synthetic-workspace'
FOCUSED = 'test/odt_section_integration_test.dart'


def event_stream(path=FOCUSED, names=('preserves section geometry',)):
    result = [{'type': 'suite', 'suite': {'id': 0, 'path': str(CWD / path)}}]
    for test_id, name in enumerate(names, start=1):
        result.extend([
            {'type': 'testStart', 'test': {'id': test_id, 'suiteID': 0, 'name': name}},
            {'type': 'testDone', 'testID': test_id, 'hidden': False, 'skipped': False, 'result': 'success'},
        ])
    result.append({'type': 'done', 'success': True})
    return result


def summary(events, selected=(FOCUSED,)):
    return runner.test_summary('\n'.join(map(json.dumps, events)).encode(), selected, True, CWD)


controls = {}
baseline_events = event_stream()
baseline = summary(baseline_events)
assert baseline['passed'] and baseline['substantive_success_count'] == 1
controls['complete_success_accepted'] = True

mutations = {}
events = copy.deepcopy(baseline_events)
events[-1]['success'] = False
mutations['unsuccessful_terminal_event_rejected'] = events
events = copy.deepcopy(baseline_events)
events[2]['result'] = 'failure'
mutations['failed_assertion_rejected'] = events
events = copy.deepcopy(baseline_events)
events[2]['skipped'] = True
mutations['unexpected_skip_rejected'] = events
mutations['unfinished_case_rejected'] = [e for e in baseline_events if e['type'] != 'testDone']
mutations['empty_suite_rejected'] = [baseline_events[0], baseline_events[-1]]
mutations['duplicate_completion_rejected'] = baseline_events[:-1] + [baseline_events[2], baseline_events[-1]]
mutations['duplicate_start_rejected'] = baseline_events[:-1] + [baseline_events[1], baseline_events[-1]]
mutations['missing_terminal_event_rejected'] = baseline_events[:-1]
events = copy.deepcopy(baseline_events)
events.insert(-1, {'type': 'error', 'error': 'compiler failed'})
mutations['error_event_rejected'] = events
for label, events in mutations.items():
    assert not summary(events)['passed'], label
    controls[label] = True
assert not summary(baseline_events, (FOCUSED, 'test/missing_test.dart'))['passed']
controls['missing_selected_suite_rejected'] = True

pdf_names = tuple(sorted(runner.PRIVATE_CASES)) + ('ordinary PDF assertions',)
pdf = summary(event_stream('test/pdf_file_test.dart', pdf_names), ('test/pdf_file_test.dart',))
assert pdf['passed'] and pdf['raw_success_count'] == 3 and pdf['substantive_success_count'] == 1
assert len(pdf['excluded_success_cases']) == 2
controls['private_fixture_early_returns_excluded_from_substantive_passes'] = True

native = event_stream('test/native_backend_test.dart', (runner.OPTIONAL_GECTOR_CASE,))
native[2]['skipped'] = True
native_summary = summary(native, ('test/native_backend_test.dart',))
assert native_summary['passed'] and native_summary['substantive_success_count'] == 0
assert len(native_summary['allowed_skipped_cases']) == 1
controls['named_optional_native_skip_accounted_separately'] = True

assert runner.compare_repetition(baseline, summary(baseline_events), (FOCUSED,), CWD)['passed']
controls['identical_node_case_identity_and_outcome_accepted'] = True
renamed = event_stream(names=('different case',))
assert not runner.compare_repetition(baseline, summary(renamed), (FOCUSED,), CWD)['passed']
controls['node_case_identity_change_rejected'] = True
failed = copy.deepcopy(baseline_events)
failed[2]['result'] = 'failure'
assert not runner.compare_repetition(baseline, summary(failed), (FOCUSED,), CWD)['passed']
controls['node_case_outcome_change_rejected'] = True

receipt = {
    'scope': 'Synthetic runner-event acceptance controls only; no application suites were executed.',
    'runner_sha256': hashlib.sha256((BASE / 'run_qualification.py').read_bytes()).hexdigest(),
    'verification_script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'controls': controls,
    'passed': all(controls.values()),
}
(BASE / 'harness-controls.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'controls': len(controls), 'passed': receipt['passed'], 'product_tests_run': False}))
