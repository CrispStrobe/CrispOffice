#!/usr/bin/env python3
"""Normalize an already-fetched local ref inventory without querying remotes."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path('/workspace/scratch/a7846890f2e1')
REPO = ROOT / 'quds_office_suite'
HEAD = 'ac1e4c8c788ea608402c2260488235c0189efcba'
KNOWN = {
    'refs/heads/main': 'd41000336c84b6ebfe6b35f7f8335140b5d46038',
    'refs/heads/codex/mail-reader-20261118': '700e5a35ce5f96e7abd1dc92d1a00d2110d40649',
    'refs/heads/codex/zotero-word-parity-20261118': '022a974a96db23e22bc161f7d465e4b972e8c2a9',
    'refs/heads/codex/office-main-integration-20261119': HEAD,
}


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def ancestor(a, b):
    p = subprocess.run(['git', '-C', str(REPO), 'merge-base', '--is-ancestor', a, b],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert p.returncode in (0, 1), p.stderr.decode()
    return p.returncode == 0


def digest(data):
    return hashlib.sha256(data).hexdigest()


raw = git('for-each-ref', '--format=%(objectname)\t%(refname)\t%(symref)')
(ROOT / 'socket_local_refs.tsv').write_bytes(raw)
normalized = {}
pr_candidates = {}
excluded = []
for line in raw.decode().splitlines():
    oid, ref, symbolic = line.split('\t')
    if symbolic:
        excluded.append({'ref': ref, 'object': oid, 'reason': 'symbolic alias', 'target': symbolic})
    elif ref.startswith('refs/remotes/origin/'):
        normalized['refs/heads/' + ref.removeprefix('refs/remotes/origin/')] = oid
    elif ref.startswith(('refs/remotes/pr/', 'refs/remotes/pull/')):
        number = ref.rsplit('/', 1)[1]
        assert number.isdecimal(), ref
        pr_candidates.setdefault(number, []).append({'local_ref': ref, 'object': oid})
    elif ref.startswith('refs/tags/'):
        normalized[ref] = oid
    else:
        excluded.append({'ref': ref, 'object': oid, 'reason': 'local checkout branch; not a fetched fork reference'})

pr_normalization = []
for number, candidates in sorted(pr_candidates.items(), key=lambda row: int(row[0])):
    unique = sorted({candidate['object'] for candidate in candidates})
    eligible = [candidate for candidate in unique if all(
        older == candidate or ancestor(older, candidate) for older in unique)]
    assert len(eligible) == 1, {'pr': number, 'candidates': candidates}
    selected = eligible[0]
    normalized_ref = f'refs/pull/{number}/head'
    normalized[normalized_ref] = selected
    pr_normalization.append({
        'normalized_ref': normalized_ref,
        'selected_object': selected,
        'local_observations': candidates,
        'all_observations_equal_selected_or_ancestors': True,
        'selection_basis': 'Identical aliases' if len(unique) == 1 else 'Unique descendant among already-fetched PR aliases',
    })

for ref, expected in KNOWN.items():
    assert normalized[ref] == expected, (ref, normalized.get(ref), expected)
    assert ancestor(expected, HEAD), ref

snapshot = ''.join(f'{oid}\t{ref}\n' for ref, oid in sorted(normalized.items())).encode()
(ROOT / 'socket_fork_refs.txt').write_bytes(snapshot)
upstream = (ROOT / 'final-upstream-refs.txt').read_bytes()
(ROOT / 'socket_upstream_refs.txt').write_bytes(upstream)

prior = {}
for line in (ROOT / 'tls-fork-refs.txt').read_text().splitlines():
    a, b = line.split()
    oid, ref = (a, b) if a[0] != 'r' else (b, a)
    prior[ref] = oid
changes = [{'ref': ref, 'prior_object': prior.get(ref), 'current_object': normalized.get(ref)}
           for ref in sorted(set(prior) | set(normalized))
           if prior.get(ref) != normalized.get(ref)]

counts = Counter('branch' if ref.startswith('refs/heads/') else
                 'pr_head' if ref.startswith('refs/pull/') else 'tag'
                 for ref in normalized)
assert counts == {'branch': 213, 'pr_head': 175, 'tag': 17}, counts
preserved = []
for source, target in [
    ('postmerge_mail_documentation_review.json', 'socket_mail_evidence_review.json'),
    ('audit_postmerge_mail.py', 'socket_mail_evidence_replay.py'),
    ('postmerge_mail_merge_tree.json', 'socket_mail_merge_tree.json'),
    ('postmerge_supplemental_review.md', 'socket_supplemental_review.md'),
    ('audit_capture_ancestry.py', 'socket_ancestry_audit.py'),
    ('audit_historical_continuity.py', 'socket_historical_continuity_audit.py'),
]:
    contents = (ROOT / source).read_bytes()
    (ROOT / target).write_bytes(contents)
    preserved.append({'source': source, 'preserved_as': target, 'sha256': digest(contents)})

report = {
    'captured_at_utc': datetime.now(timezone.utc).isoformat(),
    'frozen_source': HEAD,
    'frozen_tree': git('rev-parse', HEAD + '^{tree}').decode().strip(),
    'inventory_kind': 'normalized snapshot of already-fetched local refs; not a new remote advertisement',
    'fork_inventory': {'path': 'socket_fork_refs.txt', 'rows': len(normalized), 'sha256': digest(snapshot), 'counts': dict(counts)},
    'raw_local_observations': {'path': 'socket_local_refs.tsv', 'rows': len(raw.decode().splitlines()), 'sha256': digest(raw)},
    'upstream_inventory': {'path': 'socket_upstream_refs.txt', 'rows': len(upstream.decode().splitlines()), 'sha256': digest(upstream), 'provenance': 'Exact copy of prior literal final-upstream-refs.txt advertisement; not refreshed'},
    'known_incoming_cutoff': [{'ref': ref, 'object': oid, 'included_in_frozen_source_by_ancestry': True} for ref, oid in KNOWN.items()],
    'known_incoming_pr_context': {'172': KNOWN['refs/heads/codex/mail-reader-20261118'], '173': KNOWN['refs/heads/codex/zotero-word-parity-20261118']},
    'pr_context_scope': 'Known incoming heads were supplied by parent after its PR metadata check and fetched as origin branch heads. Stale local PR aliases are preserved literally and are not relabeled as newer observations.',
    'pr_alias_normalization': pr_normalization,
    'excluded_alias_and_checkout_refs': excluded,
    'differences_from_prior_tls_local_snapshot': changes,
    'preserved_review_artifacts': preserved,
    'scope': 'These immutable local observations and known incoming heads define this qualification cutoff. No claim that moving remotes remain unchanged afterward; final expected-head merge read is a separate action.',
    'remote_or_actions_queries_performed': False,
    'tracked_checkout_or_runtime_mutations_performed': False,
}
(ROOT / 'socket_capture_provenance.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({
    'fork_rows': len(normalized), 'counts': dict(counts),
    'upstream_rows': report['upstream_inventory']['rows'],
    'raw_local_rows': report['raw_local_observations']['rows'],
    'changed_pointers': changes,
    'provenance': str(ROOT / 'socket_capture_provenance.json'),
}, indent=2))
