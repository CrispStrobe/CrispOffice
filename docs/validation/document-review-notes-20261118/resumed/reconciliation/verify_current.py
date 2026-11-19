#!/usr/bin/env python3
"""Verify a fixed API snapshot using local immutable Git objects only."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

BASELINE = '690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e'
SEED = ('a39f786d5707af308b1f9899c3461a72e62b4b68:'
        'docs/validation/mail-store-20261118/incoming/initial-audit.json')
COVERAGE = ('main', 'codex/document-review-notes-20261118',
            'codex/mail-reader-20261118', 'codex/zotero-word-parity-20261118',
            'codex/offline-thesaurus-20261118')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--snapshot', required=True, type=Path)
    parser.add_argument('--head', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    def git(*parts):
        return subprocess.check_output(['git', *parts], cwd=args.repo,
            env={**os.environ, 'GIT_NO_LAZY_FETCH': '1'})
    def text(*parts):
        return git(*parts).decode().strip()
    def digest(data):
        return hashlib.sha256(data).hexdigest()
    def ancestors(head):
        return set(text('rev-list', head).splitlines())
    snapshot_bytes = args.snapshot.read_bytes()
    snapshot = json.loads(snapshot_bytes)
    seed_bytes = git('show', SEED)
    seed = json.loads(seed_bytes)['historical_equivalence_reverification']
    baseline_ancestors = ancestors(BASELINE)
    source_head = text('rev-parse', args.head + '^{commit}')
    source_ancestors = ancestors(source_head)
    raw_proofs = {}
    proofs = []
    for entry in seed:
        old, equivalent = entry['sha'], entry['equivalent_commit']
        method = entry['disposition']
        proof = {'sha': old, 'equivalent_commit': equivalent, 'method': method,
                 'equivalent_ancestor_of_baseline': equivalent in baseline_ancestors}
        if method == 'all_commits_patch_equivalent':
            def delta(commit):
                return git('diff', '--raw', '--no-abbrev', '--no-renames', '-z',
                           commit + '^1', commit, '--')
            old_delta, new_delta = delta(old), delta(equivalent)
            proof.update(raw_delta_sha256=digest(old_delta),
                         equivalent_raw_delta_sha256=digest(new_delta),
                         raw_delta_identical=old_delta == new_delta)
            raw_proofs[old] = proof
            equal = old_delta == new_delta
        elif method == 'identical_tree_already_integrated':
            proof['source_tree'] = text('rev-parse', old + '^{tree}')
            proof['equivalent_tree'] = text('rev-parse', equivalent + '^{tree}')
            equal = proof['source_tree'] == proof['equivalent_tree']
        elif method == 'all_changed_files_identical_in_merged_pr_140':
            proof['comparison_base'] = entry['merge_base']
            paths = git('diff', '--name-only', '-z', entry['merge_base'], old, '--').decode().split('\0')
            files = []
            for path in filter(None, paths):
                old_entry = git('ls-tree', '-z', old, '--', path)
                new_entry = git('ls-tree', '-z', equivalent, '--', path)
                files.append({'path': path, 'source_entry': old_entry.decode().rstrip('\0'),
                              'equivalent_entry': new_entry.decode().rstrip('\0'),
                              'equal': old_entry == new_entry})
            proof['files'] = files
            proof['changed_file_count'] = len(files)
            equal = len(files) == 37 and all(f['equal'] for f in files)
        else:
            raise ValueError(method)
        proof['verified'] = equal and proof['equivalent_ancestor_of_baseline']
        proofs.append(proof)
    # Verify every predecessor missing from main has its own exact raw delta
    # proof. This avoids patch-id traversal of all historical binary blobs.
    for old, proof in raw_proofs.items():
        missing = text('rev-list', old, '--not', BASELINE).splitlines()
        proof['missing_predecessors'] = missing
        proof['all_missing_predecessors_have_exact_delta_proofs'] = bool(missing) and all(
            c in raw_proofs and raw_proofs[c]['raw_delta_identical'] and
            raw_proofs[c]['equivalent_ancestor_of_baseline'] for c in missing)
        proof['verified'] = proof['verified'] and proof['all_missing_predecessors_have_exact_delta_proofs']
    equivalents = {p['sha']: p['equivalent_commit'] for p in proofs if p['verified']}
    coverage = [{'ref': r['ref'], 'sha': r['sha']} for r in snapshot['fork_branches']
                if r['ref'].removeprefix('refs/heads/') in COVERAGE]
    coverage_ancestors = {r['sha']: ancestors(r['sha']) for r in coverage}
    rows = [{'ref': r['ref'], 'sha': r['sha'], 'group': 'origin_branches'}
            for r in snapshot['fork_branches']]
    rows += [{'ref': f"refs/pull/{r['number']}/head", 'sha': r['head_sha'],
              'group': 'pull_request_heads'} for r in snapshot['pull_requests']]
    rows += [{'ref': r['ref'].replace('refs/heads/', 'refs/remotes/upstream/'),
              'sha': r['sha'], 'group': 'upstream_branches'} for r in snapshot['upstream_branches']]
    for row in rows:
        commit = row['sha']
        included = [h for h, commits in coverage_ancestors.items() if commit in commits]
        equivalent = equivalents.get(commit)
        row['covered_by_ancestry'] = included
        row['disposition'] = 'ancestor' if included else 'historical_equivalent' if equivalent else 'unaccounted'
        if equivalent:
            row['equivalent_commit'] = equivalent
        row['included_in_integrated_head'] = commit in source_ancestors or equivalent in source_ancestors
    receipt = {
        'schema': 1, 'snapshot_captured_at_utc': snapshot['captured_at_utc'],
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'snapshot_sha256': digest(snapshot_bytes), 'script_sha256': digest(Path(__file__).read_bytes()),
        'historical_proof_seed': {'git_object': SEED, 'sha256': digest(seed_bytes)},
        'scope': 'Git ancestry and reverified immutable historical content equivalence; no runtime acceptance claim.',
        'explicit_network_calls': 0, 'git_lazy_fetch_disabled': True, 'github_actions_or_status_calls': 0,
        'counts': dict(Counter(r['group'] for r in rows)), 'total_refs': len(rows),
        'distinct_heads': len({r['sha'] for r in rows}),
        'classification': dict(Counter(r['disposition'] for r in rows)),
        'coverage_heads': coverage, 'historical_equivalence_checks': proofs,
        'all_historical_equivalences_verified': len(proofs) == 14 and all(p['verified'] for p in proofs),
        'all_captured_refs_accounted_for': all(r['disposition'] != 'unaccounted' for r in rows),
        'integrated_head': source_head, 'integrated_tree': text('rev-parse', source_head + '^{tree}'),
        'all_captured_refs_in_integrated_head': all(r['included_in_integrated_head'] for r in rows),
        'refs': rows,
    }
    args.output.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k:v for k,v in receipt.items() if k not in ('refs','historical_equivalence_checks','coverage_heads')}, indent=2))
    print(json.dumps({'missing_heads': sorted({r['sha'] for r in rows if not r['included_in_integrated_head']})}))
    return 0 if all(receipt[k] for k in ('all_historical_equivalences_verified', 'all_captured_refs_accounted_for', 'all_captured_refs_in_integrated_head')) else 1

if __name__ == '__main__':
    raise SystemExit(main())
