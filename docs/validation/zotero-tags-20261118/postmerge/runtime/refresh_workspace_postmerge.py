#!/usr/bin/env python3
"""Refresh external validation manifests after the authorized main merge."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess

root = Path('/workspace/scratch/e06533a127f6')
source = root / 'quds_office_suite'
workspace = root / 'zotero-validation'
toolchain = root / 'zotero-toolchain'
upstream = '1ffcf91a3443caf9a6e8b45a3e6cab3f041831ae'
subprocess.run(['git', 'merge-base', '--is-ancestor', upstream, 'HEAD'], cwd=source, check=True)
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
lock = workspace / 'pubspec.lock'
expected_lock = '344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'
assert sha(lock) == expected_lock
original = json.loads((toolchain / 'runtime-ready.json').read_text())
assert original['workspace_package_count'] == 109
backup = toolchain / 'workspace-before-main-1ffcf91a'
backup.mkdir(exist_ok=False)
for name in ['pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json', 'packages/quds_office_editor/example/pubspec.yaml']:
    p = workspace / name
    if p.exists():
        target = backup / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, target)
manifest = (source / 'pubspec.yaml').read_text()
members = re.findall(r'^  - (\S+)\s*$', manifest.split('\nworkspace:\n', 1)[1], re.M)
assert 'packages/quds_proofing_spacy' in members
assert len(members) == 10
manifest_paths = ['pubspec.yaml'] + [p + '/pubspec.yaml' for p in members]
source_before = {p: sha(source / p) for p in manifest_paths}
changed_manifests = []
for name in manifest_paths:
    src = source / name
    dst = workspace / name
    if not dst.exists() or dst.read_bytes() != src.read_bytes():
        changed_manifests.append(name)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
new_package = 'packages/quds_proofing_spacy'
links = {}
for child in (source / new_package).iterdir():
    if child.name in {'.git', '.dart_tool', 'build', 'pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml'}:
        continue
    target = workspace / new_package / child.name
    assert not target.exists() and not target.is_symlink()
    target.symlink_to(child, target_is_directory=child.is_dir())
    links[str(target.relative_to(workspace))] = str(child)
assert (source / '.dart_tool').resolve() == workspace / '.dart_tool'
env = dict(os.environ, FLUTTER_ROOT=str(toolchain / 'flutter-sdk'), PUB_CACHE=str(toolchain / 'pub-cache'),
           TMPDIR=str(toolchain / 'tmp'), XDG_CONFIG_HOME=str(toolchain / 'config'),
           CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true')
dart = toolchain / 'flutter-sdk/bin/cache/dart-sdk/bin/dart'
command = [str(dart), 'pub', 'get', '--offline', '--enforce-lockfile']
log = toolchain / 'logs/workspace-postmerge-pub-get.log'
with log.open('w') as stream:
    result = subprocess.run(command, cwd=workspace, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
assert result.returncode == 0, log.read_text()
assert sha(lock) == expected_lock
source_after = {p: sha(source / p) for p in manifest_paths}
assert source_before == source_after
matches = {p: sha(workspace / p) == source_after[p] for p in manifest_paths}
assert all(matches.values())
config = json.loads((workspace / '.dart_tool/package_config.json').read_text())
assert len(config['packages']) == 110
old_config = json.loads((backup / '.dart_tool/package_config.json').read_text())
old_names = {p['name'] for p in old_config['packages']}
new_names = {p['name'] for p in config['packages']}
assert new_names - old_names == {'quds_proofing_spacy'}
assert old_names - new_names == set()
prior_by_name = {p['name']: p for p in old_config['packages']}
assert all(p == prior_by_name[p['name']] for p in config['packages'] if p['name'] in prior_by_name)
receipt = {
 'status': 'ready', 'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
 'source_head': head, 'integrated_main': upstream,
 'previous_receipt': str(toolchain / 'runtime-ready.json'),
 'previous_receipt_sha256': sha(toolchain / 'runtime-ready.json'),
 'workspace': str(workspace), 'source': str(source), 'environment_script': str(toolchain / 'env.sh'),
 'runtime': original['runtime'], 'dart_sha256': sha(dart),
 'flutter_tester_sha256': sha(toolchain / 'flutter-sdk/bin/cache/artifacts/engine/linux-x64/flutter_tester'),
 'runtime_changed': False,
 'command': command, 'exit_code': result.returncode, 'log': str(log), 'log_sha256': sha(log),
 'workspace_lock_sha256_before': expected_lock, 'workspace_lock_sha256_after': sha(lock),
 'workspace_package_count_before': len(old_config['packages']), 'workspace_package_count_after': len(config['packages']),
 'added_workspace_packages': sorted(new_names - old_names), 'existing_package_entries_unchanged': True,
 'changed_manifests': changed_manifests, 'workspace_manifest_matches': matches,
 'source_manifest_hashes_before': source_before, 'source_manifest_hashes_after': source_after,
 'new_live_source_links': links, 'previous_graph_backup': str(backup),
 'new_downloads': 0, 'product_tests_run_during_refresh': 0,
 'notes': ['Same exact hosted dependency lock and genuine runtime as the109-package qualification.',
           'Only current manifests and added package links were refreshed; all Dart code and tests remain live-linked.',
           'The previous runtime receipt and prior evidence are preserved unchanged.',
           'No GitHub Actions/check/status endpoints accessed.']}
assert receipt['dart_sha256'] == original['dart_sha256']
assert receipt['flutter_tester_sha256'] == original['flutter_tester_sha256']
path = toolchain / 'runtime-ready-postmerge.json'
assert not path.exists()
path.write_text(json.dumps(receipt, indent=2)+'\n')
print(json.dumps({'status':'ready', 'receipt':str(path),'package_count':len(config['packages']),'changed_manifests':changed_manifests},indent=2))
