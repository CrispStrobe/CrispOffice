#!/usr/bin/env python3
"""Run the latest-main Office compatibility gate with exact input receipts."""
import collections
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
EXPECTED_HEAD = sys.argv[1] if len(sys.argv) == 2 else None
SELECTION = json.loads((OUT / 'selection.json').read_text())


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n')


def inputs():
    paths = set()
    for package in ['quds_office_engine', 'quds_office_editor']:
        for folder in ['lib', 'assets', 'test']:
            directory = ROOT / 'packages' / package / folder
            if directory.exists():
                paths.update(path for path in directory.rglob('*') if path.is_file())
    for name in ['.fvmrc', 'pubspec.yaml', 'pubspec.lock',
                 '.dart_tool/package_config.json',
                 'packages/quds_office_engine/pubspec.yaml',
                 'packages/quds_office_editor/pubspec.yaml']:
        paths.add(ROOT / name)
    files = {str(path.relative_to(ROOT)): digest(path) for path in sorted(paths)}
    pins = json.loads((OUT.parent / 'runtime/current-runtime-pins.json').read_text())['pins']
    runtime = {}
    for name in ['dart', 'flutter_tester', 'flutter_tools_snapshot',
                 'sqlite3_native', 'package_configuration', 'package_graph',
                 'package_test_entry']:
        path = Path(pins[name]['path'])
        runtime[name] = {'path': str(path), 'sha256': digest(path)}
    return {'captured_at': now(), 'files': files, 'runtime': runtime}


def parse_events(path, package):
    suites, tests, cases, errors = {}, {}, [], []
    final = None
    for line in path.read_bytes().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get('type')
        if kind == 'suite':
            suite = event['suite']
            source = Path(suite['path'])
            if not source.is_absolute():
                source = ROOT / 'packages' / package / source
            suites[suite['id']] = str(source.relative_to(ROOT))
        elif kind == 'testStart':
            tests[event['test']['id']] = event['test']
        elif kind == 'testDone' and not event.get('hidden'):
            test = tests[event['testID']]
            cases.append({'suite': suites[test['suiteID']], 'name': test['name'],
                          'runner_test_id': test['id'], 'runner_suite_id': test['suiteID'],
                          'result': event['result'], 'skipped': bool(event.get('skipped'))})
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            final = event
    return {'passed': sum(case['result'] == 'success' and not case['skipped'] for case in cases),
            'failed': sum(case['result'] != 'success' for case in cases),
            'skipped': sum(case['skipped'] for case in cases),
            'suite_counts': dict(collections.Counter(case['suite'] for case in cases)),
            'cases': cases, 'errors': errors, 'runner_done': final}


def main():
    if EXPECTED_HEAD is None:
        raise RuntimeError('Pass the full published source checkpoint as the only argument')
    head = git('rev-parse', 'HEAD')
    if head != EXPECTED_HEAD:
        raise RuntimeError(f'Expected qualified checkpoint {EXPECTED_HEAD}; found {head}')
    before = inputs()
    save('inputs-before.json', before)
    summary = {'started_at': now(), 'head': head, 'tree': git('rev-parse', 'HEAD^{tree}'),
               'github_actions_used': False, 'status': 'running', 'cohorts': {}}
    save('summary.json', summary)
    print(json.dumps({'phase': 'inputs-captured', 'head': head, 'files': len(before['files'])}), flush=True)
    for kind in ['engine', 'editor']:
        package = 'quds_office_' + kind
        cwd = ROOT / 'packages' / package
        files = [str(Path(path).relative_to('packages/' + package)) for path in SELECTION[kind]]
        if kind == 'engine':
            command = ['dart', '--packages=' + str(ROOT / '.dart_tool/package_config.json'),
                       str(Path(os.environ['PUB_CACHE']) / 'hosted/pub.dev/test-1.31.1/bin/test.dart'),
                       '--reporter=json', '--concurrency=2', *files]
        else:
            command = ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter=json', *files]
        stdout, stderr = OUT / (kind + '.jsonl'), OUT / (kind + '.stderr')
        started = now()
        with stdout.open('wb') as output, stderr.open('wb') as error:
            result = subprocess.run(command, cwd=cwd, stdout=output, stderr=error)
        receipt = parse_events(stdout, package)
        receipt.update({'command': command, 'cwd': str(cwd), 'started_at': started,
                        'finished_at': now(), 'exit_code': result.returncode,
                        'stdout_sha256': digest(stdout), 'stderr_sha256': digest(stderr)})
        summary['cohorts'][kind] = receipt
        save('summary.json', summary)
        (OUT / (kind + '.jsonl.gz')).write_bytes(gzip.compress(stdout.read_bytes(), mtime=0))
        print(json.dumps({'cohort': kind, 'exit_code': result.returncode,
                          **{key: receipt[key] for key in ['passed', 'failed', 'skipped']}}), flush=True)
        if result.returncode != 0 or receipt['failed'] or receipt['skipped']:
            break
    after = inputs()
    save('inputs-after.json', after)
    changed = [path for path in before['files'].keys() | after['files'].keys()
               if before['files'].get(path) != after['files'].get(path)]
    runtime_changed = [name for name in before['runtime'] if before['runtime'][name] != after['runtime'][name]]
    cases = [case for receipt in summary['cohorts'].values() for case in receipt['cases']]
    duplicates = [list(key) for key, count in collections.Counter((case['suite'], case['name']) for case in cases).items() if count > 1]
    # Parameterized cases may share a display name. Their runner IDs, rather
    # than their labels, establish whether a completion was counted twice.
    duplicate_ids = [list(key) for key, count in collections.Counter(
        (case['suite'], case['runner_test_id']) for case in cases).items() if count > 1]
    selection_mismatches = {kind: sorted(set(receipt['suite_counts']) ^ set(SELECTION[kind]))
                            for kind, receipt in summary['cohorts'].items()
                            if set(receipt['suite_counts']) != set(SELECTION[kind])}
    accepted = (len(summary['cohorts']) == 2 and not changed and not runtime_changed and not duplicate_ids
                and not selection_mismatches
                and all(receipt['exit_code'] == 0 and not receipt['failed'] and not receipt['skipped']
                        and receipt['runner_done'] and receipt['runner_done']['success']
                        for receipt in summary['cohorts'].values()))
    summary.update({'finished_at': now(), 'status': 'pass' if accepted else 'fail',
                    'input_count': len(before['files']), 'changed_inputs': sorted(changed),
                    'changed_runtime': runtime_changed, 'duplicate_suite_name_pairs': duplicates,
                    'duplicate_runner_case_identities': duplicate_ids,
                    'selection_mismatches': selection_mismatches,
                    'accepted_passes': len(cases) if accepted else None})
    save('summary.json', summary)
    print(json.dumps({key: summary[key] for key in ['status', 'accepted_passes', 'changed_inputs', 'changed_runtime']}), flush=True)
    return 0 if accepted else 1


if __name__ == '__main__':
    sys.exit(main())
