#!/usr/bin/env python3
"""Run the exact final spelling regressions on an isolated immutable Git baseline.

Only baseline libraries, manifests, declared assets and configuration are
materialized. Four final regression files are the only newer workspace inputs.
The baseline never links production source to the final checkout.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse

import yaml

BASE = '4dceb86e9fae51877bb5b7dc01e7a8bc721cb6ea'
FINAL = 'fb1fd4dc3edda824c3e043c035dbfad1f0fe0869'
LOCK = 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
TESTS = {
    'engine': ['packages/quds_office_engine/test/proofing/german_spelling_projection_test.dart'],
    'editor': [
        'packages/quds_office_editor/test/platform_spelling_identifiers_test.dart',
        'packages/quds_office_editor/test/platform_spelling_identifier_review_test.dart',
        'packages/quds_office_editor/test/platform_spelling_vocabulary_unicode_test.dart',
    ],
}


def now():
    return datetime.now(timezone.utc).isoformat()


def fingerprint(path):
    sha = hashlib.sha256()
    git_blob = hashlib.sha1()
    size = path.stat().st_size
    git_blob.update(b'blob ' + str(size).encode() + b'\0')
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(block)
            git_blob.update(block)
    return {'bytes': size, 'sha256': sha.hexdigest(), 'git_blob_sha1': git_blob.hexdigest()}


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def execute(command, cwd, env, out, limit=600):
    out.mkdir(parents=True, exist_ok=True)
    began = time.monotonic()
    timed_out = False
    with (out / 'stdout.log').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
        proc = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            code = proc.wait(timeout=limit)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                code = proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                code = proc.wait()
    value = {'command': [str(x) for x in command], 'cwd': str(cwd), 'actual_process_exit_code': code,
             'timed_out': timed_out, 'elapsed_seconds': time.monotonic() - began,
             'finished_at_utc': now(), 'stdout': fingerprint(out / 'stdout.log'), 'stderr': fingerprint(out / 'stderr.log')}
    write(out / 'process-exit.json', value)
    return value


def parse_events(out, workspace, selected, cwd):
    events, parse_errors, envelopes = [], [], []
    for number, line in enumerate((out / 'stdout.log').read_text().splitlines(), 1):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            parse_errors.append({'line': number, 'text': line})
            continue
        if isinstance(value, dict) and value.get('type'):
            events.append(value)
        else:
            envelopes.append({'line': number, 'value': value})
    write(out / 'machine-envelopes.json', envelopes)
    starts = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
    suites = {e['suite']['id']: e['suite'] for e in events if e.get('type') == 'suite'}
    finishes = [e for e in events if e.get('type') == 'testDone']
    errors = [e for e in events if e.get('type') == 'error']
    dones = [e for e in events if e.get('type') == 'done']
    selected_paths = {str((workspace / p).resolve()) for p in selected}

    def suite_path(test):
        path = suites.get(test.get('suiteID'), {}).get('path')
        if path is None:
            return None
        value = str((cwd / path).resolve())
        return value

    cases, excluded = [], []
    for done in finishes:
        test = starts.get(done['testID'], {})
        error_events = [e for e in errors if e.get('testID') == done['testID']]
        prints = [e for e in events if e.get('type') == 'print' and e.get('testID') == done['testID']]
        case = {'id': done['testID'], 'name': test.get('name'), 'suite': suite_path(test),
                'result': done['result'], 'skipped': done.get('skipped', False),
                'error_events': error_events, 'print_events': prints}
        hidden = done.get('hidden') or test.get('name', '').endswith(('(setUpAll)', '(tearDownAll)'))
        if hidden:
            excluded.append(case)
            continue
        # An assertion inside an identified test is a behavioral failure.
        # StateError from .single on a changed finding list is also behavioral
        # when its stack contains the exact test file. Everything else remains
        # unclassified until independently inspected; no expected count forces it.
        if done['result'] == 'success':
            case['classification'] = 'passed'
        elif error_events and suite_path(test) in selected_paths:
            kinds = []
            for e in error_events:
                message, stack = e.get('error', ''), e.get('stackTrace', '')
                if e.get('isFailure') is True:
                    kinds.append('test-assertion')
                elif any(s in message for s in ('Bad state: Too many elements', 'Bad state: No element')) and Path(case['suite']).name in stack:
                    kinds.append('finding-cardinality-state-error')
                else:
                    kinds.append('unclassified-error')
            case['error_kinds'] = kinds
            case['classification'] = 'behavioral-nonpass' if 'unclassified-error' not in kinds else 'unclassified-nonpass'
        else:
            case['classification'] = 'unclassified-nonpass'
        cases.append(case)
    nonbehavioral_errors = [e for e in errors if not any(c['id'] == e.get('testID') and c['classification'] == 'behavioral-nonpass' for c in cases)]
    guard = {
        'all_selected_suites_executed': {str((cwd / s['path']).resolve()) for s in suites.values()} == selected_paths,
        'every_started_event_finished_once': set(starts) == {e['testID'] for e in finishes} and len(starts) == len(finishes),
        'single_completion_event': len(dones) == 1,
        'no_skipped_cases': not any(c['skipped'] for c in cases),
        'no_parse_errors': not parse_errors,
        'no_unclassified_failures': not any(c['classification'] == 'unclassified-nonpass' for c in cases),
        'no_harness_errors': not nonbehavioral_errors and all(c['result'] == 'success' for c in excluded),
        'completion_matches_cases': len(dones) == 1 and dones[0].get('success') == all(c['result'] == 'success' for c in cases),
    }
    write(out / 'cases.json', cases)
    write(out / 'excluded-events.json', excluded)
    write(out / 'raw-events.json', events)
    result = {'case_count': len(cases), 'suite_count': len(suites),
              'results': dict(Counter(c['result'] for c in cases)),
              'classifications': dict(Counter(c['classification'] for c in cases)),
              'parse_errors': parse_errors, 'nonbehavioral_errors': nonbehavioral_errors,
              'completion_events': dones, 'guards': guard}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--workspace', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--reference-workspace', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    repo, workspace, runtime, reference, out = [x.resolve() for x in (args.repo, args.workspace, args.runtime, args.reference_workspace, args.output)]
    if workspace == repo or workspace.is_relative_to(repo):
        raise RuntimeError('Baseline must be outside the product checkout.')
    out.mkdir(parents=True, exist_ok=True)
    sdk = runtime / 'flutter-sdk'
    dart = sdk / 'bin/cache/dart-sdk/bin/dart'
    flutter = sdk / 'bin/flutter'
    env = dict(os.environ, FLUTTER_ROOT=str(sdk), PUB_CACHE=str(runtime / 'pub-cache'),
               TMPDIR=str(runtime / 'tmp'), XDG_CONFIG_HOME=str(runtime / 'config'),
               CI='true', DART_SUPPRESS_ANALYTICS='true', DASH__SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true')

    def git(*argv, raw=False):
        value = subprocess.check_output(['git', *argv], cwd=repo)
        return value if raw else value.decode().strip()

    tree = {}
    for row in git('ls-tree', '-rz', BASE, raw=True).split(b'\0'):
        if row:
            metadata, name = row.split(b'\t', 1)
            mode, kind, sha = metadata.decode().split()
            if kind == 'blob':
                tree[name.decode()] = {'mode': mode, 'sha': sha}
    root_manifest = yaml.safe_load(git('show', BASE + ':pubspec.yaml'))
    members = root_manifest['workspace']
    manifests = ['pubspec.yaml'] + [m + '/pubspec.yaml' for m in members]
    selected = set(manifests)
    for member in ['', *members]:
        prefix = member + '/' if member else ''
        for name in ('analysis_options.yaml', 'dart_test.yaml'):
            if prefix + name in tree:
                selected.add(prefix + name)
        if member:
            selected.update(p for p in tree if p.startswith(prefix + 'lib/'))
            manifest = yaml.safe_load(git('show', BASE + ':' + prefix + 'pubspec.yaml'))
            for asset in manifest.get('flutter', {}).get('assets', []):
                if not isinstance(asset, str):
                    raise RuntimeError('Unsupported asset declaration')
                asset_path = prefix + asset
                selected.update(p for p in tree if p == asset_path or (asset_path.endswith('/') and p.startswith(asset_path)))
    final_tests = [p for cohort in TESTS.values() for p in cohort]
    bindings = {p: {'origin_commit': BASE, 'git_blob_sha1': tree[p]['sha']} for p in sorted(selected)}
    for path in final_tests:
        if path in tree:
            raise RuntimeError('This controlled comparison expects newly introduced regression files.')
        bindings[path] = {'origin_commit': FINAL, 'git_blob_sha1': git('rev-parse', FINAL + ':' + path)}

    prepare_receipt = out / 'preparation.json'
    if prepare_receipt.exists():
        prior = json.loads(prepare_receipt.read_text())
        if prior['bindings'] != bindings or prior['workspace'] != str(workspace):
            raise RuntimeError('Existing baseline preparation does not match this invocation.')
    else:
        if workspace.exists() and any(workspace.iterdir()):
            raise RuntimeError('Use an empty isolated workspace.')
        workspace.mkdir(parents=True, exist_ok=True)
        with subprocess.Popen(['git', 'cat-file', '--batch'], cwd=repo, stdin=subprocess.PIPE, stdout=subprocess.PIPE) as cat:
            for path, binding in bindings.items():
                cat.stdin.write((binding['git_blob_sha1'] + '\n').encode())
                cat.stdin.flush()
                object_id, kind, size = cat.stdout.readline().decode().split()
                if object_id != binding['git_blob_sha1'] or kind != 'blob':
                    raise RuntimeError('Git batch identity mismatch')
                data = cat.stdout.read(int(size))
                if cat.stdout.read(1) != b'\n':
                    raise RuntimeError('Git batch framing mismatch')
                dest = workspace / path
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
                if fingerprint(dest)['git_blob_sha1'] != binding['git_blob_sha1']:
                    raise RuntimeError('Baseline source identity mismatch')
            cat.stdin.close()
            cat.wait()
        lock_bytes = git('show', FINAL + ':' + LOCK, raw=True)
        (workspace / 'pubspec.lock').write_bytes(lock_bytes)
        assert lock_bytes == (reference / 'pubspec.lock').read_bytes()
        for path in manifests:
            assert (workspace / path).read_bytes() == git('show', FINAL + ':' + path, raw=True)
        lock = (runtime / 'flutter-cli.lock').open('a')
        print('Waiting for Flutter CLI lock for baseline dependency resolution.', flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            resolved = execute([str(flutter), 'pub', 'get', '--offline', '--enforce-lockfile'], workspace, env, out / 'resolution')
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
            lock.close()
        if resolved['actual_process_exit_code'] != 0 or resolved['timed_out']:
            raise RuntimeError('Offline baseline dependency resolution failed; receipt retained.')
        if (workspace / 'pubspec.lock').read_bytes() != lock_bytes:
            raise RuntimeError('Pinned baseline lock changed during resolution.')
        write(prepare_receipt, {'prepared_at_utc': now(), 'workspace': str(workspace), 'baseline_commit': BASE,
              'final_test_commit': FINAL, 'baseline_tree': git('rev-parse', BASE + '^{tree}'), 'bindings': bindings,
              'baseline_file_count': len(selected), 'final_test_file_count': len(final_tests), 'manifest_count': len(manifests),
              'lock_source': {'path': LOCK, 'commit': FINAL, **fingerprint(workspace / 'pubspec.lock')},
              'runner': fingerprint(Path(__file__)), 'resolution': resolved})
    config = workspace / '.dart_tool/package_config.json'
    graph = workspace / '.dart_tool/package_graph.json'
    reference_config = reference / '.dart_tool/package_config.json'
    reference_graph = reference / '.dart_tool/package_graph.json'
    assert json.loads(graph.read_text()) == json.loads(reference_graph.read_text())

    def entries(path):
        return {p['name']: {**p, 'resolved_root':str(Path(unquote(urlparse(urljoin(path.as_uri(), p['rootUri'])).path)).resolve())}
                for p in json.loads(path.read_text())['packages']}

    packages, reference_packages = entries(config), entries(reference_config)
    assert packages.keys() == reference_packages.keys()
    member_names = {yaml.safe_load((workspace / p).read_text())['name']:(workspace / p).parent.resolve() for p in manifests}
    for name, package in packages.items():
        other = reference_packages[name]
        assert (package.get('packageUri'),package.get('languageVersion')) == (other.get('packageUri'),other.get('languageVersion'))
        root = Path(package['resolved_root'])
        assert root == member_names.get(name, Path(other['resolved_root']))
        assert root.is_relative_to(workspace) or root.is_relative_to(runtime)
    if args.prepare_only:
        print(json.dumps({'status':'prepared','baseline_inputs':len(selected),'final_test_files':len(final_tests),'packages':len(packages)}),flush=True)
        return
    if (out / 'summary.json').exists():
        raise RuntimeError('Refuse to overwrite a completed run; use a fresh output directory.')

    source_paths = {p: workspace / p for p in bindings}
    def snapshot_sources():
        return {p: fingerprint(v) for p, v in source_paths.items()}
    dependencies = {}
    for name, package in packages.items():
        if name in member_names:
            continue
        root = Path(package['resolved_root'])
        files = [root / 'pubspec.yaml']
        for directory in ('lib', 'bin'):
            files.extend(p for p in (root / directory).rglob('*') if p.is_file())
        for file in files:
            if file.is_file():
                dependencies[name + '/' + str(file.relative_to(root))] = file
    def snapshot_dependencies():
        return {p: fingerprint(v) for p,v in sorted(dependencies.items())}
    runtime_paths = {'package_config':config,'package_graph':graph,'workspace_lock':workspace / 'pubspec.lock',
        'dart':dart,'dart_version':sdk / 'bin/cache/dart-sdk/version','flutter':flutter,
        'flutter_tools_snapshot':sdk / 'bin/cache/flutter_tools.snapshot',
        'flutter_tester':sdk / 'bin/cache/artifacts/engine/linux-x64/flutter_tester',
        'frontend_server_snapshot':sdk / 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot'}
    def snapshot_runtime():
        return {p:fingerprint(v) for p,v in runtime_paths.items()}
    sources_before = snapshot_sources()
    dependencies_before = snapshot_dependencies()
    runtime_before = snapshot_runtime()
    write(out / 'source-before.json',sources_before)
    write(out / 'dependencies-before.json',dependencies_before)
    write(out / 'runtime-before.json',runtime_before)
    write(out / 'package-config.json',json.loads(config.read_text()))
    write(out / 'package-graph.json',json.loads(graph.read_text()))
    start = {'started_at_utc':now(),'baseline_commit':BASE,'final_test_commit':FINAL,'workspace':str(workspace),
             'runner':fingerprint(Path(__file__)),'dart_version':subprocess.check_output([str(dart),'--version'],env=env,text=True).strip(),
             'test_files':final_tests,'package_count':len(packages),'dependency_file_count':len(dependencies),
             'historical_expected_observation':{'pass':8,'behavioral_nonpass':33,'note':'Informational expectation only; never used to coerce observed outcomes.'}}
    write(out / 'run.json', start)
    groups = {}
    for cohort, files in TESTS.items():
        group_out = out / cohort
        package_dir = 'packages/quds_office_engine' if cohort == 'engine' else 'packages/quds_office_editor'
        cwd = workspace / package_dir
        if cohort == 'engine':
            command = [str(dart),'--packages='+str(config),str(Path(packages['test']['resolved_root']) / 'bin/test.dart'),'--reporter','json','--concurrency','2']
        else:
            command = [str(flutter),'test','--no-pub','--reporter','json','--concurrency','2']
        command.extend(str(Path(p).relative_to(package_dir)) for p in files)
        lock = None
        if cohort == 'editor':
            lock = (runtime / 'flutter-cli.lock').open('a')
            print('Waiting for shared Flutter CLI lock for baseline editor tests.',flush=True)
            fcntl.flock(lock,fcntl.LOCK_EX)
            print('Acquired Flutter CLI lock for baseline editor tests.',flush=True)
        try:
            result = execute(command,cwd,env,group_out)
        finally:
            if lock:
                fcntl.flock(lock,fcntl.LOCK_UN)
                lock.close()
        parsed = parse_events(group_out,workspace,files,cwd)
        parsed['guards']['process_exit_matches_cases'] = result['actual_process_exit_code'] == (0 if parsed['classifications'].get('passed',0) == parsed['case_count'] else 1)
        parsed['guards']['not_timed_out'] = not result['timed_out']
        groups[cohort] = {**result,**parsed}
        write(group_out / 'summary.json',groups[cohort])
        print(json.dumps({'cohort':cohort,'case_count':parsed['case_count'],'classifications':parsed['classifications'],'guards':parsed['guards']}),flush=True)
    sources_after,dependencies_after,runtime_after = snapshot_sources(),snapshot_dependencies(),snapshot_runtime()
    write(out / 'source-after.json',sources_after)
    write(out / 'dependencies-after.json',dependencies_after)
    write(out / 'runtime-after.json',runtime_after)
    guards = {'all_baseline_and_test_blobs_match_pins':all(sources_before[p]['git_blob_sha1']==b['git_blob_sha1'] for p,b in bindings.items()),
              'baseline_and_test_sources_unchanged':sources_before==sources_after,
              'dependency_sources_unchanged':dependencies_before==dependencies_after,'runtime_and_configuration_unchanged':runtime_before==runtime_after,
              'all_new_tests_executed':groups['engine']['case_count']==25 and groups['editor']['case_count']==16,
              'cohorts_completed_without_harness_failure':all(all(g['guards'].values()) for g in groups.values())}
    counts=Counter()
    for group in groups.values():
        counts.update(group['classifications'])
    summary={**start,'finished_at_utc':now(),'status':'baseline-comparison-complete' if all(guards.values()) else 'needs-investigation',
             'counts':dict(counts),'case_count':sum(g['case_count'] for g in groups.values()),'guards':guards,'cohorts':groups}
    write(out / 'summary.json',summary)
    print(json.dumps({'status':summary['status'],'counts':summary['counts'],'case_count':summary['case_count'],'guards':guards},indent=2),flush=True)
    raise SystemExit(0 if all(guards.values()) else 1)


if __name__ == '__main__':
    main()
