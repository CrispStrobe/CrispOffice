#!/usr/bin/env python3
"""Archive completed evidence with deterministic members and read-back hashes."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pack(output, files, status):
    assert not output.exists(), output
    rows = []
    with tarfile.open(output, 'w:xz') as archive:
        for name, path in sorted(files.items()):
            assert not path.is_symlink() and path.is_file(), path
            data = path.read_bytes()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))
            rows.append({'path': name, 'bytes': len(data), 'sha256': digest(data)})
    with tarfile.open(output) as archive:
        assert archive.getnames() == [row['path'] for row in rows]
        for row in rows:
            data = archive.extractfile(row['path']).read()
            assert len(data) == row['bytes'] and digest(data) == row['sha256']
    index = {'archive': output.name, 'bytes': output.stat().st_size,
             'sha256': digest(output.read_bytes()), 'classification': status,
             'member_count': len(rows), 'all_members_read_back_and_verified': True,
             'members': rows}
    output.with_suffix('.index.json').write_text(json.dumps(index, indent=2) + '\n')
    print(json.dumps({k: v for k, v in index.items() if k != 'members'}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--classification', required=True)
    parser.add_argument('--directory', action='append', default=[], help='archive-prefix=directory')
    parser.add_argument('--file', action='append', default=[], help='archive-name=file')
    args = parser.parse_args()
    files = {}
    for value in args.directory:
        prefix, path = value.split('=', 1)
        root = Path(path)
        for child in root.rglob('*'):
            if child.is_file() and not child.is_symlink() and '__pycache__' not in child.parts and child.name != 'run.lock':
                files[prefix + '/' + str(child.relative_to(root))] = child
    for value in args.file:
        name, path = value.split('=', 1)
        files[name] = Path(path)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    pack(args.output, files, args.classification)


if __name__ == '__main__':
    main()
