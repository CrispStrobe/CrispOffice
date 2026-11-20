"""Read-only, network-free inclusion audit of captured refs and known equivalents."""
import collections
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path('/workspace/scratch/86ea302351d7')
REPO = ROOT / 'quds_office_suite'
TARGET = '9aa177ba9abeae7179edd517da8924f16c4c78f4'
HISTORICAL = 'docs/validation/office-vba-word-powerpoint-20261120/integration/inclusion-receipt.json'
env = dict(os.environ, GIT_NO_LAZY_FETCH='1')

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args], env=env).decode().rstrip('\n')

def ancestor(sha):
    result = subprocess.run(['git', '-C', str(REPO), 'merge-base', '--is-ancestor', sha, TARGET], env=env, capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.decode())
    return result.returncode == 0

historical_bytes = git('show', f'{TARGET}:{HISTORICAL}').encode()
previous = json.loads(historical_bytes)
known = {p['historical_head']: p for p in previous['historical_equivalence_proofs']}
verified = {}
failures = []

def equivalent(sha):
    if sha in verified:
        return verified[sha]
    old = known.get(sha)
    if not old:
        failures.append({'head': sha, 'reason': 'No ancestry or accepted equivalent'})
        return None
    accepted = old['accepted_ancestor']
    paths = git('diff', '--name-only', '-z', old['comparison_base'], sha).split('\0')
    paths = [p for p in paths if p]
    a = git('ls-tree', '-r', '-z', sha, '--', *paths)
    b = git('ls-tree', '-r', '-z', accepted, '--', *paths)
    head_tree = git('rev-parse', f'{sha}^{{tree}}')
    accepted_tree = git('rev-parse', f'{accepted}^{{tree}}')
    result = {
        'historical_head': sha,
        'accepted_ancestor': accepted,
        'accepted_is_ancestor': ancestor(accepted),
        'comparison_base': old['comparison_base'],
        'changed_path_count': len(paths),
        'all_changed_modes_types_objects_match': a == b,
        'changed_path_entry_sha256': hashlib.sha256(a.encode()).hexdigest(),
        'historical_tree': head_tree,
        'accepted_tree': accepted_tree,
        'whole_tree_equal': head_tree == accepted_tree,
    }
    result['verified'] = result['accepted_is_ancestor'] and result['all_changed_modes_types_objects_match']
    if not result['verified']:
        failures.append(result)
    verified[sha] = result
    return result

def refs(prefix):
    records = []
    for row in git('for-each-ref', '--format=%(refname) %(objectname)', prefix).splitlines():
        name, sha = row.split(' ', 1)
        if name.endswith('/HEAD'):
            continue
        entry = {'ref': name, 'sha': sha}
        if ancestor(sha):
            entry['status'] = 'ancestor'
        else:
            eq = equivalent(sha)
            entry['status'] = 'historically_superseded_equivalent' if eq and eq['verified'] else 'uncovered'
            if eq:
                entry['accepted_ancestor'] = eq['accepted_ancestor']
        records.append(entry)
    return records

branches = refs('refs/remotes/origin/')
prs = refs('refs/remotes/pull/')
result = {
    'schema': 1,
    'audited_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'repository': 'CrispStrobe/quds_office_suite',
    'target_commit': TARGET,
    'target_tree': git('rev-parse', f'{TARGET}^{{tree}}'),
    'read_only_git': True,
    'network_or_fetch_used': False,
    'github_actions_used': False,
    'historical_mapping_path': HISTORICAL,
    'historical_mapping_blob': git('rev-parse', f'{TARGET}:{HISTORICAL}'),
    'method': 'merge-base --is-ancestor for actual inclusion; historical equivalence requires accepted ancestry and exact mode/type/object identity on every path changed from the recorded comparison base. Whole-tree identity is recorded separately. GIT_NO_LAZY_FETCH=1.',
    'summary': {
        'branches': dict(collections.Counter(r['status'] for r in branches)),
        'fetched_prs': dict(collections.Counter(r['status'] for r in prs)),
        'fetched_pr_count': len(prs),
        'historical_full_tree_matches': sum(r['whole_tree_equal'] for r in verified.values()),
        'historical_changed_path_matches': sum(r['verified'] for r in verified.values()),
        'failure_count': len(failures),
    },
    'branches': branches,
    'fetched_pull_request_refs': sorted(prs, key=lambda r: int(r['ref'].rsplit('/', 1)[1])),
    'historical_equivalence_proofs': list(verified.values()),
    'failures': failures,
}
output = ROOT / 'incoming-pr-inclusion-20261120.json'
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'output': str(output), 'target': TARGET, 'summary': result['summary'], 'failures': failures}, indent=2))
if failures:
    raise SystemExit(1)
