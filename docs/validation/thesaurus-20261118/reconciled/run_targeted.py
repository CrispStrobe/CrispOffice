#!/usr/bin/env python3
"""Replay the captured affected-suite plan with local source/runtime evidence.

This runner uses the Mail reporter's tested fail-closed protocol parser and the
thesaurus fixture's effective-workspace binding. It never contacts GitHub or CI.
Each output directory is new; original failed attempts must remain available.
"""
from __future__ import annotations

import argparse
from contextlib import suppress
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse

import yaml


HERE = Path(__file__).resolve().parent
REPO = next(p for p in HERE.parents if (p / 'packages/quds_office_editor').is_dir())
FIXTURES = HERE.parent / 'continuation/local/fixtures'
sys.path.insert(0, str(FIXTURES))
sys.path.insert(0, str(REPO / 'tools/mail'))
from workspace_binding import snapshot_sources  # noqa: E402
from check_store import test_summary  # noqa: E402


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    pending = path.with_name(path.name + '.tmp')
    pending.write_text(json.dumps(value, indent=2) + '\n')
    pending.replace(path)


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args], text=True).strip()


LAYOUT_DIAGNOSTICS = re.compile(
    r'A Render\w+ overflowed|would not hit test on the specified widget|'
    r'does not receive pointer events')


def layout_diagnostics(path):
    return [{'line': number, 'text': line} for number, line in
            enumerate(path.read_text(errors='replace').splitlines(), 1)
            if LAYOUT_DIAGNOSTICS.search(line)]


def parse_cases(log, cwd, requested):
    result = test_summary(log)
    suites = {}
    started_suite_ids, suite_issues = [], []
    for line in log.read_text(errors='replace').splitlines():
        try:
            event = json.loads(line[line.index('{'):])
        except (ValueError, json.JSONDecodeError):
            continue
        if not isinstance(event, dict):
            continue  # The protocol parser already records this rejection.
        if event.get('type') == 'suite':
            suite = event.get('suite')
            if (not isinstance(suite, dict) or type(suite.get('id')) is not int
                    or not isinstance(suite.get('path'), str) or not suite['path']):
                suite_issues.append('Malformed suite registration')
                continue
            if suite['id'] in suites:
                suite_issues.append('Duplicate suite identifier')
            path = Path(suite['path'])
            suites[suite['id']] = str((cwd / path).resolve())
        elif event.get('type') == 'testStart':
            test = event.get('test')
            if isinstance(test, dict):
                identifier = test.get('suiteID')
                started_suite_ids.append(identifier if type(identifier) is int else None)
    cases = []
    for case in result.pop('cases'):
        if re.search(r'(?:^| )\((?:setUpAll|tearDownAll)\)$', case['name']):
            continue
        cases.append({**case, 'suite': suites.get(case['suite_id'])})
    expected = {str((cwd / p).resolve()) for p in requested}
    observed = set(suites.values())
    identities = [(c['suite'], c['name']) for c in cases]
    result.update(
        passed=sum(c.get('result') == 'success' and not c.get('skipped') for c in cases),
        missing_suites=sorted(expected - observed),
        unexpected_suites=sorted(observed - expected),
        empty_suites=sorted(expected - {c['suite'] for c in cases}),
        duplicate_case_count=len(identities) - len(set(identities)),
        unknown_case_suites=sum(identifier not in suites for identifier in started_suite_ids),
        suite_registration_issues=suite_issues,
        duplicate_suite_paths=len(suites) - len(set(suites.values())),
        layout_or_tap_diagnostics=layout_diagnostics(log),
    )
    result['valid'] = result['valid'] and not any(result[k] for k in (
        'missing_suites', 'unexpected_suites', 'empty_suites', 'duplicate_case_count',
        'unknown_case_suites', 'suite_registration_issues', 'duplicate_suite_paths',
        'layout_or_tap_diagnostics'))
    return result, cases


def execute_process(command, *, cwd, env, stdout, stderr, timeout):
    """Reap the command and stop its children on timeout or interruption."""
    process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout,
                               stderr=stderr, start_new_session=os.name == 'posix')
    try:
        return process.wait(timeout=timeout)
    except BaseException:
        with suppress(ProcessLookupError):
            if os.name == 'posix':
                os.killpg(process.pid, signal.SIGTERM)
            else:
                process.terminate()
        with suppress(subprocess.TimeoutExpired):
            process.wait(timeout=5)
        # The leader may have exited while a child ignored SIGTERM. Address
        # the whole group even when wait() has already reaped the leader.
        with suppress(ProcessLookupError):
            if os.name == 'posix':
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
        process.wait()
        raise


