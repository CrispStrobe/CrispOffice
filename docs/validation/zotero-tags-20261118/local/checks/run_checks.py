#!/usr/bin/env python3
"""Record analysis/format/whitespace checks against one exact product commit."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--dart', type=Path, required=True)
parser.add_argument('--product', required=True)
args = parser.parse_args()
repo = args.repo.resolve()
out = Path(__file__).resolve().parent
paths = [
    'packages/quds_office_engine/lib/src/zotero/zotero_models.dart',
    'packages/quds_office_engine/lib/src/zotero/zotero_client.dart',
    'packages/quds_office_engine/test/zotero_tag_filter_test.dart',
    'packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart',
    'packages/quds_office_editor/test/word_zotero_tag_filter_test.dart',
]


def hashes():
    return {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in paths}


before = hashes()
commands = {
    'analyze': [str(args.dart), 'analyze', '--fatal-infos', *paths],
    'format': [str(args.dart), 'format', '--language-version=3.12',
               '--output=none', '--set-exit-if-changed', *paths],
    'committed-whitespace': ['git', 'diff', '--check',
                            'c60fce9c37ca960eb64dd06c7ffc55b2fdbb2ed7', args.product],
    'working-whitespace': ['git', 'diff', '--check'],
}
results = {}
for name, command in commands.items():
    result = subprocess.run(command, cwd=repo, capture_output=True, text=True)
    log = result.stdout + result.stderr
    (out / f'{name}.log').write_text(log)
    results[name] = {'command': command, 'exit_code': result.returncode,
                     'log': f'{name}.log',
                     'log_sha256': hashlib.sha256(log.encode()).hexdigest()}
after = hashes()
matches = {}
for path in paths:
    blob = subprocess.check_output(['git', 'show', f'{args.product}:{path}'], cwd=repo)
    matches[path] = hashlib.sha256(blob).hexdigest() == after[path]
passed = before == after and all(matches.values()) and all(
    result['exit_code'] == 0 for result in results.values())
summary = {'status': 'passed' if passed else 'failed',
           'qualified_product_commit': args.product, 'cwd': str(repo),
           'checks': results, 'source_before': before, 'source_after': after,
           'source_unchanged': before == after, 'source_matches_product': matches}
(out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({'status': summary['status'], 'targets': len(paths),
                  'checks': {name: result['exit_code'] for name, result in results.items()}}))
raise SystemExit(0 if passed else 1)
