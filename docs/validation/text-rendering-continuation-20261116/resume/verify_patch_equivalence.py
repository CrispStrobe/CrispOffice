#!/usr/bin/env python3
"""Prove every unmerged non-merge commit has an exact patch equivalent in main."""
import datetime
import hashlib
import json
import subprocess
from pathlib import Path

REPO = Path('/workspace/scratch/0caf1983021b/quds_office_suite')
OUT = REPO.parent / 'inventory_work'
HEAD = '65f943d70260ad634ffd9f0d36a2a3790061a137'
MAIN = 'be9eeec9ea3455018de26fff5874c558dbc66798'
BASE = '0d19b16e10c6bc8492f47880321df2d9f2561223'
TIPS = [
    '1675bbbb7c03090a87b6df783e3741e2cbc1768f',
    'bb9866d25bf98e5aa42c10ce4679835dbc8617f1',
    '06828a5e63365495c86a4a0e1c68ecd113f891e5',
    'f27e9b0e7ee9b1db8f6b7393abd752dab67d1ca5',
    '1deb61cf78add61f5d26bea36ff596d769d06a87',
    '27137499f8cc1a946bfcdd7446f43945ea81d2be',
    '928f85483ec1cb85e468ca9381585875137ba8d5',
    '891ccc21cf91fb9f49fa0af98143468fbbd3eac7',
]
def git(*args, input_bytes=None):
    return subprocess.run(['git', '-C', str(REPO), *args], input=input_bytes,
                          check=True, capture_output=True).stdout


def record(sha):
    patch = git('diff', '--binary', '--full-index', '--no-ext-diff', sha + '^', sha)
    patch_id = git('patch-id', '--stable', input_bytes=patch).decode().split()[0]
    normalized = b'\n'.join(line for line in patch.splitlines()
                            if not line.startswith(b'index '))
    paths = git('diff', '--name-only', sha + '^', sha).decode().splitlines()
    return {
        'sha': sha,
        'subject': git('show', '-s', '--format=%s', sha).decode().strip(),
        'tree': git('rev-parse', sha + '^{tree}').decode().strip(),
        'parent': git('rev-parse', sha + '^').decode().strip(),
        'patch_id_stable': patch_id,
        'full_diff_sha256': hashlib.sha256(patch).hexdigest(),
        'diff_without_index_lines_sha256': hashlib.sha256(normalized).hexdigest(),
        'paths': paths,
    }


missing = git('rev-list', '--no-merges', *TIPS, '^' + HEAD).decode().splitlines()
canonical = git('rev-list', '--no-merges', BASE + '..' + MAIN).decode().splitlines()
canonical_records = [record(sha) for sha in canonical]
missing_records = []
for sha in missing:
    rec = record(sha)
    matches = [c for c in canonical_records
               if c['patch_id_stable'] == rec['patch_id_stable']]
    rec['equivalent_main_commits'] = [c['sha'] for c in matches]
    rec['identical_patch_except_index_lines'] = [
        c['sha'] for c in matches if c['diff_without_index_lines_sha256'] ==
        rec['diff_without_index_lines_sha256']]
    rec['identical_complete_tree'] = [c['sha'] for c in matches
                                      if c['tree'] == rec['tree']]
    missing_records.append(rec)
paths = sorted({p for rec in missing_records for p in rec['paths']})
current_files = []
for path in paths:
    head_blob = git('rev-parse', HEAD + ':' + path).decode().strip()
    main_blob = git('rev-parse', MAIN + ':' + path).decode().strip()
    current_files.append({'path': path, 'head_blob': head_blob,
                          'main_blob': main_blob, 'identical': head_blob == main_blob})
report = {
    'recorded_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'head': HEAD, 'main': MAIN, 'base': BASE, 'tips': TIPS,
    'method': 'git rev-list --no-merges TIPS ^HEAD enumerates every unmerged non-merge commit, not just the tips. Full binary full-index diffs are matched using git patch-id --stable and additionally byte hashing with only index lines removed. Matching canonical commits are in BASE..MAIN, and MAIN is an ancestor of HEAD. Every path touched by omitted commits is also checked at HEAD against current MAIN by exact Git blob identity.',
    'missing_nonmerge_count': len(missing_records),
    'matched_nonmerge_count': sum(bool(c['equivalent_main_commits']) for c in missing_records),
    'main_is_ancestor_of_head': subprocess.run(['git', '-C', str(REPO), 'merge-base', '--is-ancestor', MAIN, HEAD]).returncode == 0,
    'missing_nonmerge_commits': missing_records,
    'canonical_commits': canonical_records,
    'current_paths': current_files,
    'all_missing_commits_have_patch_matches': all(c['equivalent_main_commits'] for c in missing_records),
    'all_missing_commits_have_identical_patch_except_index_lines': all(c['identical_patch_except_index_lines'] for c in missing_records),
    'all_current_paths_equal_main': all(c['identical'] for c in current_files),
    'github_actions_used': False,
}
report['passed'] = report['main_is_ancestor_of_head'] and report['all_missing_commits_have_patch_matches'] and report['all_missing_commits_have_identical_patch_except_index_lines'] and report['all_current_paths_equal_main']
(OUT / 'complete-patch-equivalence.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: value for key, value in report.items()
                  if key not in ('missing_nonmerge_commits', 'canonical_commits', 'method')}, indent=2))
for rec in missing_records:
    print(rec['sha'], '=>', ', '.join(rec['equivalent_main_commits']), rec['subject'])
raise SystemExit(0 if report['passed'] else 1)
