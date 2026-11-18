#!/usr/bin/env python3
"""Prepare evidence objects for authenticated GitHub API publication with a separate index."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--content', type=Path, required=True)
    parser.add_argument('--prefix', required=True)
    parser.add_argument('--branch', required=True)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--message', required=True)
    parser.add_argument('--receipt-dir', type=Path, required=True)
    args = parser.parse_args()
    repo, content, out = [p.resolve() for p in (args.repo, args.content, args.receipt_dir)]
    assert not content.is_relative_to(repo)
    out.mkdir(parents=True, exist_ok=False)
    assert '[skip ci]' in args.message
    env = dict(os.environ, GIT_INDEX_FILE=str(out / 'index'))

    def git(*argv, data=None, isolated=False):
        return subprocess.check_output(['git', *argv], cwd=repo,
                                       env=env if isolated else None, input=data)

    frozen = git('rev-parse', 'HEAD').decode().strip()
    assert not git('status', '--porcelain=v1'), 'Frozen source checkout is dirty'
    ref = 'refs/heads/' + args.branch
    observed = git('ls-remote', '--exit-code', 'origin', ref).decode().split()[0]
    assert observed == args.expected_head, (observed, args.expected_head)
    git('cat-file', '-e', observed + '^{commit}')
    git('read-tree', observed, isolated=True)
    files = []
    for path in sorted(content.rglob('*')):
        if not path.is_file():
            continue
        data = path.read_bytes()
        target = args.prefix.rstrip('/') + '/' + path.relative_to(content).as_posix()
        blob = git('hash-object', '-w', '--stdin', data=data).decode().strip()
        git('update-index', '--add', '--cacheinfo', '100644', blob, target, isolated=True)
        files.append({'path': target, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'git_blob': blob})
    tree = git('write-tree', isolated=True).decode().strip()
    assert tree != git('rev-parse', observed + '^{tree}').decode().strip(), 'No changes to publish'
    payload_dir = out / 'payload'
    payload_dir.mkdir()
    changed = git('diff-tree', '-r', '--no-commit-id', '--name-only', '-z', observed, tree).split(b'\0')
    changed = {p.decode() for p in changed if p}
    elements, blobs = [], []
    import base64
    for row in files:
        if row['path'] not in changed:
            continue
        blob = row['git_blob']
        elements.append({'path': row['path'], 'mode': '100644', 'type': 'blob', 'sha': blob})
        data = git('cat-file', 'blob', blob)
        encoded = base64.b64encode(data).decode()
        parts = []
        for offset in range(0, len(encoded), 32768):
            part = payload_dir / (blob + '.' + str(len(parts)).zfill(4) + '.b64')
            part.write_text(encoded[offset:offset + 32768])
            parts.append(str(part))
        blobs.append({'sha': blob, 'bytes': len(data), 'parts': parts, 'path': row['path']})
    payload = {'base_commit': observed, 'base_tree_sha': git('rev-parse', observed + '^{tree}').decode().strip(),
               'tree_sha': tree, 'tree_elements': elements, 'new_blobs': blobs}
    (payload_dir / 'payload.json').write_text(json.dumps(payload, indent=2) + '\n')
    assert git('rev-parse', 'HEAD').decode().strip() == frozen
    assert not git('status', '--porcelain=v1')
    receipt = {'prepared_utc': datetime.now(timezone.utc).isoformat(), 'parent': observed,
               'tree': tree, 'branch': args.branch, 'frozen_checkout': frozen,
               'message': args.message, 'force': False, 'files': files,
               'publication': 'pending authenticated GitHub Git Data calls'}
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'tree': tree, 'files': len(files), 'receipt': str(out / 'receipt.json')}))


if __name__ == '__main__':
    main()
