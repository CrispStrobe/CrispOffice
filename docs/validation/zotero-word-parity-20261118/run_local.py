#!/usr/bin/env python3
"""Run the exact local Zotero/Notes/Studio selection without GitHub Actions."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def counts(path):
    tests, finishes, errors = {}, {}, []
    completed = None
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get('type')
        if kind == 'testStart':
            tests[event['test']['id']] = event['test']
        elif kind == 'testDone':
            if event['testID'] in finishes:
                raise AssertionError('Duplicate test completion')
            finishes[event['testID']] = event
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            completed = event.get('success')
    visible = [(tests.get(identifier, {}), event)
               for identifier, event in finishes.items()
               if not event.get('hidden')
               and not tests.get(identifier, {}).get('name', '').startswith('loading ')]
    return {
        'passed': sum(e.get('result') == 'success' and not e.get('skipped') for _, e in visible),
        'failed': sum(e.get('result') != 'success' and not e.get('skipped') for _, e in visible),
        'skipped': sum(bool(e.get('skipped')) for _, e in visible),
        'errors': len(errors), 'done_success': completed,
        'unfinished': sorted(set(tests) - set(finishes)),
        'cases': [{'name': t.get('name'), 'url': t.get('url'),
                   'result': e.get('result'), 'skipped': bool(e.get('skipped'))}
                  for t, e in visible],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--expect-commit', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--plan', type=Path, default=Path(__file__).with_name('plan.json'))
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    plan = json.loads(args.plan.read_text())
    runtime = Path(os.environ['FLUTTER_ROOT'])
    dart = runtime / 'bin/cache/dart-sdk/bin/dart'
    flutter = runtime / 'bin/cache/flutter_tools.snapshot'

    def git(*command):
        return subprocess.check_output(['git', *command], cwd=repo, text=True).strip()

    def clean():
        if git('rev-parse', 'HEAD') != args.expect_commit:
            raise AssertionError('HEAD changed during qualification')
        if git('status', '--porcelain', '--untracked-files=no'):
            raise AssertionError('Tracked tree changed during qualification')

    def snapshot():
        sources = [p for p in git('ls-files').splitlines()
                   if (p.startswith(('packages/', 'apps/', 'third_party/'))
                       and p.endswith(('.dart', '.yaml')))
                   or p in ('.fvmrc', 'pubspec.yaml', 'analysis_options.yaml')]
        return {
            'commit': args.expect_commit, 'tree': git('rev-parse', 'HEAD^{tree}'),
            'files': {p: digest(repo / p) for p in sources},
            'lock_sha256': digest(repo / 'pubspec.lock'),
            'package_config_sha256': digest(repo / '.dart_tool/package_config.json'),
            'dart_sha256': digest(dart),
            'flutter_tester_sha256': digest(runtime / 'bin/cache/artifacts/engine/linux-x64/flutter_tester'),
        }

    results = {'commit': args.expect_commit, 'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'gates': {}}

    def run(name, command, cwd, is_tests=False):
        clean()
        started = time.time()
        receipt = {'command': [str(x) for x in command], 'cwd': str(cwd), 'status': 'running'}
        results['gates'][name] = receipt
        write_json(out / 'summary.json', results)
        path = out / (name + ('.jsonl' if is_tests else '.log'))
        try:
            with path.open('w') as log:
                process = subprocess.run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
            receipt.update(exit_code=process.returncode, seconds=round(time.time() - started, 3),
                           log_sha256=digest(path), status='completed')
            if is_tests:
                receipt.update(counts(path))
            write_json(out / 'summary.json', results)
            print(name, receipt.get('exit_code'), receipt.get('passed', ''), flush=True)
        except BaseException as error:
            receipt.update(status='interrupted', exception=type(error).__name__, seconds=round(time.time() - started, 3))
            write_json(out / 'summary.json', results)
            raise
        clean()

    clean()
    for gate in plan['test_gates'].values():
        for path in gate['tests']:
            git('ls-files', '--error-unmatch', str(Path(gate['package']) / path))
    before = snapshot()
    write_json(out / 'source-before.json', before)
    targets = plan['analysis_targets']
    run('analysis', [dart, 'analyze', '--fatal-infos', *targets], repo)
    run('format', [dart, 'format', '--output=none', '--set-exit-if-changed', *targets], repo)
    run('whitespace', ['git', 'diff', '--check', plan['baseline'], 'HEAD'], repo)
    for name, gate in plan['test_gates'].items():
        run(name, [dart, flutter, '--no-version-check', 'test', '--no-pub',
                   '--concurrency=' + str(gate['concurrency']), '--reporter=json', *gate['tests']],
            repo / gate['package'], is_tests=True)
    after = snapshot()
    write_json(out / 'source-after.json', after)
    results['source_unchanged'] = before == after
    results['passed'] = sum(g.get('passed', 0) for g in results['gates'].values())
    results['success'] = before == after and all(
        g.get('exit_code') == 0 and g.get('failed', 0) == 0 and g.get('errors', 0) == 0
        and g.get('done_success', True) is True and not g.get('unfinished', [])
        for g in results['gates'].values())
    results['finished_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    write_json(out / 'summary.json', results)
    for path in out.glob('*.jsonl'):
        with gzip.open(str(path) + '.gz', 'wb') as target:
            target.write(path.read_bytes())
        path.unlink()
    for path in (out / 'source-before.json', out / 'source-after.json'):
        with gzip.open(str(path) + '.gz', 'wb') as target:
            target.write(path.read_bytes())
        path.unlink()
    print(json.dumps({'success': results['success'], 'passed': results['passed']}), flush=True)
    return 0 if results['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