def qualify(args, runtime, out, plan_path, record):
    plan = json.loads(plan_path.read_text())
    receipt = json.loads((runtime / 'runtime.json').read_text())
    sdk_receipt = json.loads((runtime / 'sdk-receipt.json').read_text())
    assert receipt['status'] == 'ready' and sdk_receipt['archive']['verified'] is True
    assert digest(runtime / 'sdk-receipt.json') == receipt['sdk_receipt_sha256']
    assert digest(REPO / 'pubspec.lock') == receipt['lock_sha256_after']
    assert digest(runtime / 'pub-cache-receipt.json') == receipt['pub_cache_receipt_sha256']
    for name, sha in receipt['executables_sha256'].items():
        assert digest(name) == sha, 'Changed runtime executable: ' + name
    requested = []
    for group in plan['groups']:
        assert group['runner'] in ('dart', 'flutter') and group['tests']
        for name in group['tests']:
            path = (REPO / group['cwd'] / name).resolve()
            assert path.is_file() and path.is_relative_to(REPO)
            requested.append(str(path))
    assert len(requested) == len(set(requested)), 'Duplicate requested suite'
    binding_files = [Path(__file__), HERE / 'test_run_targeted.py', plan_path,
                     FIXTURES / 'workspace_binding.py',
                     REPO / 'tools/mail/check_store.py', REPO / 'tools/mail/check_reader.py']
    for path in binding_files:
        relative = str(path.relative_to(REPO))
        assert git('hash-object', str(path)) == git('rev-parse', 'HEAD:' + relative), relative
    source_before = snapshot_sources(REPO, REPO)
    for name in source_before:
        if name.startswith('__'):
            continue
        assert git('hash-object', str(REPO / name)) == git('rev-parse', 'HEAD:' + name), name

    def environment():
        files = [runtime / name for name in ('runtime.json', 'sdk-receipt.json',
                 'pub-cache-receipt.json', 'env.sh', 'bin/dart', 'bin/flutter')]
        files += [Path(p) for p in receipt['executables_sha256']]
        files += [runtime / 'flutter/bin/cache/flutter_tools.snapshot',
                  runtime / 'flutter/packages/flutter_tools/.dart_tool/package_config.json']
        # Bind installed dependency/framework bytes, not only original download
        # receipts. The exact locked package root must be the one Dart imports.
        config_path = REPO / '.dart_tool/package_config.json'
        config = json.loads(config_path.read_text())
        lock = yaml.safe_load((REPO / 'pubspec.lock').read_text())['packages']
        local_packages = source_before['__workspace_binding__']['package_roots']
        sdk = (runtime / 'flutter').resolve()
        for package in config['packages']:
            parsed = urlparse(package['rootUri'])
            assert parsed.scheme in ('', 'file') and parsed.netloc in ('', 'localhost')
            root = Path(unquote(parsed.path))
            root = (root if root.is_absolute() else config_path.parent / root).resolve()
            name = package['name']
            if name in local_packages:
                assert root == Path(local_packages[name]['source']), name
                continue
            if lock[name]['source'] == 'hosted':
                expected = runtime / 'pub-cache/hosted/pub.dev' / (name + '-' + lock[name]['version'])
                assert root == expected.resolve(), 'Redirected hosted package: ' + name
            elif lock[name]['source'] == 'path':
                description = lock[name]['description']
                assert description.get('relative') is True, name
                expected = (REPO / description['path']).resolve()
                assert expected.is_relative_to(REPO) and root == expected, name
            else:
                assert lock[name]['source'] == 'sdk', name
                expected = sdk / ('bin/cache/pkg' if name == 'sky_engine' else 'packages') / name
                assert root == expected.resolve(), 'Redirected SDK package: ' + name
            assert package.get('packageUri') == 'lib/', name
            files.extend(p for p in root.rglob('*') if p.is_file()
                         and not any(part in {'.git', '.dart_tool', 'build', '__pycache__'}
                                     for part in p.relative_to(root).parts))
        for directory in ('bin/cache/dart-sdk/lib', 'bin/cache/dart-sdk/bin/snapshots'):
            files.extend(p for p in (sdk / directory).rglob('*') if p.is_file())
        return {str(p): digest(p) for p in files}

    environment_before = environment()
    harness_before = {str(p.relative_to(REPO)): digest(p) for p in binding_files}
    write_json(out / 'source-before.json', source_before)
    write_json(out / 'environment-before.json', environment_before)
    record.update(status='running',
                  source_commit=git('rev-parse', 'HEAD'), source_tree=git('rev-parse', 'HEAD^{tree}'),
                  suite_count=len(requested), plan=plan, harness_sha256=harness_before,
                  runtime=receipt['runtime'])
    env = dict(os.environ)
    env.update(PUB_CACHE=str(runtime / 'pub-cache'), FLUTTER_ROOT=str(runtime / 'flutter'),
               CI='true', DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true',
               DASH__SUPPRESS_ANALYTICS='true', XDG_CONFIG_HOME=str(runtime / 'config'),
               XDG_CACHE_HOME=str(runtime / 'cache'), XDG_DATA_HOME=str(runtime / 'data'),
               TMPDIR=str(runtime / 'tmp'), PATH=str(runtime / 'bin') + os.pathsep + env.get('PATH', ''))

    def save():
        write_json(out / 'receipt.json', record)

    def run(name, command, cwd, tests=None):
        print('START ' + name, flush=True)
        log, err = out / (name + '.stdout'), out / (name + '.stderr')
        start = time.monotonic()
        item = dict(name=name, command=command, cwd=str(cwd.relative_to(REPO)), status='running',
                    accepted=False, stdout=log.name, stderr=err.name)
        record['runs'].append(item)
        save()
        with log.open('wb') as stdout, err.open('wb') as stderr:
            try:
                item['exit_code'] = execute_process(command, cwd=cwd, env=env,
                    stdout=stdout, stderr=stderr, timeout=args.timeout)
            except (OSError, subprocess.TimeoutExpired) as exc:
                item.update(exit_code=124 if isinstance(exc, subprocess.TimeoutExpired) else 127,
                            exception=repr(exc))
            except BaseException as exc:
                item.update(status='interrupted', exception=repr(exc))
                save()
                raise
        item.update(status='completed', seconds=round(time.monotonic() - start, 3))
        if tests is not None:
            result, cases = parse_cases(log, cwd, tests)
            result['stderr_layout_or_tap_diagnostics'] = layout_diagnostics(err)
            result['valid'] = result['valid'] and not result['stderr_layout_or_tap_diagnostics']
            item.update(result)
            write_json(out / (name + '-cases.json'), cases)
        item['accepted'] = item['exit_code'] == 0 and (tests is None or item['valid'])
        item['logs'] = {}
        for path in (log, err):
            compressed = path.with_suffix(path.suffix + '.gz')
            compressed.write_bytes(gzip.compress(path.read_bytes(), mtime=0))
            item['logs'][path.name] = dict(sha256=digest(path), compressed=compressed.name,
                                         compressed_sha256=digest(compressed))
        save()
        print(json.dumps({k: item[k] for k in ('name', 'exit_code', 'passed', 'accepted') if k in item}), flush=True)

    save()
    try:
        for group in plan['groups']:
            command = [str(runtime / 'bin' / group['runner']), 'test']
            if group['runner'] == 'flutter':
                command.append('--no-pub')
            command += [f'--concurrency={args.concurrency}', '--reporter=json', *group['tests']]
            run(group['name'], command, REPO / group['cwd'], group['tests'])
        for kind in ('analysis', 'format'):
            paths = plan[kind]
            if paths:
                command = ([str(runtime / 'bin/dart'), 'analyze', '--fatal-infos', '--fatal-warnings']
                           if kind == 'analysis' else [str(runtime / 'bin/dart'), 'format',
                                                      '--output=none', '--set-exit-if-changed'])
                run(kind, command + paths, REPO)
    except BaseException as exc:
        record['runner_error'] = repr(exc)
        raise
    finally:
        record.update(source_unchanged=False, environment_unchanged=False, harness_unchanged=False)
        try:
            source_after = snapshot_sources(REPO, REPO)
            environment_after = environment()
            write_json(out / 'source-after.json', source_after)
            write_json(out / 'environment-after.json', environment_after)
            record.update(source_unchanged=source_before == source_after,
                          environment_unchanged=environment_before == environment_after,
                          harness_unchanged=harness_before == {str(p.relative_to(REPO)): digest(p) for p in binding_files})
        except BaseException as exc:
            record['final_inspection_error'] = repr(exc)
        record['finished_utc'] = datetime.now(timezone.utc).isoformat()
        record['passed'] = sum(r.get('passed', 0) for r in record['runs'] if r.get('accepted', False))
        record['success'] = (not record.get('runner_error') and record['source_unchanged']
                             and record['environment_unchanged'] and record['harness_unchanged']
                             and len(record['runs']) == len(plan['groups']) + bool(plan['analysis']) + bool(plan['format'])
                             and all(r.get('accepted', False) for r in record['runs']))
        record['status'] = 'passed' if record['success'] else 'failed'
        record['evidence_sha256'] = {p.name: digest(p) for p in sorted(out.glob('*.json'))
                                     if p.name != 'receipt.json'}
        save()
    return 0 if record['success'] else 1


