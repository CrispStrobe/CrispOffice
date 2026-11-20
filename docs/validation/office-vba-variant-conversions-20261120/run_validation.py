#!/usr/bin/env python3
"""Run local, source-bound test cohorts without contacting hosted CI.

Requires the repository-pinned SDK and an already resolved locked workspace.
Raw events, commands, exit codes and input manifests remain in the output.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
import time


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def stamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def inputs(repo: Path) -> dict[str, dict[str, object]]:
    paths = subprocess.check_output([
        'git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard',
        'packages', 'apps', 'third_party', 'pubspec.yaml', 'pubspec.lock', '.fvmrc',
    ], cwd=repo).decode().split('\0')
    paths += ['.dart_tool/package_config.json',
              'docs/validation/office-vba-variant-conversions-20261120/run_validation.py',
              'docs/validation/office-vba-variant-conversions-20261120/run_portable.py']
    result = {}
    for relative in sorted(set(paths)):
        if not relative:
            continue
        path = repo / relative
        if path.is_file():
            result[relative] = {'sha256': digest(path), 'bytes': path.stat().st_size}
    return result


def summarize_events(path: Path) -> dict[str, object]:
    passed = skipped = failed = errors = 0
    success = False
    tests: dict[int, dict[str, object]] = {}
    cases = []
    messages = []
    # JSON Lines uses physical LF. Unicode separators can occur inside a name.
    for line in path.read_text(errors='replace').split('\n'):
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = event.get('type')
        if kind == 'testStart':
            tests[event['test']['id']] = event['test']
        elif kind == 'error':
            errors += 1
            messages.append({'testID': event.get('testID'), 'error': event.get('error')})
        elif kind == 'testDone' and not event.get('hidden', False):
            test = tests.get(event['testID'], {})
            if event.get('skipped', False):
                skipped += 1
            elif event.get('result') == 'success':
                passed += 1
            else:
                failed += 1
            cases.append({
                'name': test.get('name'), 'url': test.get('url'),
                'result': event.get('result'), 'skipped': event.get('skipped', False),
            })
        elif kind == 'done':
            success = event.get('success', False)
    return {
        'passed': passed, 'failed': failed, 'skipped': skipped, 'errors': errors,
        'runner_success': success, 'cases': cases, 'error_messages': messages,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--pub-cache', type=Path, required=True)
    parser.add_argument('--selection', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--workers', type=int, default=3)
    parser.add_argument('--only', nargs='*')
    args = parser.parse_args()
    repo, sdk, cache = (p.resolve() for p in (args.repo, args.sdk, args.pub_cache))
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    selection = json.loads(args.selection.read_text())['cohorts']
    if args.only:
        selection = {name: selection[name] for name in args.only}
    write_json(output / 'selection.json', {'cohorts': selection})
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    before = inputs(repo)
    manifest = json.dumps(before, sort_keys=True, separators=(',', ':')).encode()
    with gzip.open(output / 'inputs-before.json.gz', 'wb') as stream:
        stream.write(manifest)
    manifest_sha = hashlib.sha256(manifest).hexdigest()
    env = dict(os.environ, FLUTTER_ROOT=str(sdk), PUB_CACHE=str(cache), CI='true',
               FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true',
               DASH__SUPPRESS_ANALYTICS='true')
    env['PATH'] = str(sdk / 'bin') + ':' + env.get('PATH', '')
    dart = str(sdk / 'bin/cache/dart-sdk/bin/dart')
    package_config = repo / '.dart_tool/package_config.json'
    packages = json.loads(package_config.read_text())['packages']
    test_package = next(p for p in packages if p['name'] == 'test')
    from urllib.parse import unquote, urljoin, urlparse
    test_uri = urljoin(package_config.as_uri(), test_package['rootUri'])
    test_runner = str(Path(unquote(urlparse(test_uri).path)) / 'bin/test.dart')
    package_locks = {cohort['package']: threading.Lock() for cohort in selection.values()}

    def run(name: str, cohort: dict[str, object]) -> dict[str, object]:
        with package_locks[cohort['package']]:
            destination = output / name
            destination.mkdir()
            command = ([str(sdk / 'bin/flutter'), '--suppress-analytics', '--no-version-check',
                        'test', '--no-pub'] if cohort['runner'] == 'flutter'
                       else [dart, f'--packages={package_config}', test_runner])
            command += cohort.get('extra_args', [])
            command += cohort['tests'] + ['--reporter', 'json', '--concurrency', '1', '--timeout', '4x']
            cwd = repo / cohort['package']
            record = {
                'name': name, 'source_head': head, 'input_manifest_sha256': manifest_sha,
                'command': command, 'cwd': str(cwd), 'started_at': stamp(),
                'selected_files': cohort['tests'],
            }
            print(json.dumps({'started': name, 'files': len(cohort['tests'])}), flush=True)
            start = time.monotonic()
            with (destination / 'events.jsonl').open('wb') as stdout, (destination / 'stderr.log').open('wb') as stderr:
                try:
                    result = subprocess.run(command, cwd=cwd, env=env, stdout=stdout, stderr=stderr, timeout=1800)
                    record['exit_code'] = result.returncode
                except subprocess.TimeoutExpired:
                    record['exit_code'] = 'timeout'
            record['finished_at'] = stamp()
            record['seconds'] = time.monotonic() - start
            summary = summarize_events(destination / 'events.jsonl')
            write_json(destination / 'cases.json', summary.pop('cases'))
            record.update(summary)
            record['accepted'] = (record['exit_code'] == 0 and summary['runner_success']
                                  and summary['passed'] > 0 and summary['failed'] == 0
                                  and summary['errors'] == 0 and summary['skipped'] == 0)
            write_json(destination / 'receipt.json', record)
            print(json.dumps({k: record[k] for k in ('name', 'passed', 'failed', 'skipped', 'errors', 'accepted', 'seconds')}), flush=True)
            return record

    records = []
    groups: dict[str, list[tuple[str, dict[str, object]]]] = {}
    for name, cohort in selection.items():
        # The Flutter wrapper updates SDK stamp files before its package lock.
        # Serialize all Flutter launches, even for different packages, while
        # independent pure-Dart package groups can still execute concurrently.
        group_key = '__flutter_sdk__' if cohort['runner'] == 'flutter' else cohort['package']
        groups.setdefault(group_key, []).append((name, cohort))

    def run_package(group: list[tuple[str, dict[str, object]]]) -> list[dict[str, object]]:
        # Keep each shared cache serial without occupying workers waiting on
        # another cohort that uses the same SDK or package.
        return [run(name, cohort) for name, cohort in group]

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [executor.submit(run_package, group) for group in groups.values()]
        for future in as_completed(futures):
            records.extend(future.result())
    after = inputs(repo)
    changed = [path for path in sorted(before.keys() | after.keys()) if before.get(path) != after.get(path)]
    check = {'input_count': len(before), 'unchanged': not changed, 'changed': changed,
             'before_manifest_sha256': manifest_sha, 'checked_at': stamp()}
    write_json(output / 'input-check.json', check)
    summary = {
        'source_head': head, 'accepted': not changed and all(r['accepted'] for r in records),
        'input_check': check, 'cohorts': sorted(records, key=lambda r: r['name']),
        'total_passed_disjoint_selection': sum(r['passed'] for r in records),
        'no_hosted_ci_queried_or_awaited': True,
    }
    write_json(output / 'summary.json', summary)
    print(json.dumps({'accepted': summary['accepted'], 'passed': summary['total_passed_disjoint_selection'],
                      'changed_inputs': changed}), flush=True)
    raise SystemExit(0 if summary['accepted'] else 1)


if __name__ == '__main__':
    main()
