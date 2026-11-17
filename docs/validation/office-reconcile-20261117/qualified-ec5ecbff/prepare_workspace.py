#!/usr/bin/env python3
"""Create a source-frozen, locked validation worktree without source edits."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
EXPECTED_LOCK = '344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def environment():
    env = dict(os.environ)
    env.update(FLUTTER_ROOT=str(HERE / 'flutter-sdk'),
               PUB_CACHE=str(HERE / 'pub-cache'),
               TMPDIR=str(HERE / 'tmp'),
               XDG_CONFIG_HOME=str(HERE / 'config'),
               CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true',
               PYTHONDONTWRITEBYTECODE='1')
    env['PATH'] = str(HERE / 'flutter-sdk/bin/cache/dart-sdk/bin') + os.pathsep + env.get('PATH', '')
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=HERE.parent / 'quds_office_suite')
    parser.add_argument('--source-commit', required=True)
    args = parser.parse_args()
    repository = args.repository.resolve()
    commit = args.source_commit
    assert re.fullmatch('[a-f0-9]{40}', commit), 'Use the exact frozen commit SHA.'
    source = HERE / 'frozen' / commit
    workspace = HERE / 'workspace' / commit
    receipt_path = HERE / f'workspace-{commit}.json'
    assert not receipt_path.exists(), 'Refuse to overwrite an existing setup receipt.'
    assert not source.exists() and not workspace.exists(), 'Refuse to overwrite an existing workspace.'
    source.parent.mkdir(exist_ok=True)
    workspace.mkdir(parents=True)
    subprocess.run(['git', '-C', str(repository), 'worktree', 'add', '--detach', str(source), commit], check=True)
    assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == commit
    root_manifest = (source / 'pubspec.yaml').read_text()
    block = root_manifest.split('\nworkspace:\n', 1)[1]
    packages = []
    for line in block.splitlines():
        if line and not line.startswith(' '):
            break
        match = re.fullmatch(r'  - ([^\s]+)', line)
        if match:
            packages.append(match.group(1))
    assert 'packages/quds_proofing_gector' in packages
    links, manifests = [], {}
    for name in ('pubspec.yaml', 'analysis_options.yaml'):
        shutil.copy2(source / name, workspace / name)
        manifests[name] = sha(workspace / name)
    lock = source / 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
    assert sha(lock) == EXPECTED_LOCK
    shutil.copy2(lock, workspace / 'pubspec.lock')
    for relative in packages:
        src, dst = source / relative, workspace / relative
        dst.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src / 'pubspec.yaml', dst / 'pubspec.yaml')
        manifests[relative + '/pubspec.yaml'] = sha(dst / 'pubspec.yaml')
        for child in src.iterdir():
            if child.name in {'.git', '.dart_tool', 'build', 'pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml'}:
                continue
            if str(child.relative_to(source)) in packages:
                continue
            target = dst / child.name
            target.symlink_to(child, target_is_directory=child.is_dir())
            links.append({'path': str(target), 'source': str(child)})
    for name in ('tools', 'tool', 'docs'):
        if (source / name).exists():
            (workspace / name).symlink_to(source / name, target_is_directory=True)
            links.append({'path': str(workspace / name), 'source': str(source / name)})
    dart = HERE / 'flutter-sdk/bin/cache/dart-sdk/bin/dart'
    command = [str(dart), 'pub', 'get', '--offline', '--enforce-lockfile']
    log = HERE / 'logs' / f'workspace-{commit}.log'
    started = time.monotonic()
    with log.open('xb') as stream:
        result = subprocess.run(command, cwd=workspace, env=environment(), stdout=stream,
                                stderr=subprocess.STDOUT, timeout=240)
    receipt = {'source_commit': commit, 'source_repository': str(repository), 'frozen_source': str(source),
               'workspace': str(workspace), 'command': command, 'exit_code': result.returncode,
               'duration_seconds': round(time.monotonic() - started, 3), 'log': str(log), 'log_sha256': sha(log),
               'lock_before_sha256': EXPECTED_LOCK, 'lock_after_sha256': sha(workspace / 'pubspec.lock'),
               'manifest_hashes': manifests, 'links': links,
               'production_source_modified': False, 'shared_runtime_modified': False,
               'source_status_after': subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True)}
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    assert result.returncode == 0, log.read_text()
    assert receipt['lock_after_sha256'] == EXPECTED_LOCK
    assert not receipt['source_status_after']
    for path, digest in manifests.items():
        assert sha(workspace / path) == digest == sha(source / path)
    graph = json.loads((workspace / '.dart_tool/package_config.json').read_text())
    assert graph['flutterRoot'] == (HERE / 'flutter-sdk').as_uri()
    assert graph['flutterVersion'] == '3.47.8'
    receipt.update({'status': 'ready', 'packages': len(graph['packages']),
                    'package_config_sha256': sha(workspace / '.dart_tool/package_config.json')})
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': 'ready', 'receipt': str(receipt_path), 'source': str(source), 'workspace': str(workspace)}))


if __name__ == '__main__':
    main()
