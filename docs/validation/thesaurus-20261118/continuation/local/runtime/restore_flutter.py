#!/usr/bin/env python3
"""Restore the recorded official SDK without changing telemetry consent."""
import hashlib
import json
from pathlib import Path
import tarfile
import time
import urllib.request

ROOT = Path('/workspace/scratch/51a3f3361ce7')
RUNTIME = ROOT / 'zotero-toolchain'
URL = 'https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz'
EXPECTED = 'baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2'
RUNTIME.mkdir(exist_ok=True)
archive = RUNTIME / 'flutter_linux_3.47.8-stable.tar.xz'
start = time.monotonic()
digest = hashlib.sha256()
if archive.exists():
    with archive.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            digest.update(chunk)
else:
    partial = archive.with_suffix('.partial')
    with urllib.request.urlopen(URL, timeout=120) as source, partial.open('wb') as output:
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b''):
            digest.update(chunk)
            output.write(chunk)
    partial.rename(archive)
assert digest.hexdigest() == EXPECTED, digest.hexdigest()
print(json.dumps({'download_verified': True, 'bytes': archive.stat().st_size}), flush=True)
destination = RUNTIME / 'flutter-sdk'
assert not destination.exists(), destination
with tarfile.open(archive, 'r:xz') as bundle:
    bundle.extractall(RUNTIME, filter='data')
(RUNTIME / 'flutter').rename(destination)
receipt = {'url': URL, 'archive_sha256': EXPECTED, 'archive_bytes': archive.stat().st_size,
           'sdk_root': str(destination), 'elapsed_seconds': time.monotonic() - start,
           'telemetry_environment_required': {'DASH__SUPPRESS_ANALYTICS': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'CI': 'true'},
           'telemetry_consent_changed': False}
(RUNTIME / 'flutter-recovery.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt), flush=True)
