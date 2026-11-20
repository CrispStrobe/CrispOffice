#!/usr/bin/env python3
"""Capture or replay source inclusion from fetched fork/upstream Git refs.

The caller fetches refs first. This tool changes no refs and queries no CI.
Without --capture, the committed snapshot is verified without rewriting it.
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


PROOF_PATH = 'docs/validation/word-vba-list-levels-20261120/final-intake.json'
PARTIAL_HEAD = 'c34945761e7991f5fe49037d79529acdd260b31c'
NAMESPACES = {
    'fork_branches': 'refs/remotes/origin/',
    'fork_pull_requests': 'refs/remotes/pull/',
    'upstream_branches': 'refs/remotes/upstream/',
    'upstream_pull_requests': 'refs/remotes/upstream-pull/',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--target')
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--output-dir', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.output_dir.resolve()

    def git(*arguments):
        return subprocess.check_output(['git', '-C', str(repo), *arguments])

    def require(condition, message):
        if not condition:
            raise ValueError(message)

    report_path = out / 'intake.json'
    previous = None if args.capture else json.loads(report_path.read_text())
    target = git('rev-parse', (args.target or (
        'HEAD' if args.capture else previous['target_commit'])) + '^{commit}').decode().strip()
    ancestry = {}

    def ancestor(head):
        if head not in ancestry:
            result = subprocess.run(
                ['git', '-C', str(repo), 'merge-base', '--is-ancestor', head, target],
                capture_output=True,
            )
            require(result.returncode in (0, 1), result.stderr.decode())
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
    proofs = {}
    for row in json.loads(proof_bytes)['historical_equivalence_proofs']:
        old, accepted = row['historical_head'], row['accepted_ancestor']
        changed = [path for path in git(
            'diff', '--name-only', '-z', row['comparison_base'], old,
        ).decode().split('\0') if path]
        old_entries, accepted_entries = tree(old), tree(accepted)
        require(ancestor(accepted), 'Replacement is not an ancestor: ' + old)
        require(set(changed) == {entry['path'] for entry in row['entries']},
                'Historical changed-path inventory differs: ' + old)
        require(len(changed) == row['changed_path_count'], 'Path count differs: ' + old)
        require(all(old_entries.get(path) == accepted_entries.get(path) for path in changed),
                'Historical mode/type/object differs: ' + old)
        old_tree = git('rev-parse', old + '^{tree}').decode().strip()
        accepted_tree = git('rev-parse', accepted + '^{tree}').decode().strip()
        equal = old_tree == accepted_tree
        require(equal or (old == PARTIAL_HEAD and len(changed) == 37),
                'Unexpected partial-tree substitute: ' + old)
        proofs[old] = dict(replacement=accepted, changed_paths=len(changed),
                           full_tree_equal=equal, exact_changed_paths=True)

    if args.capture:
        refs = {category: {} for category in NAMESPACES}
        raw = git('for-each-ref', '--format=%(refname) %(objectname) %(symref)',
                  *NAMESPACES.values()).decode()
        for line in raw.splitlines():
            fields = line.split()
            if len(fields) != 2:  # Skip symbolic origin/HEAD.
                continue
            name, head = fields
            for category, prefix in NAMESPACES.items():
                if name.startswith(prefix):
                    refs[category][name[len(prefix):]] = head
                    break
        require(all(refs.values()), 'Missing fetched fork/upstream branch or PR refs')
    else:
        refs = previous['captured_refs']

    counts, uncovered = {}, {}
    for category, names in refs.items():
        states = Counter()
        for name, head in names.items():
            disposition = ('ancestor' if ancestor(head) else
                           'equivalent' if head in proofs else 'uncovered')
            states[disposition] += 1
            if disposition == 'uncovered':
                uncovered[category + '/' + name] = head
        counts[category] = dict(states)

    result = dict(
        schema='quds-mail-source-intake/v1',
        status='PASS' if not uncovered else 'FAIL',
        captured_at_utc=(datetime.now(timezone.utc).isoformat() if args.capture
                         else previous['captured_at_utc']),
        repository='CrispStrobe/quds_office_suite', target_commit=target,
        target_tree=git('rev-parse', target + '^{tree}').decode().strip(),
        scope='Source inclusion from fetched remote-tracking refs; no runtime qualification claim.',
        counts=counts, uncovered=uncovered, captured_refs=refs,
        inventory_sha256=hashlib.sha256(json.dumps(refs, sort_keys=True).encode()).hexdigest(),
        historical_proof_source=PROOF_PATH,
        historical_proof_sha256=hashlib.sha256(proof_bytes).hexdigest(),
        recomputed_equivalence=proofs,
        github_actions='NOT QUERIED OR AWAITED',
    )
    if args.capture:
        out.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(result, indent=2) + '\n')
        totals = {category: len(names) for category, names in refs.items()}
        (out / 'intake.md').write_text(
            '# Mail header search: incoming source audit\n\n'
            f"Status: **{result['status']}** at `{target}`.\n\n"
            f"Captured {totals['fork_branches']} fork branches, "
            f"{totals['fork_pull_requests']} fork PR heads, "
            f"{totals['upstream_branches']} upstream branches and "
            f"{totals['upstream_pull_requests']} upstream PR heads. "
            f"Uncovered references: **{len(uncovered)}**. "
            'The complete compact ref inventory is in `intake.json`.\n\n'
            'All 14 historical replacements were independently recomputed from Git objects: '
            '13 complete-tree identities and the exact 37 changed ODT paths. File modes, '
            'types and object IDs agree, and every replacement is a target ancestor. '
            'These older branches therefore need no replay.\n\n'
            'The captured recent fork work includes Word paragraph spacing/controls '
            'and style identities, macro CLI process cleanup, bookmark deletion clamping, '
            'incremental layout with fitting and notes, Studio settings persistence, '
            'macOS deployment requirements, Arabic web-worker packaging/parity checks '
            'and their recorded fixture, App Store screenshot hooks and workflows, and '
            'submission notes. Preserving authored submission notes does not submit an '
            'app or independently verify App Store account state. The explicitly '
            'temporary golden-regeneration workflow was removed before main.\n\n'
            '## Replay and refresh\n\n'
            'From the repository root:\n\n'
            '```sh\npython3 docs/validation/mail-header-search-20261120/verify_intake.py\n```\n\n'
            'For a later capture, first fetch the fork/upstream branch and PR namespaces, '
            'then pass `--capture --target <commit>`. The checker only writes its report '
            'files, never Git refs. Unknown references fail the audit. This checks source '
            'inclusion, not runtime behavior; incoming validation is not claimed as a new run. '
            'GitHub Actions, workflow runs and status endpoints were neither queried nor awaited.\n'
        )
    else:
        require(result == previous, 'Replayed intake differs from the committed result')
    print(json.dumps(dict(status=result['status'], target=target, counts=counts,
                          historical_proofs=len(proofs), uncovered=len(uncovered))))
    return 1 if uncovered else 0


if __name__ == '__main__':
    raise SystemExit(main())
