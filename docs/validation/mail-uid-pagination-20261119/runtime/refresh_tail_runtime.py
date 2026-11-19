#!/usr/bin/env python3
"""Refresh the locked workspace binding and add verified preinstalled Poppler."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def sha(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--preparation', required=True, type=Path)
    parser.add_argument('--tail-preparation', required=True, type=Path)
    args = parser.parse_args()
    repo, runtime = args.repo.resolve(), args.runtime.resolve()
    prior = runtime / 'runtime-before-tail.json'
    if sha(prior) != '0b4544ac387f3efa23abacf71f66b834fcddec7d3b02414209c57dab14299729':
        raise RuntimeError('Preserve the independently audited 162f53c0 runtime first')
    subprocess.run([sys.executable, str(Path(__file__).with_name('refresh_runtime.py')),
                    '--repo', str(repo), '--runtime', str(runtime),
                    '--preparation', str(args.preparation.resolve())], check=True)
    receipt_path = runtime / 'runtime.json'
    receipt = json.loads(receipt_path.read_text())
    poppler_path = runtime / 'build-tools/poppler-receipt.json'
    poppler = json.loads(poppler_path.read_text())
    for name, expected in poppler['bound_files'].items():
        path = Path(name)
        if not path.is_file() or path.stat().st_size != expected['bytes'] or sha(path) != expected['sha256']:
            raise RuntimeError('Prepared Poppler input changed: ' + name)
        receipt['additional_inputs'][name] = expected['sha256']
    receipt['additional_inputs'][str(poppler_path)] = sha(poppler_path)
    receipt['tail_preparation'] = {
        'previous_runtime_receipt': str(prior),
        'previous_runtime_sha256': sha(prior),
        'poppler_receipt': str(poppler_path),
        'poppler_receipt_sha256': sha(poppler_path),
        'poppler_wrapper': poppler['wrapper'],
        'poppler_bound_file_count': len(poppler['bound_files']),
        'workspace_resolution_log_sha256': sha(args.tail_preparation / 'workspace-pub-get.log'),
        'refresh_script_sha256': sha(Path(__file__)),
        'source_commit': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
    }
    temporary = receipt_path.with_suffix('.tail.tmp')
    temporary.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    temporary.replace(receipt_path)
    print(json.dumps({'status': receipt['status'], 'additional_inputs': len(receipt['additional_inputs']),
                      'runtime_sha256': sha(receipt_path)}, indent=2))


if __name__ == '__main__':
    main()