def positive_integer(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError('must be a positive integer')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--plan', type=Path, default=HERE / 'plan.json')
    parser.add_argument('--timeout', type=positive_integer, default=900)
    parser.add_argument('--concurrency', type=positive_integer, default=4,
                        help='Maximum concurrent suites within each sequential group (default: 4).')
    args = parser.parse_args()
    runtime, out, plan_path = args.runtime.resolve(), args.output.resolve(), args.plan.resolve()
    out.mkdir(parents=True, exist_ok=False)
    record = dict(status='preflight', success=False,
                  started_utc=datetime.now(timezone.utc).isoformat(),
                  requested_runtime=str(runtime), requested_plan=str(plan_path),
                  concurrency=args.concurrency, timeout_seconds=args.timeout,
                  github_actions='NOT USED', runs=[])
    write_json(out / 'receipt.json', record)
    try:
        return qualify(args, runtime, out, plan_path, record)
    except BaseException as exc:
        record.update(status='interrupted' if isinstance(exc, KeyboardInterrupt) else 'failed',
                      success=False, runner_error=repr(exc),
                      finished_utc=datetime.now(timezone.utc).isoformat())
        write_json(out / 'receipt.json', record)
        print(record['runner_error'], file=sys.stderr, flush=True)
        return 130 if isinstance(exc, KeyboardInterrupt) else 1


if __name__ == '__main__':
    sys.exit(main())
