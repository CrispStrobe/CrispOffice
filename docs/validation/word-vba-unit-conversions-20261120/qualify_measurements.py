#!/usr/bin/env python3
"""Run local Word measurement qualification against an unchanged checkout.

Source the recreated runtime's env.sh first, then pass its ordinary package:test
runner wrapper. Output is evidence only; no source, manifests or refs are edited.
"""
import argparse
import base64
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--runner', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
repo, out = args.repo.resolve(), args.out.resolve()
engine = repo / 'packages/quds_office_engine'
out.mkdir(parents=True, exist_ok=False)
dart, node = shutil.which('dart'), shutil.which('node')
assert dart and node

def git(*values):
    return subprocess.check_output(['git', *values], cwd=repo, text=True).strip()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

source_paths = git('ls-files', 'packages/quds_office_engine/lib',
    'packages/quds_office_engine/test', 'packages/quds_office_engine/tool/macros',
    'packages/quds_office_engine/example/macros', 'packages/legacy_doc_parser/lib',
    'packages/legacy_doc_parser/pubspec.yaml', 'packages/quds_office_engine/pubspec.yaml',
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml').splitlines()
before = {path: digest(repo / path) for path in source_paths}
(out / 'source-before.json').write_text(json.dumps(before, sort_keys=True, indent=2) + '\n')
report = {
    'source_head': git('rev-parse', 'HEAD'),
    'source_tree': git('rev-parse', 'HEAD^{tree}'),
    'dart_version': subprocess.check_output([dart, '--version'], text=True).strip(),
    'node_version': subprocess.check_output([node, '--version'], text=True).strip(),
    'source_files_hashed': len(before),
    'commands': [],
}

def run(name, command, cwd=engine):
    start = time.monotonic()
    print(f'Starting {name}', flush=True)
    path = out / (name + '.log')
    with path.open('w') as stream:
        result = subprocess.run([str(value) for value in command], cwd=cwd,
                                stdout=stream, stderr=subprocess.STDOUT)
    row = {'name': name, 'command': [str(value) for value in command],
           'cwd': str(cwd), 'exit_code': result.returncode,
           'seconds': round(time.monotonic() - start, 3), 'log': path.name,
           'log_sha256': digest(path)}
    print(f'Finished {name}: exit {result.returncode}', flush=True)
    return row

changed_dart = [str(repo / path) for path in git('diff', '--name-only',
    'c954d00d2fc85604ae394674bca91ea8a1dede0e', 'HEAD').splitlines() if path.endswith('.dart')]
report['commands'].append(run('format', [dart, 'format', '--output=none',
    '--set-exit-if-changed', *changed_dart]))
tests = sorted({str(path.relative_to(engine)) for pattern in
    ['office_vba*_test.dart', 'office_macro*_test.dart'] for path in (engine / 'test').glob(pattern)})
report['test_files'] = tests
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
    jobs = [executor.submit(run, 'macro-vba-tests',
                [args.runner.resolve(), *tests, '--reporter=json']),
            executor.submit(run, 'engine-analysis', [dart, 'analyze', '--fatal-infos'])]
    report['commands'].extend(job.result() for job in jobs)

events = []
for line in (out / 'macro-vba-tests.log').read_text().splitlines():
    if line.startswith('{'):
        events.append(json.loads(line))
finished = [event for event in events if event.get('type') == 'testDone' and not event.get('hidden')]
report['tests'] = {
    'file_count': len(tests),
    'passed': sum(event.get('result') == 'success' and not event.get('skipped') for event in finished),
    'failed': sum(event.get('result') != 'success' for event in finished),
    'skipped': sum(bool(event.get('skipped')) for event in finished),
    'terminal_success': any(event.get('type') == 'done' and event.get('success') is True for event in events),
}

example = engine / 'example/macros/word_measurements.bas'
define = '-DWORD_MEASUREMENTS_BAS_BASE64=' + base64.b64encode(example.read_bytes()).decode('ascii')
driver = 'tool/macros/web_vba_word_measurements_smoke.dart'
report['example_sha256'] = digest(example)
report['commands'].append(run('example-vm', [dart, define, driver]))
javascript = out / 'word-measurements.js'
report['commands'].append(run('example-js-compile', [dart, 'compile', 'js', '-O2',
    define, driver, '-o', javascript]))
report['commands'].append(run('example-js-node', [node, '-e',
    'globalThis.self = globalThis; require(' + json.dumps(str(javascript)) + ');']))
try:
    vm = json.loads((out / 'example-vm.log').read_text())
    js = json.loads((out / 'example-js-node.log').read_text())
    report['portable_equal'] = vm == js
    report['portable_result'] = vm
except (ValueError, OSError):
    report['portable_equal'] = False

after = {path: digest(repo / path) for path in source_paths}
report['source_unchanged'] = before == after
report['changed_source_paths'] = [path for path in before if before[path] != after[path]]
report['success'] = (all(row['exit_code'] == 0 for row in report['commands'])
    and report['tests']['terminal_success'] and report['tests']['failed'] == 0
    and report['tests']['skipped'] == 0 and report['portable_equal'] and report['source_unchanged'])
(out / 'qualification.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
print(json.dumps({key: report[key] for key in ['success', 'tests', 'portable_equal', 'source_unchanged']}), flush=True)
raise SystemExit(0 if report['success'] else 1)
