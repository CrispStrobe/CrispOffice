#!/usr/bin/env python3
"""Recheck the bounded continuation intake using immutable local Git objects.

No remote writes or GitHub Actions queries are performed. The selected head is
an ancestry target, not a claim of execution coverage. Historical equivalents
are reproved from complete original delta paths and exact mode/type/blob IDs.
"""

import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--require-integrated', action='store_true')
    args = parser.parse_args()
    repo = args.repo.resolve()
    here = Path(__file__).resolve().parent
    intake_path = here / 'intake.json'
    prior_path = here.parent / 'final-reconciliation.json'
    intake = json.loads(intake_path.read_text())
    prior = json.loads(prior_path.read_text())

    def git(*command):
        return subprocess.check_output(
            ['git', '-C', str(repo), *command], stderr=subprocess.PIPE
        ).decode()

    def ancestor(original, target):
        result = subprocess.run(
            ['git', '-C', str(repo), 'merge-base', '--is-ancestor', original, target],
            capture_output=True,
        )
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr.decode())
        return result.returncode == 0

    def digest(value):
        return hashlib.sha256(
            json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
        ).hexdigest()

    def tree(commit):
        entries = {}
        for row in git('ls-tree', '-r', '-z', commit).split('\0'):
            if row:
                identity, path = row.split('\t', 1)
                entries[path] = identity
        return entries

    head = git('rev-parse', args.head + '^{commit}').strip()
    proofs = []
    for saved in prior['historicalEquivalenceProofs']:
        original, equivalent = saved['original'], saved['equivalent']
        bases = git('merge-base', '--all', original, equivalent).splitlines()
        expected_base = saved['commonBase']
        paths = sorted(filter(None, git(
            'diff', '--no-renames', '--name-only', '-z', expected_base, original
        ).split('\0')))
        old_tree, equivalent_tree = tree(original), tree(equivalent)
        identities = [
            [path, old_tree.get(path), equivalent_tree.get(path)] for path in paths
        ]
        failures = [row for row in identities if row[1] != row[2]]
        expected_paths = sorted(row['path'] for row in saved['pathIdentities'])
        # Three large historical entries retain the total and proof result but
        # omit their per-path arrays. Recompute every path in those cases too;
        # absence of an old detail list is not a missing original delta.
        saved_path_match = paths == expected_paths if expected_paths else None
        included = ancestor(equivalent, head)
        passed = (
            bases == [expected_base]
            and saved_path_match is not False
            and len(paths) == saved['completeOriginalDeltaPaths']
            and not failures
            and included
        )
        proofs.append({
            'original': original,
            'equivalent': equivalent,
            'common_base': expected_base,
            'fresh_common_base_matches': bases == [expected_base],
            'complete_original_delta_paths': len(paths),
            'saved_path_detail_available': bool(expected_paths),
            'complete_delta_matches_saved_path_set': saved_path_match,
            'delta_paths_sha256': digest(paths),
            'mode_type_blob_identities_sha256': digest(identities),
            'identity_failures': failures,
            'equivalent_is_ancestor': included,
            'passed': passed,
        })
    proofs_by_original = {p['original']: p for p in proofs}

    def classify(sha):
        if ancestor(sha, head):
            return 'included by ancestry'
        proof = proofs_by_original.get(sha)
        if proof and proof['passed']:
            return 'included by freshly verified historical equivalence'
        return 'outside selected target'

    branches = {
        b['name']: dict(b)
        for b in intake['source_observations'][0]['observed_branches']
    }
    for b in intake['source_observations'][1]['changes_from_api']:
        branches[b['name']] = dict(b)
    selected = {b['name']: b for b in intake['selected_new_heads']}
    branch_results = []
    for name, branch in sorted(branches.items()):
        sha = branch['sha']
        row = {'name': name, 'sha': sha, 'ancestry_disposition': classify(sha)}
        reviewed = selected.get(name)
        if reviewed:
            assert reviewed['sha'] == sha
            row['reviewed_disposition'] = reviewed['disposition']
            row['reason'] = reviewed['reason']
            if reviewed['disposition'].startswith('retain separate:'):
                row['accounted'] = True
                row['disposition'] = reviewed['disposition']
            else:
                row['accounted'] = row['ancestry_disposition'].startswith('included')
                row['disposition'] = row['ancestry_disposition']
        else:
            row['accounted'] = row['ancestry_disposition'].startswith('included')
            row['disposition'] = row['ancestry_disposition']
        branch_results.append(row)

    # Preserve all 223 historical PR-head observations and overlay the 20 most
    # recently updated PRs actually observed this turn. Historical head state is
    # explicitly old; only immutable ancestry/equivalence is freshly proved.
    pull_requests = {
        p['number']: {
            'number': p['number'], 'sha': p['headSha'],
            'observation': 'retained historical immutable head',
        }
        for p in prior['pullRequests']
    }
    for p in intake['recent_pull_requests']:
        pull_requests[p['number']] = {
            'number': p['number'], 'sha': p['head'],
            'observation': 'recent API head refreshed this continuation',
        }
    mail_sha = selected['work/mail-attachments-20261120']['sha']
    pr_results = []
    for number, p in sorted(pull_requests.items()):
        row = dict(p)
        row['disposition'] = classify(p['sha'])
        if number == 221 and p['sha'] == mail_sha:
            row['disposition'] = 'retain separate: explicitly incomplete draft'
        row['accounted'] = row['disposition'].startswith(('included', 'retain separate:'))
        pr_results.append(row)

    upstream = []
    for kind in ('branches', 'pullRequests'):
        for saved in prior['upstream'][kind]:
            sha = saved.get('sha') or saved['headSha']
            upstream.append({
                'kind': kind, 'name': saved.get('name'),
                'number': saved.get('number'), 'sha': sha,
                'observation': 'retained historical immutable upstream head; no new upstream capture',
                'disposition': classify(sha),
            })

    summary = {
        'historical_equivalence_proofs': len(proofs),
        'historical_equivalence_proofs_passed': sum(p['passed'] for p in proofs),
        'freshly_checked_original_delta_paths': sum(p['complete_original_delta_paths'] for p in proofs),
        'selected_fork_branches': len(branch_results),
        'branch_dispositions': dict(collections.Counter(p['disposition'] for p in branch_results)),
        'historical_and_refreshed_pr_heads': len(pr_results),
        'pr_dispositions': dict(collections.Counter(p['disposition'] for p in pr_results)),
        'recent_pr_observations': len(intake['recent_pull_requests']),
        'retained_upstream_heads': len(upstream),
        'unaccounted_branches': [p for p in branch_results if not p['accounted']],
        'unaccounted_pr_heads': [p for p in pr_results if not p['accounted']],
    }
    historical_passed = all(p['passed'] for p in proofs)
    complete = (
        historical_passed
        and not summary['unaccounted_branches']
        and not summary['unaccounted_pr_heads']
        and all(p['disposition'].startswith('included') for p in upstream)
    )
    result = {
        'schema_version': 1,
        'repository': intake['repository'],
        'recorded_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'audited_head': head,
        'audited_tree': git('rev-parse', head + '^{tree}').strip(),
        'qualification_note': 'Ancestry and identity audit only; no tests are asserted by this receipt. Three newer work-in-progress heads are explicitly retained outside this milestone.',
        'intake_sha256': hashlib.sha256(intake_path.read_bytes()).hexdigest(),
        'prior_audit_sha256': hashlib.sha256(prior_path.read_bytes()).hexdigest(),
        'verifier_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'summary': summary,
        'historical_equivalence_proofs': proofs,
        'branches': branch_results,
        'pull_requests': pr_results,
        'upstream': upstream,
        'complete_for_bounded_intake': complete,
        'policy': intake['policy'],
    }
    output = args.output or here / 'ref-audit.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'head': head, 'complete': complete, 'summary': summary}, indent=2))
    if not historical_passed or (args.require_integrated and not complete):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
