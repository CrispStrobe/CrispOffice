#!/usr/bin/env python3
"""Execute the selected incoming UI cases against the live workspace.

Every invocation uses a new output directory, records raw JSON test events and
hashes all relevant local libraries/assets/tests and resolved package sources.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urlparse

ROOT = Path('/workspace/scratch/8eda9a4e1801')
REPO = ROOT / 'quds_office_suite'
RUNTIME = ROOT / 'runtime'
PLAN = json.loads((RUNTIME / 'incoming-test-plan.json').read_text())

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()

def write(path, value):
    data = (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()
    if path.suffix == '.gz':
        with path.open('wb') as stream:
            with gzip.GzipFile(fileobj=stream, mode='wb', mtime=0) as zipped:
                zipped.write(data)
    else:
        path.write_bytes(data)

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args], text=True).strip()

def files(directory):
    return [p for p in directory.rglob('*') if p.is_file()] if directory.exists() else []

def snapshots(group, package, tests):
    local = set()
    for name in ['pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml']:
        local.add(REPO / name)
    # Package selection follows the actual UI package dependency graph.
    if group == 'editor':
        package_names = ['quds_office_editor', 'quds_office_engine', 'quds_reports', 'legacy_doc_parser']
        package_roots = [REPO / 'packages' / name for name in package_names]
    else:
        package_roots = [p.parent for p in REPO.glob('packages/*/pubspec.yaml')]
        package_roots += [REPO / 'packages/quds_office_editor/example']
        package_roots += [p.parent for p in REPO.glob('third_party/*/pubspec.yaml')]
    for root in package_roots:
        for name in ['pubspec.yaml', 'analysis_options.yaml']:
            if (root / name).is_file(): local.add(root / name)
        local.update(files(root / 'lib'))
    for root in [REPO / 'packages/quds_office_editor', package]:
        for name in ['assets', 'templates', 'fonts']:
            local.update(files(root / name))
    local.update(package / name for name in tests)
    local.update(files(package / 'test/support'))
    local.add(Path(__file__).resolve())
    local.add(RUNTIME / 'incoming-test-plan.json')
    source = {str(p.relative_to(ROOT)): digest(p) for p in sorted(local)}
    dependency_paths = set()
    config_path = REPO / '.dart_tool/package_config.json'
    for name in ['package_config.json', 'package_graph.json', 'native_assets.yaml']:
        p = config_path.parent / name
        if p.is_file(): dependency_paths.add(p)
    for item in json.loads(config_path.read_text())['packages']:
        uri = urlparse(item['rootUri'])
        root = Path(unquote(uri.path)) if uri.scheme == 'file' else (config_path.parent / unquote(item['rootUri'])).resolve()
        if root.is_relative_to(REPO): continue
        dependency_paths.update(files(root / 'lib'))
        if (root / 'pubspec.yaml').is_file(): dependency_paths.add(root / 'pubspec.yaml')
    dependency_paths.update(files(REPO / '.dart_tool/lib'))
    dependency = {str(p.relative_to(ROOT)): digest(p) for p in sorted(dependency_paths)}
    return source, dependency

def parse_tests(path, expected):
    suites, tests, completed, done, errors = {}, {}, {}, [], []
    for line in path.read_text().splitlines():
        try: event = json.loads(line)
        except json.JSONDecodeError: continue
        kind = event.get('type')
        if kind == 'suite': suites[event['suite']['id']] = event['suite']
        elif kind == 'testStart': tests[event['test']['id']] = event['test']
        elif kind == 'testDone': completed[event['testID']] = event
        elif kind == 'done': done.append(event)
        elif kind == 'error': errors.append(event)
    records = []
    for test_id, event in completed.items():
        test = tests[test_id]
        if event.get('hidden') or event.get('isHidden') or test.get('isHidden'): continue
        records.append({'suite': suites[test['suiteID']]['path'], 'name': test['name'],
                        'result': event['result'], 'skipped': event.get('skipped', False)})
    present = {Path(r['suite']).name for r in records}
    missing = sorted({Path(t).name for t in expected} - present)
    counts = {'passed': sum(r['result'] == 'success' and not r['skipped'] for r in records),
              'failed': sum(r['result'] != 'success' for r in records),
              'skipped': sum(r['skipped'] for r in records)}
    counts.update({'done_events': done, 'reporter_errors': errors, 'missing_suites': missing,
                   'distinct_suites': len(present), 'cases': records})
    counts['success'] = (len(done) == 1 and done[0].get('success') is True
                         and not counts['failed'] and not errors and not missing)
    return counts

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--group', choices=['editor', 'studio'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists(): raise RuntimeError('Use a fresh output directory')
    out.mkdir(parents=True)
    package = REPO / 'packages/quds_office_editor'
    if args.group == 'studio': package /= 'example'
    tests = ['test/office_dark_slide_test.dart']
    before, dependencies_before = snapshots(args.group, package, tests)
    write(out / 'source-before.json.gz', before)
    write(out / 'dependencies-before.json.gz', dependencies_before)
    command = [str(RUNTIME / 'bin/flutter'), 'test', '--no-pub', '--concurrency=1', '--reporter=json', *tests]
    start = time.monotonic()
    started = datetime.now(timezone.utc).isoformat()
    head = git('rev-parse', 'HEAD')
    with (out / 'stdout.log').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
        result = subprocess.run(command, cwd=package, stdout=stdout, stderr=stderr, timeout=900)
    after, dependencies_after = snapshots(args.group, package, tests)
    write(out / 'source-after.json.gz', after)
    write(out / 'dependencies-after.json.gz', dependencies_after)
    summary = parse_tests(out / 'stdout.log', tests)
    write(out / 'test-cases.json.gz', summary.pop('cases'))
    changed = sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))
    dep_changed = sorted(k for k in dependencies_before.keys() | dependencies_after.keys() if dependencies_before.get(k) != dependencies_after.get(k))
    receipt = {'group': args.group, 'command': command, 'cwd': str(package),
               'started_at_utc': started, 'finished_at_utc': datetime.now(timezone.utc).isoformat(),
               'elapsed_seconds': round(time.monotonic() - start, 3), 'exit_code': result.returncode,
               'source_commit_before': head, 'source_commit_after': git('rev-parse', 'HEAD'),
               'source_inputs': len(before), 'dependency_inputs': len(dependencies_before),
               'changed_source_inputs': changed, 'changed_dependency_inputs': dep_changed,
               'test_summary': summary, 'stdout_sha256': digest(out / 'stdout.log'),
               'stderr_sha256': digest(out / 'stderr.log'),
               'environment': {k: os.environ.get(k) for k in ['PUB_CACHE','FLUTTER_ROOT','CI','TMPDIR','XDG_CONFIG_HOME','XDG_CACHE_HOME','XDG_DATA_HOME']},
               'success': result.returncode == 0 and summary['success'] and not changed and not dep_changed}
    write(out / 'receipt.json', receipt)
    print(json.dumps(receipt, indent=2), flush=True)
    return 0 if receipt['success'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
