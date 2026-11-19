#!/usr/bin/env python3
"""Bind the rebuilt and host-installed Hunspell artifact without losing prior inputs."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess


def sha(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--preparation', required=True, type=Path)
    args = parser.parse_args()
    repo, runtime, preparation = (p.resolve() for p in (args.repo, args.runtime, args.preparation))
    preserved = runtime / 'runtime-before-final-build.json'
    receipt_path = runtime / 'runtime.json'
    if not preserved.exists():
        preserved.write_bytes(receipt_path.read_bytes())
    if sha(preserved) != '2d652bd61d2872999131418f845692386d1bf4ba2d037bceb72df10c586ab9a4':
        raise RuntimeError('Preserve the published pre-installer tail runtime before rebinding')
    receipt = json.loads(preserved.read_text())
    if sha(repo / 'pubspec.lock') != receipt['workspace_lock_sha256']:
        raise RuntimeError('Incoming workspace changed the pinned dependency lock')
    old_inputs = dict(receipt['additional_inputs'])
    for name, identity in old_inputs.items():
        if sha(Path(name)) != identity:
            raise RuntimeError('Previously bound runtime input changed: ' + name)
    restorer_path = repo / 'docs/validation/document-review-notes-20261118/runtime/restore_runtime.py'
    spec = importlib.util.spec_from_file_location('restored_runtime', restorer_path)
    restorer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(restorer)
    receipt['workspace_packages'] = restorer.verified_workspace_packages(repo)
    receipt['workspace_package_count'] = len(receipt['workspace_packages']['resolved'])
    restorer.bind_test_inputs(repo, runtime, receipt, node_tests=True)
    for name, identity in receipt['additional_inputs'].items():
        if name in old_inputs and old_inputs[name] != identity:
            raise RuntimeError('Previously qualified launcher input changed: ' + name)
    receipt['additional_inputs'] = {**old_inputs, **receipt['additional_inputs']}
    verification_path = preparation / 'build-verification.json'
    verification = json.loads(verification_path.read_text())
    for name, expected in verification['compiled_inputs'].items():
        if sha(repo / name) != expected:
            raise RuntimeError('Built/installed source input changed: ' + name)
    build_path = Path(verification['build_receipt'])
    if sha(build_path) != verification['build_receipt_sha256']:
        raise RuntimeError('Native build receipt changed')
    build = json.loads(build_path.read_text())
    package = repo / 'packages/quds_proofing_hunspell'
    if (sha(package / 'native/src/quds_hunspell.cpp') != build['adapter_sha256']
            or sha(package / 'licenses/manifest.json') != build['license_manifest_sha256']):
        raise RuntimeError('Current adapter/manifest differs from the verified build receipt')
    upstream = Path(verification['source_archive']['path'])
    if sha(upstream) != build['hunspell']['sha256'] or upstream.stat().st_size != build['hunspell']['bytes']:
        raise RuntimeError('Reused Hunspell source archive differs from its immutable pin')
    if sha(preparation / 'build-install.log') != verification['build_log_sha256']:
        raise RuntimeError('Captured native build/install log changed')
    built = Path(verification['native_library']['path'])
    installed = Path(verification['installed_library']['path'])
    if not (sha(built) == sha(installed) == build['files']['native/' + built.name]
            == verification['native_library']['sha256'] == verification['installed_library']['sha256']):
        raise RuntimeError('The host-installed library differs from its verified build')
    inputs = [build_path, built, verification_path, Path(verification['source_archive']['path']),
              preparation / 'source-before.json', preparation / 'source-after.json', preparation / 'build-install.log']
    for name, expected in verification['installed_files'].items():
        path = Path(name)
        if path.stat().st_size != expected['bytes'] or sha(path) != expected['sha256']:
            raise RuntimeError('Host installation changed: ' + name)
        inputs.append(path)
    for path in inputs:
        receipt['additional_inputs'][str(path)] = sha(path)
    receipt['qualification_environment']['QUDS_HUNSPELL_TEST_LIBRARY'] = str(installed)
    fixtures_path = runtime / 'hunspell/lifecycle-final/fixtures.json'
    fixtures = json.loads(fixtures_path.read_text())
    expected_fixtures = {'QUDS_HUNSPELL_LIFECYCLE_LIBRARY', 'QUDS_HUNSPELL_OWNERSHIP_LIBRARY',
                         'QUDS_HUNSPELL_PROVIDER_LIFECYCLE_LIBRARY'}
    if set(fixtures) != expected_fixtures:
        raise RuntimeError('Bind the three distinct compiled lifecycle fixtures')
    for environment, fixture in fixtures.items():
        if sha(repo / fixture['source']) != fixture['source_sha256']:
            raise RuntimeError('Lifecycle fixture source changed: ' + fixture['source'])
        library = Path(fixture['library'])
        fixture_receipt = Path(fixture['receipt'])
        log = fixture_receipt.with_name(fixture_receipt.name.replace('-receipt.json', '-build.log'))
        if (sha(library) != fixture['library_sha256'] or sha(fixture_receipt) != fixture['receipt_sha256']
                or sha(log) != fixture['log_sha256'] or sha(Path(fixture['compiler'])) != fixture['compiler_sha256']):
            raise RuntimeError('Compiled lifecycle fixture/provenance changed: ' + environment)
        for path in (library, fixture_receipt, log):
            receipt['additional_inputs'][str(path)] = sha(path)
        receipt['qualification_environment'][environment] = str(library)
    receipt['additional_inputs'][str(fixtures_path)] = sha(fixtures_path)
    receipt['lifecycle_fixtures'] = fixtures
    primary_fixture = fixtures['QUDS_HUNSPELL_LIFECYCLE_LIBRARY']
    receipt['hunspell_preparation'].update(
        build_receipt=str(build_path), build_receipt_sha256=sha(build_path),
        build_verification=str(verification_path), build_verification_sha256=sha(verification_path),
        lifecycle_receipt=primary_fixture['receipt'], lifecycle_receipt_sha256=primary_fixture['receipt_sha256'],
    )
    receipt['final_native_installation'] = {
        'prior_runtime_receipt': str(preserved), 'prior_runtime_sha256': sha(preserved),
        'build_verification': str(verification_path), 'build_verification_sha256': sha(verification_path),
        'installed_library': str(installed), 'installed_library_sha256': sha(installed),
        'installed_file_count': len(verification['installed_files']),
        'refresh_script_sha256': sha(Path(__file__)),
    }
    receipt['workspace_refresh'] = {
        'at_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
        'pubspec_sha256': sha(repo / 'pubspec.yaml'),
        'package_config_sha256': sha(repo / '.dart_tool/package_config.json'),
        'offline_resolution_log': str(preparation / 'workspace-pub-get.log'),
        'offline_resolution_log_sha256': sha(preparation / 'workspace-pub-get.log'),
    }
    receipt['additional_inputs'][str(preparation / 'workspace-pub-get.log')] = sha(
        preparation / 'workspace-pub-get.log')
    temporary = receipt_path.with_suffix('.final.tmp')
    temporary.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    temporary.replace(receipt_path)
    print(json.dumps({'status': receipt['status'], 'workspace_package_count': receipt['workspace_package_count'],
                      'additional_inputs': len(receipt['additional_inputs']), 'runtime_sha256': sha(receipt_path)}, indent=2))


if __name__ == '__main__':
    main()
