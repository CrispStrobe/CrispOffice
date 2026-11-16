"""Source-bound local ODS reader/writer qualification for the observed PR base."""
from pathlib import Path
import argparse
import collections
import datetime
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys

FILES = ['test/ods_sheet_reader_test.dart', 'test/ods_sheet_writer_test.dart']

PREFIX = 'engine-pr-base'
RUNTIME_INPUTS = {'.dart_tool/package_config.json', 'pubspec.lock'}


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def write_json(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False)
        stream.write('\n')


def snapshot(root):
    paths = []
    for package in (root / 'packages').iterdir():
        if package.is_dir():
            paths.extend((package / 'lib').rglob('*.dart'))
            if (package / 'pubspec.yaml').is_file():
                paths.append(package / 'pubspec.yaml')
    work = root / 'packages/quds_office_engine'
    paths.extend(path for path in (work / 'test').rglob('*') if path.is_file())
    paths.extend((work / 'tool').rglob('*.dart'))
    paths.extend(path for path in (root / 'packages/quds_office_editor/fonts').rglob('*') if path.is_file())
    paths.extend(root / name for name in ('pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json') if (root / name).is_file())
    hashes = {}
    git_blobs = {}
    for path in sorted(set(paths)):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        data = path.read_bytes()
        hashes[relative] = sha256(data)
        git_blobs[relative] = hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()
    return hashes, git_blobs


def published_blob_mismatches(root, head, blobs):
    listing = subprocess.check_output(['git', 'ls-tree', '-r', '-z', head], cwd=root)
    expected = {}
    for entry in listing.split(b'\0'):
        if not entry:
            continue
        metadata, path = entry.split(b'\t', 1)
        _mode, kind, oid = metadata.split()
        if kind == b'blob':
            expected[path.decode()] = oid.decode()
    return [path for path, oid in blobs.items() if (path not in RUNTIME_INPUTS or path in expected) and expected.get(path) != oid]


def parse_events(path):
    suites, tests, outcomes = {}, {}, {}
    errors, malformed = [], []
    done = None
    for number, line in enumerate(path.read_text().splitlines(), 1):
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            malformed.append(number)
            continue
        kind = event.get('type')
        if kind == 'suite':
            suite = event['suite']
            suites[suite['id']] = suite
        elif kind == 'testStart':
            test = event['test']
            tests[test['id']] = test
        elif kind == 'testDone':
            outcomes[event['testID']] = event
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            done = event
    counts = collections.Counter()
    per_file = collections.defaultdict(collections.Counter)
    failures, hidden_failures, skips, unfinished = [], [], [], []
    for identity, test in tests.items():
        outcome = outcomes.get(identity)
        path = suites.get(test['suiteID'], {}).get('path')
        item = {'name': test['name'], 'path': path, 'test_id': identity}
        if outcome is None:
            unfinished.append(item)
            continue
        status = 'skipped' if outcome.get('skipped') else outcome['result']
        if outcome.get('hidden'):
            if status not in ('success', 'skipped'):
                hidden_failures.append(item)
            continue
        counts[status] += 1
        per_file[path][status] += 1
        if status == 'skipped':
            skips.append(item)
        elif status != 'success':
            failures.append(item)
    return {
        'runner_done': done,
        'distinct_visible_tests': sum(counts.values()),
        'counts': dict(counts),
        'failures': failures,
        'hidden_failures': hidden_failures,
        'skips': skips,
        'unfinished_tests': unfinished,
        'per_file': {path: dict(value) for path, value in sorted(per_file.items())},
        'observed_suite_files': sorted({suite['path'] for suite in suites.values()}),
        'malformed_event_lines': malformed,
        'runner_errors': errors,
        'counting_rule': 'Distinct visible test IDs; hidden load/setup events excluded from counts and hidden failures retained separately. Skips are not passes.',
    }


