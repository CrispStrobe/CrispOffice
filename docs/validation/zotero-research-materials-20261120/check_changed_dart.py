#!/usr/bin/env python3
"""Check every changed Dart file without changing source or resolving packages."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--base', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = args.repo.resolve()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
paths = subprocess.check_output(
    ['git', 'diff', '--name-only', '--diff-filter=ACMR', args.base, 'HEAD', '--', '*.dart'],
    cwd=repo, text=True,
).splitlines()
if not paths:
    raise RuntimeError('No changed Dart targets')
dart = str(Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/dart-sdk/bin/dart')


def fingerprints():
    return {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in paths}


receipt = {
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'base': args.base,
    'paths': paths,
    'before': fingerprints(),
    'checks': {},
}
for name, arguments in [
    ('format', ['format', '--output=none', '--set-exit-if-changed']),
    ('analysis', ['analyze', '--fatal-infos']),
]:
    command = [dart, *arguments, *paths]
    start = time.monotonic()
    with (out / (name + '.log')).open('w') as stream:
        result = subprocess.run(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
    receipt['checks'][name] = {
        'command': command,
        'exit_code': result.returncode,
        'seconds': time.monotonic() - start,
    }
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(name, result.returncode, flush=True)
receipt['after'] = fingerprints()
receipt['inputs_identical'] = receipt['before'] == receipt['after']
receipt['accepted'] = receipt['inputs_identical'] and all(
    check['exit_code'] == 0 for check in receipt['checks'].values()
)
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'targets': len(paths), 'accepted': receipt['accepted']}), flush=True)
raise SystemExit(0 if receipt['accepted'] else 1)
