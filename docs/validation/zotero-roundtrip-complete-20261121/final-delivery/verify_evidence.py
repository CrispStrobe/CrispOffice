#!/usr/bin/env python3
"""Verify the separate final-delivery evidence and deduplicated accepted cases.

Uses only the Python standard library. Pass --repo to additionally bind all
tracked accepted-run inputs to the recorded remote Git source checkpoint.
Earlier evidence is read and verified without modifying its frozen index.
"""
import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import runpy
import subprocess
import tarfile


EVENT_MEMBER = 'validation/page-text-final/green-final/events.jsonl'
PREFIX = 'validation/page-text-final/'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def identities(keys):
    return [{'suite': path, 'name': name} for path, name in sorted(keys)]


def identity_digest(keys):
    return digest(json.dumps(sorted(keys), separators=(',', ':'),
                             ensure_ascii=False).encode())


def derive_accounting(base):
    frozen = base.parent / 'evidence'
    module = runpy.run_path(str(frozen / 'scripts/account_cases.py'))
    previous = {name: module['case_keys'](frozen, source)
                for name, source in module['SOURCES'].items()}
    baseline = set().union(*previous.values())
    current = module['case_keys'](base, ('evidence.tar.gz', EVENT_MEMBER))
    scopes = {
        'engine': previous['engine'],
        'editor_distinct': previous['editor'] | previous['renderer'] | current,
        'studio_zotero': previous['studio_zotero'],
        'mail_core': previous['mail_core'],
        'mail_store': previous['mail_store'],
        'mail_studio': previous['mail_studio'],
    }
    combined = set()
    for name, keys in scopes.items():
        assert not combined & keys, (name, 'overlap between scopes')
        combined |= keys
    return {
        'schema': 1,
        'identity': ['repository-relative suite path', 'test name'],
        'frozen_distinct_accepted_cases': len(baseline),
        'followup_accepted_executions': len(current),
        'followup_repeated_cases': len(baseline & current),
        'followup_additional_cases': len(current - baseline),
        'distinct_accepted_cases': len(combined),
        'distinct_editor_cases': len(scopes['editor_distinct']),
        'final_nonoverlapping_scope_counts': {
            name: len(keys) for name, keys in scopes.items()},
        'final_scope_identity_sha256': {
            name: identity_digest(keys) for name, keys in scopes.items()},
        'all_distinct_identity_sha256': identity_digest(combined),
        'repeated_followup_cases': identities(baseline & current),
        'additional_followup_cases': identities(current - baseline),
        'raw_event_sources': {
            'frozen': '../evidence/case-accounting.json',
            'followup': {'archive': 'evidence.tar.gz', 'member': EVENT_MEMBER},
        },
        'counting_policy': (
            'Union of accepted suite/name identities across recorded source '
            'checkpoints; not a single whole-suite run on the final tree. '
            'The earlier frozen exclusions remain excluded. The red attempt, '
            'rejected green attempt and all repeated followup cases add zero.'),
        'followup_attempts_excluded_entirely': [
            {'phase': 'red', 'passed': 0, 'failed': 1, 'exit_code': 1},
            {'phase': 'green', 'passed': 31, 'failed': 2, 'exit_code': 1},
        ],
    }


def archive_members(base, record, repack):
    data = (base / record['path']).read_bytes()
    assert len(data) == record['size'] and digest(data) == record['sha256']
    expected = {item['path']: item for item in record['members']}
    assert len(expected) == len(record['members']), 'Duplicate indexed member'
    actual = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        for member in archive.getmembers():
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and '..' not in path.parts
            assert member.isfile() and member.name not in actual
            assert member.name in expected, member.name
            raw = archive.extractfile(member).read()
            item = expected[member.name]
            assert len(raw) == item['size'] and digest(raw) == item['sha256']
            actual[member.name] = raw
    assert set(actual) == set(expected)
    assert repack(actual) == data, 'Archive is not reproducible byte for byte'
    return actual


