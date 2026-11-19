#!/usr/bin/env python3
"""Run the saved continuation plans, Python controls and browser compilers.

Source runtime/env.sh and fixtures/env.sh first. Output must be new and outside
the checkout. The shared test runner remains unchanged and supplies its own
complete reporter/source/runtime receipts. This driver also binds the actual
fixture environment forwarded to every subprocess and the gaps between gates.
No GitHub or GitHub Actions API is used.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + '\n')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--head', required=True)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--command-timeout', type=int, default=1200)
    args = parser.parse_args()
    repo, runtime, output = (p.resolve() for p in (args.repo, args.runtime, args.output))
    if output == repo or repo in output.parents:
        raise RuntimeError('Results must remain outside the source checkout')
    if output.exists() and any(output.iterdir()):
        raise RuntimeError('Use a new result directory; preserve earlier attempts')
    output.mkdir(parents=True, exist_ok=True)
    plan_dir = repo / 'docs/validation/office-finish-20261119'
    runner = repo / 'docs/validation/document-review-notes-20261118/run_checks.py'
    sys.path.insert(0, str(repo / 'tools/mail'))
    from check_store import execute

    def git(*argv: str) -> str:
        return subprocess.check_output(['git', '-C', str(repo), *argv], text=True).strip()

    head = git('rev-parse', args.head + '^{commit}')
    if git('rev-parse', 'HEAD') != head or git('status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('The committed source must be checked out and clean')
    base = 'b070e228a749e22cc8ce2098029a76ab5fb8eccb'
    declaration = runtime / 'fixture-environment.json'
    fixture = json.loads(declaration.read_text())
    env = dict(os.environ)
    forwarded = {name: env.get(name) for name in fixture['environment']}
    if forwarded != fixture['environment']:
        raise RuntimeError('Source the frozen runtime and fixture environment first')
    if digest(Path(fixture['script'])) != fixture['script_sha256']:
        raise RuntimeError('Fixture environment script changed')
    runtime_receipt = json.loads((runtime / 'runtime.json').read_text())
    for name, expected in runtime_receipt['additional_inputs'].items():
        if digest(Path(name)) != expected:
            raise RuntimeError('Additional fixture/runtime input changed: ' + name)

    tracked = git('ls-files', '-z').split('\0')
    source_paths = {p for p in tracked if p.startswith(('packages/', 'apps/', 'third_party/'))}
    source_paths.update(p for p in tracked if '/' not in p and Path(p).suffix in {'.yaml', '.lock'})
    for name in ['native-plan.json', 'node-plan.json']:
        plan = json.loads((plan_dir / name).read_text())
        source_paths.update(plan['extra_inputs'])
    source_paths.update([str(runner.relative_to(repo)), 'tools/mail/check_store.py', 'tools/mail/check_reader.py'])
    if not source_paths.issubset(set(tracked)):
        raise RuntimeError('All selected source and driver inputs must be committed')
    retained = json.loads((runtime / 'retained-inputs.json').read_text())
    environment_paths = {str(runtime / name) for name in retained}
    environment_paths.update(runtime_receipt['additional_inputs'])
    environment_paths.update(str(runtime / name) for name in [
        'runtime.json', 'retained-inputs.json', 'pub-cache-receipt.json', 'env.sh',
        'fixture-environment.json', 'runtime-fixture-addendum.json',
    ])
    environment_paths.update(str(repo / '.dart_tool' / name) for name in ['package_config.json', 'package_graph.json', 'native_assets.yaml'])

    def snapshot() -> dict:
        return {
            'head': git('rev-parse', 'HEAD'),
            'index_tree': git('write-tree'),
            'tracked_status': git('status', '--porcelain', '--untracked-files=no'),
            'source': {name: digest(repo / name) for name in sorted(source_paths)},
            'environment': {name: digest(Path(name)) for name in sorted(environment_paths)},
            'fixture_environment': {name: env.get(name) for name in fixture['environment']},
        }

    before = snapshot()
    write(output / 'inputs-before.json', before)
    record = {
        'source_commit': head, 'source_tree': git('rev-parse', head + '^{tree}'),
        'source_base': base, 'started_at_utc': datetime.now(timezone.utc).isoformat(),
        'fixture_environment': forwarded,
        'fixture_environment_receipt': str(declaration),
        'fixture_environment_receipt_sha256': digest(declaration),
        'fixture_environment_script_sha256': digest(Path(fixture['script'])),
        'runtime_receipt_sha256': digest(runtime / 'runtime.json'),
        'github_actions_queried_or_awaited': False, 'runs': [], 'success': False,
    }

    def save() -> None:
        write(output / 'verification.json', record)

    def run(name: str, command: list[str], timeout: int) -> dict:
        print('START ' + name, flush=True)
        log = output / (name + '.log')
        start = time.monotonic()
        with log.open('wb') as stream:
            try:
                code = execute(command, cwd=repo, env=env, stdout=stream, timeout=timeout)
            except (OSError, subprocess.TimeoutExpired) as error:
                stream.write((repr(error) + '\n').encode())
                code = 124 if isinstance(error, subprocess.TimeoutExpired) else 127
        item = {'name': name, 'command': command, 'exit_code': code,
                'log': log.name, 'log_sha256': digest(log),
                'elapsed_seconds': round(time.monotonic() - start, 3)}
        record['runs'].append(item)
        save()
        print(json.dumps(item), flush=True)
        if code:
            raise RuntimeError('Gate failed: ' + name)
        return item

    try:
        for name, directory, pattern, expected in [
            ('bundle-controls', 'tools/proofing/ayaspell', 'test_*.py', 17),
            ('packaging-controls', 'packages/quds_proofing_hunspell/tool', 'test_build.py', 4),
        ]:
            item = run(name, [sys.executable, '-B', '-m', 'unittest', 'discover',
                             '-s', directory, '-p', pattern, '-v'], args.command_timeout)
            log = (output / item['log']).read_text()
            cases = re.findall(r'^(test_\S+ \([^\n]+\)) \.\.\. ok$', log, flags=re.M)
            if (len(cases) != expected or len(set(cases)) != expected
                    or not re.search(rf'^Ran {expected} tests? in ', log, re.M)
                    or not re.search(r'^OK$', log, re.M)):
                raise RuntimeError('Incomplete or nonpassing named Python controls: ' + name)
            item.update(passed=expected, cases=cases)
            save()
        for name in ['native', 'node']:
            run(name, [sys.executable, '-B', str(runner), '--head', head, '--base', base,
                       '--plan', str(plan_dir / (name + '-plan.json')),
                       '--runtime', str(runtime), '--output', str(output / name),
                       '--command-timeout', str(args.command_timeout)],
                args.command_timeout * 8)
            accepted = json.loads((output / name / 'verification.json').read_text())
            if accepted.get('success') is not True:
                raise RuntimeError('Shared runner did not accept ' + name)
        browser = output / 'browser'
        browser.mkdir()
        for name, path in [
            ('hunspell-browser', 'packages/quds_proofing_hunspell/tool/web_compile_check.dart'),
            ('arabic-morph-browser', 'packages/quds_arabic_morph/tool/web_compile_check.dart'),
        ]:
            expected_js = browser / (name + '.js')
            run(name, [str(runtime / 'bin/dart'), 'compile', 'js',
                       '--packages=' + str(repo / '.dart_tool/package_config.json'),
                       str(repo / path), '-o', str(expected_js)], args.command_timeout)
            if not expected_js.is_file() or expected_js.stat().st_size == 0:
                raise RuntimeError('Compiler did not produce nonempty output: ' + name)
        record['browser_outputs'] = {
            p.relative_to(output).as_posix(): {'sha256': digest(p), 'bytes': p.stat().st_size}
            for p in sorted(browser.iterdir()) if p.is_file()
        }
        record['success'] = True
    except BaseException as error:
        record['error'] = repr(error)
    finally:
        after = snapshot()
        write(output / 'inputs-after.json', after)
        record.update(inputs_unchanged=before == after,
                      finished_at_utc=datetime.now(timezone.utc).isoformat(),
                      input_manifest_sha256={name: digest(output / name)
                                             for name in ['inputs-before.json', 'inputs-after.json']})
        record['success'] = record['success'] and before == after
        save()
        print(json.dumps({'success': record['success'], 'inputs_unchanged': before == after}), flush=True)
    return 0 if record['success'] else 1


if __name__ == '__main__':
    sys.exit(main())
