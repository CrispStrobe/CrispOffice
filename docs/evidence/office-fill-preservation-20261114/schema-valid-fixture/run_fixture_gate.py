#!/usr/bin/env python3
"""Record and run only the two consumers of the corrected native-fill fixture."""
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
OUT = Path(__file__).resolve().parent
SDK = WORK / 'toolchain/flutter'
FLUTTER = SDK / 'bin/flutter'
DART = SDK / 'bin/cache/dart-sdk/bin/dart'
FIXTURE = 'packages/quds_office_engine/test/fixtures/fidelity/sheet-fill-native.xml'
TESTS = {
    'engine-tests': ('packages/quds_office_engine', 'test/sheet_fill_fidelity_test.dart', 5),
    'editor-tests': ('packages/quds_office_editor', 'test/sheet_fill_intent_history_test.dart', 6),
}
ENV_OVERRIDES = {
    'CI': 'true', 'BOT': 'true',
    'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'DART_SUPPRESS_ANALYTICS': 'true',
    'TMPDIR': str(WORK / 'toolchain/tmp'),
    'PUB_CACHE': str(WORK / 'toolchain/pub-cache'),
}
ENV = dict(os.environ, **ENV_OVERRIDES)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def now():
    return datetime.now(timezone.utc).isoformat()


def save(receipt):
    temporary = OUT / 'validation.json.tmp'
    temporary.write_text(json.dumps(receipt, indent=2) + '\n')
    temporary.replace(OUT / 'validation.json')


def changed_inputs(hashes):
    return [name for name, digest in hashes.items()
            if not (ROOT / name).is_file() or sha((ROOT / name).read_bytes()) != digest]


def capture(source):
    if (OUT / 'validation.json').exists():
        raise RuntimeError('Existing evidence must not be overwritten')
    head = git('rev-parse', 'HEAD').decode().strip()
    if head != source:
        raise RuntimeError('Capture requires the expected corrected commit at HEAD')
    files = set()
    for package in sorted((ROOT / 'packages').iterdir()):
        if not (package / 'lib').is_dir():
            continue
        files.update((package / 'lib').rglob('*.dart'))
        for name in ['pubspec.yaml', 'analysis_options.yaml']:
            if (package / name).is_file():
                files.add(package / name)
    files.update(ROOT / package / test for package, test, _ in TESTS.values())
    for name in [
        FIXTURE, 'pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml',
        '.dart_tool/package_config.json', '.dart_tool/package_graph.json',
    ]:
        if (ROOT / name).is_file():
            files.add(ROOT / name)
    hashes = {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in sorted(files)}
    manifest = json.dumps(hashes, sort_keys=True, indent=2).encode() + b'\n'
    (OUT / 'inputs.json.gz').write_bytes(gzip.compress(manifest, mtime=0))
    for name in ['pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
        path = ROOT / name
        (OUT / (path.name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    runtime = {
        'flutter_revision': subprocess.check_output(['git', '-C', str(SDK), 'rev-parse', 'HEAD'], text=True).strip(),
        'dart_version': subprocess.check_output([str(DART), '--version'], env=ENV, text=True).strip(),
        'files_sha256': {name: sha((SDK / name).read_bytes()) for name in [
            'bin/cache/dart-sdk/bin/dart', 'bin/cache/flutter_tools.snapshot',
            'bin/cache/artifacts/engine/linux-x64/flutter_tester',
            'bin/internal/engine.version', 'bin/cache/engine.stamp',
        ]},
        'environment': ENV_OVERRIDES,
    }
    (OUT / 'runtime.json').write_text(json.dumps(runtime, indent=2) + '\n')
    commands = []
    for name, (package, test, count) in TESTS.items():
        binary = DART if name == 'engine-tests' else FLUTTER
        command = [str(binary), 'test']
        if binary == FLUTTER:
            command.append('--no-pub')
        command.extend(['--concurrency=1', '--reporter=expanded', test])
        commands.append({'name': name, 'working_directory': package,
                         'command': command, 'expected_tests': count})
    receipt = {
        'version': 1, 'captured_at': now(), 'source_commit': source,
        'source_tree': git('rev-parse', 'HEAD^{tree}').decode().strip(),
        'worktree_status_at_capture': git('status', '--porcelain').decode().strip(),
        'scope': 'Two direct consumers of the XML-only native-fill fixture correction; no analysis or other test cohorts.',
        'inputs': {'files': len(hashes), 'manifest': 'inputs.json.gz',
                   'uncompressed_sha256': sha(manifest),
                   'archive_sha256': sha((OUT / 'inputs.json.gz').read_bytes())},
        'fixture': {'path': FIXTURE, 'sha256': hashes[FIXTURE],
                    'matches_source_git_blob': sha(git('show', source + ':' + FIXTURE)) == hashes[FIXTURE]},
        'planned_commands': commands, 'steps': [], 'passed': None,
    }
    if not receipt['fixture']['matches_source_git_blob']:
        raise RuntimeError('Fixture bytes differ from the corrected Git commit')
    save(receipt)
    print(json.dumps({'checkpoint': 'inputs_recorded', 'source': source,
                      'files': len(hashes), 'fixture_sha256': hashes[FIXTURE],
                      'manifest_sha256': receipt['inputs']['archive_sha256']}), flush=True)


def run():
    receipt = json.loads((OUT / 'validation.json').read_text())
    hashes = json.loads(gzip.decompress((OUT / 'inputs.json.gz').read_bytes()))
    if receipt['steps'] or changed_inputs(hashes):
        raise RuntimeError('An execution already exists or inputs have changed')
    receipt['started_at'] = now()
    save(receipt)
    for plan in receipt['planned_commands']:
        log = OUT / (plan['name'] + '.log')
        started = now()
        with log.open('xb') as output:
            result = subprocess.run(plan['command'], cwd=ROOT / plan['working_directory'],
                                    env=ENV, stdin=subprocess.DEVNULL,
                                    stdout=output, stderr=subprocess.STDOUT)
        counts = re.findall(r'\+(\d+): All tests passed!', log.read_text(errors='replace'))
        step = dict(plan, started_at=started, completed_at=now(), exit_code=result.returncode,
                    log=log.name, log_sha256=sha(log.read_bytes()),
                    passed_tests=int(counts[-1]) if counts else None)
        receipt['steps'].append(step)
        receipt['changed_inputs_after_step'] = changed_inputs(hashes)
        save(receipt)
        print(json.dumps(step), flush=True)
        if result.returncode or step['passed_tests'] != plan['expected_tests'] or receipt['changed_inputs_after_step']:
            break
    receipt['completed_at'] = now()
    receipt['source_commit_at_end'] = git('rev-parse', 'HEAD').decode().strip()
    receipt['changed_inputs_during_run'] = changed_inputs(hashes)
    receipt['passed'] = len(receipt['steps']) == len(TESTS) and all(
        step['exit_code'] == 0 and step['passed_tests'] == step['expected_tests']
        for step in receipt['steps']) and not receipt['changed_inputs_during_run']
    save(receipt)
    print(json.dumps({'passed': receipt['passed'], 'changed_inputs': receipt['changed_inputs_during_run']}), flush=True)
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'capture':
        capture(sys.argv[2])
    elif sys.argv[1:] == ['run']:
        raise SystemExit(run())
    else:
        raise SystemExit('Usage: run_fixture_gate.py capture SOURCE_COMMIT | run')
