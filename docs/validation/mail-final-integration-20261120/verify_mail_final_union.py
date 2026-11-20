#!/usr/bin/env python3
"""Recount sealed Mail evidence without rerunning tests or changing source.

The interrupted Studio command is accepted only at complete suite boundaries:
one root group, matching case count, all starts completed, no failures/errors.
The unfinished loading suite is replaced by its successful continuation.
"""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlparse


HEAD = 'c62338c65571aa399da5592455b651fa5c6a9317'
TREE = 'd8e43e6f43b0726e8fefded52c185e387291916d'
RECHECKS = {'core-node', 'cloud-provider-node'}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def identity(case):
    return case['file'], case['name'], case['occurrence']


def git_source_check(repo, source):
    tree = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', HEAD + '^{tree}'], text=True).strip()
    assert tree == TREE
    process = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for name, row in sorted(source.items()):
        process.stdin.write((HEAD + ':' + name + '\n').encode())
        process.stdin.flush()
        response = process.stdout.readline().decode().strip().split()
        assert len(response) == 3 and response[1] == 'blob', (name, response)
        size = int(response[2])
        content = process.stdout.read(size)
        assert process.stdout.read(1) == b'\n'
        assert len(content) == row['bytes'] == size, name
        assert hashlib.sha256(content).hexdigest() == row['sha256'], name
    process.stdin.close()
    assert process.wait() == 0
    return {'source_head': HEAD, 'source_tree': TREE, 'verified_git_blob_count': len(source)}


