#!/usr/bin/env python3
"""Locally qualify the spelling dependency integrated at the fixed ref cutoff."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse


ENGINE_TESTS = [
    'german_spelling_test.dart',
    'german_spelling_quotes_test.dart',
    'german_spelling_apostrophes_test.dart',
    'german_spelling_compounds_test.dart',
    'german_spelling_shortlist_test.dart',
    'german_spelling_continuation_test.dart',
    'german_spelling_projection_test.dart',
    'german_suggestion_quality_test.dart',
    'german_lexicon_query_test.dart',
    'german_literal_ranges_test.dart',
    'german_participle_suggestions_test.dart',
    'german_nominal_word_forms_test.dart',
    'office_proofing_test.dart',
    'proofing_text_ranges_test.dart',
    'german_morphology_loading_test.dart',
    'german_morphology_grammar_test.dart',
    'german_grammar_test.dart',
    'german_agreement_facts_test.dart',
    'german_writing_rules_test.dart',
]
EDITOR_TESTS = [
    'platform_spelling_provider_test.dart',
    'platform_spelling_projection_test.dart',
    'platform_spelling_projection_review_test.dart',
    'platform_spelling_dialog_test.dart',
    'platform_spelling_identifiers_test.dart',
    'platform_spelling_identifier_review_test.dart',
    'platform_spelling_vocabulary_unicode_test.dart',
]
CHECK_TARGETS = [
    'packages/quds_office_engine/lib/src/proofing/german_spelling.dart',
    'packages/quds_office_engine/test/proofing/german_spelling_projection_test.dart',
    'packages/quds_office_engine/tool/check_native_spelling.dart',
    'packages/quds_office_editor/lib/src/proofing/platform_spelling_provider.dart',
    'packages/quds_office_editor/test/platform_spelling_identifiers_test.dart',
    'packages/quds_office_editor/test/platform_spelling_identifier_review_test.dart',
    'packages/quds_office_editor/test/platform_spelling_vocabulary_unicode_test.dart',
]


def now():
    return datetime.now(timezone.utc).isoformat()


def record(path):
    value = path.read_bytes()
    return {
        'bytes': len(value),
        'sha256': hashlib.sha256(value).hexdigest(),
        'git_blob_sha1': hashlib.sha1(
            b'blob ' + str(len(value)).encode() + b'\0' + value
        ).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cohort', choices=['engine', 'editor', 'panel', 'checks'], required=True)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--toolchain', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, workspace, toolchain, out = [
        path.resolve() for path in (args.repo, args.workspace, args.toolchain, args.output)
    ]
    out.mkdir(parents=True, exist_ok=True)
    if (out / 'run.json').exists():
        raise RuntimeError('Use a fresh output directory for each run.')

    def write(name, value):
        (out / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

    config = workspace / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text())['packages']
    test_entry = next(package for package in packages if package['name'] == 'test')
    test_root = Path(unquote(urlparse(urljoin(config.as_uri(), test_entry['rootUri'])).path))
    sdk = toolchain / 'flutter-sdk'
    dart = sdk / 'bin/cache/dart-sdk/bin/dart'
    env = dict(
        os.environ,
        FLUTTER_ROOT=str(sdk),
        PUB_CACHE=str(toolchain / 'pub-cache'),
        TMPDIR=str(toolchain / 'tmp'),
        XDG_CONFIG_HOME=str(toolchain / 'config'),
        CI='true',
        DART_SUPPRESS_ANALYTICS='true',
        DASH__SUPPRESS_ANALYTICS='true',
        FLUTTER_SUPPRESS_ANALYTICS='true',
    )
    if args.cohort == 'engine':
        selected = ['packages/quds_office_engine/test/proofing/' + name for name in ENGINE_TESTS]
        cwd = workspace / 'packages/quds_office_engine'
        command = [str(dart), '--packages=' + str(config), str(test_root / 'bin/test.dart'),
                   '--reporter', 'json', '--concurrency', '2']
        command += ['test/proofing/' + name for name in ENGINE_TESTS]
    elif args.cohort == 'editor':
        selected = ['packages/quds_office_editor/test/' + name for name in EDITOR_TESTS]
        cwd = workspace / 'packages/quds_office_editor'
        command = [str(sdk / 'bin/flutter'), 'test', '--no-pub', '--reporter', 'json',
                   '--concurrency', '2'] + ['test/' + name for name in EDITOR_TESTS]
    elif args.cohort == 'panel':
        selected = ['packages/quds_office_engine/tool/check_native_spelling.dart']
        cwd = workspace / 'packages/quds_office_engine'
        command = [str(dart), '--packages=' + str(config), 'tool/check_native_spelling.dart']
    else:
        selected = CHECK_TARGETS
        cwd = workspace
        command = [str(dart), 'analyze', '--fatal-infos'] + selected

    source_paths = {repo / path for path in selected}
    folders = ['packages/quds_office_engine/lib', 'packages/legacy_doc_parser/lib']
    if args.cohort in ('editor', 'checks'):
        folders.append('packages/quds_office_editor/lib')
    for folder in folders:
        source_paths.update(path for path in (repo / folder).rglob('*') if path.is_file())
    source_paths = sorted(source_paths)

    def sources():
        return {str(path.relative_to(repo)): record(path) for path in source_paths}

    def head():
        return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()

    def match_head(commit, snapshot):
        tree = subprocess.check_output(['git', 'ls-tree', '-rz', commit], cwd=repo)
        blobs = {}
        for entry in tree.split(b'\0'):
            if entry:
                metadata, path = entry.split(b'\t', 1)
                blobs[path.decode()] = metadata.split()[2].decode()
        return all(blobs.get(path) == value['git_blob_sha1'] for path, value in snapshot.items())

    lock = None
    if args.cohort == 'editor':
        lock = (toolchain / 'flutter-cli.lock').open('a')
        print('Waiting for shared Flutter CLI lock.', flush=True)
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        print('Acquired shared Flutter CLI lock.', flush=True)

    start_head = head()
    before = sources()
    write('source-before.json', before)
    runtime_paths = [config, workspace / 'pubspec.lock', workspace / '.dart_tool/package_graph.json',
                     dart, test_root / 'pubspec.yaml', sdk / 'bin/cache/dart-sdk/version']
    if args.cohort == 'editor':
        runtime_paths.append(sdk / 'bin/cache/artifacts/engine/linux-x64/flutter_tester')
    bound_before = {str(path): record(path) for path in runtime_paths}
    write('runtime-binding-before.json', bound_before)
    run = {
        'cohort': args.cohort,
        'started_at_utc': now(),
        'command': command,
        'cwd': str(cwd),
        'head_at_start': start_head,
        'selected_files': selected,
        'source_file_count': len(before),
        'runner_sha256': record(Path(__file__))['sha256'],
        'dart_version': subprocess.check_output([str(dart), '--version'], env=env, text=True).strip(),
        'flutter_lock_path': str(toolchain / 'flutter-cli.lock') if lock else None,
        'scope': 'Current merged incoming spelling dependency. Controlled providers and local Dart VM; no installed-OS spelling, desktop-device, AOT or JavaScript acceptance.',
    }
    write('run.json', run)
    started = time.monotonic()
    timed_out = False
    output_name = 'events.jsonl' if args.cohort in ('engine', 'editor') else 'stdout.log'
    with (out / output_name).open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout, stderr=stderr,
                                   start_new_session=True)
        try:
            exit_code = process.wait(timeout=300)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                exit_code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                exit_code = process.wait()
    elapsed = time.monotonic() - started
    after = sources()
    end_head = head()
    write('source-after.json', after)
    bound_after = {str(path): record(path) for path in runtime_paths}
    write('runtime-binding-after.json', bound_after)
    guards = {
        'source_unchanged': before == after,
        'runtime_graph_locks_unchanged': bound_before == bound_after,
        'source_matches_start_commit': match_head(start_head, before),
        'source_matches_end_commit': match_head(end_head, after),
        'workspace_matches_source': all(
            record(workspace / path) == value for path, value in after.items()
        ),
    }
    detail = {}
    accepted = exit_code == 0 and not timed_out and all(guards.values())
    if args.cohort in ('engine', 'editor'):
        events, parse_errors = [], []
        for line_number, line in enumerate((out / output_name).read_text().splitlines(), 1):
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                parse_errors.append({'line': line_number, 'text': line})
        starts = {event['test']['id']: event['test'] for event in events if event.get('type') == 'testStart'}
        suites = {event['suite']['id']: event['suite'] for event in events if event.get('type') == 'suite'}
        finishes = [event for event in events if event.get('type') == 'testDone']
        completion = [event for event in events if event.get('type') == 'done']
        errors = [event for event in events if event.get('type') == 'error']
        diagnostics = [event for event in events if event.get('type') == 'print' and any(
            token in event.get('message', '') for token in ('overflowed', 'would not hit test', 'EXCEPTION CAUGHT')
        )]
        cases, excluded = [], []
        for finish in finishes:
            test = starts.get(finish['testID'], {})
            case = {'id': finish['testID'], 'name': test.get('name'),
                    'suite': suites.get(test.get('suiteID'), {}).get('path'),
                    'result': finish['result'], 'skipped': finish.get('skipped', False)}
            target = excluded if finish.get('hidden') or test.get('name', '').endswith(('(setUpAll)', '(tearDownAll)')) else cases
            target.append(case)
        guards['all_selected_suites_executed'] = {
            str(Path(suite['path']).resolve()) for suite in suites.values()
        } == {str((workspace / path).resolve()) for path in selected}
        guards['every_started_event_finished_once'] = set(starts) == {
            finish['testID'] for finish in finishes
        } and len(starts) == len(finishes)
        accepted = accepted and all(guards.values()) and not errors and not diagnostics and not parse_errors
        accepted = accepted and len(completion) == 1 and completion[0].get('success') and bool(cases)
        accepted = accepted and all(case['result'] == 'success' and not case['skipped'] for case in cases)
        write('cases.json', cases)
        write('excluded-events.json', excluded)
        detail = {'suite_count': len(suites), 'substantive_test_count': len(cases),
                  'substantive_results': dict(Counter(case['result'] for case in cases)),
                  'skipped': sum(bool(case['skipped']) for case in cases), 'error_events': errors,
                  'diagnostic_events': diagnostics, 'parse_errors': parse_errors,
                  'completion_events': completion}
    elif args.cohort == 'panel':
        panel = json.loads((out / output_name).read_text())
        write('panel.json', panel)
        panel_cases = panel.get('cases', [])
        accepted = accepted and panel.get('caseCount') == 48 and len(panel_cases) == 48
        accepted = accepted and panel.get('failed') == 0 and all(case.get('accepted') is True for case in panel_cases)
        accepted = accepted and len({case['id'] for case in panel_cases}) == 48
        detail = {'case_count': panel.get('caseCount'), 'failed_cases': panel.get('failed')}
    summary = {**run, **detail, 'status': 'passed' if accepted else 'failed',
               'finished_at_utc': now(), 'elapsed_seconds': elapsed,
               'actual_process_exit_code': exit_code, 'timed_out': timed_out,
               'head_at_end': end_head, 'guards': guards}
    summary['artifacts'] = {path.name: record(path) for path in sorted(out.iterdir())
                            if path.is_file() and path.name != 'summary.json'}
    write('summary.json', summary)
    print(json.dumps({key: value for key, value in summary.items() if key in (
        'cohort', 'status', 'suite_count', 'substantive_test_count', 'substantive_results',
        'case_count', 'failed_cases', 'actual_process_exit_code', 'elapsed_seconds', 'guards'
    )}, indent=2), flush=True)
    if lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()
    raise SystemExit(0 if accepted else 1)


if __name__ == '__main__':
    main()
