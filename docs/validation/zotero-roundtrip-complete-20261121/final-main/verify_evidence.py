#!/usr/bin/env python3
"""Verify final-main archives, distinct case identities and source/intake binding.

The previous two packages remain frozen and are verified recursively. Historical
Word qualification is supplemental evidence; its pass totals are not added.
"""
import argparse
from collections import Counter
import contextlib
import hashlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import tarfile


PREFIX = 'validation/latest-main/'
EVENT_MEMBER = PREFIX + 'renderer/events.jsonl'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args]).decode().strip()


def derive_accounting(base):
    frozen = base.parent / 'evidence'
    previous = base.parent / 'final-delivery'
    module = runpy.run_path(str(frozen / 'scripts/account_cases.py'))
    helpers = runpy.run_path(str(previous / 'verify_evidence.py'))
    sets = {name: module['case_keys'](frozen, source)
            for name, source in module['SOURCES'].items()}
    earlier = module['case_keys'](previous, ('evidence.tar.gz', helpers['EVENT_MEMBER']))
    current = module['case_keys'](base, ('evidence.tar.gz', EVENT_MEMBER))
    baseline = set().union(*sets.values(), earlier)
    scopes = {
        'engine': sets['engine'],
        'editor_distinct': sets['editor'] | sets['renderer'] | earlier | current,
        'studio_zotero': sets['studio_zotero'],
        'mail_core': sets['mail_core'],
        'mail_store': sets['mail_store'],
        'mail_studio': sets['mail_studio'],
    }
    combined = set()
    for name, keys in scopes.items():
        assert not combined & keys, name
        combined |= keys
    return {
        'schema': 1,
        'identity': ['repository-relative suite path', 'test name'],
        'previous_distinct_accepted_cases': len(baseline),
        'final_main_accepted_executions': len(current),
        'final_main_repeated_cases': len(current & baseline),
        'final_main_additional_cases': len(current - baseline),
        'distinct_accepted_cases': len(combined),
        'distinct_editor_cases': len(scopes['editor_distinct']),
        'final_nonoverlapping_scope_counts': {name: len(keys) for name, keys in scopes.items()},
        'final_scope_identity_sha256': {name: helpers['identity_digest'](keys) for name, keys in scopes.items()},
        'all_distinct_identity_sha256': helpers['identity_digest'](combined),
        'repeated_final_main_cases': helpers['identities'](current & baseline),
        'additional_final_main_cases': helpers['identities'](current - baseline),
        'raw_event_sources': {
            'frozen': '../evidence/case-accounting.json',
            'previous_followup': '../final-delivery/case-accounting.json',
            'final_main': {'archive': 'evidence.tar.gz', 'member': EVENT_MEMBER},
        },
        'counting_policy': (
            'Union of accepted identities executed during this work across '
            'documented checkpoints. This is not a single whole-suite run at '
            'the final checkpoint. Prior rejected attempts and repeated cases '
            'remain excluded. Supplemental incoming Word qualification and '
            'converter commands are not added to this test-case ledger.'),
        'supplemental_incoming_executions_not_added': {
            'word_engine': 998, 'incoming_engine': 716,
            'formatter_followup': 33, 'odt_style_followup': 46,
            'final_editor': 75,
        },
    }


