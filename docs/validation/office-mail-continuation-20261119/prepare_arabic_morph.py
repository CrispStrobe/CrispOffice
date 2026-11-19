#!/usr/bin/env python3
"""Build ABI 2 morphology and bind the exact catalog-pinned proofing database.

This preparation downloads immutable inputs before the offline qualification.
It preserves the original runtime receipt and keeps all generated inputs outside
the checkout. Native tests subsequently use the verified local files only.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import urllib.request


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
    args = parser.parse_args()
    repo, runtime, output = args.repo.resolve(), args.runtime.resolve(), args.output.resolve()
    for other in (repo, runtime):
        if output == other or other in output.parents or output in other.parents:
            raise RuntimeError('Keep output separate from repository and runtime')
    if output.exists() and any(output.iterdir()):
        raise RuntimeError('Choose a new empty build directory; preserve prior attempts')
    runtime_path = runtime / 'runtime.json'
    runtime_receipt = json.loads(runtime_path.read_text())
    if runtime_receipt.get('status') != 'ready' or not runtime_receipt.get('archive', {}).get('verified'):
        raise RuntimeError('Restore the verified runtime first')
    package = repo / 'packages/quds_arabic_morph'
    catalog = package / 'lib/src/morph_catalog.dart'
    text = catalog.read_text().split('const camelMorphMsaProofingBin = MorphBundleDownload(', 1)[1]
    text = text.split('const camelMorphMsaNoprob =', 1)[0]
    identity = {}
    for name in ('repository', 'revision', 'directory'):
        matches = re.findall(r'\b' + name + r":\s*'([^']+)'", text)
        if len(matches) != 1:
            raise RuntimeError('Ambiguous catalog identity: ' + name)
        identity[name] = matches[0]
    if (not re.fullmatch(r'[0-9a-f]{40}', identity['revision'])
            or identity['repository'] != 'cstr/camel-morph-msa-v1.0'
            or identity['directory'] != 'proofing-bin'):
        raise RuntimeError('Expected the immutable proofing-bin catalog entry')
    artifacts = re.findall(r"MorphArtifact\(\s*'([^']+)',\s*'([0-9a-f]{64})',\s*(\d+),?\s*\)", text)
    if len(artifacts) != 4 or {row[0] for row in artifacts} != {
            'manifest.json', 'camel_morph_msa_v1.0.proofing.cmorph', 'NOTICE', 'LICENSE'}:
        raise RuntimeError('Expected exactly the four pinned bundle artifacts')
    output.mkdir(parents=True)
    original = output / 'runtime-before-arabic-morph.json'
    original.write_bytes(runtime_path.read_bytes())
    receipt = {'started_at_utc': datetime.now(timezone.utc).isoformat(),
               'status': 'preparing', 'script_sha256': digest(Path(__file__)),
               'catalog_sha256': digest(catalog), 'bundle_identity': identity,
               'original_runtime_receipt_sha256': digest(original), 'downloads': []}
    try:
        command = [sys.executable, '-B', str(package / 'tool/build.py'),
                   '--native', '--output', str(output)]
        print('START native-build', flush=True)
        log = output / 'native-build.log'
        with log.open('wb') as stream:
            result = subprocess.run(command, cwd=repo, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=300)
        receipt['build'] = {'command': command, 'exit_code': result.returncode,
                            'log': log.name, 'log_sha256': digest(log)}
        if result.returncode:
            raise RuntimeError('Native build failed: ' + log.read_text(errors='replace')[-6000:])
        build_path = output / 'build-receipt.json'
        build = json.loads(build_path.read_text())
        native_names = [name for name in build['files'] if name.startswith('native/')]
        if len(native_names) != 1:
            raise RuntimeError('Expected exactly one native library')
        library = output / native_names[0]
        if digest(library) != build['files'][native_names[0]]:
            raise RuntimeError('Library differs from build receipt')
        bundle = output / 'bundle'
        bundle.mkdir()
        bindings = {str(path.resolve()): digest(path) for path in (library, build_path)}
        for name, expected, size_text in artifacts:
            size = int(size_text)
            url = 'https://huggingface.co/{repository}/resolve/{revision}/{directory}/'.format(**identity) + name
            print('DOWNLOAD ' + name, flush=True)
            target = bundle / name
            received = 0
            with urllib.request.urlopen(url, timeout=60) as response, target.open('wb') as stream:
                while chunk := response.read(1024 * 1024):
                    received += len(chunk)
                    if received > size:
                        raise RuntimeError('Bundle artifact exceeds its pinned size: ' + name)
                    stream.write(chunk)
            if received != size or digest(target) != expected:
                raise RuntimeError('Bundle artifact differs from its pin: ' + name)
            receipt['downloads'].append({'file': name, 'url': url, 'bytes': size,
                                          'sha256': expected, 'verified': True})
            bindings[str(target.resolve())] = expected
        receipt.update(status='ready', additional_inputs=bindings)
    except BaseException as error:
        receipt.update(status='failed', error=repr(error))
        raise
    finally:
        receipt['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        write(output / 'preparation.json', receipt)
    runtime_receipt.setdefault('additional_inputs', {}).update(bindings)
    runtime_receipt['arabic_morph_preparation'] = {
        'receipt': str(output / 'preparation.json'),
        'receipt_sha256': digest(output / 'preparation.json'),
        'original_runtime_receipt_sha256': digest(original),
        'at_utc': receipt['finished_at_utc'],
    }
    write(runtime_path, runtime_receipt)
    print(json.dumps({'status': 'ready', 'library': str(library),
                      'bundle': str(bundle)}, indent=2))


if __name__ == '__main__':
    main()
