#!/usr/bin/env python3
"""Run the resumed editor gate and retain its exact observed inputs/output."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

WORK = Path(__file__).resolve().parents[1]
ROOT = WORK / 'quds_office_suite'
OUT = Path(__file__).resolve().parent
FLUTTER = WORK / 'toolchain/flutter/bin/flutter'
DART = WORK / 'toolchain/flutter/bin/cache/dart-sdk/bin/dart'
EDITOR = ROOT / 'packages/quds_office_editor'
TESTS = [
    'test/sheet_fill_intent_history_test.dart',
    'test/sheet_font_color_intent_test.dart',
    'test/sheet_explicit_style_history_test.dart',
]
ANALYZE = [
    'packages/quds_office_engine/lib/src/sheet/model/sml_workbook.dart',
    'packages/quds_office_engine/lib/src/sheet/model/sml_analysis.dart',
    'packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart',
    'packages/quds_office_engine/lib/src/sheet/styles/sml_styles.dart',
    'packages/quds_office_engine/test/sheet_fill_fidelity_test.dart',
    'packages/quds_office_editor/lib/src/embed/office_controller.dart',
    *['packages/quds_office_editor/' + path for path in TESTS],
]
ENV = dict(os.environ, CI='true', BOT='true',
           FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true',
           TMPDIR=str(WORK / 'toolchain/tmp'), PUB_CACHE=str(WORK / 'toolchain/pub-cache'))

def digest(data):
    return hashlib.sha256(data).hexdigest()

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()

def now():
    return datetime.now(timezone.utc).isoformat()

inputs = set()
for package_root in sorted((ROOT / 'packages').iterdir()):
    if not (package_root / 'lib').is_dir():
        continue
    inputs.update((package_root / 'lib').rglob('*.dart'))
    for name in ['pubspec.yaml', 'analysis_options.yaml']:
        path = package_root / name
        if path.is_file():
            inputs.add(path)
inputs.update(ROOT / name for name in ANALYZE)
for name in [
    'pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml',
    '.dart_tool/package_config.json', '.dart_tool/package_graph.json',
    'packages/quds_office_engine/test/fixtures/fidelity/sheet-fill-native.xml',
    'packages/quds_office_engine/test/fixtures/fidelity/sheet-normal-font-native.xlsx',
]:
    path = ROOT / name
    if path.is_file():
        inputs.add(path)
input_hashes = {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in sorted(inputs)}
manifest = json.dumps(input_hashes, sort_keys=True, indent=2).encode() + b'\n'
(OUT / 'inputs.json.gz').write_bytes(gzip.compress(manifest, mtime=0))
for name in ['pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
    source = ROOT / name
    if source.is_file():
        (OUT / (source.name + '.gz')).write_bytes(gzip.compress(source.read_bytes(), mtime=0))

receipt = {
    'version': 1,
    'started_at': now(),
    'source_commit': git('rev-parse', 'HEAD'),
    'source_tree': git('rev-parse', 'HEAD^{tree}'),
    'worktree_status_at_start': git('status', '--porcelain'),
    'flutter_revision': subprocess.check_output(
        ['git', '-C', str(WORK / 'toolchain/flutter'), 'rev-parse', 'HEAD'], text=True).strip(),
    'dart_version': subprocess.check_output([str(DART), '--version'], env=ENV, text=True).strip(),
    'inputs': {'files': len(input_hashes), 'manifest': 'inputs.json.gz',
               'uncompressed_sha256': digest(manifest),
               'archive_sha256': digest((OUT / 'inputs.json.gz').read_bytes())},
    'steps': [],
}

def save():
    (OUT / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')

save()
print(json.dumps({'checkpoint': 'inputs_recorded', 'source': receipt['source_commit'],
                  'files': len(input_hashes)}), flush=True)
commands = [
    ('editor-tests', EDITOR,
     [str(FLUTTER), 'test', '--no-pub', '--concurrency=1', '--reporter=expanded', *TESTS]),
    ('focused-analysis', ROOT, [str(FLUTTER), 'analyze', '--no-pub', *ANALYZE]),
]
for name, cwd, command in commands:
    start = now()
    log = OUT / (name + '.log')
    with log.open('wb') as output:
        completed = subprocess.run(command, cwd=cwd, env=ENV, stdin=subprocess.DEVNULL,
                                   stdout=output, stderr=subprocess.STDOUT)
    receipt['steps'].append({'name': name, 'command': command,
                              'working_directory': str(cwd.relative_to(ROOT)) or '.',
                              'started_at': start, 'completed_at': now(),
                              'exit_code': completed.returncode,
                              'log': log.name, 'log_sha256': digest(log.read_bytes())})
    save()
    print(json.dumps({'step': name, 'exit_code': completed.returncode, 'log': log.name}), flush=True)
    if completed.returncode:
        break
changed = [name for name, sha in input_hashes.items()
           if not (ROOT / name).is_file() or digest((ROOT / name).read_bytes()) != sha]
receipt['completed_at'] = now()
receipt['source_commit_at_end'] = git('rev-parse', 'HEAD')
receipt['changed_inputs_during_run'] = changed
receipt['passed'] = len(receipt['steps']) == 2 and all(
    step['exit_code'] == 0 for step in receipt['steps']) and not changed
save()
print(json.dumps({'passed': receipt['passed'], 'changed_inputs': changed}), flush=True)
sys.exit(0 if receipt['passed'] else 1)
