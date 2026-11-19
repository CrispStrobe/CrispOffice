#!/usr/bin/env python3
"""Audit PR180 source provenance separately from the historical Mail qualification.

Reads immutable Git objects and retained qualification manifests only. This
does not execute product tests or import the repository qualification runner.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

QUALIFIED = '5569c055a021c893e941fc54d40499ad9d96a5db'
BASELINE = '0796cb50155b7bf558fc661dbd6b8d94a553eebd'
INCOMING_PARENT = 'f059065fa622da8cee7824d66d29a2aff414d529'
INCOMING = 'f7117a493055008a72e6e16713dd67a4f7c2ad39'
REPORT = 'docs/validation/office-main-completion-20261119/'
PLAN = REPORT + 'arabic-plan.json'
STORE_README = 'packages/quds_mail_store/README.md'
DOCS = {'docs/PROOFING.md', 'docs/roadmaps/arabic-proofing.md'}
EXISTING = {
    'packages/quds_office_editor/example/lib/suite_workspace.dart',
    'packages/quds_office_editor/lib/src/proofing/word_proofing.dart',
    'packages/quds_office_engine/lib/quds_office_engine.dart',
}
ADDED = {
    'packages/quds_office_editor/test/word_arabic_writing_integration_test.dart',
    'packages/quds_office_engine/lib/src/proofing/arabic_writing_rules.dart',
    'packages/quds_office_engine/test/proofing/arabic_writing_rules_test.dart',
}
EXPECTED = DOCS | EXISTING | ADDED
REPAIRABLE = DOCS | {
    'packages/quds_office_engine/lib/src/proofing/arabic_writing_rules.dart',
    'packages/quds_office_engine/test/proofing/arabic_writing_rules_test.dart',
}
GUARD = 'tools/proofing/ayaspell/build_bundle.py'
GUARD_RECEIPT = REPORT + 'release/proofing-output-guard.json'
GUARD_CHECKER = REPORT + 'release/check_proofing_output_guard.py'


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--target', required=True, help='Frozen application/Arabic-plan commit')
    parser.add_argument('--reviewed-source', help='Exact reviewed repair commit; defaults to target')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()

    def git(*words):
        return subprocess.check_output(['git', '--no-replace-objects', *words], cwd=args.repo)

    def text(*words):
        return git(*words).decode()

    def digest(data):
        return hashlib.sha256(data).hexdigest()

    def tree(commit):
        result = {}
        for row in git('ls-tree', '-r', '-z', commit).decode().split('\0'):
            if row:
                metadata, path = row.split('\t', 1)
                mode, kind, blob = metadata.split(' ')
                result[path] = {'mode': mode, 'kind': kind, 'git_blob': blob}
        return result

    def changed(left, right):
        return {path for path in left.keys() | right.keys() if left.get(path) != right.get(path)}

    target_id = text('rev-parse', args.target + '^{commit}').strip()
    repair_id = text('rev-parse', (args.reviewed_source or args.target) + '^{commit}').strip()
    source, baseline, previous, incoming, target, repair = [tree(commit) for commit in
        [QUALIFIED, BASELINE, INCOMING_PARENT, INCOMING, target_id, repair_id]]
    issues = []
    incoming_delta = changed(previous, incoming)
    target_delta = changed(baseline, target)
    if incoming_delta != EXPECTED:
        issues.append('Incoming main differs from its parent outside the exact eight reviewed paths')
    if not EXPECTED <= target_delta or target_delta - EXPECTED - {PLAN}:
        issues.append('Frozen target differs from baseline outside PR180 and its separate qualification plan')
    if PLAN not in target:
        issues.append('Frozen Arabic qualification plan is missing')
    if any(path not in baseline for path in EXISTING) or any(path in baseline for path in ADDED):
        issues.append('Existing/added Office source classification differs from the reviewed inventory')
    repairs = {path for path in EXPECTED if target.get(path) != incoming.get(path)}
    if repairs - REPAIRABLE:
        issues.append('Unreviewed successor edit outside the four explicitly permitted repair paths')
    if any(target.get(path) != repair.get(path) for path in EXPECTED | {PLAN}):
        issues.append('Target does not match the exact reviewed repair/plan Git entries')
    history = {}
    for commit in [QUALIFIED, BASELINE, INCOMING, repair_id]:
        history[commit] = subprocess.run(['git', '--no-replace-objects', 'merge-base', '--is-ancestor',
                                         commit, target_id], cwd=args.repo).returncode == 0
    if not all(history.values()):
        issues.append('Qualified Mail source, prior baseline, incoming main or reviewed repair ancestry is missing')

    index = json.loads(git('show', BASELINE + ':' + REPORT + 'release/local-qualification.index.json'))
    archive_bytes = git('show', BASELINE + ':' + REPORT + 'release/local-qualification.tar.xz')
    if digest(archive_bytes) != index['archive_sha256']:
        issues.append('Original qualification archive SHA-256 mismatch')
    member_index = {row['path']: row for row in index['members']}
    archive = tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:xz')

    def retained(name):
        data = archive.extractfile(name).read()
        if digest(data) != member_index[name]['sha256'] or len(data) != member_index[name]['bytes']:
            raise RuntimeError('Original evidence member binding failed: ' + name)
        return json.loads(data)

    union, gates = set(), {}
    for label in ['native', 'node']:
        bound = retained('qualification-release-' + label + '/source-before.json')
        for path, row in bound.items():
            if source.get(path) != {'mode': row['mode'], 'kind': 'blob', 'git_blob': row['git_blob']}:
                issues.append('Original ' + label + ' manifest differs from qualified Git source: ' + path)
        differing = sorted(path for path in bound if source.get(path) != target.get(path))
        if set(differing) != EXISTING | {STORE_README}:
            issues.append('Unexpected original ' + label + ' qualified-input changes')
        gates[label] = {'historical_bound_inputs': len(bound),
                        'existing_inputs_identical_to_qualified_source': len(bound) - len(differing),
                        'existing_qualified_input_changes': differing,
                        'new_broad_scope_inputs': sorted(ADDED),
                        'current_scope_count_if_reselected': len(bound) + len(ADDED)}
        union.update(bound)
    for label, member in [('store', 'qualification-release-store/results/receipt.json'),
                          ('support', 'qualification-release-support/receipt.json')]:
        bound = retained(member)['source_before']
        differing = sorted(path for path in bound if source.get(path) != target.get(path))
        if differing:
            issues.append('Previously qualified ' + label + ' input changed')
        gates[label] = {'historical_bound_inputs': len(bound), 'all_inputs_identical': not differing,
                        'changed_paths': differing}
        union.update(bound)
    if len(union) != 5033 or union & ADDED or union & EXPECTED != EXISTING:
        issues.append('Historical complete input union or PR180 overlap is unexpected')
    qualified_changes = sorted(path for path in union if source.get(path) != target.get(path))
    baseline_changes = sorted(path for path in union if baseline.get(path) != target.get(path))
    if set(qualified_changes) != EXISTING | {STORE_README} or set(baseline_changes) != EXISTING:
        issues.append('Original/previous publication input differences do not match the explicit classification')
    prior_counts = retained('reconciliation-audit/release-5569c055/independent-summary.json')
    if not prior_counts['passed'] or prior_counts['source_commit'] != QUALIFIED:
        issues.append('Historical Mail qualification source identity failed')
    archive.close()

    mail_paths = {path for path in baseline if path.startswith(('packages/quds_mail_', 'third_party/enough_mail/', 'tools/mail/'))}
    mail_paths.update(path for path in baseline if '/' not in path and Path(path).suffix in {'.yaml', '.lock'})
    mail_paths.update({'.fvmrc', REPORT + 'native-plan.json', REPORT + 'node-plan.json',
                       'docs/validation/document-review-notes-20261118/run_checks.py',
                       'docs/validation/document-review-notes-20261118/runtime/restore_runtime.py',
                       'docs/validation/document-review-notes-20261118/runtime/test_restore_runtime.py'})
    final_mail_paths = {path for path in target if path.startswith(('packages/quds_mail_', 'third_party/enough_mail/', 'tools/mail/'))}
    expected_mail_paths = {path for path in baseline if path.startswith(('packages/quds_mail_', 'third_party/enough_mail/', 'tools/mail/'))}
    mail_changes = sorted(path for path in mail_paths if baseline.get(path) != target.get(path))
    source_mail_changes = sorted(path for path in mail_paths if source.get(path) != target.get(path))
    if mail_changes or final_mail_paths != expected_mail_paths or set(source_mail_changes) != {STORE_README}:
        issues.append('Mail package/fork/test/tool/plan/dependency scope changed beyond the earlier README update')
    guard_bytes = git('cat-file', 'blob', target[GUARD]['git_blob'])
    guard_receipt = json.loads(git('cat-file', 'blob', target[GUARD_RECEIPT]['git_blob']))
    checker_bytes = git('cat-file', 'blob', target[GUARD_CHECKER]['git_blob'])
    if any(target.get(path) != baseline.get(path) for path in [GUARD, GUARD_RECEIPT, GUARD_CHECKER]):
        issues.append('The prior output-directory guard or its evidence was modified')
    if (not guard_receipt['passed'] or guard_receipt['helper_sha256'] != digest(guard_bytes)
            or guard_receipt['check_script_sha256'] != digest(checker_bytes)
            or guard_receipt['network_or_publish_performed']):
        issues.append('Retained output-directory guard evidence binding failed')

    result = {
        'schema': 'quds.office.arabic_main_tail_provenance.v1',
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'qualified_mail_execution_source': QUALIFIED, 'previous_audited_baseline': BASELINE,
        'incoming_main_parent': INCOMING_PARENT, 'incoming_main': INCOMING,
        'checked_target': {'commit': target_id, 'tree': text('rev-parse', target_id + '^{tree}').strip()},
        'exact_reviewed_repair_source': repair_id, 'required_history_included': history,
        'incoming_delta': {'documentation': sorted(DOCS), 'existing_office_source': sorted(EXISTING),
                           'new_office_source_and_tests': sorted(ADDED), 'total_paths': len(incoming_delta)},
        'baseline_to_target_delta': sorted(target_delta),
        'all_baseline_paths_outside_incoming_and_new_plan_unchanged': not(target_delta - EXPECTED - {PLAN}),
        'incoming_and_reviewed_entries': {path: {'incoming': incoming.get(path), 'final': target.get(path),
                                               'reviewed_successor_change': path in repairs} for path in sorted(EXPECTED)},
        'reviewed_successor_repair_paths': sorted(repairs),
        'separate_arabic_plan': {'path': PLAN, 'git_entry': target.get(PLAN)},
        'historical_qualification_input_checks': gates,
        'historical_distinct_input_union': len(union),
        'original_inputs_identical_to_qualified_mail_source': len(union) - len(qualified_changes),
        'original_inputs_identical_to_previous_publication': len(union) - len(baseline_changes),
        'original_qualified_input_changes': qualified_changes, 'new_input_paths': sorted(ADDED),
        'augmented_input_union_count': len(union) + len(ADDED),
        'augmented_input_union_scope': 'Historical5033 input paths plus the three newly added Office source/test paths; the separately identified Arabic plan is not included in this count.',
        'union_including_separate_arabic_plan': len(union | ADDED | {PLAN}),
        'mail_scope': {'entries_compared': len(mail_paths), 'changed_since_previous_publication': mail_changes,
                       'changed_since_qualified_source': source_mail_changes,
                       'package_fork_test_inventory_unchanged': final_mail_paths == expected_mail_paths,
                       'mail_executable_test_plan_dependency_changes': [path for path in source_mail_changes if path != STORE_README]},
        'retained_output_guard': {'path': GUARD, 'git_entry': target[GUARD], 'sha256': digest(guard_bytes),
                                  'baseline_byte_identity': target[GUARD] == baseline[GUARD],
                                  'existing_isolated_check_count': len(guard_receipt['checks']),
                                  'checks_reexecuted_by_this_audit': False},
        'historical_mail_qualification': {'execution_source': QUALIFIED,
                                         'application_executions': prior_counts['application_case_executions'],
                                         'separate_python_controls': prior_counts['combined_separate_python_controls'],
                                         'original_archive_sha256': index['archive_sha256'],
                                         'execution_relabelled_as_final_source': False},
        'qualification_boundary': 'The historical 836/78 Mail result retains its actual source. Mail executable/test/plan/dependency bytes remain unchanged, but the broad Office-containing5033 input union has three changed Office source files and three new source/test inputs, in addition to the earlier Store README documentation change. Arabic/proofing execution requires its separate source-bound receipt and is not established by this provenance audit.',
        'runtime_scope': 'No runtime/dependency source change is introduced. This audit does not reexecute or relabel runtime validation; actual before/after runtime checks belong to the separate qualification receipts.',
        'new_product_tests_or_ci_executed': False,
        'audit_script_sha256': digest(Path(__file__).read_bytes()),
        'issues': issues, 'passed': not issues,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['checked_target', 'historical_distinct_input_union',
                                                 'original_inputs_identical_to_qualified_mail_source',
                                                 'augmented_input_union_count', 'reviewed_successor_repair_paths',
                                                 'passed', 'issues']}, indent=2))
    raise SystemExit(0 if not issues else 1)


if __name__ == '__main__':
    main()
