#!/usr/bin/env python3
"""Pack completed evidence files deterministically and verify every member."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile


def fingerprint(value):
    return {'bytes': len(value), 'sha256': hashlib.sha256(value).hexdigest(),
            'git_blob_sha1': hashlib.sha1(b'blob ' + str(len(value)).encode() + b'\0' + value).hexdigest()}


def verify(archive, index):
    assert fingerprint(archive.read_bytes()) == index['archive'], 'Archive fingerprint mismatch'
    with tarfile.open(archive, 'r:xz') as stream:
        members = stream.getmembers()
        assert len(members) == len(index['members'])
        assert {member.name for member in members} == set(index['members'])
        for member in members:
            assert member.isfile() and not member.name.startswith('/') and '..' not in Path(member.name).parts
            assert fingerprint(stream.extractfile(member).read()) == index['members'][member.name], member.name
    return {'status': 'passed', 'verified_members': len(index['members']), 'archive_sha256': index['archive']['sha256']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--include', action='append', default=[], help='ARCHIVE_PREFIX=directory or file')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    archive, index_path = args.output / 'evidence.tar.xz', args.output / 'evidence-index.json'
    if args.verify_only:
        print(json.dumps(verify(archive, json.loads(index_path.read_text())), indent=2))
        return
    entries = {}
    for item in args.include:
        prefix, source = item.split('=', 1)
        assert prefix and not prefix.startswith('/') and '..' not in Path(prefix).parts
        source = Path(source)
        paths = sorted(source.rglob('*')) if source.is_dir() else [source]
        for path in paths:
            if not path.is_file() or '__pycache__' in path.parts or path.suffix == '.pyc':
                continue
            name = (Path(prefix) / path.relative_to(source)).as_posix() if source.is_dir() else prefix
            assert name not in entries, name
            entries[name] = path
    assert entries, 'No evidence selected'
    members = {}
    with tarfile.open(archive, 'w:xz', preset=6, format=tarfile.PAX_FORMAT) as stream:
        for name, path in sorted(entries.items()):
            value = path.read_bytes()
            members[name] = fingerprint(value)
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(value), 0o644, 0
            stream.addfile(info, io.BytesIO(value))
    index = {'schema': 'quds.spelling_resume.evidence.v1', 'archive_name': archive.name,
             'archive': fingerprint(archive.read_bytes()), 'member_count': len(members), 'members': members}
    index_path.write_text(json.dumps(index, indent=2, sort_keys=True) + '\n')
    print(json.dumps(verify(archive, index), indent=2))


if __name__ == '__main__':
    main()
