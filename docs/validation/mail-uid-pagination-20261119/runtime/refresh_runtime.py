#!/usr/bin/env python3
"""Bind an existing verified SDK to the combined Mail/Hunspell qualification.

This does not download or install software. Run the checked-in Hunspell builder,
prepare the eight catalog-pinned dictionary files and compile the lifecycle test
fixture first. The original runtime receipt is retained before replacement.
"""
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


def read(path: Path):
    return json.loads(path.read_text())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--preparation', required=True, type=Path)
    args = parser.parse_args()
    repo, runtime, preparation = (p.resolve() for p in (args.repo, args.runtime, args.preparation))
    receipt_path = runtime / 'runtime.json'
    preserved_path = runtime / 'runtime-before-combined.json'
    if not preserved_path.exists():
        preserved_path.write_bytes(receipt_path.read_bytes())
    receipt = read(preserved_path)
    if receipt.get('status') != 'ready' or not receipt.get('archive', {}).get('verified'):
        raise RuntimeError('A previously verified runtime is required')
    if sha(repo / 'pubspec.lock') != receipt['workspace_lock_sha256']:
        raise RuntimeError('Combined workspace changed the pinned dependency lock')
    restorer_path = repo / 'docs/validation/document-review-notes-20261118/runtime/restore_runtime.py'
    spec = importlib.util.spec_from_file_location('restored_runtime', restorer_path)
    restorer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(restorer)
    receipt['workspace_packages'] = restorer.verified_workspace_packages(repo)
    receipt['workspace_package_count'] = len(receipt['workspace_packages']['resolved'])
    restorer.bind_test_inputs(repo, runtime, receipt, node_tests=True)

    build_root = runtime / 'hunspell/build'
    build_path = build_root / 'build-receipt.json'
    build = read(build_path)
    library = build_root / 'native/libquds_proofing_hunspell.so'
    if sha(library) != build['files']['native/libquds_proofing_hunspell.so']:
        raise RuntimeError('Hunspell native library changed after the source-bound build')
    package = repo / 'packages/quds_proofing_hunspell'
    if sha(package / 'native/src/quds_hunspell.cpp') != build['adapter_sha256']:
        raise RuntimeError('Current adapter differs from the compiled adapter')
    if sha(package / 'licenses/manifest.json') != build['license_manifest_sha256']:
        raise RuntimeError('Current Hunspell manifest differs from the build')
    build_verification = read(preparation / 'build-verification.json')
    for name, expected in build_verification['compiled_inputs'].items():
        if sha(repo / name) != expected:
            raise RuntimeError('Compiled source/build input changed: ' + name)
    upstream = build_root / 'source/hunspell-1.7.2.tar.gz'
    if sha(upstream) != build['hunspell']['sha256'] or upstream.stat().st_size != build['hunspell']['bytes']:
        raise RuntimeError('Upstream Hunspell archive differs from its pin')

    dictionary_receipt_path = runtime / 'hunspell/dictionary-receipt.json'
    dictionary_receipt = read(dictionary_receipt_path)
    if sha(package / 'lib/src/hunspell_catalog.dart') != dictionary_receipt['catalog_sha256']:
        # Dart formatting may change without changing the compiled artifact pins.
        # Verify every exact file/name/length/digest against the current catalog.
        import re
        catalog = (package / 'lib/src/hunspell_catalog.dart').read_text()
        catalog_files = {
            name: (digest, int(size)) for name, digest, size in re.findall(
                r"HunspellArtifact\(\s*'([^']+)',\s*'([0-9a-f]{64})',\s*(\d+),", catalog
            )
        }
        captured = {item['file']: (item['sha256'], item['bytes']) for item in dictionary_receipt['files']}
        if catalog_files != captured or dictionary_receipt['revision'] not in catalog:
            raise RuntimeError('Current dictionary catalog differs from the verified inputs')
    dictionary = Path(dictionary_receipt['directory'])
    if len(list(dictionary.iterdir())) != 8 or len(dictionary_receipt['files']) != 8:
        raise RuntimeError('Exactly eight catalog-pinned dictionary files are required')
    inputs = [library, upstream, build_path, dictionary_receipt_path, preparation / 'build-verification.json']
    for item in dictionary_receipt['files']:
        path = Path(item['path'])
        if path.parent != dictionary or path.stat().st_size != item['bytes'] or sha(path) != item['sha256']:
            raise RuntimeError('Dictionary file differs from its pinned catalog: ' + item['file'])
        inputs.append(path)

    cmake_root = runtime / 'build-tools/cmake-3.31.10'
    cmake_receipt_path = cmake_root / 'receipt.json'
    cmake = read(cmake_receipt_path)
    compiler = Path(cmake['compiler']['path'])
    if sha(compiler) != cmake['compiler']['sha256'] or sha(Path(cmake['executable'])) != cmake['executable_sha256']:
        raise RuntimeError('Native compiler or CMake executable changed')
    if sha(Path(cmake['wheel']['file'])) != cmake['wheel']['sha256']:
        raise RuntimeError('Pinned CMake wheel changed')
    if sha(cmake_root / 'pypi-release.json') != cmake['metadata_sha256']:
        raise RuntimeError('Official CMake metadata record changed')
    inputs.extend([compiler, Path(cmake['executable']), Path(cmake['wheel']['file']),
                   cmake_receipt_path, cmake_root / 'pypi-release.json'])

    lifecycle_path = runtime / 'hunspell/lifecycle/build-receipt.json'
    lifecycle = read(lifecycle_path)
    fixture = repo / lifecycle['source']
    lifecycle_library = Path(lifecycle['library'])
    if sha(fixture) != lifecycle['source_sha256'] or sha(lifecycle_library) != lifecycle['library_sha256']:
        raise RuntimeError('Native lifecycle fixture source/output changed')
    if lifecycle['compiler_sha256'] != sha(compiler):
        raise RuntimeError('Lifecycle fixture used a different compiler')
    inputs.extend([lifecycle_path, lifecycle_library])
    for path in inputs:
        receipt['additional_inputs'][str(path)] = sha(path)
    receipt['qualification_environment'] = {
        'QUDS_HUNSPELL_TEST_LIBRARY': str(library),
        'QUDS_HUNSPELL_TEST_DICTIONARY': str(dictionary),
        'QUDS_HUNSPELL_LIFECYCLE_LIBRARY': str(lifecycle_library),
        'QUDS_HUNSPELL_LIVE_DOWNLOAD': '1',
    }
    receipt['prior_runtime_receipt'] = {'path': str(preserved_path), 'sha256': sha(preserved_path)}
    receipt['workspace_refresh'] = {
        'at_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
        'pubspec_sha256': sha(repo / 'pubspec.yaml'),
        'package_config_sha256': sha(repo / '.dart_tool/package_config.json'),
        'offline_resolution_log': str(preparation / 'workspace-pub-get.log'),
        'offline_resolution_log_sha256': sha(preparation / 'workspace-pub-get.log'),
        'refresh_script_sha256': sha(Path(__file__)),
    }
    receipt['hunspell_preparation'] = {
        'build_receipt': str(build_path), 'build_receipt_sha256': sha(build_path),
        'build_verification': str(preparation / 'build-verification.json'),
        'build_verification_sha256': sha(preparation / 'build-verification.json'),
        'dictionary_receipt': str(dictionary_receipt_path), 'dictionary_receipt_sha256': sha(dictionary_receipt_path),
        'cmake_receipt': str(cmake_receipt_path), 'cmake_receipt_sha256': sha(cmake_receipt_path),
        'lifecycle_receipt': str(lifecycle_path), 'lifecycle_receipt_sha256': sha(lifecycle_path),
    }
    temporary = runtime / 'runtime-combined.tmp.json'
    temporary.write_text(json.dumps(receipt, indent=2) + '\n')
    temporary.replace(receipt_path)
    print(json.dumps({'status': receipt['status'], 'workspace_package_count': receipt['workspace_package_count'],
                      'additional_inputs': len(receipt['additional_inputs']), 'runtime_sha256': sha(receipt_path)}, indent=2))


if __name__ == '__main__':
    main()
