#!/usr/bin/env python3
"""Reconstruct saved evidence parts and verify every extracted byte.

Usage: python unpack_evidence.py --output /absolute/fresh/evidence-directory
The separate development bundle has its own index and instructions.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def safe_name(name):
    path = PurePosixPath(name)
    require(bool(name) and not path.is_absolute() and '..' not in path.parts,
            'Unsafe archive path: ' + repr(name))
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', type=Path,
                        default=Path(__file__).resolve().parent / 'evidence')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    output = args.output.resolve()
    require(not output.exists() or not any(output.iterdir()), 'Output must be empty')
    output.mkdir(parents=True, exist_ok=True)
    manifests = sorted(evidence.rglob('manifest.json'))
    require(manifests, 'No evidence manifests found')
    totals = {'archives': 0, 'files': 0, 'bytes': 0}
    for index in manifests:
        manifest = json.loads(index.read_text())
        chunks = []
        for chunk in manifest['chunks']:
            name = safe_name(chunk['path'])
            require(len(name.parts) == 1, 'Archive part must be alongside manifest')
            data = (index.parent / str(name)).read_bytes()
            require(len(data) == chunk['size'] and sha(data) == chunk['sha256'],
                    'Archive part mismatch: ' + str(name))
            chunks.append(data)
        packed = b''.join(chunks)
        require(len(packed) == manifest['archive_bytes']
                and sha(packed) == manifest['archive_sha256'], 'Combined archive mismatch')
        destination = output / index.parent.relative_to(evidence)
        expected = {item['path']: item for item in manifest['files']}
        require(len(expected) == len(manifest['files']), 'Duplicate indexed file paths')
        with tarfile.open(fileobj=io.BytesIO(packed), mode='r:xz') as archive:
            actual = archive.getmembers()
            require(len(actual) == len(expected) and {m.name for m in actual} == set(expected),
                    'Archive membership differs from index')
            for member in actual:
                name = safe_name(member.name)
                require(member.isfile() or member.islnk(), 'Unsupported archive member type')
                if member.islnk():
                    require(str(safe_name(member.linkname)) in expected,
                            'Hard-link target is outside the indexed archive')
                data = archive.extractfile(member).read()
                entry = expected[member.name]
                require(len(data) == entry['size'] and sha(data) == entry['sha256'],
                        'Archived member mismatch: ' + member.name)
                path = destination / str(name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
                totals['files'] += 1
                totals['bytes'] += len(data)
        totals['archives'] += 1
    print(json.dumps(dict(passed=True, **totals)))


if __name__ == '__main__':
    main()
