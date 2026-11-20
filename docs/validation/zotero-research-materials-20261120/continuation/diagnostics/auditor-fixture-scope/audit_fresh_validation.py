#!/usr/bin/env python3
"""Independently recount the five fresh continuation cohorts; run no tests."""
import argparse
from collections import Counter
from datetime import datetime, timezone
from fnmatch import fnmatchcase
import gzip
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlparse

from recheck_saved_evidence import digest, git, read, record, source_records, tree


COHORTS = ('engine-zotero', 'editor-zotero', 'engine-proofing', 'spacy', 'studio-integration')
STUDIO_FILES = {
    'studio_spacy_pin_test.dart', 'studio_spacy_setup_test.dart',
    'studio_downloads_manager_test.dart', 'studio_linguistic_analysis_test.dart',
    'studio_settings_test.dart', 'studio_language_id_test.dart',
    'studio_comment_draft_proofing_test.dart', 'studio_zotero_shortcuts_test.dart',
    'studio_zotero_citing_transport_test.dart',
}
PINNED_RUNNER = '4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf'
CACHE = {}
RESTORED_SOURCE = 'e79c32e77f1990e303527e477e4909df993c1b9b'
PROOFING_FIXTURES = (
    'packages/quds_office_engine/test/proofing/german_context_test.dart',
    'packages/quds_office_engine/test/proofing/german_release_context_test.dart',
)


def recount(path, repo, cwd):
    events = []
    for line in gzip.decompress(path.read_bytes()).decode('utf-8').split('\n'):
        if not line.strip(' \t\r'):
            continue
        value = json.loads(line)
        if isinstance(value, dict) and isinstance(value.get('type'), str):
            events.append(value)
        else:
            assert isinstance(value, list) and all(isinstance(row, dict) and 'event' in row for row in value)
    starts_list = [row['test'] for row in events if row['type'] == 'testStart']
    starts = {row['id']: row for row in starts_list}
    suites_list = [row['suite'] for row in events if row['type'] == 'suite']
    suites = {row['id']: row for row in suites_list}
    ends = [row for row in events if row['type'] == 'testDone']
    assert len(starts) == len(starts_list) and len(suites) == len(suites_list)
    completions = Counter(row['testID'] for row in ends)
    assert set(completions) == set(starts) and set(completions.values()) == {1}
    final = [row for row in events if row['type'] == 'done']
    assert len(final) == 1 and final[0].get('success') is True
    assert not any(row['type'] == 'error' for row in events)
    assert not any(row['type'] == 'print' and re.search(
        r'A Render\w+ overflowed|would not hit test on the specified widget|does not receive pointer events',
        row.get('message', '')) for row in events)

    def suite_path(value):
        path = Path(unquote(urlparse(value).path)) if value.startswith('file:') else Path(value)
        return str((path if path.is_absolute() else Path(cwd) / path).relative_to(repo))

    cases, excluded, per_suite = [], 0, Counter()
    for end in ends:
        case = starts[end['testID']]
        assert end.get('result') == 'success' and not end.get('skipped') and not case.get('metadata', {}).get('skip')
        lifecycle = end.get('hidden', False) or (case.get('url') is None and (
            case['name'].startswith('loading ') or case['name'].endswith(('(setUpAll)', '(tearDownAll)'))))
        suite = suite_path(suites[case['suiteID']]['path'])
        if lifecycle:
            excluded += 1
        else:
            cases.append((suite, case['name']))
            per_suite[suite] += 1
    multiplicities = Counter(cases)
    duplicates = [{'suite': suite, 'name': name, 'count': count}
                  for (suite, name), count in sorted(multiplicities.items()) if count != 1]
    return {'passed': len(cases), 'distinct_passed_cases': len(multiplicities),
            'repeated_successful_executions': len(cases) - len(multiplicities),
            'duplicate_case_names': duplicates, 'files': len(suites_list),
            'excluded_lifecycle_events': excluded,
            'suite_paths': sorted(suite_path(row['path']) for row in suites_list),
            'per_suite': dict(sorted(per_suite.items()))}, cases


