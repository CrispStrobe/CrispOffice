#!/usr/bin/env python3
"""Bind the complete final incoming qualification window to immutable inputs."""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REPO = ROOT / 'quds_office_suite'
RUNTIME = ROOT / 'runtime'
SDK = RUNTIME / 'flutter'
HELPER = REPO / 'docs/validation/mail-archive-portability-20261119/run-local-validation.py'
spec = importlib.util.spec_from_file_location('incoming_full_inputs', HELPER)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
parser = argparse.ArgumentParser()
parser.add_argument('phase', choices=['before', 'after'])
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
if args.phase == 'before':
    output.mkdir(parents=True, exist_ok=False)
else:
    if not (output / 'before.json').is_file(): raise RuntimeError('Missing initial capture')

def info(path):
    return {'bytes': path.stat().st_size, 'sha256': helper.sha(path)}

def save(name, value):
    helper.write_manifest(output / (name + '.json.gz'), value)

def read(name):
    return json.loads(gzip.decompress((output / (name + '.json.gz')).read_bytes()))

def changed(before, after):
    return sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))

sources = helper.source_manifest(REPO)
config = REPO / '.dart_tool/package_config.json'
dependencies = helper.dependency_manifest(config, RUNTIME / 'pub-cache', SDK, REPO)
paths = {
    config, REPO / '.dart_tool/package_graph.json', REPO / '.dart_tool/native_assets.yaml',
    REPO / '.dart_tool/lib/libsqlite3.so', SDK / 'bin/cache/flutter_tools.snapshot',
    SDK / 'bin/cache/flutter.version.json', SDK / 'packages/flutter_tools/pubspec.yaml',
    SDK / 'packages/flutter_tools/pubspec.lock',
    SDK / 'packages/flutter_tools/.dart_tool/package_config.json',
    SDK / 'packages/flutter_tools/.dart_tool/package_graph.json',
    RUNTIME / 'bin/flutter', RUNTIME / 'bin/dart', RUNTIME / 'env.sh',
    Path(sys.executable).resolve(), Path(shutil.which('node')).resolve(),
    Path(shutil.which('bash')).resolve(), Path(shutil.which('git')).resolve(),
    Path('/opt/codex/runtimes/codex-primary-runtime/dependencies/node/bin/node').resolve(),
}
for folder in [
    'bin/cache/dart-sdk/bin', 'bin/cache/dart-sdk/lib',
    'bin/cache/artifacts/engine/linux-x64',
    'bin/cache/artifacts/engine/common/flutter_patched_sdk',
    'bin/cache/artifacts/engine/common/flutter_patched_sdk_product',
]:
    paths.update(p for p in (SDK / folder).rglob('*') if p.is_file())
runtime = {str(path): info(path) for path in sorted(paths)}
harnesses = {str(p.relative_to(ROOT)): info(p) for p in sorted(HERE.glob('*.py'))}
harnesses[str(HELPER.relative_to(ROOT))] = info(HELPER)
harnesses[str((RUNTIME / 'incoming-test-plan.json').relative_to(ROOT))] = info(RUNTIME / 'incoming-test-plan.json')
harnesses[str((HERE / 'incoming-ui-analysis-selection.json').relative_to(ROOT))] = info(HERE / 'incoming-ui-analysis-selection.json')
values = {'source': sources, 'dependencies': dependencies, 'runtime': runtime, 'harnesses': harnesses}
for name, value in values.items(): save(name + '-' + args.phase, value)
receipt = {
    'phase': args.phase,
    'captured_at_utc': datetime.now(timezone.utc).isoformat(),
    'head': helper.capture(['git', 'rev-parse', 'HEAD'], REPO),
    'tree': helper.capture(['git', 'rev-parse', 'HEAD^{tree}'], REPO),
    'counts': {name: len(value) for name, value in values.items()},
    'environment': {key: os.environ.get(key) for key in [
        'PUB_CACHE','FLUTTER_ROOT','CI','DART_SUPPRESS_ANALYTICS','FLUTTER_SUPPRESS_ANALYTICS',
        'DASH__SUPPRESS_ANALYTICS','TMPDIR','XDG_CONFIG_HOME','XDG_CACHE_HOME','XDG_DATA_HOME',
    ]},
    'sqlite': helper.sqlite_probe(REPO / '.dart_tool/lib/libsqlite3.so'),
    'executed_capture_sha256': helper.sha(Path(__file__)),
}
if args.phase == 'before':
    shutil.copyfile(Path(__file__), output / 'executed-capture.py')
else:
    receipt['changed_inputs'] = {name: changed(read(name + '-before'), value) for name,value in values.items()}
    initial = json.loads((output / 'before.json').read_text())
    receipt['environment_unchanged'] = initial['environment'] == receipt['environment']
    receipt['sqlite_unchanged'] = initial['sqlite'] == receipt['sqlite']
    receipt['success'] = (not any(receipt['changed_inputs'].values())
                          and receipt['environment_unchanged'] and receipt['sqlite_unchanged'])
helper.write_json(output / (args.phase + '.json'), receipt)
print(json.dumps(receipt, indent=2), flush=True)
if args.phase == 'after' and not receipt['success']: raise SystemExit(1)
