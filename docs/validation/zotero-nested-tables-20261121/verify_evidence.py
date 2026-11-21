"""Verify retained evidence without extracting or executing archive members."""

import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


def check_bytes(data, expected, label):
    if len(data) != expected['bytes']:
        raise SystemExit(f'Byte count mismatch: {label}')
    if hashlib.sha256(data).hexdigest() != expected['sha256']:
        raise SystemExit(f'SHA-256 mismatch: {label}')


def main():
    root = Path(__file__).resolve().parent
    index = json.loads((root / 'evidence-index.json').read_text())
    total = 0
    for name, record in index['archives'].items():
        path = root / name
        check_bytes(path.read_bytes(), record, name)
        with tarfile.open(path, 'r:gz') as archive:
            members = archive.getmembers()
            names = [member.name for member in members]
            if len(names) != len(set(names)) or set(names) != set(record['members']):
                raise SystemExit(f'Member inventory mismatch: {name}')
            if len(members) != record['member_count']:
                raise SystemExit(f'Member count mismatch: {name}')
            for member in members:
                relative = PurePosixPath(member.name)
                if not member.isfile() or relative.is_absolute() or '..' in relative.parts:
                    raise SystemExit(f'Unexpected member: {member.name}')
                stream = archive.extractfile(member)
                if stream is None:
                    raise SystemExit(f'Missing member bytes: {member.name}')
                with stream:
                    check_bytes(stream.read(), record['members'][member.name], member.name)
            total += len(members)
    for name, record in index.get('files', {}).items():
        check_bytes((root / name).read_bytes(), record, name)
    print(json.dumps({
        'status': 'verified',
        'archives': len(index['archives']),
        'archive_members': total,
        'standalone_files': len(index.get('files', {})),
    }))


if __name__ == '__main__':
    main()