def verify_receipts(members, continuity, accounting):
    def read(path):
        return json.loads(members[PREFIX + path])

    final = read('final-receipt.json')
    receipt = read('green-final/receipt.json')
    assert receipt['accepted'] and receipt['exit_code'] == 0
    assert receipt['passed'] == accounting['followup_accepted_executions']
    assert receipt['failed'] == receipt['skipped'] == receipt['stderr_bytes'] == 0
    for key in ('errors', 'raw_background_error_markers', 'source_changes',
                'non_json_output'):
        assert receipt[key] == [], key
    assert receipt['runner_done'][-1]['success'] is True
    assert not members[PREFIX + 'green-final/stderr.log']
    assert final['status'] == 'accepted'
    assert final['source_commit'] == receipt['source_commit']
    assert final['source_tree'] == receipt['source_tree']
    assert receipt['source_commit'] == continuity['execution']['head_commit']
    assert receipt['source_tree'] == continuity['execution']['head_tree']
    before = read('green-final/source-before.json')
    assert before == read('green-final/source-after.json')
    assert len(before) == receipt['source_files'] == final['source_manifest_count']
    assert len(before) == continuity['accepted_input_manifest']['total_entries']
    assert digest(members[PREFIX + 'green-final/source-before.json']) == (
        continuity['accepted_input_manifest']['sha256'])
    expected_cases = (accounting['repeated_followup_cases']
                      + accounting['additional_followup_cases'])
    assert {(x['suite'], x['name']) for x in final['passed_identities']} == {
        (x['suite'], x['name']) for x in expected_cases}
    for binding in continuity['accepted_source_bindings']:
        path = binding['path']
        expected = binding['sha256']
        assert digest(members[PREFIX + 'green-final/source/' + path]) == expected
        assert before[path] == expected == final['working_source_sha256'][path]
    checks = read('static-final/receipt.json')
    assert {check['name'] for check in checks} == {'format', 'analyze', 'diff-check'}
    for check in checks:
        assert check['accepted'] and check['exit_code'] == 0
        assert check['source_before'] == check['source_after']
        for path, value in check['source_before'].items():
            assert before['packages/quds_office_editor/' + path] == value
    for excluded in accounting['followup_attempts_excluded_entirely']:
        rejected = read(excluded['phase'] + '/receipt.json')
        assert rejected['accepted'] is False
        for key in ('passed', 'failed', 'exit_code'):
            assert rejected[key] == excluded[key]
    return before


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def verify_git(repo, continuity, manifest):
    for checkpoint in continuity['checkpoints']:
        assert git(repo, 'rev-parse', checkpoint['remote_commit'] + '^{tree}').decode().strip() == checkpoint['tree']
    final = continuity['final_source']['remote_commit']
    for item in continuity['unchanged_scopes_from_frozen_source']:
        for commit in (continuity['frozen_source_checkpoint'], final):
            assert git(repo, 'rev-parse', commit + ':' + item['path']).decode().strip() == item['git_object']
    for item in continuity['ancestry']:
        subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor',
                        item['ancestor'], item['descendant']], check=True)
    tree = {}
    for entry in git(repo, 'ls-tree', '-rz', '--full-tree', final).split(b'\0'):
        if entry:
            info, path = entry.split(b'\t', 1)
            tree[path.decode()] = info.split()[2].decode()
    paths = sorted(path for path in manifest if path in tree)
    missing = sorted(set(manifest) - set(paths))
    assert missing == [x['path'] for x in continuity['accepted_input_manifest']['runtime_only_inputs']]
    assert len(paths) == continuity['accepted_input_manifest']['git_blob_entries']
    objects = '\n'.join(tree[path] for path in paths) + '\n'
    raw = subprocess.check_output(['git', '-C', str(repo), 'cat-file', '--batch'],
                                  input=objects.encode())
    position = 0
    for path in paths:
        end = raw.index(b'\n', position)
        header = raw[position:end].split()
        assert header[1] == b'blob', path
        size = int(header[2])
        position = end + 1
        payload = raw[position:position + size]
        position += size + 1
        assert digest(payload) == manifest[path], path
    for comparison in continuity['source_deltas']:
        actual = git(repo, 'diff', '--name-only', comparison['from'],
                     comparison['to'], '--', 'packages/**/*.dart',
                     'third_party/**/*.dart').decode().splitlines()
        assert actual == comparison['dart_paths'], comparison
    return len(paths)


def verify(index_path, repo=None):
    base = index_path.parent
    index = json.loads(index_path.read_text())
    frozen = (base / index['frozen_evidence']['index']).resolve()
    assert digest(frozen.read_bytes()) == index['frozen_evidence']['index_sha256']
    module = runpy.run_path(str(frozen.with_name('verify_evidence.py')))
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        module['verify'](frozen)
    frozen_summary = json.loads(captured.getvalue())
    for item in index['files']:
        data = (base / item['path']).read_bytes()
        assert len(data) == item['size'] and digest(data) == item['sha256'], item['path']
    members = archive_members(base, index['archive'], module['repack'])
    accounting = derive_accounting(base)
    assert accounting == json.loads((base / 'case-accounting.json').read_text())
    continuity = json.loads((base / 'source-continuity.json').read_text())
    manifest = verify_receipts(members, continuity, accounting)
    git_count = verify_git(repo, continuity, manifest) if repo else None
    print(json.dumps({
        'frozen_package': frozen_summary,
        'followup_archive_members_verified': len(members),
        'followup_standalone_files_verified': len(index['files']),
        'deterministic_repacking': 'passed',
        'accepted_followup_cases': accounting['followup_accepted_executions'],
        'repeated_cases_excluded': accounting['followup_repeated_cases'],
        'additional_cases': accounting['followup_additional_cases'],
        'distinct_accepted_cases': accounting['distinct_accepted_cases'],
        'unchanged_execution_manifest_entries': len(manifest),
        'git_source_blob_bindings_verified': git_count,
        'source_checkpoint': continuity['final_source']['remote_commit'],
    }))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, default=Path(__file__).with_name('index.json'))
    parser.add_argument('--repo', type=Path, help='Git clone containing the recorded remote checkpoints')
    arguments = parser.parse_args()
    verify(arguments.index.resolve(), arguments.repo.resolve() if arguments.repo else None)
