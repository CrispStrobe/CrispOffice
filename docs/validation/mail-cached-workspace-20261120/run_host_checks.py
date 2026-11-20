#!/usr/bin/env python3
"""Run source-bound local mail cohorts; never use hosted CI or status APIs."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/mail'))
from check_store import direct_launcher, execute, test_summary  # noqa: E402


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs(phase: str) -> dict[str, str]:
    names = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
        cwd=ROOT).decode().split('\0')
    shared = tuple('packages/' + package + '/' for package in (
        'quds_mail_core', 'quds_mail_mime', 'quds_mail_store',
        'quds_mail_transport', 'quds_mail_ui')) + ('third_party/enough_mail/',)
    prefixes = ('packages/', 'third_party/') if phase == 'studio' else shared
    fixed = {'.fvmrc', '.cursorrules', 'CONTRIBUTING.md', 'analysis_options.yaml',
             'pubspec.yaml', 'pubspec.lock', 'tools/mail/check_store.py',
             'tools/mail/check_reader.py', str(Path(__file__).relative_to(ROOT))}
    selected = {ROOT / name for name in names if name and (
        name in fixed or name.startswith(prefixes))}
    return {str(path.relative_to(ROOT)): sha(path) for path in sorted(selected)
            if path.is_file()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter-sdk', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--phase', choices=('studio', 'shared'), required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sdk = args.flutter_sdk.resolve()
    dart = str(sdk / 'bin/cache/dart-sdk/bin/dart')
    flutter = str(sdk / 'bin/flutter')
    studio = ROOT / 'packages/quds_office_editor/example'
    receipt_path = output / 'receipt.json'
    config, test_entry, native_inputs = direct_launcher(ROOT)
    runtime_inputs = dict(native_inputs)
    for file in (Path(dart), sdk / 'bin/cache/artifacts/engine/linux-x64/flutter_tester'):
        runtime_inputs[str(file)] = sha(file)
    direct = [dart, '--disable-dart-dev', '--packages=' + str(config), str(test_entry)]
    studio_tests = sorted(str(path.relative_to(studio))
                          for path in (studio / 'test').glob('*_test.dart')
                          if path.name.startswith(('studio_mail', 'studio_saved_mail', 'studio_credential')))
    if args.phase == 'studio':
        analyzed = sorted({str(path.relative_to(studio))
                           for folder in ('lib', 'test')
                           for pattern in ('studio_mail*.dart', 'studio_saved_mail*.dart', 'studio_credential*.dart')
                           for path in (studio / folder).glob(pattern)})
        changed = subprocess.check_output(
            ['git', 'diff', '--name-only', 'bb5320a50f288d95844a6d60cfd72eab13a9befc', 'HEAD'],
            cwd=ROOT, text=True).splitlines()
        formatted = sorted(name for name in changed if name.endswith('.dart'))
        commands = [
            ('studio-mail', [flutter, 'test', '--no-pub', '--concurrency=2', '--reporter=json',
                             *studio_tests], studio, True),
            ('studio-analysis', [dart, 'analyze', '--fatal-infos', *analyzed], studio, False),
            ('changed-format', [dart, 'format', '--output=none', '--set-exit-if-changed',
                                *formatted], ROOT, False),
            ('whitespace', ['git', 'diff', '--check', 'HEAD'], ROOT, False),
        ]
    else:
        commands = [
            ('shared-mail-ui', [flutter, 'test', '--no-pub', '--concurrency=2', '--reporter=json'],
             ROOT / 'packages/quds_mail_ui', True),
            ('mime-transport', direct + ['--compiler=kernel', '--concurrency=2', '--reporter=json',
                                        '../quds_mail_mime/test', 'test'],
             ROOT / 'packages/quds_mail_transport', True),
        ]
    receipt = dict(
        status='RUNNING', phase=args.phase, started_at=datetime.now(timezone.utc).isoformat(),
        source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        source_tree=subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=ROOT, text=True).strip(),
        source_before=inputs(args.phase), runtime_before=runtime_inputs,
        github_actions='NOT USED', checks=[])

    def save() -> None:
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')

    save()
    env = dict(os.environ, CI='true', FLUTTER_SUPPRESS_ANALYTICS='true',
               DART_SUPPRESS_ANALYTICS='true')
    accepted = True
    try:
        for name, command, cwd, is_tests in commands:
            print(name, flush=True)
            log = output / (name + ('.jsonl' if is_tests else '.log'))
            errors = output / (name + '.stderr')
            check = dict(name=name, command=command, cwd=str(cwd), status='RUNNING',
                         log=log.name, stderr=errors.name, timeout_seconds=900)
            receipt['checks'].append(check)
            save()
            with log.open('wb') as out, errors.open('wb') as err:
                check['exit_code'] = execute(command, cwd=cwd, env=env,
                                             stdout=out, stderr=err, timeout=900)
            ok = check['exit_code'] == 0
            if is_tests:
                summary = test_summary(log)
                cases = output / (name + '-cases.json')
                cases.write_text(json.dumps(summary, indent=2) + '\n')
                check['tests'] = {key: value for key, value in summary.items() if key != 'cases'}
                check['case_list'] = cases.name
                ok = ok and bool(summary['valid'])
            check.update(log_sha256=sha(log), stderr_sha256=sha(errors),
                         status='PASS' if ok else 'FAIL')
            accepted &= ok
            save()
        receipt['status'] = 'PASS' if accepted else 'FAIL'
    except (Exception, KeyboardInterrupt) as error:
        receipt.update(status='FAIL', error=f'{type(error).__name__}: {error}')
    finally:
        receipt['source_after'] = inputs(args.phase)
        receipt['runtime_after'] = {
            name: sha(Path(name)) if Path(name).is_file() else None
            for name in runtime_inputs}
        receipt['source_unchanged'] = receipt['source_before'] == receipt['source_after']
        receipt['runtime_unchanged'] = runtime_inputs == receipt['runtime_after']
        if not receipt['source_unchanged'] or not receipt['runtime_unchanged']:
            receipt['status'] = 'FAIL'
        receipt['finished_at'] = datetime.now(timezone.utc).isoformat()
        save()
    print(receipt['status'], flush=True)
    return 0 if receipt['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
