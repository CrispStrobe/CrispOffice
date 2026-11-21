#!/usr/bin/env python3
"""Independently replay the final Zotero qualification from raw test events.

Reads only the fixed original-engine and resumed-cohort executions. It never
selects a preferred retry, changes a test, or starts a test process.
"""

import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess


EXPECTED_SOURCE = 'b02b5b7f62c34bf37698d53e0cb614df93ac30d955ce0ad8b1cb1707f6f18916'
FROZEN_COMMIT = 'a6095c304ad2d6935f2ae6f8b74412038d19f142'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return json.loads(path.read_text())


def packed(path):
    return json.loads(gzip.decompress(path.read_bytes()))


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def inspect_events(directory, command, expected_files, repo):
    events = []
    for line in (directory / 'stdout.jsonl').read_text().splitlines():
        if not line.strip():
            continue
        value = json.loads(line)
        require(isinstance(value, dict), 'Nonobject output event')
        events.append(value)
    starts = [event['test'] for event in events if event.get('type') == 'testStart']
    finishes = [event for event in events if event.get('type') == 'testDone']
    suites = [event['suite'] for event in events if event.get('type') == 'suite']
    terminal = [event for event in events if event.get('type') == 'done']
    require(len(terminal) == 1 and terminal[0].get('success') is True,
            f'No unique successful terminal: {directory}')
    require(not any(event.get('type') == 'error' for event in events),
            f'Runtime error event: {directory}')
    require((directory / 'stderr.log').read_bytes() == b'',
            f'Nonempty stderr: {directory}')
    diagnostics = re.compile(
        r'Unhandled\s+(?:exception|error)|Uncaught\s+(?:exception|error)|'
        r'EXCEPTION CAUGHT BY|Segmentation fault|SIGSEGV|'
        r'Exception caught by widgets library|^\[ERROR:|^Error:', re.I | re.M)
    require(not any(diagnostics.search(str(event.get('message', '')))
                    for event in events if event.get('type') == 'print'),
            f'Raw runtime exception: {directory}')
    by_id = {item['id']: item for item in starts}
    require(len(by_id) == len(starts), f'Duplicate test starts: {directory}')
    ends = Counter(event['testID'] for event in finishes)
    require(set(by_id) == set(ends) and all(count == 1 for count in ends.values()),
            f'Incomplete/duplicate test completion: {directory}')
    suite_map = {item['id']: item for item in suites}
    require(len(suite_map) == len(suites), f'Duplicate suite ID: {directory}')
    cwd = Path(command['cwd'])
    resolved = {}
    for suite in suites:
        path = Path(suite['path'])
        resolved[suite['id']] = str((path if path.is_absolute() else cwd / path).resolve())
    require(len(set(resolved.values())) == len(suites), f'Repeated suite path: {directory}')
    expected = {str((repo / path).resolve()) for path in expected_files}
    require(set(resolved.values()) == expected, f'Selection mismatch: {directory}')
    actual_cases = []
    excluded = []
    for finish in finishes:
        test = by_id[finish['testID']]
        name = test['name']
        suite = resolved[test['suiteID']]
        loading = name.startswith('loading ') and bool(finish.get('hidden'))
        lifecycle = bool(re.search(r'(?:^|\s)\((?:setUpAll|tearDownAll)\)$', name))
        require(not finish.get('hidden') or loading or lifecycle,
                f'Hidden real case was excluded: {suite}: {name}')
        require(finish.get('result') == 'success' and not finish.get('skipped'),
                f'Failure/skip, including lifecycle: {suite}: {name}')
        item = {'suite': str(Path(suite).relative_to(repo)), 'name': name,
                'test_id': test['id'], 'result': finish['result']}
        if loading or lifecycle:
            excluded.append({**item, 'reason': 'loading' if loading else 'lifecycle'})
        else:
            actual_cases.append(item)
    keys = [(item['suite'], item['name']) for item in actual_cases]
    require(len(keys) == len(set(keys)), f'Duplicate actual case identity: {directory}')
    return {'passed': len(actual_cases), 'suites': len(suites),
            'failures': 0, 'skips': 0, 'runtime_errors': 0, 'stderr_bytes': 0,
            'excluded': dict(Counter(item['reason'] for item in excluded)),
            'cases': actual_cases, 'excluded_events': excluded,
            'stdout_sha256': sha((directory / 'stdout.jsonl').read_bytes()),
            'terminal': terminal[0], 'raw_event_count': len(events)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path,
                        default=Path('/workspace/scratch/a4ce103494d8'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.root
    base = root / 'cell-validation'
    repo = root / 'quds_office_suite'
    original = base / 'frozen-final'
    remaining = base / 'frozen-remaining'
    plan = read(base / 'selection.json')
    frozen = packed(original / 'frozen-source.json.gz')
    require(len(frozen) == 2978 and sha(canonical(frozen)) == EXPECTED_SOURCE,
            'Unexpected frozen source map')
    git_tree = {}
    for value in subprocess.check_output(['git', 'ls-tree', '-rz', FROZEN_COMMIT], cwd=repo).split(b'\0'):
        if not value:
            continue
        metadata, path = value.split(b'\t')
        mode, kind, obj = metadata.decode().split()
        git_tree[path.decode()] = (mode, kind, obj)
    derived = set()
    for path in git_tree:
        p = Path(path)
        if path in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'):
            derived.add(path)
        if not path.startswith(('packages/', 'third_party/')):
            continue
        if any(part in p.parts for part in ('.dart_tool', 'build', 'docs')):
            continue
        if (p.suffix == '.dart' or p.name in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')
                or '/test/fixtures/' in path
                or (path.startswith('packages/quds_office_engine/example/macros/') and p.suffix == '.bas')):
            derived.add(path)
    # rg --files omitted this hidden Git normalization rule. It is not runtime
    # fixture content; retain the exact one-file difference explicitly instead
    # of broadening an exclusion or pretending it was bound during execution.
    metadata_exclusion = 'packages/quds_office_engine/test/fixtures/word_reviews/.gitattributes'
    require(derived - set(frozen) == {metadata_exclusion} and not set(frozen) - derived,
            'Frozen map omits/adds unexpected scoped committed paths')
    metadata_bytes = (repo / metadata_exclusion).read_bytes()
    metadata_blob = hashlib.sha1(b'blob ' + str(len(metadata_bytes)).encode() + b'\0' + metadata_bytes).hexdigest()
    require(git_tree[metadata_exclusion] == ('100644', 'blob', metadata_blob),
            'Excluded Git normalization metadata differs from frozen commit')
    for path, expected in frozen.items():
        data = (repo / path).read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        mode, kind, obj = git_tree[path]
        require(kind == 'blob' and mode in ('100644', '100755') and obj == blob,
                f'Current source differs from frozen commit: {path}')
        require(expected == {'size': len(data), 'sha256': sha(data),
                             'git_blob_sha1': blob, 'executable': mode == '100755'},
                f'Frozen source metadata differs: {path}')
        require(bool((repo / path).stat().st_mode & 0o111) == expected['executable'],
                f'Current mode differs: {path}')
    env = read(original / 'environment-before.json')
    for run in (original, remaining):
        require(packed(run / 'frozen-source.json.gz') == frozen
                and packed(run / 'final-source.json.gz') == frozen,
                f'Run source binding changed: {run}')
        require(read(run / 'environment-before.json') == env
                and read(run / 'environment-after.json') == env,
                f'Run environment binding changed: {run}')
    v1 = (base / 'run_qualification_v1.py').read_bytes()
    v2 = (base / 'run_qualification.py').read_bytes()
    old = b"actual={str(Path(s['path']).resolve()) for s in suites.values() if s.get('path')}"
    new = b"actual={str((Path(s['path']) if Path(s['path']).is_absolute() else cwd/s['path']).resolve()) for s in suites.values() if s.get('path')}"
    require(v1.count(old) == 1 and v1.replace(old, new) == v2,
            'Audit correction changed more than suite-path resolution')
    require(sha(v1) == read(original / 'run.json')['runner_sha256']
            and sha(v2) == read(remaining / 'run.json')['runner_sha256'],
            'Recorded runner identities do not match preserved scripts')
    original_summary = read(original / 'engine-zotero/summary.json')
    require(original_summary['status'] == 'failed'
            and [key for key, value in original_summary['guards'].items() if not value]
            == ['all_selected_suites_reported'], 'Original audit rejection was not preserved')

    all_cases = []
    all_suites = []
    cohorts = []
    for cohort in plan['cohorts']:
        directory = (original if cohort['name'] == 'engine-zotero' else remaining) / cohort['name']
        command = read(directory / 'command.json')
        selected = [cohort['package'] + '/' + path for path in cohort['tests']]
        require(command['selected_test_files'] == selected, 'Command selected-file inventory differs')
        prefix = ([str(root / 'runtime-setup/dart-test.sh')]
                  if cohort['runner'] == 'dart'
                  else [str(root / 'runtime-setup/flutter-sdk/bin/flutter'), 'test', '--no-pub'])
        expected_command = prefix + ['--reporter', 'json', '--concurrency', str(cohort['concurrency']),
                                     '--timeout', cohort['test_timeout'], *cohort['tests']]
        require(command['command'] == expected_command, 'Test command filters/semantics changed')
        exit_record = read(directory / 'process-exit.json')
        require(exit_record['exit_code'] == 0 and not exit_record['timed_out'], 'Test process failed')
        require(packed(directory / 'source-before.json.gz') == frozen
                and packed(directory / 'source-after.json.gz') == frozen,
                f'Cohort source changed: {cohort["name"]}')
        report = inspect_events(directory, command, selected, repo)
        published = read(directory / 'summary.json')
        require(report['passed'] == published['counts']['passed']
                and report['suites'] == published['counts']['suites']
                and report['stdout_sha256'] == published['stdout_sha256'],
                f'Raw result/summary mismatch: {cohort["name"]}')
        all_cases.extend(report.pop('cases'))
        report.pop('excluded_events')
        all_suites.extend(selected)
        cohorts.append({'name': cohort['name'], 'directory': str(directory), **report})
    require(len(all_suites) == len(set(all_suites)) == 119,
            'Cohort file populations overlap or omit selected suites')
    keys = [(item['suite'], item['name']) for item in all_cases]
    require(len(keys) == len(set(keys)), 'Case identities overlap across cohorts')

    portable_dir = root / 'zotero-cell-portable'
    portable_receipt = read(portable_dir / 'receipt.json')
    portable_selection = ['packages/quds_office_engine/test/word_zotero_table_cell_replacement_test.dart',
                          'packages/quds_office_engine/test/word_zotero_multiparagraph_test.dart']
    portable = inspect_events(portable_dir, portable_receipt, portable_selection, repo)
    require(portable['passed'] == 121 and portable_receipt['exit_code'] == 0,
            'Portable run did not complete 121 cases')
    before = read(portable_dir / 'source-before.json')
    require(before == read(portable_dir / 'source-after.json'), 'Portable source changed')
    require(all(frozen[path]['sha256'] == digest for path, digest in before.items()),
            'Portable input source differs from qualified source')
    require({(item['suite'], item['name']) for item in portable['cases']}.issubset(set(keys)),
            'Portable population is not exactly an overlap subset')
    portable.pop('cases')
    portable.pop('excluded_events')
    receipt = {'status': 'accepted', 'frozen_commit': FROZEN_COMMIT,
               'source_input_count': len(frozen), 'source_map_sha256': EXPECTED_SOURCE,
               'source_matches_committed_and_current_paths_blobs_modes': True,
               'explicit_nonruntime_metadata_exclusion': {
                   'path': metadata_exclusion,
                   'reason': 'Hidden Git normalization attributes omitted by rg; all actual XML fixture bytes are included',
                   'current_matches_frozen_commit': True,
                   'git_blob': metadata_blob,
                   'sha256': sha(metadata_bytes),
                   'bound_during_test_execution': False},
               'bound_runtime_environment_files': len(env),
               'runtime_environment_unchanged_between_both_executions': True,
               'audit_correction': 'Only suite-path resolution changed; original rejection and raw execution retained',
               'runner_v1_sha256': sha(v1), 'runner_v2_sha256': sha(v2),
               'cohorts': cohorts, 'unique_vm_cases': len(all_cases), 'unique_suite_files': len(all_suites),
               'failures': 0, 'skips': 0, 'runtime_errors': 0,
               'portable': portable, 'portable_cases_are_overlapping': True,
               'raw_case_inventory_sha256': sha(canonical(all_cases)),
               'audit_script_sha256': sha(Path(__file__).read_bytes()),
               'methodology': 'Original test files in standard runners; no synthesized or rewritten test modules. Engine concurrency two, Flutter concurrency one. Independent raw-event reconstruction excludes only successful loading/lifecycle events.',
               'scope_limit': 'Runtime equality covers recorded binaries, runner configuration, locks and manifests; it is not an exhaustive hash of every extracted dependency file.'}
    args.output.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in ['status', 'unique_vm_cases', 'unique_suite_files',
                                                  'failures', 'skips', 'runtime_errors',
                                                  'source_input_count', 'source_map_sha256']}, indent=2))


if __name__ == '__main__':
    main()