def prove_duplicate_fixtures(repo, source, cases, receipt):
    files, duplicate_rows = {}, []
    observed = Counter(cases)
    pair_pattern = re.compile(r'\(\s*("(?:[^"\\]|\\.)*")\s*,\s*("(?:[^"\\]|\\.)*")\s*,?\s*\)', re.S)
    for path in PROOFING_FIXTURES:
        before = git(repo, 'show', f'{RESTORED_SOURCE}:{path}')
        qualified = git(repo, 'show', f'{source}:{path}')
        assert before == qualified, ('fixture source changed', path)
        text = qualified.decode('utf-8')
        assert text.count('for (final (source, expected) in cases)') == 1
        assert text.count("test('context: $source', () async {") == 1
        section = re.search(r'const cases = <\(String, String\)>\[(.*?)\n  \];', text, re.S).group(1)
        matches = list(pair_pattern.finditer(section))
        assert re.fullmatch(r'[\s,]*', pair_pattern.sub('', section))
        pairs = [(json.loads(row.group(1)), json.loads(row.group(2))) for row in matches]
        expected_names = Counter('context: ' + value for value, _ in pairs)
        actual_names = Counter({name: count for (suite, name), count in observed.items() if suite == path})
        assert actual_names == expected_names, ('raw cases differ from complete literal fixture', path)
        unique_pairs = Counter(pairs)
        assert len(unique_pairs) == len(expected_names), 'A source has two different expected results'
        files[path] = {'restored_source': RESTORED_SOURCE, 'qualified_source': source,
                       'identical_complete_file': True, 'record': record(qualified),
                       'fixture_rows': len(pairs), 'distinct_fixture_rows': len(unique_pairs)}
        for (value, expected), count in unique_pairs.items():
            if count > 1:
                assert count == 2
                duplicate_rows.append({'suite': path, 'name': 'context: ' + value, 'count': count,
                                       'source': value, 'expected': expected,
                                       'fixture_row_numbers': [i + 1 for i, pair in enumerate(pairs) if pair == (value, expected)]})
    duplicate_rows.sort(key=lambda row: (row['suite'], row['name']))
    raw_duplicates = sorted((suite, name, count) for (suite, name), count in observed.items() if count > 1)
    assert raw_duplicates == [(row['suite'], row['name'], row['count']) for row in duplicate_rows]
    assert len(duplicate_rows) == 8 and sum(row['count'] - 1 for row in duplicate_rows) == 8
    primary_duplicates = sorted((str(Path(row['suite']).relative_to(repo)), row['name'], row['count'])
                                for row in receipt['tests']['duplicate_application_names'])
    assert primary_duplicates == raw_duplicates
    return {
        'status': 'verified_preexisting_identical_fixture_repetitions',
        'primary_runner_status': receipt['status'],
        'primary_failed_guards': ['unique_application_test_names'],
        'every_other_primary_guard_passed': True,
        'successful_application_executions': len(cases),
        'distinct_successful_case_identities': len(observed),
        'repeated_successful_executions_excluded_from_distinct_count': 8,
        'primary_receipt_modified': False,
        'fixture_sources_modified': False,
        'qualified_source': source,
        'restored_source': RESTORED_SOURCE,
        'source_files': files,
        'repeated_pairs': duplicate_rows,
        'policy': 'Only these eight exact identical source/expected fixture pairs are counted once. The original name-uniqueness rejection remains in the primary receipt. Every execution passed and no other guard exception is allowed.',
    }


