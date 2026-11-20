#!/usr/bin/env python3
"""Replay the frozen fork/upstream source inventory without network or Git writes.

For a new capture, the caller obtains a complete paginated API snapshot and
fetches its objects first. Pass --capture --snapshot <file> --target <commit>.
The checker copies that snapshot and writes intake.json, but never changes refs.
Unknown or unavailable heads fail coverage. Runtime validation is separate.
"""

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


PROOF_PATH = 'docs/validation/word-vba-list-levels-20261120/final-intake.json'
PARTIAL_HEAD = 'c34945761e7991f5fe49037d79529acdd260b31c'
CATEGORIES = (
    'fork_branches',
    'fork_pull_requests',
    'upstream_branches',
    'upstream_pull_requests',
)
REPOSITORY = 'CrispStrobe/quds_office_suite'
UPSTREAM = 'MohammedAsaadAsaad/quds_office_suite'
SHA = re.compile(r'[0-9a-f]{40}')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--target', help='Commit to check; defaults to HEAD for capture')
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--snapshot', type=Path, help='Complete API ref snapshot, for capture')
    parser.add_argument('--output-dir', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    require(args.capture == (args.snapshot is not None),
            '--capture and --snapshot must be supplied together')
    repo, out = args.repo.resolve(), args.output_dir.resolve()
    env = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_TERMINAL_PROMPT='0')

    def run_git(*arguments):
        return subprocess.run(['git', '-C', str(repo), *arguments],
                              env=env, capture_output=True)

    def git(*arguments):
        result = run_git(*arguments)
        require(result.returncode == 0, result.stderr.decode(errors='replace'))
        return result.stdout

    report_path = out / 'intake.json'
    snapshot_path = out / 'remote-refs.json'
    previous = None if args.capture else json.loads(report_path.read_text())
    snapshot_bytes = (args.snapshot if args.capture else snapshot_path).read_bytes()
    snapshot = json.loads(snapshot_bytes)
    require(snapshot['schema'] == 'quds-mail-api-ref-snapshot/v1',
            'Unsupported remote snapshot schema')
    require(snapshot['repository'] == REPOSITORY and snapshot['upstream'] == UPSTREAM,
            'Unexpected fork/upstream repository')
    require(snapshot['github_actions'] == 'NOT QUERIED OR AWAITED',
            'Snapshot must document the requested CI exclusion')
    refs = snapshot['captured_refs']
    require(set(refs) == set(CATEGORIES), 'Incomplete or unknown source categories')
    for category in CATEGORIES:
        require(bool(refs[category]), 'Missing remote inventory: ' + category)
        require(all(isinstance(name, str) and name and isinstance(head, str)
                    and SHA.fullmatch(head) for name, head in refs[category].items()),
                'Invalid captured head: ' + category)
        pages = snapshot['pagination'][category]
        require(bool(pages) and all(isinstance(size, int) and 0 <= size <= 100
                                   for size in pages) and pages[-1] < 100,
                'Pagination did not reach its final page: ' + category)
        require(sum(pages) == len(refs[category]),
                'Pagination count does not match unique inventory: ' + category)

    target_input = args.target or ('HEAD' if args.capture else previous['target_commit'])
    target = git('rev-parse', target_input + '^{commit}').decode().strip()
    ancestry = {}
    unavailable = {}

    def ancestor(head):
        if head not in ancestry:
            result = run_git('merge-base', '--is-ancestor', head, target)
            if result.returncode not in (0, 1):
                unavailable[head] = 'Commit or ancestry object unavailable locally'
                ancestry[head] = False
            else:
                ancestry[head] = result.returncode == 0
        return ancestry[head]

    def tree(commit):
        entries = {}
        for row in git('ls-tree', '-r', '-z', commit).split(b'\0'):
            if row:
                metadata, name = row.split(b'\t', 1)
                entries[name.decode()] = metadata.decode().split()
        return entries

    proof_bytes = git('show', target + ':' + PROOF_PATH)
    proof_rows = json.loads(proof_bytes)['historical_equivalence_proofs']
    require(len(proof_rows) == 14, 'Unexpected historical replacement inventory')
    proofs = {}
    for row in proof_rows:
        old, accepted = row['historical_head'], row['accepted_ancestor']
        require(old not in proofs, 'Duplicate historical replacement: ' + old)
        require(ancestor(accepted), 'Replacement is not a verified ancestor: ' + old)
        changed = [path for path in git(
            'diff', '--name-only', '-z', row['comparison_base'], old,
        ).decode().split('\0') if path]
        old_entries, accepted_entries = tree(old), tree(accepted)
        require(set(changed) == {entry['path'] for entry in row['entries']},
                'Historical changed-path inventory differs: ' + old)
        require(len(changed) == row['changed_path_count'], 'Path count differs: ' + old)
        require(all(old_entries.get(path) == accepted_entries.get(path) for path in changed),
                'Historical mode/type/object differs: ' + old)
        for entry in row['entries']:
            path = entry['path']
            for label, entries in (('historical', old_entries), ('accepted', accepted_entries)):
                actual = (' '.join(entries[path]) + '\t' + path) if path in entries else ''
                require(actual == entry[label + '_mode_type_object'],
                        'Recorded historical object differs: ' + old + ':' + path)
        old_tree = git('rev-parse', old + '^{tree}').decode().strip()
        accepted_tree = git('rev-parse', accepted + '^{tree}').decode().strip()
        require(old_tree == row['historical_tree'] and accepted_tree == row['accepted_tree'],
                'Recorded tree identity differs: ' + old)
        equal = old_tree == accepted_tree
        require(equal or (old == PARTIAL_HEAD and len(changed) == 37),
                'Unexpected partial-tree substitute: ' + old)
        proofs[old] = dict(replacement=accepted, changed_paths=len(changed),
                           full_tree_equal=equal, exact_changed_paths=True)

    counts, uncovered, missing = {}, {}, {}
    for category in CATEGORIES:
        states = Counter()
        for name, head in refs[category].items():
            if ancestor(head):
                disposition = 'ancestor'
            elif head in unavailable:
                disposition = 'missing_object'
                missing[category + '/' + name] = head
            elif head in proofs:
                disposition = 'equivalent'
            else:
                disposition = 'uncovered'
            states[disposition] += 1
            if disposition in ('uncovered', 'missing_object'):
                uncovered[category + '/' + name] = head
        counts[category] = dict(states)

    result = dict(
        schema='quds-mail-source-intake/v2',
        status='PASS' if not uncovered else 'FAIL',
        captured_at_utc=snapshot['captured_at_utc'],
        repository=REPOSITORY, upstream=UPSTREAM,
        target_commit=target,
        target_tree=git('rev-parse', target + '^{tree}').decode().strip(),
        scope=('Source inclusion for an explicit frozen API inventory. '
               'Ancestry does not assert that overlapping implementations were retained '
               'unchanged, nor qualify runtime behavior. See intake.md for reconciliation.'),
        counts=counts, uncovered=uncovered, missing_objects=missing,
        captured_refs=refs,
        inventory_sha256=digest(json.dumps(refs, sort_keys=True).encode()),
        remote_snapshot_file=snapshot_path.name,
        remote_snapshot_sha256=digest(snapshot_bytes),
        pagination=snapshot['pagination'],
        historical_proof_source=PROOF_PATH,
        historical_proof_sha256=digest(proof_bytes),
        recomputed_equivalence=proofs,
        github_actions='NOT QUERIED OR AWAITED',
        git_network_access='DISABLED: GIT_NO_LAZY_FETCH=1; no fetch or network commands',
    )
    if args.capture:
        out.mkdir(parents=True, exist_ok=True)
        snapshot_path.write_bytes(snapshot_bytes)
        report_path.write_text(json.dumps(result, indent=2) + '\n')
    else:
        require(result == previous, 'Replayed intake differs from the committed result')
    print(json.dumps(dict(status=result['status'], target=target, counts=counts,
                          historical_proofs=len(proofs), uncovered=len(uncovered),
                          missing_objects=len(missing))))
    return 1 if uncovered else 0


if __name__ == '__main__':
    raise SystemExit(main())
