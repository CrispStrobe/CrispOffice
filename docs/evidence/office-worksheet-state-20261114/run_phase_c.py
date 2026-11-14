#!/usr/bin/env python3
"""Capture and retain the committed typed-formatting positive gate."""
from collections import Counter
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
OUT = Path(__file__).resolve().parent / 'phase-c-positive'
CONTROLLER = 'packages/quds_office_editor/lib/src/embed/office_controller.dart'
TEST = 'packages/quds_office_editor/test/sheet_style_history_test.dart'
TESTS = [
    'sheet_style_history_test.dart',
    'sheet_grid_history_test.dart',
    'sheet_view_history_test.dart',
    'sheet_fill_intent_history_test.dart',
    'sheet_font_color_intent_test.dart',
    'sheet_explicit_style_history_test.dart',
    'sheet_cell_state_history_test.dart',
    'pending_edit_save_test.dart',
]
EXPECTED_COUNTS = dict(zip(TESTS, [20, 14, 20, 6, 2, 3, 2, 33]))
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


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def changed(hashes):
    return [name for name, digest in hashes.items()
            if not (ROOT / name).is_file() or sha((ROOT / name).read_bytes()) != digest]


def capture(source):
    OUT.mkdir(exist_ok=True)
    assert not (OUT / 'validation.json').exists(), 'Existing evidence must not be overwritten'
    assert git('rev-parse', 'HEAD').decode().strip() == source
    assert not git('status', '--porcelain').strip(), 'Capture requires a clean committed source'
    files = {ROOT / 'packages/quds_office_editor/test' / name for name in TESTS}
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
    prepared = json.loads((OUT.parent / 'phase-c-implementation.json').read_text())
    assert all(hashes[name] == item['sha256'] for name, item in prepared['files'].items())
    tracked = set(git('ls-files', '-z').decode().rstrip('\0').split('\0'))
    git_bound = [name for name in hashes if name in tracked]
    mismatches = [name for name in git_bound
                  if hashes[name] != sha(git('show', source + ':' + name))]
    assert not mismatches, mismatches
    manifest = json.dumps(hashes, sort_keys=True, indent=2).encode() + b'\n'
    (OUT / 'inputs.json.gz').write_bytes(gzip.compress(manifest, mtime=0))
    for name in [TEST, 'pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
        path = ROOT / name
        (OUT / (path.name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    write_json(OUT / 'runtime.json', {
        'flutter_revision': subprocess.check_output(['git', '-C', str(SDK), 'rev-parse', 'HEAD'], text=True).strip(),
        'dart_version': subprocess.check_output([str(SDK / 'bin/cache/dart-sdk/bin/dart'), '--version'], env=ENV, text=True).strip(),
        'environment': ENV_OVERRIDES,
        'files_sha256': {name: sha((SDK / name).read_bytes()) for name in [
            'bin/cache/dart-sdk/bin/dart', 'bin/cache/flutter_tools.snapshot',
            'bin/cache/artifacts/engine/linux-x64/flutter_tester',
            'bin/internal/engine.version', 'bin/cache/engine.stamp',
        ]},
        'payload_limit': 'External package cache and runtime/native payloads are identified, not archived by this receipt.',
    })
    receipt = {
        'version': 1, 'phase': 'positive', 'captured_at': now(), 'source_commit': source,
        'source_tree': git('rev-parse', 'HEAD^{tree}').decode().strip(),
        'worktree_status_at_capture': git('status', '--porcelain').decode().strip(),
        'tracked_inputs_bound_to_source_git': len(git_bound),
        'untracked_generated_inputs': [name for name in hashes if name not in tracked],
        'source_git_mismatches': mismatches,
        'prepared_source_and_test_bytes_unchanged': True,
        'negative_baseline': prepared['negative_baseline'],
        'test_path': TEST, 'test_source_snapshot': Path(TEST).name + '.gz',
        'inputs': {'files': len(hashes), 'manifest': 'inputs.json.gz',
                   'uncompressed_sha256': sha(manifest),
                   'archive_sha256': sha((OUT / 'inputs.json.gz').read_bytes())},
        'expected_tests': sum(EXPECTED_COUNTS.values()), 'expected_tests_by_file': EXPECTED_COUNTS,
        'command': [str(SDK / 'bin/flutter'), 'test', '--no-pub', '--concurrency=1',
                    '--reporter=expanded', *['test/' + name for name in TESTS]],
        'working_directory': 'packages/quds_office_editor', 'completed': False,
    }
    write_json(OUT / 'validation.json', receipt)
    print(json.dumps(receipt, indent=2), flush=True)


def run():
    path = OUT / 'validation.json'
    receipt = json.loads(path.read_text())
    hashes = json.loads(gzip.decompress((OUT / 'inputs.json.gz').read_bytes()))
    assert not receipt['completed'] and not changed(hashes)
    assert git('rev-parse', 'HEAD').decode().strip() == receipt['source_commit']
    receipt['started_at'] = now()
    write_json(path, receipt)
    log = OUT / 'editor-tests.log'
    with log.open('xb') as output:
        result = subprocess.run(receipt['command'], cwd=ROOT / receipt['working_directory'],
                                env=ENV, stdin=subprocess.DEVNULL,
                                stdout=output, stderr=subprocess.STDOUT)
    output_text = log.read_text(errors='replace')
    count = re.search(r'\+(\d+)(?:\s+-(\d+))?:\s+(?:All tests passed!|Some tests failed\.)', output_text)
    receipt.update({
        'completed': True, 'completed_at': now(), 'exit_code': result.returncode,
        'log': log.name, 'log_sha256': sha(log.read_bytes()),
        'passed_tests': int(count.group(1)) if count else None,
        'failed_tests': int(count.group(2) or 0) if count else None,
        'changed_inputs_during_run': changed(hashes),
        'source_commit_at_end': git('rev-parse', 'HEAD').decode().strip(),
        'compile_failure_detected': 'Failed to load' in output_text or 'Compilation failed' in output_text,
    })
    write_json(path, receipt)
    print(json.dumps(receipt, indent=2), flush=True)
    return result.returncode


def analyze():
    test_receipt = json.loads((OUT / 'validation.json').read_text())
    assert test_receipt['exit_code'] == 0 and test_receipt['passed_tests'] == 100
    hashes = json.loads(gzip.decompress((OUT / 'inputs.json.gz').read_bytes()))
    assert not changed(hashes)
    command = [str(SDK / 'bin/flutter'), 'analyze', '--no-pub', CONTROLLER, TEST]
    receipt = {'version': 1, 'source_commit': test_receipt['source_commit'],
               'inputs_manifest': 'inputs.json.gz', 'command': command,
               'working_directory': '.', 'started_at': now()}
    path = OUT / 'analysis.json'
    assert not path.exists(), 'Existing evidence must not be overwritten'
    write_json(path, receipt)
    log = OUT / 'focused-analysis.log'
    with log.open('xb') as output:
        result = subprocess.run(command, cwd=ROOT, env=ENV, stdin=subprocess.DEVNULL,
                                stdout=output, stderr=subprocess.STDOUT)
    receipt.update({'completed_at': now(), 'exit_code': result.returncode,
                    'log': log.name, 'log_sha256': sha(log.read_bytes()),
                    'changed_inputs_during_analysis': changed(hashes),
                    'source_commit_at_end': git('rev-parse', 'HEAD').decode().strip()})
    receipt['passed'] = result.returncode == 0 and not receipt['changed_inputs_during_analysis']
    write_json(path, receipt)
    counts = Counter()
    for line in (OUT / 'editor-tests.log').read_text().splitlines():
        match = re.search(r'([^/ ]+_test\.dart): (?!loading )', line)
        if match:
            counts[match.group(1)] += 1
    assert dict(counts) == EXPECTED_COUNTS, counts
    completion = {
        'version': 1, 'completed_at': now(), 'passed': receipt['passed'],
        'source_commit': test_receipt['source_commit'],
        'source_commit_at_end': receipt['source_commit_at_end'],
        'tests_passed': test_receipt['passed_tests'], 'tests_failed': test_receipt['failed_tests'],
        'tests_by_file': dict(sorted(counts.items())),
        'analysis_items': 2, 'analysis_exit_code': result.returncode,
        'input_files': len(hashes), 'changed_inputs_during_execution': changed(hashes),
        'tracked_inputs_bound_to_source_git': test_receipt['tracked_inputs_bound_to_source_git'],
        'untracked_generated_inputs': test_receipt['untracked_generated_inputs'],
        'prepared_source_and_test_bytes_unchanged': True,
        'negative_baseline': test_receipt['negative_baseline'],
        'files_sha256': {item.name: sha(item.read_bytes()) for item in sorted(OUT.iterdir()) if item.is_file()},
    }
    write_json(OUT / 'completion.json', completion)
    print(json.dumps(completion, indent=2), flush=True)
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'capture':
        capture(sys.argv[2])
    elif len(sys.argv) == 2 and sys.argv[1] == 'run':
        raise SystemExit(run())
    elif len(sys.argv) == 2 and sys.argv[1] == 'analyze':
        raise SystemExit(analyze())
    else:
        raise SystemExit('Usage: run_phase_c.py capture SOURCE | run | analyze')
