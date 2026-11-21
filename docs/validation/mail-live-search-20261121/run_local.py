#!/usr/bin/env python3
"""Run the finite, serialized Mail live-search qualification without CI.

Resolve the original workspace lockfile first, then put its pinned Flutter and
Dart SDKs on PATH. Use a new output directory for each attempt; earlier evidence
is never overwritten. Example, from the repository root:

  python docs/validation/mail-live-search-20261121/run_local.py \
    --output /absolute/path/to/evidence

The source inventories cover every present Git-tracked or nonignored untracked
file under packages/ and third_party/, plus the root manifests/configuration.
They include the selected visual gate even before that file is committed.
Generated, ignored build/cache outputs are intentionally outside this inventory.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time


STUDIO = [
    'studio_mail_cached_search_test.dart',
    'studio_mail_cached_search_refresh_test.dart',
    'studio_mail_cached_search_dialog_test.dart',
    'studio_mail_cached_search_refresh_dialog_test.dart',
    'studio_mail_saved_search_dialog_test.dart',
    'studio_mail_saved_search_store_test.dart',
    'studio_mail_local_accounts_dialog_test.dart',
]
STORE = ['cached_header_search_test.dart', 'saved_header_searches_test.dart']
EDITOR = [
    'word_page_text_cache_test.dart',
    'word_page_text_picture_cache_test.dart',
    # The incoming paragraph/frame ownership caches also feed frame text.
    'office_frame_wrap_golden_test.dart',
]
CHANGED_DART = [
    'packages/quds_office_editor/example/lib/studio_mail_cached_search.dart',
    'packages/quds_office_editor/example/lib/studio_mail_cached_search_dialog.dart',
    'packages/quds_office_editor/example/lib/studio_mail_cached_search_refresh.dart',
    'packages/quds_office_editor/example/lib/studio_mail_cached_search_strings.dart',
    'packages/quds_office_editor/example/test/studio_mail_cached_search_dialog_test.dart',
    'packages/quds_office_editor/example/test/studio_mail_cached_search_refresh_test.dart',
    'packages/quds_office_editor/example/test/studio_mail_cached_search_refresh_dialog_test.dart',
    'packages/quds_office_editor/example/tool/mail_live_search_visual_test.dart',
]
ROOT_INPUTS = ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.fvmrc']


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        before = os.fstat(stream.fileno())
        value = hashlib.file_digest(stream, 'sha256').hexdigest()
        after = os.fstat(stream.fileno())
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise RuntimeError(f'Input changed while hashing: {path}')
    return value


def save_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def source_manifest(repo: Path) -> dict[str, str]:
    names = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z',
         '--', 'packages', 'third_party', *ROOT_INPUTS], cwd=repo,
    ).decode().split('\0')
    names = sorted(set(names) | set(CHANGED_DART))
    manifest = {}
    for name in names:
        if not name:
            continue
        path = repo / name
        if path.is_symlink():
            manifest[name] = 'symlink:' + os.readlink(path)
        elif path.is_file():
            manifest[name] = digest(path)
    return manifest


def changed_inputs(before: dict[str, str], after: dict[str, str]) -> list[str]:
    return sorted(path for path in before.keys() | after.keys()
                  if before.get(path) != after.get(path))


def audit_events(path: Path, expected_suites: list[Path]) -> dict[str, object]:
    starts = {}
    finishes = {}
    suites = {}
    runner_starts = []
    done_events = []
    errors = []
    malformed = []
    lifecycle_errors = []
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            malformed.append({'line': line_number, 'text': line})
            continue
        if not isinstance(event, dict):
            malformed.append({'line': line_number, 'text': line})
            continue
        kind = event.get('type')
        if kind == 'start':
            runner_starts.append(event)
        elif kind == 'suite':
            suites[event['suite']['id']] = event['suite']
        elif kind == 'testStart':
            identity = event['test']['id']
            if identity in starts:
                lifecycle_errors.append(f'Duplicate testStart: {identity}')
            starts[identity] = event
        elif kind == 'testDone':
            identity = event['testID']
            if identity in finishes:
                lifecycle_errors.append(f'Duplicate testDone: {identity}')
            if identity not in starts:
                lifecycle_errors.append(f'testDone without start: {identity}')
            finishes[identity] = event
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            done_events.append(event)
    for identity in starts.keys() - finishes.keys():
        lifecycle_errors.append(f'Unfinished test: {identity}')
    cases = []
    for identity, finish in finishes.items():
        if finish.get('hidden', False):
            continue
        start = starts.get(identity)
        if start is None:
            continue
        test = start['test']
        suite = suites.get(test['suiteID'], {})
        if not suite.get('path'):
            lifecycle_errors.append(f'Visible test has no suite path: {identity}')
        cases.append({
            'id': identity,
            'suite': suite.get('path'),
            'name': test['name'],
            'result': finish.get('result'),
            'skipped': bool(finish.get('skipped', False)),
            'start_time_ms': start.get('time'),
            'end_time_ms': finish.get('time'),
        })
    observed = sorted({str(Path(s['path']).resolve()) for s in suites.values()
                       if s.get('path')})
    expected = sorted(str(path.resolve()) for path in expected_suites)
    failed = [case for case in cases if case['result'] != 'success'
              and not case['skipped']]
    skipped = [case for case in cases if case['skipped']]
    complete = (len(runner_starts) == 1 and len(done_events) == 1
                and done_events[0].get('success') is True
                and observed == expected and bool(cases)
                and not lifecycle_errors and not malformed)
    return {
        'completed_visible_cases': len(cases),
        'passed': len(cases) - len(failed) - len(skipped),
        'failed': len(failed), 'skipped': len(skipped),
        'runtime_error_events': errors,
        'runner_start_events': runner_starts,
        'done_events': done_events,
        'expected_suites': expected, 'observed_suites': observed,
        'complete_lifecycle': complete,
        'lifecycle_errors': lifecycle_errors, 'non_json_lines': malformed,
        'cases': cases,
    }


def execute(command: list[str], cwd: Path, env: dict[str, str],
            stdout: Path, stderr: Path, timeout: int) -> dict[str, object]:
    started = utc_now()
    clock = time.monotonic()
    timed_out = False
    with stdout.open('wb') as out, stderr.open('wb') as err:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=out,
                                   stderr=err, start_new_session=True)
        try:
            exit_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                exit_code = process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                exit_code = process.wait(timeout=10)
    return {
        'command': command, 'cwd': str(cwd), 'started_utc': started,
        'finished_utc': utc_now(), 'duration_seconds': time.monotonic() - clock,
        'exit_code': exit_code, 'timed_out': timed_out,
        'stdout_file': stdout.name, 'stderr_file': stderr.name,
        'stdout_bytes': stdout.stat().st_size, 'stderr_bytes': stderr.stat().st_size,
        'stdout_sha256': digest(stdout), 'stderr_sha256': digest(stderr),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--only', nargs='+', choices=['checks', 'studio', 'store', 'editor'],
                        default=['checks', 'studio', 'store', 'editor'])
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('--dart', default='dart')
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = args.output.resolve()
    for name in CHANGED_DART:
        if not (repo / name).is_file():
            parser.error(f'Required changed/visual source is unavailable: {name}')
    flutter = shutil.which(args.flutter)
    dart = shutil.which(args.dart)
    if flutter is None or dart is None:
        parser.error('Put the pinned Flutter and Dart executables on PATH first.')
    if output.exists():
        parser.error('Use a new evidence directory; existing attempts are preserved.')
    output.mkdir(parents=True)
    env = dict(os.environ)
    env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true')
    flutter_base = [flutter, '--suppress-analytics', '--no-version-check']
    original = source_manifest(repo)
    save_json(output / 'source-before.json', original)
    context = {
        'schema': 'quds-mail-live-search-local-qualification/v1',
        'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo).decode().strip(),
        'selected_cohorts': args.only,
        'environment': {name: env.get(name) for name in [
            'CI', 'FLUTTER_SUPPRESS_ANALYTICS', 'DART_SUPPRESS_ANALYTICS',
            'PUB_CACHE', 'TMPDIR',
        ]},
        'runner_sha256': digest(Path(__file__).resolve()),
        'source_inventory_scope': (
            'All present tracked/nonignored untracked packages and third_party '
            'files, root manifests/configuration, and the selected visual source; '
            'generated ignored build/cache files are excluded.'),
        'source_input_count': len(original),
    }
    save_json(output / 'context.json', context)
    versions = []
    for label, command in [
        ('flutter-version', [*flutter_base, '--version', '--machine']),
        ('dart-version', [dart, '--version']),
    ]:
        versions.append(execute(command, repo, env, output / (label + '.stdout'),
                                output / (label + '.stderr'), args.timeout))
    save_json(output / 'runtime-versions.json', versions)
    steps = []
    if 'checks' in args.only:
        steps.extend([
            ('analysis', repo, [*flutter_base, 'analyze', '--no-pub',
                               '--fatal-infos', '--fatal-warnings', *CHANGED_DART], []),
            ('format', repo, [dart, 'format', '--output=none',
                             '--set-exit-if-changed', *CHANGED_DART], []),
        ])
    for name, package, files in [
        ('studio', 'packages/quds_office_editor/example', STUDIO),
        ('store', 'packages/quds_mail_store', STORE),
        ('editor', 'packages/quds_office_editor', EDITOR),
    ]:
        if name not in args.only:
            continue
        cwd = repo / package
        selected = [cwd / 'test' / name for name in files]
        for path in selected:
            if not path.is_file():
                raise FileNotFoundError(path)
        command = [*flutter_base, 'test', '--no-pub', '--concurrency=1',
                   '--reporter=json', *['test/' + name for name in files]]
        steps.append((name, cwd, command, selected))
    receipts = []
    for name, cwd, command, selected in steps:
        print(f'Starting {name}: ' + json.dumps(command), flush=True)
        before = source_manifest(repo)
        save_json(output / (name + '.source-before.json'), before)
        receipt = execute(command, cwd, env, output / (name + '.stdout'),
                          output / (name + '.stderr'), args.timeout)
        after = source_manifest(repo)
        save_json(output / (name + '.source-after.json'), after)
        receipt.update(name=name, source_input_count=len(before),
                       changed_inputs=changed_inputs(before, after))
        accepted = (receipt['exit_code'] == 0 and not receipt['timed_out']
                    and receipt['stderr_bytes'] == 0 and before == after)
        if selected:
            audit = audit_events(output / (name + '.stdout'), selected)
            save_json(output / (name + '.cases.json'), audit)
            receipt['test_summary'] = {key: value for key, value in audit.items()
                                       if key != 'cases'}
            accepted = (accepted and audit['complete_lifecycle']
                        and audit['failed'] == 0 and audit['skipped'] == 0
                        and not audit['runtime_error_events'])
        receipt['accepted'] = accepted
        save_json(output / (name + '.receipt.json'), receipt)
        receipts.append(receipt)
        print(json.dumps({'name': name, 'exit_code': receipt['exit_code'],
                          'accepted': accepted, 'stderr_bytes': receipt['stderr_bytes'],
                          'changed_inputs': receipt['changed_inputs'],
                          'passed': receipt.get('test_summary', {}).get('passed')}), flush=True)
    final = source_manifest(repo)
    save_json(output / 'source-after.json', final)
    summary = {
        'schema': context['schema'], 'git_head': context['git_head'],
        'finished_utc': utc_now(), 'source_input_count': len(original),
        'changed_inputs_across_gate': changed_inputs(original, final),
        'accepted': (all(receipt['accepted'] for receipt in receipts)
                     and all(version['exit_code'] == 0 for version in versions)
                     and original == final),
        'steps': receipts,
    }
    save_json(output / 'summary.json', summary)
    print(json.dumps({'accepted': summary['accepted'],
                      'output': str(output), 'steps': len(receipts)}), flush=True)
    return 0 if summary['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
