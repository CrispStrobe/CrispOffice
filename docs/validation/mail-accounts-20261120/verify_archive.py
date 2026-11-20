#!/usr/bin/env python3
"""Verify the exact evidence archive and every regular member without extraction."""

import argparse
import hashlib
import json
from pathlib import Path
import tarfile


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path,
                        default=Path(__file__).with_name('evidence-manifest.json'))
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    archive = args.archive or args.manifest.parent / manifest['archive']['file']
    archive_sha = sha(archive)
    errors = []
    if archive_sha != manifest['archive']['sha256']:
        errors.append('Archive SHA-256 differs from the manifest.')
    if archive.stat().st_size != manifest['archive']['bytes']:
        errors.append('Archive size differs from the manifest.')
    expected = {item['path']: item for item in manifest['members']}
    if len(expected) != len(manifest['members']):
        errors.append('Duplicate expected member paths.')
    observed = set()
    with tarfile.open(archive, 'r:xz') as bundle:
        for member in bundle:
            if not member.isfile() or member.name not in expected or member.name in observed:
                errors.append('Unexpected, non-regular or duplicate member: ' + member.name)
                continue
            observed.add(member.name)
            wanted = expected[member.name]
            stream = bundle.extractfile(member)
            if (member.size != wanted['bytes']
                    or hashlib.file_digest(stream, 'sha256').hexdigest() != wanted['sha256']):
                errors.append('Member content mismatch: ' + member.name)
    for missing in sorted(expected.keys() - observed):
        errors.append('Missing member: ' + missing)
    result = {'archive': archive.name, 'archive_sha256': archive_sha,
              'archive_bytes': archive.stat().st_size,
              'manifest_sha256': sha(args.manifest),
              'verified_members': len(observed), 'errors': errors,
              'passed': not errors,
              'scope': 'Archive integrity only; raw-event replay and Git source continuity are separate.'}
    rendered = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.write_text(rendered)
    print(rendered, end='')
    return 0 if not errors else 1


if __name__ == '__main__':
    raise SystemExit(main())
