#!/usr/bin/env python3
"""Retain the focused worksheet-grid baseline or positive validation."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

WORK = Path(__file__).resolve().parents[1]
ROOT = WORK / 'quds_office_suite'
SDK = WORK / 'toolchain/flutter'
TEST = 'packages/quds_office_editor/test/sheet_grid_history_test.dart'
CONTROLLER = 'packages/quds_office_editor/lib/src/embed/office_controller.dart'
RELATED_TESTS = [
    'packages/quds_office_editor/test/sheet_view_history_test.dart',
    'packages/quds_office_editor/test/sheet_fill_intent_history_test.dart',
    'packages/quds_office_editor/test/sheet_font_color_intent_test.dart',
    'packages/quds_office_editor/test/sheet_explicit_style_history_test.dart',
    'packages/quds_office_editor/test/sheet_cell_state_history_test.dart',
    'packages/quds_office_editor/test/pending_edit_save_test.dart',
]

ENV_OVERRIDES = {
    'CI': 'true', 'BOT': 'true',
    'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'DART_SUPPRESS_ANALYTICS': 'true',
    'TMPDIR': str(WORK / 'toolchain/tmp'),
    'PUB_CACHE': str(WORK / 'toolchain/pub-cache'),
}
ENV = dict(os.environ, **ENV_OVERRIDES)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def capture(phase, source):
    out = Path(__file__).resolve().parent / ('phase-b-' + phase)
    out.mkdir(exist_ok=True)
    if (out / 'validation.json').exists():
        raise RuntimeError('Existing evidence must not be overwritten')
    if git('rev-parse', 'HEAD').decode().strip() != source:
        raise RuntimeError('Capture requires the declared source HEAD')
    files = {ROOT / TEST, *[ROOT / name for name in RELATED_TESTS]}
    for package in (ROOT / 'packages').iterdir():
        if not (package / 'lib').is_dir():
            continue
        files.update((package / 'lib').rglob('*.dart'))
        for name in ['pubspec.yaml', 'analysis_options.yaml']:
            if (package / name).is_file():
                files.add(package / name)
    for name in ['pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml',
                 '.dart_tool/package_config.json', '.dart_tool/package_graph.json',
                 'packages/quds_office_engine/test/fixtures/fidelity/sheet-fill-native.xml',
                 'packages/quds_office_engine/test/fixtures/fidelity/sheet-normal-font-native.xlsx']:
        if (ROOT / name).is_file():
            files.add(ROOT / name)
    hashes = {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in sorted(files)}
    manifest = json.dumps(hashes, sort_keys=True, indent=2).encode() + b'\n'
    (out / 'inputs.json.gz').write_bytes(gzip.compress(manifest, mtime=0))
    for name in [TEST, 'pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
        path = ROOT / name
        (out / (path.name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    runtime = {
        'flutter_revision': subprocess.check_output(['git', '-C', str(SDK), 'rev-parse', 'HEAD'], text=True).strip(),
        'dart_version': subprocess.check_output([str(SDK / 'bin/cache/dart-sdk/bin/dart'), '--version'], env=ENV, text=True).strip(),
        'environment': ENV_OVERRIDES,
        'files_sha256': {name: sha((SDK / name).read_bytes()) for name in [
            'bin/cache/dart-sdk/bin/dart', 'bin/cache/flutter_tools.snapshot',
            'bin/cache/artifacts/engine/linux-x64/flutter_tester',
            'bin/internal/engine.version', 'bin/cache/engine.stamp',
        ]},
    }
    (out / 'runtime.json').write_text(json.dumps(runtime, indent=2) + '\n')
    receipt = {
        'version': 1, 'phase': phase, 'captured_at': now(), 'source_commit': source,
        'source_tree': git('rev-parse', 'HEAD^{tree}').decode().strip(),
        'worktree_status_at_capture': git('status', '--porcelain').decode().strip(),
        'controller_matches_source_git_blob': hashes[CONTROLLER] == sha(git('show', source + ':' + CONTROLLER)),
        'test_path': TEST, 'test_source_snapshot': Path(TEST).name + '.gz',
        'inputs': {'files': len(hashes), 'manifest': 'inputs.json.gz',
                   'uncompressed_sha256': sha(manifest),
                   'archive_sha256': sha((out / 'inputs.json.gz').read_bytes())},
        'command': [str(SDK / 'bin/flutter'), 'test', '--no-pub', '--concurrency=1',
                    '--reporter=expanded', 'test/sheet_grid_history_test.dart',
                    *([name.removeprefix('packages/quds_office_editor/') for name in RELATED_TESTS]
                      if phase == 'positive' else [])],
        'working_directory': 'packages/quds_office_editor',
        'completed': False,
    }
    if not receipt['controller_matches_source_git_blob']:
        raise RuntimeError('Controller does not match declared source commit')
    (out / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'phase': phase, 'source': source, 'input_files': len(hashes),
                      'manifest_sha256': receipt['inputs']['archive_sha256']}), flush=True)


def run(phase):
    out = Path(__file__).resolve().parent / ('phase-b-' + phase)
    path = out / 'validation.json'
    receipt = json.loads(path.read_text())
    hashes = json.loads(gzip.decompress((out / 'inputs.json.gz').read_bytes()))

    def changed():
        return [name for name, digest in hashes.items()
                if not (ROOT / name).is_file() or sha((ROOT / name).read_bytes()) != digest]

    if receipt['completed'] or changed():
        raise RuntimeError('Execution exists or captured inputs have changed')
    receipt['started_at'] = now()
    path.write_text(json.dumps(receipt, indent=2) + '\n')
    log = out / 'editor-tests.log'
    with log.open('xb') as output:
        result = subprocess.run(receipt['command'], cwd=ROOT / receipt['working_directory'],
                                env=ENV, stdin=subprocess.DEVNULL,
                                stdout=output, stderr=subprocess.STDOUT)
    text = log.read_text(errors='replace')
    count = re.search(r'\+(\d+)(?:\s+-(\d+))?:\s+(?:All tests passed!|Some tests failed\.)', text)
    receipt.update({
        'completed': True, 'completed_at': now(), 'exit_code': result.returncode,
        'log': log.name, 'log_sha256': sha(log.read_bytes()),
        'passed_tests': int(count.group(1)) if count else None,
        'failed_tests': int(count.group(2) or 0) if count else None,
        'changed_inputs_during_run': changed(),
        'source_commit_at_end': git('rev-parse', 'HEAD').decode().strip(),
        'expected_failure_phase': phase == 'baseline',
        'compile_failure_detected': 'Failed to load' in text or 'Compilation failed' in text,
    })
    path.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt), flush=True)
    return result.returncode


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == 'capture' and sys.argv[2] in ['baseline', 'positive']:
        capture(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == 'run' and sys.argv[2] in ['baseline', 'positive']:
        raise SystemExit(run(sys.argv[2]))
    else:
        raise SystemExit('Usage: run_phase_b.py capture baseline|positive SOURCE | run baseline|positive')
