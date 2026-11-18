"""Verify fetched checkpoint objects and every newly published archive member."""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', required=True, type=Path)
parser.add_argument('--plan', required=True, type=Path)
parser.add_argument('--commit', required=True)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
plan = json.loads(args.plan.read_text())

def git(*argv):
    return subprocess.check_output(['git', *argv], cwd=args.repo)

def sha(data):
    return hashlib.sha256(data).hexdigest()

assert git('rev-parse', args.commit + '^{tree}').decode().strip() == plan['tree_sha']
assert git('rev-parse', args.commit + '^').decode().strip() == plan['base_commit']
files, archives = [], []
for row in plan['new_blobs']:
    data = git('show', args.commit + ':' + row['path'])
    blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    assert len(data) == row['bytes'] and blob == row['sha'], row['path']
    files.append({'path': row['path'], 'bytes': len(data), 'git_blob': blob,
                  'sha256': sha(data), 'verified': True})
    if not row['path'].endswith('.tar.index.json'):
        continue
    index = json.loads(data)
    archive_path = str(PurePosixPath(row['path']).parent / index['archive'])
    archive_data = git('show', args.commit + ':' + archive_path)
    assert len(archive_data) == index.get('bytes', index.get('archive_bytes'))
    assert sha(archive_data) == index.get('sha256', index.get('archive_sha256'))
    members = {item['path']: item for item in index['members']}
    assert len(members) == len(index['members'])
    with tarfile.open(fileobj=io.BytesIO(archive_data), mode='r:xz') as archive:
        entries = archive.getmembers()
        assert len(entries) == len(members)
        assert {entry.name for entry in entries} == set(members)
        for entry in entries:
            p = PurePosixPath(entry.name)
            assert entry.isfile() and not p.is_absolute() and '..' not in p.parts
            content = archive.extractfile(entry).read()
            expected = members[entry.name]
            assert len(content) == expected['bytes'] and sha(content) == expected['sha256']
    archives.append({'path': archive_path, 'bytes': len(archive_data),
                     'sha256': sha(archive_data), 'members_verified': len(members)})
report = {'observed_utc': datetime.now(timezone.utc).isoformat(), 'commit': args.commit,
          'parent': plan['base_commit'], 'tree': plan['tree_sha'], 'all_files_verified': True,
          'files': files, 'archives': archives,
          'scope': 'Exact fetched Git objects; complete byte and member readback of newly added archive indexes.'}
args.output.parent.mkdir(parents=True, exist_ok=True)
with args.output.open('x') as stream:
    json.dump(report, stream, indent=2)
    stream.write('\n')
print(json.dumps({'commit': args.commit, 'files_verified': len(files),
                  'archives_verified': len(archives), 'members_verified': sum(a['members_verified'] for a in archives)}))
