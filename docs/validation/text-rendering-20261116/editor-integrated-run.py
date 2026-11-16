"""Run the frozen 16-file editor cohort only after the parent gives the start signal."""

from pathlib import Path
import argparse
import collections
import datetime
import gzip
import hashlib
import json
import os
import re
import subprocess
import sys


PIN = '4c1d71adea066bd5ee4d510a8b60b79b64f96a49'
PREFIX = 'editor-integrated'
FILES = [
    'test/office_direction_chord_test.dart',
    'test/office_input_ownership_test.dart',
    'test/office_units_test.dart',
    'test/word_underline_paint_test.dart',
    'test/word_input_focus_test.dart',
    'test/paint_run_text_unicode_test.dart',
    'test/word_run_metrics_test.dart',
    'test/word_shaped_wrap_test.dart',
    'test/sheet_navigation_widget_test.dart',
    'test/word_proofing_navigation_test.dart',
    'test/word_proofing_dialog_test.dart',
    'test/word_hyphenation_caret_test.dart',
    'test/word_zotero_dialog_test.dart',
    'test/host_fonts_test.dart',
    'test/paint_font_fallback_test.dart',
    'test/word_small_caps_test.dart',
]
RUNTIME_INPUTS = {'.dart_tool/package_config.json', 'pubspec.lock'}
DEPENDENCY_RECEIPT = 'docs/validation/text-rendering-20261116/resolved-dependencies.yaml'
GOLDEN_CALL = re.compile(r'\b(matchesGoldenFile|compareWithGolden|screenMatchesGolden)\s*\(')


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def write_json(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def snapshot(root, work):
    paths = []
    for package in (root / 'packages').iterdir():
        if package.is_dir():
            paths.extend((package / 'lib').rglob('*.dart'))
            if (package / 'pubspec.yaml').is_file():
                paths.append(package / 'pubspec.yaml')
    # Include the full editor fixture/helper tree, although only FILES execute.
    paths.extend(path for path in (work / 'test').rglob('*') if path.is_file())
    paths.extend(path for path in (work / 'fonts').rglob('*') if path.is_file())
    paths.extend(root / name for name in ('pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json') if (root / name).is_file())
    paths.append(root / DEPENDENCY_RECEIPT)
    hashes, blobs = {}, {}
    for path in sorted(set(paths)):
        data = path.read_bytes()
        name = path.relative_to(root).as_posix()
        hashes[name] = digest(data)
        blobs[name] = hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()
    return hashes, blobs


def published_mismatches(root, head, blobs):
    expected = {}
    for item in subprocess.check_output(['git', 'ls-tree', '-r', '-z', head], cwd=root).split(b'\0'):
        if not item:
            continue
        metadata, path = item.split(b'\t', 1)
        _mode, kind, oid = metadata.split()
        if kind == b'blob':
            expected[path.decode()] = oid.decode()
    return sorted(name for name, oid in blobs.items() if name not in RUNTIME_INPUTS and expected.get(name) != oid)


def suite_path(path, work):
    candidate = Path(path)
    return candidate.relative_to(work).as_posix() if candidate.is_absolute() else candidate.as_posix()


def parse_events(path, work):
    suites, tests, outcomes = {}, {}, {}
    done_counts = collections.Counter()
    errors, malformed = [], []
    runner_done = None
    lines = path.read_text().splitlines() if path.is_file() else []
    for number, line in enumerate(lines, 1):
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            malformed.append(number)
            continue
        kind = event.get('type')
        if kind == 'suite':
            suite = dict(event['suite'])
            suite['path'] = suite_path(suite['path'], work)
            suites[suite['id']] = suite
        elif kind == 'testStart':
            test = event['test']
            tests[test['id']] = test
        elif kind == 'testDone':
            identity = event['testID']
            outcomes[identity] = event
            done_counts[identity] += 1
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            runner_done = event
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
        'counts': dict(counts),
        'distinct_visible_tests': sum(counts.values()),
        'per_file': {name: dict(value) for name, value in sorted(per_file.items())},
        'observed_suite_files': sorted({suite['path'] for suite in suites.values()}),
        'failures': failures, 'hidden_failures': hidden_failures, 'skips': skips,
        'unfinished_tests': unfinished, 'runner_errors': errors,
        'malformed_event_lines': malformed,
        'duplicate_test_done_ids': sorted(identity for identity, count in done_counts.items() if count > 1),
        'orphan_test_done_ids': sorted(set(outcomes) - set(tests)),
        'runner_done': runner_done,
        'event_log_found': path.is_file(),
        'counting_rule': 'Distinct visible test IDs; hidden setup/load events excluded from counts, hidden failures retained. Skips are not passes.',
    }


