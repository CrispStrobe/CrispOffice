#!/usr/bin/env python3
"""Verify exact accepted Word case identities and retained baseline inputs."""
import argparse
import collections
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', type=Path, required=True)
parser.add_argument('--final', type=Path, required=True)
parser.add_argument('--fixture-audit', type=Path, required=True)
args = parser.parse_args()
baseline, final = args.baseline.resolve(), args.final.resolve()
base_report = json.loads((baseline / 'qualification.json').read_text())
final_report = json.loads((final / 'qualification.json').read_text())
assert base_report['success'] and final_report['success']
assert base_report['source_unchanged'] and final_report['source_unchanged']
fixture_audit = json.loads(args.fixture_audit.read_text())
assert fixture_audit['baseline_source'] == base_report['source_head']
assert fixture_audit['checked_source'] == final_report['source_head']
assert fixture_audit['retained_test_files'] == 62


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def original_cases(path):
    events = []
    for line in path.read_text().splitlines():
        if line.startswith('{'):
            events.append(json.loads(line))
    assert events[-1].get('type') == 'done' and events[-1].get('success') is True
    assert not any(event.get('type') == 'error' for event in events)
    suites = {event['suite']['id']: event['suite']['path'] for event in events if event.get('type') == 'suite'}
    starts = {event['test']['id']: event['test'] for event in events if event.get('type') == 'testStart'}
    occurrences = collections.Counter()
    rows = []
    for event in events:
        if event.get('type') != 'testDone' or event.get('hidden'):
            continue
        assert event['result'] == 'success' and not event.get('skipped')
        test = starts[event['testID']]
        file = suites[test['suiteID']]
        if '/test/' in file:
            file = 'test/' + file.rsplit('/test/', 1)[1]
        identity = (file, test['name'])
        occurrences[identity] += 1
        rows.append({'file': file, 'name': test['name'], 'occurrence': occurrences[identity]})
    return rows


base_cases = original_cases(baseline / 'macro-vba-tests.log')
final_cases = original_cases(final / 'measurement-tests.log')
assert len(base_cases) == base_report['tests']['passed']
assert len(final_cases) == final_report['tests']['passed']
expected_final_cases = json.loads((final / 'test-cases.json').read_text())
assert final_cases == [{key: row[key] for key in ['file', 'name', 'occurrence']} for row in expected_final_cases]
superseded = {
    'test/office_vba_word_measurements_test.dart': 'test/office_vba_word_named_measurements_test.dart',
    'test/office_vba_word_measurements_integration_test.dart': 'test/office_vba_word_named_measurements_integration_test.dart',
}
removed = [row for row in base_cases if row['file'] in superseded]
retained = [row for row in base_cases if row['file'] not in superseded]
removed_counts = dict(collections.Counter(row['file'] for row in removed))
assert removed_counts == {
    'test/office_vba_word_measurements_test.dart': 147,
    'test/office_vba_word_measurements_integration_test.dart': 10,
}
final_ids = {(row['file'], row['name'], row['occurrence']) for row in final_cases}
for row in removed:
    assert (superseded[row['file']], row['name'], row['occurrence']) in final_ids, row
accepted = retained + final_cases
accepted_ids = {(row['file'], row['name'], row['occurrence']) for row in accepted}
assert len(accepted_ids) == len(accepted)
retained_files = sorted({row['file'] for row in retained})
assert len(retained_files) == 62
base_manifest = json.loads((baseline / 'source-before.json').read_text())
final_before = json.loads((final / 'source-before.json').read_text())
final_manifest = json.loads((final / 'source-after.json').read_text())
assert final_before == final_manifest
for file in retained_files:
    path = 'packages/quds_office_engine/' + file
    assert base_manifest[path] == final_manifest[path], file
common = set(base_manifest) & set(final_manifest)
changed = {path: {'baseline': base_manifest[path], 'final': final_manifest[path]}
           for path in sorted(common) if base_manifest[path] != final_manifest[path]}
allowed_changes = {
    'packages/quds_office_engine/example/macros/word_measurements.bas',
    'packages/quds_office_engine/test/office_vba_word_measurements_test.dart',
    'packages/quds_office_engine/test/office_vba_word_measurements_integration_test.dart',
    'packages/quds_office_engine/tool/macros/web_vba_word_measurements_smoke.dart',
}
assert set(changed) <= allowed_changes, changed
assert not (set(base_manifest) - set(final_manifest))
production = 'packages/quds_office_engine/lib/src/automation/office_vba_language.dart'
assert base_manifest[production] == final_manifest[production]
per_file = dict(sorted(collections.Counter(row['file'] for row in accepted).items()))
result = {
    'schema': 'quds-word-measurement-accepted-union/v1',
    'baseline_source': base_report['source_head'],
    'final_source': final_report['source_head'],
    'final_tree': final_report['source_tree'],
    'baseline_passed_cases': len(base_cases),
    'superseded_baseline_cases': len(removed),
    'superseded_baseline_per_file': removed_counts,
    'superseded_case_identities_retained_in_named_suites': True,
    'retained_baseline_cases': len(retained),
    'retained_baseline_suite_count': len(retained_files),
    'final_focused_cases': len(final_cases),
    'final_focused_suite_count': final_report['tests']['file_count'],
    'accepted_case_count': len(accepted),
    'accepted_suite_count': len(per_file),
    'accepted_per_file': per_file,
    'additional_node_cases': final_report['bulk_intake_node'],
    'node_cases_are_platform_rechecks_not_additional_logical_cases': True,
    'production_sha256': final_manifest[production],
    'shared_source_inputs': len(common),
    'unchanged_shared_source_inputs': len(common) - len(changed),
    'changed_shared_source_inputs': changed,
    'additional_final_manifest_paths': sorted(set(final_manifest) - set(base_manifest)),
    'fixture_reference_audit': {
        'file': str(args.fixture_audit), 'sha256': digest(args.fixture_audit),
        'finding': fixture_audit['finding'],
    },
    'evidence_hashes': {
        'baseline_qualification': digest(baseline / 'qualification.json'),
        'baseline_raw_reporter': digest(baseline / 'macro-vba-tests.log'),
        'final_qualification': digest(final / 'qualification.json'),
        'final_raw_reporter': digest(final / 'measurement-tests.log'),
    },
    'excluded_attempts': ['prior 378-case supplementary checkpoint',
        'prior six-suite fixture-error attempt', 'interrupted seven-suite loading attempt'],
    'success': True,
}
(final / 'accepted-union.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
(final / 'accepted-test-cases.json').write_text(json.dumps(accepted, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['success', 'accepted_case_count',
    'accepted_suite_count', 'retained_baseline_cases', 'final_focused_cases']}))
