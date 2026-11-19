#!/usr/bin/env python3
"""Create a deterministic evidence archive and verify every indexed member."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile

p = argparse.ArgumentParser()
p.add_argument('--input', action='append', required=True, help='archive-prefix=directory')
p.add_argument('--archive', type=Path, required=True)
p.add_argument('--index', type=Path, required=True)
a = p.parse_args()

def digest(data):
    return hashlib.sha256(data).hexdigest()

members = []
names = set()
a.archive.parent.mkdir(parents=True, exist_ok=True)
if a.archive.exists() or a.index.exists():
    raise RuntimeError('Preserve existing evidence; select new output names')
with tarfile.open(a.archive, 'w:xz', preset=6) as bundle:
    for argument in a.input:
        prefix, path = argument.split('=', 1)
        relative = PurePosixPath(prefix)
        if relative.is_absolute() or '..' in relative.parts:
            raise RuntimeError('Unsafe archive prefix')
        root = Path(path).resolve()
        if not root.is_dir():
            raise RuntimeError('Evidence input must be a directory')
        for source in sorted(root.rglob('*')):
            if source.is_symlink():
                raise RuntimeError('Evidence symlinks are not accepted')
            if not source.is_file():
                continue
            name = str(relative / source.relative_to(root).as_posix())
            if name in names:
                raise RuntimeError('Duplicate archive member: ' + name)
            names.add(name)
            data = source.read_bytes()
            member = tarfile.TarInfo(name)
            member.size = len(data)
            member.mode = 0o644
            member.mtime = 0
            bundle.addfile(member, io.BytesIO(data))
            members.append({'path': name, 'bytes': len(data), 'sha256': digest(data)})
expected = {row['path']: row for row in members}
with tarfile.open(a.archive, 'r:xz') as bundle:
    actual = bundle.getmembers()
    if len(actual) != len(expected) or {m.name for m in actual} != set(expected):
        raise RuntimeError('Archive membership mismatch')
    for member in actual:
        data = bundle.extractfile(member).read()
        row = expected[member.name]
        if not member.isfile() or len(data) != row['bytes'] or digest(data) != row['sha256']:
            raise RuntimeError('Archive member mismatch: ' + member.name)
index = {'archive': a.archive.name, 'bytes': a.archive.stat().st_size,
         'sha256': digest(a.archive.read_bytes()), 'members': members,
         'member_count': len(members), 'all_members_reopened_and_verified': True}
a.index.write_text(json.dumps(index, indent=2) + '\n')
print(json.dumps({key: index[key] for key in
                  ('archive', 'bytes', 'sha256', 'member_count', 'all_members_reopened_and_verified')}))