def current_record(path):
    path = path.resolve()
    stat = path.stat()
    key = (str(path), stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
    if key not in CACHE:
        sha256 = hashlib.sha256()
        blob = hashlib.sha1(f'blob {stat.st_size}\0'.encode())
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                sha256.update(block)
                blob.update(block)
        CACHE[key] = {'bytes': stat.st_size, 'sha256': sha256.hexdigest(), 'git_blob_sha1': blob.hexdigest()}
    return CACHE[key]


def expected_selection(name, names):
    if name in ('engine-zotero', 'editor-zotero'):
        package = 'quds_office_engine' if name == 'engine-zotero' else 'quds_office_editor'
        parent = Path('packages') / package / 'test'
        return sorted(p for p in names if Path(p).parent == parent and fnmatchcase(Path(p).name, '*zotero*_test.dart'))
    if name == 'engine-proofing':
        prefix = 'packages/quds_office_engine/test/proofing/'
        return sorted(p for p in names if p.startswith(prefix) and p.endswith('_test.dart'))
    if name == 'spacy':
        prefix = 'packages/quds_proofing_spacy/test/'
        return sorted(p for p in names if p.startswith(prefix) and p.endswith('_test.dart'))
    if name == 'studio-integration':
        return sorted('packages/quds_office_editor/example/test/' + p for p in STUDIO_FILES)
    raise ValueError(name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True, help='The continuation directory')
    parser.add_argument('--source', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    source = git(repo, 'rev-parse', '--verify', args.source).decode().strip()
    candidate = git(repo, 'rev-parse', '--verify', args.candidate).decode().strip()
    source_tree, candidate_tree = tree(repo, source), tree(repo, candidate)
    receipts, inventories = {}, {}
    oids = set()
    for name in COHORTS:
        folder = args.evidence / ('accepted-' + name)
        receipts[name] = read(folder / 'receipt.json')
        inventories[name] = read(folder / 'inputs.json.gz')['before']
        oids.update(source_tree[p] for p in inventories[name]['source'])
    records = source_records(repo, oids)
    all_cases, all_paths, results = [], [], []
    drift = {}
    proofing_accounting = None
    for name in COHORTS:
        folder = args.evidence / ('accepted-' + name)
        receipt, inventory = receipts[name], inventories[name]
        assert receipt['exit_code'] == 0 and not receipt['timed_out']
        failed_guards = sorted(key for key, value in receipt['guards'].items() if not value)
        if name == 'engine-proofing':
            assert receipt['status'] == 'failed' and failed_guards == ['unique_application_test_names']
        else:
            assert receipt['status'] == 'passed' and failed_guards == []
        assert receipt['source_head_at_start'] == receipt['source_head_at_finish'] == source
        assert receipt['head_unchanged'] and not receipt['application_timeouts_modified']
        assert receipt['validation_runner']['sha256'] == PINNED_RUNNER
        runner_record = current_record(Path(receipt['validation_runner']['path']))
        assert all(receipt['validation_runner'][key] == runner_record[key] for key in runner_record)
        for filename, expected in receipt['artifacts'].items():
            assert current_record(folder / filename) == expected, (name, filename)
        assert read(folder / 'input-check.json') == receipt['fingerprints']
        counted, cases = recount(folder / 'events.jsonl.gz', repo, receipt['cwd'])
        if name == 'engine-proofing':
            proofing_accounting = prove_duplicate_fixtures(repo, source, cases, receipt)
            assert counted['passed'] == 1713 and counted['distinct_passed_cases'] == 1705
        else:
            assert counted['duplicate_case_names'] == []
        expected = expected_selection(name, source_tree)
        assert expected == counted['suite_paths'] == sorted(receipt['selected_repository_paths'])
        assert counted['passed'] == receipt['tests']['passed'] and counted['files'] == receipt['tests']['suite_count']
        for suite in receipt['tests']['suites']:
            path = str(Path(suite['path']).relative_to(repo))
            assert counted['per_suite'][path] == suite['passed'] and suite['failed'] == suite['skipped'] == 0
        for area, value in inventory.items():
            assert digest(value) == receipt['fingerprints']['before_sha256'][area] == receipt['fingerprints']['after_sha256'][area]
            assert receipt['fingerprints']['changed_paths'][area] == []
        for path, expected in inventory['source'].items():
            oid = source_tree[path]
            assert records[oid] == expected, (name, path)
            if candidate_tree.get(path) != oid:
                drift[path] = {'qualified_blob': oid, 'candidate_blob': candidate_tree.get(path)}
        live_counts = {'source_git_inputs': len(inventory['source']), 'dependency_files': 0}
        for area, root in [('runtime', Path(receipt['runtime']['flutter_root'])), ('workspace', repo)]:
            for path, expected in inventory[area].items():
                assert current_record(root / path) == expected, (name, area, path)
            live_counts[area] = len(inventory[area])
        for package, info in inventory['dependencies'].items():
            assert len(info['files']) == info['file_count']
            assert digest(info['files']) == info['inventory_sha256']
            for path, expected in info['files'].items():
                assert current_record(Path(info['root']) / path) == expected, (name, package, path)
            live_counts['dependency_files'] += len(info['files'])
        for path, expected in inventory['host_fonts'].items():
            assert current_record(Path(path)) == expected
        live_counts['host_fonts'] = len(inventory['host_fonts'])
        adapter = receipt.get('selection_adapter')
        if name in ('engine-proofing', 'spacy', 'studio-integration'):
            assert adapter and adapter['code_unchanged'] and adapter['shared_sdk_validation_lock_unchanged']
            assert adapter['code_before'] == adapter['code_after']
            for info in adapter['code_before'].values():
                actual = current_record(Path(info['path']))
                assert info['bytes'] == actual['bytes'] and info['sha256'] == actual['sha256']
        if name == 'spacy':
            fixture = receipt['qualified_bytes_fixture']
            assert fixture['status'] == 'passed' and fixture['fixture_unchanged'] and fixture['code_unchanged']
            assert fixture['fixture_before'] == fixture['fixture_after'] == current_record(Path(fixture['fixture_path']))
            assert fixture['fixture_after']['sha256'] == 'ccc96620e01164d18e8d2e46b9a383677e4430c8889833bedab5b56c16a1b40f'
            assert fixture['fixture_after']['bytes'] == 2322928
            assert fixture['native_library_loaded_or_executed'] is False
            assert fixture['source_commit'] == source
            assert counted['passed'] == 114
        counted.update(name=name, source_commit=source, receipt_sha256=current_record(folder / 'receipt.json')['sha256'],
                       source_inventory_sha256=digest(inventory['source']), verified_inputs=live_counts,
                       primary_runner_status=receipt['status'], primary_failed_guards=failed_guards,
                       started_at_utc=receipt['started_at_utc'], finished_at_utc=receipt['finished_at_utc'])
        results.append(counted)
        all_cases.extend(cases)
        all_paths.extend(counted['suite_paths'])
    assert len(all_cases) - len(set(all_cases)) == 8
    assert len(all_paths) == len(set(all_paths))
    assert proofing_accounting is not None
    proofing_accounting['audited_at_utc'] = datetime.now(timezone.utc).isoformat()
    proofing_accounting['verifier_sha256'] = current_record(Path(__file__))['sha256']
    proofing_accounting['primary_receipt_sha256'] = current_record(args.evidence / 'accepted-engine-proofing/receipt.json')['sha256']
    accounting_path = args.evidence / 'proofing-accounting.json'
    accounting_path.write_text(json.dumps(proofing_accounting, indent=2, sort_keys=True) + '\n')
    result = {
        'status': 'fresh_evidence_verified_with_documented_accounting_exception',
        'audited_at_utc': datetime.now(timezone.utc).isoformat(),
        'qualified_source': source,
        'candidate_commit': candidate,
        'verifier_sha256': current_record(Path(__file__))['sha256'],
        'imported_helpers_sha256': current_record(Path(__file__).with_name('recheck_saved_evidence.py'))['sha256'],
        'fresh_successful_application_executions': len(all_cases),
        'fresh_distinct_passed_cases': len(set(all_cases)),
        'repeated_successful_executions_excluded_from_distinct_count': 8,
        'failed_or_skipped_application_executions': 0,
        'fresh_distinct_test_files': len(all_paths),
        'primary_receipts_rejected': [{'cohort': 'engine-proofing', 'guard': 'unique_application_test_names'}],
        'proofing_accounting': {'path': 'proofing-accounting.json', 'sha256': current_record(accounting_path)['sha256']},
        'cohorts': results,
        'source_blob_objects_rehashed': len(records),
        'live_runtime_workspace_dependency_and_font_files_rehashed': len(CACHE),
        'candidate_preserves_all_recorded_source_inputs': not drift,
        'candidate_recorded_source_differences': drift,
        'limits': [
            'This independent audit runs no application tests. It recounts all five fresh raw event streams and rehashes saved source objects plus available current runtime/dependency inputs.',
            'The original 2,886 historical cases remain a separate source-attributed result; overlapping fresh Zotero cases must not be summed into that number.',
            'The proofing primary receipt remains rejected for duplicate display names. A separate exact source-bound proof counts eight identical repeated fixture rows once; no source or original guard was changed.',
            'Candidate differences are reported explicitly; no automatic claim that an untested source change is qualified is made.',
            'Runtime inventory covers the named SDK files recorded by the runner, not every operating-system library or binary.',
        ],
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    summary = {key: result[key] for key in [
        'status', 'qualified_source', 'candidate_commit', 'fresh_successful_application_executions',
        'fresh_distinct_passed_cases', 'fresh_distinct_test_files',
        'repeated_successful_executions_excluded_from_distinct_count',
        'failed_or_skipped_application_executions', 'primary_receipts_rejected', 'proofing_accounting',
        'candidate_preserves_all_recorded_source_inputs', 'candidate_recorded_source_differences', 'limits',
    ]}
    summary['cohorts'] = [{key: row[key] for key in ['name', 'passed', 'distinct_passed_cases', 'files',
                                                  'primary_runner_status', 'primary_failed_guards',
                                                  'receipt_sha256']} for row in results]
    summary['independent_audit'] = {'path': str(args.output.relative_to(args.evidence)),
                                    'sha256': current_record(args.output)['sha256']}
    (args.evidence / 'summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: result[key] for key in ['status', 'fresh_distinct_passed_cases', 'fresh_distinct_test_files',
                                                'source_blob_objects_rehashed', 'candidate_preserves_all_recorded_source_inputs']}, indent=2))


if __name__ == '__main__':
    main()
