#!/usr/bin/env python3
"""Read-only preservation audit using saved proofs and immutable Git identity.

Does not fetch refs, run application tests, touch runtime inputs, or repeat the
earlier full raw-artifact/source hashing. Output must be outside the checkout.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

ORIGINAL = '39843ed4874c7b56572c7aa8195716e5892aeca2'
PRIOR = '29dd23a6edd0a0fbb916b3d9f73861a8aa4f435e'
PUBLICATION = 'fb6e47d58d8f174797a78ca72428f82264597dbd'
INCOMING = 'be641457c8c7d1acc25091b31c87c73eaa3c9c2a'
FIRST = '4681760c542eb2a3473b72605ebb7606e0e7b4a3'
REVIEW = 'docs/validation/office-main-integration-20261119/host-final/review-evidence'
FIRST_EVIDENCE = 'docs/validation/office-main-integration-20261119/host-final/first-attempt-evidence'
EXPECTED_REPORTS = {
    'reviews/latest_ancestry_review.json':
        'b80dffcdd2d41aa16f4980e89ccaed04a1a853313ed8d892e75121adb352c1c3',
    'reviews/latest_proofing_continuity_review.json':
        'ac84178316de30fee796956da1aeb7602a5c47a169979fe3542f558ef042ce07',
}
PHASES = [
    ('original 129-suite qualified source', ORIGINAL),
    ('original PR174 evidence head', 'df62b58975bab1f650879fc88f850550a3df5c13'),
    ('initial Notes integration', 'f38959f04cf58298ac56b142228d825e9d0deb82'),
    ('early Mail integration gate', 'ebe0498a8ddd118dd579698cab3ddc281a630b11'),
    ('strict FETCH integration checkpoint', '1655db9ff8a5fb9eb140ef236fa0cca74c472107'),
    ('UID regression integration checkpoint', '7d279e084bae438d383630726ad7b0514da77d35'),
    ('post-evidence integration checkpoint', '99dd7307e749854f00266bd5b8bae4dcdf66df20'),
    ('combined TLS qualified source', '4624218f9468eeeac07f1f100ac0e4bb6b050a17'),
    ('published PR174 head', '59e0a7c232e7380021a8bda4477999205da0f8ae'),
    ('main PR174 merge', 'd41000336c84b6ebfe6b35f7f8335140b5d46038'),
    ('preserved supplemental Mail evidence', '3cd60db25cb81ff836bbc06fed9af28819337339'),
    ('Socket-compatible TLS qualified source', 'ac1e4c8c788ea608402c2260488235c0189efcba'),
    ('632-execution evidence publication', 'cd430b2229ff81e3d486c9ed95c80e92a41fe8af'),
    ('bundle continuation reconciliation', '5ec15bdd4c5016b320f0fe8edff36b1da69fa44f'),
    ('Arabic runtime capture', '84aa6f96e95c1eda39ad8c548c93b167be21dd1f'),
    ('Arabic semantic repair checkpoint', '47783366a66facf6e479ded4db009cd3047a91f6'),
    ('Arabic qualified source', 'e41679f85c511bc8cf42447d3d1af0931884dee2'),
    ('semantic repair evidence publication', '86dc8b62d9f99ffc58f2391ef719002c523dca86'),
    ('1286-execution evidence publication', 'ec8bd8edf0452f7b8dd8b15b3f9b62f1bb224fa4'),
    ('UID and Hunspell qualified source', PRIOR),
    ('784-execution evidence publication', PUBLICATION),
    ('CrispOffice host integration', '293f45449b496e3024ff100968d78f37983faadd'),
    ('Mail/routing/Notes repair checkpoint', '010e412a933097cf4e61bc683fb8477f4d96b7dc'),
    ('first host attempt source; not accepted final qualification', FIRST),
]
NOTES = [
    'packages/quds_office_editor/CHANGELOG.md',
    'packages/quds_office_editor/lib/src/embed/office_editors.dart',
    'packages/quds_office_editor/test/word_notes_proofing_controller_test.dart',
    'packages/quds_office_editor/test/word_notes_proofing_pane_test.dart',
    'packages/quds_office_editor/test/word_zotero_notes_pane_test.dart',
]
INTENTIONAL_README_UPDATES = {
    'docs/validation/office-main-completion-20261119/README.md',
    'docs/validation/office-main-integration-20261119/README.md',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--head', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    if output.is_relative_to(repo):
        raise SystemExit('Audit output must be outside the repository.')

    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args])

    def text(*args):
        return git(*args).decode().strip()

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    def ancestor(older, newer):
        result = subprocess.run(
            ['git', '-C', str(repo), 'merge-base', '--is-ancestor', older, newer],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert result.returncode in (0, 1), result.stderr.decode()
        return result.returncode == 0

    def observe():
        return {'head': text('rev-parse', 'HEAD'),
                'index_sha256': sha(git('ls-files', '--stage', '-z'))}

    before = observe()
    head = text('rev-parse', args.head+'^{commit}')
    index_bytes = git('show', head+':'+REVIEW+'.index.json')
    index = json.loads(index_bytes)
    archive_bytes = git('show', head+':'+REVIEW+'.tar.xz')
    assert len(archive_bytes) == index['archive_bytes']
    assert sha(archive_bytes) == index['archive_sha256']
    member_index = {row['path']: row for row in index['members']}
    reports = {}
    verified_members = []
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:xz') as archive:
        members = archive.getmembers()
        assert all(m.isfile() and not m.name.startswith('/') and
                   '..' not in PurePosixPath(m.name).parts for m in members)
        assert len(members) == len({m.name for m in members})
        assert {m.name for m in members} == set(member_index)
        for name, expected in EXPECTED_REPORTS.items():
            data = archive.extractfile(name).read()
            assert sha(data) == member_index[name]['sha256'] == expected
            assert len(data) == member_index[name]['bytes']
            reports[name] = json.loads(data)
            verified_members.append({'path': name, 'bytes': len(data), 'sha256': expected})

    prior = reports['reviews/latest_ancestry_review.json']
    continuity = reports['reviews/latest_proofing_continuity_review.json']
    capture = prior['captured_reference_audit']
    assert prior['passed'] and prior['frozen_source'] == PRIOR
    assert capture['passed'] and capture['integrated_head'] == PRIOR
    assert capture['total_capture_rows'] == 409
    assert capture['actual_ref_count_excluding_aliases_and_peeled_ads'] == 409
    assert capture['classification'] == {'ancestor': 381, 'historical_equivalent': 28}
    assert len(capture['refs']) == 409 and not capture['unaccounted_refs']
    assert len(capture['historical_equivalence_checks']) == 14
    assert capture['all_14_historical_equivalences_reverified']
    assert all(row['passed'] for row in capture['historical_equivalence_checks'])
    assert continuity['current_frozen_source'] == PRIOR
    assert continuity['scope']['byte_bound_suites'] == 33
    assert continuity['scope']['byte_bound_historical_cases'] == 580
    assert ancestor(PRIOR, head)

    # Verify the small source records behind the reused proof; do not rerun its
    # complete ref/cherry/artifact checks or rehash its 6,064 verified artifacts.
    proof_inputs = []
    for row in prior['saved_audit_reuse']['input_records']:
        data = git('show', row['commit']+':'+row['path'])
        assert len(data) == row['bytes'] and sha(data) == row['sha256']
        proof_inputs.append(row)
    historical_source = capture['historical_source_record']
    assert sha(git('show', historical_source['commit']+':'+historical_source['path'])) == historical_source['sha256']
    identity = lambda row: [row['namespace'], row['kind'], row['ref'], row['object_sha']]
    identities = sorted(identity(row) for row in capture['refs'])
    assert len({tuple(row) for row in identities}) == 409

    def describe(label, commit):
        resolved = text('rev-parse', commit+'^{commit}')
        assert resolved == commit
        return {'label': label, 'commit': commit,
                'tree': text('rev-parse', commit+'^{tree}'),
                'parents': text('show', '-s', '--format=%P', commit).split(),
                'subject': text('show', '-s', '--format=%s', commit),
                'ancestor_of_final_source': ancestor(commit, head)}

    phases = [describe(label, commit) for label, commit in PHASES]
    known = [describe(row['label'], row['commit'])
             for row in prior['known_head_addendum']['heads']]
    known.append(describe('later captured main after PR185', INCOMING))
    earlier = [describe(row['label'], row['commit'])
               for row in prior['earlier_main_and_integration_commits']
               if row['commit'] not in {entry['commit'] for entry in phases}]
    assert all(row['ancestor_of_final_source'] for row in phases+known+earlier)

    tree_cache = {}
    def tree(commit):
        if commit not in tree_cache:
            result = {}
            for row in git('ls-tree', '-rz', commit).split(b'\0'):
                if row:
                    metadata, path = row.split(b'\t', 1)
                    result[path.decode()] = metadata.decode().split()
            tree_cache[commit] = result
        return tree_cache[commit]

    final_tree = tree(head)
    notes = [{'path': path, 'original_entry': tree(ORIGINAL)[path],
              'final_entry': final_tree[path],
              'unchanged': tree(ORIGINAL)[path] == final_tree[path]}
             for path in NOTES]
    assert all(row['unchanged'] for row in notes)

    def catalog_digest(entries):
        return sha(json.dumps(sorted(entries.items()), separators=(',', ':')).encode())

    validation = []
    union = {}
    for label, baseline in [('29dd qualified-source snapshot', PRIOR),
                            ('completed 784-execution publication', PUBLICATION),
                            ('incoming be641 main evidence', INCOMING),
                            ('retained first host attempt source', FIRST)]:
        old = {p: v for p, v in tree(baseline).items() if p.startswith('docs/validation/')}
        raw = {p: v for p, v in old.items() if not p.lower().endswith(('.md', '.markdown'))}
        nonreadme = {p: v for p, v in old.items()
                    if p.lower().endswith(('.md', '.markdown')) and
                    PurePosixPath(p).name.lower() not in ('readme.md', 'readme.markdown')}
        changed_raw = [p for p, v in raw.items() if final_tree.get(p) != v]
        changed_reports = [p for p, v in nonreadme.items() if final_tree.get(p) != v]
        changed_readmes = [{'path': p, 'baseline_entry': v, 'final_entry': final_tree.get(p)}
                           for p, v in old.items() if PurePosixPath(p).name.lower()
                           in ('readme.md', 'readme.markdown') and final_tree.get(p) != v]
        assert not changed_raw and not changed_reports
        assert all(row['path'] in INTENTIONAL_README_UPDATES for row in changed_readmes)
        for path, entry in (raw | nonreadme).items():
            assert path not in union or union[path] == entry
            union[path] = entry
        final_subset = {p: final_tree[p] for p in raw}
        assert catalog_digest(raw) == catalog_digest(final_subset)
        validation.append({'label': label, 'baseline': baseline,
                           'prior_validation_paths': len(old),
                           'raw_non_markdown_paths': len(raw),
                           'raw_paths_identical': len(raw), 'changed_raw_paths': changed_raw,
                           'other_markdown_report_paths': len(nonreadme),
                           'other_markdown_reports_identical': len(nonreadme),
                           'changed_other_markdown_reports': changed_reports,
                           'intentional_readme_changes_excluded': changed_readmes,
                           'raw_path_mode_blob_catalog_sha256': catalog_digest(raw),
                           'current_subset_catalog_sha256': catalog_digest(final_subset)})

    key_archives = []
    for path, entry in sorted(union.items()):
        if path.endswith('.tar.xz') and (
            path.startswith('docs/validation/office-main-integration-20261119/') or
            path.startswith('docs/validation/thesaurus-20261118/resumed-20261119/evidence/')
        ):
            key_archives.append({'path': path, 'preserved_entry': entry})

    # Verify the newly retained failed attempt completely, while retaining its
    # immutable source and non-acceptance status. This is integrity verification,
    # not an independent reconstruction of raw test event counts.
    first_index_bytes = git('show', head+':'+FIRST_EVIDENCE+'.index.json')
    first_index = json.loads(first_index_bytes)
    first_archive_bytes = git('show', head+':'+FIRST_EVIDENCE+'.tar.xz')
    assert first_index['source_commit'] == FIRST
    assert len(first_archive_bytes) == first_index['archive_bytes']
    assert sha(first_archive_bytes) == first_index['archive_sha256']
    first_records = {row['path']: row for row in first_index['members']}
    assert len(first_records) == len(first_index['members'])
    first_data = {}
    with tarfile.open(fileobj=io.BytesIO(first_archive_bytes), mode='r:xz') as archive:
        members = archive.getmembers()
        assert all(m.isfile() and not m.name.startswith('/') and
                   '..' not in PurePosixPath(m.name).parts for m in members)
        assert len(members) == len({m.name for m in members})
        assert {m.name for m in members} == set(first_records)
        for name, row in first_records.items():
            data = archive.extractfile(name).read()
            assert len(data) == row['bytes'] and sha(data) == row['sha256']
            first_data[name] = data
    first_receipts = []
    for cohort, accepted, expected_passed, expected_failed in [
            ('main', False, 920, 59), ('node', True, 306, 0)]:
        receipt = json.loads(first_data[cohort+'/verification.json'])
        assert receipt['source_commit'] == FIRST
        assert receipt['source_tree'] == text('rev-parse', FIRST+'^{tree}')
        assert receipt['success'] is accepted
        assert receipt['passed'] == expected_passed and receipt['failed'] == expected_failed
        assert receipt['skipped'] == 0
        assert receipt['source_unchanged'] and receipt['environment_unchanged']
        for group in ['source', 'environment']:
            a = first_data[cohort+'/'+group+'-before.json']
            z = first_data[cohort+'/'+group+'-after.json']
            assert a == z
            for phase in ['before', 'after']:
                key = group+'-'+phase+'.json'
                assert sha(first_data[cohort+'/'+key]) == receipt['manifest_sha256'][key]
        first_receipts.append({k: receipt[k] for k in [
            'source_commit', 'source_tree', 'success', 'passed', 'failed', 'skipped',
            'source_unchanged', 'environment_unchanged', 'source_input_count', 'runtime_input_count'
        ]} | {'cohort': cohort, 'count_provenance': 'unchanged archived receipt; no raw-event recount in this preservation audit'})
    first_attempt = {
        'source': FIRST, 'archive_path': FIRST_EVIDENCE+'.tar.xz',
        'archive_sha256': sha(first_archive_bytes), 'archive_bytes': len(first_archive_bytes),
        'index_sha256': sha(first_index_bytes), 'indexed_members': len(first_records),
        'all_member_hashes_verified': True, 'all_names_safe_unique_and_indexed': True,
        'receipts': first_receipts, 'accepted_as_final_qualification': False,
        'counts_added_to_later_gate': False,
    }

    after = observe()
    report = {
        'schema': 1, 'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'final_frozen_source': head, 'final_frozen_tree': text('rev-parse', head+'^{tree}'),
        'replay_script_sha256': sha(Path(__file__).read_bytes()),
        'reused_proof_container': {'archive_path': REVIEW+'.tar.xz',
                                  'index_path': REVIEW+'.index.json',
                                  'index_source_commit': index.get('source_commit'),
                                  'archive_sha256': sha(archive_bytes),
                                  'archive_bytes': len(archive_bytes),
                                  'selected_member_hashes_verified': verified_members,
                                  'all_member_names_safe_unique_and_indexed': True},
        'saved_reference_proof': {
            'proof_source': PRIOR, 'proof_source_is_ancestor_of_final': True,
            'reference_rows': 409, 'counts': capture['counts'],
            'prior_classification': capture['classification'],
            'historical_equivalence_proofs_reused': 14,
            'prior_full_equivalence_and_ref_audit_passed': True,
            'unaccounted_saved_refs': [],
            'reference_identity_catalog_sha256': sha(json.dumps(identities, separators=(',', ':')).encode()),
            'small_proof_inputs_reverified': proof_inputs,
            'historical_source_record': historical_source,
            'scope': 'The saved 381 ancestry proofs and 28 reference dispositions backed by 14 immutable historical-equivalence proofs remain valid through 29dd ancestry. This is proof reuse, not a new remote advertisement or a claim that historical equivalents are direct ancestors.',
        },
        'retained_first_host_attempt': first_attempt,
        'saved_phase_checkpoints': phases,
        'captured_later_main_and_pr_heads': known,
        'other_saved_integration_heads': earlier,
        'all_explicit_checkpoint_and_head_ancestors': True,
        'original_notes_preservation': notes,
        'validation_artifact_preservation': {
            'baselines': validation, 'union_nonreadme_paths': len(union),
            'all_union_nonreadme_paths_identical': True,
            'union_path_mode_blob_catalog_sha256': catalog_digest(union),
            'key_qualification_archives': key_archives,
            'prior_full_29dd_audit_verified_6064_raw_artifact_sha256_values':
                prior['raw_artifact_continuity']['unchanged_raw_artifact_paths'] == 6064,
            'method': 'Git mode/type/blob identity extends prior byte-hash checks without rereading thousands of artifact bodies. Original receipts, report content and source attributions remain unchanged. Only README status updates are excluded. No archive event recount or current application test result is inferred.',
        },
        'historical_qualification_scope': {
            'reused_29dd_proofing_continuity_original_source': continuity['qualified_source'],
            'reused_29dd_proofing_continuity_suites': 33,
            'reused_29dd_proofing_continuity_historical_executions': 580,
            'that_static_closure_claim_stops_at': PRIOR,
            'new_host_rule_routing_and_fixture_inputs_require_final_gate': True,
            'original129_native208_and_web_results_keep_original_source_attribution': True,
            'historical_and_fresh_overlapping_counts_not_added': True,
            'final_host_gate_result_claimed_by_this_audit': False,
            'human_browser_installed_os_and_linguistic_release_gates_changed': False,
        },
        'working_copy_observation': {'before': before, 'after': after, 'unchanged': before == after},
        'remote_refreshes': 0, 'github_actions_queries': 0,
        'repository_mutations': 0, 'runtime_mutations': 0,
        'application_tests_executed': False, 'passed': True,
    }
    output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'output': str(output), 'source': head, 'passed': True,
                      'saved_refs': 409, 'phase_checkpoints': len(phases),
                      'later_heads': len(known), 'other_integration_heads': len(earlier),
                      'notes_preserved': len(notes), 'union_nonreadme_artifacts': len(union),
                      'first_attempt_archive_members_verified': len(first_records),
                      'baselines': [{k: row[k] for k in ['baseline', 'raw_non_markdown_paths',
                                                       'other_markdown_report_paths']}
                                    for row in validation],
                      'working_copy_observation_unchanged': before == after}, indent=2))


if __name__ == '__main__':
    main()
