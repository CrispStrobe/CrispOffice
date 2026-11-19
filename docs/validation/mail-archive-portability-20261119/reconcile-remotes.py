#!/usr/bin/env python3
"""Read-only fresh frontier and historical-equivalence audit."""
import argparse
import collections
import datetime
import hashlib
import json
import subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--head', default='81ae98688860599f118748afca19bdb2ec45da37')
p.add_argument('--incoming', default='f0ce86842452ee7397afcf21b93c73e126d7d07e')
p.add_argument('--output', default='reconciliation.json')
p.add_argument('--references-from', type=Path,
               help='Reclassify an already captured remote frontier without moving its cutoff.')
args = p.parse_args()
repo = Path(__file__).resolve().parents[3]

def git(*argv):
    return subprocess.check_output(['git', *argv], cwd=repo, stderr=subprocess.PIPE).decode().strip()

def ancestor(a, b):
    return subprocess.run(['git', 'merge-base', '--is-ancestor', a, b], cwd=repo,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def exists(sha):
    return subprocess.run(['git', 'cat-file', '-e', sha+'^{commit}'], cwd=repo,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

previous = json.loads((repo/'docs/validation/mail-archive-search-20261119/reconciliation-refresh.json').read_text())
proofs = []
for proof in previous['historical_proofs']:
    original, equivalent = proof['original'], proof['equivalent']
    base = git('merge-base', original, equivalent)
    paths = git('diff', '--name-only', base, original).splitlines()
    if proof['method'] == 'exact_complete_tree_identity':
        equal = git('rev-parse', original+'^{tree}') == git('rev-parse', equivalent+'^{tree}')
    else:
        equal = all(git('ls-tree', original, '--', path) ==
                    git('ls-tree', equivalent, '--', path) for path in paths)
    proofs.append({
        'original': original, 'equivalent': equivalent, 'method': proof['method'],
        'common_base': base, 'common_base_matches_prior': base == proof['common_base'],
        'complete_original_delta_paths': len(paths),
        'equivalent_is_ancestor': ancestor(equivalent, args.head),
        'passed': equal and ancestor(equivalent, args.head) and base == proof['common_base'],
    })

references = []
frontier = None
if args.references_from:
    raw_frontier = args.references_from.read_bytes()
    frontier = json.loads(raw_frontier)
    references = [{key: item[key] for key in ('source', 'ref', 'sha')}
                  for item in frontier['references']]
    if len({(item['source'], item['ref']) for item in references}) != len(references):
        raise ValueError('Duplicate references in the captured frontier')
else:
    for source, remote, patterns in (
        ('fork', 'origin', ['refs/heads/*', 'refs/pull/*/head']),
        ('upstream', 'https://github.com/MohammedAsaadAsaad/quds_office_suite.git', ['refs/heads/*']),
    ):
        for line in git('ls-remote', remote, *patterns).splitlines():
            sha, ref = line.split()
            references.append({'source': source, 'ref': ref, 'sha': sha})

proof_by_sha = {x['original']: x for x in proofs if x['passed']}
for ref in references:
    sha = ref['sha']
    if not exists(sha):
        ref['classification'] = 'object_not_fetched'
    elif ancestor(sha, args.head):
        ref['classification'] = 'ancestor'
    elif sha in proof_by_sha:
        ref['classification'] = 'historical_equivalent'
        ref['equivalent'] = proof_by_sha[sha]['equivalent']
    elif args.incoming and ancestor(sha, args.incoming):
        ref['classification'] = 'incoming'
        ref['integration_tip'] = args.incoming
    else:
        ref['classification'] = 'unaccounted'

receipt = {
    'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'scope': 'Every advertised fork branch and PR head, plus every advertised upstream branch; no Actions queried or awaited.',
    'audited_head': args.head,
    'audited_tree': git('rev-parse', args.head+'^{tree}'),
    'incoming_tip': args.incoming,
    'counts': dict(collections.Counter(r['classification'] for r in references)),
    'historical_proofs': proofs,
    'references': references,
}
if frontier is not None:
    receipt['frontier_captured_at_utc'] = frontier['captured_at_utc']
    receipt['frontier_source_sha256'] = hashlib.sha256(raw_frontier).hexdigest()
    receipt['frontier_mode'] = 'retained_capture'
else:
    receipt['frontier_mode'] = 'fresh_remote_capture'
Path(args.output).write_text(json.dumps(receipt, indent=2)+'\n')
print(json.dumps({'output': args.output, 'references': len(references), 'counts': receipt['counts'],
                  'failed_proofs': [x for x in proofs if not x['passed']],
                  'unaccounted': [x for x in references if x['classification'] in ['unaccounted', 'object_not_fetched']]}, indent=2))
if any(not item['passed'] for item in proofs) or any(
    item['classification'] in ('unaccounted', 'object_not_fetched') for item in references
):
    raise SystemExit(1)
