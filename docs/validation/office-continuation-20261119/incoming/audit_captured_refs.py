#!/usr/bin/env python3
"""Recheck one captured remote advertisement against a local commit.

No network calls, ref updates, checkout changes, or CI queries are made.
Historical equivalence is independently recomputed from retained Git objects.
"""
import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--capture', required=True, type=Path)
    parser.add_argument('--head', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()

    def git(*arguments):
        return subprocess.check_output(
            ['git', *arguments], cwd=args.repo, text=True
        ).strip()

    head = git('rev-parse', args.head + '^{commit}')
    ancestors = set(git('rev-list', head).splitlines())
    prior_path = args.repo / (
        'docs/validation/mail-uid-pagination-20261119/merge-refresh/'
        'audit-394-origin424-plus-retained-upstream4.json'
    )
    prior = json.loads(prior_path.read_text())
    checks = []
    for original in prior['historical_equivalence_checks']:
        sha = original['sha']
        check = {key: original[key] for key in ('branch', 'sha', 'disposition')}
        equivalent = original.get('equivalent_commit')
        if equivalent:
            check['equivalent_commit'] = equivalent
            check['equivalent_is_ancestor'] = equivalent in ancestors
        if original['disposition'] == 'all_commits_patch_equivalent':
            lines = git('cherry', head, sha).splitlines()
            check['cherry'] = lines
            check['passed'] = bool(lines) and all(x.startswith('- ') for x in lines)
        elif original['disposition'] == 'identical_tree_already_integrated':
            check['original_tree'] = git('rev-parse', sha + '^{tree}')
            check['equivalent_tree'] = git('rev-parse', equivalent + '^{tree}')
            check['passed'] = (
                check['equivalent_is_ancestor']
                and check['original_tree'] == check['equivalent_tree']
            )
        elif original['disposition'] == 'all_changed_files_identical_in_merged_pr_140':
            merge_base = git('merge-base', head, sha)
            paths = git('diff', '--name-only', merge_base, sha).splitlines()
            check['merge_base'] = merge_base
            check['complete_delta_paths'] = paths
            check['path_list_matches_prior'] = (
                paths == original['recomputed_complete_delta_paths']
            )
            file_checks = []
            for path in paths:
                left = git('ls-tree', sha, '--', path)
                right = git('ls-tree', equivalent, '--', path)
                file_checks.append({
                    'path': path, 'original': left, 'equivalent': right,
                    'identical': left == right,
                })
            check['files'] = file_checks
            check['passed'] = (
                bool(file_checks) and check['equivalent_is_ancestor']
                and check['path_list_matches_prior']
                and all(x['identical'] for x in file_checks)
            )
        else:
            raise ValueError(original['disposition'])
        checks.append(check)

    verified = {x['sha']: x for x in checks if x['passed']}
    capture = json.loads(args.capture.read_text())
    refs = []
    excluded = []
    for row in capture['rows']:
        ref = row['ref']
        if ref == 'HEAD' or ref.endswith('^{}'):
            excluded.append(row)
            continue
        commit = git('rev-parse', row['sha'] + '^{commit}')
        if commit in ancestors:
            disposition = 'ancestor'
        elif commit in verified:
            disposition = 'historical_equivalent'
        else:
            disposition = 'unaccounted'
        refs.append({
            **row, 'commit': commit, 'namespace': 'current_origin',
            'classification': disposition,
        })
    upstream = []
    for row in prior['refs']:
        if row['kind'] != 'upstream_branch':
            continue
        commit = git('rev-parse', row['object_sha'] + '^{commit}')
        upstream.append({
            'ref': row['ref'], 'sha': row['object_sha'], 'commit': commit,
            'namespace': 'retained_upstream',
            'classification': 'ancestor' if commit in ancestors else 'unaccounted',
            'capture': row['capture'],
        })
    unaccounted = [x for x in refs + upstream if x['classification'] == 'unaccounted']
    result = {
        'schema': 1,
        'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'head': head,
        'tree': git('rev-parse', head + '^{tree}'),
        'capture_started_at': capture['started_at'],
        'capture_completed_at': capture['completed_at'],
        'capture_sha256': hashlib.sha256(args.capture.read_bytes()).hexdigest(),
        'historical_proof_source_sha256': hashlib.sha256(prior_path.read_bytes()).hexdigest(),
        'current_origin_counts': dict(collections.Counter(
            'branch' if x['ref'].startswith('refs/heads/') else
            'pull_request_head' if x['ref'].startswith('refs/pull/') else
            'tag' if x['ref'].startswith('refs/tags/') else 'other'
            for x in refs
        )),
        'current_origin_ref_count': len(refs),
        'current_origin_classification': dict(collections.Counter(x['classification'] for x in refs)),
        'retained_upstream_count': len(upstream),
        'retained_upstream_refs': upstream,
        'excluded_alias_and_peeled_advertisements': excluded,
        'historical_equivalence_checks': checks,
        'refs': refs,
        'unaccounted_refs': unaccounted,
        'passed': not unaccounted and all(x['passed'] for x in checks),
        'network_calls': 0,
        'github_actions_calls': 0,
        'scope': 'One bounded ref capture; ancestry and historical equivalence only, not application qualification.',
    }
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in (
        'head', 'current_origin_ref_count', 'current_origin_classification',
        'retained_upstream_count', 'unaccounted_refs', 'passed',
    )}, indent=2))


if __name__ == '__main__':
    main()
