#!/usr/bin/env python3
"""Run the complete resumed spelling cohorts, preserving source-bound raw events.

Requires the pinned Flutter SDK and an offline-resolved, unchanged workspace.
This runner never accesses GitHub or a CI service.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse


EDITOR_TESTS = [
    'platform_spelling_provider_test.dart',
    'platform_spelling_projection_test.dart',
    'platform_spelling_projection_review_test.dart',
    'platform_spelling_dialog_test.dart',
    'platform_spelling_identifiers_test.dart',
    'platform_spelling_identifier_review_test.dart',
    'platform_spelling_vocabulary_unicode_test.dart',
    'word_manual_proofing_test.dart',
    'word_proofing_context_test.dart',
    'word_proofing_correction_test.dart',
    'word_proofing_dialog_test.dart',
    'word_proofing_geometry_test.dart',
    'word_proofing_navigation_test.dart',
    'word_proofing_session_test.dart',
]

INCOMING_ZOTERO_TESTS = [
    'word_zotero_stored_details_test.dart',
    'word_zotero_stored_details_dialog_test.dart',
]

# These unchanged frozen grammar fixtures register the same input/expected
# row twice. Preserve their executions and disclose the eight repetitions.
LEGACY_DUPLICATE_NAMES = {
    'german_context_test.dart': {
        'context: Sie antwortet dem Lehrer.',
        'context: Wenn ich Zeit habe, lese ich ein Buch.',
        'context: Sie ist nach Hause gegangen.',
    },
    'german_release_context_test.dart': {
        'context: Wir helfen der Freundin.',
        'context: Wir helfen den Freundinnen.',
        'context: Wir stehen bei diesem Gebäude.',
        'context: Wir sprechen mit dem Straßenpolizisten.',
        'context: Wir sehen den Straßenpolizisten.',
    },
}


def now():
    return datetime.now(timezone.utc).isoformat()


def record(path):
    size = path.stat().st_size
    sha256 = hashlib.sha256()
    blob = hashlib.sha1(b'blob ' + str(size).encode() + b'\0')
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            sha256.update(block)
            blob.update(block)
    return {'bytes': size, 'sha256': sha256.hexdigest(), 'git_blob_sha1': blob.hexdigest()}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def tree_blobs(repo, commit):
    result = {}
    raw = subprocess.check_output(['git', 'ls-tree', '-rz', commit], cwd=repo)
    for entry in raw.split(b'\0'):
        if entry:
            metadata, path = entry.split(b'\t', 1)
            result[path.decode()] = metadata.split()[2].decode()
    return result


def parse_events(path, cwd, selected):
    events, parse_errors, envelopes = [], [], []
    raw_text = gzip.decompress(path.read_bytes()).decode() if path.suffix == '.gz' else path.read_text()
    for number, line in enumerate(raw_text.splitlines(), 1):
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            parse_errors.append({'line': number, 'text': line})
            continue
        if isinstance(event, list) and all(isinstance(item, dict) and 'event' in item for item in event):
            envelopes.append(event)
        elif isinstance(event, dict) and 'type' in event:
            events.append(event)
        else:
            parse_errors.append({'line': number, 'unexpected_json': event})
    starts = {event['test']['id']: event['test'] for event in events if event['type'] == 'testStart'}
    suites = {event['suite']['id']: event['suite'] for event in events if event['type'] == 'suite'}
    finishes = [event for event in events if event['type'] == 'testDone']
    completions = [event for event in events if event['type'] == 'done']
    errors = [event for event in events if event['type'] == 'error']
    diagnostics = [event for event in events if event['type'] == 'print' and any(
        token in event.get('message', '') for token in ('overflowed', 'would not hit test', 'EXCEPTION CAUGHT')
    )]
    cases, excluded = [], []
    for finish in finishes:
        test = starts.get(finish['testID'], {})
        suite_path = suites.get(test.get('suiteID'), {}).get('path')
        case = {
            'id': finish['testID'], 'name': test.get('name'), 'suite': suite_path,
            'result': finish['result'], 'skipped': finish.get('skipped', False),
        }
        target = excluded if finish.get('hidden') or test.get('name', '').endswith(('(setUpAll)', '(tearDownAll)')) else cases
        target.append(case)
    suite_paths = {str((cwd / suite['path']).resolve()) for suite in suites.values()}
    identities = Counter((case['suite'], case['name']) for case in cases)
    duplicates = [{'suite': suite, 'name': name, 'registrations': count}
                  for (suite, name), count in sorted(identities.items()) if count > 1]
    guards = {
        'all_selected_suites_executed': suite_paths == {str(path.resolve()) for path in selected},
        'every_started_event_finished_once': set(starts) == {finish['testID'] for finish in finishes} and len(starts) == len(finishes),
        'one_successful_completion': len(completions) == 1 and completions[0].get('success') is True,
        'duplicate_names_are_documented_legacy_rows': all(
            item['registrations'] == 2 and item['name'] in LEGACY_DUPLICATE_NAMES.get(Path(item['suite']).name, set())
            for item in duplicates
        ),
        'all_cases_successful_without_skips': bool(cases) and all(case['result'] == 'success' and not case['skipped'] for case in cases),
        'no_error_or_diagnostic_events': not errors and not diagnostics,
        'raw_stream_parses': not parse_errors,
    }
    return {
        'cases': cases, 'excluded_events': excluded, 'machine_envelopes': envelopes,
        'suite_count': len(suites), 'substantive_test_count': len(cases),
        'distinct_named_test_count': len(identities),
        'duplicate_registration_count': len(cases) - len(identities),
        'duplicate_name_groups': duplicates,
        'results': dict(Counter(case['result'] for case in cases)),
        'skipped': sum(bool(case['skipped']) for case in cases),
        'errors': errors, 'diagnostics': diagnostics, 'parse_errors': parse_errors,
        'completion_events': completions, 'guards': guards,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cohort', choices=('engine', 'editor', 'incoming-zotero'), required=True)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source-commit', default='HEAD')
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, workspace, runtime, out = [path.resolve() for path in (args.repo, args.workspace, args.runtime, args.output)]
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        raise RuntimeError('Use a new empty output directory for every attempt.')
    sdk = runtime / 'flutter-sdk'
    dart = sdk / 'bin/cache/dart-sdk/bin/dart'
    config = workspace / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text())['packages']
    roots = {package['name']: Path(unquote(urlparse(urljoin(config.as_uri(), package['rootUri'])).path)) for package in packages}
    env = dict(os.environ, FLUTTER_ROOT=str(sdk), PUB_CACHE=str(runtime / 'pub-cache'),
               TMPDIR=str(runtime / 'tmp'), XDG_CONFIG_HOME=str(runtime / 'config'), CI='true',
               DART_SUPPRESS_ANALYTICS='true', DASH__SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true')
    if args.cohort == 'engine':
        cwd = workspace / 'packages/quds_office_engine'
        selected = sorted('packages/quds_office_engine/test/proofing/' + path.name
                          for path in (repo / 'packages/quds_office_engine/test/proofing').glob('*_test.dart'))
        command = [str(dart), '--packages=' + str(config), str(roots['test'] / 'bin/test.dart'),
                   '--reporter', 'json', '--concurrency', '2'] + [str(workspace / path) for path in selected]
    else:
        cwd = workspace / 'packages/quds_office_editor'
        names = EDITOR_TESTS if args.cohort == 'editor' else INCOMING_ZOTERO_TESTS
        selected = ['packages/quds_office_editor/test/' + name for name in names]
        command = [str(sdk / 'bin/flutter'), 'test', '--no-pub', '--reporter', 'json', '--concurrency', '2']
        command += [str(workspace / path) for path in selected]

    members = re.findall(r'^  - (\S+)\s*$', (repo / 'pubspec.yaml').read_text().split('\nworkspace:\n', 1)[1], re.M)
    relative_inputs = set(selected) | {'pubspec.yaml', 'analysis_options.yaml'}
    for member in members:
        relative_inputs.add(member + '/pubspec.yaml')
        for name in ('analysis_options.yaml', 'dart_test.yaml'):
            if (repo / member / name).is_file():
                relative_inputs.add(member + '/' + name)
        for folder in ('lib', 'assets', 'fonts'):
            relative_inputs.update(str(path.relative_to(repo)) for path in (repo / member / folder).rglob('*') if path.is_file())
    relative_inputs = sorted(relative_inputs)

    def source_snapshot():
        return {path: record(workspace / path) for path in relative_inputs}

    dependency_paths = set()
    for root in roots.values():
        if root.resolve().is_relative_to(repo) or root.resolve().is_relative_to(workspace):
            continue
        for name in ('pubspec.yaml', 'analysis_options.yaml'):
            if (root / name).is_file():
                dependency_paths.add(root / name)
        for name in ('lib', 'bin', 'assets'):
            dependency_paths.update(path for path in (root / name).rglob('*') if path.is_file())
    runtime_paths = {config, workspace / 'pubspec.lock', workspace / '.dart_tool/package_graph.json'}
    runtime_paths.update(path for path in (sdk / 'bin/cache/dart-sdk').rglob('*') if path.is_file())
    for name in ('bin/cache/flutter_tools.snapshot', 'bin/cache/flutter.version.json',
                 'bin/cache/artifacts/engine/linux-x64/flutter_tester',
                 'bin/cache/artifacts/engine/linux-x64/icudtl.dat'):
        if (sdk / name).is_file():
            runtime_paths.add(sdk / name)
    runtime_paths.update(path for path in (sdk / 'bin/cache/artifacts/engine/common').rglob('*') if path.is_file())

    def environment_snapshot():
        return {str(path): record(path) for path in sorted(dependency_paths | runtime_paths)}

    lock = None
    if args.cohort != 'engine':
        lock = (runtime / 'flutter-cli.lock').open('a')
        print('Acquiring shared local Flutter CLI lock.', flush=True)
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    head = subprocess.check_output(['git', 'rev-parse', args.source_commit], cwd=repo, text=True).strip()
    before, environment_before = source_snapshot(), environment_snapshot()
    write_json(out / 'source-before.json', before)
    write_json(out / 'environment-before.json', environment_before)
    run = {
        'schema': 'quds.spelling_resume.regression.v1', 'cohort': args.cohort,
        'started_at_utc': now(), 'source_commit': head, 'source_tree': subprocess.check_output(['git', 'rev-parse', head + '^{tree}'], cwd=repo, text=True).strip(),
        'command': command, 'cwd': str(cwd), 'selected_files': selected,
        'source_input_count': len(before), 'environment_input_count': len(environment_before),
        'runner': record(Path(__file__)), 'package_count': len(packages),
        'scope': ('Local genuine Flutter checks for the two incoming Zotero stored-details suites; controlled catalog and clipboard responses.'
                  if args.cohort == 'incoming-zotero' else
                  'Local genuine Dart/Flutter regression tests; native spelling uses controlled channel responses.'),
    }
    write_json(out / 'run.json', run)
    started = time.monotonic()
    timed_out = False
    with (out / 'events.jsonl').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            exit_code = process.wait(timeout=600)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                exit_code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                exit_code = process.wait()
    elapsed = time.monotonic() - started
    after, environment_after = source_snapshot(), environment_snapshot()
    write_json(out / 'source-after.json', after)
    write_json(out / 'environment-after.json', environment_after)
    blobs = tree_blobs(repo, head)
    guards = {
        'source_unchanged': before == after,
        'environment_unchanged': environment_before == environment_after,
        'all_inputs_match_saved_source': all(blobs.get(path) == value['git_blob_sha1'] for path, value in before.items()),
        'actual_process_exited_zero': exit_code == 0,
        'not_timed_out': not timed_out,
    }
    detail = parse_events(out / 'events.jsonl', cwd, [workspace / path for path in selected])
    guards.update(detail.pop('guards'))
    for key in ('cases', 'excluded_events', 'machine_envelopes'):
        write_json(out / (key.replace('_', '-') + '.json'), detail.pop(key))
    summary = {**run, **detail, 'status': 'passed' if all(guards.values()) else 'failed',
               'finished_at_utc': now(), 'elapsed_seconds': elapsed,
               'actual_process_exit_code': exit_code, 'timed_out': timed_out, 'guards': guards}
    write_json(out / 'summary.json', summary)
    for path in sorted(out.iterdir()):
        if path.name in ('events.jsonl', 'environment-before.json', 'environment-after.json', 'source-before.json', 'source-after.json', 'cases.json'):
            with path.open('rb') as source, gzip.GzipFile(filename=str(path) + '.gz', mode='wb', mtime=0) as destination:
                for block in iter(lambda: source.read(1024 * 1024), b''):
                    destination.write(block)
            path.unlink()
    print(json.dumps({key: summary[key] for key in ('cohort', 'status', 'suite_count', 'substantive_test_count', 'results', 'skipped', 'actual_process_exit_code', 'guards')}, indent=2), flush=True)
    if lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()
    raise SystemExit(0 if summary['status'] == 'passed' else 1)


if __name__ == '__main__':
    main()