def completed_partial_studio(path, command, source_repo):
    events = []
    for line in path.read_text().splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict) and isinstance(row.get('type'), str):
            events.append(row)
    assert not [row for row in events if row['type'] in {'error', 'done'}]
    starts_list = [row['test'] for row in events if row['type'] == 'testStart']
    ends_list = [row for row in events if row['type'] == 'testDone']
    assert all(count == 1 for count in Counter(row['id'] for row in starts_list).values())
    assert all(count == 1 for count in Counter(row['testID'] for row in ends_list).values())
    starts = {row['id']: row for row in starts_list}
    ends = {row['testID']: row for row in ends_list}
    suites = {row['suite']['id']: row['suite'] for row in events if row['type'] == 'suite'}
    groups = [row['group'] for row in events if row['type'] == 'group']
    assert set(ends) <= set(starts)
    cases, suites_result = [], []
    occurrences = Counter()
    for suite_id, suite in suites.items():
        p = Path(unquote(urlparse(suite['path']).path)) if suite['path'].startswith('file:') else Path(suite['path'])
        if not p.is_absolute():
            p = Path(command['cwd']) / p
        file = str(p.resolve().relative_to(source_repo))
        roots = [g for g in groups if g['suiteID'] == suite_id and g.get('parentID') is None]
        suite_starts = {key: row for key, row in starts.items() if row['suiteID'] == suite_id}
        unfinished = sorted(set(suite_starts) - set(ends))
        visible = [(key, ends[key]) for key in suite_starts if key in ends and not ends[key].get('hidden')]
        assert all(end['result'] == 'success' and not end.get('skipped') for key, end in visible)
        complete = len(roots) == 1 and roots[0]['testCount'] == len(visible) and not unfinished and bool(visible)
        if complete:
            for key, end in visible:
                name = starts[key]['name']
                occurrences[(file, name)] += 1
                cases.append({'file': file, 'name': name, 'occurrence': occurrences[(file, name)],
                    'platform': command['platform'], 'result': 'success', 'skipped': False})
        else:
            assert file.endswith('/studio_mail_cached_mail_test.dart') and not roots and not visible
            assert len(suite_starts) == len(unfinished) == 1
            assert all(starts[key]['name'].startswith('loading ') for key in unfinished)
        suites_result.append({'file': file, 'completed_cases': len(visible),
            'expected_root_group_cases': [g['testCount'] for g in roots],
            'unfinished_test_ids': unfinished, 'accepted_complete_suite': complete})
    assert len(cases) == 323
    assert sum(row['accepted_complete_suite'] for row in suites_result) == 5
    assert len(suites_result) == 6
    return cases, suites_result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--initial', type=Path, required=True)
    parser.add_argument('--continuation', type=Path, required=True)
    parser.add_argument('--repo', type=Path, required=True,
                        help='Any checkout containing the immutable c623 Git objects; its working tree may have later docs.')
    parser.add_argument('--historical-cases', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    initial, continued = args.initial.resolve(), args.continuation.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    old, new = read(initial / 'progress.json'), read(continued / 'qualification.json')
    interrupted = read(initial / 'interruption-seal.json')
    assert old['status'] == 'running' and new['status'] == 'passed'
    assert interrupted['whole_interrupted_aggregate_passed'] is False
    assert interrupted['tool_reported_session_exit'] == 130
    assert interrupted['source_head'] == HEAD and interrupted['git_status'] == ''
    assert interrupted['progress_sha256'] == sha(initial / 'progress.json')
    assert interrupted['raw_studio_log_sha256'] == sha(initial / 'studio-tests.jsonl')
    assert all(interrupted['source_seals'].values())
    assert new['git_status_after'] == '' and new['source_head_after'] == HEAD
    assert new['source_tree_after'] == TREE
    seals = {}
    for kind in ['source', 'dependencies', 'runtime']:
        values = [read(initial / (kind + '-before.json')),
            read(initial / (kind + '-interruption-after.json')),
            read(continued / (kind + '-before.json')),
            read(continued / (kind + '-after.json'))]
        assert all(value == values[0] for value in values), kind
        assert new[kind + '_unchanged'] is True
        seals[kind] = {'initial_before': sha(initial / (kind + '-before.json')),
            'initial_after': sha(initial / (kind + '-interruption-after.json')),
            'continuation_before': sha(continued / (kind + '-before.json')),
            'continuation_after': sha(continued / (kind + '-after.json')),
            'all_equal': True, 'files': len(values[0])}
    assert old['source_head'] == new['source_head'] == HEAD
    assert old['source_tree'] == new['source_tree'] == TREE
    assert old['runner_sha256'] == new['runner_sha256'] == sha(initial / 'qualification-runner.py')
    assert sha(initial / 'qualification-runner.py') == sha(continued / 'qualification-runner.py')
    spec = importlib.util.spec_from_file_location('sealed_mail_runner', initial / 'qualification-runner.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    source_repo = Path(old['commands'][0]['cwd']).resolve()
    canonical, portable, commands, results = [], [], [], {}
    for label, directory, receipt in [('initial', initial, old), ('continuation', continued, new)]:
        for command in receipt['commands']:
            name = command['name']
            if label == 'initial' and name == 'studio-tests':
                continue
            assert command['exit_code'] == 0, (label, name)
            for stream in ['stdout', 'stderr']:
                assert sha(directory / command[stream]) == command[stream + '_sha256']
            commands.append({'run': label, **command})
            if not command['expected_test_files']:
                continue
            result, cases = runner.test_report(directory / command['stdout'], Path(command['cwd']),
                source_repo, command['expected_test_files'], command['platform'])
            assert result == receipt['test_results'][name] and result['accepted'], (label, name)
            assert [{**case, 'gate': name} for case in cases] == read(directory / (name + '-cases.json'))
            results[label + '/' + name] = result
            target = portable if name in RECHECKS else canonical
            target.extend({**case, 'source_head': HEAD, 'run': label, 'gate': name} for case in cases)
    command = next(row for row in old['commands'] if row['name'] == 'studio-tests')
    cases, suites = completed_partial_studio(initial / command['stdout'], command, source_repo)
    assert [{**case, 'gate': 'studio-completed-before-interruption'} for case in cases] == read(initial / 'completed-studio-cases.json')
    assert suites == interrupted['studio_suites']
    canonical.extend({**case, 'source_head': HEAD, 'run': 'initial-complete-suite', 'gate': 'studio-tests'} for case in cases)
    identities = [identity(case) for case in canonical]
    assert len(identities) == len(set(identities)) == 1161
    assert len({case['file'] for case in canonical}) == 52
    assert len(portable) == 218
    assert not any(case['skipped'] or case['result'] != 'success' for case in canonical + portable)
    portable_checks = {}
    for gate in sorted(RECHECKS):
        actual = [case for case in portable if case['gate'] == gate]
        files = {case['file'] for case in actual}
        expected = [case for case in canonical if case['file'] in files]
        assert Counter(map(identity, actual)) == Counter(map(identity, expected)), gate
        portable_checks[gate] = {'passed': len(actual), 'suites': len(files), 'identity_matches_canonical_vm': True}
    gate_names = {row['name'] for row in commands}
    assert gate_names == set(runner.GATES)
    assert all('--fatal-infos' in row['command'] and '--fatal-warnings' in row['command']
        for row in commands if row['name'].endswith('-analysis'))
    assert '--set-exit-if-changed' in next(row for row in commands if row['name'] == 'format')['command']
    historical = read(args.historical_cases)
    previous = {identity(case) for case in historical}
    assert len(previous) == len(historical) == 1056
    current = set(identities)
    overlap = {'historical_source_head': 'cf25a0a3d80ee18d2550161af182bacc4e49d18f',
        'current_source_head': HEAD, 'historical_cases': 1056, 'current_cases': 1161,
        'matching_case_identities': len(previous & current),
        'current_only_case_identities': [list(row) for row in sorted(current - previous)],
        'historical_only_case_identities': [list(row) for row in sorted(previous - current)],
        'counts_are_not_additive': True,
        'note': 'All current cases executed on c623; matching names do not claim unchanged behavior or retained earlier execution.'}
    git_record = git_source_check(args.repo, read(initial / 'source-before.json'))
    per_file = dict(sorted(Counter(case['file'] for case in canonical).items()))
    accepted = {'schema_version': 1, 'status': 'passed', 'source_head': HEAD, 'source_tree': TREE,
        'accepted_passed': 1161, 'accepted_suites': 52, 'failed': 0, 'skipped': 0,
        'additional_platform_rechecks': 218, 'platform_rechecks': portable_checks,
        'raw_test_executions': 1379, 'whole_interrupted_aggregate_passed': False,
        'initial_progress_status': old['status'], 'interrupted_session_exit': 130,
        'continuation_status': new['status'], 'continuation_cases': 45,
        'completed_initial_cases': 1116, 'completed_partial_studio_cases': 323,
        'completed_partial_studio_suites': 5, 'partial_studio_suite_boundaries': suites,
        'interruption_cause': 'Undetermined; hidden cached-suite load did not finish before bounded interruption.',
        'source_dependency_runtime_seals': seals, 'git_source_verification': git_record,
        'source_file_count': old['source_file_count'], 'dependency_file_count': old['dependency_file_count'],
        'dart_version': old['dart_version'], 'node_version': old['node_version'],
        'flutter_runtime': old['flutter_runtime'], 'runner_sha256': old['runner_sha256'],
        'github_actions_used': False, 'live_provider_accounts_used': False,
        'commands': commands, 'completed_test_results': results, 'per_file': per_file,
        'format_checked_changed_dart_files': old['changed_dart_files'],
        'historical_overlap': {key: value for key, value in overlap.items() if not isinstance(value, list)}}
    canonical.sort(key=lambda row: (identity(row), row['platform']))
    portable.sort(key=lambda row: (row['gate'], identity(row)))
    write(out / 'qualification.json', accepted)
    write(out / 'accepted-test-cases.json', canonical)
    write(out / 'platform-recheck-cases.json', portable)
    write(out / 'historical-overlap.json', overlap)
    write(out / 'source-git-verification.json', git_record)
    print(json.dumps({'status': 'passed', 'accepted': len(canonical), 'suites': len(per_file),
        'node_rechecks': len(portable), 'historical_identity_overlap': len(previous & current),
        'git_blobs_verified': git_record['verified_git_blob_count']}, indent=2))


if __name__ == '__main__':
    main()
