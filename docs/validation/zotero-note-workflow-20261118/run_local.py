#!/usr/bin/env python3
"""Run the saved local Zotero and affected-workflow selection without CI."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--repo', required=True, type=Path)
parser.add_argument('--expect-commit', required=True)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--plan', type=Path, default=Path(__file__).with_name('plan.json'))
parser.add_argument('--analysis-targets', required=True, type=Path)
args = parser.parse_args()
repo = args.repo.resolve()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
plan = json.loads(args.plan.read_text())
dart = str(Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/dart-sdk/bin/dart')
flutter = str(Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/flutter_tools.snapshot')


def git(*command):
    return subprocess.check_output(['git', *command], cwd=repo).decode().strip()


def clean():
    assert git('rev-parse', 'HEAD') == args.expect_commit, 'HEAD changed'
    assert not git('status', '--porcelain', '--untracked-files=no'), 'Tracked tree changed'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot():
    paths = [p for p in git('ls-files').splitlines()
             if (p.startswith(('packages/', 'apps/')) and p.endswith(('.dart', '.yaml')))
             or p in ('.fvmrc', 'pubspec.yaml', 'analysis_options.yaml')]
    return {
        'commit': args.expect_commit,
        'tree': git('rev-parse', 'HEAD^{tree}'),
        'files': {p: digest(repo / p) for p in paths},
        'lock_sha256': digest(repo / 'pubspec.lock'),
        'package_config_sha256': digest(repo / '.dart_tool/package_config.json'),
        'dart_sha256': digest(Path(dart)),
        'flutter_tester_sha256': digest(Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/artifacts/engine/linux-x64/flutter_tester'),
    }


def run(name, command, cwd):
    started = time.time()
    with (out / (name + '.log')).open('w') as log:
        result = subprocess.run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
    return {'command': command, 'cwd': str(cwd), 'exit_code': result.returncode,
            'seconds': round(time.time() - started, 3)}


def counts(path):
    tests, finishes, errors = {}, {}, []
    done = None
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
            assert event['testID'] not in finishes, 'Duplicate test completion'
            finishes[event['testID']] = event
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            done = event.get('success')
    visible = [e for ident, e in finishes.items()
               if not e.get('hidden') and not tests.get(ident, {}).get('name', '').startswith('loading ')]
    return {
        'passed': sum(e.get('result') == 'success' and not e.get('skipped') for e in visible),
        'failed': sum(e.get('result') != 'success' and not e.get('skipped') for e in visible),
        'skipped': sum(bool(e.get('skipped')) for e in visible),
        'errors': len(errors), 'done_success': done,
        'unfinished': sorted(set(tests) - set(finishes)),
    }


clean()
before = snapshot()
(out / 'source-before.json').write_text(json.dumps(before, indent=2) + '\n')
results = {}
targets = json.loads(args.analysis_targets.read_text())
for name, command in [
    ('analysis', [dart, 'analyze', '--fatal-infos', *targets]),
    ('format', [dart, 'format', '--output=none', '--set-exit-if-changed', *targets]),
    ('whitespace', ['git', 'diff', '--check', 'HEAD^', 'HEAD']),
]:
    results[name] = run(name, command, repo)
    print(name, results[name]['exit_code'], flush=True)
for name, gate in plan.items():
    clean()
    command = [dart, flutter, '--no-version-check', 'test', '--no-pub',
               '--concurrency=' + str(gate['concurrency']), '--reporter=json', *gate['tests']]
    results[name] = run(name, command, repo / gate['package'])
    results[name].update(counts(out / (name + '.log')))
    print(name, json.dumps({k: v for k, v in results[name].items() if k not in ('command', 'cwd')}), flush=True)
clean()
after = snapshot()
(out / 'source-after.json').write_text(json.dumps(after, indent=2) + '\n')
assert before == after, 'Source/runtime/dependency binding changed'
results['binding'] = {'unchanged': True, 'files': len(before['files']), 'commit': args.expect_commit}
results['total_passed'] = sum(results[name]['passed'] for name in plan)
results['success'] = all(results[name]['exit_code'] == 0 for name in results if isinstance(results[name], dict) and 'exit_code' in results[name]) and all(results[name]['done_success'] and not results[name]['failed'] and not results[name]['skipped'] and not results[name]['errors'] and not results[name]['unfinished'] for name in plan)
(out / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
for name in plan:
    path = out / (name + '.log')
    (out / (name + '.jsonl.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
print('complete', results['total_passed'], results['success'], flush=True)
raise SystemExit(0 if results['success'] else 1)
