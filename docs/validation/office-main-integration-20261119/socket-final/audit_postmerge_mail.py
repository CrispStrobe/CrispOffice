#!/usr/bin/env python3
"""Review immutable Mail publication objects without touching the checkout."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path('/workspace/scratch/a7846890f2e1')
REPO = ROOT / 'quds_office_suite'
MAIN = 'd41000336c84b6ebfe6b35f7f8335140b5d46038'
MAIL = '700e5a35ce5f96e7abd1dc92d1a00d2110d40649'
SOURCE = '71edec2de364805113d18e0f1d7edbb1f00467e5'
ZOTERO = '022a974a96db23e22bc161f7d465e4b972e8c2a9'
PREFIX = 'docs/validation/mail-m06-resume-20261119/final/'


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def blob(head, path):
    return git('show', head + ':' + path)


def sha(value):
    return hashlib.sha256(value).hexdigest()


def obj(head, path):
    return json.loads(blob(head, path))


def entries(head):
    result = {}
    for row in git('ls-tree', '-rz', head).split(b'\0'):
        if row:
            meta, path = row.split(b'\t', 1)
            mode, kind, oid = meta.decode().split()
            result[path.decode()] = {'mode': mode, 'type': kind, 'git_blob': oid}
    return result


def archive(head, path):
    contents = blob(head, path)
    with tarfile.open(fileobj=io.BytesIO(contents), mode='r:xz') as handle:
        members = handle.getmembers()
        assert all(member.isfile() for member in members)
        assert len(members) == len({member.name for member in members})
        files = {member.name: handle.extractfile(member).read() for member in members}
    return contents, files


source_entries = entries(SOURCE)
mail_entries = entries(MAIL)
changed = git('diff', '--name-only', SOURCE, MAIL).decode().splitlines()
named_docs = {
    'docs/roadmaps/mail/status.md',
    'docs/roadmaps/mail/implementation-plan.md',
    'docs/validation/mail-m06-resume-20261119/README.md',
    'packages/quds_mail_store/README.md',
}
assert all(path in named_docs or path.startswith(PREFIX) or path.startswith(
    'docs/validation/mail-m06-resume-20261119/review/tls-development-evidence/'
) for path in changed)
archive_reports = []
all_files = {}
for index_path in sorted(path for path in mail_entries if path.startswith(PREFIX)
                         and path.endswith('.tar.index.json')):
    index = obj(MAIL, index_path)
    archive_path = PREFIX + index['archive']
    contents, files = archive(MAIL, archive_path)
    assert len(contents) == index['archive_bytes']
    assert sha(contents) == index['archive_sha256']
    indexed = {member['path']: member for member in index['members']}
    assert len(indexed) == len(index['members'])
    assert set(indexed) == set(files)
    for name, contents_member in files.items():
        assert len(contents_member) == indexed[name]['bytes']
        assert sha(contents_member) == indexed[name]['sha256']
    all_files[index['archive']] = files
    archive_reports.append({
        'path': archive_path,
        'archive_bytes': len(contents),
        'archive_sha256': sha(contents),
        'member_count': len(files),
        'uncompressed_bytes': sum(map(len, files.values())),
        'source_commit': index.get('source_commit'),
        'member_set_sizes_and_hashes_verified': True,
    })
assert len(archive_reports) == 8

source_bindings = []
for name in ('native', 'node'):
    files = all_files[name + '-final.tar.xz']
    before = json.loads(files[name + '-final/source-before.json'])
    after = json.loads(files[name + '-final/source-after.json'])
    assert before == after
    mismatches = []
    for path, binding in before.items():
        entry = source_entries.get(path)
        if entry is None or entry['mode'] != binding['mode'] or entry['git_blob'] != binding['git_blob']:
            mismatches.append(path)
    assert not mismatches, mismatches
    receipt = obj(MAIL, PREFIX + name + '-final-verification.json')
    assert receipt['source_commit'] == SOURCE
    assert receipt['source_tree'] == git('rev-parse', SOURCE + '^{tree}').decode().strip()
    assert receipt['success'] and receipt['failed'] == receipt['skipped'] == 0
    assert receipt['plan_sha256'] == sha(blob(SOURCE, receipt['plan']))
    source_bindings.append({
        'gate': name,
        'source_records': len(before),
        'all_record_modes_and_git_blobs_match_source_tree': True,
        'source_before_after_equal': True,
        'plan_hash_matches_qualified_source': True,
        'receipt_passed': receipt['passed'],
        'source_commit': SOURCE,
    })

store = obj(MAIL, PREFIX + 'mail-final-receipt.json')
assert store['starting_commit'] == SOURCE
assert store['status'] == 'PASS' and store['source_before'] == store['source_after']
for path, expected in store['source_before'].items():
    assert sha(blob(SOURCE, path)) == expected

execution = obj(MAIL, PREFIX + 'execution.json')
assert execution['head'] == SOURCE and execution['status'] == 'PASS'
evidence = obj(MAIL, PREFIX + 'evidence-audit.json')
assert evidence['source_commit'] == SOURCE and evidence['success']

readme_path = 'packages/quds_mail_store/README.md'
_, main_files = archive(MAIN, 'docs/validation/office-main-integration-20261119/tls/qualification-evidence.tar.xz')
main_source = json.loads(main_files['focused/source-before.json'])
main_store = obj(MAIN, 'docs/validation/office-main-integration-20261119/tls/store-receipt.json')
readme = {
    'path': readme_path,
    'main_focused_source_records': len(main_source),
    'main_bound_record': main_source[readme_path],
    'main_sha256': sha(blob(MAIN, readme_path)),
    'incoming_sha256': sha(blob(MAIL, readme_path)),
    'incoming_git_blob': mail_entries[readme_path]['git_blob'],
    'included_in_main_core_store_binding': readme_path in main_store['source_before'],
    'included_in_mail_core_store_binding': readme_path in store['source_before'],
    'main_core_store_bound_inputs': len(main_store['source_before']),
    'mail_core_store_bound_inputs': len(store['source_before']),
    'decision': 'Accept useful documentation with an explicit publication-documentation exception. The complete prior focused inventory is no longer identical. Do not rewrite its archived manifest or represent the old run as executed on a newer tree.',
}
assert readme['main_sha256'] == readme['main_bound_record']['sha256']
assert readme['main_sha256'] != readme['incoming_sha256']

models_path = 'packages/quds_mail_core/test/models_test.dart'
models = {}
for label, head in [('main', MAIN), ('incoming_zotero', ZOTERO)]:
    contents = blob(head, models_path).decode()
    models[label] = {
        'git_blob': git('rev-parse', head + ':' + models_path).decode().strip(),
        'nonconstant_equivalent': 'final equivalent = MailMessageFlags(' in contents,
        'nonidentity_assertion': 'expect(identical(observed, equivalent), isFalse);' in contents,
        'equality_assertion': 'expect(observed, equivalent);' in contents,
        'equal_hash_assertion': 'expect(observed.hashCode, equivalent.hashCode);' in contents,
        'cascade_set_add': 'expect({observed}..add(equivalent), hasLength(1));' in contents,
    }
assert all(models[label][key] for label in models for key in (
    'nonconstant_equivalent', 'nonidentity_assertion', 'equality_assertion', 'equal_hash_assertion'))
models['diff'] = git('diff', MAIN, ZOTERO, '--', models_path).decode()
models['decision'] = 'Keep exact main blob dd9172e8aed55f976baf698ce9e5ed52d8cc0c02, preserving explicit nonidentity, equality, hash and runtime Set.add coverage.'

merge = json.loads((ROOT / 'postmerge_mail_merge_tree.json').read_text())
report = {
    'main': MAIN, 'incoming_mail': MAIL, 'incoming_zotero': ZOTERO,
    'incoming_mail_qualified_source': SOURCE,
    'status': 'PASS; merge decisions identified; no application execution performed',
    'incoming_mail_changed_paths': changed,
    'incoming_mail_changes_confined_to_declared_docs_and_evidence': True,
    'simulated_merge': merge,
    'archives': archive_reports,
    'archive_member_total': sum(item['member_count'] for item in archive_reports),
    'archive_uncompressed_bytes': sum(item['uncompressed_bytes'] for item in archive_reports),
    'source_bindings': source_bindings,
    'core_store_input_hashes_verified_at_71e': len(store['source_before']),
    'incoming_counts_from_retained_evidence_audit': evidence['counts'],
    'count_scope': 'Retain 631 executions / 508 distinct scenarios / 48 suites as the separate 71edec2d Mail-branch result. Do not replace or add to the main 4624218f result of 611 executions / 541 distinct cases / 47 suites. These retained count records were not freshly re-executed or independently recounted from raw events by this review.',
    'store_readme_source_binding': readme,
    'models_test_preservation': models,
    'merge_guidance': {
        'docs/roadmaps/mail/status.md': 'Keep main integrated status/counts and add a separate historical 71edec2d Mail-branch evidence link if useful. Do not restore branch-only continuation instructions or substitute incoming 631 counts.',
        'docs/roadmaps/mail/implementation-plan.md': 'Keep main current qualification text and existing Linux loopback ownership coverage. Link incoming 71edec2d evidence as a separate checkpoint, preserving current 4624218f counts until next qualification.',
        'docs/validation/mail-m06-resume-20261119/README.md': 'Accept incoming complete historical report, retain all 71edec2d identities and links; add a brief contextual link to the current Office integration report so its Final heading cannot imply qualification of a later merged source.',
        'packages/quds_mail_store/README.md': 'Accept incoming evidence detail while identifying 71edec2d as the Mail-branch checkpoint and linking current Office integration separately. Record the changed bound documentation input; preserve archive manifests exactly.',
        'all_added_evidence_and_logs': 'Retain every added original artifact without rewriting source identities, failed receipts, counts, indexes or archives.',
    },
    'limitations': ['No fresh test execution', 'No source/runtime continuity claim to the yet-unresolved Zotero merge', 'No runtime filesystem or raw-event recount in this review', 'No remote queries or GitHub Actions queries', 'No tracked checkout edits; merge simulation object writes isolated to scratch'],
}
(ROOT / 'postmerge_mail_documentation_review.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({
    'status': report['status'],
    'report': str(ROOT / 'postmerge_mail_documentation_review.json'),
    'archives_verified': len(archive_reports),
    'members_verified': report['archive_member_total'],
    'uncompressed_bytes': report['archive_uncompressed_bytes'],
    'source_bindings': source_bindings,
    'readme_bound_snapshot_changes': True,
    'models_recommendation': models['decision'],
}, indent=2))
