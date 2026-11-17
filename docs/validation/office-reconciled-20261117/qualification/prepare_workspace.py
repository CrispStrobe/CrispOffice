#!/usr/bin/env python3
"""Resolve an external validation graph without modifying production manifests."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--workspace', type=Path, required=True)
parser.add_argument('--runtime', type=Path, required=True)
args = parser.parse_args()
source, workspace, runtime = [p.resolve() for p in (args.source, args.workspace, args.runtime)]
workspace.mkdir(parents=True, exist_ok=False)
manifest = (source / 'pubspec.yaml').read_text()
members = re.findall(r'^  - (\S+)\s*$', manifest.split('\nworkspace:\n', 1)[1], re.M)
assert members and not any('quds_proofing_aot' in m for m in members)
for name in ('pubspec.yaml', 'analysis_options.yaml'):
    shutil.copy2(source / name, workspace / name)
lock = source / 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
lock_hash = hashlib.sha256(lock.read_bytes()).hexdigest()
assert lock_hash == '344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'
shutil.copy2(lock, workspace / 'pubspec.lock')
links = []
for member in members:
    src, dst = source / member, workspace / member
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / 'pubspec.yaml', dst / 'pubspec.yaml')
    for child in src.iterdir():
        if child.name in {'.git', '.dart_tool', 'build', 'pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml'}:
            continue
        if child.relative_to(source).as_posix() in members:
            continue
        target = dst / child.name
        target.symlink_to(child, target_is_directory=child.is_dir())
        links.append({'path': str(target), 'source': str(child)})
for name in ('tools', 'tool', 'docs'):
    if (source / name).exists():
        (workspace / name).symlink_to(source / name, target_is_directory=True)
for name in ('tmp', 'config'):
    (workspace / name).mkdir()
env = dict(os.environ, FLUTTER_ROOT=str(runtime / 'flutter-sdk'), PUB_CACHE=str(runtime / 'pub-cache'),
           TMPDIR=str(workspace / 'tmp'), XDG_CONFIG_HOME=str(workspace / 'config'),
           CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true', PYTHONDONTWRITEBYTECODE='1')
dart = runtime / 'flutter-sdk/bin/cache/dart-sdk/bin/dart'
env['PATH'] = str(dart.parent) + os.pathsep + env.get('PATH', '')
command = [str(dart), 'pub', 'get', '--offline', '--enforce-lockfile']
with (workspace / 'setup.log').open('w') as stream:
    result = subprocess.run(command, cwd=workspace, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
receipt = {'source': str(source), 'workspace': str(workspace), 'command': command,
           'exit_code': result.returncode, 'environment': {k: env[k] for k in ('FLUTTER_ROOT', 'PUB_CACHE', 'TMPDIR', 'XDG_CONFIG_HOME')},
           'lock_before_sha256': lock_hash, 'lock_after_sha256': hashlib.sha256((workspace / 'pubspec.lock').read_bytes()).hexdigest(),
           'links': links}
(workspace / 'setup.json').write_text(json.dumps(receipt, indent=2) + '\n')
assert result.returncode == 0, (workspace / 'setup.log').read_text()
assert receipt['lock_before_sha256'] == receipt['lock_after_sha256']
print(json.dumps({'workspace': str(workspace), 'status': 'ready', 'packages': len(json.loads((workspace / '.dart_tool/package_config.json').read_text())['packages'])}))
