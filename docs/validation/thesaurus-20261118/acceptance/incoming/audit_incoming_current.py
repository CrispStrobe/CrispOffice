#!/usr/bin/env python3
"""Replay the exact captured-head audit without fetching or changing git refs.

Keep this script beside incoming_audit_snapshot.json and
incoming_upstream_snapshot.json. Pass --repo for a separate checkout; when
installed in a repository evidence directory, its ancestor checkout is found
automatically. New output defaults to incoming_audit_replay.json so the original
incoming_audit_result.json capture remains unchanged.
"""
import argparse
import collections
import datetime
import json
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=pathlib.Path,
                    help='Checkout containing the captured commit objects')
parser.add_argument('--output', type=pathlib.Path,
                    default=HERE / 'incoming_audit_replay.json',
                    help='Replay receipt; defaults beside this script')
args = parser.parse_args()
if args.repo is None:
    REPO = next((p for p in (HERE, *HERE.parents) if (p / '.git').exists()), None)
    if REPO is None:
        parser.error('No ancestor checkout found; pass --repo /path/to/checkout')
else:
    REPO = args.repo.resolve()
if not (REPO / '.git').exists():
    parser.error('--repo must name a git checkout (a .git directory or worktree file)')
BASE = '0e84dc951e7a9e923107d7895fa457cf29a7af71'
REVIEW = '4600c0ebc9ac5e6acabd92935821d1c15315f2c1'
MAIL = '2fef06f5fe9aefb07a48c75c0e762eee3edf26e1'

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args], text=True).strip()

def ancestor(a, b):
    result = subprocess.run(['git', '-C', str(REPO), 'merge-base', '--is-ancestor', a, b], capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.decode())
    return result.returncode == 0

snap = json.loads((HERE / 'incoming_audit_snapshot.json').read_text(encoding='utf-8'))
upstream = json.loads((HERE / 'incoming_upstream_snapshot.json').read_text(encoding='utf-8'))
previous = json.loads(git('show', BASE + ':docs/validation/thesaurus-20261118/resume/incoming-audit.json'))
historical = {}
for old in previous['historical_equivalence']:
    row = {k: old[k] for k in ('branch', 'sha', 'disposition')}
    sha = row['sha']
    equivalent = old.get('equivalent_commit')
    if row['disposition'] == 'all_commits_patch_equivalent':
        lines = git('cherry', BASE, sha).splitlines()
        row['cherry'] = lines
        row['passed'] = bool(lines) and all(line.startswith('- ') for line in lines)
    elif row['disposition'] == 'identical_tree_already_integrated':
        row['equivalent_commit'] = equivalent
        row['tree'] = git('rev-parse', sha + '^{tree}')
        row['equivalent_tree'] = git('rev-parse', equivalent + '^{tree}')
        row['equivalent_in_baseline'] = ancestor(equivalent, BASE)
        row['passed'] = row['tree'] == row['equivalent_tree'] and row['equivalent_in_baseline']
    elif row['disposition'] == 'all_changed_files_identical_in_merged_pr_140':
        paths = old['fresh_changed_files']
        row['equivalent_commit'] = equivalent
        row['verified_file_count'] = len(paths)
        row['different_files'] = [p for p in paths if git('ls-tree', sha, '--', p) != git('ls-tree', equivalent, '--', p)]
        row['equivalent_in_baseline'] = ancestor(equivalent, BASE)
        row['passed'] = not row['different_files'] and row['equivalent_in_baseline']
    else:
        raise RuntimeError(row['disposition'])
    historical[sha] = row

refs = ([{'kind': 'branch', 'name': b['name'], 'sha': b['sha']} for b in snap['branches']]
        + [{'kind': 'pull_request', 'name': str(p['number']), 'sha': p['head']} for p in snap['prs']]
        + [{'kind': 'upstream_branch', 'name': b['name'], 'sha': b['sha']} for b in upstream])
unique = {}
for row in refs:
    sha = row['sha']
    if sha not in unique:
        exists = subprocess.run(['git', '-C', str(REPO), 'cat-file', '-e', sha + '^{commit}'], capture_output=True).returncode == 0
        if not exists:
            disposition = 'missing_git_object'
        elif ancestor(sha, BASE):
            disposition = 'included_in_handoff'
        elif ancestor(sha, REVIEW):
            disposition = 'included_by_review_fast_forward'
        elif ancestor(sha, MAIL):
            disposition = 'included_by_mail_merge'
        elif historical.get(sha, {}).get('passed'):
            disposition = 'verified_historical_equivalent'
        else:
            disposition = 'unaccounted'
        unique[sha] = disposition
    row['classification'] = unique[sha]

report = {
    'recorded_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'repository': snap['repository'],
    'captured_api_at': snap['capturedAt'],
    'handoff': BASE,
    'main': next(b['sha'] for b in snap['branches'] if b['name'] == 'main'),
    'recommended_integration': [{'action': 'fast_forward', 'sha': REVIEW, 'branch': 'codex/document-review-20261118'}, {'action': 'merge', 'sha': MAIL, 'branch': 'codex/mail-reader-20261118'}],
    'counts': {'fork_branches': len(snap['branches']), 'pull_request_heads': len(snap['prs']), 'upstream_branches': len(upstream), 'total_refs': len(refs), 'unique_heads': len(unique), 'classifications': dict(collections.Counter(r['classification'] for r in refs))},
    'refs': refs,
    'historical_equivalence': list(historical.values()),
    'review_unique_commits': git('log', '--format=%H %s', MAIL + '..' + REVIEW).splitlines(),
    'mail_unique_commits': git('log', '--format=%H %s', REVIEW + '..' + MAIL).splitlines(),
    'application_paths_different_between_incoming_heads': git('diff', '--name-only', REVIEW, MAIL, '--', 'packages', 'apps', 'tools').splitlines(),
    'github_actions': {'queried': False, 'waited': False, 'dispatched': False},
    'read_only_audit': True,
    'passed': all(r['classification'] not in ('unaccounted', 'missing_git_object') for r in refs) and all(r['passed'] for r in historical.values()),
}
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: report[k] for k in ('counts', 'passed')}, indent=2))
print(json.dumps([r for r in refs if r['classification'] in ('unaccounted', 'missing_git_object')], indent=2))
