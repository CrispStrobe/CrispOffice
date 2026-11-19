#!/usr/bin/env python3
"""Independently inspect completed cohorts; never execute application tests."""
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent / 'quds_office_suite'
EVIDENCE = ROOT.parent / 'combined-qualification'
COMMIT = '59f13897fd5aafccc234c58f41370dd786703418'
PLAN_PATH = 'docs/validation/thesaurus-20261118/reconciled/plan.json'
DIAGNOSTIC = re.compile(r'A Render\w+ overflowed|would not hit test on the specified widget|does not receive pointer events')


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    pending = path.with_name(path.name + '.tmp')
    pending.write_text(json.dumps(value, indent=2) + '\n')
    pending.replace(path)


def committed(path):
    return subprocess.check_output(['git', '-C', str(REPO), 'show', COMMIT + ':' + path])


def source_check(records):
    ordinary = {p: v for p, v in records.items() if not p.startswith('__')}
    process = subprocess.Popen(['git', '-C', str(REPO), 'cat-file', '--batch'],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    mismatches = []
    try:
        for path, record in ordinary.items():
            process.stdin.write((COMMIT + ':' + path + '\n').encode())
            process.stdin.flush()
            header = process.stdout.readline().decode().rstrip()
            if header.endswith(' missing'):
                mismatches.append({'path': path, 'reason': 'not_in_frozen_commit'})
                continue
            _, _, size = header.split()
            data = process.stdout.read(int(size))
            assert process.stdout.read(1) == b'\n'
            if len(data) != record['bytes'] or hashlib.sha256(data).hexdigest() != record['sha256']:
                mismatches.append({'path': path, 'reason': 'differs_from_frozen_commit'})
    finally:
        process.stdin.close()
        process.wait()
    return {'source_records': len(ordinary), 'mismatches': mismatches}


def audit_cohort(group, run):
    stdout = EVIDENCE / run['stdout']
    stderr = EVIDENCE / run['stderr']
    expected = {(REPO / group['cwd'] / p).resolve() for p in group['tests']}
    issues, diagnostics, events = [], [], []
    command = [str(ROOT.parent / 'runtime/bin' / group['runner']), 'test']
    if group['runner'] == 'flutter':
        command.append('--no-pub')
    command += ['--concurrency=4', '--reporter=json', *group['tests']]
    if run['command'] != command or run['cwd'] != group['cwd']:
        issues.append('Execution command or working directory differs from frozen plan')
    for channel, path in [('stdout', stdout), ('stderr', stderr)]:
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if DIAGNOSTIC.search(line):
                diagnostics.append({'channel': channel, 'line': number, 'text': line})
            if channel != 'stdout':
                continue
            record = line.strip()
            while True:
                prefix = next((p for p in ('Running build hooks...', 'Running link hooks...') if record.startswith(p)), None)
                if prefix is None:
                    break
                record = record[len(prefix):].lstrip()
            if not record:
                continue
            try:
                event = json.loads(record)
            except json.JSONDecodeError:
                issues.append(f'Line {number}: malformed JSON')
                continue
            if not isinstance(event, dict) or not isinstance(event.get('type'), str):
                issues.append(f'Line {number}: malformed event')
                continue
            events.append((number, event))
    suites, tests, dones, done_counts = {}, {}, {}, Counter()
    starts, terminals, all_suites, error_events = [], [], [], []
    for number, event in events:
        kind = event['type']
        if terminals:
            issues.append(f'Line {number}: event after terminal')
        if kind == 'start':
            starts.append(event)
        elif not starts:
            issues.append(f'Line {number}: event before start')
        if kind == 'suite':
            suite = event.get('suite')
            if not isinstance(suite, dict) or type(suite.get('id')) is not int or not isinstance(suite.get('path'), str):
                issues.append(f'Line {number}: malformed suite')
                continue
            identifier = suite['id']
            if identifier in suites:
                issues.append(f'Line {number}: duplicate suite id')
            suites[identifier] = (REPO / group['cwd'] / suite['path']).resolve()
        elif kind == 'testStart':
            test = event.get('test')
            if not isinstance(test, dict) or type(test.get('id')) is not int or type(test.get('suiteID')) is not int or not isinstance(test.get('name'), str):
                issues.append(f'Line {number}: malformed test start')
                continue
            if test['id'] in tests:
                issues.append(f'Line {number}: duplicate test id')
            tests[test['id']] = test
        elif kind == 'testDone':
            identifier = event.get('testID')
            if type(identifier) is not int:
                issues.append(f'Line {number}: malformed completion id')
                continue
            done_counts[identifier] += 1
            dones[identifier] = event
            if event.get('result') not in ('success', 'failure', 'error') or type(event.get('hidden')) is not bool or type(event.get('skipped')) is not bool:
                issues.append(f'Line {number}: malformed completion')
        elif kind == 'done':
            terminals.append(event)
        elif kind == 'allSuites':
            all_suites.append(event)
        elif kind == 'error':
            error_events.append(event)
    if len(starts) != 1 or len(terminals) != 1 or terminals[0].get('success') is not True:
        issues.append('Expected exactly one start and one successful terminal')
    if len(all_suites) != 1 or all_suites[0].get('count') != len(expected):
        issues.append('Announced suite count differs from plan')
    if set(tests) != set(dones) or any(v != 1 for v in done_counts.values()):
        issues.append('Test start/completion identities are incomplete or repeated')
    if any(t['suiteID'] not in suites for t in tests.values()):
        issues.append('Test refers to an unregistered suite')
    actual = set(suites.values())
    if actual != expected or len(suites) != len(actual):
        issues.append('Registered suites differ from exact requested set')
    cases, excluded, failures, skips = [], [], [], []
    for identifier, event in dones.items():
        test = tests.get(identifier, {})
        suite = suites.get(test.get('suiteID'))
        name = test.get('name', '')
        record = {'suite': str(suite.relative_to(REPO)) if suite and suite.is_relative_to(REPO) else str(suite),
                  'name': name, 'result': event.get('result'), 'skipped': event.get('skipped')}
        if event.get('result') != 'success':
            failures.append(record)
        if event.get('skipped') or test.get('metadata', {}).get('skip'):
            skips.append(record)
        if event.get('hidden') or name.startswith('loading ') or name.endswith(('(setUpAll)', '(tearDownAll)')):
            excluded.append(record)
        else:
            cases.append(record)
    identities = [(c['suite'], c['name']) for c in cases]
    counts = Counter(c['suite'] for c in cases)
    if len(set(identities)) != len(identities):
        issues.append('Duplicate substantive case identity')
    if {str(p.relative_to(REPO)) for p in expected} != set(counts):
        issues.append('A selected suite has no substantive case')
    passed = sum(c['result'] == 'success' and not c['skipped'] for c in cases)
    if passed != run.get('passed'):
        issues.append('Independent pass count differs from runner claim')
    hashes = {}
    for path in (stdout, stderr):
        hashes[path.name] = sha(path)
        declared = run.get('logs', {}).get(path.name, {})
        compressed = EVIDENCE / declared.get('compressed', 'MISSING')
        if hashes[path.name] != declared.get('sha256') or not compressed.is_file() or sha(compressed) != declared.get('compressed_sha256') or gzip.decompress(compressed.read_bytes()) != path.read_bytes():
            issues.append('Raw/compressed log hash binding failed: ' + path.name)
    valid = not any((issues, diagnostics, failures, skips, error_events)) and passed > 0 and run.get('exit_code') == 0
    return {'name': group['name'], 'status': 'passed' if valid else 'failed',
            'source_stability': 'Final before/after source and environment inspection pending until full run completes.',
            'passed': passed, 'suite_count': len(suites), 'per_suite_cases': dict(sorted(counts.items())),
            'test_start_count': len(tests), 'test_completion_count': sum(done_counts.values()),
            'excluded_lifecycle_count': len(excluded), 'failures_including_lifecycle': failures,
            'skips_including_lifecycle': skips, 'error_events': error_events,
            'layout_or_tap_diagnostics': diagnostics, 'issues': issues,
            'stdout_bytes': stdout.stat().st_size, 'stderr_bytes': stderr.stat().st_size,
            'logs_sha256': hashes, 'exit_code': run.get('exit_code'), 'cases': cases}


def audit_non_test(name, paths, run):
    if not run or run.get('status') != 'completed':
        return {'name': name, 'status': 'pending'}
    issues, hashes = [], {}
    expected_prefix = ([str(ROOT.parent / 'runtime/bin/dart'), 'analyze', '--fatal-infos', '--fatal-warnings']
                       if name == 'analysis' else [str(ROOT.parent / 'runtime/bin/dart'), 'format', '--output=none', '--set-exit-if-changed'])
    if run['command'] != expected_prefix + paths:
        issues.append('Command differs from exact committed plan')
    for channel in ('stdout', 'stderr'):
        path = EVIDENCE / run[channel]
        declared = run.get('logs', {}).get(path.name, {})
        compressed = EVIDENCE / declared.get('compressed', 'MISSING')
        hashes[path.name] = sha(path)
        if hashes[path.name] != declared.get('sha256') or not compressed.is_file() or sha(compressed) != declared.get('compressed_sha256') or gzip.decompress(compressed.read_bytes()) != path.read_bytes():
            issues.append('Raw/compressed log binding failed: ' + channel)
    stdout = (EVIDENCE / run['stdout']).read_text()
    stderr = (EVIDENCE / run['stderr']).read_text()
    if name == 'analysis' and 'No issues found!' not in stdout:
        issues.append('Analysis log does not report no issues')
    if name == 'format' and not re.search(r'Formatted \d+ files? \(0 changed\)', stdout):
        issues.append('Format log does not report zero changed files')
    return {'name': name, 'status': 'passed' if run.get('exit_code') == 0 and not issues else 'failed',
            'exit_code': run.get('exit_code'), 'target_count': len(paths),
            'issues': issues, 'logs_sha256': hashes, 'stdout': stdout, 'stderr': stderr}


def main():
    receipt = read(EVIDENCE / 'receipt.json')
    assert receipt['source_commit'] == COMMIT
    plan = json.loads(committed(PLAN_PATH))
    assert plan == receipt['plan']
    initial_path = ROOT / 'initial-binding-audit.json'
    if not initial_path.exists():
        source = source_check(read(EVIDENCE / 'source-before.json'))
        harness = {p: {'recorded': h, 'git_sha256': hashlib.sha256(committed(p)).hexdigest(), 'current_sha256': sha(REPO / p)}
                   for p, h in receipt['harness_sha256'].items()}
        report = {'source_commit': COMMIT, 'source_comparison': source, 'harness_bindings': harness,
                  'source_inventory_sha256': sha(EVIDENCE / 'source-before.json'),
                  'environment_inventory_sha256': sha(EVIDENCE / 'environment-before.json'),
                  'environment_records': len(read(EVIDENCE / 'environment-before.json')),
                  'exact_plan_matches_commit': True, 'expected_suites': sum(len(g['tests']) for g in plan['groups'])}
        assert not source['mismatches']
        assert all(v['recorded'] == v['git_sha256'] == v['current_sha256'] for v in harness.values())
        write(initial_path, report)
    audits = []
    by_name = {r['name']: r for r in receipt['runs']}
    for group in plan['groups']:
        run = by_name.get(group['name'])
        if not run or run.get('status') != 'completed':
            continue
        result = audit_cohort(group, run)
        write(ROOT / (group['name'] + '-audit.json'), result)
        audits.append(result)
    final = receipt.get('status') in ('passed', 'failed', 'interrupted')
    final_bindings = None
    if final:
        source_before = read(EVIDENCE / 'source-before.json')
        environment_before = read(EVIDENCE / 'environment-before.json')
        source_after = read(EVIDENCE / 'source-after.json')
        environment_after = read(EVIDENCE / 'environment-after.json')
        changed_current = [p for p, expected in environment_after.items() if not Path(p).is_file() or sha(p) != expected]
        changed_harness = [p for p, expected in receipt['harness_sha256'].items() if sha(REPO / p) != expected]
        changed_source = [p for p, expected in source_after.items() if not p.startswith('__') and (not (REPO / p).is_file() or sha(REPO / p) != expected['sha256'])]
        package_config_matches = sha(REPO / '.dart_tool/package_config.json') == source_after['__workspace_package_config__']['sha256']
        receipt_file_issues = [p for p, expected in receipt.get('evidence_sha256', {}).items() if not (EVIDENCE / p).is_file() or sha(EVIDENCE / p) != expected]
        final_bindings = {'source_before_equals_after': source_before == source_after,
                          'environment_before_equals_after': environment_before == environment_after,
                          'changed_current_environment_files': changed_current,
                          'changed_current_harness_files': changed_harness,
                          'changed_current_source_files': changed_source,
                          'current_package_config_matches': package_config_matches,
                          'receipt_evidence_hash_mismatches': receipt_file_issues,
                          'source_after_sha256': sha(EVIDENCE / 'source-after.json'),
                          'environment_after_sha256': sha(EVIDENCE / 'environment-after.json')}
        for audit in audits:
            audit['source_stability'] = final_bindings
            write(ROOT / (audit['name'] + '-audit.json'), audit)
    all_cases = [c for a in audits for c in a['cases']]
    identities = {(c['suite'], c['name']) for c in all_cases}
    non_test_audits = [audit_non_test(name, plan[name], by_name.get(name)) for name in ('analysis', 'format') if plan[name]]
    guards = {'run_finished': final,
              'all_planned_cohorts_completed': len(audits) == len(plan['groups']),
              'all_cohort_audits_passed': all(a['status'] == 'passed' for a in audits),
              'no_duplicate_union_case_identities': len(all_cases) == len(identities),
              'strict_checks_passed': all(a['status'] == 'passed' for a in non_test_audits),
              'source_and_environment_stable': bool(final_bindings) and final_bindings['source_before_equals_after'] and final_bindings['environment_before_equals_after'],
              'current_inputs_match': bool(final_bindings) and not any(final_bindings[k] for k in ('changed_current_environment_files', 'changed_current_harness_files', 'changed_current_source_files', 'receipt_evidence_hash_mismatches')) and final_bindings['current_package_config_matches']}
    if final:
        expected_runs = [g['name'] for g in plan['groups']] + [name for name in ('analysis', 'format') if plan[name]]
        guards['exact_completed_run_sequence'] = [r['name'] for r in receipt['runs']] == expected_runs and all(r['status'] == 'completed' for r in receipt['runs'])
        guards['no_reported_runner_error'] = not receipt.get('runner_error') and not receipt.get('final_inspection_error')
    summary = {'recorded_utc': datetime.now(timezone.utc).isoformat(), 'source_commit': COMMIT,
               'independent_status': 'passed' if all(guards.values()) else ('failed' if final else 'pending'),
               'guards': guards,
               'run_finished': final, 'runner_status': receipt['status'],
               'completed_cohorts': [{'name': a['name'], 'status': a['status'], 'passed': a['passed'], 'suites': a['suite_count']} for a in audits],
               'independently_counted_passes': sum(a['passed'] for a in audits if a['status'] == 'passed'),
               'distinct_case_identities': len(identities), 'duplicate_union_identities': len(all_cases) - len(identities),
               'final_bindings': final_bindings,
               'non_test_audits': non_test_audits,
               'scope': 'Independent raw-event and hash audit; no repeated application execution.'}
    write(ROOT / 'union-audit-progress.json', summary)
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
