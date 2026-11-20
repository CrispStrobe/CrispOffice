#!/usr/bin/env python3
"""Archive explicit local qualification outputs and verify every member."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    scratch, output = args.scratch.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    directories = (
        'mail_intake_audit', 'store-mailbox-accepted', 'store-mailbox-reviewed',
        'mail-cached-store-full', 'mail-cached-store-final',
        'mail-cached-store-final-recovery',
        'mail-cached-shared-full', 'mail-cached-shared-final',
        'mail-cached-shared-final-recovery',
        'mail-cached-studio-full', 'mail-cached-studio-final',
        'mail-cached-studio-final-rtl', 'mail-cached-studio-final-recovery',
        'mail-cached-studio-accepted',
        'runtime/logs',
    )
    selected: dict[str, Path] = {}
    for name in directories:
        for path in (scratch / name).rglob('*'):
            if path.is_file() and not path.is_symlink() and '__pycache__' not in path.parts:
                selected[str(path.relative_to(scratch))] = path
    for pattern in (
        'mailbox-store-host-dev*', 'mailbox-store-host-cleanup*',
        'host-cache-analysis*', 'store-mailbox-focused*', 'store-cache-review-*',
        'store-cache-recovery-*',
        'cache_review_probe*', 'cache-independent-review*.json',
        'html-provider-fixture-*',
        'mail-cached-*-review.*', 'intake-api.json',
        'runtime/*receipt.json', 'runtime/cached-mail-*.png',
        'runtime/cached_mail_layout_probe_test.dart',
        'runtime/runtime.json', 'runtime/env.sh',
        'runtime/sdk-release.json', 'runtime/prefetch_locked.py',
    ):
        for path in scratch.glob(pattern):
            if path.is_file() and not path.is_symlink():
                selected[str(path.relative_to(scratch))] = path
    manifest = []
    archive = output / 'evidence.tar.xz'
    with tarfile.open(archive, 'w:xz') as bundle:
        for name, path in sorted(selected.items()):
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data), 0o644, 0
            bundle.addfile(info, io.BytesIO(data))
            manifest.append(dict(path=name, bytes=len(data), sha256=digest))
    by_name = {row['path']: row for row in manifest}
    with tarfile.open(archive, 'r:xz') as bundle:
        members = bundle.getmembers()
        if len(members) != len(manifest):
            raise ValueError('Archive member count mismatch')
        for member in members:
            data = bundle.extractfile(member).read()
            expected = by_name[member.name]
            if len(data) != expected['bytes'] or hashlib.sha256(data).hexdigest() != expected['sha256']:
                raise ValueError('Archive payload mismatch: ' + member.name)
    receipt = dict(members=manifest, archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
                   archive_bytes=archive.stat().st_size, verified=True)
    (output / 'evidence-files.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(dict(members=len(manifest), archive_bytes=receipt['archive_bytes'],
                          archive_sha256=receipt['archive_sha256'], verified=True)))


if __name__ == '__main__':
    main()
