#!/usr/bin/env python3
"""Preserve exact local validation evidence while omitting reproducible binaries."""
import argparse
import gzip
import hashlib
import json
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('destination', type=Path)
args = parser.parse_args()
source = args.source.resolve()
destination = args.destination.resolve()
receipt = json.loads((source / 'receipt.json').read_text())
if receipt['status'] not in ('passed', 'failed', 'interrupted'):
    raise SystemExit('Refusing to publish an incomplete validation run')
destination.mkdir(parents=True, exist_ok=False)
retained, omitted = [], []
for path in sorted(source.rglob('*')):
    if not path.is_file():
        continue
    relative = path.relative_to(source)
    raw = path.read_bytes()
    record = {'path': relative.as_posix(), 'bytes': len(raw),
              'sha256': hashlib.sha256(raw).hexdigest()}
    if path.suffix == '.log':
        target = destination / (str(relative) + '.gz')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(gzip.compress(raw, mtime=0))
        record['retained_as'] = target.relative_to(destination).as_posix()
        record['encoding'] = 'gzip; hashes describe decompressed original bytes'
        retained.append(record)
    elif path.suffix in ('.json', '.py', '.gz'):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        record['retained_as'] = relative.as_posix()
        record['encoding'] = 'unchanged'
        retained.append(record)
    else:
        record['reason'] = 'Generated native fixture or JavaScript build product; reproduce using retained command.json and frozen source.'
        omitted.append(record)
(destination / 'retention.json').write_text(json.dumps({
    'source_head': receipt['source_head'],
    'source_tree': receipt['source_tree'],
    'run_status': receipt['status'],
    'retained': retained, 'omitted_build_products': omitted,
}, indent=2) + '\n')
(destination / 'RETENTION.md').write_text(
    '# Evidence retention\n\n'
    'Receipts, commands, results, the executed harness, selected plan, input '
    'manifests and per-test records are retained unchanged. Raw stdout/stderr '
    'logs are stored with deterministic gzip compression; their recorded hashes '
    'apply to the decompressed bytes. `retention.json` maps every original file '
    'to its retained form and records hashes for omitted generated build products.\n\n'
    'Compiled fixture libraries and JavaScript outputs are reproducible from '
    'the frozen source and retained command arguments. They remain in the local '
    'run directory but are not duplicated in Git. No earlier or failed run '
    'contributes to a later successful test total.\n'
)
print(json.dumps({'status': receipt['status'], 'retained_files': len(retained),
                  'omitted_build_products': len(omitted),
                  'destination': str(destination)}))