def derive_intake(repo, base, head):
    ancestors = set(git(repo, 'rev-list', head).splitlines())
    summaries = []
    resolved = []
    for name, label in [('final-original-replay.json', 'original383'),
                        ('final-publication-classified-replay.json', 'publication386')]:
        path = base.parent / 'intake' / name
        data = json.loads(path.read_text())
        proofs = data['proofs']
        for source, proof in proofs.items():
            replacement = proof['replacement']
            assert replacement in ancestors
            if proof['kind'] == 'full_tree':
                assert git(repo, 'rev-parse', source + '^{tree}') == git(repo, 'rev-parse', replacement + '^{tree}')
            else:
                origin = proof.get('base') or git(repo, 'merge-base', source, replacement)
                paths = git(repo, 'diff', '--name-only', origin, source).splitlines()
                assert paths and not git(repo, 'diff', '--name-only', source, replacement, '--', *paths)
        counts = Counter()
        for row in data['refs']:
            disposition = ('ancestor' if row['sha'] in ancestors else
                           'verified_equivalent' if row['sha'] in proofs else 'unmerged')
            counts[disposition] += 1
            if row['disposition'] == 'deferred_new_draft':
                resolved.append({key: row[key] for key in ('repository', 'ref', 'sha')} | {
                    'previous_disposition': row['disposition'], 'current_disposition': disposition})
        assert not counts.get('unmerged')
        summaries.append({
            'snapshot': label, 'source_record': '../intake/' + name,
            'source_record_sha256': digest(path.read_bytes()),
            'captured_ref_count': len(data['refs']),
            'previous_counts': data['counts'], 'current_counts': dict(counts),
            'equivalence_proof_kinds': dict(Counter(x['kind'] for x in proofs.values())),
        })
    return {
        'schema': 1, 'verified_head': head,
        'verified_tree': git(repo, 'rev-parse', head + '^{tree}'),
        'snapshots': summaries, 'resolved_deferred_refs': resolved,
        'resolution': 'PR336 typography completed and reached main aa861c28; both aliases of its previously captured draft commit are now ancestors of the integrated source checkpoint.',
        'boundary': 'Replays the unchanged historical 383-ref and 386-ref inputs. This is not an unbounded new remote scan, and no earlier snapshot or disposition record is rewritten.',
    }


