#!/usr/bin/env python3
"""Plan, then explicitly run pinned local Mail and incoming Office gates.

Planning executes no Dart/Flutter commands. The task owner must authorize the
separate --run invocation after freezing source. No Git mutation, remote API,
SDK modification, automatic retry, or reference-image update is performed.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import datetime as dt
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
BASE = '4621326a5a452da475f219353c298d0f9b12470e'
STUDIO = Path('packages/quds_office_editor/example')
MAIL_UI = Path('packages/quds_mail_ui')
ENGINE = Path('packages/quds_office_engine')
ENGINE_TESTS = [
    'word_directional_paragraph_io_test.dart',
    'office_vba_string_intrinsics_test.dart',
    'office_vba_variant_substrings_test.dart',
    'office_vba_word_headers_footers_test.dart',
    'office_vba_word_named_measurements_test.dart',
    'office_vba_word_named_selectors_test.dart',
    'office_vba_word_page_setup_test.dart',
    'office_vba_word_text_selectors_conformance_test.dart',
    'office_vba_word_cell_paragraphs_test.dart',
    'office_vba_word_named_measurements_integration_test.dart',
    'office_vba_word_text_selectors_cli_test.dart',
    'office_vba_word_text_selectors_directional_test.dart',
    'office_vba_word_text_selectors_integration_test.dart',
    'word_zotero_paragraph_format_test.dart',
]
RULER_INPUTS = [
    'packages/quds_office_editor/lib/src/editor_word/office_ruler.dart',
    'packages/quds_office_editor/test/word_ruler_directional_indent_test.dart',
    'packages/quds_office_editor/lib/src/embed/office_theme.dart',
    'packages/quds_office_editor/lib/src/ui_components/office_chrome.dart',
    'packages/quds_office_editor/lib/src/editor_word/paint_run_text.dart',
    'packages/quds_office_engine/lib/src/word/properties/wml_properties.dart',
]
ROOT_INPUTS = {
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.fvmrc',
    'dart_test.yaml', 'build.yaml',
}
GENERATED_INPUTS = ['.dart_tool/package_config.json', '.dart_tool/package_graph.json']
ENVIRONMENT_KEYS = [
    'BOT', 'CI', 'FLUTTER_ROOT', 'PUB_CACHE', 'TMPDIR',
    'FLUTTER_SUPPRESS_ANALYTICS', 'DART_SUPPRESS_ANALYTICS',
]


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def write_json(path, value):
    path.write_bytes(json_bytes(value))


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


def current_head():
    return git('rev-parse', 'HEAD').decode().strip()


def input_paths():
    paths = set(git('ls-files', '-z', '--cached', '--others', '--exclude-standard').decode().split('\0'))
    # Include all local package sources, tests, fixtures, assets, BAS examples,
    # CLI helpers and manifests. Only screenshots are outside the execution
    # scope. Historical top-level validation/evidence files are not copied.
    return sorted(path for path in paths if path and (
        path in ROOT_INPUTS
        or path.startswith(('packages/', 'third_party/'))
        and '/screenshots/' not in path
    ))


def stable_bytes(path):
    before = path.stat()
    data = path.read_bytes()
    after = path.stat()
    identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    if identity(before) != identity(after) or len(data) != after.st_size:
        raise RuntimeError(f'Input changed while hashing: {path}')
    return data


def tree_blobs(ref):
    result = {}
    for row in git('ls-tree', '-r', '-z', ref).split(b'\0'):
        if row:
            metadata, path = row.split(b'\t', 1)
            mode, kind, blob = metadata.decode().split()
            result[path.decode()] = {'mode': mode, 'kind': kind, 'blob': blob}
    return result


def capture_inputs(expected_head):
    blobs = tree_blobs(expected_head)
    entries = {}
    for relative in input_paths():
        path = REPO / relative
        if not path.exists() and not path.is_symlink():
            entries[relative] = {'missing': True, 'matches_expected_head': False}
            continue
        if path.is_symlink():
            data = os.readlink(path).encode()
            target = path.resolve()
            if not target.is_relative_to(REPO):
                raise RuntimeError(f'Source symlink leaves repository: {relative}')
            target_sha = digest(stable_bytes(target))
        else:
            data = stable_bytes(path)
            target_sha = None
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        recorded = blobs.get(relative)
        entries[relative] = {
            'bytes': len(data), 'sha256': digest(data), 'actual_blob': blob,
            'expected_blob': recorded['blob'] if recorded else None,
            'matches_expected_head': recorded is not None and blob == recorded['blob'],
            **({'symlink_target_sha256': target_sha} if target_sha else {}),
        }
    generated = {}
    for relative in GENERATED_INPUTS:
        data = stable_bytes(REPO / relative)
        generated[relative] = {'bytes': len(data), 'sha256': digest(data)}
    return {
        'captured_at_utc': now(), 'observed_head': current_head(),
        'expected_head': expected_head, 'entries': entries, 'generated': generated,
        'policy': 'All tracked and untracked nonignored package/third_party files excluding screenshots; root manifests, pin and analysis configuration; generated root package configuration/graph.',
    }


def source_drift(before, after):
    changed = []
    for path in set(before['entries']) | set(after['entries']):
        left = before['entries'].get(path, {})
        right = after['entries'].get(path, {})
        if (left.get('sha256'), left.get('symlink_target_sha256'), left.get('missing')) != (
            right.get('sha256'), right.get('symlink_target_sha256'), right.get('missing')
        ):
            changed.append(path)
    return {
        'changed_source_inputs': sorted(changed),
        'generated_inputs_unchanged': before['generated'] == after['generated'],
        'stable': not changed and before['generated'] == after['generated'],
    }


def changed_dart_paths():
    tracked = git('diff', '--name-only', '-z', BASE, '--', '*.dart').decode().split('\0')
    untracked = git('ls-files', '-z', '--others', '--exclude-standard', '--', '*.dart').decode().split('\0')
    return sorted({path for path in tracked + untracked if path
        and path.startswith(('packages/', 'third_party/')) and (REPO / path).is_file()})


def selection():
    tests = REPO / STUDIO / 'test'
    studio = sorted({p.relative_to(REPO).as_posix() for p in tests.glob('studio_mail*_test.dart')} | {
        (STUDIO / 'test/studio_saved_mail_test.dart').as_posix(),
        (STUDIO / 'test/suite_workspace_mail_shortcuts_test.dart').as_posix(),
    })
    ui = sorted(p.relative_to(REPO).as_posix() for p in (REPO / MAIL_UI / 'test').rglob('*_test.dart'))
    engine = [(ENGINE / 'test' / name).as_posix() for name in ENGINE_TESTS]
    return {'studio_mail': studio, 'shared_mail_ui': ui, 'incoming_engine': engine}


def ruler_continuity():
    path = HERE.parent / 'incoming/inputs-before.json.gz'
    before = json.loads(gzip.decompress(path.read_bytes()))['tracked']
    rows = {}
    for relative in RULER_INPUTS:
        current = digest(stable_bytes(REPO / relative))
        original = before[relative]['sha256']
        rows[relative] = {'qualified_sha256': original, 'current_sha256': current, 'unchanged': current == original}
    return {
        'qualification': '../incoming/editor-result.json', 'original_passed_cases': 10,
        'inputs': rows, 'unchanged': all(row['unchanged'] for row in rows.values()),
        'counted_as_fresh': False,
        'scope': 'Retained focused ruler arithmetic qualification by exact unchanged source/test/model/helper hashes; no claim that the entire Office dependency closure stayed unchanged.',
    }


def runtime_info():
    sdk = Path(os.environ['FLUTTER_ROOT'])
    pin = json.loads((REPO / '.fvmrc').read_text())['flutter']
    version = json.loads((sdk / 'bin/cache/flutter.version.json').read_text())
    observed = version.get('frameworkVersion', version.get('flutterVersion'))
    if observed != pin:
        raise RuntimeError(f'Runtime {observed} differs from repository pin {pin}')
    executables = [sdk / 'bin/cache/dart-sdk/bin/dart', sdk / 'bin/cache/artifacts/engine/linux-x64/flutter_tester']
    return {
        'version': version, 'pinned_flutter': pin,
        'executables_sha256': {str(p): digest(stable_bytes(p)) for p in executables},
        'environment': {key: os.environ.get(key) for key in ENVIRONMENT_KEYS},
        'metadata_probe_suppression': 'BOT=true and CI=true short-circuit Flutter BotDetector before its Azure metadata fallback. SDK source and network controls are unchanged.',
    }


def commands(selected, static, ruler):
    sdk = Path(os.environ.get('FLUTTER_ROOT', REPO.parent / 'runtime/flutter'))
    dart = str(sdk / 'bin/cache/dart-sdk/bin/dart')
    flutter = str(sdk / 'bin/flutter')
    gates = [
        {'name': 'analysis', 'cwd': '.', 'kind': 'static', 'command': [dart, 'analyze', '--fatal-infos', *static]},
        {'name': 'format', 'cwd': '.', 'kind': 'static', 'command': [dart, 'format', '--output=none', '--set-exit-if-changed', *static]},
    ]
    for name, cwd, executable, extra in [
        ('incoming_engine', ENGINE, dart, []),
        ('studio_mail', STUDIO, flutter, ['--no-pub']),
        ('shared_mail_ui', MAIL_UI, flutter, ['--no-pub']),
    ]:
        files = selected[name]
        relative = [str(Path(path).relative_to(cwd)) for path in files]
        gates.append({'name': name, 'cwd': str(cwd), 'kind': 'tests', 'expected_suites': files,
            'command': [executable, 'test', *extra, '--concurrency=2', '--reporter=json', *relative]})
    if not ruler['unchanged']:
        cwd = Path('packages/quds_office_editor')
        file = str(cwd / 'test/word_ruler_directional_indent_test.dart')
        gates.append({'name': 'changed_ruler', 'cwd': str(cwd), 'kind': 'tests', 'expected_suites': [file],
            'command': [flutter, 'test', '--no-pub', '--concurrency=2', '--reporter=json', 'test/word_ruler_directional_indent_test.dart']})
    return gates


def parse_reporter(path, cwd, expected):
    tests, completed, suites, errors, done = {}, {}, {}, [], []
    duplicate_starts, duplicate_completions, non_json = [], [], []
    for number, line in enumerate(path.read_text(errors='replace').splitlines(), 1):
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            non_json.append({'line': number, 'text': line})
            continue
        if not isinstance(event, dict):
            non_json.append({'line': number, 'text': line})
            continue
        kind = event.get('type')
        if kind == 'testStart':
            identifier = event['test']['id']
            if identifier in tests:
                duplicate_starts.append(identifier)
            tests[identifier] = event['test']
        elif kind == 'testDone':
            identifier = event['testID']
            if identifier in completed:
                duplicate_completions.append(identifier)
            completed[identifier] = event
        elif kind == 'suite':
            suite = event['suite']
            raw = suite.get('path')
            if raw:
                absolute = Path(raw) if Path(raw).is_absolute() else cwd / raw
                suite['canonical_path'] = str(absolute.relative_to(REPO)) if absolute.is_relative_to(REPO) else str(absolute)
            suites[suite['id']] = suite
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            done.append(event)
    cases, excluded = [], []
    for identifier, test in tests.items():
        end = completed.get(identifier, {})
        name = test['name']
        reason = ('hidden' if end.get('hidden') else
            'suite_loader' if name.startswith('loading ') else
            'fixture_hook' if re.search(r'(?:^| )\((?:setUpAll|tearDownAll)\)$', name) else None)
        row = {'id': identifier, 'suite': suites.get(test.get('suiteID'), {}).get('canonical_path'),
            'name': name, 'result': end.get('result', 'incomplete'), 'skipped': bool(end.get('skipped', False))}
        if reason:
            excluded.append(row | {'reason': reason})
        else:
            cases.append(row)
    canonical = defaultdict(list)
    for row in cases:
        canonical[(row['suite'], row['name'])].append(row)
    success, failed, skipped, incomplete = set(), set(), set(), set()
    for key, attempts in canonical.items():
        if any(row['result'] == 'incomplete' for row in attempts):
            incomplete.add(key)
        elif any(row['result'] in ('failure', 'error') for row in attempts):
            failed.add(key)
        elif any(row['skipped'] for row in attempts):
            skipped.add(key)
        elif all(row['result'] == 'success' for row in attempts):
            success.add(key)
    counts = defaultdict(Counter)
    for label, keys in [('passed', success), ('failed', failed), ('skipped', skipped), ('incomplete', incomplete)]:
        for file, name in keys:
            counts[file][label] += 1
    observed = {suite.get('canonical_path') for suite in suites.values()} - {None}
    return {
        'suite_count': len(suites), 'expected_suite_count': len(expected),
        'missing_suites': sorted(set(expected) - observed), 'unexpected_suites': sorted(observed - set(expected)),
        'unique_started_cases': len(canonical), 'unique_completed_cases': len(canonical) - len(incomplete),
        'passed_cases': len(success), 'failed_cases': len(failed), 'skipped_cases': len(skipped),
        'incomplete_cases': len(incomplete), 'case_attempts': len(cases),
        'duplicate_case_names': [{'suite': key[0], 'name': key[1], 'attempts': len(value)} for key, value in canonical.items() if len(value) > 1],
        'started_lifecycles': len(tests), 'completed_lifecycles': len(completed),
        'incomplete_lifecycle_ids': sorted(set(tests) - set(completed)),
        'orphan_completion_ids': sorted(set(completed) - set(tests)),
        'duplicate_start_ids': duplicate_starts, 'duplicate_completion_ids': duplicate_completions,
        'excluded_lifecycles': excluded, 'per_file_counts': dict(counts),
        'errors': errors, 'done_events': done, 'non_json_output': non_json, 'cases': cases,
        'reporter_success': len(done) == 1 and done[0].get('success') is True,
    }


def pack_file(path):
    data = path.read_bytes()
    packed = path.with_name(path.name + '.gz')
    packed.write_bytes(gzip.compress(data, mtime=0))
    result = {'path': packed.name, 'raw_bytes': len(data), 'raw_sha256': digest(data), 'gzip_sha256': digest(packed.read_bytes())}
    path.unlink()
    return result


def save_manifest(directory, name, manifest):
    path = directory / name
    write_json(path, manifest)
    return pack_file(path)


def execute_gate(gate, directory, environment):
    record = gate | {'started_at_utc': now(), 'observed_head': current_head(), 'status': 'running'}
    write_json(directory / (gate['name'] + '-command.json'), record)
    stdout = directory / (gate['name'] + '.jsonl' if gate['kind'] == 'tests' else gate['name'] + '.stdout')
    stderr = directory / (gate['name'] + '.stderr')
    started = time.monotonic()
    interrupted = False
    print(json.dumps({'gate': gate['name'], 'status': 'started', 'utc': now()}), flush=True)
    with stdout.open('wb') as so, stderr.open('wb') as se:
        process = subprocess.Popen(gate['command'], cwd=REPO / gate['cwd'], env=environment,
            stdout=so, stderr=se, start_new_session=True)
        try:
            while True:
                try:
                    exit_code = process.wait(timeout=30)
                    break
                except subprocess.TimeoutExpired:
                    print(json.dumps({'gate': gate['name'], 'status': 'running', 'elapsed_seconds': round(time.monotonic() - started)}), flush=True)
        except KeyboardInterrupt:
            interrupted = True
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGINT)
                except ProcessLookupError:
                    pass
            try:
                exit_code = process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                exit_code = process.wait(timeout=30)
    record.update({'finished_at_utc': now(), 'exit_code': exit_code, 'interrupted': interrupted, 'status': 'completed'})
    if gate['kind'] == 'tests':
        record['reporter'] = parse_reporter(stdout, REPO / gate['cwd'], gate['expected_suites'])
    record['stdout'] = pack_file(stdout)
    record['stderr'] = pack_file(stderr)
    write_json(directory / (gate['name'] + '-result.json'), record)
    write_json(directory / (gate['name'] + '-command.json'), {key: value for key, value in record.items() if key != 'reporter'})
    report = record.get('reporter', {})
    print(json.dumps({'gate': gate['name'], 'exit_code': exit_code,
        **{key: report[key] for key in ('passed_cases', 'failed_cases', 'skipped_cases', 'incomplete_cases') if key in report}}), flush=True)
    return record


def plan():
    selected = selection()
    static = changed_dart_paths()
    ruler = ruler_continuity()
    return {
        'planned_at_utc': now(), 'observed_head': current_head(), 'comparison_base': BASE,
        'gate_execution_authorized_by_this_command': False,
        'suite_counts': {key: len(value) for key, value in selected.items()},
        'suite_selection': selected, 'changed_dart_paths': static, 'static_path_count': len(static),
        'planned_source_input_count': len(input_paths()),
        'manifest_policy': 'Full local package/third_party sources/tests/fixtures/assets/examples/CLI helpers and manifests, excluding screenshots; root lock/config/pin and generated package config/graph. No old validation evidence is copied.',
        'retained_ruler': ruler, 'commands': commands(selected, static, ruler),
        'missing_planned_suites': [path for files in selected.values() for path in files if not (REPO / path).is_file()],
        'execution_policy': 'All gates sequential. Test-runner concurrency=2. Normal pinned runners; no automatic retries, CI polling, golden updates, SDK patches or Git mutations. Source is captured at --run time and rechecked after every gate.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--plan', action='store_true')
    mode.add_argument('--run', action='store_true')
    parser.add_argument('--expected-head')
    parser.add_argument('--run-id')
    args = parser.parse_args()
    planned = plan()
    if args.plan:
        write_json(HERE / 'plan.json', planned)
        print(json.dumps({key: planned[key] for key in ('observed_head', 'suite_counts', 'static_path_count', 'planned_source_input_count', 'missing_planned_suites')}, indent=2))
        return 0
    if not args.expected_head or current_head() != args.expected_head:
        parser.error('--run requires --expected-head equal to the current exact Git HEAD')
    if 'FLUTTER_ROOT' not in os.environ or 'PUB_CACHE' not in os.environ:
        parser.error('Source the prepared runtime/env.sh before running')
    if planned['missing_planned_suites']:
        parser.error('A planned test suite is missing; inspect plan.json')
    os.environ.update({'BOT': 'true', 'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'DART_SUPPRESS_ANALYTICS': 'true'})
    runtime = runtime_info()
    run_id = args.run_id or dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', run_id):
        parser.error('--run-id must contain only letters, digits, underscore or hyphen')
    directory = HERE / run_id
    directory.mkdir()  # Never overwrite an earlier run.
    expected = args.expected_head
    before = capture_inputs(expected)
    write_json(directory / 'selection.json', planned | {'gate_execution_authorized_by_this_command': True})
    write_json(directory / 'runtime.json', runtime)
    write_json(directory / 'retained-ruler.json', planned['retained_ruler'])
    manifests = [save_manifest(directory, 'inputs-before.json', before)]
    results, drifts = [], []
    runner_sha = digest(Path(__file__).read_bytes())
    for gate in planned['commands']:
        result = execute_gate(gate, directory, os.environ.copy())
        results.append(result)
        after = capture_inputs(expected)
        comparison = source_drift(before, after)
        drifts.append({'after_gate': gate['name'], **comparison})
        manifests.append(save_manifest(directory, 'inputs-after-' + gate['name'] + '.json', after))
        write_json(directory / 'progress.json', {'completed_gates': [r['name'] for r in results], 'source_checks': drifts})
        if result['interrupted'] or not comparison['stable']:
            break
    test_results = [record for record in results if record['kind'] == 'tests']
    protocols_ok = all(record['reporter']['reporter_success']
        and not record['reporter']['incomplete_lifecycle_ids']
        and not record['reporter']['orphan_completion_ids']
        and not record['reporter']['duplicate_start_ids']
        and not record['reporter']['duplicate_completion_ids']
        and not record['reporter']['missing_suites']
        and not record['reporter']['unexpected_suites'] for record in test_results)
    summary = {
        'expected_source_head': expected, 'finished_head': current_head(),
        'runner_sha256_before': runner_sha, 'runner_sha256_after': digest(Path(__file__).read_bytes()),
        'captured_source_inputs': len(before['entries']),
        'inputs_not_matching_source_commit': [path for path, value in before['entries'].items() if not value['matches_expected_head']],
        'input_manifests': manifests, 'source_checks': drifts,
        'all_planned_gates_completed': len(results) == len(planned['commands']),
        'all_commands_exit_zero': all(record['exit_code'] == 0 for record in results),
        'all_reporters_complete': protocols_ok,
        'fresh_unique_passed_cases': sum(record['reporter']['passed_cases'] for record in test_results),
        'fresh_unique_failed_cases': sum(record['reporter']['failed_cases'] for record in test_results),
        'fresh_unique_skipped_cases': sum(record['reporter']['skipped_cases'] for record in test_results),
        'fresh_unique_incomplete_cases': sum(record['reporter']['incomplete_cases'] for record in test_results),
        'gate_summaries': [{key: record[key] for key in ('name', 'exit_code', 'started_at_utc', 'finished_at_utc')} |
            ({key: record['reporter'][key] for key in ('suite_count', 'passed_cases', 'failed_cases', 'skipped_cases', 'per_file_counts')} if record['kind'] == 'tests' else {}) for record in results],
        'historical_results_added_to_fresh_total': False,
        'scope': 'Local normal-runner regression only; no live-provider, installed-platform or complete product-parity claim. GitHub Actions not queried or awaited.',
    }
    summary['accepted'] = (summary['all_planned_gates_completed'] and summary['all_commands_exit_zero']
        and protocols_ok and all(row['stable'] for row in drifts)
        and not summary['inputs_not_matching_source_commit']
        and summary['runner_sha256_before'] == summary['runner_sha256_after'])
    write_json(directory / 'summary.json', summary)
    sums = [digest(path.read_bytes()) + '  ' + path.name for path in sorted(directory.iterdir()) if path.is_file() and path.name != 'SHA256SUMS.txt']
    (directory / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n')
    print(json.dumps({key: summary[key] for key in ('accepted', 'fresh_unique_passed_cases', 'fresh_unique_failed_cases', 'fresh_unique_skipped_cases', 'all_planned_gates_completed')}, indent=2), flush=True)
    return 0 if summary['accepted'] else 1


if __name__ == '__main__':
    sys.exit(main())
