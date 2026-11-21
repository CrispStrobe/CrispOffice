#!/usr/bin/env python3
"""Reverify the captured fork/upstream intake against one local Git commit."""
import argparse
from collections import Counter
import datetime
import json
import os
from pathlib import Path
import subprocess

os.environ['GIT_NO_LAZY_FETCH'] = '1'
os.environ['GIT_TERMINAL_PROMPT'] = '0'

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--input', type=Path, required=True)
parser.add_argument('--head', default='HEAD')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()

def git(*arguments):
    return subprocess.check_output(['git', '-C', str(args.repo), *arguments], text=True).strip()

data = json.loads(args.input.read_text())
head = git('rev-parse', args.head)
ancestors = set(git('rev-list', head).splitlines())
proofs = {}
for source, old in data['proofs'].items():
    replacement = old['replacement']
    if replacement not in ancestors:
        raise AssertionError((source, 'replacement is not an ancestor', replacement))
    proof = {k: old[k] for k in ('kind', 'replacement')}
    proof['replacement_ancestor'] = True
    if old['kind'] == 'full_tree':
        proof['source_tree'] = git('rev-parse', source + '^{tree}')
        proof['replacement_tree'] = git('rev-parse', replacement + '^{tree}')
        if proof['source_tree'] != proof['replacement_tree']:
            raise AssertionError((source, 'tree inequality'))
    else:
        base = old.get('base') or git('merge-base', source, replacement)
        paths = git('diff', '--name-only', base, source).splitlines()
        if not paths:
            raise AssertionError((source, 'no changed paths'))
        differences = git('diff', '--name-only', source, replacement, '--', *paths)
        if differences:
            raise AssertionError((source, differences))
        proof.update(base=base, changed_paths=paths, exact_changed_paths=True)
    proofs[source] = proof

for row in data['refs']:
    row['disposition'] = (
        'ancestor' if row['sha'] in ancestors
        else 'verified_equivalent' if row['sha'] in proofs
        else 'unmerged'
    )
data.update(
    verified_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
    verified_head=head,
    verified_tree=git('rev-parse', head + '^{tree}'),
    proofs=proofs,
    counts=dict(Counter(row['disposition'] for row in data['refs'])),
)
args.output.write_text(json.dumps(data, indent=2) + '\n')
print(json.dumps({key: data[key] for key in ('verified_head', 'verified_tree', 'counts')}))
raise SystemExit(1 if data['counts'].get('unmerged') else 0)
