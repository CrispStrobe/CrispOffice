"""Stage evidence in a separate Git index without touching the frozen checkout."""
import argparse
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--base', required=True)
parser.add_argument('--mapping', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
env = dict(os.environ, GIT_INDEX_FILE=str(args.output.resolve() / 'index'))


def git(*command, input=None):
    return subprocess.check_output(['git', *command], cwd=args.repo, env=env, input=input)


git('read-tree', args.base)
for row in json.loads(args.mapping.read_text()):
    if 'local_path' in row:
        data = Path(row['local_path']).read_bytes()
        sha = git('hash-object', '-w', '--stdin', input=data).decode().strip()
    else:
        sha = row['sha']
    git('update-index', '--add', '--cacheinfo', row.get('mode', '100644'), sha, row['path'])
script = args.repo / 'docs/validation/office-resume-20261118/prepare_checkpoint.py'
subprocess.run([os.sys.executable, str(script), '--repo', str(args.repo),
                '--base', args.base, '--output', str(args.output / 'payload')],
               env=env, check=True)
