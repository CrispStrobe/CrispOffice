#!/usr/bin/env python3
"""Verify the retained evidence archive and its complete qualified source map."""

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def source_paths(repo):
    output = subprocess.check_output(
        ['rg', '--files', 'packages', 'third_party'], cwd=repo, text=True
    )
    paths = set()
    for path in output.splitlines():
        value = Path(path)
        if any(part in value.parts for part in ('.dart_tool', 'build', 'docs')):
            continue
        if (value.suffix == '.dart'
                or value.name in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')
                or '/test/fixtures/' in path
                or (path.startswith('packages/quds_office_engine/example/macros/')
                    and value.suffix == '.bas')):
            paths.add(path)
    for path in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'):
        if (repo / path).is_file():
            paths.add(path)
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--archive-only', action='store_true')
    parser.add_argument('--bundle', type=Path,
                        help='Evidence directory; defaults to this original qualification bundle')
    args = parser.parse_args()
    directory = args.bundle.resolve() if args.bundle else Path(__file__).resolve().parent
    index = json.loads((directory / 'evidence-index.json').read_text())
    archive_path = directory / index['archive']
    require(digest(archive_path.read_bytes()) == index['archive_sha256'], 'Archive checksum mismatch')
    expected = {entry['path']: entry for entry in index['members']}
    require(len(expected) == len(index['members']), 'Duplicate indexed members')
    with tarfile.open(archive_path, 'r:xz') as archive:
        members = archive.getmembers()
        require(len(members) == len(expected), 'Archive member count mismatch')
        require({member.name for member in members} == set(expected), 'Archive member set mismatch')
        for member in members:
            require(member.isfile(), f'Non-file archive member: {member.name}')
            require(not Path(member.name).is_absolute() and '..' not in Path(member.name).parts,
                    f'Unsafe archive path: {member.name}')
            data = archive.extractfile(member).read()
            record = expected[member.name]
            require(len(data) == record['size'], f'Size mismatch: {member.name}')
            require(digest(data) == record['sha256'], f'Content mismatch: {member.name}')
        manifest = json.loads(gzip.decompress(
            archive.extractfile(index['qualified_source_member']).read()
        ))
    canonical = (json.dumps(manifest, sort_keys=True, separators=(',', ':')) + '\n').encode()
    require(digest(canonical) == index['qualified_source_map_sha256'], 'Source-map checksum mismatch')
    if not args.archive_only:
        actual_paths = source_paths(args.repo)
        require(actual_paths == set(manifest), (
            f'Qualified source path set changed: added={sorted(actual_paths - set(manifest))}, '
            f'removed={sorted(set(manifest) - actual_paths)}'
        ))
        for path, record in manifest.items():
            source = args.repo / path
            data = source.read_bytes()
            require(len(data) == record['size'], f'Source size changed: {path}')
            require(digest(data) == record['sha256'], f'Source changed: {path}')
            git_object = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            require(git_object == record['git_blob_sha1'], f'Git blob mismatch: {path}')
            require(bool(source.stat().st_mode & 0o111) == record['executable'], f'Mode changed: {path}')
    print(json.dumps({
        'archive_verified': True,
        'members': len(expected),
        'qualified_source_inputs': len(manifest),
        'source_verified': not args.archive_only,
        'source_map_sha256': digest(canonical),
    }, indent=2))


if __name__ == '__main__':
    main()
