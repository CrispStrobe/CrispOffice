#!/usr/bin/env python3
"""Account for the captured refs with Git ancestry and exact historical proofs."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent


def git(*args: str) -> str:
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def main() -> None:
    captured = json.loads((HERE / 'capture.json').read_text())
    previous = json.loads((ROOT / 'docs/validation/mail-store-20261118/incoming/final-frontier.json').read_text())
    head = git('rev-parse', 'HEAD')
    ancestors = set(git('rev-list', head).splitlines())
    proofs = {}
    for old in previous['historical_equivalence_reverification']:
        sha, equivalent = old['sha'], old['equivalent_commit']
        proof = {'sha': sha, 'equivalent': equivalent,
                 'equivalent_is_ancestor': equivalent in ancestors}
        assert proof['equivalent_is_ancestor'], proof
        if old['disposition'] == 'identical_tree_already_integrated':
            proof.update(method='identical_git_trees', tree=git('rev-parse', sha + '^{tree}'),
                         equivalent_tree=git('rev-parse', equivalent + '^{tree}'))
            assert proof['tree'] == proof['equivalent_tree'], proof
        elif old['disposition'] == 'all_commits_patch_equivalent':
            left = git('diff-tree', '--no-commit-id', '--raw', '--no-abbrev', '-r', sha)
            right = git('diff-tree', '--no-commit-id', '--raw', '--no-abbrev', '-r', equivalent)
            assert left and left == right, proof
            proof.update(method='identical_modes_paths_and_before_after_blob_ids',
                         delta_sha256=hashlib.sha256(left.encode()).hexdigest())
        else:
            paths = git('diff', '--name-only', old['merge_base'], sha).splitlines()
            records = []
            for path in paths:
                left = git('ls-tree', sha, '--', path)
                right = git('ls-tree', equivalent, '--', path)
                assert left == right, (path, left, right)
                records.append(left)
            proof.update(method='identical_changed_path_tree_entries', files=len(paths),
                         entries_sha256=hashlib.sha256('\n'.join(records).encode()).hexdigest())
        proof['verified'] = True
        proofs[sha] = proof
    rows = []
    excluded = []
    for kind, source, name_key in (
        ('branch', captured['branches'], 'name'),
        ('pull_request', captured['pull_requests'], 'number'),
        ('upstream_branch', captured['upstream_branches'], 'name'),
    ):
        for item in source:
            name, sha = item[name_key], item['sha']
            row = {'kind': kind, 'name': name, 'sha': sha}
            if (kind == 'branch' and name == 'codex/mail-reader-20261118') or (kind == 'pull_request' and name == 172):
                excluded.append(row)
                continue
            row['disposition'] = 'ancestor' if sha in ancestors else 'historical_equivalent' if sha in proofs else 'UNACCOUNTED'
            if sha in proofs:
                row['equivalent'] = proofs[sha]['equivalent']
            rows.append(row)
    counts = {kind: {disposition: sum(row['kind'] == kind and row['disposition'] == disposition for row in rows)
                     for disposition in ('ancestor', 'historical_equivalent', 'UNACCOUNTED')}
              for kind in ('branch', 'pull_request', 'upstream_branch')}
    incoming_heads = ['c9f8cd8e213b0d5ed3edc31546dd19db553048f2',
                      '2d31df46d9aa684c60b75053671b0f45016388d2',
                      '5535d2eb8ed153b937f372912d3279c7794090ed']
    incoming = git('rev-list', *incoming_heads, '--not', '514c341d985e01bbc38f8ec4a1f5708e2b7fc8f3').splitlines()
    result = {'captured_at_utc': captured['captured_at'],
              'verified_at_utc': datetime.now(timezone.utc).isoformat(),
              'source': captured['source'], 'integration_commit': head,
              'integration_tree': git('rev-parse', head + '^{tree}'),
              'counts': counts, 'excluded_own_refs': excluded, 'refs': rows,
              'historical_equivalence_proofs': list(proofs.values()),
              'new_commits': [{'sha': sha, 'ancestor': sha in ancestors} for sha in incoming],
              'all_captured_external_refs_accounted_for': all(row['disposition'] != 'UNACCOUNTED' for row in rows),
              'github_actions': 'NOT QUERIED OR AWAITED',
              'scope': 'Capture-time reconciliation; later remote advances are not implied.'}
    assert result['all_captured_external_refs_accounted_for']
    assert all(row['ancestor'] for row in result['new_commits'])
    (HERE / 'audit.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'integration_commit': head, 'counts': counts, 'new_commits': len(incoming), 'verified': True}))


if __name__ == '__main__':
    main()
