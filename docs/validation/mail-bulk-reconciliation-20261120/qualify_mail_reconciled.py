#!/usr/bin/env python3
"""Qualify the reconciled Mail tree with pinned local Dart and Flutter runtimes.

Run only after the owner has frozen a clean checkout at a published remote SHA.
This runner does not resolve dependencies, edit tracked files, or access CI.
"""
import argparse
import collections
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse

import yaml


BASE = Path('/workspace/scratch/03cd41fa0e7e')
STUDIO_LIBS = [
    'lib/studio_mail_bulk_status.dart',
    'lib/studio_mail_native.dart',
    'lib/studio_mail_ews.dart',
    'lib/studio_mail_message_loader.dart',
    'lib/studio_mail_workspace_strings.dart',
]
STUDIO_TESTS = [
    'test/studio_mail_workspace_test.dart',
    'test/studio_mail_ews_test.dart',
    'test/studio_mail_bulk_provider_test.dart',
    'test/studio_mail_message_loader_test.dart',
    'test/studio_mail_cloud_test.dart',
    'test/studio_mail_cached_mail_test.dart',
    'test/studio_mail_bulk_visual_test.dart',
]
TRANSPORT_NODE = [
    'test/unsupported_test.dart',
    'test/cloud_unsupported_test.dart',
    'test/ews_unsupported_test.dart',
]
GATES = [
    'format', 'core-tests', 'transport-tests', 'transport-node', 'ui-tests',
    'studio-tests', 'ui-visual-tests', 'core-analysis', 'transport-analysis',
    'ui-analysis', 'studio-analysis', 'editor-font-analysis',
]


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(path):
    checksum = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            checksum.update(chunk)
    return checksum.hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def manifest(paths, base):
    result = {}
    for path in sorted(set(Path(p).resolve() for p in paths)):
        key = str(path.relative_to(base)) if path.is_relative_to(base) else str(path)
        result[key] = {'sha256': digest(path), 'bytes': path.stat().st_size}
    return result


