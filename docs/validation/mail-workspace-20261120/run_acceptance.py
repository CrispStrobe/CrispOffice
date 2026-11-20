#!/usr/bin/env python3
"""Source-bound local mail acceptance using the real pinned test runners.

Run after sourcing the pinned runtime/env.sh. Every attempt is retained in a
new directory; --only can select a focused follow-up without recounting earlier
runs. JSON event counting excludes loading, hidden, skipped and repeated IDs.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

REPO = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
BASELINE = 'c16e121365b7c52c0b66371381c8c58f592e1d8e'
KINDS = ['format', 'core-analyze', 'transport-analyze', 'ui-analyze', 'studio-analyze',
         'core', 'transport', 'transport-node', 'ui', 'studio', 'incoming-spacy', 'studio-paths']


def now():
    return datetime.now(timezone.utc).isoformat()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO).decode().strip()


def digest_file(path):
    hasher = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            hasher.update(block)
    return hasher.hexdigest()


def canonical_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def source_manifest(runtime):
    raw = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard',
         '--', 'packages', 'third_party'], cwd=REPO)
    paths = set(raw.decode().split('\0')) - {''}
    paths.update(['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.fvmrc'])
    # Documentation/evidence are not product inputs for these selected suites.
    paths = {p for p in paths if not set(Path(p).parts) &
             {'doc', 'docs', '.dart_tool', 'build', '.git'}}
    files = {}
    for relative in sorted(paths):
        path = REPO / relative
        if path.is_symlink():
            data = os.readlink(path).encode()
            files[relative] = {'sha256': hashlib.sha256(data).hexdigest(),
                               'kind': 'symlink', 'bytes': len(data)}
        elif path.is_file():
            files[relative] = {'sha256': digest_file(path),
                               'kind': 'file', 'bytes': path.stat().st_size,
                               'mode': path.stat().st_mode & 0o777}
        else:
            raise RuntimeError('Missing product input: ' + relative)
    pinned = {}
    for label, path in runtime.items():
        pinned[label] = {'path': str(path), 'sha256': digest_file(path),
                         'bytes': path.stat().st_size}
    manifest = {'files': files, 'pinned_inputs': pinned}
    return {'captured_at': now(), 'file_count': len(files),
            'aggregate_sha256': canonical_digest(manifest), **manifest}


def parse_tests(path, cwd, selected):
    events = []
    for line in path.read_text(errors='replace').splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            events.append(event)
    starts = {event['test']['id']: event['test'] for event in events
              if event.get('type') == 'testStart'}
    final = {event['testID']: event for event in events
             if event.get('type') == 'testDone'}
    cases = []
    for identity, event in final.items():
        if event.get('hidden'):
            continue
        info = starts.get(identity, {})
        cases.append({'id': identity, 'name': info.get('name'),
                      'suite_id': info.get('suiteID'),
                      'result': event.get('result'),
                      'skipped': bool(event.get('skipped'))})
    loaded = set()
    for event in events:
        if event.get('type') != 'suite':
            continue
        source = Path(event['suite']['path'])
        if not source.is_absolute():
            source = cwd / source
        loaded.add(str(source.resolve().relative_to(REPO)))
    expected = {str((cwd / relative).resolve().relative_to(REPO))
                for relative in selected}
    errors = [event for event in events if event.get('type') == 'error']
    successes = [event for event in events if event.get('type') == 'done']
    return {'completed': bool(successes) and successes[-1].get('success') is True,
            'passed': sum(case['result'] == 'success' and not case['skipped']
                          for case in cases),
            'failed': sum(case['result'] != 'success' and not case['skipped']
                          for case in cases),
            'skipped': sum(case['skipped'] for case in cases),
            'hidden_skips': sum(bool(event.get('hidden')) and
                                bool(event.get('skipped'))
                                for event in final.values()),
            'selected_suites': len(expected), 'loaded_suites': len(loaded),
            'missing_suites': sorted(expected - loaded),
            'unexpected_suites': sorted(loaded - expected),
            'errors': errors, 'cases': cases}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--attempt', required=True)
    parser.add_argument('--only', choices=KINDS, action='append')
    args = parser.parse_args()
    if not args.attempt.replace('-', '').replace('_', '').isalnum():
        raise SystemExit('Use a simple attempt name.')
    out = HERE / args.attempt
    out.mkdir(exist_ok=False)
    sdk = Path(os.environ['FLUTTER_ROOT'])
    cache = Path(os.environ['PUB_CACHE'])
    dart = Path(shutil.which('dart') or '')
    flutter = Path(shutil.which('flutter') or '')
    runner = cache / 'hosted/pub.dev/test-1.31.1/bin/test.dart'
    configuration = REPO / '.dart_tool/package_config.json'
    runtime = {'dart': sdk / 'bin/cache/dart-sdk/bin/dart',
               'flutter_tester': sdk / 'bin/cache/artifacts/engine/linux-x64/flutter_tester',
               'flutter_tools_snapshot': sdk / 'bin/cache/flutter_tools.snapshot',
               'sqlite3_native': REPO / '.dart_tool/lib/libsqlite3.so',
               'package_configuration': configuration,
               'package_graph': REPO / '.dart_tool/package_graph.json',
               'package_test_entry': runner}
    head = git('rev-parse', 'HEAD')
    record = {'schema_version': 1, 'started_at': now(), 'head': head,
              'git_tree': git('rev-parse', 'HEAD^{tree}'),
              'initial_status': git('status', '--short'),
              'runner_sha256': digest_file(Path(__file__)),
              'platform': 'Linux x64; Flutter VM and Node portable boundary',
              'github_actions_used': False, 'runs': [], 'status': 'running'}
    receipt = out / 'receipt.json'
    write_json(receipt, record)
    before = source_manifest(runtime)
    write_json(out / 'inputs-before.json', before)
    record['inputs_before_sha256'] = before['aggregate_sha256']
    record['product_input_count'] = before['file_count']
    print(json.dumps({'phase': 'inputs-captured', 'files': before['file_count'],
                      'head': head, 'sha256': before['aggregate_sha256']}), flush=True)

    changed = git('diff', '--name-only', BASELINE, 'HEAD', '--', '*.dart').splitlines()
    changed_mail = [relative for relative in changed if
                    relative.startswith(('packages/quds_mail_core/',
                                         'packages/quds_mail_transport/',
                                         'packages/quds_mail_ui/')) or
                    relative.startswith('packages/quds_office_editor/example/') and
                    (Path(relative).name.startswith('studio_mail') or
                     relative.endswith('test/support/mail_draft_store.dart'))]
    studio = REPO / 'packages/quds_office_editor/example'
    studio_changed = [str((REPO / relative).relative_to(studio))
                      for relative in changed_mail if
                      relative.startswith('packages/quds_office_editor/example/')]
    core = REPO / 'packages/quds_mail_core'
    transport = REPO / 'packages/quds_mail_transport'
    ui = REPO / 'packages/quds_mail_ui'
    spacy = REPO / 'packages/quds_proofing_spacy'
    def tests_in(package):
        return sorted(str(p.relative_to(package)) for p in
                      (package / 'test').rglob('*_test.dart'))
    core_tests = tests_in(core)
    node_transport = ['test/unsupported_test.dart', 'test/ews_unsupported_test.dart',
                      'test/cloud_unsupported_test.dart']
    transport_tests = [p for p in tests_in(transport) if p not in node_transport]
    ui_tests = tests_in(ui)
    studio_tests = sorted(str(p.relative_to(studio)) for p in
                          (studio / 'test').glob('studio_mail*_test.dart'))
    studio_tests += ['test/studio_saved_mail_test.dart']
    spacy_tests = ['test/distribution_test.dart', 'test/grammar_planner_test.dart']
    path_tests = ['test/studio_native_paths_test.dart']
    prefix = [str(dart), '--packages=' + str(configuration), str(runner)]
    flutter_prefix = [str(flutter), 'test', '--no-pub', '--reporter=json', '--concurrency=1']
    jobs = {
        'format': (REPO, [str(dart), 'format', '--output=none',
                          '--set-exit-if-changed', *changed_mail], []),
        'core-analyze': (core, [str(dart), 'analyze', '--fatal-infos'], []),
        'transport-analyze': (transport, [str(dart), 'analyze', '--fatal-infos'], []),
        'ui-analyze': (ui, [str(dart), 'analyze', '--fatal-infos'], []),
        'studio-analyze': (studio, [str(dart), 'analyze', '--fatal-infos',
                                    *studio_changed], []),
        'core': (core, [*prefix, '--reporter=json', '--concurrency=4',
                       *core_tests], core_tests),
        'transport': (transport, [*prefix, '--reporter=json', '--concurrency=2',
                         *transport_tests], transport_tests),
        'transport-node': (transport, [*prefix, '--platform=node', '--reporter=json',
                              *node_transport], node_transport),
        'ui': (ui, [*flutter_prefix, *ui_tests], ui_tests),
        'studio': (studio, [*flutter_prefix, *studio_tests], studio_tests),
        'incoming-spacy': (spacy, [*prefix, '--reporter=json', '--concurrency=2',
                                 *spacy_tests], spacy_tests),
        'studio-paths': (studio, [*flutter_prefix, *path_tests], path_tests),
    }
    selected_jobs = args.only or KINDS
    write_json(out / 'selection.json', {
        'jobs': selected_jobs, 'format_targets': changed_mail,
        'studio_analysis_targets': studio_changed,
        'test_files': {name: jobs[name][2] for name in selected_jobs if jobs[name][2]},
        'platform_selection': 'Three @TestOn(js) transport boundary suites execute separately on Node. '
                              'All other transport suites execute on VM. UI, Studio and native-path '
                              'test suites execute on Flutter VM on Linux x64.'})
    try:
        for name in selected_jobs:
            cwd, command, selected = jobs[name]
            print('START ' + name, flush=True)
            stdout = out / (name + '.jsonl' if selected else name + '.stdout')
            stderr = out / (name + '.stderr')
            start = time.monotonic()
            with stdout.open('wb') as output, stderr.open('wb') as errors:
                try:
                    process = subprocess.run(command, cwd=cwd, env=os.environ,
                                             stdout=output, stderr=errors, timeout=600)
                    code = process.returncode
                except subprocess.TimeoutExpired:
                    code = 'timeout'
            run = {'name': name, 'command': command,
                   'cwd': str(cwd.relative_to(REPO)) or '.', 'exit_code': code,
                   'elapsed_seconds': time.monotonic() - start,
                   'stdout': stdout.name, 'stderr': stderr.name,
                   'stdout_sha256': digest_file(stdout),
                   'stderr_sha256': digest_file(stderr), 'accepted': code == 0}
            if selected:
                tests = parse_tests(stdout, cwd, selected)
                cases = tests.pop('cases')
                write_json(out / (name + '-cases.json'), cases)
                run['tests'] = tests
                run['accepted'] = (code == 0 and tests['completed'] and
                    tests['passed'] > 0 and tests['failed'] == 0 and
                    tests['skipped'] == 0 and tests['hidden_skips'] == 0 and
                    not tests['missing_suites'] and not tests['unexpected_suites'] and
                    not tests['errors'])
            record['runs'].append(run)
            write_json(receipt, record)
            print(json.dumps({'name': name, 'exit_code': code,
                              'accepted': run['accepted'],
                              'tests': {k: v for k, v in run.get('tests', {}).items()
                                        if k != 'errors'}}), flush=True)
            if not run['accepted']:
                record['status'] = 'failed'
                break
        else:
            record['status'] = 'passed'
    finally:
        after = source_manifest(runtime)
        write_json(out / 'inputs-after.json', after)
        record['inputs_after_sha256'] = after['aggregate_sha256']
        record['source_unchanged'] = (before['aggregate_sha256'] ==
                                      after['aggregate_sha256'])
        changed_inputs = []
        for key in ['files', 'pinned_inputs']:
            for path in sorted(set(before[key]) | set(after[key])):
                if before[key].get(path) != after[key].get(path):
                    changed_inputs.append(key + ':' + path)
        record['changed_inputs'] = changed_inputs
        record['final_head'] = git('rev-parse', 'HEAD')
        record['final_status'] = git('status', '--short')
        record['finished_at'] = now()
        record['passed_test_executions'] = sum(
            run.get('tests', {}).get('passed', 0)
            for run in record['runs'] if run['accepted'])
        record['accepted'] = record['status'] == 'passed' and record['source_unchanged']
        if not record['source_unchanged']:
            record['status'] = 'source-changed'
        write_json(receipt, record)
        print(json.dumps({'status': record['status'], 'accepted': record['accepted'],
                          'passed_test_executions': record['passed_test_executions'],
                          'changed_inputs': changed_inputs}), flush=True)
    return 0 if record['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
