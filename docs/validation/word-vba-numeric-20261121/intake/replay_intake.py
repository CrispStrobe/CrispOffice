#!/usr/bin/env python3
"""Replay the captured Quds fork/PR/upstream history against a local commit."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--inventory', type=Path, required=True)
parser.add_argument('--proofs', type=Path, required=True)
parser.add_argument('--head', default='HEAD')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
environment = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_TERMINAL_PROMPT='0')


def git(*arguments):
    return subprocess.check_output(
        ['git', '-C', str(args.repo), *arguments], text=True, env=environment
    ).strip()


head = git('rev-parse', args.head)
ancestors = set(git('rev-list', head).splitlines())
data = json.loads(args.inventory.read_text())
old_proofs = json.loads(args.proofs.read_text())['proofs']
proofs = {}
for source, old in old_proofs.items():
    replacement = old['replacement']
    if replacement not in ancestors:
        raise AssertionError((source, replacement, 'replacement is not ancestor'))
    proof = dict(kind=old['kind'], replacement=replacement, replacement_ancestor=True)
    if old['kind'] == 'full_tree':
        proof['source_tree'] = git('rev-parse', source + '^{tree}')
        proof['replacement_tree'] = git('rev-parse', replacement + '^{tree}')
        if proof['source_tree'] != proof['replacement_tree']:
            raise AssertionError((source, 'full tree differs'))
    else:
        base = old.get('base') or git('merge-base', source, replacement)
        paths = git('diff', '--name-only', base, source).splitlines()
        if not paths:
            raise AssertionError((source, 'changed paths are empty'))
        different = git('diff', '--name-only', source, replacement, '--', *paths)
        if different:
            raise AssertionError((source, different))
        proof.update(base=base, changed_paths=paths, exact_changed_paths=True)
    proofs[source] = proof

items = (
    [('branch', row['name'], row['sha']) for row in data['branches']]
    + [('pr', str(row['number']), row['head_sha']) for row in data['pull_requests']]
    + [('upstream', row['name'], row['sha']) for row in data['upstream_branches']]
)
rows = []
for kind, name, sha in items:
    disposition = (
        'ancestor' if sha in ancestors else
        'verified_equivalent' if sha in proofs else 'uncovered'
    )
    rows.append(dict(kind=kind, name=name, sha=sha, disposition=disposition))
counts = dict(Counter(row['disposition'] for row in rows))
result = dict(
    verified_at=datetime.now(timezone.utc).isoformat(),
    verified_head=head,
    verified_tree=git('rev-parse', head + '^{tree}'),
    counts=counts,
    refs=rows,
    proofs=proofs,
)
args.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ('verified_head', 'verified_tree', 'counts')}))
raise SystemExit(1 if counts.get('uncovered') else 0)
