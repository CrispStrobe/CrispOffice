#!/usr/bin/env python3
"""Classify a final ref capture without hiding raw uncovered later heads.

Run with --capture for a new publication capture; omit it for offline replay of
that output directory. Initial captures are hash-checked and never overwritten.
All captured Git objects must already be available locally. This script queries
no CI/status endpoints and never fetches, pushes, merges, or changes Git refs.
"""

import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


HERE = Path(__file__).resolve().parent


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--initial-review', type=Path, default=HERE / 'incoming-review.json')
    parser.add_argument('--deferrals', type=Path, default=HERE / 'publication-deferrals.json')
    parser.add_argument('--publication-branch', default='codex/word-vba-paragraph-controls-20261120')
    parser.add_argument('--publication-pr', type=int)
    parser.add_argument('--capture', action='store_true')
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.output_dir.resolve()
    initial_path, deferrals_path = args.initial_review.resolve(), args.deferrals.resolve()
    initial = json.loads(initial_path.read_text())
    require(initial['status'] == 'PASS' and not initial['uncovered'], 'Initial intake was not fully included')
    require(out != initial_path.parent and not initial_path.is_relative_to(out),
            'Final output must not overwrite or contain the initial capture directory')
    initial_hashes = {str(initial_path): digest(initial_path)}
    for capture in initial['captures'].values():
        path = initial_path.parent / capture['path']
        require(digest(path) == capture['sha256'] and path.stat().st_size == capture['bytes'],
                'Initial remote capture changed: ' + str(path))
        initial_hashes[str(path)] = digest(path)
    if args.capture:
        require(not out.exists() or not any(out.iterdir()),
                'A new remote capture requires a fresh output directory; previous captures are retained')
    out.mkdir(parents=True, exist_ok=True)
    raw_dir = out / 'raw'
    raw_dir.mkdir(exist_ok=True)
    raw_path = raw_dir / 'incoming-final-review.json'
    old_raw_digest = digest(raw_path) if raw_path.exists() else None
    command = [sys.executable, str(HERE / 'verify_intake.py'), '--repo', str(repo),
               '--target', args.target, '--output-dir', str(raw_dir),
               '--report-prefix', 'incoming-final-review']
    if args.capture:
        command.append('--capture')
    write_json(out / 'raw-audit-command.json', dict(argv=command, cwd=str(repo), capture=args.capture))
    stdout, stderr = out / 'raw-audit.stdout', out / 'raw-audit.stderr'
    with stdout.open('wb') as output, stderr.open('wb') as error:
        result = subprocess.run(command, cwd=repo, stdout=output, stderr=error)
    write_json(out / 'raw-audit-result.json', dict(exit_code=result.returncode,
               stdout_sha256=digest(stdout), stderr_sha256=digest(stderr),
               github_actions='NOT QUERIED OR AWAITED'))
    require(result.returncode in (0, 1), 'Raw ref verifier failed unexpectedly; inspect raw-audit.stderr')
    require(raw_path.exists(), 'Raw verifier did not produce a complete report; missing Git objects must be fetched separately')
    require(old_raw_digest is None or digest(raw_path) != old_raw_digest,
            'Raw verifier did not produce a fresh report; an old report cannot satisfy this run')
    raw = json.loads(raw_path.read_text())
    for capture in raw['captures'].values():
        path = raw_dir / capture['path']
        require(path.stat().st_size == capture['bytes'] and digest(path) == capture['sha256'],
                'Raw capture bytes differ from the verifier report')
    git = lambda *values: subprocess.check_output(['git', '-C', str(repo), *values])
    target = git('rev-parse', args.target + '^{commit}').decode().strip()
    require(raw['target_commit'] == target, 'Raw audit target differs')
    require((result.returncode == 1) == bool(raw['uncovered']), 'Raw exit does not match uncovered reference inventory')
    require(raw['status'] == ('FAIL' if raw['uncovered'] else 'PASS'), 'Raw audit status differs')
    require({(row['kind'],row['ref'],row['sha']) for row in raw['uncovered']} ==
            {(row['kind'],row['ref'],row['sha']) for row in raw['refs'] if row['disposition']=='uncovered'},
            'Raw uncovered inventory was truncated')
    equivalents = {proof['historical_head']: proof['accepted_ancestor']
                   for proof in raw['recomputed_equivalence_proofs']}

    def inclusion(head):
        if head == target:
            return 'target'
        probe = subprocess.run(['git','-C',str(repo),'merge-base','--is-ancestor',head,target],capture_output=True)
        require(probe.returncode in (0,1), probe.stderr.decode())
        return 'ancestor' if probe.returncode == 0 else 'equivalent' if head in equivalents else 'uncovered'

    initial_rows, initial_uncovered = [], []
    initial_identities = set()
    for entry in initial['refs']:
        key = (entry['kind'],entry['ref'],entry['sha'])
        require(key not in initial_identities, 'Duplicate initial reference identity')
        initial_identities.add(key)
        state = inclusion(entry['sha'])
        row = dict(entry, disposition=state)
        initial_rows.append(row)
        if state == 'uncovered':
            initial_uncovered.append(row)

    decisions = json.loads(deferrals_path.read_text())
    approved = {}
    for entry in decisions['deferrals']:
        key = (entry['kind'],entry['ref'],entry['sha'])
        require(key not in approved, 'Duplicate deferral')
        require(entry['kind'] in ('fork_branches','fork_pull_requests','upstream_branches','upstream_pull_requests'),
                'Invalid deferral reference kind')
        require(re.fullmatch(r'[0-9a-f]{40}',entry['sha']) is not None and entry['reason'].strip(),
                'Every deferral requires an exact SHA and reason')
        require(key not in initial_identities, 'An initial captured head cannot be deferred')
        require(entry['ref'] not in ('refs/heads/main','refs/heads/'+args.publication_branch),
                'Main and the publication branch cannot be deferred')
        approved[key] = entry
    current, deferred, unclassified, used = [], [], [], set()
    counts = {}
    for entry in raw['refs']:
        key = (entry['kind'],entry['ref'],entry['sha'])
        state = entry['disposition']
        row = dict(entry, captured_initially=key in initial_identities)
        if state == 'uncovered':
            if key in approved:
                row.update(disposition='deferred', reason=approved[key]['reason'],
                           pull_request=approved[key].get('pull_request'),
                           classification=approved[key].get('classification'))
                deferred.append(row)
                used.add(key)
            else:
                row['disposition'] = 'unclassified'
                unclassified.append(row)
        current.append(row)
        counts.setdefault(entry['kind'],collections.Counter())[row['disposition']] += 1
    branch = [row for row in current if row['kind']=='fork_branches' and row['ref']=='refs/heads/'+args.publication_branch]
    branch_included = len(branch)==1 and branch[0]['disposition'] in ('target','ancestor','equivalent')
    if args.publication_pr is not None:
        pr = [row for row in current if row['kind']=='fork_pull_requests' and row['ref']==f'refs/pull/{args.publication_pr}/head']
        pr_included = len(pr)==1 and pr[0]['disposition'] in ('target','ancestor','equivalent')
    else:
        pr, pr_included = [], None
    for path, expected_hash in initial_hashes.items():
        require(digest(path)==expected_hash, 'Initial audit was modified during publication review')
    accepted = not initial_uncovered and not unclassified and branch_included and pr_included is not False
    report = dict(schema='quds-publication-scope/v1',status='PASS' if accepted else 'FAIL',
        reviewed_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        repository=raw['repository'],target_commit=target,target_tree=raw['target_tree'],
        initial_review=dict(path=str(initial_path.relative_to(repo)),sha256=digest(initial_path),
                            captured_target=initial['target_commit'],inputs_unchanged=True),
        initial_all_included=not initial_uncovered, initial_refs=initial_rows,initial_uncovered=initial_uncovered,
        current_all_included=not raw['uncovered'],current_all_classified=not unclassified,
        counts={key:dict(value) for key,value in counts.items()},current_refs=current,
        explicitly_deferred=deferred,unclassified=unclassified,
        unused_deferrals=[entry for key,entry in approved.items() if key not in used],
        deferrals_source=dict(path=str(deferrals_path.relative_to(repo)),sha256=digest(deferrals_path)),
        raw_audit=dict(path='raw/incoming-final-review.json',sha256=digest(raw_path),exit_code=result.returncode,
                       status=raw['status'],uncovered=raw['uncovered']),
        publication_branch=branch,publication_branch_included=branch_included,
        publication_pr=pr,publication_pr_included=pr_included,
        github_actions='NOT QUERIED OR AWAITED',
        scope='All initial captured heads must be included. Later heads require inclusion or an explicit matching-SHA deferral; no unclassified head is accepted. Raw audit failures remain recorded.')
    write_json(out / 'publication-scope-review.json',report)
    print(json.dumps(dict(status=report['status'],initial_all_included=report['initial_all_included'],
                          current_all_included=report['current_all_included'],current_all_classified=report['current_all_classified'],
                          deferred=len(deferred),unclassified=len(unclassified),raw_audit_exit_code=result.returncode)))
    return 0 if accepted else 1


if __name__ == '__main__':
    raise SystemExit(main())
