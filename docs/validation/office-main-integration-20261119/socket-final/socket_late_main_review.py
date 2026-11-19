#!/usr/bin/env python3
"""Audit the immutable late-main publication without modifying frozen inputs."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path('/workspace/scratch/a7846890f2e1')
REPO = ROOT / 'quds_office_suite'
FROZEN = 'ac1e4c8c788ea608402c2260488235c0189efcba'
MAIN = '55e262ef269634a0d618c0b5102dc9be5430a5f3'
PR_HEAD = 'b0a9bd3f1b46ac89021d1b7e49c32980ca4d181e'
QUALIFIED = '5569c055a021c893e941fc54d40499ad9d96a5db'
PREVIOUS_INCOMING = '022a974a96db23e22bc161f7d465e4b972e8c2a9'
BASE = 'docs/validation/office-main-completion-20261119/release/'


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def blob(head, path):
    return git('show', head + ':' + path)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def tree(commit):
    return git('rev-parse', commit + '^{tree}').decode().strip()


def entries(commit):
    result = {}
    for row in git('ls-tree', '-rz', commit).split(b'\0'):
        if row:
            meta, path = row.split(b'\t', 1)
            mode, kind, oid = meta.decode().split()
            result[path.decode()] = {'mode': mode, 'type': kind, 'git_blob': oid}
    return result


def json_blob(head, path):
    return json.loads(blob(head, path))


assert tree(MAIN) == tree(PR_HEAD)
publication_paths = git('diff', '--name-only', PREVIOUS_INCOMING, PR_HEAD).decode().splitlines()
assert all(path == 'README.md' or path.startswith('docs/') for path in publication_paths)
index = json_blob(MAIN, BASE + 'local-qualification.index.json')
archive_bytes = blob(MAIN, BASE + index['archive'])
assert len(archive_bytes) == index['archive_bytes']
assert digest(archive_bytes) == index['archive_sha256']
with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:xz') as archive:
    members = archive.getmembers()
    assert all(member.isfile() for member in members)
    assert len(members) == len({member.name for member in members})
    files = {member.name: archive.extractfile(member).read() for member in members}
indexed = {member['path']: member for member in index['members']}
assert len(indexed) == len(index['members']) == index['member_count'] == len(files)
assert set(files) == set(indexed)
for path, data in files.items():
    assert len(data) == indexed[path]['bytes']
    assert digest(data) == indexed[path]['sha256']

manifest = json_blob(MAIN, BASE + 'manifest.json')
summary = json_blob(MAIN, BASE + 'independent-summary.json')
coverage = json_blob(MAIN, BASE + 'coverage-summary.json')
for document in (manifest, summary, coverage):
    assert document['source_commit'] == QUALIFIED
    assert document['source_tree'] == tree(QUALIFIED)
for path, expected in manifest['summary_sha256'].items():
    assert digest(blob(MAIN, BASE + path)) == expected
for document in (summary, coverage):
    assert digest(files[document['complete_audit_member']]) == document['complete_audit_sha256']

source_entries = entries(QUALIFIED)
published_entries = entries(MAIN)
frozen_entries = entries(FROZEN)
sources = {}
receipts = {}
for gate in ('native', 'node'):
    prefix = 'qualification-release-' + gate + '/'
    before = json.loads(files[prefix + 'source-before.json'])
    assert before == json.loads(files[prefix + 'source-after.json'])
    assert json.loads(files[prefix + 'environment-before.json']) == json.loads(files[prefix + 'environment-after.json'])
    receipt = json.loads(files[prefix + 'verification.json'])
    assert receipt['source_commit'] == QUALIFIED and receipt['source_tree'] == tree(QUALIFIED)
    assert receipt['source_input_count'] == len(before) == 5031
    assert receipt['success'] and receipt['failed'] == receipt['skipped'] == 0
    assert digest(blob(QUALIFIED, receipt['plan'])) == receipt['plan_sha256']
    for path, record in before.items():
        for checked_tree in (source_entries, published_entries):
            assert checked_tree[path]['mode'] == record['mode']
            assert checked_tree[path]['git_blob'] == record['git_blob']
    sources[gate] = before
    receipts[gate] = receipt

objects = sorted({record['git_blob'] for source in sources.values() for record in source.values()})
hashes = {}
process = subprocess.Popen(['git', '-C', str(REPO), 'cat-file', '--batch'],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
for oid in objects:
    process.stdin.write((oid + '\n').encode())
    process.stdin.flush()
    got_oid, kind, size = process.stdout.readline().decode().strip().split()
    assert got_oid == oid and kind == 'blob'
    data = process.stdout.read(int(size))
    assert len(data) == int(size) and process.stdout.read(1) == b'\n'
    hashes[oid] = digest(data)
process.stdin.close()
assert process.wait() == 0, process.stderr.read().decode()
for source in sources.values():
    for record in source.values():
        assert record['materialized'] and hashes[record['git_blob']] == record['sha256']

store = json.loads(files['qualification-release-store/results/receipt.json'])
assert store['starting_commit'] == QUALIFIED and store['status'] == 'PASS'
assert store['source_before'] == store['source_after']
for path, expected in store['source_before'].items():
    assert digest(blob(QUALIFIED, path)) == expected
support = json.loads(files['qualification-release-support/receipt.json'])
assert support['source_commit'] == QUALIFIED and support['source_tree'] == tree(QUALIFIED)
assert support['success'] and support['source_before'] == support['source_after']
assert support['passed'] == 36

groups = summary['groups']
assert sum(group['passed'] for group in groups) == summary['application_case_executions'] == 836
assert summary['failed'] == summary['skipped'] == 0
assert sum(group['suites'] for group in groups) == summary['suite_platform_executions'] == 85
assert receipts['native']['passed'] == 602 and receipts['node']['passed'] == 35
store_groups = [group for group in groups if group['gate'] == 'store']
assert sum(group['passed'] for group in store_groups) == 199
assert manifest['separate_python_controls'] == summary['combined_separate_python_controls'] == 78

runtime_references = []
for reference in manifest['runtime_evidence_references']:
    archive_data = blob(MAIN, reference['archive_repository_path'])
    index_data = blob(MAIN, reference['index_repository_path'])
    assert len(archive_data) == reference['archive_bytes']
    assert digest(archive_data) == reference['archive_sha256']
    assert digest(index_data) == reference['index_sha256']
    runtime_references.append({**reference, 'archive_and_index_bytes_verified': True})

changes_from_frozen = []
for path, record in sources['native'].items():
    current = frozen_entries.get(path)
    if current is None or current['mode'] != record['mode'] or current['git_blob'] != record['git_blob']:
        changes_from_frozen.append({'path': path, 'qualified_and_late_main': record,
                                    'frozen_ac1_entry': current})

incoming_release_paths = sorted(path for path in published_entries if path.startswith(BASE)
                                and path not in frozen_entries)
missing_mail_evidence = sorted(path for path in frozen_entries if path not in published_entries
                               and (path.startswith('docs/validation/mail-m06-resume-20261119/final/')
                                    or path.startswith('docs/validation/mail-m06-resume-20261119/review/tls-development-evidence/')))
assert len(incoming_release_paths) == 12
assert len(missing_mail_evidence) == 36

report = {
    'frozen_source_left_unchanged': FROZEN,
    'late_main': MAIN, 'late_pr_head': PR_HEAD,
    'late_main_and_pr_tree': tree(MAIN), 'late_main_and_pr_tree_identical': True,
    'prior_known_incoming': PREVIOUS_INCOMING,
    'new_publication_changes_confined_to_readme_and_docs': True,
    'publication_paths_since_prior_known_incoming': publication_paths,
    'qualified_source': QUALIFIED, 'qualified_tree': tree(QUALIFIED),
    'archive': {
        'path': BASE + index['archive'], 'bytes': len(archive_bytes),
        'sha256': digest(archive_bytes), 'member_count': len(files),
        'uncompressed_bytes': sum(map(len, files.values())),
        'member_set_sizes_and_sha256_verified': True,
        'summary_and_internal_audit_member_hashes_verified': True,
    },
    'source_binding': {
        'native_records': len(sources['native']), 'node_records': len(sources['node']),
        'unique_git_blobs_independently_sha256_hashed': len(hashes),
        'all_modes_and_blobs_match_qualified_and_late_main_trees': True,
        'all_archived_source_sha256_values_match_qualified_git_bytes': True,
        'native_node_source_and_environment_before_after_equal': True,
        'source_qualified_plan_hashes_verified': True,
        'store_bound_input_hashes_verified': len(store['source_before']),
        'current_runtime_environment_reverified': False,
    },
    'reported_counts_reconciled_from_retained_receipts_and_summaries': {
        'native_executions': 602, 'node_executions': 35, 'core_store_executions': 199,
        'total_application_executions': 836, 'suite_platform_executions': 85,
        'distinct_test_files': 73, 'separate_python_controls': 78,
        'count_is_not_a_distinct_case_claim': True,
        'new_raw_event_recount_performed_by_this_review': False,
    },
    'bound_paths_differing_between_5569_and_frozen_ac1': changes_from_frozen,
    'runtime_reference_bytes': runtime_references,
    'incoming_release_paths_to_preserve': incoming_release_paths,
    'frozen_mail_evidence_missing_from_late_main_to_preserve': missing_mail_evidence,
    'recommended_merge_scope': [
        'Merge late-main ancestry and preserve all newly added release evidence, indexes and complete completion report.',
        'Retain every frozen ac1 bound input; the 836 execution evidence is a separate 5569c055 checkpoint and does not qualify ac1-specific cleanup/tests or prove ac1 inventory identity.',
        'Retain all 36 Mail publication artifacts already present in ac1; their absence from the other tip is not a reason to remove them.',
        'Preserve the Historical PR #174 receipt header and original 611 execution body. Contextualize the linked 836 execution report as the later PR #173 checkpoint; publish ac1 qualification separately after its own audit.',
        'Keep frozen socket ref/continuity audits unchanged. Record this late main and its final merge/readback as a separate addendum.',
    ],
    'scope': 'Archive integrity, immutable Git source continuity and retained receipt arithmetic only. No fresh application tests, current runtime revalidation, raw-event recount, remote query or GitHub Actions query.',
    'tracked_checkout_or_runtime_mutations_performed': False,
    'passed': True,
}
(ROOT / 'socket_late_main_review.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({
    'passed': True, 'report': str(ROOT / 'socket_late_main_review.json'),
    'archive': report['archive'], 'source_binding': report['source_binding'],
    'counts': report['reported_counts_reconciled_from_retained_receipts_and_summaries'],
    'changed_bound_paths_vs_ac1': [row['path'] for row in changes_from_frozen],
    'new_release_paths': len(incoming_release_paths),
    'mail_evidence_paths_to_retain': len(missing_mail_evidence),
}, indent=2))
