#!/usr/bin/env python3
"""Re-run the two-file main-refresh conflict gate with the pinned SDK."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
MODE = sys.argv[1]
ENGINE = [
    'test/slide_import_fidelity_test.dart',
    'test/slide_gradient_merge_test.dart',
]
RESOLVED = [
    'packages/quds_office_engine/lib/src/slide/serial/slide_serial.dart',
    'packages/quds_office_engine/test/slide_import_fidelity_test.dart',
]

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()

SOURCE = git('rev-parse', 'HEAD')
FILES = RESOLVED
INPUTS = FILES + [
    'packages/quds_office_engine/test/slide_gradient_merge_test.dart',
    'pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json',
]

def hashes():
    return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in INPUTS}

before = hashes()
commands = []
if MODE == 'engine':
    config = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    test_uri = next(p['rootUri'] for p in config['packages'] if p['name'] == 'test')
    test_root = Path(unquote(urlparse(test_uri).path))
    cwd = ROOT / 'packages/quds_office_engine'
    commands = [['dart', f'--packages={ROOT / ".dart_tool/package_config.json"}', str(test_root / 'bin/test.dart'), '--reporter=json', *ENGINE]]
elif MODE == 'static':
    cwd = ROOT
    commands = [['dart', 'analyze', '--fatal-infos', *FILES], ['dart', 'format', '--output=none', '--set-exit-if-changed', *FILES]]
else:
    raise SystemExit('Choose engine or static')

runs = []
for index, command in enumerate(commands):
    suffix = '.jsonl' if MODE != 'static' else '.log'
    stdout = OUT / f'{MODE}-{index}{suffix}'
    stderr = OUT / f'{MODE}-{index}.stderr.log'
    started = time.time()
    with stdout.open('w') as out, stderr.open('w') as err:
        result = subprocess.run(command, cwd=cwd, stdout=out, stderr=err, check=False, timeout=300)
    record = {'command': command, 'cwd': str(cwd), 'exit_code': result.returncode, 'seconds': round(time.time() - started, 3)}
    if MODE != 'static':
        events = [json.loads(line) for line in stdout.read_text().splitlines() if line.startswith('{')]
        starts = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
        suites = {e['suite']['id']: e['suite']['path'] for e in events if e.get('type') == 'suite'}
        done = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
        successful = [e for e in done if e.get('result') == 'success' and not e.get('skipped')]
        identities = [(suites[starts[e['testID']]['suiteID']], starts[e['testID']]['name']) for e in successful]
        record.update(passing=len(successful), distinct_passing=len(set(identities)), skipped=sum(bool(e.get('skipped')) for e in done), errors=sum(e.get('type') == 'error' for e in events), finished=any(e.get('type') == 'done' and e.get('success') for e in events))
        record['accepted'] = result.returncode == 0 and record['finished'] and record['passing'] > 0 and record['passing'] == record['distinct_passing'] and record['skipped'] == 0 and record['errors'] == 0
    else:
        record['accepted'] = result.returncode == 0
    record['stdout_sha256'] = hashlib.sha256(stdout.read_bytes()).hexdigest()
    record['stderr_sha256'] = hashlib.sha256(stderr.read_bytes()).hexdigest()
    runs.append(record)

after = hashes()
source_clean = git('diff', '--name-only', 'HEAD', '--', 'packages') == ''
receipt = {'mode': MODE, 'source_commit': SOURCE, 'source_parents': git('show', '-s', '--format=%P', 'HEAD').split(), 'tracked_package_sources_clean': source_clean, 'source_tree': git('rev-parse', 'HEAD^{tree}'), 'source_inputs': before, 'source_inputs_unchanged': before == after, 'runs': runs, 'accepted': before == after and source_clean and all(r['accepted'] for r in runs)}
(OUT / f'{MODE}-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
sys.exit(0 if receipt['accepted'] else 1)
