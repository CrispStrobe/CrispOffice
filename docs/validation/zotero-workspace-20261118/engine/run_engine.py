#!/usr/bin/env python3
"""Run the complete current Zotero engine cohort without invoking pub or CI."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--workspace', type=Path, required=True)
parser.add_argument('--toolchain', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo, workspace, toolchain, out = [p.resolve() for p in (
    args.repo, args.workspace, args.toolchain, args.output)]
out.mkdir(parents=True, exist_ok=True)
if (out / 'run.json').exists() or (out / 'summary.json').exists():
    raise RuntimeError('Use a fresh output directory; evidence is never overwritten')

sdk = toolchain / 'flutter-sdk'
dart = sdk / 'bin/cache/dart-sdk/bin/dart'
cwd = workspace / 'packages/quds_office_engine'
config_path = workspace / '.dart_tool/package_config.json'
graph_path = workspace / '.dart_tool/package_graph.json'
config = json.loads(config_path.read_text())
graph = {p['name']: p for p in json.loads(graph_path.read_text())['packages']}
config_by_name = {p['name']: p for p in config['packages']}

def package_root(name):
    value = config_by_name[name]['rootUri']
    return Path(unquote(urlparse(urljoin(config_path.as_uri(), value)).path))

def digest(data):
    return hashlib.sha256(data).hexdigest()

def record(path):
    data = path.read_bytes()
    blob = b'blob ' + str(len(data)).encode() + b'\0' + data
    return {'bytes': len(data), 'sha256': digest(data),
            'git_blob_sha1': hashlib.sha1(blob).hexdigest()}

def write_json(name, payload):
    (out / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n')

def compress_json(name, payload):
    data = (json.dumps(payload, indent=2, sort_keys=True) + '\n').encode()
    (out / name).write_bytes(gzip.compress(data, mtime=0))

def head():
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                   cwd=repo, text=True).strip()

selected = sorted((repo / 'packages/quds_office_engine/test').glob('*zotero*_test.dart'))
selected_paths = [str(p.relative_to(repo)) for p in selected]
if len(selected_paths) != 22 or 'packages/quds_office_engine/test/zotero_item_details_test.dart' not in selected_paths:
    raise RuntimeError('Expected 21 prior Zotero suites plus item details')

reachable = set()
queue = ['quds_office_engine'] + graph['quds_office_engine']['devDependencies']
while queue:
    name = queue.pop()
    if name in reachable:
        continue
    reachable.add(name)
    queue.extend(graph[name].get('dependencies', []))

def source_snapshot():
    paths = set(selected)
    for relative in ['packages/quds_office_engine/lib', 'packages/legacy_doc_parser/lib',
                     'packages/quds_office_engine/test/fixtures/zotero']:
        paths.update(p for p in (repo / relative).rglob('*') if p.is_file())
    for relative in ['pubspec.yaml', 'analysis_options.yaml',
                     'packages/quds_office_engine/pubspec.yaml',
                     'packages/legacy_doc_parser/pubspec.yaml']:
        paths.add(repo / relative)
    return {str(p.relative_to(repo)): record(p) for p in sorted(paths)}

def dependencies_snapshot():
    result = {}
    for name in sorted(reachable - {'quds_office_engine', 'legacy_doc_parser'}):
        root = package_root(name)
        paths = {root / 'pubspec.yaml'}
        for part in ['lib', 'bin']:
            paths.update(p for p in (root / part).rglob('*') if p.is_file())
        result.update({name + '/' + str(p.relative_to(root)): record(p) for p in sorted(paths)})
    return result

def runtime_snapshot():
    root = sdk / 'bin/cache/dart-sdk'
    return {str(p.relative_to(root)): record(p) for p in sorted(root.rglob('*')) if p.is_file()}

def workspace_snapshot():
    relatives = ['.dart_tool/package_config.json', '.dart_tool/package_graph.json',
                 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
                 'packages/quds_office_engine/pubspec.yaml',
                 'packages/legacy_doc_parser/pubspec.yaml']
    return {p: record(workspace / p) for p in relatives}

snapshotters = {'source': source_snapshot, 'dependencies': dependencies_snapshot,
                'runtime': runtime_snapshot, 'workspace': workspace_snapshot}
before = {name: fn() for name, fn in snapshotters.items()}
for name, values in before.items():
    compress_json(name + '-before.json.gz', values)


command = [str(dart), '--packages=' + str(config_path),
           str(package_root('test') / 'bin/test.dart'), '--reporter', 'json',
           '--concurrency', '4'] + ['test/' + p.name for p in selected]
env = dict(os.environ, FLUTTER_ROOT=str(sdk), PUB_CACHE=str(toolchain / 'pub-cache'),
           TMPDIR=str(toolchain / 'tmp'), XDG_CONFIG_HOME=str(toolchain / 'config'),
           CI='true', DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true')
run = {'status': 'running', 'started_at_utc': datetime.now(timezone.utc).isoformat(),
       'command': command, 'cwd': str(cwd), 'source_head_at_start': head(),
       'source_binding': 'Before/after SHA-256 and Git blob inventories; commits may advance while unchanged source is tested.',
       'selected_test_files': selected_paths, 'reachable_packages': sorted(reachable),
       'package_graph_package_count': len(config['packages']),
       'runner_sha256': digest(Path(__file__).read_bytes()),
       'runtime_version': subprocess.check_output([str(dart), '--version'], env=env, text=True).strip()}
write_json('run.json', run)
print('RUN: 22 complete current-source engine Zotero suites', flush=True)
started = time.monotonic()
timeout_error = None
with (out / 'events.jsonl').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
    try:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=stdout,
                                stderr=stderr, timeout=600)
        exit_code = result.returncode
    except subprocess.TimeoutExpired:
        exit_code = None
        timeout_error = 'Test runner exceeded the 600 second limit'
elapsed = time.monotonic() - started
after = {name: fn() for name, fn in snapshotters.items()}
for name, values in after.items():
    compress_json(name + '-after.json.gz', values)

events, parse_errors = [], []
for line_no, line in enumerate((out / 'events.jsonl').read_text().splitlines(), 1):
    try:
        events.append(json.loads(line))
    except json.JSONDecodeError:
        parse_errors.append({'line': line_no, 'text': line})
starts = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
suites = {e['suite']['id']: e['suite'] for e in events if e.get('type') == 'suite'}
done_events = [e for e in events if e.get('type') == 'testDone']
errors = [e for e in events if e.get('type') == 'error']
completion = [e for e in events if e.get('type') == 'done']
cases, excluded = [], []
for event in done_events:
    test = starts.get(event['testID'], {})
    suite = suites.get(test.get('suiteID'), {})
    case = {'id': event['testID'], 'name': test.get('name'), 'suite': suite.get('path'),
            'result': event['result'], 'skipped': event.get('skipped', False)}
    if event.get('hidden') or test.get('name', '').endswith(('(setUpAll)', '(tearDownAll)')):
        case['reason'] = 'hidden event' if event.get('hidden') else 'suite setup or teardown'
        excluded.append(case)
    else:
        cases.append(case)
compress_json('cases.json.gz', cases)
compress_json('excluded-events.json.gz', excluded)
guards = {name + '_unchanged': before[name] == after[name] for name in before}
guards['selection_unchanged'] = selected_paths == [str(p.relative_to(repo)) for p in sorted(
    (repo / 'packages/quds_office_engine/test').glob('*zotero*_test.dart'))]
guards['every_started_test_finished_once'] = (set(starts) == {e['testID'] for e in done_events}
                                             and len(done_events) == len(starts))
guards['all_22_suites_executed'] = len(suites) == len(selected_paths)
passed = (exit_code == 0 and all(guards.values()) and not errors and not parse_errors
          and len(completion) == 1 and completion[0].get('success')
          and cases and all(c['result'] == 'success' and not c['skipped'] for c in cases))
summary = {**run, 'status': 'passed' if passed else 'failed',
           'finished_at_utc': datetime.now(timezone.utc).isoformat(),
           'elapsed_seconds': elapsed, 'exit_code': exit_code, 'timeout_error': timeout_error,
           'source_head_at_end': head(), 'suite_count': len(suites),
           'substantive_test_count': len(cases),
           'substantive_results': dict(Counter(c['result'] for c in cases)),
           'substantive_skips': sum(bool(c['skipped']) for c in cases),
           'excluded_event_count': len(excluded), 'error_events': errors,
           'json_parse_errors': parse_errors, 'completion_events': completion,
           'guards': guards, 'input_file_counts': {k: len(v) for k, v in before.items()},
           'scope': 'Current engine Zotero tests with synthetic documents, fixtures and controlled transports. Earlier focused tests overlap and are not added. No GitHub CI, live Zotero account, full application build, or Word/LibreOffice acceptance.'}
for name in ['events.jsonl', 'stderr.log']:
    path = out / name
    (out / (name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    path.unlink()
compress_json('workspace-inputs.json.gz', {p: (workspace / p).read_text() for p in before['workspace']})
summary['artifacts'] = {p.name: record(p) for p in sorted(out.iterdir())
                        if p.is_file() and p.name != 'summary.json'}
write_json('summary.json', summary)
print(json.dumps({k: summary[k] for k in ['status', 'suite_count', 'substantive_test_count',
      'substantive_results', 'substantive_skips', 'exit_code', 'guards']}), flush=True)
if not passed:
    raise SystemExit(1)
