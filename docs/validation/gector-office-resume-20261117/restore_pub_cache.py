#!/usr/bin/env python3
"""Restore hosted packages from exact checked-in locks for offline resolution."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path
import tarfile
import urllib.request
import yaml

REPO = Path(__file__).resolve().parents[3]
RUNTIME = REPO.parent / 'toolchains'
CACHE = RUNTIME / 'pub-cache'
LOCKS = [RUNTIME / 'flutter-sdk/packages/flutter_tools/pubspec.lock',
         REPO / 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock']
packages = {}
for lock in LOCKS:
    for name, value in yaml.safe_load(lock.read_text())['packages'].items():
        if value['source'] != 'hosted':
            continue
        description = value['description']
        assert description['url'] == 'https://pub.dev'
        key = (name, value['version'])
        expected = description['sha256']
        assert key not in packages or packages[key] == expected
        packages[key] = expected

def restore(item):
    (name, version), expected = item
    destination = CACHE / 'hosted/pub.dev' / f'{name}-{version}'
    hashfile = CACHE / 'hosted-hashes/pub.dev' / f'{name}-{version}.sha256'
    if destination.is_dir() and hashfile.is_file() and hashfile.read_text().strip() == expected:
        # Pub compares the cached checksum text verbatim; no trailing newline.
        hashfile.write_text(expected)
        return {'name': name, 'version': version, 'sha256': expected, 'status': 'existing-verified-download'}
    assert not destination.exists(), destination
    url = f'https://pub.dev/api/archives/{name}-{version}.tar.gz'
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    actual = hashlib.sha256(data).hexdigest()
    assert actual == expected, (name, actual, expected)
    destination.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        archive.extractall(destination, filter='data')
    hashfile.parent.mkdir(parents=True, exist_ok=True)
    hashfile.write_text(expected)
    return {'name': name, 'version': version, 'sha256': expected, 'status': 'verified-download',
            'url': url, 'archive_bytes': len(data)}

with ThreadPoolExecutor(max_workers=8) as executor:
    receipts = list(executor.map(restore, sorted(packages.items())))
result = {'locks': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in LOCKS},
          'packages': receipts}
(RUNTIME / 'pub-cache-recovery.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'packages_verified': len(receipts), 'cache': str(CACHE)}))
