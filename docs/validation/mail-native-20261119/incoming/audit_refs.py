#!/usr/bin/env python3
"""Reverify captured incoming heads and historical equivalences without CI."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--capture-dir', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    here = args.capture_dir.resolve()
    root = args.repo.resolve()

    def git(*argv: str) -> str:
        return subprocess.check_output(['git', *argv], cwd=root, text=True).strip()

    captured = json.loads((here / 'capture.json').read_text())
    upstream = json.loads((here / 'upstream-capture.json').read_text())
    previous = json.loads((root / 'docs/validation/mail-store-20261118/incoming/final-frontier.json').read_text())
    previous_audit = json.loads((root / 'docs/validation/mail-continue-20261119/incoming/audit.json').read_text())
    head = git('rev-parse', args.head + '^{commit}')
    base = next(row['sha'] for row in captured['refs'] if row['ref'] == captured['target_branch'])
    ancestors = set(git('rev-list', head).splitlines())
    proofs = {}

    for old in previous['historical_equivalence_reverification']:
        sha, equivalent = old['sha'], old['equivalent_commit']
        proof = {'sha': sha, 'equivalent': equivalent,
                 'equivalent_is_ancestor': equivalent in ancestors}
        if not proof['equivalent_is_ancestor']:
            raise ValueError(f'Historical equivalent is not an ancestor: {proof}')
        if old['disposition'] == 'identical_tree_already_integrated':
            left, right = git('rev-parse', sha + '^{tree}'), git('rev-parse', equivalent + '^{tree}')
            if left != right:
                raise ValueError(f'Historical trees differ: {sha}, {equivalent}')
            proof.update(method='identical_git_trees', tree=left, equivalent_tree=right)
        elif old['disposition'] == 'all_commits_patch_equivalent':
            left = git('diff-tree', '--no-commit-id', '--raw', '--no-abbrev', '-r', sha)
            right = git('diff-tree', '--no-commit-id', '--raw', '--no-abbrev', '-r', equivalent)
            if not left or left != right:
                raise ValueError(f'Historical raw deltas differ: {sha}, {equivalent}')
            proof.update(method='identical_modes_paths_and_before_after_blob_ids',
                         delta_sha256=hashlib.sha256(left.encode()).hexdigest())
        elif old['disposition'] == 'all_changed_files_identical_in_merged_pr_140':
            paths = git('diff', '--name-only', old['merge_base'], sha).splitlines()
            records = []
            for path in paths:
                left, right = git('ls-tree', sha, '--', path), git('ls-tree', equivalent, '--', path)
                if left != right:
                    raise ValueError(f'Historical changed path differs: {sha}, {equivalent}, {path}')
                records.append(left)
            proof.update(method='identical_changed_path_tree_entries', files=len(paths),
                         entries_sha256=hashlib.sha256('\n'.join(records).encode()).hexdigest())
        else:
            raise ValueError(f'Unknown historical proof disposition: {old["disposition"]}')
        proof['verified'] = True
        proofs[sha] = proof

    rows, excluded = [], []
    for source, is_upstream in ((captured, False), (upstream, True)):
        for item in source['refs']:
            ref, sha = item['ref'], item['sha']
            if ref.startswith('refs/heads/'):
                kind, name = ('upstream_branch' if is_upstream else 'branch'), ref[len('refs/heads/'):]
            elif ref.startswith('refs/pull/') and ref.endswith('/head') and not is_upstream:
                kind, name = 'pull_request', int(ref.split('/')[2])
            else:
                raise ValueError(f'Unexpected captured ref: {ref}')
            row = {'kind': kind, 'name': name, 'sha': sha}
            if (kind == 'branch' and ref == captured['target_branch']) or (kind == 'pull_request' and name == 172):
                excluded.append(row)
                continue
            row['disposition'] = 'ancestor' if sha in ancestors else 'historical_equivalent' if sha in proofs else 'UNACCOUNTED'
            if sha in proofs:
                row['equivalent'] = proofs[sha]['equivalent']
            rows.append(row)

    old_refs = {(r['kind'], r['name']): r['sha'] for r in previous_audit['refs']}
    current_refs = {(r['kind'], r['name']): r['sha'] for r in rows}
    advanced = [{'kind': kind, 'name': name, 'previous_sha': old_refs.get((kind, name)), 'sha': sha}
                for (kind, name), sha in current_refs.items() if old_refs.get((kind, name)) != sha]
    removed = [{'kind': kind, 'name': name, 'previous_sha': sha}
               for (kind, name), sha in old_refs.items() if (kind, name) not in current_refs]
    incoming_heads = sorted({r['sha'] for r in advanced})
    incoming_commits = git('rev-list', *incoming_heads, '--not', base).splitlines() if incoming_heads else []
    counts = {kind: dict(Counter(r['disposition'] for r in rows if r['kind'] == kind))
              for kind in ('branch', 'pull_request', 'upstream_branch')}
    result = {
        'schema_version': 1,
        'repository': captured['repository'],
        'origin_capture_started_utc': captured['capture_started_utc'],
        'origin_capture_finished_utc': captured['capture_finished_utc'],
        'upstream_capture_started_utc': upstream['capture_started_utc'],
        'upstream_capture_finished_utc': upstream['capture_finished_utc'],
        'verified_at_utc': datetime.now(timezone.utc).isoformat(),
        'source': 'Single git ls-remote advertisement for origin branch and PR heads; separate upstream branch advertisement',
        'base_commit': base,
        'integration_commit': head,
        'integration_tree': git('rev-parse', head + '^{tree}'),
        'counts': counts,
        'external_ref_count': len(rows),
        'excluded_own_refs': excluded,
        'refs': rows,
        'historical_equivalence_proofs': list(proofs.values()),
        'advanced_or_new_refs_since_previous_capture': advanced,
        'removed_refs_since_previous_capture': removed,
        'unique_new_commit_count': len(incoming_commits),
        'new_commits': [{'sha': sha, 'ancestor': sha in ancestors} for sha in incoming_commits],
        'all_captured_external_refs_accounted_for': all(r['disposition'] != 'UNACCOUNTED' for r in rows),
        'all_new_commits_integrated': all(sha in ancestors for sha in incoming_commits),
        'github_actions': 'NOT QUERIED OR AWAITED',
        'scope': 'Capture-time reconciliation only. No claim about later remote advances or test acceptance.',
    }
    output = args.output or here / 'audit.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ('integration_commit', 'counts', 'external_ref_count',
                                           'unique_new_commit_count', 'all_captured_external_refs_accounted_for',
                                           'all_new_commits_integrated')}))
    return 0 if result['all_captured_external_refs_accounted_for'] and result['all_new_commits_integrated'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
