#!/usr/bin/env python3
"""Run independent read-only final gate audits and combine exact execution inventories."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['repo', 'outer', 'runtime', 'output']:
        p.add_argument('--' + name, type=Path, required=True)
    for name in ['source', 'driver', 'native-plan', 'node-plan']:
        p.add_argument('--' + name, required=True)
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=True)
    here = Path(__file__).resolve().parent
    issues, audit_runs, inventory, groups, reports = [], [], [], [], {}
    def invoke(label, argv):
        path = a.output / (label + '-audit.json')
        log = a.output / (label + '-audit.log')
        with log.open('wb') as stream:
            proc = subprocess.run(argv + ['--output', str(path)], stdout=stream, stderr=subprocess.STDOUT)
        if path.is_file():
            result = json.loads(path.read_text())
        else:
            result = {'passed': False, 'issues': ['audit failed without a report']}
        audit_runs.append({'name': label, 'exit_code': proc.returncode, 'command': argv + ['--output', str(path)], 'audit_file': path.name, 'audit_sha256': sha(path) if path.is_file() else None, 'log_sha256': sha(log)})
        if proc.returncode or result.get('passed') is not True:
            issues.append(label + ': independent audit failed')
        reports[label] = result
        return result
    for label, plan_path in [('native', a.native_plan), ('node', a.node_plan)]:
        plan = json.loads(subprocess.check_output(['git', '--no-replace-objects', 'show', a.source + ':' + plan_path], cwd=a.repo))
        targets = [{'path': (Path(g['cwd']) / test).as_posix(), 'platform': g.get('platform', 'vm'), 'gate': label} for g in plan['groups'] for test in g['tests']]
        result = invoke(label, [sys.executable, str(here / 'audit_current_gate.py'), '--repo', str(a.repo), '--gate', str(a.outer / label), '--runtime', str(a.runtime), '--source', a.source, '--plan', plan_path, '--expected-suites', str(len(targets))])
        inventory.extend(targets)
        groups.extend({'gate': label, **g} for g in result.get('groups', []))
    store = invoke('store', [sys.executable, str(here / 'audit_store_current.py'), '--repo', str(a.repo), '--gate', str(a.outer / 'core-store'), '--outer', str(a.outer), '--runtime', str(a.runtime), '--source', a.source, '--driver', a.driver, '--native-plan', a.native_plan, '--node-plan', a.node_plan])
    for g in store.get('groups', []):
        inventory.extend({'path': path, 'platform': g['platform'], 'gate': 'store'} for path in g['suite_paths'])
        groups.append({'gate': 'store', 'name': g['name'], 'suites': g['suites'], 'passed': g['passed'], 'failed': g['failed'], 'skipped': g['skipped']})
    python = invoke('python', [sys.executable, str(here / 'audit_outer_python_controls.py'), '--repo', str(a.repo), '--outer', str(a.outer), '--source', a.source, '--store-audit', str(a.output / 'store-audit.json')])
    duplicates = [{'path': path, 'platform': platform, 'count': count} for (path, platform), count in Counter((x['path'], x['platform']) for x in inventory).items() if count != 1]
    if duplicates:
        issues.append('duplicate application suite/platform executions')
    sources = {r.get('source_commit') for r in reports.values()}
    if sources != {a.source}:
        issues.append('different or absent original execution source identities')
    runtime_ids = {r.get('verified_runtime_recovery', {}).get('receipt_sha256') for label, r in reports.items() if label in {'native', 'node'}}
    runtime_ids.add(store.get('runtime_receipt_sha256'))
    if runtime_ids != {sha(a.runtime / 'runtime.json')}:
        issues.append('inconsistent runtime receipt identities')
    result = {'audited_at_utc': datetime.now(timezone.utc).isoformat(), 'source_commit': a.source, 'source_tree': subprocess.check_output(['git', '--no-replace-objects', 'rev-parse', a.source + '^{tree}'], cwd=a.repo, text=True).strip(), 'method': 'Independent raw reporter and Python AST/log recounts, full immutable/current source and runtime inventories, exact scope/command checks. Every cohort uses the same final source. No tests executed by this audit.', 'audit_script_sha256': sha(__file__), 'helper_sha256': {name: sha(here / name) for name in ['audit_current_gate.py', 'audit_store_current.py', 'audit_outer_python_controls.py']}, 'runs': audit_runs, 'groups': groups, 'application_case_executions': sum(g['passed'] for g in groups), 'suite_platform_executions': len(inventory), 'distinct_test_files': len({x['path'] for x in inventory}), 'suite_platform_inventory': inventory, 'duplicate_suite_platform_executions': duplicates, 'failed': sum(g['failed'] for g in groups), 'skipped': sum(g['skipped'] for g in groups), 'separate_python_controls': python.get('passed_python_controls', 0), 'python_groups': python.get('groups', []), 'runtime_receipt_sha256': sha(a.runtime / 'runtime.json'), 'native_source_inputs_reverified': reports['native'].get('source_inputs_reverified'), 'node_source_inputs_reverified': reports['node'].get('source_inputs_reverified'), 'native_runtime_inputs_reverified': reports['native'].get('runtime_inputs_reverified'), 'node_runtime_inputs_reverified': reports['node'].get('runtime_inputs_reverified'), 'outer_source_inputs_reverified': store.get('outer_source_inputs_reverified'), 'outer_runtime_inputs_reverified': store.get('outer_runtime_inputs_reverified'), 'store_source_inputs_reverified': store.get('source_inputs_reverified'), 'store_launcher_inputs_reverified': store.get('launcher_inputs_reverified'), 'historical_application_cases_added': 0, 'development_application_cases_added': 0, 'intermediate_237_application_cases_added': 0, 'intermediate_90_python_controls_added': 0, 'github_actions': 'NOT QUERIED OR AWAITED', 'issues': issues, 'passed': not issues}
    (a.output / 'independent-summary.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ['source_commit', 'application_case_executions', 'suite_platform_executions', 'distinct_test_files', 'separate_python_controls', 'failed', 'skipped', 'passed', 'issues']}, indent=2))
    return bool(issues)


if __name__ == '__main__':
    raise SystemExit(main())