def archive(source, target):
    data = source.read_bytes()
    compressed = gzip.compress(data, mtime=0)
    with target.open('xb') as stream:
        stream.write(compressed)
    return {
        'path': target.name,
        'uncompressed_bytes': len(data),
        'compressed_bytes': len(compressed),
        'uncompressed_sha256': sha256(data),
        'archive_sha256': sha256(compressed),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--expected-head', required=True, help='Exact frozen and published 40-character commit SHA.')
    parser.add_argument('--published-ref', default='refs/remotes/origin/codex/text-rendering-20261116')
    args = parser.parse_args()
    root = args.repo.resolve()
    work = root / 'packages/quds_office_engine'
    evidence = root / 'docs/validation/text-rendering-20261116'
    scratch = Path(os.environ['TMPDIR'])
    dart = Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/dart-sdk/bin/dart'
    assert len(args.expected_head) == 40 and all(c in '0123456789abcdef' for c in args.expected_head)
    assert len(FILES) == 2 and all((work / name).is_file() for name in FILES)
    assert dart.is_file()
    head = git(root, 'rev-parse', 'HEAD')
    published = git(root, 'rev-parse', args.published_ref)
    assert head == args.expected_head, (head, args.expected_head)
    assert published == args.expected_head, ('Refresh the pinned work-branch tracking ref after publication.', published, args.expected_head)
    assert git(root, 'rev-parse', '--show-object-format') == 'sha1'
    before, before_blobs = snapshot(root)
    unpublished = published_blob_mismatches(root, head, before_blobs)
    assert not unpublished, ('Inputs differ from the frozen published source.', unpublished)
    dependency_receipt = 'docs/validation/text-rendering-20261116/resolved-dependencies.yaml'
    committed_lock = subprocess.check_output(['git', 'show', args.expected_head + ':' + dependency_receipt], cwd=root)
    assert (root / 'pubspec.lock').read_bytes() == committed_lock, 'Runtime lock differs from the frozen committed dependency receipt.'
    raw_log = scratch / f'{PREFIX}.log'
    raw_events = scratch / f'{PREFIX}-events.jsonl'
    outputs = [
        evidence / f'{PREFIX}-inputs-before.json',
        evidence / f'{PREFIX}-inputs-after.json',
        evidence / f'{PREFIX}-summary.json',
        evidence / f'{PREFIX}-events.jsonl.gz',
        evidence / f'{PREFIX}.log.gz',
        evidence / f'{PREFIX}-run.py',
        raw_log, raw_events,
    ]
    assert not any(path.exists() for path in outputs), 'Existing integrated receipts must not be overwritten.'
    command = [str(dart), 'test', '--concurrency=1', '--reporter', 'expanded', '--timeout', '2m', '--file-reporter', 'json:' + str(raw_events), *FILES]
    dart_version = subprocess.run([str(dart), '--version'], capture_output=True, text=True, check=True)
    record = {
        'started_utc': utc_now(),
        'git_head': head,
        'git_tree': git(root, 'rev-parse', 'HEAD^{tree}'),
        'expected_published_head': args.expected_head,
        'verified_remote_tracking_ref': args.published_ref,
        'verified_remote_tracking_head': published,
        'published_source_blob_verification': 'All tracked and non-runtime source inputs match the published commit blobs exactly; generated package_config.json and untracked resolved pubspec.lock are independently hashed before/after.',
        'cwd': str(work), 'command': command, 'test_files': FILES,
        'scope': 'Two-file ODS reader/writer qualification for the exact PR base observed at ed5facb4bd503667749ed3d13378da6a1b34738b, merged into the font/text branch. This does not repeat the broader rendering qualification or test statically identified follow-up cases.',
        'dart_version': (dart_version.stdout + dart_version.stderr).strip(),
        'dart_executable_sha256': sha256(dart.read_bytes()),
        'runner_sha256': sha256(Path(__file__).read_bytes()),
        'dependency_provenance': {'runtime_input': 'pubspec.lock', 'committed_receipt': dependency_receipt, 'sha256': sha256(committed_lock), 'byte_identical_at_start': True},
        'source_sha256': before,
        'source_snapshot_sha256': sha256(json.dumps(before, sort_keys=True, separators=(',', ':')).encode()),
        'execution': 'Local Dart tests only; no GitHub Actions polling or waiting.',
    }
    evidence.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(__file__, evidence / f'{PREFIX}-run.py')
    write_json(evidence / f'{PREFIX}-inputs-before.json', record)
    print(f'Starting {len(FILES)} engine suites at {head}; {len(before)} verified input hashes.', flush=True)
    with raw_log.open('x', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=work, stdout=log, stderr=subprocess.STDOUT)
    after, after_blobs = snapshot(root)
    changed = [path for path in sorted(before.keys() | after.keys()) if before.get(path) != after.get(path)]
    finish = {
        'finished_utc': utc_now(), 'exit_code': result.returncode,
        'git_head': git(root, 'rev-parse', 'HEAD'),
        'changed_inputs': changed, 'source_sha256': after,
        'published_source_mismatches_after': published_blob_mismatches(root, args.expected_head, after_blobs),
    }
    write_json(evidence / f'{PREFIX}-inputs-after.json', finish)
    outcomes = parse_events(raw_events) if raw_events.is_file() else {'runner_done': None, 'failures': [], 'hidden_failures': [], 'malformed_event_lines': [], 'observed_suite_files': [], 'unfinished_tests': []}
    missing = sorted(set(FILES) - set(outcomes['observed_suite_files']))
    qualified = (
        result.returncode == 0 and not changed and not finish['published_source_mismatches_after']
        and outcomes['runner_done'] is not None and outcomes['runner_done'].get('success') is True
        and not outcomes['failures'] and not outcomes['hidden_failures']
        and not outcomes['malformed_event_lines'] and not outcomes['unfinished_tests'] and not missing
    )
    archives = [archive(raw_log, evidence / f'{PREFIX}.log.gz')]
    if raw_events.is_file():
        archives.append(archive(raw_events, evidence / f'{PREFIX}-events.jsonl.gz'))
    summary = {
        'git_head_at_start': head, 'git_head_at_finish': finish['git_head'],
        'started_utc': record['started_utc'], 'finished_utc': finish['finished_utc'],
        'command': command, 'cwd': str(work), 'test_file_count': len(FILES), 'test_files': FILES,
        'input_file_count': len(before), 'changed_inputs': changed,
        'exit_code': result.returncode, 'qualified': qualified, 'missing_suite_files': missing,
        **outcomes, 'archives': archives,
    }
    write_json(evidence / f'{PREFIX}-summary.json', summary)
    print(json.dumps({'qualified': qualified, 'counts': outcomes.get('counts'), 'changed_inputs': changed, 'failures': outcomes['failures'], 'hidden_failures': outcomes['hidden_failures']}, indent=2), flush=True)
    return 0 if qualified else result.returncode or 2


if __name__ == '__main__':
    sys.exit(main())
