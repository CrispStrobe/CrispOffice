#!/usr/bin/env python3
import datetime
import json
from pathlib import Path
import subprocess

ROOT = Path('/workspace/scratch/6e376c6dad91/quds_office_suite')
OUT = Path(__file__).parent
BASE = 'bb5320a50f288d95844a6d60cfd72eab13a9befc'

def git(*args, check=True):
    p = subprocess.run(['git', *args], cwd=ROOT, text=True, capture_output=True)
    if check and p.returncode:
        raise RuntimeError(f'git {args}: {p.stderr}')
    return p.stdout.strip() if check else p

def ancestor(sha, target=BASE):
    return git('merge-base', '--is-ancestor', sha, target, check=False).returncode == 0

def tree(sha):
    return git('rev-parse', sha + '^{tree}')

def refs(filename):
    return [{'sha': line.split()[0], 'ref': line.split()[1]}
            for line in (OUT / filename).read_text().splitlines()]

history = json.loads((ROOT / 'docs/validation/mail-offline-accounts-20261120/final-reconciliation.json').read_text())
equivalents = {x['head']: x for x in history['dispositions']
              if x['disposition'] in ('changed-path equivalent', 'exact-tree equivalent')}

def disposition(sha):
    if ancestor(sha):
        return {'disposition': 'ancestor'}
    prior = equivalents.get(sha)
    if prior:
        equivalent = prior['equivalent_ancestor']
        assert ancestor(equivalent)
        if prior['disposition'] == 'exact-tree equivalent':
            assert tree(sha) == tree(equivalent)
            return {'disposition': 'exact-tree equivalent', 'equivalent_ancestor': equivalent,
                    'tree': tree(sha), 'verified_equal': True}
        base = prior['comparison_base']
        paths = git('diff', '--name-only', base, sha).splitlines()
        assert paths == prior['changed_paths']
        for path in paths:
            assert git('ls-tree', sha, '--', path) == git('ls-tree', equivalent, '--', path), path
        return {'disposition': 'changed-path equivalent', 'equivalent_ancestor': equivalent,
                'comparison_base': base, 'changed_paths': paths, 'verified_equal': True}
    return {'disposition': 'unmerged', 'unique_commits': git('rev-list', '--count', BASE + '..' + sha)}

fork = refs('fork-refs.txt')
upstream = refs('upstream-refs.txt')
prs = json.loads((OUT / 'prs.json').read_text())
entries = []
for entry in fork:
    if entry['ref'].startswith('refs/heads/'):
        entries.append({'kind': 'fork_branch', **entry, **disposition(entry['sha'])})
for pr in prs:
    entries.append({'kind': 'recent_pr', 'number': pr['number'], 'sha': pr['head_sha'],
                    'branch': pr['head'], 'state': pr['state'], 'draft': pr['draft'],
                    'merged': pr['merged'], **disposition(pr['head_sha'])})
for entry in upstream:
    entries.append({'kind': 'upstream_ref', **entry, **disposition(entry['sha'])})
result = {'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'target': BASE, 'target_tree': tree(BASE), 'github_actions': 'NOT QUERIED OR AWAITED',
          'fork_branch_count': sum(e['kind'] == 'fork_branch' for e in entries),
          'recent_pr_count': len(prs),
          'upstream_ref_count': len(upstream),
          'entries': entries,
          'unmerged': [e for e in entries if e['disposition'] == 'unmerged']}
(OUT / 'reconciliation-initial.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k:v for k,v in result.items() if k != 'entries'}, indent=2))
