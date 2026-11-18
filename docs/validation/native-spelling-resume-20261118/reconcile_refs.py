#!/usr/bin/env python3
"""Recheck a captured reference inventory against an exact integrated commit."""

import argparse
import collections
import datetime
import json
import pathlib
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=pathlib.Path, required=True)
    parser.add_argument('--refs', type=pathlib.Path, required=True)
    parser.add_argument('--prior', type=pathlib.Path, required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    captured = json.loads(args.refs.read_text())
    refs = captured['refs'] if isinstance(captured, dict) else captured
    prior = json.loads(args.prior.read_text())

    def git(*words):
        return subprocess.check_output(['git', *words], cwd=args.repo)

    def ancestor(sha):
        result = subprocess.run(
            ['git', 'merge-base', '--is-ancestor', sha, args.target],
            cwd=args.repo, capture_output=True,
        )
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr.decode())
        return result.returncode == 0

    def patch_id(base, head):
        diff = git('diff', '--no-ext-diff', base, head)
        result = subprocess.run(
            ['git', 'patch-id', '--stable'], cwd=args.repo, input=diff,
            capture_output=True, check=True,
        ).stdout.decode().split()
        return result[0] if result else None

    equivalent = {}
    checks = {'patch': [], 'tree': []}
    for original in prior['equivalence']['patch']:
        branch, accepted = original['branch'], original['main']
        base = git('rev-parse', branch + '^').decode().strip()
        branch_patch = patch_id(base, branch)
        accepted_patch = patch_id(accepted + '^', accepted)
        method = 'single_commit'
        if branch_patch != accepted_patch:
            base = git('merge-base', branch, accepted).decode().strip()
            branch_patch = patch_id(base, branch)
            method = 'aggregate_from_common_ancestor'
        check = {
            'pr': original['pr'], 'branch': branch, 'main': accepted,
            'branch_base': base, 'method': method,
            'branch_patch_id': branch_patch,
            'main_patch_id': accepted_patch,
            'match': branch_patch == accepted_patch,
            'main_ancestor': ancestor(accepted),
        }
        checks['patch'].append(check)
        if check['match'] and check['main_ancestor']:
            equivalent[branch] = ('patch_equivalent_on_main', accepted)
    for original in prior['equivalence']['tree']:
        branch, accepted = original['branch'], original['main']
        branch_tree = git('rev-parse', branch + '^{tree}').decode().strip()
        accepted_tree = git('rev-parse', accepted + '^{tree}').decode().strip()
        check = {
            'pr': original['pr'], 'branch': branch, 'main': accepted,
            'branch_tree': branch_tree, 'main_tree': accepted_tree,
            'match': branch_tree == accepted_tree,
            'main_ancestor': ancestor(accepted),
        }
        checks['tree'].append(check)
        if check['match'] and check['main_ancestor']:
            equivalent[branch] = ('tree_equivalent_on_main', accepted)
    ancestors = {sha: ancestor(sha) for sha in {x['sha'] for x in refs}}
    for item in refs:
        sha = item['sha']
        if ancestors[sha]:
            item['disposition'] = 'ancestor_of_integration'
        elif sha in equivalent:
            item['disposition'], item['accepted_counterpart'] = equivalent[sha]
        else:
            item['disposition'] = 'unresolved'
    counts = collections.Counter(x['disposition'] for x in refs)
    by_repo = {}
    for repository in sorted({x['repository'] for x in refs}):
        by_repo[repository] = dict(collections.Counter(
            x['kind'] for x in refs if x['repository'] == repository
        ))
    snapshot = {
        'schema': 'quds.native_spelling_resume.reconciliation.v1',
        'audited_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'integration': git('rev-parse', args.target).decode().strip(),
        'integration_tree': git('rev-parse', args.target + '^{tree}').decode().strip(),
        'integration_parents': git('show', '-s', '--format=%P', args.target).decode().split(),
        'initial_main': '517f6d10f0ec2509b1381b3cf23807645bba4f92',
        'prior_spelling_head': '8cbdb9d9a05ff7f0e795efe0ee7848b196f424a3',
        'scope': 'Initial paginated live GitHub branch and PR inventories. Symbolic refs and PR test-merge refs excluded. Snapshot predates creation of this task branch.',
        'snapshot_is_atomic': False,
        'github_actions_workflow_checks_or_status_endpoints_used': False,
        'counts': {'refs': len(refs), 'distinct_heads': len(ancestors),
                   'by_repository': by_repo, 'dispositions': dict(counts)},
        'equivalence': checks,
        'aot_package_present': bool(git('ls-tree', args.target, 'packages/quds_proofing_aot').strip()),
        'unresolved_refs': [x for x in refs if x['disposition'] == 'unresolved'],
        'refs': refs,
    }
    args.output.write_text(json.dumps(snapshot, indent=2) + '\n')
    print(json.dumps({key: snapshot[key] for key in
                     ('integration', 'integration_tree', 'counts', 'unresolved_refs')}, indent=2))
    if counts['unresolved']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
