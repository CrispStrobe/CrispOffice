#!/usr/bin/env python3
"""Read-only source/dependency delta for the next incoming main checkpoint."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import runpy


BASELINE = '5289b90a83ce9042a4f4cfb73ba8115fe501513a'
INCOMING = '9f23cbd2be72c527829b3990f22b356e5237ed96'
PRIOR_MAIN = '4a1eaa69e7a068e354bdd851ec9b0323b89ae300'
GUARD = 'packages/quds_office_engine/lib/src/automation/operations/word_header_footer_guard.dart'
MACRO_TEST = 'packages/quds_office_engine/test/office_macro_word_headers_footers_test.dart'
MAIL_NATIVE = 'packages/quds_office_editor/example/lib/studio_mail_native.dart'
SAVED_MAIL_TEST = 'packages/quds_office_editor/example/test/studio_saved_mail_test.dart'
EXPECTED_AFFECTED = {
    'packages/quds_office_engine/test/word_table_grid_addressing_test.dart',
    'packages/quds_office_engine/test/word_bookmark_fidelity_test.dart',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--combined-ref', help='Optional committed merge for final source verification')
    args = parser.parse_args()
    repo = args.repo.resolve()
    evidence = repo / 'docs/validation/zotero-table-cell-ranges-20261121'
    helper_path = evidence / 'combined-main/replay_impact_review.py'
    prior_review = json.loads((evidence / 'combined-main/impact-review.json').read_text())
    helper_sha = hashlib.sha256(helper_path.read_bytes()).hexdigest()
    assert helper_sha == prior_review['replay_script_sha256'], 'Prior reviewed helper changed'
    h = runpy.run_path(str(helper_path), run_name='review_helpers')
    selected = json.loads((evidence / 'qualification.json').read_text())['selected_test_files']
    target = (h['git'](repo, 'rev-parse', f'{args.combined_ref}^{{commit}}').decode().strip()
              if args.combined_ref else INCOMING)
    refs = list(dict.fromkeys((BASELINE, INCOMING, target)))
    trees = {ref: h['tree'](repo, ref) for ref in refs}
    needed = {item['git_blob_sha1'] for entries in trees.values() for p, item in entries.items()
              if h['captured_path'](p) or p.endswith('.dart') or PurePosixPath(p).name == 'pubspec.yaml'}
    blobs = h['load_blobs'](repo, needed)
    maps = {ref: h['source_map'](entries, blobs) for ref, entries in trees.items()}
    graphs = {ref: h['dependency_graph'](entries, blobs) for ref, entries in trees.items()}
    base_entries = trees[BASELINE]
    target_entries = trees[target]
    changed = {p for p in set(base_entries) | set(target_entries)
               if base_entries.get(p) != target_entries.get(p)}
    changed_production = {p for p in changed if '/lib/' in p and p.endswith('.dart')}
    rows = []
    issues = {}
    for ref in (BASELINE, target):
        dependencies = set()
        for suite in selected:
            dependencies.update(h['closure'](graphs[ref][0], suite))
        issues[ref] = [{'path': p, **d} for p in sorted(dependencies)
                       for d in graphs[ref][3].get(p, ())]
    assert not any(issues.values()), 'Unresolved/unsupported selected closure directives'
    for suite in selected:
        before = h['closure'](graphs[BASELINE][0], suite)
        after = h['closure'](graphs[target][0], suite)
        affected = sorted(set(after) & changed_production)
        rows.append({
            'path': suite,
            'test_source_unchanged': base_entries[suite] == target_entries[suite],
            'repository_dependency_count': len(after),
            'repository_dependency_identity_sha256': h['canonical_digest'](h['identity'](target_entries, after)),
            'repository_dependency_closure_unchanged': h['identity'](base_entries, before) == h['identity'](target_entries, after),
            'changed_production_dependencies': affected,
            'dependency_paths': {p: h['path_to'](after, p) for p in affected},
        })
    assert all(r['test_source_unchanged'] for r in rows), 'Selected test source changed'
    assert {r['path'] for r in rows if r['changed_production_dependencies']} == EXPECTED_AFFECTED
    assert sum(r['repository_dependency_closure_unchanged'] for r in rows) == 117
    assert changed_production == {GUARD}, 'Unexpected production change'
    changed_loaders = []
    for path in changed_production:
        text = blobs[target_entries[path]['git_blob_sha1']].decode()
        for number, line in enumerate(text.splitlines(), 1):
            if re.search(r'\b(Process\.(?:run|runSync|start)|Isolate\.spawnUri|loadLibrary\(|Platform\.script)', line):
                changed_loaders.append({'path': path, 'line': number, 'text': line.strip()})
    assert not changed_loaders, 'Changed production has an unreviewed dynamic loader'
    assert all(base_entries[p] == target_entries[p] for p in h['LOADER_DISPOSITIONS'])
    assert trees[BASELINE][MAIL_NATIVE] == trees[INCOMING][MAIL_NATIVE], 'Incoming Mail native differs'
    assert base_entries[MAIL_NATIVE] == target_entries[MAIL_NATIVE], 'Combined Mail native differs'
    node = [r for p in h['NODE_TESTS'] for r in rows if r['path'] == p]
    assert len(node) == 2 and all(r['repository_dependency_closure_unchanged'] for r in node)
    modified = h['changes'](maps[BASELINE], maps[target])
    if args.combined_ref:
        assert maps[BASELINE][SAVED_MAIL_TEST] == maps[target][SAVED_MAIL_TEST], 'Saved-Mail regression was lost'
        assert {r['path'] for r in modified['modified_existing']} == {GUARD, MACRO_TEST}
        assert not modified['added'] and not modified['removed']
    guard_imports = {}
    for ref in (BASELINE, INCOMING):
        text = blobs[trees[ref][GUARD]['git_blob_sha1']].decode()
        guard_imports[ref] = [line for line in text.splitlines() if line.startswith(('import ', 'export ', 'part '))]
    assert guard_imports[BASELINE] == guard_imports[INCOMING]
    relevant_fields = ('schema_version', 'reviewed_commit', 'reviewed_tree', 'reviewed_source_identity_sha256')
    report = {
        'schema_version': 1,
        'status': 'pending-targeted-39-case-execution-and-final-merged-source-receipt',
        'accepts_new_main': False,
        'baseline_combined_checkpoint': BASELINE,
        'incoming_main': INCOMING,
        'previous_main': PRIOR_MAIN,
        'reviewed_target': target,
        'reviewed_target_is_final_combination': bool(args.combined_ref),
        'reviewed_tree': h['git'](repo, 'rev-parse', f'{target}^{{tree}}').decode().strip(),
        'prior_impact_review': {k: prior_review[k] for k in relevant_fields},
        'prior_impact_review_sha256': h['sha256']((evidence / 'combined-main/impact-review.json').read_bytes()),
        'dependency_helper_sha256': helper_sha,
        'replay_script_sha256': h['sha256'](Path(__file__).read_bytes()),
        'baseline_to_incoming_source_delta': h['changes'](maps[BASELINE], maps[INCOMING]),
        'baseline_to_reviewed_source_delta': modified,
        'reviewed_source_identity_sha256': h['canonical_digest'](maps[target]),
        'studio_mail_native_identical': True,
        'studio_mail_native_identity': maps[target][MAIL_NATIVE],
        'saved_mail_regression_disposition': ('Preserved exactly in the combined commit.' if args.combined_ref else
            'The incoming main lacks our 27-line regression added at the baseline. Retain the baseline version when merging; this file is outside the original 119 selected suites.'),
        'header_guard_imports_unchanged': True,
        'guard_changes': [
            'Checks independent/non-inherited story linkage across all sections before edits.',
            'Rejects aliasing of mutable paragraph, inline and property models.',
            'Requires faithful native paragraph/run text projection and supported attributes/markers.',
        ],
        'only_changed_production_source': GUARD,
        'changed_unselected_macro_test': MACRO_TEST,
        'selected_suites': rows,
        'all_119_selected_test_sources_unchanged': True,
        'unchanged_selected_dependency_closures': 117,
        'affected_selected_suites': sorted(EXPECTED_AFFECTED),
        'directive_completeness_issues': issues,
        'changed_production_dynamic_loader_matches': changed_loaders,
        'prior_reviewed_loader_sources_unchanged': True,
        'node_selected_suites': node,
        'both_node_repository_closures_unchanged': True,
        'repeat_plan': {
            'expected_existing_cases': 39,
            'suites': [{'path': p, 'original_passed_cases': 22 if 'grid_addressing' in p else 17}
                       for p in sorted(EXPECTED_AFFECTED)],
            'result': 'Pending separate immutable-source execution receipts; these are repeated existing cases.',
        },
        'studio_repeat_needed_for_this_delta': False,
        'full_119_suite_repeat_needed_for_this_delta': False,
        'no_github_ci_used': True,
        'no_source_or_ref_mutations': True,
    }
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