def archive(source, target):
    data = source.read_bytes()
    compressed = gzip.compress(data, mtime=0)
    assert gzip.decompress(compressed) == data
    with target.open('xb') as stream:
        stream.write(compressed)
    return {
        'path': target.name,
        'uncompressed_bytes': len(data), 'compressed_bytes': len(compressed),
        'uncompressed_sha256': digest(data), 'archive_sha256': digest(compressed),
        'roundtrip_verified': True,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--expected-head', default=PIN)
    parser.add_argument('--published-ref', default='refs/remotes/origin/codex/text-rendering-20261116')
    parser.add_argument('--concurrency', type=int, default=4)
    parser.add_argument('--prepare-only', action='store_true', help='Verify inputs and print the plan; never start Flutter or write qualification receipts.')
    args = parser.parse_args()
    root = args.repo.resolve()
    work = root / 'packages/quds_office_editor'
    evidence = root / 'docs/validation/text-rendering-20261116'
    scratch = Path(os.environ['TMPDIR'])
    flutter_root = Path(os.environ['FLUTTER_ROOT'])
    flutter = flutter_root / 'bin/flutter'
    assert args.expected_head == PIN, ('Runner is prepared for one frozen source pin.', PIN)
    assert len(FILES) == 16 and len(set(FILES)) == 16
    assert all((work / name).is_file() for name in FILES), 'Every selected test file must exist.'
    assert args.concurrency > 0 and flutter.is_file()
    golden_files = [name for name in FILES if GOLDEN_CALL.search((work / name).read_text())]
    assert not golden_files, ('Review newly detected image goldens; do not silently exclude.', golden_files)
    head = git(root, 'rev-parse', 'HEAD')
    published = git(root, 'rev-parse', args.published_ref)
    assert head == PIN and published == PIN, (head, published, PIN)
    assert git(root, 'rev-parse', '--show-object-format') == 'sha1'
    before, before_blobs = snapshot(root, work)
    unpublished = published_mismatches(root, PIN, before_blobs)
    assert not unpublished, ('Inputs differ from the published source.', unpublished)
    assert before['pubspec.lock'] == before[DEPENDENCY_RECEIPT], 'Generated lock must match the published dependency receipt byte-for-byte.'
    raw_log = scratch / f'{PREFIX}.log'
    raw_events = scratch / f'{PREFIX}-events.jsonl'
    outputs = [evidence / f'{PREFIX}{suffix}' for suffix in (
        '-inputs-before.json', '-inputs-after.json', '-summary.json',
        '-events.jsonl.gz', '.log.gz', '-run.py',
    )] + [raw_log, raw_events]
    assert not any(path.exists() for path in outputs), 'Existing qualification receipts must not be overwritten.'
    command = [str(flutter), 'test', '--no-pub', f'--concurrency={args.concurrency}', '--reporter', 'expanded', '--file-reporter', 'json:' + str(raw_events), *FILES]
    plan = {
        'git_head': head, 'git_tree': git(root, 'rev-parse', 'HEAD^{tree}'),
        'verified_published_head': published, 'verified_remote_tracking_ref': args.published_ref,
        'cwd': str(work), 'command': command, 'test_file_count': len(FILES), 'test_files': FILES,
        'input_file_count': len(before),
        'source_snapshot_sha256': digest(json.dumps(before, sort_keys=True, separators=(',', ':')).encode()),
        'selected_test_sha256': {name: digest((work / name).read_bytes()) for name in FILES},
        'generated_runtime_inputs': sorted(RUNTIME_INPUTS),
        'dependency_lock_provenance': {
            'published_receipt': DEPENDENCY_RECEIPT,
            'sha256': before['pubspec.lock'],
            'byte_for_byte_match': True,
        },
        'excluded_test_name_pattern': None, 'excluded_image_golden_tests': 0,
        'detected_image_golden_files': golden_files,
        'runner_sha256': digest(Path(__file__).read_bytes()),
        'receipt_files': [str(path) for path in outputs if path.parent == evidence],
        'execution': 'Local Flutter tests only; no GitHub Actions polling or waiting.',
        'render_output_note': 'The incoming underline test writes fresh before/after PNG diagnostics under build/underline-preview; these are not image-golden comparisons.',
    }
    if args.prepare_only:
        print(json.dumps({'prepared_only': True, 'tests_started': False, **plan}, indent=2), flush=True)
        return 0
    runtime_paths = [
        flutter, flutter_root / 'bin/cache/dart-sdk/bin/dart',
        flutter_root / 'bin/cache/flutter_tools.snapshot',
        flutter_root / 'bin/cache/artifacts/engine/linux-x64/flutter_tester',
    ]
    runtime_version = json.loads(subprocess.check_output([str(flutter), '--version', '--machine'], cwd=work, text=True))
    record = {
        'started_utc': utc_now(), **plan,
        'runtime': runtime_version,
        'runtime_sha256': {str(path): digest(path.read_bytes()) for path in runtime_paths if path.is_file()},
        'source_sha256': before,
        'published_source_blob_verification': 'All hashed repository source inputs match pinned commit blobs. Generated package_config.json is recorded separately; generated pubspec.lock matches the pinned resolved-dependencies.yaml receipt byte-for-byte.',
    }
    evidence.mkdir(parents=True, exist_ok=True)
    with (evidence / f'{PREFIX}-run.py').open('xb') as stream:
        stream.write(Path(__file__).read_bytes())
    write_json(evidence / f'{PREFIX}-inputs-before.json', record)
    print(f'Starting {len(FILES)} editor suites at {PIN}; {len(before)} verified input hashes.', flush=True)
    with raw_log.open('x', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=work, stdout=log, stderr=subprocess.STDOUT)
    after, after_blobs = snapshot(root, work)
    changed = [name for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)]
    finish = {
        'finished_utc': utc_now(), 'exit_code': result.returncode,
        'git_head': git(root, 'rev-parse', 'HEAD'), 'source_sha256': after,
        'changed_inputs': changed,
        'published_source_mismatches_after': published_mismatches(root, PIN, after_blobs),
        'dependency_lock_matches_published_receipt': after['pubspec.lock'] == after[DEPENDENCY_RECEIPT],
    }
    write_json(evidence / f'{PREFIX}-inputs-after.json', finish)
    outcomes = parse_events(raw_events, work)
    missing = sorted(set(FILES) - set(outcomes['observed_suite_files']))
    qualified = (
        result.returncode == 0 and not changed and finish['git_head'] == PIN
        and not finish['published_source_mismatches_after']
        and finish['dependency_lock_matches_published_receipt']
        and outcomes['runner_done'] is not None and outcomes['runner_done'].get('success') is True
        and not outcomes['failures'] and not outcomes['hidden_failures'] and not outcomes['runner_errors']
        and not outcomes['malformed_event_lines'] and not outcomes['unfinished_tests']
        and not outcomes['duplicate_test_done_ids'] and not outcomes['orphan_test_done_ids'] and not missing
    )
    archives = [archive(raw_log, evidence / f'{PREFIX}.log.gz')]
    if raw_events.is_file():
        archives.append(archive(raw_events, evidence / f'{PREFIX}-events.jsonl.gz'))
    summary = {
        'git_head_at_start': PIN, 'git_head_at_finish': finish['git_head'],
        'started_utc': record['started_utc'], 'finished_utc': finish['finished_utc'],
        'command': command, 'cwd': str(work), 'test_file_count': len(FILES), 'test_files': FILES,
        'input_file_count': len(before), 'changed_inputs': changed,
        'published_source_mismatches_after': finish['published_source_mismatches_after'],
        'exit_code': result.returncode, 'qualified': qualified, 'missing_suite_files': missing,
        'excluded_test_name_pattern': None, 'excluded_image_golden_tests': 0,
        **outcomes, 'archives': archives,
    }
    write_json(evidence / f'{PREFIX}-summary.json', summary)
    print(json.dumps({'qualified': qualified, 'counts': outcomes['counts'], 'changed_inputs': changed, 'failures': outcomes['failures'], 'hidden_failures': outcomes['hidden_failures']}, indent=2), flush=True)
    return 0 if qualified else result.returncode or 2


if __name__ == '__main__':
    sys.exit(main())
