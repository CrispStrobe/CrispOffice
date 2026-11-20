#!/usr/bin/env python3
"""Audit one frozen Quds fork/upstream inventory using local immutable Git objects."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--target', default='HEAD')
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--artifact-prefix', choices=('', 'final-'), default='')
    args = parser.parse_args()
    env = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_TERMINAL_PROMPT='0')

    def run(*argv):
        return subprocess.run(['git', '-C', str(args.repo), *argv],
                              env=env, capture_output=True)

    def git(*argv):
        result = run(*argv)
        if result.returncode:
            raise ValueError(result.stderr.decode(errors='replace'))
        return result.stdout

    def sha(value):
        return git('rev-parse', value).decode().strip()

    target = sha(args.target + '^{commit}')
    snapshot_bytes = args.snapshot.read_bytes()
    snapshot = json.loads(snapshot_bytes)
    categories = ('fork_branches', 'fork_pull_requests',
                  'upstream_branches', 'upstream_pull_requests')
    assert set(snapshot['captured_refs']) == set(categories)
    assert snapshot['github_actions'] == 'NOT QUERIED OR AWAITED'
    for category in categories:
        pages = snapshot['pagination'][category]
        assert pages[-1] < 100
        assert sum(pages) == len(snapshot['captured_refs'][category])

    cache = {}

    def ancestor(head):
        if head not in cache:
            result = run('merge-base', '--is-ancestor', head, target)
            if result.returncode not in (0, 1):
                raise ValueError('Unavailable ancestry object: ' + head)
            cache[head] = result.returncode == 0
        return cache[head]

    trees = {}

    def tree(commit):
        if commit not in trees:
            rows = {}
            for row in git('ls-tree', '-r', '-z', commit).split(b'\0'):
                if row:
                    metadata, name = row.split(b'\t', 1)
                    rows[name.decode()] = metadata.decode()
            trees[commit] = rows
        return trees[commit]

    def changed(base, head):
        return [p for p in git('diff', '--name-only', '-z', base, head).decode().split('\0') if p]

    proof_path = 'docs/validation/word-vba-list-levels-20261120/final-intake.json'
    proof_bytes = git('show', target + ':' + proof_path)
    historical = json.loads(proof_bytes)['historical_equivalence_proofs']
    assert len(historical) == 14
    proofs = {}
    for row in historical:
        old, accepted = row['historical_head'], row['accepted_ancestor']
        assert ancestor(accepted), old
        paths = changed(row['comparison_base'], old)
        assert set(paths) == {e['path'] for e in row['entries']}
        assert len(paths) == row['changed_path_count']
        before, after = tree(old), tree(accepted)
        entries = []
        for entry in row['entries']:
            path = entry['path']
            assert before.get(path) == after.get(path), path
            for label, mapping in (('historical', before), ('accepted', after)):
                actual = mapping[path] + '\t' + path if path in mapping else ''
                assert actual == entry[label + '_mode_type_object'], path
            entries.append({'path': path, 'mode_type_object': before.get(path)})
        old_tree, accepted_tree = sha(old + '^{tree}'), sha(accepted + '^{tree}')
        assert old_tree == row['historical_tree']
        assert accepted_tree == row['accepted_tree']
        assert old_tree == accepted_tree or (old == 'c34945761e7991f5fe49037d79529acdd260b31c' and len(paths) == 37)
        proofs[old] = {
            'replacement': accepted, 'replacement_is_ancestor': True,
            'comparison_base': row['comparison_base'],
            'changed_path_count': len(paths),
            'historical_tree': old_tree, 'accepted_tree': accepted_tree,
            'full_tree_equal': old_tree == accepted_tree,
            'exact_changed_paths': True,
            'proof_source': proof_path,
        }

    old = 'ec70b9423febefcb9b104629d2ad48b0c96e9082'
    accepted = 'e975cec13b289fe067ef406cd3044701ecc44744'
    old_base, accepted_base = sha(old + '^'), sha(accepted + '^')
    paths = changed(old_base, old)
    assert len(paths) == 3 and paths == changed(accepted_base, accepted)
    assert ancestor(accepted)
    assert git('diff', '--binary', old_base, old) == git('diff', '--binary', accepted_base, accepted)
    entries = []
    for path in paths:
        assert tree(old_base).get(path) == tree(accepted_base).get(path)
        assert tree(old).get(path) == tree(accepted).get(path)
        entries.append({'path': path, 'before_mode_type_object': tree(old_base).get(path),
                        'after_mode_type_object': tree(old).get(path)})
    proofs[old] = {
        'replacement': accepted, 'replacement_is_ancestor': True,
        'comparison_base': old_base, 'replacement_base': accepted_base,
        'changed_path_count': len(paths), 'exact_changed_paths': True,
        'before_and_after_entries_equal': True, 'binary_git_diff_equal': True,
        'patch_sha256': digest(git('diff', '--binary', old_base, old)),
        'historical_tree': sha(old + '^{tree}'), 'accepted_tree': sha(accepted + '^{tree}'),
        'full_tree_equal': sha(old + '^{tree}') == sha(accepted + '^{tree}'),
        'entries': entries,
    }

    old = '37148e37736a4134bba1d3c07b0ad847c2e1447d'
    accepted = 'e219e25772a109f7e1edc9af3608dcd6b92de5a6'
    assert ancestor(accepted)
    old_tree, accepted_tree = sha(old + '^{tree}'), sha(accepted + '^{tree}')
    assert old_tree == accepted_tree
    assert not git('diff', '--name-only', old, accepted)
    proofs[old] = {
        'replacement': accepted, 'replacement_is_ancestor': True,
        'historical_tree': old_tree, 'accepted_tree': accepted_tree,
        'full_tree_equal': True, 'exact_changed_paths': True,
        'reason': 'Concurrent merges of the same PR277 and main heads produced identical complete trees.',
    }

    counts, uncovered, missing, dispositions = {}, {}, {}, {}
    for category in categories:
        counts[category] = Counter()
        for name, head in snapshot['captured_refs'][category].items():
            key = category + '/' + name
            if run('cat-file', '-e', head + '^{commit}').returncode:
                disposition = 'missing_object'
                missing[key] = head
            elif ancestor(head):
                disposition = 'ancestor'
            elif head in proofs:
                disposition = 'equivalent'
            else:
                disposition = 'uncovered'
            counts[category][disposition] += 1
            dispositions[key] = {'sha': head, 'disposition': disposition}
            if disposition in ('uncovered', 'missing_object'):
                uncovered[key] = head
    temporary = '.github/workflows/tmp-regenerate-editor-goldens.yml'
    assert temporary not in tree(target), 'Retired temporary workflow was restored'
    result = {
        'schema': 'quds-mail-command-journal-source-intake/v1',
        'status': 'PASS' if not uncovered else 'FAIL',
        'captured_at_utc': snapshot['captured_at_utc'],
        'target_commit': target, 'target_tree': sha(target + '^{tree}'),
        'scope': 'Frozen source inclusion; ancestry does not certify retention of every overlapping line or runtime behavior.',
        'counts': {k: dict(v) for k, v in counts.items()},
        'uncovered': uncovered, 'missing_objects': missing,
        'remote_snapshot_file': args.artifact_prefix + 'remote-refs.json',
        'remote_snapshot_sha256': digest(snapshot_bytes),
        'historical_proof_source': proof_path,
        'historical_proof_sha256': digest(proof_bytes),
        'recomputed_equivalence': proofs,
        'dispositions': dispositions,
        'temporary_golden_workflow_absent': True,
        'github_actions': 'NOT QUERIED OR AWAITED',
        'git_network_access': 'DISABLED: GIT_NO_LAZY_FETCH=1; no fetch or network commands',
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / (args.artifact_prefix + 'remote-refs.json')).write_bytes(snapshot_bytes)
    (args.output_dir / (args.artifact_prefix + 'intake.json')).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'target': target, 'counts': result['counts'],
                      'proofs': len(proofs), 'uncovered': uncovered, 'missing': missing}))
    return int(bool(uncovered))


if __name__ == '__main__':
    raise SystemExit(main())
