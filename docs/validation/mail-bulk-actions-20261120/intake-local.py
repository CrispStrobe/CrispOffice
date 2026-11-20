#!/usr/bin/env python3
"""Capture/replay independent source inclusion from dedicated fetched refs.

Fetch fork/upstream branches and PR heads into refs/audit-bulk first. This
checker never changes refs and never reads GitHub Actions or status endpoints.
Without --capture it verifies the frozen report without rewriting evidence.
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess


NAMESPACES = {
    'fork_branches': 'refs/audit-bulk/fork/heads/',
    'fork_pull_requests': 'refs/audit-bulk/fork/pull/',
    'upstream_branches': 'refs/audit-bulk/upstream/heads/',
    'upstream_pull_requests': 'refs/audit-bulk/upstream/pull/',
}
PROOF_PATH = 'docs/validation/word-vba-list-levels-20261120/final-intake.json'
PRIOR_PATH = 'docs/validation/mail-bulk-actions-20261120/intake.json'
PARTIAL_HEAD = 'c34945761e7991f5fe49037d79529acdd260b31c'
BASE = 'c954d00d2fc85604ae394674bca91ea8a1dede0e'
WIP = '332d7b26a320ca560f4f2214e1e63da9392269ab'
MERGE = '4d9cddeea2608ac1d7a8f1acfdd5ecc1482f5114'
RETIRED = '.github/workflows/tmp-regenerate-editor-goldens.yml'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path,
                        default=Path(__file__).resolve().parents[3])
    parser.add_argument('--target')
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--report-prefix', default='intake-local')
    args = parser.parse_args()
    if not re.fullmatch(r'intake-local(?:-[a-z0-9]+)*', args.report_prefix):
        parser.error('report-prefix must start with intake-local')
    repo = args.repo.resolve()
    out = Path(__file__).resolve().parent
    report_path = out / (args.report_prefix + '.json')
    previous = None if args.capture else json.loads(report_path.read_text())

    def git(*values):
        return subprocess.check_output(['git', '-C', str(repo), *values])

    def require(condition, message):
        if not condition:
            raise ValueError(message)

    target = git('rev-parse', (args.target or (
        'HEAD' if args.capture else previous['target_commit'])) + '^{commit}')
    target = target.decode().strip()
    ancestry = {}

    def ancestor(head):
        if head not in ancestry:
            process = subprocess.run(
                ['git', '-C', str(repo), 'merge-base', '--is-ancestor', head, target],
                capture_output=True,
            )
            require(process.returncode in (0, 1), process.stderr.decode())
            ancestry[head] = process.returncode == 0
        return ancestry[head]

    def tree(commit):
        entries = {}
        for row in git('ls-tree', '-r', '-z', commit).split(b'\0'):
            if row:
                metadata, path = row.split(b'\t', 1)
                entries[path.decode()] = metadata.decode().split()
        return entries

    def tree_id(commit):
        return git('rev-parse', commit + '^{tree}').decode().strip()

    proof_bytes = git('show', target + ':' + PROOF_PATH)
    proof_rows = json.loads(proof_bytes)['historical_equivalence_proofs']
    proofs = {}
    for row in proof_rows:
        old, accepted = row['historical_head'], row['accepted_ancestor']
        changed = [name for name in git(
            'diff', '--name-only', '-z', row['comparison_base'], old,
        ).decode().split('\0') if name]
        old_entries, accepted_entries = tree(old), tree(accepted)
        require(ancestor(accepted), 'Replacement is not an ancestor: ' + old)
        require(set(changed) == {entry['path'] for entry in row['entries']},
                'Historical changed-path inventory differs: ' + old)
        require(len(changed) == row['changed_path_count'],
                'Historical changed-path count differs: ' + old)
        require(all(old_entries.get(path) == accepted_entries.get(path)
                    for path in changed), 'Historical mode/type/object differs: ' + old)
        old_tree, accepted_tree = tree_id(old), tree_id(accepted)
        equal = old_tree == accepted_tree
        require(equal or (old == PARTIAL_HEAD and len(changed) == 37),
                'Unexpected partial replacement: ' + old)
        proofs[old] = dict(
            replacement=accepted, comparison_base=row['comparison_base'],
            old_tree=old_tree, replacement_tree=accepted_tree,
            changed_paths=changed, full_tree_equal=equal,
            exact_mode_type_object_match=True, replacement_is_ancestor=True,
        )
    require(len(proofs) == 14, 'Historical proof set changed unexpectedly')

    if args.capture:
        refs = {category: {} for category in NAMESPACES}
        raw = git('for-each-ref', '--format=%(refname) %(objectname) %(symref)',
                  *NAMESPACES.values()).decode()
        for row in raw.splitlines():
            fields = row.split()
            if len(fields) != 2:
                continue
            ref, head = fields
            for category, prefix in NAMESPACES.items():
                if ref.startswith(prefix):
                    refs[category][ref[len(prefix):]] = head
                    break
        require(all(refs.values()), 'Missing fetched fork/upstream branch or PR refs')
    else:
        refs = previous['captured_refs']

    def classify(snapshot):
        counts, uncovered = {}, {}
        for category, names in snapshot.items():
            states = Counter()
            for name, head in names.items():
                state = ('ancestor' if ancestor(head) else
                         'equivalent' if head in proofs else 'uncovered')
                states[state] += 1
                if state == 'uncovered':
                    uncovered[category + '/' + name] = head
            counts[category] = dict(states)
        return counts, uncovered

    counts, uncovered = classify(refs)
    prior_bytes = git('show', target + ':' + PRIOR_PATH)
    prior = json.loads(prior_bytes)
    prior_counts, prior_uncovered = classify(prior['captured_refs'])
    merge_parents = git('rev-list', '--parents', '-n', '1', MERGE).decode().split()[1:]
    require(merge_parents == [BASE, WIP], 'Reconciliation parents differ')
    require(ancestor(MERGE), 'History-preserving reconciliation is not incorporated')
    require(tree_id(MERGE) == tree_id(BASE), 'Reconciliation changed main tree')
    require(not git('ls-tree', MERGE, RETIRED), 'Retired workflow was restored')

    result = dict(
        schema='quds-mail-bulk-local-intake/v1',
        status='PASS' if not uncovered and not prior_uncovered else 'FAIL',
        captured_at_utc=(datetime.now(timezone.utc).isoformat() if args.capture
                         else previous['captured_at_utc']),
        repository='CrispStrobe/quds_office_suite', target_commit=target,
        target_tree=tree_id(target), captured_refs=refs,
        inventory_sha256=hashlib.sha256(json.dumps(refs, sort_keys=True).encode()).hexdigest(),
        counts=counts, uncovered=uncovered,
        historical_proof_source=PROOF_PATH,
        historical_proof_sha256=hashlib.sha256(proof_bytes).hexdigest(),
        independently_recomputed_equivalence=proofs,
        previous_api_snapshot=dict(
            path=PRIOR_PATH, sha256=hashlib.sha256(prior_bytes).hexdigest(),
            counts=prior_counts, uncovered=prior_uncovered,
            note='Previously observed heads remain checked even if a branch was deleted or advanced.',
        ),
        maintenance_reconciliation=dict(
            commit=MERGE, parents=merge_parents,
            main_tree=tree_id(BASE), merge_tree=tree_id(MERGE),
            exact_tree_identity=True, merge_is_target_ancestor=True,
            retired_workflow=RETIRED, retired_workflow_absent=True,
        ),
        scope='Independent local Git ancestry, complete-tree/changed-path proofs and reconciliation binding. No runtime qualification claim.',
        github_actions='NOT QUERIED OR AWAITED',
    )
    if args.capture:
        report_path.write_text(json.dumps(result, indent=2) + '\n')
        totals = {category: len(names) for category, names in refs.items()}
        (out / (args.report_prefix + '.md')).write_text(
            '# Mail bulk actions: independent local intake\n\n'
            f"Status: **{result['status']}** at `{target}`.\n\n"
            f"Captured {totals['fork_branches']} fork branches, "
            f"{totals['fork_pull_requests']} fork PR heads, "
            f"{totals['upstream_branches']} upstream branches and "
            f"{totals['upstream_pull_requests']} upstream PR heads. "
            f"Uncovered current references: **{len(uncovered)}**. "
            f"Uncovered earlier API-captured references: **{len(prior_uncovered)}**.\n\n"
            'After executor recovery, all 14 historical substitutes were independently '
            'recomputed from immutable Git objects: 13 complete-tree identities and '
            'the exact 37 changed ODT paths. Modes, types and object IDs agree, and '
            'each accepted substitute is a target ancestor. This supersedes only the '
            'earlier snapshot’s local-replay limitation; the original API report is '
            'retained as historical evidence.\n\n'
            f'History reconciliation `{MERGE}` has exactly the parents `{BASE}` '
            f'and `{WIP}`. Its complete Git tree equals main’s tree '
            f'`{tree_id(BASE)}`; the temporary golden workflow remains absent. '
            'The reconciliation is an ancestor of this reviewed target.\n\n'
            '## Replay\n\n'
            'From the repository root, with the recorded objects available:\n\n'
            '```sh\npython3 docs/validation/mail-bulk-actions-20261120/intake-local.py '
            '--report-prefix ' + args.report_prefix + '\n```\n\n'
            'To refresh, fetch fork/upstream branches and PR heads into the dedicated '
            '`refs/audit-bulk/` namespaces, then add `--capture --target <commit>`. '
            'The checker writes only its own report files. Unknown heads fail the '
            'audit. Incoming runtime evidence is not a new test run. GitHub Actions, '
            'workflow runs and status endpoints were neither queried nor awaited.\n'
        )
    else:
        require(result == previous, 'Replayed intake differs from frozen report')
    print(json.dumps(dict(status=result['status'], target=target, counts=counts,
                          historical_proofs=len(proofs), uncovered=uncovered,
                          prior_uncovered=prior_uncovered)))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
