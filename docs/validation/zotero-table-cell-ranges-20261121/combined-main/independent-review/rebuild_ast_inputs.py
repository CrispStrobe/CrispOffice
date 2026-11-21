#!/usr/bin/env python3
"""Reconstruct the accepted AST input from immutable Git and recorded modes.

This writes review input outside the repository; it does not run tests or
change Git refs. Original workspace paths are retained deliberately.
"""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path('/workspace/scratch/a4ce103494d8')
REPO = ROOT / 'quds_office_suite'
OUTPUT = ROOT / 'zotero-cell-review/directive-ast-input.jsonl'
DIRECTORY = Path(__file__).resolve().parent
COMMITS = [
    'a6095c304ad2d6935f2ae6f8b74412038d19f142',
    '5289b90a83ce9042a4f4cfb73ba8115fe501513a',
]

versions = json.loads((DIRECTORY / 'ast-language-versions.json').read_text())
expected = json.loads((DIRECTORY / 'impact-ast-review.json').read_text())
needed = {}
for commit in COMMITS:
    raw = subprocess.check_output(['git', 'ls-tree', '-rz', commit], cwd=REPO)
    for row in raw.split(b'\0'):
        if not row:
            continue
        metadata, raw_path = row.split(b'\t', 1)
        mode, kind, blob = metadata.decode().split()
        path = raw_path.decode()
        if kind == 'blob' and path.endswith('.dart'):
            needed.setdefault(blob, path)
objects = sorted(needed)
raw = subprocess.run(
    ['git', 'cat-file', '--batch'], cwd=REPO,
    input=('\n'.join(objects) + '\n').encode(),
    stdout=subprocess.PIPE, check=True,
).stdout
position = 0
rows = []
for blob in objects:
    end = raw.index(b'\n', position)
    actual, kind, size = raw[position:end].decode().split()
    assert actual == blob and kind == 'blob'
    position = end + 1
    size = int(size)
    content = raw[position:position + size].decode()
    position += size + 1
    path = needed[blob]
    language = versions['default_language_version']
    for package in versions['repository_packages']:
        if path == package['root'] or path.startswith(package['root'] + '/'):
            language = package['language_version']
            break
    rows.append(json.dumps({'key': blob, 'path': path, 'content': content,
                            'languageVersion': language}))
assert position == len(raw)
encoded = ('\n'.join(rows) + '\n').encode()
assert hashlib.sha256(encoded).hexdigest() == expected['parsed_input_sha256']
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
OUTPUT.write_bytes(encoded)
print(json.dumps({'parsed_input_sha256': expected['parsed_input_sha256'],
                  'unique_committed_dart_blobs': len(rows),
                  'output': str(OUTPUT)}, indent=2))
