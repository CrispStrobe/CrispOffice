#!/usr/bin/env python3
"""Extract CRC-verified SDK entries from complete downloaded ZIP ranges."""
from pathlib import Path
import hashlib
import json
import os
import zipfile

root = Path('/workspace/scratch/796b63b8623e/toolchain')
archive = root / 'archives/dart-central.zip'
parts = root / 'archives/dart-sdk-linux-x64.zip.parts'
out = root / 'early-sdk'
out.mkdir(exist_ok=True)
coverage = {}
coverage_path = root / 'setup/early-sdk-coverage.json'
previous_coverage = json.loads(coverage_path.read_text()) if coverage_path.exists() else {}
with archive.open('r+b') as target:
    for part in parts.glob('*.part'):
        start = int(part.stem)
        old_length = int(previous_coverage.get(str(start), 0))
        length = part.stat().st_size
        if old_length > length:
            old_length = 0
        with part.open('rb') as source:
            source.seek(old_length)
            data = source.read(length - old_length)
        target.seek(start + old_length)
        target.write(data)
        coverage[start] = start + length
        previous_coverage[str(start)] = length
coverage_path.write_text(json.dumps(previous_coverage) + '\n')

def complete(start, end):
    while start < end:
        chunk = start // (4 * 1024 * 1024) * (4 * 1024 * 1024)
        if coverage.get(chunk, chunk) <= start:
            return False
        start = min(end, coverage[chunk])
    return True

receipt = root / 'setup/early-sdk-receipt.json'
extracted = json.loads(receipt.read_text())['files'] if receipt.exists() else []
already_extracted = {entry['path'] for entry in extracted}
missing = []
snapshots = {'dartdev_aot.dart.snapshot', 'analysis_server_aot.dart.snapshot',
             'frontend_server_aot.dart.snapshot', 'kernel-service.dart.snapshot',
             'kernel_worker_aot.dart.snapshot', 'dds_aot.dart.snapshot'}
with zipfile.ZipFile(archive) as sdk:
    infos = sorted(sdk.infolist(), key=lambda info: info.header_offset)
    for index, info in enumerate(infos):
        name = info.filename
        required = name.startswith('dart-sdk/lib/') or name in {
            'dart-sdk/bin/dart', 'dart-sdk/bin/dartvm', 'dart-sdk/bin/dartaotruntime',
            'dart-sdk/version', 'dart-sdk/revision', 'dart-sdk/sdk_packages.yaml',
        } or name.removeprefix('dart-sdk/bin/snapshots/') in snapshots
        if not required:
            continue
        if name in already_extracted:
            continue
        end = infos[index + 1].header_offset if index + 1 < len(infos) else 238742233
        if not complete(info.header_offset, end):
            missing.append(name)
            continue
        dest = out / name
        if not dest.resolve().is_relative_to(out.resolve()):
            raise ValueError('Invalid archive path')
        data = sdk.read(info)  # zipfile verifies the original per-entry CRC.
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        mode = (info.external_attr >> 16) & 0o777
        dest.chmod(mode or (0o755 if '/bin/' in name else 0o644))
        extracted.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                          'zip_crc32': info.CRC})
record = {'source_url': 'https://storage.googleapis.com/flutter_infra_release/flutter/cf636b1dfb818dd6a3ff16e390e93b1a036969c8/dart-sdk-linux-x64.zip',
          'scope': 'Official unmodified files, verified per-entry CRC; full archive download is ongoing.',
          'files': extracted, 'missing': missing, 'ready': not missing}
(root / 'setup/early-sdk-receipt.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({'ready': not missing, 'extracted': len(extracted), 'missing': missing}, indent=2))
