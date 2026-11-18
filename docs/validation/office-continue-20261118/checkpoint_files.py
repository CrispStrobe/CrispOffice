#!/usr/bin/env python3
"""Stage evidence in an external Git index without changing frozen source."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--base', required=True)
parser.add_argument('--manifest', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo, output = args.repo.resolve(), args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
env = dict(os.environ, GIT_INDEX_FILE=str(output / 'index'))

def git(*arguments, data=None):
    return subprocess.check_output(['git', *arguments], cwd=repo, env=env, input=data)

before_head = git('rev-parse', 'HEAD').decode().strip()
before_status = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=repo)
git('read-tree', args.base)
receipt = []
for row in json.loads(args.manifest.read_text()):
    source = Path(row['source']).resolve()
    destination = row['path']
    assert destination.startswith('docs/validation/office-continue-20261118/')
    assert '..' not in Path(destination).parts
    data = source.read_bytes()
    blob = git('hash-object', '-w', '--stdin', data=data).decode().strip()
    git('update-index', '--add', '--cacheinfo', '100644', blob, destination)
    receipt.append({'path': destination, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'git_blob': blob})
(output / 'staging-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
subprocess.run(['python3', str(repo / 'docs/validation/office-resume-20261118/prepare_checkpoint.py'), '--repo', str(repo), '--base', args.base, '--output', str(output / 'payload')], env=env, check=True)
assert git('rev-parse', 'HEAD').decode().strip() == before_head
normal_status = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=repo)
assert normal_status == before_status
