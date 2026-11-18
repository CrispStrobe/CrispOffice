#!/usr/bin/env python3
"""Recheck the retained Dart events with paths relative to their recorded cwd."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys


def record(path):
    value = path.read_bytes()
    return {'bytes': len(value), 'sha256': hashlib.sha256(value).hexdigest()}


folder = Path(sys.argv[1]).resolve()
summary_path = folder / 'summary.json'
original_path = folder / 'summary-before-path-normalization.json'
if original_path.exists():
    raise RuntimeError('Correction has already been recorded.')
original = json.loads(summary_path.read_text())
run = json.loads((folder / 'run.json').read_text())
assert original['status'] == 'failed'
assert original['actual_process_exit_code'] == 0 and not original['timed_out']
assert original['guards']['all_selected_suites_executed'] is False
assert all(value for key, value in original['guards'].items()
           if key != 'all_selected_suites_executed')
assert record(folder / 'run_spelling_at_execution.py')['sha256'] == run['runner_sha256']
events = [json.loads(line) for line in (folder / 'events.jsonl').read_text().splitlines()]
starts = {event['test']['id']: event['test'] for event in events if event.get('type') == 'testStart'}
suites = [event['suite'] for event in events if event.get('type') == 'suite']
finishes = [event for event in events if event.get('type') == 'testDone']
completion = [event for event in events if event.get('type') == 'done']
assert not any(event.get('type') == 'error' for event in events)
assert len(completion) == 1 and completion[0]['success'] is True
assert set(starts) == {event['testID'] for event in finishes}
assert len(starts) == len(finishes)
assert all(event['result'] == 'success' and not event.get('skipped') for event in finishes)
substantive = [event for event in finishes if not event.get('hidden') and not
               starts[event['testID']]['name'].endswith(('(setUpAll)', '(tearDownAll)'))]
assert len(substantive) == original['substantive_test_count']
assert dict(Counter(event['result'] for event in substantive)) == original['substantive_results']
cwd = Path(run['cwd'])
workspace = cwd.parents[1]
observed = sorted(str((cwd / suite['path']).resolve()) for suite in suites)
expected = sorted(str((workspace / path).resolve()) for path in run['selected_files'])
assert observed == expected and len(set(observed)) == len(expected)
assert json.loads((folder / 'source-before.json').read_text()) == json.loads((folder / 'source-after.json').read_text())
assert json.loads((folder / 'runtime-binding-before.json').read_text()) == json.loads((folder / 'runtime-binding-after.json').read_text())
original_path.write_bytes(summary_path.read_bytes())
correction = {
    'corrected_at_utc': datetime.now(timezone.utc).isoformat(),
    'reason': 'Dart JSON reporter returns relative suite paths. Resolve them against the recorded test process cwd, not the receipt runner cwd.',
    'original_runner_process_exit_code': 1,
    'actual_test_process_exit_code': original['actual_process_exit_code'],
    'test_process_rerun': False,
    'source_or_test_edits': False,
    'original_summary': record(original_path),
    'executed_runner': record(folder / 'run_spelling_at_execution.py'),
    'corrected_runner': record(folder.parent / 'run_spelling.py'),
    'correction_script': record(Path(__file__)),
    'observed_reporter_paths': [suite['path'] for suite in suites],
    'recorded_test_cwd': str(cwd),
    'resolved_observed_paths': observed,
    'resolved_expected_paths': expected,
    'all_selected_suites_executed': True,
    'substantive_test_count': len(substantive),
    'all_substantive_tests_passed': True,
    'input_artifacts': {name: record(folder / name) for name in (
        'run.json', 'events.jsonl', 'source-before.json', 'source-after.json',
        'runtime-binding-before.json', 'runtime-binding-after.json'
    )},
}
(folder / 'suite-path-correction.json').write_text(json.dumps(correction, indent=2, sort_keys=True) + '\n')
corrected = {**original, 'status': 'passed',
             'guards': {**original['guards'], 'all_selected_suites_executed': True},
             'derived_summary_correction': 'suite-path-correction.json',
             'original_runner_process_exit_code': 1}
corrected['artifacts'] = {path.name: record(path) for path in sorted(folder.iterdir())
                          if path.is_file() and path.name != 'summary.json'}
summary_path.write_text(json.dumps(corrected, indent=2, sort_keys=True) + '\n')
print(json.dumps({'status': corrected['status'], 'suite_count': len(suites),
                  'substantive_test_count': len(substantive), 'actual_test_exit': 0,
                  'rerun': False, 'guards': corrected['guards']}, indent=2))
