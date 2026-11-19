#!/usr/bin/env python3
"""Verify the explicit Arabic integration addendum using local immutable Git objects."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--head', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()

KNOWN_HEADS = [
    ('main after PR176', 'f059065fa622da8cee7824d66d29a2aff414d529'),
    ('PR177 incoming head', 'c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e'),
    ('PR178 incoming head', '0b8f8f7f78fbf4e2e26671ecf9a0d858c38ca75c'),
    ('main after PR180', 'f7117a493055008a72e6e16713dd67a4f7c2ad39'),
]


def git(*params):
    return subprocess.check_output(['git', '-C', str(args.repo), *params]).decode().strip()


def ancestor(older, newer):
    result = subprocess.run(['git', '-C', str(args.repo), 'merge-base', '--is-ancestor', older, newer],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode in (0, 1), result.stderr.decode()
    return result.returncode == 0


head = git('rev-parse', args.head + '^{commit}')
rows = []
secondary_parents = []
for label, oid in KNOWN_HEADS:
    assert git('rev-parse', oid + '^{commit}') == oid
    parents = git('show', '-s', '--format=%P', oid).split()
    row = {'label': label, 'commit': oid, 'tree': git('rev-parse', oid + '^{tree}'),
           'parents': parents, 'ancestor_of_frozen_source': ancestor(oid, head)}
    assert row['ancestor_of_frozen_source'], row
    rows.append(row)
    if label.startswith('main after'):
        assert len(parents) == 2
        secondary = {'observed_merge': oid, 'secondary_parent': parents[1],
                     'ancestor_of_frozen_source': ancestor(parents[1], head)}
        assert secondary['ancestor_of_frozen_source']
        secondary_parents.append(secondary)

report = {
    'checked_at_utc': datetime.now(timezone.utc).isoformat(),
    'frozen_source': head,
    'frozen_tree': git('rev-parse', head + '^{tree}'),
    'known_incoming_heads': rows,
    'known_head_count': len(rows),
    'all_known_heads_are_ancestors': True,
    'secondary_merge_parents_derived_from_immutable_commits': secondary_parents,
    'saved_inventory_scope': 'Separate from the previously saved 409-reference inventory. These four additional known commit observations do not constitute a new advertisement or increase the unique-reference count to 413.',
    'input_provenance': 'Explicit incoming heads supplied for the frozen integration cutoff and already present in local Git; no remote refresh.',
    'no_github_actions': True,
    'remote_queries': 0,
    'repository_or_runtime_mutations': 0,
    'passed': True,
}
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
