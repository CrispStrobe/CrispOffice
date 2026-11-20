#!/usr/bin/env python3
"""Recount saved tests and bind their recorded inputs to immutable Git blobs.

This script runs no application tests and does not re-observe the original SDK,
dependency cache or before/after execution. It verifies their saved inventories
for internal consistency only. Candidate input drift is reported separately.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlparse


def record(data):
    return {
        'bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
        'git_blob_sha1': hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest(),
    }


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def read(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)


def git(repo, *args, **kwargs):
    return subprocess.check_output(['git', *args], cwd=repo, **kwargs)


def tree(repo, commit):
    result = {}
    for row in git(repo, 'ls-tree', '-rz', commit).split(b'\0'):
        if row:
            metadata, path = row.split(b'\t', 1)
            mode, kind, oid = metadata.decode().split()
            if kind == 'blob':
                result[path.decode()] = oid
    return result


def source_records(repo, oids):
    records = {}
    objects = sorted(set(oids))
    for start in range(0, len(objects), 128):
        batch = objects[start:start + 128]
        raw = git(repo, 'cat-file', '--batch', input=('\n'.join(batch) + '\n').encode())
        offset = 0
        for oid in batch:
            end = raw.index(b'\n', offset)
            found, kind, size = raw[offset:end].decode().split()
            size = int(size)
            assert found == oid and kind == 'blob'
            data = raw[end + 1:end + size + 1]
            assert len(data) == size and raw[end + size + 1] == 10
            records[oid] = record(data)
            assert records[oid]['git_blob_sha1'] == oid
            offset = end + size + 2
        assert offset == len(raw)
    return records


def recount(path, old_repo, cwd):
    events = []
    for line in gzip.decompress(path.read_bytes()).decode('utf-8').split('\n'):
        if not line.strip(' \t\r'):
            continue
        value = json.loads(line)
        if isinstance(value, dict) and isinstance(value.get('type'), str):
            events.append(value)
        else:
            assert isinstance(value, list) and all(isinstance(row, dict) and 'event' in row for row in value)
    starts = [row['test'] for row in events if row['type'] == 'testStart']
    suites = [row['suite'] for row in events if row['type'] == 'suite']
    ends = [row for row in events if row['type'] == 'testDone']
    start_map = {row['id']: row for row in starts}
    suite_map = {row['id']: row for row in suites}
    assert len(start_map) == len(starts) and len(suite_map) == len(suites)
    counts = Counter(row['testID'] for row in ends)
    assert set(counts) == set(start_map) and set(counts.values()) == {1}
    final = [row for row in events if row['type'] == 'done']
    assert len(final) == 1 and final[0].get('success') is True
    assert not any(row['type'] == 'error' for row in events)
    assert not any(row['type'] == 'print' and re.search(
        r'A Render\w+ overflowed|would not hit test on the specified widget|does not receive pointer events',
        row.get('message', '')) for row in events)

    def suite_path(value):
        path = Path(unquote(urlparse(value).path)) if value.startswith('file:') else Path(value)
        path = path if path.is_absolute() else Path(cwd) / path
        return str(path.relative_to(old_repo))

    identities = []
    excluded = 0
    per_suite = Counter()
    for row in ends:
        case = start_map[row['testID']]
        assert row.get('result') == 'success'
        assert not row.get('skipped') and not case.get('metadata', {}).get('skip')
        is_lifecycle = row.get('hidden', False) or (case.get('url') is None and (
            case['name'].startswith('loading ') or case['name'].endswith(('(setUpAll)', '(tearDownAll)'))))
        suite = suite_path(suite_map[case['suiteID']]['path'])
        if is_lifecycle:
            excluded += 1
        else:
            identities.append((suite, case['name']))
            per_suite[suite] += 1
    assert len(identities) == len(set(identities))
    return {'passed': len(identities), 'files': len(suites), 'excluded_lifecycle_events': excluded,
            'suite_paths': sorted(suite_path(row['path']) for row in suites),
            'per_suite': dict(sorted(per_suite.items()))}, identities


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.candidate = git(args.repo, 'rev-parse', '--verify', args.candidate).decode().strip()
    summary = read(args.evidence / 'summary.json')
    candidates = tree(args.repo, args.candidate)
    cohorts = summary['cohorts'] + summary['additional_cohorts']
    sources = {row['source_head']: tree(args.repo, row['source_head']) for row in cohorts}
    inventories = {row['name']: read(args.evidence / Path(row['receipt']).parent / 'inputs.json.gz') for row in cohorts}
    objects = set()
    for row in cohorts:
        objects.update(sources[row['source_head']][p] for p in inventories[row['name']]['before']['source'])
    records = source_records(args.repo, objects)
    results = []
    all_cases = []
    selected = []
    candidate_drift = {}
    runner_record = record((args.evidence / 'run_validation.py').read_bytes())
    for row in cohorts:
        path = args.evidence / row['receipt']
        receipt = read(path)
        assert record(path.read_bytes())['sha256'] == row['receipt_sha256']
        assert receipt['status'] == 'passed' and receipt['exit_code'] == 0 and not receipt['timed_out']
        assert all(receipt['guards'].values())
        assert receipt['source_head_at_start'] == receipt['source_head_at_finish'] == row['source_head']
        assert all(receipt['validation_runner'][key] == runner_record[key] for key in runner_record)
        for name, expected in receipt['artifacts'].items():
            assert record((path.parent / name).read_bytes()) == expected, (row['name'], name)
        assert read(path.parent / 'input-check.json') == receipt['fingerprints']
        old_repo = Path(receipt['cwd'])
        for _ in Path(receipt['package']).parts:
            old_repo = old_repo.parent
        counted, cases = recount(path.parent / 'events.jsonl.gz', old_repo, receipt['cwd'])
        assert counted['passed'] == row['passed'] == receipt['tests']['passed']
        assert counted['files'] == row['files'] == receipt['tests']['suite_count']
        assert counted['suite_paths'] == sorted(receipt['selected_repository_paths'])
        for saved in receipt['tests']['suites']:
            relative = str(Path(saved['path']).relative_to(old_repo))
            assert counted['per_suite'][relative] == saved['passed'] and saved['failed'] == saved['skipped'] == 0
        inventory = inventories[row['name']]['before']
        for area, value in inventory.items():
            assert digest(value) == receipt['fingerprints']['before_sha256'][area] == receipt['fingerprints']['after_sha256'][area]
            assert receipt['fingerprints']['changed_paths'][area] == []
        for package in inventory['dependencies'].values():
            assert len(package['files']) == package['file_count']
            assert digest(package['files']) == package['inventory_sha256']
        for name, expected in inventory['source'].items():
            oid = sources[row['source_head']][name]
            assert records[oid] == expected, (row['name'], name)
            if candidates.get(name) != oid:
                candidate_drift[name] = {'qualified_blob': oid, 'candidate_blob': candidates.get(name)}
        counted.update(name=row['name'], source_commit=row['source_head'], source_inputs=len(inventory['source']),
                       receipt_sha256=row['receipt_sha256'], artifacts_verified=len(receipt['artifacts']))
        results.append(counted)
        all_cases.extend(cases)
        selected.extend(counted['suite_paths'])
    assert len(all_cases) == len(set(all_cases)) == summary['distinct_application_tests_passed']
    assert len(selected) == len(set(selected)) == summary['distinct_test_files']

    static = read(args.evidence / 'post-main/static/receipt.json')
    assert static['accepted'] and static['inputs_identical'] and static['before'] == static['after']
    assert len(static['paths']) == len(set(static['paths'])) == summary['changed_dart_targets']
    assert set(static['before']) == set(static['paths'])
    static_tree = sources[static['head']]
    for name in static['paths']:
        assert static['before'][name] == records[static_tree[name]]['sha256']
    assert set(static['checks']) == {'format', 'analysis'}
    assert all(check['exit_code'] == 0 for check in static['checks'].values())
    post_audit = read(args.evidence / 'post-main/audit.json')
    for name, expected in post_audit['post_main_static']['artifacts'].items():
        assert record((args.evidence / 'post-main/static' / name).read_bytes()) == expected
    assert record((args.evidence / 'supplemental/evidence.tar.gz').read_bytes())['sha256'] == summary['supplemental_archive_sha256']

    final = {
        'status': 'saved_evidence_verified',
        'audited_at_utc': datetime.now(timezone.utc).isoformat(),
        'candidate_commit': args.candidate,
        'evidence_summary_sha256': record((args.evidence / 'summary.json').read_bytes())['sha256'],
        'verifier_sha256': record(Path(__file__).read_bytes())['sha256'],
        'distinct_passed_application_cases': len(all_cases),
        'distinct_test_files': len(selected),
        'static_targets_verified_against_saved_source': len(static['paths']),
        'qualified_source_blob_objects_rehashed': len(records),
        'distinct_recorded_source_input_paths': len(set().union(*(set(inv['before']['source']) for inv in inventories.values()))),
        'static_log_artifacts_match_recorded_audit': True,
        'supplemental_archive_matches_recorded_sha256': True,
        'cohorts': results,
        'candidate_preserves_all_qualified_source_inputs': not candidate_drift,
        'candidate_source_differences': candidate_drift,
        'limits': [
            'No application tests, analysis or format commands were rerun by this audit.',
            'Original SDK, dependency cache and before/after execution were not re-observed; their saved inventories are checked for internal consistency.',
            'Source files are independently rehashed from immutable Git objects. Candidate input differences are reported, not silently accepted.',
            'Supplemental VBA/MIME checks are not added to the application-case total.',
        ],
    }
    args.output.write_text(json.dumps(final, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: final[key] for key in ['status', 'distinct_passed_application_cases', 'distinct_test_files',
                      'static_targets_verified_against_saved_source', 'qualified_source_blob_objects_rehashed',
                      'candidate_preserves_all_qualified_source_inputs']}, indent=2))


if __name__ == '__main__':
    main()
