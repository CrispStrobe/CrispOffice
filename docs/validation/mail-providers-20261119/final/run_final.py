#!/usr/bin/env python3
"""Frozen-source local Mail qualification.

Set FLUTTER_ROOT and PUB_CACHE and resolve the pinned workspace dependencies
before running. In the original workspace, activate toolchains/env.sh first.
Pass --repo and --scratch when replaying from a different working directory.

This runner never contacts GitHub/CI, edits product files, resolves dependencies,
or retries failed tests. A new output directory is required for every attempt.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def capture(command, cwd=None):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def source_paths(repo):
    paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=repo).decode().split('\0')
    roots = ('packages/', 'third_party/', 'apps/', 'tool/', 'tools/')
    return sorted(path for path in paths if path and (
        path in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'melos.yaml', '.cursorrules', 'CONTRIBUTING.md')
        or path.startswith(roots) and '/doc/' not in path and '/docs/' not in path
        and not path.lower().endswith('.md')))


def source_manifest(repo):
    return {name: {'sha256': sha(repo / name), 'bytes': (repo / name).stat().st_size}
            for name in source_paths(repo)}


def manifest_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def parse_tests(path):
    suites, tests, done_tests, errors, done, non_json = {}, {}, {}, [], [], 0
    for line in path.read_text(errors='replace').splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            non_json += bool(line.strip())
            continue
        if not isinstance(event, dict):
            non_json += 1
            continue
        kind = event.get('type')
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite']
        elif kind == 'testStart':
            tests[event['test']['id']] = event['test']
        elif kind == 'testDone':
            ident = event['testID']
            if ident in done_tests:
                errors.append({'duplicate_test_done': ident})
            done_tests[ident] = event
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            done.append(event)
    visible, hidden_failures, incomplete = [], [], []
    error_ids = {event.get('testID') for event in errors if isinstance(event, dict) and 'testID' in event}
    for ident, event in done_tests.items():
        test = tests.get(ident)
        if test is None:
            errors.append({'test_done_without_start': ident})
            continue
        suite = suites.get(test.get('suiteID'), {})
        result = 'error' if ident in error_ids else event.get('result')
        row = {'name': test.get('name'), 'file': suite.get('path'),
               'platform': suite.get('platform'), 'result': result,
               'skipped': bool(event.get('skipped')), 'test_id': ident}
        if event.get('hidden') and ident not in error_ids:
            if result != 'success':
                hidden_failures.append(row)
        else:
            visible.append(row)
    for ident, test in tests.items():
        if ident not in done_tests:
            incomplete.append({'id': ident, 'name': test.get('name')})
    passed = [case for case in visible if case['result'] == 'success' and not case['skipped']]
    skipped = [case for case in visible if case['skipped']]
    failed = [case for case in visible if case['result'] != 'success' and not case['skipped']]
    successful = (len(done) == 1 and done[0].get('success') is True
                  and bool(passed) and not failed and not skipped and not hidden_failures
                  and not incomplete and not errors)
    return {'passed': len(passed), 'failed': len(failed), 'skipped': len(skipped),
            'visible_cases': visible, 'skipped_cases': skipped, 'hidden_failures': hidden_failures,
            'incomplete': incomplete, 'error_events': errors, 'done_events': done,
            'non_json_lines': non_json, 'suites': list(suites.values()), 'accepted': successful}


class Runner:
    def __init__(self, repo, output, scratch, expected):
        self.repo, self.output, self.scratch, self.expected = repo, output, scratch, expected
        self.flutter = Path(os.environ['FLUTTER_ROOT']).resolve()
        self.pubcache = Path(os.environ['PUB_CACHE']).resolve()
        # Avoid the Flutter bin/dart wrapper's shared engine-stamp writes when
        # independent native suites run concurrently with the same SDK cache.
        self.dart = str(self.flutter / 'bin/cache/dart-sdk/bin/dart')
        self.flutter_cli = str(self.flutter / 'bin/flutter')
        self.compiler = Path(shutil.which('c++')).resolve()
        self.node = Path(shutil.which('node')).resolve()
        package_config = json.loads((repo / '.dart_tool/package_config.json').read_text())
        test_package = next(package for package in package_config['packages'] if package['name'] == 'test')
        from urllib.parse import urlparse, unquote
        uri = test_package['rootUri']
        self.test_cli = (Path(unquote(urlparse(uri).path)) if uri.startswith('file:')
                         else (repo / '.dart_tool' / uri).resolve()) / 'bin/test.dart'
        self.commands = []
        self.lock = threading.Lock()
        self.receipt = {'status': 'prepared', 'created_at_utc': now(),
            'scope': 'Fresh local mail/provider, Studio, synthetic language identification, and browser compilation qualification.',
            'github_actions_used': False, 'source_commit': expected, 'commands': self.commands,
            'excluded_acceptance': [
                'Real Gmail, Microsoft 365, IMAP/SMTP and EWS accounts: no endpoint credentials supplied.',
                'Real language-identification external native library acceptance: not supplied; synthetic allocation fixture only.',
                'Signed macOS application build, installed Keychain integration and OS browser callback acceptance.',
                'Browser runtime interaction: compiler import closure and JavaScript syntax only.',
            ]}

    def test_command(self, platform='vm'):
        return [self.dart, '--disable-dart-dev', '--packages=' + str(self.repo / '.dart_tool/package_config.json'),
                str(self.test_cli), '--platform=' + platform,
                '--compiler=' + ('kernel' if platform == 'vm' else 'dart2js'),
                '--reporter=json', '--concurrency=1']

    def save(self):
        with self.lock:
            write(self.output / 'receipt.json', self.receipt)

    def step(self, name, command, cwd=None, kind='command', environment=None, timeout=900):
        directory = self.output / name
        directory.mkdir()
        cwd = Path(cwd or self.repo)
        env = os.environ.copy()
        if environment:
            env.update(environment)
        record = {'name': name, 'kind': kind, 'argv': [str(arg) for arg in command],
                  'cwd': str(cwd), 'started_at_utc': now(), 'timeout_seconds': timeout,
                  'environment_overrides': environment or {}}
        write(directory / 'command.json', record)
        print(json.dumps({'started': name}), flush=True)
        started = time.monotonic()
        with (directory / 'stdout.log').open('wb') as stdout, (directory / 'stderr.log').open('wb') as stderr:
            try:
                process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout, stderr=stderr,
                                           start_new_session=True)
                try:
                    record['exit_code'] = process.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)
                    raise
            except subprocess.TimeoutExpired:
                record['exit_code'] = None
                record['timed_out'] = True
            except OSError as error:
                record['exit_code'] = None
                record['launch_error'] = str(error)
        record.update(finished_at_utc=now(), elapsed_seconds=round(time.monotonic()-started, 3),
                      stdout_sha256=sha(directory / 'stdout.log'), stderr_sha256=sha(directory / 'stderr.log'))
        record['accepted'] = record['exit_code'] == 0
        if kind == 'tests':
            parsed = parse_tests(directory / 'stdout.log')
            write(directory / 'test-cases.json', parsed)
            record['test_counts'] = {key: parsed[key] for key in ('passed', 'failed', 'skipped')}
            record['accepted'] = record['accepted'] and parsed['accepted']
        write(directory / 'result.json', record)
        with self.lock:
            self.commands.append(record)
        self.save()
        print(json.dumps({'finished': name, 'accepted': record['accepted'],
                          'exit_code': record['exit_code'], 'counts': record.get('test_counts'),
                          'seconds': record['elapsed_seconds']}), flush=True)
        if not record['accepted']:
            print((directory / 'stderr.log').read_text(errors='replace')[-3500:], flush=True)
            print((directory / 'stdout.log').read_text(errors='replace')[-3500:], flush=True)
        return record

    def runtime_manifest(self, fixture):
        paths = [Path(sys.executable).resolve(), self.flutter / 'bin/cache/dart-sdk/bin/dart', self.flutter / 'bin/flutter',
            self.flutter / 'bin/dart', self.node, self.compiler, self.test_cli,
            self.flutter / 'bin/cache/flutter_tools.snapshot',
            self.repo / '.dart_tool/package_config.json', self.repo / '.dart_tool/native_assets.yaml',
            self.repo / '.dart_tool/lib/libsqlite3.so', fixture,
            self.flutter / 'bin/cache/artifacts/engine/linux-x64/flutter_tester',
            self.flutter / 'bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill',
            self.flutter / 'bin/cache/artifacts/engine/common/flutter_patched_sdk_product/platform_strong.dill',
            self.flutter / 'bin/cache/flutter_web_sdk/kernel/dart2js_platform.dill']
        paths += sorted((self.flutter / 'bin/cache/dart-sdk/bin/snapshots').glob('*dart2js*'))
        paths += sorted((self.flutter / 'bin/cache/dart-sdk/bin/snapshots').glob('*frontend_server*'))
        paths += sorted((self.flutter / 'bin/cache/dart-sdk/bin/snapshots').glob('*kernel-service*'))
        paths += sorted((self.flutter / 'bin/cache/dart-sdk/bin/snapshots').glob('*gen_kernel*'))
        result = {str(path.resolve()): {'sha256': sha(path), 'bytes': path.stat().st_size}
                  for path in paths if path.is_file()}
        result['versions'] = {
            'dart': capture([self.dart, '--version']),
            'flutter_git_head': capture(['git', 'rev-parse', 'HEAD'], self.flutter),
            'node': capture([str(self.node), '--version']),
            'compiler': capture([str(self.compiler), '--version']),
            'python': sys.version,
        }
        return result

    def selected_files(self):
        transport = self.repo / 'packages/quds_mail_transport'
        studio = self.repo / 'packages/quds_office_editor/example'
        transport_files = sorted(set(
            list((transport / 'lib/src/cloud').rglob('*.dart')) +
            list((transport / 'test').glob('cloud*_test.dart')) +
            list((transport / 'example').glob('*.dart')) +
            [transport / 'lib/quds_mail_transport.dart']))
        studio_tests = sorted(path for path in (studio / 'test').glob('*.dart')
                              if re.fullmatch(r'studio_(saved_mail|mail[^/]*)_test\.dart', path.name))
        studio_files = sorted(set(studio_tests + [studio / 'tool/mail_web_entry.dart'] +
            list((studio / 'lib').glob('studio_mail*.dart')) +
            list((studio / 'lib').glob('studio_saved_mail.dart')) +
            list((studio / 'lib').glob('studio*strings.dart')) +
            list((studio / 'lib').glob('*credential*.dart')) +
            list((studio / 'lib').glob('*keychain*.dart'))))
        ui = self.repo / 'packages/quds_mail_ui'
        ui_files = sorted(list((ui / 'lib').rglob('*.dart')) + list((ui / 'test').glob('*_test.dart')))
        return transport, studio, ui, transport_files, studio_files, ui_files, studio_tests

    def execute(self):
        head = capture(['git', 'rev-parse', 'HEAD'], self.repo)
        expected = capture(['git', 'rev-parse', self.expected + '^{commit}'], self.repo)
        if head != expected:
            raise RuntimeError('Freeze commit does not match checked out HEAD')
        if self.output.exists() and any(self.output.iterdir()):
            raise RuntimeError('Output must be empty: do not overwrite an earlier attempt')
        selected = set(source_paths(self.repo))
        dirty = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD', '-z'], cwd=self.repo).decode().split('\0')
        if selected.intersection(dirty):
            raise RuntimeError('Tracked product/test source is dirty at freeze')
        unknown = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z'], cwd=self.repo).decode().split('\0')
        if any(path.startswith(('packages/', 'third_party/', 'apps/', 'tool/', 'tools/')) and not path.endswith('.md') for path in unknown):
            raise RuntimeError('Untracked product/test files exist at freeze')
        self.output.mkdir(parents=True, exist_ok=True)
        self.scratch.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(__file__, self.output / 'run_final.py')
        self.receipt.update(status='running', source_commit=head,
                            source_tree=capture(['git', 'rev-parse', 'HEAD^{tree}'], self.repo),
                            runner_sha256=sha(__file__), started_at_utc=now())
        before = source_manifest(self.repo)
        write(self.output / 'source-before.json', before)
        self.receipt.update(source_before_sha256=manifest_digest(before),
                            source_file_count=len(before), lock_sha256_before=sha(self.repo / 'pubspec.lock'))
        self.save()
        fixture = self.scratch / 'language-id-fixture.so'
        fixture_step = self.step('language-fixture-build', [str(self.compiler), '-std=c++17', '-shared',
            '-fPIC', '-O2', '-pthread', str(self.repo / 'packages/quds_language_id/test/fixtures/native_transport_fixture.cpp'),
            '-o', str(fixture)])
        if not fixture_step['accepted']:
            raise RuntimeError('Cannot qualify native transport without the fixture')
        runtime_before = self.runtime_manifest(fixture)
        write(self.output / 'runtime-before.json', runtime_before)
        transport, studio, ui, transport_files, studio_files, ui_files, studio_tests = self.selected_files()
        write(self.output / 'selected-suites.json', {'studio_mail': [str(p.relative_to(self.repo)) for p in studio_tests],
            'real_native_language_excluded': 'packages/quds_language_id/test/language_id_native_test.dart'})
        editor = self.repo / 'packages/quds_office_editor'
        engine = self.repo / 'packages/quds_office_engine'
        editor_regressions = [editor / 'test' / name for name in (
            'word_proofing_dialog_test.dart', 'word_proofing_session_test.dart',
            'word_thesaurus_dialog_test.dart')]
        editor_analysis = editor_regressions + [editor / path for path in (
            'lib/src/embed/word_proofing_dialog.dart', 'lib/src/embed/word_thesaurus_dialog.dart',
            'lib/src/proofing/word_proofing.dart')]
        engine_analysis = [engine / 'lib/src/thesaurus/office_thesaurus.dart',
                           engine / 'test/office_thesaurus_test.dart']
        all_format_files = sorted(set(transport_files + studio_files + ui_files + editor_analysis + engine_analysis))
        self.step('strict-format', [self.dart, 'format', '--output=none', '--set-exit-if-changed',
                  *map(str, all_format_files)])
        analysis_jobs = [
            ('strict-transport-analysis', [self.dart, 'analyze', '--fatal-infos', '--fatal-warnings',
                *[str(path.relative_to(transport)) for path in transport_files]], transport),
            ('strict-studio-analysis', [self.flutter_cli, 'analyze', '--no-pub', '--fatal-infos', '--fatal-warnings',
                *[str(path.relative_to(studio)) for path in studio_files]], studio),
            ('strict-mail-ui-analysis', [self.flutter_cli, 'analyze', '--no-pub', '--fatal-infos', '--fatal-warnings',
                *[str(path.relative_to(ui)) for path in ui_files]], ui),
            ('strict-incoming-editor-analysis', [self.flutter_cli, 'analyze', '--no-pub', '--fatal-infos', '--fatal-warnings',
                *[str(path.relative_to(editor)) for path in editor_analysis]], editor),
            ('strict-incoming-thesaurus-analysis', [self.dart, 'analyze', '--fatal-infos', '--fatal-warnings',
                *[str(path.relative_to(engine)) for path in engine_analysis]], engine),
        ]
        # Flutter tooling has a shared startup lock; run its analysis sequentially.
        for name, command, cwd in analysis_jobs:
            self.step(name, command, cwd=cwd)
        entitlement_checker = self.output / 'check_entitlements.py'
        entitlement_checker.write_text('''import json, pathlib, plistlib, sys\nroot=pathlib.Path(sys.argv[1])\nchecks=[]\nfor name in ("DebugProfile.entitlements", "Release.entitlements"):\n    path=root / "packages/quds_office_editor/example/macos/Runner" / name\n    data=plistlib.loads(path.read_bytes())\n    for key in ("com.apple.security.network.client", "com.apple.security.network.server"):\n        checks.append({"path":str(path.relative_to(root)),"key":key,"passed":data.get(key) is True})\nprint(json.dumps({"checks":checks,"passed":all(c["passed"] for c in checks)},indent=2))\nraise SystemExit(0 if all(c["passed"] for c in checks) else 1)\n''')
        self.step('macos-entitlements', [sys.executable, str(entitlement_checker), str(self.repo)])

        vm_jobs = []
        exclusions = []
        for package in ('quds_mail_core', 'quds_mail_mime', 'quds_mail_store', 'quds_mail_transport'):
            cwd = self.repo / 'packages' / package
            files = []
            for path in sorted((cwd / 'test').rglob('*_test.dart')):
                header = path.read_text()[:300]
                if re.search(r"@TestOn\(['\"](?:js|node|browser)['\"]\)", header):
                    exclusions.append({'path': str(path.relative_to(self.repo)),
                        'reason': 'Declares non-VM platform; excluded from VM suite selection.'})
                else:
                    files.append(str(path.relative_to(cwd)))
            vm_jobs.append((package + '-vm', self.test_command() + files, cwd))
        vm_jobs += [
            ('language-id-synthetic', self.test_command() + ['test/language_id_unit_test.dart',
                'test/language_id_native_transport_test.dart'], self.repo / 'packages/quds_language_id'),
            ('engine-language-id', self.test_command() + ['test/proofing/language_identification_test.dart',
                'test/proofing/language_identification_calibration_test.dart'], self.repo / 'packages/quds_office_engine'),
            ('engine-thesaurus', self.test_command() + ['test/office_thesaurus_test.dart'], engine),
        ]
        write(self.output / 'platform-exclusions.json', exclusions)
        fixture_env = {'QUDS_LANGUAGE_ID_FIXTURE_LIBRARY': str(fixture)}
        # Independent VM suites run in pairs, with each package's own runner
        # serialized. This bounds memory while reducing wall-clock time.
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(self.step, name, command, cwd, 'tests',
                fixture_env if name == 'language-id-synthetic' else None)
                for name, command, cwd in vm_jobs]
            for future in concurrent.futures.as_completed(futures):
                future.result()
        self.step('transport-node-boundaries', self.test_command('node') + [
            'test/unsupported_test.dart', 'test/ews_configuration_test.dart',
            'test/ews_unsupported_test.dart', 'test/cloud_unsupported_test.dart'],
            cwd=transport, kind='tests')
        flutter_tests = [self.flutter_cli, 'test', '--no-pub', '--concurrency=1', '--reporter=json']
        self.step('mail-ui-widgets', flutter_tests + ['test'], cwd=ui, kind='tests')
        self.step('editor-proofing-thesaurus-widgets', flutter_tests + [str(path.relative_to(editor)) for path in editor_regressions],
                  cwd=editor, kind='tests')
        self.step('studio-mail-widgets', flutter_tests + [str(path.relative_to(studio)) for path in studio_tests],
                  cwd=studio, kind='tests', timeout=1200)
        self.step('studio-language-id-widgets', flutter_tests + ['test/studio_language_id_test.dart'],
                  cwd=studio, kind='tests')

        kernel = self.scratch / 'mail-web.dill'
        javascript = self.scratch / 'mail-web.js'
        common = [self.dart, 'compile', 'js',
            '--platform-binaries=' + str(self.flutter / 'bin/cache/flutter_web_sdk/kernel'),
            '--invoker=flutter_tool', '-Ddart.vm.product=true', '-O1']
        frontend = self.step('mail-browser-frontend', common + [
            '--packages=' + str(self.repo / '.dart_tool/package_config.json'), '--cfe-only', '-o', str(kernel),
            str(studio / 'tool/mail_web_entry.dart')], timeout=1200)
        closure = {'passed': False, 'reason': 'Frontend compilation failed'}
        if frontend['accepted']:
            deps = Path(str(kernel) + '.deps')
            entries = set(deps.read_text().splitlines())
            required = [
                'packages/quds_office_editor/example/tool/mail_web_entry.dart',
                'packages/quds_office_editor/example/lib/studio_mail.dart',
                'packages/quds_office_editor/example/lib/studio_mail_web.dart',
                'packages/quds_office_editor/example/lib/studio_saved_mail.dart',
                'packages/quds_office_editor/example/lib/studio_mail_file_web.dart',
            ]
            forbidden = [
                'packages/quds_office_editor/example/lib/studio_mail_native.dart',
                'packages/quds_office_editor/example/lib/studio_mail_ews.dart',
                'packages/quds_office_editor/example/lib/studio_mail_cloud.dart',
                'packages/quds_office_editor/example/lib/studio_mail_message_loader.dart',
                'packages/quds_office_editor/example/lib/studio_mail_file_native.dart',
                'third_party/enough_mail/lib/highlevel.dart',
                'third_party/enough_mail/lib/src/mail/mail_client.dart',
                'third_party/enough_mail/lib/src/private/util/client_base.dart',
            ]
            forbidden += [str(p.relative_to(self.repo)) for p in (studio / 'lib').glob('*credential*.dart')]
            forbidden += [str(p.relative_to(self.repo)) for p in (transport / 'lib/src/cloud/native').rglob('*.dart')]
            forbidden += [str(p.relative_to(self.repo)) for p in (transport / 'lib/src/ews/native').rglob('*.dart')]
            missing = [path for path in required if (self.repo / path).as_uri() not in entries]
            present = [path for path in forbidden if (self.repo / path).as_uri() in entries]
            closure = {'required_web_paths': required, 'forbidden_native_paths': forbidden,
                'missing_web_paths': missing, 'present_native_paths': present,
                'dependency_count': len(entries), 'dependencies_sha256': sha(deps),
                'passed': not missing and not present,
                'scope': 'Actual Flutter web compiler import closure; not browser execution.'}
            shutil.copyfile(deps, self.output / 'mail-web.dill.deps')
            backend = self.step('mail-browser-javascript', common + ['--no-source-maps',
                '-o', str(javascript), str(kernel)], timeout=1200)
            if backend['accepted']:
                self.step('mail-browser-node-syntax', [str(self.node), '--check', str(javascript)])
            write(self.output / 'web-artifacts.json', {str(path.name): {
                'sha256': sha(path), 'bytes': path.stat().st_size} for path in (kernel, javascript)
                if path.is_file()})
        write(self.output / 'mail-browser-import-closure.json', closure)
        after = source_manifest(self.repo)
        runtime_after = self.runtime_manifest(fixture)
        write(self.output / 'source-after.json', after)
        write(self.output / 'runtime-after.json', runtime_after)
        counts = {key: sum(item.get('test_counts', {}).get(key, 0) for item in self.commands)
                  for key in ('passed', 'failed', 'skipped')}
        head_after = capture(['git', 'rev-parse', 'HEAD'], self.repo)
        accepted = (all(command['accepted'] for command in self.commands) and before == after
                    and runtime_before == runtime_after and closure['passed'] and head_after == head)
        self.receipt.update(status='passed' if accepted else 'failed', finished_at_utc=now(),
            source_after_sha256=manifest_digest(after), source_unchanged=before == after,
            runtime_unchanged=runtime_before == runtime_after,
            runtime_manifest_sha256=manifest_digest(runtime_before),
            lock_sha256_after=sha(self.repo / 'pubspec.lock'),
            lock_unchanged=self.receipt['lock_sha256_before'] == sha(self.repo / 'pubspec.lock'),
            checkout_head_after=head_after, source_head_unchanged=head_after == head,
            test_counts=counts, browser_closure_passed=closure['passed'])
        self.save()
        print(json.dumps({'final': self.receipt['status'], 'counts': counts,
              'source_unchanged': before == after, 'runtime_unchanged': runtime_before == runtime_after,
              'output': str(self.output)}), flush=True)
        return 0 if accepted else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--output', type=Path)
    parser.add_argument('--scratch', type=Path)
    parser.add_argument('--freeze', required=True, help='Root-approved frozen source commit SHA')
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = (args.output or repo / 'docs/validation/mail-providers-20261119/final').resolve()
    scratch = args.scratch or Path(tempfile.mkdtemp(prefix='mail-providers-qualification-'))
    runner = Runner(repo, output, scratch.resolve(), args.freeze)
    try:
        return runner.execute()
    except BaseException as error:
        if output.exists():
            runner.receipt.update(status='failed', finished_at_utc=now(), runner_error=repr(error))
            runner.save()
        raise


if __name__ == '__main__':
    raise SystemExit(main())
