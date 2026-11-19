#!/usr/bin/env python3
"""Reproduce the separate current-source workspace used for local qualification."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
source = root / 'quds_office_suite'
workspace = root / 'zotero-validation'
toolchain = root / 'zotero-toolchain'
members = re.findall(
    r'^  - (\S+)\s*$',
    (source / 'pubspec.yaml').read_text().split('\nworkspace:\n', 1)[1],
    re.M,
)
workspace.mkdir(exist_ok=True)
for member in members:
    (workspace / member).mkdir(parents=True, exist_ok=True)
manifests = ['pubspec.yaml'] + [p + '/pubspec.yaml' for p in members]
for path in manifests:
    shutil.copy2(source / path, workspace / path)
skip = {'.git', '.dart_tool', 'build', 'pubspec.yaml', 'pubspec.lock',
        'pubspec_overrides.yaml'}
links = {}
for member in members:
    for child in (source / member).iterdir():
        target = workspace / member / child.name
        if child.name in skip:
            continue
        if target.exists() or target.is_symlink():
            relative = target.relative_to(workspace).as_posix()
            nested_member = any(m == relative or m.startswith(relative + '/') for m in members)
            if nested_member and target.is_dir() and not target.is_symlink():
                continue
            if not target.is_symlink() or target.resolve() != child.resolve():
                raise RuntimeError('Existing workspace source is not a live checkout link: ' + str(target))
            links[str(target.relative_to(workspace))] = str(child)
            continue
        target.symlink_to(child, target_is_directory=child.is_dir())
        links[str(target.relative_to(workspace))] = str(child)
analysis = source / 'analysis_options.yaml'
if analysis.exists() and not (workspace / analysis.name).exists():
    (workspace / analysis.name).symlink_to(analysis)
lock = toolchain / 'setup/workspace-pubspec.lock'
shutil.copy2(lock, workspace / 'pubspec.lock')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
receipt = {
    'source_head': subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip(),
    'members': members,
    'manifests_sha256': {p: sha(source / p) for p in manifests},
    'links': links,
    'lock_source': str(lock),
    'lock_sha256': sha(lock),
    'workspace': str(workspace),
}
(toolchain / 'setup').mkdir(exist_ok=True)
(toolchain / 'setup/workspace-prepared.json').write_text(
    json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'members': len(members), 'live_links': len(links),
                  'source_head': receipt['source_head'],
                  'lock_sha256': receipt['lock_sha256']}, indent=2))
