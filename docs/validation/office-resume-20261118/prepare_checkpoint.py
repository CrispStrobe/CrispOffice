#!/usr/bin/env python3
"""Prepare staged Git objects for API publication without credentials or ref writes.

The caller uploads missing blobs, verifies their object IDs, creates the tree
and commit, then updates its branch with a non-force expected-head lease. The
payload directory is external to the repository and contains only staged bytes.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--base', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = args.repo.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=repo)


def tree_entries(tree):
    result = {}
    for item in git('ls-tree', '-r', '-z', tree).split(b'\0'):
        if not item:
            continue
        metadata, path = item.split(b'\t', 1)
        mode, kind, sha = metadata.decode().split()
        assert kind == 'blob', (path, kind)
        result[path.decode()] = (mode, sha)
    return result


base_tree = git('rev-parse', args.base + '^{tree}').decode().strip()
target_tree = git('write-tree').decode().strip()
before, after = tree_entries(base_tree), tree_entries(target_tree)
known = {row.split(b' ', 1)[0].decode()
         for row in git('rev-list', '--objects', '--remotes').splitlines()}
elements, blobs = [], {}
for path in sorted(before.keys() | after.keys()):
    if before.get(path) == after.get(path):
        continue
    if path not in after:
        elements.append({'path': path, 'mode': before[path][0],
                         'type': 'blob', 'sha': None})
        continue
    mode, sha = after[path]
    elements.append({'path': path, 'mode': mode, 'type': 'blob', 'sha': sha})
    if sha in known or sha in blobs:
        continue
    data = git('cat-file', 'blob', sha)
    assert hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == sha
    encoded = base64.b64encode(data).decode()
    parts = []
    for offset in range(0, len(encoded), 65536):
        part = output / f'{sha}.{len(parts):04d}.b64'
        part.write_text(encoded[offset:offset + 65536])
        parts.append(str(part))
    blobs[sha] = {'sha': sha, 'bytes': len(data), 'parts': parts, 'path': path}

payload = {'base_commit': args.base, 'base_tree_sha': base_tree,
           'tree_sha': target_tree, 'tree_elements': elements,
           'new_blobs': list(blobs.values())}
(output / 'payload.json').write_text(json.dumps(payload, indent=2) + '\n')
print(json.dumps({'tree_sha': target_tree, 'changed_paths': len(elements),
                  'new_blobs': len(blobs), 'bytes': sum(b['bytes'] for b in blobs.values()),
                  'payload': str(output / 'payload.json')}))
