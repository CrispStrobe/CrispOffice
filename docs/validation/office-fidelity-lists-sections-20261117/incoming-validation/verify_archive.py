#!/usr/bin/env python3
"""Verify and restore the complete incoming validation archive."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

parser = argparse.ArgumentParser()
parser.add_argument('destination', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent
manifest = json.loads((root / 'manifest.json').read_text())
archive = root / manifest['archive']
assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest['archive_sha256']
args.destination.mkdir(parents=True, exist_ok=False)
observed = {}
with tarfile.open(archive) as tar:
    for member in tar.getmembers():
        assert member.isfile() and member.name.startswith(manifest['archive_prefix'])
        relative = Path(member.name).relative_to(manifest['archive_prefix'])
        assert not relative.is_absolute() and '..' not in relative.parts
        assert str(relative) not in observed
        stream = tar.extractfile(member)
        assert stream is not None
        data = stream.read()
        identity = {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
        assert identity == manifest['files'][str(relative)]
        target = args.destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        observed[str(relative)] = identity
assert observed == manifest['files']
print(json.dumps({'verified_files': len(observed), 'destination': str(args.destination)}))
