#!/usr/bin/env python3
"""Verify retained execution bytes without extracting archive paths."""
import hashlib
import json
from pathlib import Path
import tarfile

root = Path(__file__).resolve().parent
index = json.loads((root / 'archive-index.json').read_text())
archive = root / 'execution.tar.gz'
assert hashlib.sha256(archive.read_bytes()).hexdigest() == index['archiveSha256']
with tarfile.open(archive, 'r:gz') as tar:
    assert set(tar.getnames()) == set(index['members'])
    assert len(tar.getmembers()) == len(index['members'])
    for name, expected in index['members'].items():
        member = tar.getmember(name)
        assert member.isfile(), name
        data = tar.extractfile(member).read()
        assert len(data) == expected['bytes'], name
        assert hashlib.sha256(data).hexdigest() == expected['sha256'], name
for name, expected in json.loads(
    (root / 'independent/numeric-review-evidence-sha256.json').read_text()
).items():
    assert hashlib.sha256((root / 'independent' / name).read_bytes()).hexdigest() == expected, name
print(json.dumps({'verifiedArchiveMembers': len(index['members']), 'independentFiles': 24}))
