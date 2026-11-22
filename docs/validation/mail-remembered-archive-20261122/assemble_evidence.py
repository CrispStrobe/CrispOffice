#!/usr/bin/env python3
"""Verify the recorded archive parts and reconstruct the local evidence archive."""

import argparse
import hashlib
import json
from pathlib import Path


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--output', type=Path, default=Path('mail-remembered-archive-evidence.tar.xz')
    )
    args = parser.parse_args()
    evidence = Path(__file__).resolve().parent / 'evidence'
    manifest = json.loads((evidence / 'index.json').read_text())
    parts = []
    for entry in manifest['parts']:
        name = entry['file']
        if Path(name).name != name:
            raise SystemExit('Invalid archive part path in index')
        data = (evidence / name).read_bytes()
        if len(data) != entry['bytes'] or digest(data) != entry['sha256']:
            raise SystemExit('Archive part failed verification: ' + name)
        parts.append(data)
    archive = b''.join(parts)
    if (
        len(archive) != manifest['archive_bytes']
        or digest(archive) != manifest['archive_sha256']
    ):
        raise SystemExit('Reconstructed archive failed verification')
    if args.output.exists():
        if args.output.read_bytes() != archive:
            raise SystemExit('Output already exists with different content; choose another path')
    else:
        with args.output.open('xb') as target:
            target.write(archive)
    print(f'Verified {len(parts)} parts and {manifest["member_count"]} indexed members')
    print(f'Archive: {args.output.resolve()}')
    print(f'SHA-256: {manifest["archive_sha256"]}')


if __name__ == '__main__':
    main()
