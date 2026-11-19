#!/usr/bin/env python3
"""Build and bind the pinned CLD3 backend and allocation-counting test fixture.

Run before freezing a qualification source. The original SDK restoration
receipt is preserved; only explicit additional test input bindings are added.
All build outputs stay outside the tracked checkout and verified SDK files.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cxx', default='c++')
    args = parser.parse_args()
    repo, runtime, output = args.repo.resolve(), args.runtime.resolve(), args.output.resolve()
    for other in (repo, runtime):
        if output == other or other in output.parents or output in other.parents:
            raise RuntimeError('Keep build output separate from repository and runtime')
    if output.exists() and any(output.iterdir()):
        raise RuntimeError('Choose a new empty build directory; preserve previous attempts')
    identity_path = runtime / 'runtime.json'
    identity = json.loads(identity_path.read_text())
    if identity.get('status') != 'ready' or not identity.get('archive', {}).get('verified'):
        raise RuntimeError('A verified restored runtime is required')
    compiler_path = shutil.which(args.cxx)
    if compiler_path is None:
        raise RuntimeError('A C++ compiler is required')
    compiler = Path(compiler_path).resolve(strict=True)
    output.mkdir(parents=True)
    original = output / 'runtime-before-language-id.json'
    original.write_bytes(identity_path.read_bytes())
    receipt = {'started_at_utc': datetime.now(timezone.utc).isoformat(),
               'status': 'preparing', 'commands': [], 'repo': str(repo),
               'original_runtime_receipt_sha256': digest(original),
               'script_sha256': digest(Path(__file__))}

    def run(name: str, command: list[str]) -> None:
        print('START ' + name, flush=True)
        log = output / (name + '.log')
        with log.open('wb') as stream:
            result = subprocess.run(command, cwd=repo, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=300)
        receipt['commands'].append({'name': name, 'command': command,
                                    'exit_code': result.returncode,
                                    'log': log.name, 'log_sha256': digest(log)})
        if result.returncode:
            raise RuntimeError(name + ': ' + log.read_text(errors='replace')[-6000:])

    try:
        run('native-build', [sys.executable, '-B',
                            str(repo / 'packages/quds_language_id/tool/build.py'),
                            '--native', '--output', str(output)])
        build_receipt = output / 'build-receipt.json'
        built = json.loads(build_receipt.read_text())
        native_names = [name for name in built['files'] if name.startswith('native/')]
        if len(native_names) != 1:
            raise RuntimeError('Expected exactly one freshly built native library')
        library = output / native_names[0]
        if digest(library) != built['files'][native_names[0]]:
            raise RuntimeError('Native library differs from its build receipt')

        # The fixture observes actual native allocations across Dart isolates.
        # It is not a replacement for the separately executed real-model suite.
        source_relative = 'packages/quds_language_id/test/fixtures/native_transport_fixture.cpp'
        source = repo / source_relative
        fixture = output / 'native/libquds_language_id_fixture.so'
        command = [str(compiler), '-std=c++17', '-O2', '-shared', '-fPIC',
                   '-pthread', str(source), '-o', str(fixture)]
        run('fixture-build', command)
        fixture_receipt = fixture.with_suffix('.receipt.json')
        write(fixture_receipt, {
            'library': fixture.name, 'library_sha256': digest(fixture),
            'source': source_relative, 'source_sha256': digest(source),
            'compiler': str(compiler), 'compiler_sha256': digest(compiler),
            'compiler_version': subprocess.check_output([str(compiler), '--version'], text=True),
            'command': command,
        })
        bindings = {str(path.resolve()): digest(path)
                    for path in (library, build_receipt, fixture, fixture_receipt)}
        receipt.update(status='ready', additional_inputs=bindings)
    except BaseException as error:
        receipt.update(status='failed', error=repr(error))
        raise
    finally:
        receipt['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        write(output / 'preparation.json', receipt)
    identity.setdefault('additional_inputs', {}).update(bindings)
    identity['language_id_preparation'] = {
        'receipt': str(output / 'preparation.json'),
        'receipt_sha256': digest(output / 'preparation.json'),
        'original_runtime_receipt_sha256': digest(original),
        'at_utc': receipt['finished_at_utc'],
    }
    write(identity_path, identity)
    print(json.dumps({'status': 'ready', 'library': str(library),
                      'fixture_library': str(fixture)}, indent=2))


if __name__ == '__main__':
    main()
