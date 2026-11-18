#!/usr/bin/env python3
"""Qualify Mail storage locally; never query or wait for hosted CI."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

from check_reader import write_receipt


def hashes(root: Path) -> dict[str, str]:
    paths = [root / name for name in (
        '.fvmrc', 'analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock',
        'tools/mail/check_store.py', 'tools/mail/check_reader.py',
        'tools/mail/test_check_store.py',
    )]
    for package in ('quds_mail_core', 'quds_mail_store'):
        base = root / 'packages' / package
        paths.append(base / 'pubspec.yaml')
        for folder in ('lib', 'test', 'tool'):
            paths.extend(path for path in (base / folder).rglob('*') if path.is_file())
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(set(paths))
            if path.is_file() and not any(part in {'.dart_tool', 'build', '__pycache__'}
                                          for part in path.parts)}


def test_summary(log: Path) -> dict[str, object]:
    cases: dict[int, dict[str, object]] = {}
    errors: list[dict[str, object]] = []
    protocol_issues: list[str] = []
    completed: set[int] = set()
    starts = 0
    terminals = 0
    terminal = None
    for number, line in enumerate(log.read_text(errors='replace').splitlines(), 1):
        # Native-assets progress may precede an event without a newline. Strip
        # only those known prefixes; searching for an opening brace can discard
        # malformed records, scalar/array JSON, or unexpected runner output.
        record = line.strip()
        progress = ('Running build hooks...', 'Running link hooks...')
        while record.startswith(progress):
            prefix = next(item for item in progress if record.startswith(item))
            record = record[len(prefix):].lstrip()
        if not record:
            continue
        try:
            event = json.loads(record)
        except json.JSONDecodeError:
            protocol_issues.append(f'Line {number}: malformed JSON event')
            continue
        if not isinstance(event, dict):
            protocol_issues.append(f'Line {number}: event is not an object')
            continue
        kind = event.get('type')
        if not isinstance(kind, str):
            protocol_issues.append(f'Line {number}: missing event type')
            continue
        if terminals:
            protocol_issues.append(f'Line {number}: event after terminal result')
        if kind == 'start':
            starts += 1
            if starts != 1:
                protocol_issues.append(f'Line {number}: duplicate start event')
        elif starts != 1:
            protocol_issues.append(f'Line {number}: event without one start')
        if kind == 'testStart':
            case = event.get('test')
            if (not isinstance(case, dict) or type(case.get('id')) is not int
                    or not isinstance(case.get('name'), str)
                    or type(case.get('suiteID')) is not int):
                protocol_issues.append(f'Line {number}: invalid test start')
                continue
            identifier = case['id']
            if identifier in cases:
                protocol_issues.append(f'Line {number}: duplicate test identifier')
                continue
            cases[identifier] = {'name': case['name'], 'suite_id': case['suiteID']}
        elif kind == 'testDone':
            identifier = event.get('testID')
            if type(identifier) is not int or identifier not in cases:
                protocol_issues.append(f'Line {number}: unmatched test completion')
                continue
            if identifier in completed:
                protocol_issues.append(f'Line {number}: duplicate test completion')
                continue
            completed.add(identifier)
            result = event.get('result')
            if (not isinstance(result, str)
                    or result not in {'success', 'failure', 'error'}
                    or type(event.get('skipped')) is not bool
                    or type(event.get('hidden')) is not bool):
                protocol_issues.append(f'Line {number}: invalid test completion')
            case = cases[identifier]
            case.update(result=result, skipped=event.get('skipped'),
                        hidden=event.get('hidden'))
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            terminals += 1
            terminal = event.get('success')
            if type(terminal) is not bool:
                protocol_issues.append(f'Line {number}: invalid terminal result')
    substantive = []
    excluded = []
    for case in cases.values():
        target = (excluded if case.get('hidden') or str(case.get('name', '')).startswith('loading ')
                  else substantive)
        target.append(case)
    passed = sum(case.get('result') == 'success' and not case.get('skipped') for case in substantive)
    skipped = sum(bool(case.get('skipped')) for case in substantive)
    failed = [case for case in substantive if case.get('result') != 'success' and not case.get('skipped')]
    # Hidden loaders and setup/teardown cases are not substantive test counts,
    # but their failures or skips must still prevent qualification.
    excluded_failed = sum(case.get('result') != 'success' and not case.get('skipped')
                          for case in excluded)
    excluded_skipped = sum(bool(case.get('skipped')) for case in excluded)
    incomplete = len(set(cases) - completed)
    return dict(passed=passed, skipped=skipped, failed=len(failed), errors=len(errors),
                excluded_failed=excluded_failed, excluded_skipped=excluded_skipped,
                terminal_success=terminal, start_events=starts, terminal_events=terminals,
                incomplete=incomplete, protocol_errors=len(protocol_issues),
                protocol_issues=protocol_issues, cases=substantive,
                valid=(terminal is True and starts == 1 and terminals == 1
                       and passed > 0 and skipped == 0 and not failed and not errors
                       and excluded_failed == 0 and excluded_skipped == 0
                       and not incomplete and not protocol_issues))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter-sdk', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('build/mail-store-qualification'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    receipt_path = output / 'receipt.json'
    checks: list[dict[str, object]] = []
    receipt: dict[str, object] = dict(
        status='RUNNING', run_id=uuid.uuid4().hex,
        started_utc=datetime.now(timezone.utc).isoformat(), checks=checks,
        active_check=None, source_unchanged=None,
        browser_runtime='NOT RUN: compile/Node checks do not exercise browser storage',
        github_actions='NOT USED',
    )
    # Replace any earlier PASS before validation or spawning a process.
    write_receipt(receipt_path, receipt)
    before = None
    code = 1
    try:
        sdk = args.flutter_sdk.resolve()
        dart = sdk / 'bin/cache/dart-sdk/bin/dart'
        if not dart.is_file() or shutil.which('node') is None:
            raise FileNotFoundError('Verified Flutter/Dart SDK and Node are required.')
        (output / 'tmp').mkdir(exist_ok=True)
        env = dict(os.environ, FLUTTER_ROOT=str(sdk), TMPDIR=str(output / 'tmp'),
                   CI='true', DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true')
        env['PATH'] = str(dart.parent) + os.pathsep + env.get('PATH', '')
        before = hashes(root)
        receipt['source_before'] = before
        receipt['starting_commit'] = subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
        write_receipt(receipt_path, receipt)

        def run(name: str, command: list[str], cwd: Path = root, *, tests: bool = False) -> bool:
            print(name, flush=True)
            path = output / (name + ('.jsonl' if tests else '.log'))
            entry: dict[str, object] = dict(name=name, command=command, cwd=str(cwd),
                                            status='RUNNING', log=path.name, exit_code=None)
            checks.append(entry)
            receipt['active_check'] = name
            write_receipt(receipt_path, receipt)
            try:
                with path.open('wb') as stream:
                    result = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                            stderr=subprocess.STDOUT, check=False)
                entry['exit_code'] = result.returncode
                ok = result.returncode == 0
                if tests:
                    summary = test_summary(path)
                    details = output / (name + '-cases.json')
                    details.write_text(json.dumps(summary, indent=2) + '\n')
                    entry['tests'] = {key: value for key, value in summary.items() if key != 'cases'}
                    entry['case_list'] = details.name
                    ok = ok and bool(summary['valid'])
                entry['status'] = 'PASS' if ok else 'FAIL'
                return ok
            except KeyboardInterrupt:
                entry['status'] = 'INTERRUPTED'
                raise
            except OSError:
                entry['status'] = 'ERROR'
                raise
            finally:
                if path.exists():
                    entry['log_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
                receipt['active_check'] = None
                write_receipt(receipt_path, receipt)

        cmd = [str(dart)]
        ok = run('runtime', cmd + ['--version'])
        ok &= run('runner-regressions', [sys.executable, '-m', 'unittest',
                                         'discover', '-s', 'tools/mail',
                                         '-p', 'test_check_store.py', '-v'])
        ok &= run('locked-resolution', cmd + ['pub', 'get', '--enforce-lockfile'])
        if ok:
            core = root / 'packages/quds_mail_core'
            store = root / 'packages/quds_mail_store'
            for package, directory in [('core', core), ('store', store)]:
                ok &= run(package + '-analysis', cmd + ['analyze', '--fatal-infos'], directory)
            ok &= run('format', cmd + ['format', '--output=none', '--set-exit-if-changed',
                                      str(core / 'lib'), str(core / 'test'),
                                      str(store / 'lib'), str(store / 'test'), str(store / 'tool')])
            ok &= run('core-vm', cmd + ['test', '--platform', 'vm', '--reporter', 'json'], core, tests=True)
            ok &= run('core-node', cmd + ['test', '--platform', 'node', '--reporter', 'json'], core, tests=True)
            native = sorted(str(path.relative_to(store)) for path in (store / 'test').glob('*_test.dart')
                            if path.name != 'browser_problem_test.dart')
            ok &= run('store-vm', cmd + ['test', '--platform', 'vm', '--reporter', 'json',
                                        '--concurrency=2', *native], store, tests=True)
            ok &= run('portable-node', cmd + ['test', '--platform', 'node', '--reporter', 'json',
                                               'test/codec_test.dart', 'test/platform_configuration_test.dart',
                                               'test/browser_problem_test.dart'], store, tests=True)
            for name, source in [('browser-entry', 'tool/browser_compile_probe.dart'),
                                 ('browser-worker', 'tool/mail_store_worker.dart')]:
                target = output / (name + '.js')
                target.unlink(missing_ok=True)
                ok &= run(name, cmd + ['compile', 'js', source, '-o', str(target)], store)
            ok &= run('whitespace', ['git', 'diff', '--check', 'HEAD'])
        receipt['status'] = 'PASS' if ok else 'FAIL'
        code = 0 if ok else 1
    except KeyboardInterrupt:
        receipt['status'] = 'INTERRUPTED'
        code = 130
    except Exception as error:
        receipt['status'] = 'FAIL'
        receipt['error'] = f'{type(error).__name__}: {error}'
    finally:
        if before is not None:
            after = hashes(root)
            receipt['source_after'] = after
            receipt['source_unchanged'] = before == after
            if before != after:
                receipt['status'] = 'FAIL'
                code = code or 1
        if receipt['status'] == 'RUNNING':
            receipt['status'] = 'FAIL'
        receipt['active_check'] = None
        receipt['finished_utc'] = datetime.now(timezone.utc).isoformat()
        write_receipt(receipt_path, receipt)
    print(f"{receipt['status']}: {receipt_path}")
    return code


if __name__ == '__main__':
    sys.exit(main())
