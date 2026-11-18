#!/usr/bin/env python3
"""Invoke a retained consumer gate with external source/runtime stability seals."""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gate', choices=['retained33', 'current7', 'boundary5', 'frame5'], required=True)
    for name in ['repo', 'workspace', 'dart', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    repo, workspace, dart, output = [p.resolve() for p in [args.repo, args.workspace, args.dart, args.output]]
    root = Path(__file__).resolve().parent
    consumer = root / 'consumer-runtime/retained-reference'
    schemas = consumer / 'schemas'
    guard = repo / 'docs/validation/office-union-20261117/setup/guard_frozen_run.py'
    run = output / 'run'
    assert not output.exists(), 'Refusing to overwrite an existing attempt'
    output.mkdir(parents=True)
    extra = [Path(__file__).resolve()]
    if args.gate in {'retained33', 'current7'}:
        runner = consumer / ('wave3-runner/verify_consumers.py' if args.gate == 'retained33' else 'verify_current_consumers.py')
        command = [sys.executable, runner, '--repo', workspace, '--source-repo', repo,
                   '--expected-head', args.commit, '--schemas', schemas, '--dart', dart, '--output', run]
        extra.append(runner)
    elif args.gate == 'boundary5':
        runner = repo / 'docs/validation/office-reconciled-20261117/resume/consumer-new/verify_boundary_consumers.py'
        command = [sys.executable, runner, '--repo', repo, '--workspace', workspace,
                   '--dart', dart, '--schemas', schemas, '--output', run, '--commit', args.commit]
        extra.extend([runner, runner.with_name('make_boundary_fixtures.dart')])
    else:
        runner = repo / 'docs/validation/gector-office-resume-20261117/office-consumer/run_consumers.py'
        command = [sys.executable, runner, '--repo', repo,
                   '--package-config', workspace / '.dart_tool/package_config.json',
                   '--jing', consumer / 'tools/jing-20241231.jar', '--schemas', schemas, '--output', run]
        extra.extend([runner, runner.with_name('make_fixtures.dart')])
    argv = [sys.executable, guard, '--repo', repo, '--workspace', workspace,
            '--dart', dart, '--consumer-root', consumer, '--output', output / 'guard', '--commit', args.commit]
    for path in extra:
        argv.extend(['--extra-input', path])
    argv.extend(['--', *command])
    argv = [str(value) for value in argv]
    env = dict(os.environ, TMPDIR=str(root / 'consumer-runtime/tmp'),
               XDG_CONFIG_HOME=str(root / 'consumer-runtime/config'),
               CI='true', DART_SUPPRESS_ANALYTICS='true', DASH__SUPPRESS_ANALYTICS='true',
               FLUTTER_SUPPRESS_ANALYTICS='true', PYTHONDONTWRITEBYTECODE='1')
    env['PATH'] = str(dart.parent) + os.pathsep + env.get('PATH', '')
    record = {'gate': args.gate, 'source_commit': args.commit,
              'started_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'command': argv, 'cwd': str(repo),
              'launcher_sha256': sha(Path(__file__).resolve()),
              'retained_oracle_modified': False,
              'scope': 'Fresh source-bound consumer run; historical references retain their original attribution.'}
    (output / 'invocation.json').write_text(json.dumps(record, indent=2) + '\n')
    with (output / 'launcher.stdout.log').open('wb') as stdout, (output / 'launcher.stderr.log').open('wb') as stderr:
        result = subprocess.run(argv, cwd=repo, env=env, stdout=stdout, stderr=stderr, check=False)
    record['exit_code'] = result.returncode
    record['finished_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    if (output / 'guard/receipt.json').is_file():
        record['guard'] = json.loads((output / 'guard/receipt.json').read_text())
    (output / 'invocation.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'gate': args.gate, 'exit_code': result.returncode, 'output': str(output),
                      'guard_passed': record.get('guard', {}).get('passed'),
                      'error': record.get('guard', {}).get('error')}), flush=True)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
