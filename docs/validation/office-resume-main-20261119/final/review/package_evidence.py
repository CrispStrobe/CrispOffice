#!/usr/bin/env python3
"""Pack explicitly selected workspace evidence and verify every archived byte."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--status', required=True)
    parser.add_argument('--include', action='append', required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    archive = args.archive.resolve()
    files = {}
    for entry in args.include:
        item = (root / entry).resolve()
        item.relative_to(root)
        if not item.exists():
            raise FileNotFoundError(item)
        candidates = [item] if item.is_file() else sorted(item.rglob('*'))
        for path in candidates:
            if path.is_file():
                if path.is_symlink() or path.resolve() == archive:
                    raise ValueError('Unexpected linked/self-referential input: ' + str(path))
                files[path.relative_to(root).as_posix()] = path.read_bytes()
    archive.parent.mkdir(parents=True, exist_ok=True)
    members = []
    with tarfile.open(archive, 'w:xz', preset=6, format=tarfile.PAX_FORMAT) as stream:
        for name, data in sorted(files.items()):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            stream.addfile(info, io.BytesIO(data))
            members.append({'path': name, 'bytes': len(data), 'sha256': sha256(data)})
    with tarfile.open(archive, 'r:xz') as stream:
        assert stream.getnames() == [m['path'] for m in members]
        for member in members:
            data = stream.extractfile(member['path']).read()
            assert len(data) == member['bytes']
            assert sha256(data) == member['sha256']
    index = {'source_commit': args.source, 'status': args.status,
             'archive': archive.name, 'bytes': archive.stat().st_size,
             'sha256': sha256(archive.read_bytes()),
             'member_count': len(members), 'members': members}
    target = archive.with_suffix('').with_suffix('.index.json')
    target.write_text(json.dumps(index, indent=2) + '\n')
    print(json.dumps({k: v for k, v in index.items() if k != 'members'}))


if __name__ == '__main__':
    main()
