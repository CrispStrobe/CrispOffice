#!/usr/bin/env python3
"""Build and bind the three synthetic Hunspell lifecycle fixtures for replay.

These libraries expose allocation counters and controlled native calls. They
do not contain Hunspell or a linguistic dictionary and are never product assets.
Run after the committed pinned-runtime restorer, before freezing qualification.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, runtime, output = (p.resolve() for p in
                             (args.repo, args.runtime, args.output))
    if repo == output or repo in output.parents:
        raise RuntimeError('Write fixture output outside the source checkout')
    if output.exists() and any(output.iterdir()):
        raise RuntimeError('Preserve earlier fixtures; select an empty output')
    receipt_path = runtime / 'runtime.json'
    runtime_receipt = json.loads(receipt_path.read_text())
    if runtime_receipt.get('status') != 'ready':
        raise RuntimeError('Restore and verify the runtime first')
    compiler = shutil.which('g++')
    if compiler is None:
        raise RuntimeError('A C++17 compiler is required')
    compiler = Path(compiler).resolve()
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(receipt_path, output / 'runtime-before-fixtures.json')
    specs = [
        ('QUDS_HUNSPELL_LIFECYCLE_LIBRARY',
         'test/fixtures/lifecycle_hunspell.cpp', 'lifecycle.so'),
        ('QUDS_HUNSPELL_PROVIDER_LIFECYCLE_LIBRARY',
         'test/support/hunspell_lifecycle_shim.cpp', 'provider.so'),
        ('QUDS_HUNSPELL_OWNERSHIP_LIBRARY',
         'test/support/lifecycle_library.cpp', 'ownership.so'),
    ]
    record = {
        'created_at_utc': datetime.now(timezone.utc).isoformat(),
        'scope': 'Synthetic native C ABI ownership and lifecycle controls only',
        'compiler': {'path': str(compiler), 'sha256': digest(compiler),
                     'version': subprocess.check_output(
                         [str(compiler), '--version'], text=True)},
        'implementation_sha256': digest(Path(__file__)),
        'runtime_before_sha256': digest(output / 'runtime-before-fixtures.json'),
        'builds': [], 'environment': {},
    }
    additions = {str(compiler): digest(compiler)}
    for variable, relative, filename in specs:
        source = repo / 'packages/quds_proofing_hunspell' / relative
        library = output / filename
        command = [str(compiler), '-std=c++17', '-O2', '-shared', '-fPIC',
                   '-pthread', str(source), '-o', str(library)]
        result = subprocess.run(command, capture_output=True, timeout=120)
        log = output / (filename + '.build.log')
        log.write_bytes(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError('Fixture compilation failed: ' + str(log))
        row = {
            'source': str(source.relative_to(repo)),
            'source_sha256': digest(source), 'command': command,
            'exit_code': result.returncode, 'log': log.name,
            'log_sha256': digest(log), 'library': str(library),
            'bytes': library.stat().st_size, 'sha256': digest(library),
        }
        record['builds'].append(row)
        record['environment'][variable] = str(library)
        additions[str(library)] = row['sha256']
    env_path = output / 'env.sh'
    env_path.write_text(''.join('export ' + key + '=' + shlex.quote(value) + '\n'
                               for key, value in record['environment'].items()))
    record['environment_script_sha256'] = digest(env_path)
    evidence = output / 'fixture-build.json'
    evidence.write_text(json.dumps(record, indent=2) + '\n')
    additions[str(env_path)] = digest(env_path)
    additions[str(evidence)] = digest(evidence)
    runtime_receipt.setdefault('additional_inputs', {}).update(additions)
    runtime_receipt['synthetic_hunspell_fixtures'] = {
        'receipt': str(evidence), 'sha256': digest(evidence),
        'environment': record['environment'],
    }
    receipt_path.write_text(json.dumps(runtime_receipt, indent=2) + '\n')
    print(json.dumps({'built': len(specs), 'receipt': str(evidence),
                      'bound_runtime_inputs': len(additions)}))


if __name__ == '__main__':
    main()
