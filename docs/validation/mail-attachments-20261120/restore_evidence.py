#!/usr/bin/env python3
"""Restore the original flat validation-input layout into a new directory.

This copies recorded evidence and verifies indexed archive contents. It does
not execute tests or download/replace runtimes, dependencies or Git objects.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tarfile


def unpack(base: Path, archive_name: str, index_name: str, target: Path) -> None:
    archive = base / archive_name
    index = json.loads((base / index_name).read_text())
    assert archive.stat().st_size == index['archive_bytes']
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == index['archive_sha256']
    records = {row['path']: row for row in index['files']}
    with tarfile.open(archive, 'r:*') as reader:
        members = reader.getmembers()
        assert len(members) == len(records)
        assert {member.name for member in members} == set(records)
        for member in members:
            relative = PurePosixPath(member.name)
            if not member.isfile() or relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unexpected archive member: ' + member.name)
            stream = reader.extractfile(member)
            assert stream is not None
            data = stream.read()
            record = records[member.name]
            assert len(data) == record['bytes']
            assert hashlib.sha256(data).hexdigest() == record['sha256']
            path = target / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.exists() and path.read_bytes() != data:
                raise ValueError('Evidence collision: ' + str(path))
            path.write_bytes(data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    base = Path(__file__).resolve().parent
    target = args.output.resolve()
    target.mkdir(parents=True, exist_ok=False)
    mappings = {
        'flutter-cohorts': 'flutter-cohorts',
        'flutter-cohorts/final-input-audit': 'flutter-final-input-audit-58c6962',
        'incoming-office/engine-rendering': 'engine-rendering',
        'incoming-office/spacy-package': 'spacy-package',
        'incoming-office/macros': 'engine-macro-serialization',
        'incoming-office/analysis': 'engine-spacy-analysis',
        'incoming-office/slide-background': 'slide-background',
        'static': 'changed-static-final',
        'arabic-composer': 'arabic-capture-readable',
        'independent-audit': 'independent-audit',
        'post-main-comment-draft': 'post-main-comment-draft',
        'resumed/reconciliation': 'reconciliation',
    }
    for source, destination in mappings.items():
        shutil.copytree(base / source, target / destination)
    if (base / 'post-main-macos').is_dir():
        shutil.copytree(base / 'post-main-macos', target / 'macos-portability-refresh')
        unpack(base, 'post-main-macos/script-checks/raw-evidence.tar.xz',
               'post-main-macos/script-checks/raw-evidence.index.json',
               target / 'macos-portability-refresh/script-checks')
    unpack(base, 'mail-packages/raw-evidence.tar.xz',
           'mail-packages/raw-evidence.index.json', target / 'mail-packages')
    unpack(base, 'diagnostics/development.tar.xz',
           'diagnostics/development.index.json', target)
    unpack(base, 'diagnostics/preliminary-mail-packages.tar.xz',
           'diagnostics/preliminary-mail-packages.index.json',
           target / 'mail-packages-preliminary-pptx-lock-update')
    files = [path for path in target.rglob('*') if path.is_file()]
    print(json.dumps({'output': str(target), 'files': len(files),
                      'bytes': sum(path.stat().st_size for path in files),
                      'archives_verified': True,
                      'runtime_dependencies_and_git_objects_not_installed': True}))


if __name__ == '__main__':
    main()