def manifest_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def test_report(stdout, package, repo, expected, platform):
    events = []
    non_json_lines = []
    for number, line in enumerate(stdout.read_text(errors='replace').splitlines(), 1):
        try:
            event = json.loads(line)
        except ValueError:
            if line.strip():
                non_json_lines.append(number)
            continue
        if isinstance(event, dict) and isinstance(event.get('type'), str):
            events.append(event)
    suites = {e['suite']['id']: e['suite'] for e in events if e['type'] == 'suite'}
    starts = {e['test']['id']: e['test'] for e in events if e['type'] == 'testStart'}
    ends = {e['testID']: e for e in events if e['type'] == 'testDone'}
    occurrences = collections.Counter()
    cases = []
    incomplete_metadata = []

    def resolve_suite(path):
        if path.startswith('file:'):
            file = Path(unquote(urlparse(path).path))
        else:
            file = Path(path)
        if not file.is_absolute():
            file = package / file
        file = file.resolve()
        return str(file.relative_to(repo))

    loaded = {resolve_suite(s['path']) for s in suites.values()}
    for identity, end in ends.items():
        if end.get('hidden'):
            continue
        start = starts.get(identity)
        if start is None or start['suiteID'] not in suites:
            incomplete_metadata.append(identity)
            continue
        file = resolve_suite(suites[start['suiteID']]['path'])
        key = (file, start['name'])
        occurrences[key] += 1
        cases.append({
            'file': file, 'name': start['name'], 'occurrence': occurrences[key],
            'platform': platform, 'result': end['result'],
            'skipped': bool(end.get('skipped')),
        })
    per_file = {}
    for case in cases:
        row = per_file.setdefault(case['file'], {'passed': 0, 'failed': 0, 'skipped': 0})
        category = 'skipped' if case['skipped'] else 'passed' if case['result'] == 'success' else 'failed'
        row[category] += 1
    expected_paths = {str((package / path).relative_to(repo)) for path in expected}
    terminal = [e for e in events if e['type'] == 'done']
    errors = [e for e in events if e['type'] == 'error']
    summary = {
        'selected_suites': len(expected_paths), 'loaded_suites': len(loaded),
        'missing_suites': sorted(expected_paths - loaded),
        'unexpected_suites': sorted(loaded - expected_paths),
        'passed': sum(r['passed'] for r in per_file.values()),
        'failed': sum(r['failed'] for r in per_file.values()),
        'skipped': sum(r['skipped'] for r in per_file.values()),
        'reporter_errors': len(errors), 'errors': errors,
        'terminal_success': bool(terminal and terminal[-1].get('success') is True),
        'terminal_events': len(terminal),
        'incomplete_case_metadata': incomplete_metadata,
        'unfinished_test_ids': sorted(set(starts) - set(ends)),
        'non_json_stdout_lines': non_json_lines,
        'per_file': per_file,
    }
    summary['accepted'] = bool(
        summary['terminal_success'] and summary['passed'] and not summary['failed']
        and not summary['skipped'] and not errors and not incomplete_metadata
        and not summary['missing_suites'] and not summary['unexpected_suites']
        and not summary['unfinished_test_ids']
    )
    return summary, cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=BASE / 'quds_mail_integration')
    parser.add_argument('--runtime', type=Path, default=BASE / 'runtime/flutter-toolchain')
    parser.add_argument('--out', type=Path, default=BASE / 'runtime/mail-final-qualification')
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--format-base', default='cb5909fefe6dd41db0f9c38207db83166072dcaf')
    parser.add_argument('--only', choices=GATES, action='append')
    parser.add_argument('--studio-test', choices=STUDIO_TESTS, action='append',
                        help='Restrict Studio execution for a documented focused rerun; analysis keeps its full scope.')
    parser.add_argument('--command-timeout', type=int, default=1200)
    args = parser.parse_args()
    repo, runtime, out = args.repo.resolve(), args.runtime.resolve(), args.out.resolve()

    def git(*arguments):
        return subprocess.check_output(['git', '-C', str(repo), *arguments], text=True).strip()

    if not re.fullmatch(r'[0-9a-f]{40}', args.expected_head):
        parser.error('--expected-head must be the exact published 40-character remote SHA.')
    if git('rev-parse', 'HEAD') != args.expected_head:
        raise SystemExit('Checkout does not match the published source freeze.')
    if git('status', '--porcelain'):
        raise SystemExit('Require a clean frozen checkout before final qualification.')

    sdk = runtime / 'flutter'
    dart = sdk / 'bin/cache/dart-sdk/bin/dart'
    flutter = [dart, sdk / 'bin/cache/flutter_tools.snapshot', '--no-version-check']
    kernel = runtime / 'test-runner/test-runner.dill'
    config = repo / '.dart_tool/package_config.json'
    native_manifest = repo / '.dart_tool/native_assets.yaml'
    sqlite = repo / '.dart_tool/lib/libsqlite3.so'
    for required in [dart, kernel, config, native_manifest, sqlite]:
        if not required.is_file():
            raise SystemExit(f'Runtime preparation is incomplete: {required}')
    if digest(sqlite) != '0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b':
        raise SystemExit('Native SQLite differs from the pinned 3.9.1 build-hook artifact.')

    out.mkdir(parents=True, exist_ok=False)
    for name in ['tmp', 'config', 'cache', 'data', 'screenshots/ui', 'screenshots/studio']:
        (out / name).mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ)
    environment.update({
        'FLUTTER_ROOT': str(sdk), 'PUB_CACHE': str(runtime / 'pub-cache'),
        'TMPDIR': str(out / 'tmp'), 'XDG_CONFIG_HOME': str(out / 'config'),
        'XDG_CACHE_HOME': str(out / 'cache'), 'XDG_DATA_HOME': str(out / 'data'),
        'CI': 'true', 'DART_SUPPRESS_ANALYTICS': 'true',
        'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'DASH__SUPPRESS_ANALYTICS': 'true',
        'MAIL_BULK_UI_EVIDENCE': str(out / 'screenshots/ui'),
        'PATH': str(runtime / 'bin') + os.pathsep + environment['PATH'],
    })
    selected = list(dict.fromkeys(args.only or GATES))
    studio_tests = list(dict.fromkeys(args.studio_test or STUDIO_TESTS))
    package_paths = {name: repo / 'packages' / ('quds_mail_' + name)
                     for name in ['core', 'transport', 'ui']}
    package_paths['studio'] = repo / 'packages/quds_office_editor/example'
    tests = {name: sorted(str(p.relative_to(path)) for p in (path / 'test').rglob('*_test.dart'))
             for name, path in package_paths.items() if name != 'studio'}
    node_tests = sorted(TRANSPORT_NODE)
    assert set(node_tests) <= set(tests['transport'])
    transport_vm = [p for p in tests['transport'] if p not in node_tests]
    changed = git('diff', '--name-only', args.format_base, 'HEAD', '--', '*.dart').splitlines()
    mail_prefixes = tuple(f'packages/quds_mail_{n}/' for n in ['core', 'transport', 'ui'])
    studio_prefix = 'packages/quds_office_editor/example/'
    changed_dart = [p for p in changed if (repo / p).is_file() and
                    (p.startswith(mail_prefixes) or p.startswith(studio_prefix))]

    source_paths = [repo / p for p in git('ls-files', 'packages', 'apps', 'third_party',
                    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.fvmrc').splitlines()
                    if (repo / p).is_file()]
    source_before = manifest(source_paths, repo)
    write_json(out / 'source-before.json', source_before)

    package_configuration = json.loads(config.read_text())
    workspace_manifest = yaml.safe_load((repo / 'pubspec.yaml').read_text())
    locked_packages = yaml.safe_load((repo / 'pubspec.lock').read_text())['packages']
    expected_local_roots = {workspace_manifest['name']: repo}
    for relative in workspace_manifest['workspace']:
        package = (repo / relative).resolve()
        name = yaml.safe_load((package / 'pubspec.yaml').read_text())['name']
        expected_local_roots[name] = package
    for name, lock in locked_packages.items():
        if lock['source'] == 'path':
            expected_local_roots[name] = (repo / lock['description']['path']).resolve()
    archived_packages = {(p['name'], p['version']): p
                         for p in json.loads((runtime / 'pub-cache-receipt.json').read_text())}
    dependency_roots = []
    resolved_packages = []
    hosted_lock_verification = []
    for entry in package_configuration['packages']:
        root = Path(unquote(urlparse(urljoin(config.as_uri(), entry['rootUri'])).path)).resolve()
        if not root.is_relative_to(repo) and not root.is_relative_to(runtime):
            raise RuntimeError(f'Unexpected configured dependency root: {root}')
        name = entry['name']
        if name in expected_local_roots:
            if root != expected_local_roots[name]:
                raise RuntimeError(f'{name} does not map to its canonical directory in this checkout.')
        else:
            lock = locked_packages[name]
            if lock['source'] == 'hosted':
                version = lock['version']
                expected = runtime / 'pub-cache/hosted/pub.dev' / f'{name}-{version}'
                if root != expected:
                    raise RuntimeError(f'{name} does not map to its locked hosted version.')
                archive = archived_packages[(name, version)]
                recorded_hash = lock['description']['sha256']
                cache_hash = (runtime / 'pub-cache/hosted-hashes/pub.dev' / f'{name}-{version}.sha256').read_text().strip()
                if not archive['verified'] or archive['sha256'] != recorded_hash or cache_hash != recorded_hash:
                    raise RuntimeError(f'{name} does not match its verified lockfile archive hash.')
                hosted_lock_verification.append({'name': name, 'version': version,
                    'archive_sha256': recorded_hash, 'verified': True})
            elif lock['source'] == 'sdk':
                allowed = [sdk / 'packages' / name, sdk / 'bin/cache/pkg' / name]
                if root not in allowed:
                    raise RuntimeError(f'{name} does not map to its canonical Flutter SDK package.')
            else:
                raise RuntimeError(f'Unrecognized dependency source for {name}: {lock["source"]}')
        resolved_packages.append({**entry, 'resolved_root': str(root)})
        if root.is_relative_to(repo):
            continue
        dependency_roots.append(root)
    if not set(expected_local_roots) <= {entry['name'] for entry in resolved_packages}:
        raise RuntimeError('A workspace/path package is missing from the configuration.')

    def dependency_paths():
        result = []
        for root in dependency_roots:
            for dirname in ['lib', 'bin', 'hook', 'shaders']:
                directory = root / dirname
                if directory.is_dir():
                    result.extend(p for p in directory.rglob('*') if p.is_file())
            result.extend(root / name for name in ['pubspec.yaml', 'pubspec.lock']
                          if (root / name).is_file())
        return result

    dependency_before = manifest(dependency_paths(), runtime)
    write_json(out / 'dependencies-before.json', dependency_before)
    write_json(out / 'resolved-packages.json', resolved_packages)
    write_json(out / 'hosted-lock-verification.json', hosted_lock_verification)

    runtime_paths = [dart, dart.parent / 'dartaotruntime', kernel,
        sdk / 'bin/cache/flutter_tools.snapshot',
        sdk / 'bin/cache/artifacts/engine/linux-x64/flutter_tester',
        sdk / 'bin/cache/artifacts/engine/linux-x64/frontend_server_aot.dart.snapshot',
        sdk / 'bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill',
        sdk / 'bin/cache/dart-sdk/lib/_internal/vm_platform_strong.dill',
        config, repo / '.dart_tool/package_graph.json', native_manifest, sqlite,
        runtime / 'runtime.json', runtime / 'pub-cache-receipt.json',
        runtime / 'sqlite-readiness.json', runtime / 'sqlite-readiness.log',
        runtime / 'sqlite_probe.dart', Path(__file__).resolve(),
    ]
    runtime_paths.extend((dart.parent / 'snapshots').glob('*aot.dart.snapshot'))
    runtime_paths.extend(p for p in (sdk / 'bin/cache/artifacts/material_fonts').rglob('*') if p.is_file())
    runtime_before = manifest(runtime_paths, BASE)
    write_json(out / 'runtime-before.json', runtime_before)
    shutil.copyfile(Path(__file__), out / 'qualification-runner.py')

    record = {
        'schema_version': 1, 'started_utc': now(), 'status': 'running',
        'source_head': args.expected_head, 'source_tree': git('rev-parse', 'HEAD^{tree}'),
        'format_base': git('rev-parse', args.format_base),
        'runner_argv': sys.argv, 'runner_sha256': digest(__file__),
        'github_actions_used': False,
        'dart_version': subprocess.check_output([dart, '--version'], env=environment, text=True).strip(),
        'node_version': subprocess.check_output(['node', '--version'], env=environment, text=True).strip(),
        'flutter_runtime': json.loads((runtime / 'runtime.json').read_text())['runtime'],
        'source_file_count': len(source_before), 'dependency_file_count': len(dependency_before),
        'canonical_workspace_packages_verified': len(expected_local_roots),
        'locked_hosted_archives_verified': len(hosted_lock_verification),
        'source_before_sha256': manifest_digest(source_before),
        'dependencies_before_sha256': manifest_digest(dependency_before),
        'runtime_before_sha256': manifest_digest(runtime_before),
        'selected_gates': selected,
        'full_default_scope': selected == GATES and not args.studio_test,
        'studio_test_selection': studio_tests,
        'changed_dart_files': changed_dart, 'commands': [], 'test_results': {},
        'environment': {k: environment[k] for k in ['FLUTTER_ROOT', 'PUB_CACHE', 'TMPDIR',
            'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'CI',
            'DART_SUPPRESS_ANALYTICS', 'FLUTTER_SUPPRESS_ANALYTICS',
            'DASH__SUPPRESS_ANALYTICS', 'MAIL_BULK_UI_EVIDENCE']},
    }
    write_json(out / 'progress.json', record)
    print(json.dumps({'phase': 'frozen-inputs-captured', 'head': args.expected_head,
                      'sources': len(source_before), 'dependencies': len(dependency_before)}), flush=True)

    test_cases = []
    runner_prefix = [dart, '--old_gen_heap_size=1024', f'--packages={config}', kernel]
    vm_options = ['--compiler=kernel', '--concurrency=1', '--timeout=4x', '--reporter=json']
    flutter_options = ['test', '--no-pub', '--concurrency=1', '--timeout=4x', '--reporter=json']
    plan = {
        'format': (repo, [dart, 'format', '--output=none', '--set-exit-if-changed',
                         *changed_dart], None, None),
        'core-tests': (package_paths['core'], [*runner_prefix, *vm_options, *tests['core']], tests['core'], 'vm'),
        'transport-tests': (package_paths['transport'], [*runner_prefix, *vm_options, *transport_vm], transport_vm, 'vm'),
        'transport-node': (package_paths['transport'], [*runner_prefix, '--platform=node',
            '--compiler=dart2js', '--concurrency=1', '--timeout=4x', '--reporter=json', *node_tests], node_tests, 'node'),
        'ui-tests': (package_paths['ui'], [*flutter, *flutter_options, *tests['ui']], tests['ui'], 'flutter-vm'),
        'studio-tests': (package_paths['studio'], [*flutter, *flutter_options,
            '--dart-define=MAIL_BULK_SCREENSHOT_DIR=' + str(out / 'screenshots/studio'), *studio_tests], studio_tests, 'flutter-vm'),
        'ui-visual-tests': (package_paths['ui'], [*flutter, *flutter_options,
            'tool/bulk_flags_visual_test.dart'], ['tool/bulk_flags_visual_test.dart'], 'flutter-vm'),
        'core-analysis': (package_paths['core'], [dart, 'analyze', '--fatal-infos'], None, None),
        'transport-analysis': (package_paths['transport'], [dart, 'analyze', '--fatal-infos'], None, None),
        'ui-analysis': (package_paths['ui'], [dart, 'analyze',
            '--fatal-infos', '--fatal-warnings', 'lib', 'test', 'tool'], None, None),
        'studio-analysis': (package_paths['studio'], [dart, 'analyze',
            '--fatal-infos', '--fatal-warnings', *STUDIO_LIBS, *STUDIO_TESTS], None, None),
        'editor-font-analysis': (repo / 'packages/quds_office_editor',
            [dart, 'analyze', '--fatal-infos', '--fatal-warnings',
             'lib/src/embed/office_system_fonts_io.dart'], None, None),
    }

    for name in selected:
        cwd, command, expected, platform = plan[name]
        command = [str(p) for p in command]
        stdout = out / (name + ('.jsonl' if expected else '.log'))
        stderr = out / (name + '.stderr')
        row = {'name': name, 'command': command, 'cwd': str(cwd), 'started_utc': now(),
               'stdout': stdout.name, 'stderr': stderr.name,
               'expected_test_files': expected, 'platform': platform}
        record['commands'].append(row)
        write_json(out / 'progress.json', record)
        start = time.monotonic()
        last_heartbeat = start
        print(json.dumps({'phase': 'starting', 'gate': name}), flush=True)
        with stdout.open('w') as output, stderr.open('w') as errors:
            process = subprocess.Popen(command, cwd=cwd, env=environment,
                stdout=output, stderr=errors, start_new_session=True)
            row['pid'] = process.pid
            try:
                while process.poll() is None:
                    elapsed = time.monotonic() - start
                    if elapsed > args.command_timeout:
                        row['timeout'] = True
                        os.killpg(process.pid, signal.SIGTERM)
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait()
                        break
                    if time.monotonic() - last_heartbeat >= 30:
                        print(json.dumps({'phase': 'running', 'gate': name,
                            'elapsed_seconds': round(elapsed, 1),
                            'stdout_bytes': stdout.stat().st_size,
                            'stderr_bytes': stderr.stat().st_size}), flush=True)
                        last_heartbeat = time.monotonic()
                    time.sleep(0.5)
            except BaseException:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                row['interrupted'] = True
                row['exit_code'] = process.returncode
                record['status'] = 'interrupted'
                write_json(out / 'progress.json', record)
                raise
        row.update({'finished_utc': now(), 'exit_code': process.returncode,
                    'seconds': round(time.monotonic() - start, 3),
                    'stdout_sha256': digest(stdout), 'stderr_sha256': digest(stderr)})
        if expected:
            summary, cases = test_report(stdout, cwd, repo, expected, platform)
            summary['accepted'] = summary['accepted'] and row['exit_code'] == 0
            record['test_results'][name] = summary
            test_cases.extend(cases)
            write_json(out / (name + '-cases.json'), cases)
            print(json.dumps({'phase': 'completed', 'gate': name,
                'exit_code': row['exit_code'], 'passed': summary['passed'],
                'failed': summary['failed'], 'skipped': summary['skipped'],
                'accepted': summary['accepted']}), flush=True)
        else:
            print(json.dumps({'phase': 'completed', 'gate': name,
                              'exit_code': row['exit_code']}), flush=True)
        write_json(out / 'progress.json', record)

    source_after = manifest(source_paths, repo)
    dependency_after = manifest(dependency_paths(), runtime)
    runtime_after = manifest(runtime_paths, BASE)
    write_json(out / 'source-after.json', source_after)
    write_json(out / 'dependencies-after.json', dependency_after)
    write_json(out / 'runtime-after.json', runtime_after)
    write_json(out / 'test-cases.json', test_cases)
    images = manifest((out / 'screenshots').rglob('*.png'), out)
    write_json(out / 'screenshots.json', images)
    record.update({
        'finished_utc': now(), 'source_unchanged': source_before == source_after,
        'dependencies_unchanged': dependency_before == dependency_after,
        'runtime_unchanged': runtime_before == runtime_after,
        'source_head_after': git('rev-parse', 'HEAD'),
        'source_tree_after': git('rev-parse', 'HEAD^{tree}'),
        'git_status_after': git('status', '--porcelain'),
        'passed': sum(r['passed'] for r in record['test_results'].values()),
        'failed': sum(r['failed'] for r in record['test_results'].values()),
        'skipped': sum(r['skipped'] for r in record['test_results'].values()),
        'suite_count': sum(r['selected_suites'] for r in record['test_results'].values()),
        'screenshots': images,
    })
    stable = record['source_unchanged'] and record['dependencies_unchanged'] and record['runtime_unchanged']
    frozen = record['source_head_after'] == args.expected_head and not record['git_status_after']
    successful = all(r['exit_code'] == 0 for r in record['commands']) and all(
        r['accepted'] for r in record['test_results'].values())
    record['status'] = 'passed' if stable and frozen and successful else 'failed'
    write_json(out / 'qualification.json', record)
    write_json(out / 'progress.json', record)
    print(json.dumps({k: record[k] for k in ['status', 'passed', 'failed', 'skipped',
        'suite_count', 'source_unchanged', 'dependencies_unchanged', 'runtime_unchanged']}), flush=True)
    return 0 if record['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
