#!/usr/bin/env python3
"""Independently recount raw reporter evidence for the frozen Zotero gate.

No import of the qualification runner, no test execution, and no GitHub/CI
requests. Inputs come from the saved commit, reporter logs and source snapshots.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlparse


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def resolve_suite(name, cwd):
    parsed = urlparse(name)
    if parsed.scheme == 'file':
        require(parsed.netloc in ('', 'localhost'), 'Non-local reporter suite')
        name = unquote(parsed.path)
    path = Path(name)
    return str((path if path.is_absolute() else cwd / path).resolve())


def recount(data, cwd, expected):
    """Use a strict independent event state machine; retain failures as data."""
    phase = 'not_started'
    suite_ids, suite_names, starts, completions = {}, set(), {}, set()
    cases, errors, excluded, anomalies = [], [], [], []
    terminal = None
    for number, raw in enumerate(data.decode('utf-8').splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if '{' in line:
            line = line[line.index('{'):]
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            require(not line.startswith(('{', '[')), f'Malformed event at line {number}')
            continue
        require(isinstance(event, dict), f'Non-object event at line {number}')
        kind = event.get('type')
        require(isinstance(kind, str), f'Missing event type at line {number}')
        require(phase != 'finished', f'Event after terminal at line {number}')
        if kind == 'start':
            require(phase == 'not_started', f'Duplicate start at line {number}')
            phase = 'running'
            continue
        require(phase == 'running', f'Event before start at line {number}')
        if kind == 'suite':
            item = event['suite']
            ident, name = item['id'], resolve_suite(item['path'], cwd)
            require(type(ident) is int and ident not in suite_ids, 'Duplicate/invalid suite id')
            require(name not in suite_names, 'Repeated source suite')
            suite_ids[ident] = name
            suite_names.add(name)
        elif kind == 'testStart':
            item = event['test']
            ident = item['id']
            require(type(ident) is int and ident not in starts, 'Duplicate/invalid case id')
            require(type(item['suiteID']) is int and isinstance(item['name'], str), 'Invalid case identity')
            require(item['suiteID'] in suite_ids, 'Case started before its suite')
            starts[ident] = item
        elif kind == 'testDone':
            ident = event['testID']
            require(type(ident) is int and ident in starts, 'Orphan test completion')
            require(ident not in completions, 'Duplicate test completion')
            completions.add(ident)
            for field in ('hidden', 'skipped'):
                require(type(event[field]) is bool, 'Invalid boolean completion metadata')
            require(event['result'] in ('success', 'failure', 'error'), 'Invalid completion result')
            case = starts[ident]
            is_fixture = (case['name'].startswith('loading ')
                          or re.search(r'(?:^|\s)\((?:setUpAll|tearDownAll)\)$', case['name']))
            row = {'id': ident, 'suite': suite_ids[case['suiteID']], 'name': case['name'],
                   'result': event['result'], 'skipped': event['skipped']}
            if event['hidden'] or is_fixture:
                excluded.append(row)
                if event['result'] != 'success' or event['skipped']:
                    anomalies.append({'line': number, 'hidden_case_failed_or_skipped': ident})
            else:
                cases.append(row)
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            require(type(event['success']) is bool, 'Invalid terminal boolean')
            terminal = event['success']
            phase = 'finished'
        else:
            require(kind in ('group', 'allSuites', 'print', 'debug'), 'Unknown reporter event: ' + kind)
    require(phase == 'finished', 'Reporter lacks a terminal event')
    require(set(starts) == completions, 'Unfinished reporter cases/loaders')
    require(suite_names == expected, 'Requested/observed suite mismatch: ' + repr({
        'missing': sorted(expected - suite_names), 'unexpected': sorted(suite_names - expected)}))
    per_suite = {}
    for case in cases:
        row = per_suite.setdefault(case['suite'], {'passed': 0, 'failed': 0, 'skipped': 0})
        if case['skipped']:
            row['skipped'] += 1
        elif case['result'] == 'success':
            row['passed'] += 1
        else:
            row['failed'] += 1
    require(set(per_suite) == expected, 'Empty requested suite')
    totals = {key: sum(row[key] for row in per_suite.values()) for key in ('passed', 'failed', 'skipped')}
    return {
        **totals, 'errors': len(errors), 'done_success': terminal,
        'per_suite': per_suite, 'suite_paths': sorted(suite_names),
        'cases': cases, 'error_events': errors, 'excluded_count': len(excluded),
        'anomalies': anomalies,
        'valid': terminal and totals['passed'] > 0 and not errors and not anomalies
                 and totals['failed'] == 0 and totals['skipped'] == 0,
    }


def audit(args):
    repo, output = args.repo.resolve(), args.output.resolve()
    summary_data = (output / 'summary.json').read_bytes()
    summary = json.loads(summary_data)
    def git(*words):
        return subprocess.check_output(['git', '-C', str(repo), *words]).decode().strip()
    def committed_file(name):
        return subprocess.check_output(['git', '-C', str(repo), 'show', args.commit + ':' + name])
    def artifact(name):
        path = (output / name).resolve()
        require(output in path.parents, 'Artifact escapes result directory')
        return path.read_bytes()

    require(summary['commit'] == args.commit, 'Wrong qualification commit')
    require(git('rev-parse', args.commit + '^{tree}') == args.tree, 'Wrong qualification tree')
    plan_name = summary['plan']
    plan_bytes = committed_file(plan_name)
    plan = json.loads(plan_bytes)
    require(len(plan['analysis_targets']) == len(set(plan['analysis_targets'])), 'Duplicate analysis targets')
    require(sha(plan_bytes) == summary['plan_sha256'], 'Plan hash differs from committed plan')
    runner_name = str(Path(plan_name).with_name('run_local.py'))
    require(sha(committed_file(runner_name)) == summary['runner_sha256'], 'Runner hash differs from committed runner')
    selected = [str(Path(group['package']) / name)
                for group in plan['test_gates'].values() for name in group['tests']]
    require(len(selected) == len(set(selected)) == 98, 'Plan does not select 98 distinct files')
    require(summary['distinct_test_files'] == 98 and summary['requested_test_files'] == selected,
            'Summary selection differs from committed plan')
    records, observed_all, application_cases = {}, set(), 0
    gate_failures = []
    python_cases, completed_count = 0, 0
    application_failures = application_skips = application_errors = 0
    expected_gates = set(plan['test_gates']) | set(plan['support_tests']) | {'analysis', 'format', 'whitespace'}
    require(set(summary['gates']) <= expected_gates, 'Unexpected gate in results')
    for name, gate in summary['gates'].items():
        if gate['status'] != 'completed':
            require(args.partial, 'Gate is unfinished: ' + name)
            continue
        completed_count += 1
        if gate['exit_code'] != 0 or not gate['accepted']:
            gate_failures.append({'name': name, 'exit_code': gate['exit_code']})
        if name in plan['test_gates']:
            compressed = artifact(gate['compressed_log'])
            require(sha(compressed) == gate['compressed_log_sha256'], name + ' compressed-log hash mismatch')
            raw = gzip.decompress(compressed)
            group = plan['test_gates'][name]
            cwd = repo / group['package']
            expected = {str((cwd / source).resolve()) for source in group['tests']}
            parsed = recount(raw, cwd, expected)
            for field in ('passed', 'failed', 'skipped', 'errors', 'done_success', 'per_suite', 'valid'):
                require(parsed[field] == gate[field], name + ' recount mismatch: ' + field)
            for field in ('cases', 'error_events'):
                detail = artifact(gate[field + '_file'])
                require(sha(detail) == gate[field + '_sha256'], name + ' detail hash mismatch: ' + field)
                require(json.loads(detail) == parsed[field], name + ' detail contents mismatch: ' + field)
            require(not observed_all.intersection(expected), 'Repeated suite across gates')
            observed_all.update(expected)
            application_cases += parsed['passed']
            application_failures += parsed['failed']
            application_skips += parsed['skipped']
            application_errors += parsed['errors']
            records[name] = {key: parsed[key] for key in ('passed', 'failed', 'skipped', 'errors',
                                                         'per_suite', 'excluded_count')}
            records[name]['failed_or_skipped_cases'] = [
                row for row in parsed['cases'] if row['result'] != 'success' or row['skipped']]
            records[name]['compressed_log_sha256'] = sha(compressed)
            records[name]['cases_sha256'] = gate['cases_sha256']
            records[name]['error_events_sha256'] = gate['error_events_sha256']
        else:
            raw = artifact(gate['log'])
            if name in plan['support_tests']:
                lines = raw.decode().splitlines()
                numbers = [int(match[1]) for line in lines
                           if (match := re.fullmatch(r'Ran (\d+) tests? in .+', line))]
                verbose_passes = sum(bool(re.match(r'^test_.* \.\.\. ok$', line)) for line in lines)
                require(len(numbers) == 1 and numbers[0] > 0, name + ' lacks one positive unittest count')
                require([line for line in lines if line.strip()][-1] == 'OK', name + ' not fully passing')
                require(verbose_passes == numbers[0] == gate['python_passed'], name + ' Python count mismatch')
                python_cases += numbers[0]
                records[name] = {'python_passed': numbers[0], 'application_cases': 0}
            else:
                records[name] = {'exit_code': gate['exit_code']}
        require(sha(raw) == gate['log_sha256'], name + ' raw-log hash mismatch')
        records[name]['raw_log_sha256'] = sha(raw)
    complete = summary.get('success') is not None
    report = {
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'checked_commit': args.commit, 'checked_tree': args.tree,
        'summary_sha256': sha(summary_data), 'plan_sha256': sha(plan_bytes),
        'runner_sha256': summary['runner_sha256'], 'complete': complete,
        'completed_gates': completed_count, 'expected_gates': len(expected_gates),
        'planned_distinct_dart_files': len(selected), 'observed_distinct_dart_files': len(observed_all),
        'analysis_and_format_target_count': len(plan['analysis_targets']),
        'independent_dart_passed': application_cases, 'independent_python_passed': python_cases,
        'independent_dart_failed': application_failures, 'independent_dart_skipped': application_skips,
        'independent_dart_errors': application_errors,
        'gates': records, 'gate_failures': gate_failures,
        'github_actions_queried_or_awaited': False,
    }
    if not complete:
        require(args.partial, 'Final qualification is still running')
        report['accepted'] = False
        return report
    require(set(summary['gates']) == expected_gates and completed_count == len(expected_gates), 'Missing completed gate')
    require(observed_all == {str((repo / source).resolve()) for source in selected}, 'Not exactly 98 observed files')
    require(application_cases == summary['passed'], 'Aggregate application count mismatch')
    require(python_cases == summary['python_passed'], 'Aggregate Python support count mismatch')
    snapshots = {}
    for label in ('source-before', 'source-after'):
        compressed = artifact(label + '.json.gz')
        require(sha(compressed) == summary[label + '_compressed_sha256'], label + ' compressed hash mismatch')
        raw = gzip.decompress(compressed)
        require(sha(raw) == summary[label + '_sha256'], label + ' raw hash mismatch')
        snapshots[label] = json.loads(raw)
    before, after = snapshots['source-before'], snapshots['source-after']
    require(before == after and summary['source_unchanged'], 'Source/runtime/dependency fingerprints changed')
    require(before['commit'] == args.commit and before['tree'] == args.tree, 'Snapshot has wrong source identity')
    require(before['plan_sha256'] == sha(plan_bytes), 'Snapshot plan hash mismatch')
    require(before['runner_sha256'] == summary['runner_sha256'], 'Snapshot runner hash mismatch')
    exceptions = plan.get('whitespace_exceptions', [])
    if exceptions:
        require(before.get('whitespace_exceptions') == exceptions
                and summary.get('whitespace_exceptions') == exceptions,
                'Pinned whitespace mapping differs between plan/snapshots/summary')
        paths = [row['path'] for row in exceptions]
        require(len(paths) == len(set(paths)) == 6, 'Expected exactly six distinct verbatim exceptions')
        exception_proofs = []
        for row in exceptions:
            incoming_blob = git('rev-parse', '8fa115e8358e305872fd14e757f9133fa9c1540d:' + row['path'])
            qualified_blob = git('rev-parse', args.commit + ':' + row['path'])
            current_blob = git('rev-parse', 'HEAD:' + row['path'])
            require(incoming_blob == qualified_blob == current_blob == row['git_blob'],
                    'Excepted source blob differs from incoming integration, frozen commit or current HEAD')
            exception_proofs.append({'path': row['path'], 'incoming_blob': incoming_blob,
                                     'qualified_blob': qualified_blob, 'current_blob': current_blob,
                                     'pinned_blob': row['git_blob'], 'verified': True})
        report['verbatim_whitespace_exception_proofs'] = exception_proofs
        require(plan['baseline'] == 'aad56eb498aa4839ad5bb11fd35d9f734d2ca397',
                'Original product whitespace baseline changed')
        require(summary['gates']['whitespace']['command'] ==
                ['git', 'diff', '--check', plan['baseline'], 'HEAD', '--', '.'] +
                [':(exclude,literal)' + path for path in paths],
                'Whitespace command differs from six literal pinned exclusions')
        report['original_baseline_whitespace_coverage_retained_outside_six_pinned_blobs'] = True
    tracked = set(git('ls-files').splitlines())
    required_inputs = {name for name in tracked if
                       (name.startswith(('packages/', 'apps/', 'third_party/')) and
                        name.endswith(('.dart', '.yaml', '.lock'))) or
                       name in ('.fvmrc', 'pubspec.yaml', 'analysis_options.yaml')}
    required_inputs.update(selected)
    required_inputs.update(plan['analysis_targets'])
    required_inputs.update(plan['support_tests'].values())
    required_inputs.update(plan.get('fingerprint_inputs', []))
    required_inputs.update((plan_name, runner_name))
    require(set(before['files']) == required_inputs, 'Snapshot source coverage differs from committed plan')
    for name, expected in before['files'].items():
        require(sha((repo / name).read_bytes()) == expected, 'Current source fingerprint mismatch: ' + name)
    bindings = {
        'lock_sha256': repo / 'pubspec.lock',
        'package_config_sha256': repo / '.dart_tool/package_config.json',
    }
    dart = Path(summary['gates']['analysis']['command'][0])
    runtime = dart.parents[4]
    bindings.update({
        'dart_sha256': dart,
        'flutter_tools_sha256': runtime / 'bin/cache/flutter_tools.snapshot',
        'flutter_tester_sha256': runtime / 'bin/cache/artifacts/engine/linux-x64/flutter_tester',
        'python_sha256': Path(summary['gates']['runner-accounting']['command'][0]).resolve(),
    })
    for key, path in bindings.items():
        require(sha(path.read_bytes()) == before[key], 'Current environment fingerprint mismatch: ' + key)
    for name, expected in before['environment_inputs'].items():
        require(sha(Path(name).read_bytes()) == expected, 'Current receipt/input changed: ' + name)
    require(git('rev-parse', 'HEAD') == args.commit, 'Current HEAD differs from frozen qualification')
    require(git('rev-parse', 'HEAD^{tree}') == args.tree, 'Current tree differs from frozen qualification')
    require(not git('status', '--porcelain', '--untracked-files=no'), 'Tracked worktree/index is dirty')
    require(not [name for name in git('ls-files', '--others', '--exclude-standard').splitlines()
                 if name.startswith(('packages/', 'apps/', 'third_party/'))], 'Untracked product inputs present')
    require(summary['source_head_unchanged'] and summary['tracked_worktree_clean_after']
            and not summary['untracked_product_inputs_after'], 'Source cleanliness claims differ')
    report.update(accepted=summary['success'] and not gate_failures,
                  independent_evidence_checks_succeeded=True,
                  source_input_count=len(before['files']),
                  environment_receipt_count=len(before['environment_inputs']),
                  source_runtime_dependency_fingerprints_identical=True,
                  source_inputs_verified_against_current_checkout=True,
                  current_tracked_source_clean=True,
                  raw_compressed_detail_hashes_verified=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--tree', required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--partial', action='store_true')
    args = parser.parse_args()
    try:
        result = audit(args)
    except Exception as error:
        result = {'accepted': False, 'error': type(error).__name__ + ': ' + str(error)}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in result if key != 'gates'}, indent=2))
    return 0 if result.get('accepted') or (args.partial and not result.get('error')) else 1


if __name__ == '__main__':
    sys.exit(main())
