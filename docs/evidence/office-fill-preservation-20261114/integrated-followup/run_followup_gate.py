#!/usr/bin/env python3
"""Capture and validate the cell-state and speaker-note follow-up changes."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

WORK = Path(__file__).resolve().parents[1]
ROOT = WORK / 'quds_office_suite'
OUT = Path(__file__).resolve().parent
SDK = WORK / 'toolchain/flutter'
FLUTTER = SDK / 'bin/flutter'
DART = SDK / 'bin/cache/dart-sdk/bin/dart'
SOURCE = 'c37789b596a6f6516d9e2cee78ce57ab33872b07'
ENGINE_TESTS = [
    'test/sheet_cell_state_preservation_test.dart',
    'test/sheet_fill_fidelity_test.dart',
]
EDITOR_TESTS = [
    'test/sheet_cell_state_history_test.dart',
    'test/slide_notes_history_test.dart',
    'test/pending_edit_save_test.dart',
    'test/sheet_fill_intent_history_test.dart',
    'test/sheet_font_color_intent_test.dart',
    'test/sheet_explicit_style_history_test.dart',
]
ANALYZE = [
    'packages/quds_office_engine/lib/src/sheet/model/sml_analysis.dart',
    'packages/quds_office_editor/lib/src/embed/office_controller.dart',
    *['packages/quds_office_engine/' + name for name in ENGINE_TESTS],
    *['packages/quds_office_editor/' + name for name in EDITOR_TESTS],
]
ENV_OVERRIDES = {
    'CI': 'true', 'BOT': 'true',
    'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'DART_SUPPRESS_ANALYTICS': 'true',
    'TMPDIR': str(WORK / 'toolchain/tmp'),
    'PUB_CACHE': str(WORK / 'toolchain/pub-cache'),
}
ENV = dict(os.environ, **ENV_OVERRIDES)
COMMANDS = [
    ('engine-tests', ROOT / 'packages/quds_office_engine',
     [str(DART), 'test', '--concurrency=1', '--reporter=expanded', *ENGINE_TESTS]),
    ('editor-tests', ROOT / 'packages/quds_office_editor',
     [str(FLUTTER), 'test', '--no-pub', '--concurrency=1', '--reporter=expanded', *EDITOR_TESTS]),
    ('focused-analysis', ROOT, [str(FLUTTER), 'analyze', '--no-pub', *ANALYZE]),
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def now():
    return datetime.now(timezone.utc).isoformat()


def save(receipt):
    temporary = OUT / 'validation.json.tmp'
    temporary.write_text(json.dumps(receipt, indent=2) + '\n')
    temporary.replace(OUT / 'validation.json')


def changed_inputs(hashes):
    return [name for name, sha in hashes.items()
            if not (ROOT / name).is_file() or digest((ROOT / name).read_bytes()) != sha]


def capture():
    if (OUT / 'validation.json').exists():
        raise RuntimeError('Existing validation receipt must not be overwritten')
    if git('rev-parse', 'HEAD') != SOURCE:
        raise RuntimeError('Expected the reviewed source commit before capture')
    inputs = set()
    for package in sorted((ROOT / 'packages').iterdir()):
        if not (package / 'lib').is_dir():
            continue
        inputs.update((package / 'lib').rglob('*.dart'))
        for name in ['pubspec.yaml', 'analysis_options.yaml']:
            if (package / name).is_file():
                inputs.add(package / name)
    inputs.update(ROOT / name for name in ANALYZE)
    for name in [
        'pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml',
        '.dart_tool/package_config.json', '.dart_tool/package_graph.json',
        'packages/quds_office_engine/test/fixtures/fidelity/sheet-fill-native.xml',
        'packages/quds_office_engine/test/fixtures/fidelity/sheet-normal-font-native.xlsx',
    ]:
        if (ROOT / name).is_file():
            inputs.add(ROOT / name)
    hashes = {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in sorted(inputs)}
    manifest = json.dumps(hashes, sort_keys=True, indent=2).encode() + b'\n'
    (OUT / 'inputs.json.gz').write_bytes(gzip.compress(manifest, mtime=0))
    for name in ['pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
        source = ROOT / name
        if source.is_file():
            (OUT / (source.name + '.gz')).write_bytes(gzip.compress(source.read_bytes(), mtime=0))
    runtime = {
        'version': 1,
        'flutter_revision': subprocess.check_output(
            ['git', '-C', str(SDK), 'rev-parse', 'HEAD'], text=True).strip(),
        'dart_version': subprocess.check_output([str(DART), '--version'], env=ENV, text=True).strip(),
        'files_sha256': {name: digest((SDK / name).read_bytes()) for name in [
            'bin/cache/dart-sdk/bin/dart', 'bin/cache/flutter_tools.snapshot',
            'bin/cache/artifacts/engine/linux-x64/flutter_tester',
            'bin/internal/engine.version', 'bin/cache/engine.stamp',
        ]},
        'environment': ENV_OVERRIDES,
    }
    (OUT / 'runtime.json').write_text(json.dumps(runtime, indent=2) + '\n')
    receipt = {
        'version': 1, 'captured_at': now(), 'source_commit': SOURCE,
        'source_tree': git('rev-parse', 'HEAD^{tree}'),
        'worktree_status_at_capture': git('status', '--porcelain'),
        'reviewed_commits': [
            'f75a33e8beb53a7b116df4852bce6f975242b8b1', SOURCE,
        ],
        'inputs': {'files': len(hashes), 'manifest': 'inputs.json.gz',
                   'uncompressed_sha256': digest(manifest),
                   'archive_sha256': digest((OUT / 'inputs.json.gz').read_bytes())},
        'runtime_manifest': 'runtime.json',
        'planned_commands': [
            {'name': name, 'working_directory': str(cwd.relative_to(ROOT)) or '.', 'command': cmd}
            for name, cwd, cmd in COMMANDS
        ],
        'steps': [], 'passed': None,
    }
    save(receipt)
    print(json.dumps({'checkpoint': 'inputs_recorded', 'source': SOURCE,
                      'files': len(hashes), 'manifest_sha256': receipt['inputs']['archive_sha256']}), flush=True)


def run():
    receipt = json.loads((OUT / 'validation.json').read_text())
    hashes = json.loads(gzip.decompress((OUT / 'inputs.json.gz').read_bytes()))
    if receipt['steps']:
        raise RuntimeError('Existing execution must not be overwritten')
    changed = changed_inputs(hashes)
    if changed:
        raise RuntimeError('Source inputs changed before execution: ' + repr(changed))
    receipt['started_at'] = now()
    receipt['free_disk_bytes_before_tests'] = shutil.disk_usage(WORK).free
    save(receipt)
    for name, cwd, command in COMMANDS:
        start = now()
        log = OUT / (name + '.log')
        with log.open('xb') as output:
            completed = subprocess.run(command, cwd=cwd, env=ENV, stdin=subprocess.DEVNULL,
                                       stdout=output, stderr=subprocess.STDOUT)
        content = log.read_text(errors='replace')
        counts = re.findall(r'\+(\d+): All tests passed!', content)
        step = {
            'name': name, 'command': command,
            'working_directory': str(cwd.relative_to(ROOT)) or '.',
            'started_at': start, 'completed_at': now(), 'exit_code': completed.returncode,
            'log': log.name, 'log_sha256': digest(log.read_bytes()),
        }
        if counts:
            step['passed_tests'] = int(counts[-1])
        receipt['steps'].append(step)
        receipt['changed_inputs_after_step'] = changed_inputs(hashes)
        save(receipt)
        print(json.dumps(step), flush=True)
        if completed.returncode or receipt['changed_inputs_after_step']:
            break
    receipt['completed_at'] = now()
    receipt['source_commit_at_end'] = git('rev-parse', 'HEAD')
    receipt['changed_inputs_during_run'] = changed_inputs(hashes)
    receipt['passed'] = len(receipt['steps']) == len(COMMANDS) and all(
        step['exit_code'] == 0 for step in receipt['steps']) and not receipt['changed_inputs_during_run']
    save(receipt)
    print(json.dumps({'passed': receipt['passed'], 'changed_inputs': receipt['changed_inputs_during_run']}), flush=True)
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    if len(sys.argv) != 2 or sys.argv[1] not in ['capture', 'run']:
        raise SystemExit('Usage: run_followup_gate.py capture|run')
    if sys.argv[1] == 'capture':
        capture()
    else:
        raise SystemExit(run())
