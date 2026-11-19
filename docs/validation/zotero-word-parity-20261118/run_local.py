#!/usr/bin/env python3
"""Qualify one frozen Zotero/Notes/Mail selection without GitHub Actions."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def suite_path(path, cwd):
    """Resolve reporter paths against the test process, not this runner's cwd."""
    if path.startswith('file:'):
        uri = urlparse(path)
        if uri.netloc not in ('', 'localhost'):
            raise ValueError('Nonlocal suite URI')
        path = unquote(uri.path)
    source = Path(path)
    return str((source if source.is_absolute() else cwd / source).resolve())


def counts(path, cwd, requested):
    """Count completed user cases and reject incomplete or ambiguous evidence."""
    tests, finishes, suites, errors, issues = {}, {}, {}, [], []
    starts = terminals = 0
    completed = None
    excluded = Counter()
    expected = {suite_path(name, cwd) for name in requested}
    for number, line in enumerate(path.read_text(errors='replace').splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        # Native build-hook progress can prefix a reporter object on one line.
        brace = line.find('{')
        candidate = line[brace:] if brace >= 0 else line
        try:
            event = json.loads(candidate)
        except ValueError:
            if brace >= 0 or line.startswith('['):
                issues.append({'line': number, 'problem': 'malformed JSON event'})
            continue  # Ordinary Flutter/build progress is not a reporter event.
        if not isinstance(event, dict):
            issues.append({'line': number, 'problem': 'event is not an object'})
            continue
        kind = event.get('type')
        if not isinstance(kind, str):
            issues.append({'line': number, 'problem': 'missing event type'})
            continue
        if terminals:
            issues.append({'line': number, 'problem': 'event after terminal'})
        if kind == 'start':
            starts += 1
            if starts != 1:
                issues.append({'line': number, 'problem': 'duplicate runner start'})
        elif starts != 1:
            issues.append({'line': number, 'problem': 'event without one runner start'})
        try:
            if kind == 'suite':
                suite = event['suite']
                identifier, source = suite['id'], suite['path']
                if type(identifier) is not int or not isinstance(source, str):
                    raise ValueError('Invalid suite identity')
                resolved = suite_path(source, cwd)
                if identifier in suites or resolved in suites.values():
                    issues.append({'line': number, 'problem': 'duplicate suite'})
                else:
                    suites[identifier] = resolved
            elif kind == 'testStart':
                case = event['test']
                identifier = case['id']
                if (type(identifier) is not int or type(case['suiteID']) is not int
                        or not isinstance(case['name'], str)):
                    raise ValueError('Invalid test identity')
                if identifier in tests:
                    issues.append({'line': number, 'problem': 'duplicate test start'})
                else:
                    tests[identifier] = case
            elif kind == 'testDone':
                identifier = event['testID']
                if type(identifier) is not int or identifier not in tests:
                    issues.append({'line': number, 'problem': 'unmatched test completion'})
                    continue
                if identifier in finishes:
                    issues.append({'line': number, 'problem': 'duplicate test completion'})
                    continue
                if (event['result'] not in ('success', 'failure', 'error')
                        or type(event['skipped']) is not bool
                        or type(event['hidden']) is not bool):
                    raise ValueError('Invalid test completion')
                finishes[identifier] = event
            elif kind == 'error':
                errors.append(event)
            elif kind == 'done':
                terminals += 1
                if terminals != 1 or type(event['success']) is not bool:
                    raise ValueError('Invalid terminal result')
                completed = event['success']
            elif kind not in ('start', 'group', 'allSuites', 'print', 'debug'):
                raise ValueError('Unknown reporter event: ' + kind)
        except (KeyError, TypeError, ValueError) as error:
            issues.append({'line': number, 'problem': str(error)})
    cases = []
    for identifier, event in finishes.items():
        case = tests[identifier]
        source = suites.get(case['suiteID'])
        if source is None:
            issues.append({'test_id': identifier, 'problem': 'unknown suite'})
        name = case['name']
        fixture = name.startswith('loading ') or re.search(
            r'(?:^|\s)\((?:setUpAll|tearDownAll)\)$', name)
        if event['hidden'] or fixture:
            excluded['hidden' if event['hidden'] else 'loading_or_fixture'] += 1
            if event['result'] != 'success' or event['skipped']:
                issues.append({'test_id': identifier, 'problem': 'failed/skipped hidden event'})
            continue
        cases.append({'id': identifier, 'suite': source, 'name': name,
                      'result': event['result'], 'skipped': event['skipped']})
    per_suite = {}
    for case in cases:
        row = per_suite.setdefault(case['suite'], {'passed': 0, 'failed': 0, 'skipped': 0})
        row['passed'] += int(case['result'] == 'success' and not case['skipped'])
        row['failed'] += int(case['result'] != 'success' and not case['skipped'])
        row['skipped'] += int(case['skipped'])
    observed = set(suites.values())
    result = {
        'passed': sum(row['passed'] for row in per_suite.values()),
        'failed': sum(row['failed'] for row in per_suite.values()),
        'skipped': sum(row['skipped'] for row in per_suite.values()),
        'errors': len(errors), 'done_success': completed,
        'runner_starts': starts, 'terminal_events': terminals,
        'unfinished': sorted(set(tests) - set(finishes)),
        'missing_requested_suites': sorted(expected - observed),
        'unexpected_suites': sorted(observed - expected),
        'empty_requested_suites': sorted(expected - set(per_suite)),
        'protocol_issues': issues, 'per_suite': per_suite,
        'excluded_events': dict(excluded), 'cases': cases, 'error_events': errors,
    }
    result['valid'] = (starts == 1 and terminals == 1 and completed is True
                       and result['passed'] > 0 and not any(result[key] for key in (
                           'failed', 'skipped', 'errors', 'unfinished',
                           'missing_requested_suites', 'unexpected_suites',
                           'empty_requested_suites', 'protocol_issues')))
    return result


def python_counts(path):
    """Keep support-unit-test counts separate from Dart application cases."""
    lines = path.read_text(errors='replace').splitlines()
    totals = [int(match.group(1)) for line in lines
              if (match := re.fullmatch(r'Ran (\d+) tests? in .+', line))]
    valid = len(totals) == 1 and totals[0] > 0 and lines[-1:] == ['OK']
    return {'python_passed': totals[0] if valid else 0, 'valid': valid}


def validate_plan(plan, repo, tracked):
    """Resolve every input and reject duplicate suites before starting tools."""
    def tracked_file(name):
        if not isinstance(name, str) or Path(name).is_absolute():
            raise ValueError('Plan inputs must be repository-relative paths')
        source = (repo / name).resolve()
        canonical = source.relative_to(repo).as_posix()
        if canonical not in tracked or not source.is_file():
            raise ValueError('Plan input must be a tracked existing file: ' + name)
        return canonical

    gates = plan['test_gates']
    if not isinstance(gates, dict) or not gates:
        raise ValueError('Plan must contain test gates')
    names = {'analysis', 'format', 'whitespace'}
    requested, inputs = [], set()
    for name, gate in gates.items():
        if not re.fullmatch(r'[a-z0-9_-]+', name) or name in names:
            raise ValueError('Test gate names must be unique safe filenames')
        names.add(name)
        if gate.get('runner', 'flutter') not in ('dart', 'flutter'):
            raise ValueError('Unknown test runner')
        if type(gate['concurrency']) is not int or gate['concurrency'] < 1:
            raise ValueError('Test concurrency must be positive')
        if not isinstance(gate['tests'], list) or not gate['tests']:
            raise ValueError('Test gates must not be empty')
        for source in gate['tests']:
            if not isinstance(source, str) or not source.endswith('_test.dart'):
                raise ValueError('Expected a Dart test filename')
            relative = tracked_file(str(Path(gate['package']) / source))
            requested.append(relative)
            inputs.add(relative)
    if len(requested) != len(set(requested)):
        raise ValueError('A test file appears more than once in the plan')
    targets = [tracked_file(name) for name in plan['analysis_targets']]
    if len(targets) != len(set(targets)) or any(not name.endswith('.dart') for name in targets):
        raise ValueError('Analysis targets must be unique Dart source files')
    inputs.update(targets)
    for name, source in plan.get('support_tests', {}).items():
        if not re.fullmatch(r'[a-z0-9_-]+', name) or name in names:
            raise ValueError('Support gate names must be unique safe filenames')
        names.add(name)
        canonical = tracked_file(source)
        if not canonical.endswith('.py'):
            raise ValueError('Expected a Python unittest filename')
        inputs.add(canonical)
    inputs.update(tracked_file(name) for name in plan.get('fingerprint_inputs', []))
    return requested, inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--expect-commit', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--plan', type=Path, default=Path(__file__).with_name('plan.json'))
    parser.add_argument('--environment-input', type=Path, action='append', default=[])
    parser.add_argument('--command-timeout', type=int, default=1800)
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.output.resolve()
    if out == repo or repo in out.parents:
        raise ValueError('Keep qualification output outside the frozen checkout')
    out.mkdir(parents=True, exist_ok=False)
    plan_path = args.plan.resolve()
    plan = json.loads(plan_path.read_text())
    runtime = Path(os.environ['FLUTTER_ROOT']).resolve()
    dart = runtime / 'bin/cache/dart-sdk/bin/dart'
    flutter = runtime / 'bin/cache/flutter_tools.snapshot'

    def git(*command):
        return subprocess.check_output(['git', *command], cwd=repo, text=True).strip()

    expected_commit = git('rev-parse', '--verify', args.expect_commit + '^{commit}')

    def clean():
        if git('rev-parse', 'HEAD') != expected_commit:
            raise AssertionError('HEAD changed during qualification')
        if git('status', '--porcelain', '--untracked-files=no'):
            raise AssertionError('Tracked tree changed during qualification')
        untracked = git('ls-files', '--others', '--exclude-standard').splitlines()
        if any(path.startswith(('packages/', 'apps/', 'third_party/')) for path in untracked):
            raise AssertionError('Untracked product inputs could affect qualification')

    clean()
    tracked = set(git('ls-files').splitlines())
    requested, extra_inputs = validate_plan(plan, repo, tracked)
    for source in (plan_path, Path(__file__).resolve()):
        name = source.relative_to(repo).as_posix()
        if name not in tracked:
            raise ValueError('Commit the plan and runner before qualification')
        extra_inputs.add(name)
    environment_inputs = {str(path.resolve()): path.resolve() for path in args.environment_input}
    if any(not path.is_file() for path in environment_inputs.values()):
        raise ValueError('An explicit environment fingerprint input is missing')

    def snapshot():
        sources = {p for p in tracked
                   if (p.startswith(('packages/', 'apps/', 'third_party/'))
                       and p.endswith(('.dart', '.yaml', '.lock')))
                   or p in ('.fvmrc', 'pubspec.yaml', 'analysis_options.yaml')}
        sources.update(extra_inputs)
        return {
            'commit': expected_commit, 'tree': git('rev-parse', 'HEAD^{tree}'),
            'files': {p: digest(repo / p) for p in sorted(sources)},
            'plan_sha256': digest(plan_path),
            'runner_sha256': digest(Path(__file__).resolve()),
            'lock_sha256': digest(repo / 'pubspec.lock'),
            'package_config_sha256': digest(repo / '.dart_tool/package_config.json'),
            'dart_sha256': digest(dart),
            'flutter_tools_sha256': digest(flutter),
            'flutter_tester_sha256': digest(runtime / 'bin/cache/artifacts/engine/linux-x64/flutter_tester'),
            'python_sha256': digest(Path(sys.executable).resolve()),
            'environment_inputs': {name: digest(path) for name, path in environment_inputs.items()},
        }

    results = {
        'commit': expected_commit,
        'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'plan': plan_path.relative_to(repo).as_posix(), 'plan_sha256': digest(plan_path),
        'runner_sha256': digest(Path(__file__).resolve()),
        'distinct_test_files': len(requested), 'requested_test_files': requested,
        'github_actions_queried_or_awaited': False, 'gates': {},
    }

    def run(name, command, cwd, test_files=None, python_tests=False):
        clean()
        started = time.time()
        receipt = {'command': [str(x) for x in command], 'cwd': str(cwd), 'status': 'running'}
        results['gates'][name] = receipt
        write_json(out / 'summary.json', results)
        path = out / (name + ('.jsonl' if test_files is not None else '.log'))
        try:
            with path.open('w') as log:
                try:
                    process = subprocess.run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                                             timeout=args.command_timeout)
                    code = process.returncode
                except subprocess.TimeoutExpired:
                    code = 124
                    receipt['timeout_seconds'] = args.command_timeout
            receipt.update(exit_code=code, seconds=round(time.time() - started, 3),
                           log=path.name, log_sha256=digest(path), status='completed')
            if test_files is not None:
                parsed = counts(path, cwd, test_files)
                for key in ('cases', 'error_events'):
                    detail = out / (name + '-' + key + '.json')
                    write_json(detail, parsed.pop(key))
                    receipt[key + '_file'] = detail.name
                    receipt[key + '_sha256'] = digest(detail)
                receipt.update(parsed)
            elif python_tests:
                receipt.update(python_counts(path))
            receipt['accepted'] = code == 0 and receipt.get('valid', True)
            if test_files is not None:
                compressed = Path(str(path) + '.gz')
                compressed.write_bytes(gzip.compress(path.read_bytes(), mtime=0))
                receipt.update(compressed_log=compressed.name, compressed_log_sha256=digest(compressed))
                path.unlink()
            write_json(out / 'summary.json', results)
            print(name, code, receipt.get('passed', receipt.get('python_passed', '')),
                  'accepted=' + str(receipt['accepted']), flush=True)
        except BaseException as error:
            receipt.update(status='interrupted', exception=type(error).__name__,
                           seconds=round(time.time() - started, 3), accepted=False)
            write_json(out / 'summary.json', results)
            raise
        clean()

    before = snapshot()
    write_json(out / 'source-before.json', before)
    expected_gates = 3 + len(plan['test_gates']) + len(plan.get('support_tests', {}))
    try:
        for name, source in plan.get('support_tests', {}).items():
            run(name, [sys.executable, '-B', '-m', 'unittest', 'discover',
                       '-s', str(Path(source).parent), '-p', Path(source).name, '-v'],
                repo, python_tests=True)
        targets = plan['analysis_targets']
        run('analysis', [dart, 'analyze', '--fatal-infos', *targets], repo)
        run('format', [dart, 'format', '--output=none', '--set-exit-if-changed', *targets], repo)
        run('whitespace', ['git', 'diff', '--check', plan['baseline'], 'HEAD'], repo)
        for name, gate in plan['test_gates'].items():
            command = ([dart, 'test'] if gate.get('runner', 'flutter') == 'dart' else
                       [dart, flutter, '--no-version-check', 'test', '--no-pub'])
            command += ['--concurrency=' + str(gate['concurrency']), '--reporter=json', *gate['tests']]
            run(name, command, repo / gate['package'], test_files=gate['tests'])
    except BaseException as error:
        results['runner_error'] = repr(error)
        write_json(out / 'summary.json', results)
        raise
    finally:
        after = snapshot()
        write_json(out / 'source-after.json', after)
        results['source_unchanged'] = before == after
        results['source_head_unchanged'] = git('rev-parse', 'HEAD') == expected_commit
        results['tracked_worktree_clean_after'] = not git(
            'status', '--porcelain', '--untracked-files=no')
        results['untracked_product_inputs_after'] = [
            path for path in git('ls-files', '--others', '--exclude-standard').splitlines()
            if path.startswith(('packages/', 'apps/', 'third_party/'))]
        results['passed'] = sum(g.get('passed', 0) for g in results['gates'].values())
        results['python_passed'] = sum(g.get('python_passed', 0) for g in results['gates'].values())
        results['success'] = (not results.get('runner_error') and before == after
                              and results['source_head_unchanged']
                              and results['tracked_worktree_clean_after']
                              and not results['untracked_product_inputs_after']
                              and len(results['gates']) == expected_gates
                              and all(g.get('accepted') is True for g in results['gates'].values()))
        results['finished_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        for path in (out / 'source-before.json', out / 'source-after.json'):
            compressed = Path(str(path) + '.gz')
            compressed.write_bytes(gzip.compress(path.read_bytes(), mtime=0))
            results[path.stem + '_sha256'] = digest(path)
            results[path.stem + '_compressed_sha256'] = digest(compressed)
            path.unlink()
        write_json(out / 'summary.json', results)
    print(json.dumps({key: results[key] for key in ('success', 'passed', 'python_passed')}), flush=True)
    return 0 if results['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