def verify(index_path, repo=None):
    base = index_path.parent
    index = json.loads(index_path.read_text())
    prior = (base / index['previous_package']['index']).resolve()
    assert digest(prior.read_bytes()) == index['previous_package']['index_sha256']
    helpers = runpy.run_path(str(prior.with_name('verify_evidence.py')))
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        helpers['verify'](prior, repo)
    previous_summary = json.loads(captured.getvalue())
    for item in index['files'] + index['external_files']:
        raw = (base / item['path']).read_bytes()
        assert len(raw) == item['size'] and digest(raw) == item['sha256'], item['path']
    frozen = runpy.run_path(str(base.parent / 'evidence/verify_evidence.py'))
    archives = {}
    for item in index['archives']:
        order = item.get('sort_order', 'lexical')
        archives[item['path']] = helpers['archive_members'](
            base, item, lambda members: frozen['repack'](members, order))
    members = archives['evidence.tar.gz']
    accounting = derive_accounting(base)
    assert accounting == json.loads((base / 'case-accounting.json').read_text())
    continuity = json.loads((base / 'source-continuity.json').read_text())
    def read(name):
        return json.loads(members[PREFIX + name])
    receipt = read('renderer/receipt.json')
    final = read('renderer-final-receipt.json')
    assert receipt['accepted'] and receipt['exit_code'] == 0
    assert receipt['passed'] == accounting['final_main_accepted_executions']
    assert receipt['failed'] == receipt['skipped'] == receipt['stderr_bytes'] == 0
    for key in ('errors', 'raw_background_error_markers', 'source_changes', 'non_json_output'):
        assert receipt[key] == []
    assert receipt['runner_done'][-1]['success'] is True
    assert receipt['source_tree'] == receipt['source_tree_after'] == continuity['final_source']['tree']
    assert final['source_tree'] == receipt['source_tree']
    assert final['repository_edits_during_qualification'] is False
    manifest = read('renderer/source-before.json')
    assert manifest == read('renderer/source-after.json')
    assert len(manifest) == receipt['source_files'] == final['source_manifest_count']
    assert digest(members[PREFIX + 'renderer/source-before.json']) == continuity['accepted_input_manifest']['sha256']
    assert not members[PREFIX + 'renderer/stderr.log']
    expected_cases = accounting['repeated_final_main_cases'] + accounting['additional_final_main_cases']
    assert {(x['suite'], x['name']) for x in final['passed_identities']} == {
        (x['suite'], x['name']) for x in expected_cases}
    for path, expected in final['key_source_sha256'].items():
        assert digest(members[PREFIX + 'renderer/source/' + path]) == manifest[path] == expected
    checks = read('renderer-static/receipt.json')
    assert {check['name'] for check in checks} == {'format', 'analyze', 'diff-check'}
    for check in checks:
        assert check['accepted'] and check['exit_code'] == 0
        assert check['source_before'] == check['source_after']
        for path, value in check['source_before'].items():
            assert manifest['packages/quds_office_editor/' + path] == value
    converter = json.loads((base / 'converter-summary.json').read_text())
    assert converter['success'] is True and converter['failures'] == []
    assert converter['remote_equivalent_commit'] == continuity['final_source']['remote_commit']
    assert converter['source_tree'] == continuity['final_source']['tree']
    assert converter['gate_dart_commands'] == 3 and converter['actual_host_save_commands'] == 1
    assert converter['roundtrip_matched'] and converter['image_three_native_cycles_matched']
    converter_members = archives['converter.tar.gz']
    converter_before = next(json.loads(raw) for name, raw in converter_members.items()
                            if name.endswith('/source-before.json'))
    converter_after = next(json.loads(raw) for name, raw in converter_members.items()
                           if name.endswith('/source-after.json'))
    assert converter_before == converter_after
    assert len(converter_before['files']) == converter['source_file_count']
    review = read('incoming-word-review.json')
    incoming_root = base.parent.parent / 'word-vba-typography-20261121'
    incoming_manifest = json.loads((incoming_root / 'archive-manifest.json').read_text())
    with tarfile.open(incoming_root / 'execution.tar.gz', 'r:gz') as incoming:
        assert set(incoming.getnames()) == set(incoming_manifest['files']) | {'manifest.json'}
        for name, item in incoming_manifest['files'].items():
            raw = incoming.extractfile(name).read()
            assert len(raw) == item['bytes'] and digest(raw) == item['sha256']
        assert digest(incoming.extractfile('manifest.json').read()) == incoming_manifest['embedded_manifest_sha256']
        for gate in review['gates'].values():
            for phase in ('before', 'after'):
                ref = gate[phase]
                raw = incoming.extractfile(ref['member']).read()
                assert len(raw) == ref['bytes'] and digest(raw) == ref['sha256']
                snapshot = json.loads(raw)
                comparison = gate[phase + '_comparison']
                differences = {x['path']: x for x in comparison['tracked_differences']}
                runtime = set(comparison['untracked_runtime_paths'])
                for path, value in snapshot.items():
                    if path in runtime:
                        continue
                    expected = differences.get(path, {}).get('accepted_main_sha256', value)
                    if path in manifest:
                        assert manifest[path] == expected, path
                    elif repo:
                        raw_blob = subprocess.check_output(['git', '-C', str(repo), 'show',
                            continuity['final_source']['remote_commit'] + ':' + path])
                        assert digest(raw_blob) == expected, path
    git_count = helpers['verify_git'](repo, continuity, manifest) if repo else None
    if repo:
        for item in continuity['incoming_source_object_bindings']:
            for commit in (continuity['accepted_main'], continuity['final_source']['remote_commit']):
                assert git(repo, 'rev-parse', commit + ':' + item['path']) == item['git_object']
        converter_continuity = dict(continuity)
        converter_continuity['accepted_input_manifest'] = dict(continuity['accepted_input_manifest'])
        converter_continuity['accepted_input_manifest']['git_blob_entries'] = converter['source_file_count'] - 1
        assert helpers['verify_git'](repo, converter_continuity, converter_before['files']) == converter['source_file_count'] - 1
        actual_intake = derive_intake(repo, base, continuity['final_source']['remote_commit'])
        assert actual_intake == json.loads((base / 'intake.json').read_text())
    print(json.dumps({
        'previous_package': previous_summary,
        'archives_verified': len(archives),
        'archive_members_verified': sum(len(x) for x in archives.values()),
        'standalone_files_verified': len(index['files']),
        'supplemental_incoming_files_verified': len(index['external_files']),
        'supplemental_incoming_archive_members_verified': len(incoming_manifest['files']) + 1,
        'deterministic_repacking': 'passed',
        'final_main_accepted_cases': accounting['final_main_accepted_executions'],
        'repeated_cases_excluded': accounting['final_main_repeated_cases'],
        'additional_cases': accounting['final_main_additional_cases'],
        'distinct_accepted_cases': accounting['distinct_accepted_cases'],
        'unchanged_execution_manifest_entries': len(manifest),
        'git_source_blob_bindings_verified': git_count,
        'converter_source_manifest_entries': converter['source_file_count'],
        'converter_dart_commands': converter['gate_dart_commands'],
        'converter_host_saves': converter['actual_host_save_commands'],
        'intake_replayed': bool(repo),
        'source_checkpoint': continuity['final_source']['remote_commit'],
    }))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, default=Path(__file__).with_name('index.json'))
    parser.add_argument('--repo', type=Path)
    args = parser.parse_args()
    verify(args.index.resolve(), args.repo.resolve() if args.repo else None)
