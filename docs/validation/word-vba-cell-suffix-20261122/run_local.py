#!/usr/bin/env python3
"""Run source-bound local macro qualification with the locked Dart workspace.

Usage from any directory after configuring the pinned SDK and dependencies:
  python3 run_local.py --output /absolute/path/to/evidence
Uses the package-resolved test runner directly; never queries GitHub Actions.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from urllib.parse import urlparse, unquote

ROOT = Path(__file__).resolve().parents[3]
ENGINE = ROOT / 'packages/quds_office_engine'
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
parser.add_argument('--suites-file')
parser.add_argument('--batch-size', type=int, default=10)
args = parser.parse_args()
if not 1 <= args.batch_size <= 20:
    parser.error('--batch-size must be between 1 and 20')
OUT = Path(args.output).resolve()
OUT.mkdir(parents=True, exist_ok=True)
DART = Path(shutil.which('dart')).resolve()
CONFIG = ROOT / '.dart_tool/package_config.json'
config = json.loads(CONFIG.read_text())
test_package = next(p for p in config['packages'] if p['name'] == 'test')
uri = urlparse(test_package['rootUri'])
TEST_RUNNER = (Path(unquote(uri.path)) if uri.scheme == 'file' else
               (CONFIG.parent / unquote(test_package['rootUri'])).resolve()) / 'bin/test.dart'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    paths = set()
    for name in ('quds_office_engine', 'legacy_doc_parser'):
        paths.update((ROOT / 'packages' / name).glob('lib/**/*.dart'))
    for directory in ('test', 'tool', 'example/macros'):
        paths.update(p for p in (ENGINE / directory).rglob('*') if p.is_file()
                     and p.suffix in {'.dart', '.json', '.bas'})
    for pattern in ('**/pubspec.yaml', '**/pubspec.lock'):
        for relative in subprocess.check_output(
                ['git', 'ls-files', pattern], cwd=ROOT, text=True).splitlines():
            paths.add(ROOT / relative)
    paths.update((ROOT / '.fvmrc', CONFIG, DART, TEST_RUNNER))
    for name in ('dartvm', 'snapshots/dart2js_aot.dart.snapshot',
                 'snapshots/frontend_server_aot.dart.snapshot'):
        candidate = DART.parent / name
        if candidate.is_file():
            paths.add(candidate)
    return {str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p): digest(p)
            for p in sorted(paths)}


def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n')


def run(name, command):
    start = time.monotonic()
    with (OUT / f'{name}.stdout').open('wb') as stdout, (OUT / f'{name}.stderr').open('wb') as stderr:
        completed = subprocess.run(command, cwd=ENGINE, stdout=stdout, stderr=stderr)
    result = {'command': command, 'exitCode': completed.returncode,
              'elapsedSeconds': round(time.monotonic() - start, 3)}
    write(f'{name}.json', result)
    print(name, result['exitCode'], flush=True)
    return result


before = inputs()
write('inputs-before.json', before)
suites = sorted(set(ENGINE.glob('test/office_vba*_test.dart')) |
                set(ENGINE.glob('test/office_macro*_test.dart')))
if args.suites_file:
    suites = [ENGINE / line.strip() for line in Path(args.suites_file).read_text().splitlines() if line.strip()]
    if any(not p.is_file() or not p.resolve().is_relative_to(ENGINE) for p in suites):
        parser.error('Every suite must be an existing engine test file')
relative_suites = [str(p.relative_to(ENGINE)) for p in suites]
(OUT / 'suites.txt').write_text('\n'.join(relative_suites) + '\n')
gates = {}
batches = []
combined = OUT / 'macro-regressions.stdout'
combined.write_text('')
for index, start in enumerate(range(0, len(relative_suites), args.batch_size)):
    name = f'macro-batch-{index + 1:02d}'
    batches.append(run(name, [str(DART), f'--packages={CONFIG}', str(TEST_RUNNER),
        '--reporter=json', '--concurrency=2', *relative_suites[start:start + args.batch_size]]))
    with combined.open('ab') as aggregate:
        aggregate.write((OUT / f'{name}.stdout').read_bytes())
gates['tests'] = {'batches': batches, 'exitCode': max(g['exitCode'] for g in batches),
                  'elapsedSeconds': round(sum(g['elapsedSeconds'] for g in batches), 3)}
counts = {'passed': 0, 'failed': 0, 'skipped': 0, 'hiddenErrors': 0}
known = {}
failures = []
done = None
for line in (OUT / 'macro-regressions.stdout').read_text().splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get('type') == 'testStart':
        known[event['test']['id']] = event['test']
    elif event.get('type') == 'testDone':
        if event['result'] != 'success':
            key = 'hiddenErrors' if event.get('hidden') else 'failed'
            counts[key] += 1
            failures.append(known.get(event['testID'], {'id': event['testID']}))
        elif not event.get('hidden'):
            counts['skipped' if event.get('skipped') else 'passed'] += 1
    elif event.get('type') == 'done':
        done = event
write('macro-regressions-counts.json', {'suiteCount': len(suites), **counts,
                                     'failures': failures, 'runnerDone': done})
gates['analysis'] = run('analysis', [str(DART), 'analyze', '--fatal-infos', 'lib', 'test', 'tool'])
changed = subprocess.check_output(['git', 'diff', '--name-only',
    'b2bba1638924237435460e4238d4bd98c407fc3a', 'HEAD'], cwd=ROOT, text=True).splitlines()
changed_dart = [str(ROOT / p) for p in changed if p.startswith('packages/quds_office_engine/') and p.endswith('.dart') and (ROOT / p).is_file()]
gates['format'] = run('format', [str(DART), 'format', '--output=none',
    '--set-exit-if-changed', *changed_dart])
after = inputs()
write('inputs-after.json', after)
changes = [p for p in sorted(set(before) | set(after)) if before.get(p) != after.get(p)]
write('summary.json', {'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'],
    cwd=ROOT, text=True).strip(), 'sdkVersion': subprocess.check_output([str(DART), '--version'],
    text=True).strip(), 'suiteCount': len(suites), 'counts': counts, 'gates': gates,
    'sourceInputs': len(before), 'changedInputs': changes,
    'runnerSuccessful': bool(done and done.get('success'))})
for path in OUT.glob('*.stdout'):
    with gzip.GzipFile(filename=str(path) + '.gz', mode='wb', mtime=0) as compressed:
        compressed.write(path.read_bytes())
if changes or any(g['exitCode'] for g in gates.values()) or not done or not done.get('success'):
    raise SystemExit(1)
