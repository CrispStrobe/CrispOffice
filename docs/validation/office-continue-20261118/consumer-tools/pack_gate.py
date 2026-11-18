#!/usr/bin/env python3
"""Pack a completed consumer gate and verify every archived evidence byte."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import tarfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    args = parser.parse_args()
    source, archive = args.input.resolve(), args.archive.resolve()
    assert source.is_dir() and not archive.exists()
    excluded = {'lo-profile', 'profiles', 'profile-pdf', 'profile-docx', '__pycache__', 'tmp'}
    paths = [path for path in sorted(source.rglob('*'))
             if path.is_file() and not excluded.intersection(path.relative_to(source).parts)]
    assert paths
    manifest = [{'path': str(path.relative_to(source)), 'bytes': path.stat().st_size,
                 'sha256': digest(path)} for path in paths]
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'w:xz', preset=3) as output:
        for path in paths:
            info = output.gettarinfo(str(path), arcname=str(path.relative_to(source)))
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            info.mtime = 0
            with path.open('rb') as stream:
                output.addfile(info, stream)
    expected = {item['path']: item for item in manifest}
    seen = set()
    with tarfile.open(archive) as packed:
        for member in packed:
            assert member.isfile() and member.name not in seen
            data = packed.extractfile(member).read()
            assert len(data) == expected[member.name]['bytes']
            assert hashlib.sha256(data).hexdigest() == expected[member.name]['sha256']
            seen.add(member.name)
    assert seen == set(expected)
    result = {'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'archive': archive.name, 'sha256': digest(archive),
              'bytes': archive.stat().st_size, 'member_count': len(manifest),
              'members': manifest, 'readback_verified': True,
              'excluded_disposable_directories': sorted(excluded)}
    archive.with_suffix('.index.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'members'}))


if __name__ == '__main__':
    main()
