#!/usr/bin/env python3
"""Run one local gate with source hashes and raw process/test receipts."""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(repo):
    paths = set()
    for package in ('quds_office_engine', 'quds_office_editor', 'legacy_doc_parser'):
        root = repo / 'packages' / package
        for directory in ('lib', 'test', 'tool'):
            paths.update(p for p in (root / directory).rglob('*') if p.is_file())
        for name in ('pubspec.yaml', 'analysis_options.yaml'):
            if (root / name).is_file():
                paths.add(root / name)
    for name in ('pubspec.lock', 'pubspec.yaml', 'analysis_options.yaml', '.dart_tool/package_config.json'):
        if (repo / name).is_file():
            paths.add(repo / name)
    return {str(p.relative_to(repo)): digest(p) for p in sorted(paths)}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--cwd', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--test-events', action='store_true')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('A command after -- is required')
    repo = args.repo.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    before = snapshot(repo)
    inputs = json.dumps(before, sort_keys=True).encode()
    (output / 'inputs.json.gz').write_bytes(gzip.compress(inputs, mtime=0))
    receipt = {
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'source_head': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
        'cwd': str(args.cwd.resolve()),
        'command': command,
        'input_count': len(before),
        'input_manifest_sha256': hashlib.sha256(inputs).hexdigest(),
    }
    write_json(output / 'receipt.json', receipt)
    started = time.monotonic()
    with (output / 'stdout.log').open('wb') as stdout, (output / 'stderr.log').open('wb') as stderr:
        result = subprocess.run(command, cwd=args.cwd.resolve(), stdout=stdout, stderr=stderr)
    receipt.update(exit_code=result.returncode, duration_seconds=round(time.monotonic() - started, 3))
    after = snapshot(repo)
    changed = sorted(path for path in before.keys() | after.keys() if before.get(path) != after.get(path))
    receipt['inputs_unchanged'] = not changed
    receipt['changed_inputs'] = changed
    good = result.returncode == 0 and not changed
    if args.test_events:
        suites, tests, completed, errors, done, unparsed = {}, {}, [], [], [], []
        for line in (output / 'stdout.log').read_text(errors='replace').splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                unparsed.append(line)
                continue
            if event.get('type') == 'suite':
                suites[event['suite']['id']] = event['suite']
            elif event.get('type') == 'testStart':
                tests[event['test']['id']] = event['test']
            elif event.get('type') == 'testDone':
                completed.append(event)
            elif event.get('type') == 'error':
                errors.append(event)
            elif event.get('type') == 'done':
                done.append(event)
        identities = []
        failures, skips = [], []
        for event in completed:
            if event.get('hidden'):
                continue
            test = tests.get(event['testID'], {})
            identity = {'path': suites.get(test.get('suiteID'), {}).get('path'), 'name': test.get('name')}
            if event.get('skipped'):
                skips.append(identity)
            elif event.get('result') == 'success':
                identities.append(identity)
            else:
                failures.append(identity)
        receipt['tests'] = {'passed': len(identities), 'failed': len(failures), 'skipped': len(skips),
                            'errors': len(errors), 'suites': len(suites), 'done': done,
                            'failures': failures, 'skips': skips, 'unparsed_lines': unparsed}
        write_json(output / 'test-identities.json', identities)
        good = good and bool(identities) and not failures and not skips and not errors and len(done) == 1 and done[0].get('success') is True
    for name in ('stdout.log', 'stderr.log'):
        path = output / name
        data = path.read_bytes()
        receipt[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        (output / (name + '.gz')).write_bytes(gzip.compress(data, mtime=0))
    receipt['accepted'] = good
    receipt['finished_utc'] = datetime.now(timezone.utc).isoformat()
    write_json(output / 'receipt.json', receipt)
    print(json.dumps({k: receipt[k] for k in ('source_head', 'exit_code', 'input_count', 'inputs_unchanged', 'accepted')}))
    if 'tests' in receipt:
        print(json.dumps({k: receipt['tests'][k] for k in ('passed', 'failed', 'skipped', 'errors', 'suites')}))
    raise SystemExit(0 if good else 1)


if __name__ == '__main__':
    main()
