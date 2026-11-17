import json
import subprocess
import sys

def git(*args):
    return subprocess.check_output(['git', *args])

head = git('rev-parse', sys.argv[1] if len(sys.argv) > 1 else 'HEAD').decode().strip()
parents = git('show', '-s', '--format=%P', head).decode().split()
known = {line.split(b' ', 1)[0].decode() for line in git('rev-list', '--objects', '--remotes').splitlines()}
entries = {}
for record in git('ls-tree', '-rz', head).split(b'\0'):
    if not record:
        continue
    metadata, path = record.split(b'\t', 1)
    mode, kind, sha = metadata.decode().split()
    entries[path.decode()] = {'path': path.decode(), 'mode': mode, 'type': kind, 'sha': sha}
changes = []
blobs = []
for raw_path in git('diff', '--name-only', '--no-renames', '-z', parents[0], head).split(b'\0'):
    if not raw_path:
        continue
    path = raw_path.decode()
    if path not in entries:
        changes.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': None})
        continue
    entry = entries[path].copy()
    if entry['sha'] not in known and entry['type'] == 'blob':
        if not any(blob['sha'] == entry['sha'] for blob in blobs):
            blobs.append({'sha': entry['sha'], 'size': int(git('cat-file', '-s', entry['sha']))})
    changes.append(entry)
print(json.dumps({
    'local_commit': head,
    'parents': parents,
    'message': git('show', '-s', '--format=%B', head).decode().rstrip(),
    'base_tree': git('rev-parse', parents[0] + '^{tree}').decode().strip(),
    'expected_tree': git('rev-parse', head + '^{tree}').decode().strip(),
    'tree_elements': changes,
    'blobs': blobs,
}))
