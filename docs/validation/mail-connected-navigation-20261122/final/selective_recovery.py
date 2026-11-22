#!/usr/bin/env python3
"""Qualify two corrected test fixtures without replaying unaffected suites.

Planning and continuity proof are read-only with respect to package source and
runtime execution. --run requires an explicitly supplied, exact frozen HEAD.
The original failed qualification and every original checksum remain intact.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlparse


sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
HELPER = HERE / 'qualify_mail.py'
HELPER_SHA256 = '011edb05704918cd2c79315b1eda6fef8eba63c43eb4706e433a6aaa15f44935'
BASELINE_RUN = 'reconciled-source-recovery'
BASELINE_SOURCE = '604a939991f568e7c6ad3f13958c6a4e204cafe1'
PREFIX = 'packages/quds_office_editor/example/test/'
AFFECTED = [
    PREFIX + 'studio_mail_bulk_provider_test.dart',
    PREFIX + 'studio_mail_session_test.dart',
]
EXPECTED_FAILURES = {
    (AFFECTED[0], provider + ': disconnect and reconnect cannot project late results into overlapping row IDs')
    for provider in ('ews', 'gmail', 'graph')
} | {(AFFECTED[1], 'a delayed native draft open cannot install the previous account store')}
BASELINE_GATES = ['incoming_engine', 'incoming_editor', 'studio_zotero', 'studio_mail']


def sha(data):
    return hashlib.sha256(data).hexdigest()


def helper():
    if sha(HELPER.read_bytes()) != HELPER_SHA256:
        raise RuntimeError('The frozen 604 qualification helper changed')
    spec = importlib.util.spec_from_file_location('frozen_mail_qualification', HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


q = helper()


def verify_index(directory):
    records = {}
    for line in (directory / 'SHA256SUMS.txt').read_text().split('\n'):
        if not line:
            continue
        expected, name = line.split('  ', 1)
        if Path(name).name != name or name in ('.', '..'):
            raise RuntimeError('Unsafe evidence checksum entry')
        actual = sha(q.stable_bytes(directory / name))
        if actual != expected:
            raise RuntimeError(f'Original evidence changed: {directory.name}/{name}')
        records[name] = actual
    return records


def unpack(directory, metadata):
    packed = q.stable_bytes(directory / metadata['path'])
    raw = gzip.decompress(packed)
    if sha(packed) != metadata['gzip_sha256'] or sha(raw) != metadata['raw_sha256']:
        raise RuntimeError(f'Raw/compressed evidence hash mismatch: {metadata["path"]}')
    return raw


def identity(case):
    return (case['suite'], case['name'])


def structural_reporter(report):
    """A failed run may still have a complete, auditable event protocol."""
    return (len(report['reporter_start_events']) == 1
        and report['reporter_start_events'][0].get('protocolVersion') == '0.1.1'
        and len(report['done_events']) == 1
        and not report['non_json_output']
        and not report['incomplete_lifecycle_ids'] and not report['orphan_completion_ids']
        and not report['duplicate_start_ids'] and not report['duplicate_completion_ids']
        and not report['duplicate_case_names']
        and not report['missing_suites'] and not report['unexpected_suites']
        and not report['skipped_cases'] and not report['incomplete_cases'])


def baseline():
    directory = HERE / BASELINE_RUN
    hashes = verify_index(directory)
    summary = json.loads((directory / 'summary.json').read_text())
    selection = json.loads((directory / 'selection.json').read_text())
    runtime = json.loads((directory / 'runtime.json').read_text())
    manifests = [json.loads(unpack(directory, row)) for row in summary['input_manifests']]
    before = manifests[0]
    source_stable = all(q.source_drift(before, item)['stable'] for item in manifests)
    if (summary['expected_source_head'] != BASELINE_SOURCE or summary['accepted'] is not False
            or summary['runner_sha256_before'] != HELPER_SHA256
            or summary['runner_sha256_after'] != HELPER_SHA256
            or summary['inputs_not_matching_source_commit'] or not source_stable
            or not all(item['expected_head'] == BASELINE_SOURCE for item in manifests)
            or not all(row['matches_expected_head'] for row in before['entries'].values())):
        raise RuntimeError('Baseline source identity/stability is not the recorded failed 604 run')
    static = {name: json.loads((directory / (name + '-result.json')).read_text())
        for name in ('analysis', 'format')}
    if not all(record['exit_code'] == 0 for record in static.values()):
        raise RuntimeError('Baseline static gates did not complete successfully')
    retained_cases, discarded_cases, seeds, gate_rows = [], [], [], []
    failure_cases, error_rows = [], []
    for name in BASELINE_GATES:
        record = json.loads((directory / (name + '-result.json')).read_text())
        raw = unpack(directory, record['stdout'])
        unpack(directory, record['stderr'])
        report = q.parse_reporter(raw, q.REPO / record['cwd'], record['expected_suites'])
        if not structural_reporter(report):
            raise RuntimeError(f'Baseline {name} reporter is structurally incomplete')
        if name != 'studio_mail' and (record['exit_code'] != 0 or not q.complete_reporter(report)):
            raise RuntimeError(f'An independent baseline gate failed: {name}')
        if name == 'studio_mail' and (record['exit_code'] != 1 or report['reporter_success']):
            raise RuntimeError('The original failed Mail run must remain failed')
        case_by_id = {case['id']: case for case in report['cases'] + report['excluded_lifecycles']}
        for error in report['errors']:
            case = case_by_id.get(error.get('testID'))
            if case is None or case['suite'] not in AFFECTED or identity(case) not in EXPECTED_FAILURES:
                raise RuntimeError('Baseline error is outside the two approved excluded fixtures')
            error_rows.append({'test_id': error['testID'], 'suite': case['suite'],
                'name': case['name'], 'error': error['error']})
        for excluded in report['excluded_lifecycles']:
            if excluded['result'] != 'success' or excluded['skipped']:
                raise RuntimeError('A hidden loader/fixture-hook failure prevents selective retention')
        for case in report['cases']:
            if case['result'] in ('failure', 'error'):
                failure_cases.append(case)
            if case['suite'] in AFFECTED:
                discarded_cases.append(case)
            else:
                if case['result'] != 'success' or case['skipped']:
                    raise RuntimeError('A retained case did not pass')
                retained_cases.append(case)
        retained_suites = [file for file in record['expected_suites'] if file not in AFFECTED]
        seeds.extend(retained_suites)
        gate_rows.append({'name': name, 'original_result': f'../{BASELINE_RUN}/{name}-result.json',
            'raw_reporter_sha256': record['stdout']['raw_sha256'],
            'original_exit_code': record['exit_code'],
            'started_lifecycles': report['started_lifecycles'],
            'completed_lifecycles': report['completed_lifecycles'],
            'structurally_complete': True, 'retained_suite_count': len(retained_suites),
            'retained_passed_cases': sum(case['suite'] not in AFFECTED for case in report['cases']),
            'discarded_cases': sum(case['suite'] in AFFECTED for case in report['cases']),
            'per_file_counts': report['per_file_counts']})
    if ({identity(case) for case in failure_cases} != EXPECTED_FAILURES
            or len(failure_cases) != 4 or len(error_rows) != 4
            or {row['test_id'] for row in error_rows} != {case['id'] for case in failure_cases}
            or len(discarded_cases) != 60 or len(retained_cases) != 6916
            or len(set(seeds)) != 234):
        raise RuntimeError('Baseline failure attribution or retained/discarded scope differs from the approved plan')
    return {'directory': directory, 'hashes': hashes, 'summary': summary,
        'selection': selection, 'runtime': runtime, 'before': before,
        'retained_cases': retained_cases, 'discarded_cases': discarded_cases,
        'failure_cases': failure_cases, 'errors': error_rows, 'seeds': seeds,
        'gate_rows': gate_rows, 'manifest_count': len(manifests)}


def retained_imports(seeds, current_inputs):
    """Walk actual local directives, including Studio, rejecting both fixtures."""
    configuration = json.loads((q.REPO / '.dart_tool/package_config.json').read_text())
    libraries = {}
    for package in configuration['packages']:
        uri = urlparse(package['rootUri'])
        if uri.scheme == 'file':
            root = Path(unquote(uri.path)).resolve()
        elif not uri.scheme:
            root = (q.REPO / '.dart_tool' / unquote(package['rootUri'])).resolve()
        else:
            raise RuntimeError('Unsupported package URI in the captured resolver')
        libraries[package['name']] = root / package.get('packageUri', 'lib/')
    pending = [(q.REPO / file).resolve() for file in seeds]
    forbidden = {(q.REPO / file).resolve() for file in AFFECTED}
    visited, forbidden_references, unresolved, uncaptured = {}, set(), set(), set()
    directive = re.compile(r'''(?m)^\s*(?:import|export|part)\s+(?=r?['"])([^;]*);''')
    quoted = re.compile(r"['\"]([^'\"]+)['\"]")
    while pending:
        path = pending.pop()
        if path in forbidden:
            forbidden_references.add(str(path.relative_to(q.REPO)))
            continue
        if path in visited or not path.is_relative_to(q.REPO):
            continue
        if not path.is_file():
            unresolved.add(str(path))
            continue
        data = q.stable_bytes(path)
        relative = str(path.relative_to(q.REPO))
        visited[path] = sha(data)
        if current_inputs['entries'].get(relative, {}).get('sha256') != sha(data):
            uncaptured.add(relative)
        for statement in directive.findall(data.decode('utf-8')):
            for uri in quoted.findall(statement):
                if uri.startswith('dart:'):
                    continue
                if uri.startswith('package:'):
                    name, separator, suffix = uri[len('package:'):].partition('/')
                    if not separator or name not in libraries:
                        unresolved.add(uri)
                        continue
                    target = (libraries[name] / suffix).resolve()
                elif urlparse(uri).scheme:
                    unresolved.add(uri)
                    continue
                else:
                    target = (path.parent / uri).resolve()
                if target.is_relative_to(q.REPO):
                    pending.append(target)
    return {'seed_paths': seeds, 'local_dart_file_count': len(visited),
        'local_dart_sha256': {str(path.relative_to(q.REPO)): value for path, value in sorted(visited.items())},
        'forbidden_fixture_references': sorted(forbidden_references),
        'unresolved_directives': sorted(unresolved), 'uncaptured_or_mismatched_files': sorted(uncaptured),
        'accepted': not forbidden_references and not unresolved and not uncaptured,
        'scope': 'All retained test entry points plus engine CLI entry points; recursive repository-owned import/export/part directives including conditional branches. Hosted/SDK inputs remain pinned by identical resolver, lock and runtime. Neither changed test fixture may be imported by a retained test.'}


def proof(base, current_inputs, runtime):
    difference = q.source_drift(base['before'], current_inputs)
    same_keys = set(base['before']['entries']) == set(current_inputs['entries'])
    runtime_equal = (base['runtime']['version'] == runtime['version']
        and base['runtime']['executables_sha256'] == runtime['executables_sha256'])
    carry = {name: q.retained_continuity(run, current_inputs, runtime, gate_name=name)
        for name, run in [('shared_mail_ui', 'qualified-source'), ('incoming_store', 'merged-source-recovery')]}
    retained_cases = list(base['retained_cases'])
    seeds = list(base['seeds'])
    for name, value in carry.items():
        original = HERE / value['original_run']
        record = json.loads((original / (name + '-result.json')).read_text())
        report = q.parse_reporter(unpack(original, record['stdout']), q.REPO / record['cwd'], record['expected_suites'])
        if not q.complete_reporter(report):
            raise RuntimeError('Retained store/UI raw reporter does not pass')
        retained_cases.extend(report['cases'])
        seeds.extend(record['expected_suites'])
    test_seeds = sorted(set(seeds))
    cli_seeds = sorted(path.relative_to(q.REPO).as_posix()
        for path in (q.REPO / q.ENGINE / 'tool/macros').glob('*.dart'))
    imports = retained_imports(sorted(set(test_seeds + cli_seeds)), current_inputs)
    keys = [identity(case) for case in retained_cases]
    discarded_keys = {identity(case) for case in base['discarded_cases']}
    names_unique = len(keys) == len(set(keys)) and not (set(keys) & discarded_keys)
    eligible = (set(difference['changed_source_inputs']) == set(AFFECTED) and same_keys
        and len(current_inputs['entries']) == 6151 and difference['generated_inputs_unchanged']
        and runtime_equal and imports['accepted'] and names_unique
        and len(retained_cases) == 7257 and len(test_seeds) == 254
        and all(value['accepted'] for value in carry.values()))
    return {'eligible_for_selective_run': eligible, 'baseline_source': BASELINE_SOURCE,
        'baseline_run': BASELINE_RUN, 'baseline_overall_accepted': False,
        'baseline_artifact_sha256': base['hashes'],
        'baseline_source_manifests_verified': base['manifest_count'],
        'captured_input_count': len(current_inputs['entries']), 'same_input_path_set': same_keys,
        'changed_source_inputs': difference['changed_source_inputs'], 'allowed_changes': AFFECTED,
        'fixture_sha256': {path: {'baseline': base['before']['entries'][path]['sha256'],
            'candidate': current_inputs['entries'][path]['sha256']} for path in AFFECTED},
        'generated_configuration_unchanged': difference['generated_inputs_unchanged'],
        'runtime_identity_unchanged': runtime_equal,
        'helper_sha256': HELPER_SHA256, 'baseline_gate_retention': base['gate_rows'],
        'baseline_errors_attributed_to_excluded_cases': base['errors'],
        'discarded_original_cases': base['discarded_cases'], 'discarded_original_case_count': 60,
        'discarded_original_passed_cases': 56, 'discarded_original_failed_cases': 4,
        'retained_case_count': len(retained_cases), 'retained_suite_count': len(test_seeds),
        'retained_case_identity_sha256': sha(q.json_bytes(sorted(keys))),
        'retained_case_identities_unique_and_disjoint': names_unique,
        'independent_store_ui_proofs': carry, 'actual_import_closure': imports,
        'scope': 'All production and other captured inputs are identical to 604. Only the two reviewed test fixtures may differ. Every original case from those files is discarded; no old success or failure from either file contributes to retention.'}


def commands(static):
    dart = str(Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/dart-sdk/bin/dart')
    flutter = str(Path(os.environ['FLUTTER_ROOT']) / 'bin/flutter')
    return [
        {'name': 'analysis', 'cwd': '.', 'kind': 'static', 'command': [dart, 'analyze', '--fatal-infos', *static]},
        {'name': 'format', 'cwd': '.', 'kind': 'static', 'command': [dart, 'format', '--output=none', '--set-exit-if-changed', *static]},
        {'name': 'studio_mail_corrected_fixtures', 'cwd': str(q.STUDIO), 'kind': 'tests',
            'expected_suites': AFFECTED, 'command': [flutter, 'test', '--no-pub', '--concurrency=2',
                '--reporter=json', *[str(Path(path).relative_to(q.STUDIO)) for path in AFFECTED]]},
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--plan', action='store_true')
    mode.add_argument('--run', action='store_true')
    parser.add_argument('--expected-head')
    parser.add_argument('--run-id', default='selective-fixture-recovery')
    args = parser.parse_args()
    if 'FLUTTER_ROOT' not in os.environ or 'PUB_CACHE' not in os.environ:
        parser.error('Source runtime/env.sh before planning or running')
    os.environ.update(BOT='true', CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true')
    if args.run and (not args.expected_head or q.current_head() != args.expected_head):
        parser.error('--run requires --expected-head equal to the exact current Git HEAD')
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', args.run_id):
        parser.error('Use a simple unique run ID')
    expected = args.expected_head if args.run else q.current_head()
    script_hash = sha(Path(__file__).read_bytes())
    base = baseline()
    before = q.capture_inputs(expected)
    runtime = q.runtime_info()
    continuity = proof(base, before, runtime)
    static = q.changed_dart_paths()
    selected = commands(static)
    planned = {'baseline_source': BASELINE_SOURCE, 'observed_head': q.current_head(),
        'source_freeze_required_before_execution': True,
        'test_processes_started_by_planning': False, 'changed_dart_paths': static,
        'static_path_count': len(static), 'captured_source_input_count': len(before['entries']),
        'fresh_suite_selection': AFFECTED, 'fresh_expected_case_count': 60,
        'fresh_required_case_identities': sorted(identity(case) for case in base['discarded_cases']),
        'fresh_required_former_failures': sorted(EXPECTED_FAILURES),
        'retained_case_count': continuity['retained_case_count'],
        'retained_suite_count': continuity['retained_suite_count'],
        'expected_combined_case_count_if_accepted': 7317,
        'commands': selected, 'helper_sha256': HELPER_SHA256, 'selective_script_sha256': script_hash,
        'scope': 'Static analysis/format for every changed Dart path, then both complete fixture suites. All 60 original case identities must be present exactly once and pass; the four prior failures must be among those successes. No CI or unrelated suite rerun.'}
    if args.plan:
        q.write_json(HERE / 'selective-recovery-plan.json', planned)
        q.write_json(HERE / 'selective-preflight.json', continuity)
        q.save_manifest(HERE, 'selective-preflight-inputs.json', before)
        print(json.dumps({'eligible_for_selective_run': continuity['eligible_for_selective_run'],
            'static_paths': len(static), 'inputs': len(before['entries']), 'fresh_suites': 2,
            'fresh_expected_cases': 60, 'retained_cases': continuity['retained_case_count'],
            'retained_suites': continuity['retained_suite_count'],
            'local_import_files': continuity['actual_import_closure']['local_dart_file_count'],
            'forbidden_imports': continuity['actual_import_closure']['forbidden_fixture_references'],
            'unresolved_imports': continuity['actual_import_closure']['unresolved_directives'],
            'uncaptured_imports': continuity['actual_import_closure']['uncaptured_or_mismatched_files'],
            'changed_inputs': continuity['changed_source_inputs']}, indent=2))
        return 0 if continuity['eligible_for_selective_run'] else 1
    directory = HERE / args.run_id
    directory.mkdir()
    q.write_json(directory / 'plan.json', planned)
    q.write_json(directory / 'retained-evidence.json', continuity)
    q.write_json(directory / 'runtime.json', runtime)
    manifests = [q.save_manifest(directory, 'inputs-before.json', before)]
    mismatches = [path for path, row in before['entries'].items() if not row['matches_expected_head']]
    if not continuity['eligible_for_selective_run'] or mismatches:
        q.write_json(directory / 'summary.json', {'accepted': False, 'gates_executed': [],
            'reason': 'Selective continuity or frozen-source identity failed before execution.',
            'inputs_not_matching_source_commit': mismatches})
        return 1
    results, checks = [], []
    for gate in selected:
        record = q.execute_gate(gate, directory, os.environ.copy())
        results.append(record)
        after = q.capture_inputs(expected)
        drift = q.source_drift(before, after)
        checks.append({'after_gate': gate['name'], **drift})
        manifests.append(q.save_manifest(directory, 'inputs-after-' + gate['name'] + '.json', after))
        q.write_json(directory / 'progress.json', {'completed_gates': [row['name'] for row in results], 'source_checks': checks})
        if record['interrupted'] or not drift['stable']:
            break
    test = next((row for row in results if row['kind'] == 'tests'), None)
    fresh = test['reporter'] if test else None
    expected_cases = {identity(case) for case in base['discarded_cases']}
    observed_cases = {identity(case) for case in fresh['cases']} if fresh else set()
    all_names_match = expected_cases == observed_cases and fresh is not None and fresh['case_attempts'] == 60
    failures_recovered = fresh is not None and all(any(identity(case) == wanted
        and case['result'] == 'success' and not case['skipped'] for case in fresh['cases'])
        for wanted in EXPECTED_FAILURES)
    baseline_unchanged = verify_index(base['directory']) == base['hashes']
    final_runtime = q.runtime_info()
    runtime_unchanged = runtime['version'] == final_runtime['version'] and runtime['executables_sha256'] == final_runtime['executables_sha256']
    accepted = (len(results) == 3 and all(row['exit_code'] == 0 for row in results)
        and fresh is not None and q.complete_reporter(fresh) and all_names_match and failures_recovered
        and all(row['stable'] for row in checks) and not mismatches
        and baseline_unchanged and runtime_unchanged and sha(HELPER.read_bytes()) == HELPER_SHA256
        and sha(Path(__file__).read_bytes()) == script_hash)
    summary = {'accepted': accepted, 'expected_source_head': expected, 'finished_head': q.current_head(),
        'baseline_source': BASELINE_SOURCE, 'baseline_run_preserved_accepted_false': True,
        'baseline_artifacts_unchanged_after_execution': baseline_unchanged,
        'captured_source_input_count': len(before['entries']), 'input_manifests': manifests,
        'source_checks': checks, 'inputs_not_matching_source_commit': mismatches,
        'static_path_count': len(static), 'all_planned_gates_completed': len(results) == 3,
        'all_commands_exit_zero': all(row['exit_code'] == 0 for row in results),
        'fresh_reporter_complete': q.complete_reporter(fresh) if fresh else False,
        'fresh_case_identity_set_matches_all_60_original_names': all_names_match,
        'all_four_former_failures_passed': failures_recovered,
        'missing_original_case_identities': sorted(expected_cases - observed_cases),
        'unexpected_case_identities': sorted(observed_cases - expected_cases),
        'fresh_unique_passed_cases': fresh['passed_cases'] if fresh else 0,
        'fresh_unique_failed_cases': fresh['failed_cases'] if fresh else 0,
        'fresh_unique_skipped_cases': fresh['skipped_cases'] if fresh else 0,
        'fresh_unique_incomplete_cases': fresh['incomplete_cases'] if fresh else 0,
        'fresh_suite_count': fresh['suite_count'] if fresh else 0,
        'retained_accepted_cases': continuity['retained_case_count'],
        'retained_suite_count': continuity['retained_suite_count'],
        'discarded_original_file_cases': 60,
        'combined_accepted_case_count': continuity['retained_case_count'] + fresh['passed_cases'] if accepted else None,
        'runtime_identity_unchanged': runtime_unchanged, 'helper_sha256': HELPER_SHA256,
        'selective_script_sha256_before': script_hash, 'selective_script_sha256_after': sha(Path(__file__).read_bytes()),
        'gate_summaries': [{key: row[key] for key in ('name', 'exit_code', 'started_at_utc', 'finished_at_utc')} for row in results],
        'scope': 'Pinned local VM/widget acceptance only, by exact unchanged-input retention and one fresh complete execution of both corrected fixtures. No old case from either fixture is counted; no CI, live-provider, installed-platform, JavaScript/browser or full product-parity claim.'}
    q.write_json(directory / 'summary.json', summary)
    (directory / 'SHA256SUMS.txt').write_text(''.join(
        f'{sha(path.read_bytes())}  {path.name}\n' for path in sorted(directory.iterdir())
        if path.is_file() and path.name != 'SHA256SUMS.txt'))
    print(json.dumps({key: summary[key] for key in ('accepted', 'fresh_unique_passed_cases',
        'fresh_unique_failed_cases', 'retained_accepted_cases', 'combined_accepted_case_count')}, indent=2))
    return 0 if accepted else 1


if __name__ == '__main__':
    raise SystemExit(main())
