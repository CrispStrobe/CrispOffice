#!/usr/bin/env python3
"""Recount final outer Python controls and add the Store launcher cohort once."""
import argparse
import ast
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, required=True)
    p.add_argument('--outer', type=Path, required=True)
    p.add_argument('--source', required=True)
    p.add_argument('--store-audit', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    issues = []
    def check(value, message):
        if not value:
            issues.append(message)
    def frozen(path):
        return subprocess.check_output(['git', '--no-replace-objects', 'show', a.source + ':' + path], cwd=a.repo)
    outer_raw = (a.outer / 'execution.json').read_bytes()
    outer = json.loads(outer_raw)
    store_raw = a.store_audit.read_bytes()
    store = json.loads(store_raw)
    check(outer['status'] == 'PASS' and outer['source_commit'] == a.source and bool(outer.get('finished_at_utc')), 'complete source-bound outer execution')
    check(store['passed'] is True and store['source_commit'] == a.source, 'complete source-bound Store audit')
    check(store['outer_execution_receipt_sha256'] == sha(outer_raw), 'Store audit binds this exact outer envelope')
    names = ['shared-runner-controls', 'runtime-controls', 'bundle-controls', 'core-store', 'native', 'node']
    check([r['name'] for r in outer['runs']] == names, 'exact outer gate inventory/order')
    before = json.loads((a.outer / 'source-before.json').read_bytes())
    after = json.loads((a.outer / 'source-after.json').read_bytes())
    runtime_before = json.loads((a.outer / 'runtime-before.json').read_bytes())
    runtime_after = json.loads((a.outer / 'runtime-after.json').read_bytes())
    check(before == after and runtime_before == runtime_after, 'outer source/runtime stability')
    check(sha(Path(outer['python_executable']).read_bytes()) == runtime_before['python/executable'], 'actual before/after-bound Python executable')
    definitions = [
        ('shared-runner-controls', ['docs/validation/document-review-notes-20261118/test_run_checks.py']),
        ('runtime-controls', ['docs/validation/document-review-notes-20261118/runtime/test_restore_runtime.py']),
        ('bundle-controls', ['tools/proofing/ayaspell/test_build_bundle.py', 'tools/proofing/ayaspell/test_build_bundle_incoming.py']),
    ]
    control_sources = {path for name, paths in definitions for path in paths}
    control_sources.update(['docs/validation/document-review-notes-20261118/run_checks.py', 'docs/validation/document-review-notes-20261118/runtime/restore_runtime.py', 'tools/proofing/ayaspell/build_bundle.py', 'tools/mail/check_store.py', 'tools/mail/check_reader.py', 'tools/mail/test_check_store.py'])
    for path in control_sources:
        check(path in before and sha(frozen(path)) == before.get(path) == sha((a.repo / path).read_bytes()), 'frozen/current control source: ' + path)
    reports, normalized_ids = [], []
    for name, paths in definitions:
        run = next(r for r in outer['runs'] if r['name'] == name)
        check(run['exit_code'] == 0 and run['accepted'] is True, name + ': successful original process')
        check(Path(run['command'][0]).resolve() == Path(outer['python_executable']), name + ': bound Python interpreter')
        if len(paths) == 1:
            check(run['command'][1:] == [str(a.repo / paths[0])], name + ': exact direct test-file command')
        else:
            check(run['command'][1:] == ['-B', '-m', 'unittest', 'discover', '-s', 'tools/proofing/ayaspell', '-p', 'test_build_bundle*.py', '-v'], name + ': exact bundled discovery command')
        raw = (a.outer / run['log']).read_bytes()
        check(sha(raw) == run['log_sha256'], name + ': original raw log binding')
        supplemental = None
        if name == 'shared-runner-controls' and not re.search(rb'^test\S+ \(', raw, re.MULTILINE):
            original_raw = raw
            compact_terminal = re.findall(rb'Ran (\d+) tests? in [^\n]+\n\s*\nOK\s*$', original_raw)
            first_line = original_raw.splitlines()[0]
            check(len(compact_terminal) == 1 and first_line == b'.' * int(compact_terminal[0]), name + ': preserve successful compact original count')
            supplemental_root = a.outer / 'shared-runner-controls-verbose'
            supplemental_raw = (supplemental_root / 'receipt.json').read_bytes()
            supplemental = json.loads(supplemental_raw)
            check(supplemental['status'] == 'PASS' and supplemental['exit_code'] == 0 and supplemental['source_commit'] == a.source and supplemental['source_tree'] == outer['source_tree'], name + ': accepted same-source supplemental execution')
            check(supplemental['command'] == [outer['python_executable'], '-B', str(a.repo / paths[0]), '-v'], name + ': exact supplemental command')
            check(supplemental['original_outer_execution_sha256'] == sha(outer_raw) and supplemental['original_compact_log_sha256'] == sha(original_raw), name + ': supplement binds unaltered original evidence')
            for scope, expected in [('source', before), ('runtime', runtime_before)]:
                for phase in ['before', 'after']:
                    filename = scope + '-' + phase + '.json'
                    manifest_raw = (supplemental_root / filename).read_bytes()
                    check(sha(manifest_raw) == supplemental['manifest_sha256'][filename] and json.loads(manifest_raw) == expected, name + ': exact supplemental ' + filename + ' matches original envelope')
            for field in ['source_unchanged', 'runtime_unchanged', 'head_unchanged', 'tracked_worktree_clean_before', 'tracked_worktree_clean_after']:
                check(supplemental[field] is True, name + ': supplemental stability: ' + field)
            raw = (supplemental_root / supplemental['raw_log']).read_bytes()
            check(sha(raw) == supplemental['raw_log_sha256'], name + ': supplemental verbose log binding')
            check(supplemental['original_compact_run_added_to_final_control_count'] == 0, name + ': compact repetition is not added to accepted controls')
            supplemental = {'receipt': 'shared-runner-controls-verbose/receipt.json', 'receipt_sha256': sha(supplemental_raw), 'original_compact_log_sha256': sha(original_raw), 'original_compact_run_status': 'successful; retained unchanged', 'original_compact_run_added_to_total': 0, 'accepted_case_identity_source': 'supplemental same-source verbose rerun', 'source_and_runtime_match_original_envelope': True}
        rows = re.findall(r'^(test\S+) \(([^)]+)\) \.\.\. (ok|FAIL|ERROR|skipped[^\n]*)$', raw.decode(), re.MULTILINE)
        terminal = re.findall(rb'Ran (\d+) tests? in [^\n]+\n\s*\nOK\s*$', raw)
        check(len(terminal) == 1 and int(terminal[0]) == len(rows), name + ': exact successful raw terminal count')
        check(len(rows) == len({owner for method, owner, result in rows}) and all(result == 'ok' for method, owner, result in rows), name + ': distinct successful raw cases')
        expected, identities = {}, []
        for path in paths:
            module = '__main__' if len(paths) == 1 else Path(path).stem
            syntax = ast.parse(frozen(path))
            for cls in syntax.body:
                if isinstance(cls, ast.ClassDef):
                    for method in cls.body:
                        if isinstance(method, (ast.FunctionDef, ast.AsyncFunctionDef)) and method.name.startswith('test'):
                            expected[module + '.' + cls.name + '.' + method.name] = path + '::' + cls.name + '.' + method.name
        check({owner for method, owner, result in rows} == set(expected), name + ': exact frozen AST case inventory')
        for method, owner, result in rows:
            check(owner.endswith('.' + method), name + ': raw method/owner agreement')
            if owner in expected:
                identities.append(expected[owner])
        normalized_ids.extend(identities)
        reports.append({'name': name, 'passed_cases': len(rows), 'raw_log_sha256': sha(raw), 'raw_case_ids': [owner for method, owner, result in rows], 'case_identities': identities, 'frozen_sources': paths, 'supplemental_case_identity_evidence': supplemental})
    controls = store['separate_python_controls']
    store_ids = ['tools/mail/test_check_store.py::' + ident.split('.', 1)[1] for ident in controls['case_ids']]
    normalized_ids.extend(store_ids)
    reports.insert(0, {'name': 'store-launcher-controls', 'passed_cases': controls['cases'], 'raw_log_sha256': controls['raw_log_sha256'], 'raw_case_ids': controls['case_ids'], 'case_identities': store_ids, 'frozen_sources': ['tools/mail/test_check_store.py']})
    check(len(normalized_ids) == len(set(normalized_ids)), 'no repeated Python source/test identities')
    result = {'audited_at_utc': datetime.now(timezone.utc).isoformat(), 'source_commit': a.source, 'method': 'Independent verbose-log/AST recount for final runner, runtime and bundle controls; add independently recounted Store launcher controls exactly once. No tests executed or historical runs included.', 'audit_script_sha256': sha(Path(__file__).read_bytes()), 'outer_execution_sha256': sha(outer_raw), 'store_audit_sha256': sha(store_raw), 'source_inputs_reverified': len(control_sources), 'python_executable_sha256': runtime_before['python/executable'], 'groups': reports, 'passed_python_controls': sum(r['passed_cases'] for r in reports), 'distinct_case_identities': len(set(normalized_ids)), 'historical_python_controls_added': 0, 'issues': issues, 'passed': not issues}
    a.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['source_commit', 'passed_python_controls', 'distinct_case_identities', 'passed', 'issues']}, indent=2))
    return bool(issues)


if __name__ == '__main__':
    raise SystemExit(main())
