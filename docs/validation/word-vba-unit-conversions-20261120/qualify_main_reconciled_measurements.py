#!/usr/bin/env python3
"""Final Word qualification after reconciliation with captured remote main."""
import argparse
import base64
import collections
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

BASE = Path('/workspace/scratch/03cd41fa0e7e')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, default=BASE / 'quds_integration')
parser.add_argument('--root-repo', type=Path, default=BASE / 'quds_office_suite')
parser.add_argument('--runtime', type=Path, default=BASE / 'runtime/toolchain')
parser.add_argument('--out', type=Path, default=BASE / 'runtime/measurement-main-final')
args = parser.parse_args()
REPO = args.repo.resolve()
ROOT_REPO = args.root_repo.resolve()
RUNTIME = args.runtime.resolve()
OUT = args.out.resolve()
ENGINE = REPO / 'packages/quds_office_engine'
TESTS = [
    'test/office_vba_word_measurements_test.dart',
    'test/office_vba_word_measurements_integration_test.dart',
    'test/office_vba_word_named_measurements_test.dart',
    'test/office_vba_word_named_measurements_integration_test.dart',
    'test/office_vba_word_unit_conversions_test.dart',
    'test/office_vba_word_unit_conversions_integration_test.dart',
    'test/office_vba_word_bulk_intake_conversions_test.dart',
]


def git(*arguments):
    return subprocess.check_output(['git', '-C', str(REPO), *arguments], text=True).strip()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


assert not git('status', '--porcelain'), 'Require a clean reconciled checkout.'
OUT.mkdir(parents=True, exist_ok=False)
for name in ['tmp', 'config', 'cache']:
    (OUT / name).mkdir()

root_config = ROOT_REPO / '.dart_tool/package_config.json'
root_graph = ROOT_REPO / '.dart_tool/package_graph.json'
root_config_before = digest(root_config)
root_graph_before = digest(root_graph)
configuration = json.loads(root_config.read_text())
for entry in configuration['packages']:
    if entry['name'] in {'quds_office_engine', 'legacy_doc_parser'}:
        entry['rootUri'] = (REPO / 'packages' / entry['name']).as_uri()
(REPO / '.dart_tool').mkdir(exist_ok=True)
config = REPO / '.dart_tool/package_config.json'
expected_configuration = json.dumps(configuration, indent=2) + '\n'
if config.exists():
    assert config.read_text() == expected_configuration, 'Unexpected preexisting worktree package configuration.'
else:
    config.write_text(expected_configuration)
graph = REPO / '.dart_tool/package_graph.json'
if graph.exists():
    assert graph.read_bytes() == root_graph.read_bytes(), 'Unexpected worktree package graph.'
else:
    shutil.copyfile(root_graph, graph)

dart = RUNTIME / 'dart-sdk/bin/dart'
node = Path(shutil.which('node'))
kernel = RUNTIME / 'test-runner/test-runner.dill'
environment = dict(os.environ)
environment.update({
    'QUDS_VALIDATION_ROOT': str(REPO),
    'QUDS_DART_ROOT': str(RUNTIME / 'dart-sdk'),
    'PUB_CACHE': str(RUNTIME / 'pub-cache'),
    'TMPDIR': str(OUT / 'tmp'),
    'XDG_CONFIG_HOME': str(OUT / 'config'),
    'XDG_CACHE_HOME': str(OUT / 'cache'),
    'DART_SUPPRESS_ANALYTICS': 'true',
    'PATH': str(dart.parent) + os.pathsep + os.environ['PATH'],
})

source_paths = git('ls-files', 'packages/quds_office_engine/lib',
    'packages/quds_office_engine/test', 'packages/quds_office_engine/tool/macros',
    'packages/quds_office_engine/example/macros', 'packages/legacy_doc_parser/lib',
    'packages/legacy_doc_parser/pubspec.yaml', 'packages/quds_office_engine/pubspec.yaml',
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.fvmrc').splitlines()
runtime_paths = [config, REPO / '.dart_tool/package_graph.json', dart, kernel,
    RUNTIME / 'dart-sdk/bin/snapshots/dart2js_aot.dart.snapshot',
    RUNTIME / 'dart-sdk/bin/snapshots/analysis_server_aot.dart.snapshot',
    RUNTIME / 'environment.json', Path(__file__)]


def source_snapshot():
    return {path: digest(REPO / path) for path in source_paths}


def runtime_snapshot():
    return {str(path): digest(path) for path in runtime_paths if path.exists()}


before = source_snapshot()
runtime_before = runtime_snapshot()
(OUT / 'source-before.json').write_text(json.dumps(before, indent=2, sort_keys=True) + '\n')
(OUT / 'runtime-before.json').write_text(json.dumps(runtime_before, indent=2, sort_keys=True) + '\n')
report = {
    'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_head': git('rev-parse', 'HEAD'),
    'source_tree': git('rev-parse', 'HEAD^{tree}'),
    'source_files_hashed': len(before),
    'dart_version': subprocess.check_output([dart, '--version'], env=environment, text=True).strip(),
    'node_version': subprocess.check_output([node, '--version'], env=environment, text=True).strip(),
    'production_sha256': before['packages/quds_office_engine/lib/src/automation/office_vba_language.dart'],
    'commands': [],
    'test_files': TESTS,
    'runtime_environment': {key: environment[key] for key in [
        'QUDS_VALIDATION_ROOT', 'QUDS_DART_ROOT', 'PUB_CACHE', 'TMPDIR',
        'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'DART_SUPPRESS_ANALYTICS']},
}


def run(name, command):
    start = time.monotonic()
    print('Starting ' + name, flush=True)
    log = OUT / (name + '.log')
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with log.open('w') as stream:
        result = subprocess.run([str(value) for value in command], cwd=ENGINE,
            env=environment, stdout=stream, stderr=subprocess.STDOUT)
    row = {'name': name, 'command': [str(value) for value in command],
        'cwd': str(ENGINE), 'started_utc': started,
        'finished_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'exit_code': result.returncode, 'seconds': round(time.monotonic() - start, 3),
        'log': log.name, 'log_sha256': digest(log)}
    report['commands'].append(row)
    (OUT / 'progress.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Finished {name}: exit {result.returncode}', flush=True)
    return result.returncode


changed_dart = [str(ENGINE / path) for path in [*TESTS,
    'tool/macros/web_vba_word_measurements_smoke.dart',
    'tool/macros/web_vba_word_named_measurements_smoke.dart']]
run('format', [dart, 'format', '--output=none', '--set-exit-if-changed', *changed_dart])
run('measurement-tests', [dart, '--old_gen_heap_size=768', f'--packages={config}',
    kernel, '--compiler', 'source', '--concurrency=1', '--timeout=4x',
    *TESTS, '--reporter=json'])
run('bulk-intake-node', [dart, '--old_gen_heap_size=768', f'--packages={config}',
    kernel, '--platform=node', '--compiler=dart2js', '--concurrency=1', '--timeout=4x',
    'test/office_vba_word_bulk_intake_conversions_test.dart', '--reporter=json'])
run('engine-analysis', [dart, 'analyze', '--fatal-infos'])

events = []
for line in (OUT / 'measurement-tests.log').read_text().splitlines():
    if line.startswith('{'):
        events.append(json.loads(line))
suites = {event['suite']['id']: event['suite']['path'] for event in events if event.get('type') == 'suite'}
starts = {event['test']['id']: event['test'] for event in events if event.get('type') == 'testStart'}
finished = [event for event in events if event.get('type') == 'testDone' and not event.get('hidden')]
identities = []
occurrences = collections.Counter()
per_file = {}
for event in finished:
    test = starts[event['testID']]
    suite_path = Path(suites[test['suiteID']])
    file = str(suite_path.relative_to(ENGINE) if suite_path.is_absolute() else suite_path)
    key = (file, test['name'])
    occurrences[key] += 1
    identities.append({'file': file, 'name': test['name'], 'occurrence': occurrences[key],
        'result': event['result'], 'skipped': bool(event.get('skipped'))})
    counts = per_file.setdefault(file, {'passed': 0, 'failed': 0, 'skipped': 0})
    outcome = 'skipped' if event.get('skipped') else 'passed' if event['result'] == 'success' else 'failed'
    counts[outcome] += 1
report['tests'] = {
    'file_count': len(TESTS), 'passed': sum(row['passed'] for row in per_file.values()),
    'failed': sum(row['failed'] for row in per_file.values()),
    'skipped': sum(row['skipped'] for row in per_file.values()),
    'reporter_errors': sum(event.get('type') == 'error' for event in events),
    'terminal_success': bool(events and events[-1].get('type') == 'done' and events[-1].get('success') is True),
    'per_file': per_file,
}
(OUT / 'test-cases.json').write_text(json.dumps(identities, indent=2) + '\n')

node_events = []
for line in (OUT / 'bulk-intake-node.log').read_text().splitlines():
    if line.startswith('{'):
        node_events.append(json.loads(line))
node_starts = {event['test']['id']: event['test'] for event in node_events if event.get('type') == 'testStart'}
node_finished = [event for event in node_events if event.get('type') == 'testDone' and not event.get('hidden')]
node_occurrences = collections.Counter()
node_identities = []
for event in node_finished:
    test = node_starts[event['testID']]
    node_occurrences[test['name']] += 1
    node_identities.append({'file': 'test/office_vba_word_bulk_intake_conversions_test.dart',
        'name': test['name'], 'occurrence': node_occurrences[test['name']],
        'result': event['result'], 'skipped': bool(event.get('skipped'))})
report['bulk_intake_node'] = {
    'passed': sum(event['result'] == 'success' and not event.get('skipped') for event in node_finished),
    'failed': sum(event['result'] != 'success' for event in node_finished),
    'skipped': sum(bool(event.get('skipped')) for event in node_finished),
    'reporter_errors': sum(event.get('type') == 'error' for event in node_events),
    'terminal_success': bool(node_events and node_events[-1].get('type') == 'done' and node_events[-1].get('success') is True),
    'same_case_identities_as_vm': {(row['name'], row['occurrence']) for row in node_identities} ==
        {(row['name'], row['occurrence']) for row in identities if row['file'] == 'test/office_vba_word_bulk_intake_conversions_test.dart'},
}
(OUT / 'bulk-intake-node-cases.json').write_text(json.dumps(node_identities, indent=2) + '\n')


report['portable_examples'] = {}
for label, basename, define_name in [
    ('measurements', 'word_measurements', 'WORD_MEASUREMENTS_BAS_BASE64'),
    ('named-measurements', 'word_named_measurements', 'WORD_NAMED_MEASUREMENTS_BAS_BASE64'),
]:
    example = ENGINE / f'example/macros/{basename}.bas'
    define = '-D' + define_name + '=' + base64.b64encode(example.read_bytes()).decode()
    driver = f'tool/macros/web_vba_{basename}_smoke.dart'
    result = {'example': str(example.relative_to(ENGINE)), 'example_sha256': digest(example),
        'driver': driver, 'driver_sha256': digest(ENGINE / driver), 'define': define_name}
    report['portable_examples'][label] = result
    run(label + '-vm', [dart, f'--packages={config}', define, driver])
    javascript = OUT / (basename + '.js')
    run(label + '-js-compile', [dart, 'compile', 'js', '-O2', f'--packages={config}', define, driver, '-o', javascript])
    run(label + '-js-node', [node, '-e', 'globalThis.self = globalThis; require(' + json.dumps(str(javascript)) + ');'])
    try:
        vm = json.loads((OUT / (label + '-vm.log')).read_text())
        js = json.loads((OUT / (label + '-js-node.log')).read_text())
        result['portable_equal'] = vm == js
        result['portable_result'] = vm
    except (ValueError, OSError):
        result['portable_equal'] = False
report['portable_equal'] = all(result['portable_equal'] for result in report['portable_examples'].values())
report['incoming_example_sha256'] = digest(ENGINE / 'example/macros/word_unit_conversions.bas')

after = source_snapshot()
runtime_after = runtime_snapshot()
(OUT / 'source-after.json').write_text(json.dumps(after, indent=2, sort_keys=True) + '\n')
(OUT / 'runtime-after.json').write_text(json.dumps(runtime_after, indent=2, sort_keys=True) + '\n')
report['source_unchanged'] = before == after
report['runtime_unchanged'] = runtime_before == runtime_after
report['source_head_unchanged'] = report['source_head'] == git('rev-parse', 'HEAD')
report['root_package_configuration_unchanged'] = root_config_before == digest(root_config) and root_graph_before == digest(root_graph)
report['changed_source_paths'] = [path for path in before if before[path] != after[path]]
report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
report['success'] = (all(row['exit_code'] == 0 for row in report['commands'])
    and report['tests']['terminal_success'] and report['tests']['failed'] == 0
    and report['tests']['skipped'] == 0 and report['tests']['reporter_errors'] == 0
    and report['portable_equal'] and report['source_unchanged'] and report['runtime_unchanged']
    and report['source_head_unchanged'] and report['root_package_configuration_unchanged']
    and report['bulk_intake_node']['terminal_success']
    and report['bulk_intake_node']['failed'] == 0
    and report['bulk_intake_node']['skipped'] == 0
    and report['bulk_intake_node']['reporter_errors'] == 0
    and report['bulk_intake_node']['same_case_identities_as_vm'])
(OUT / 'qualification.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
print(json.dumps({key: report[key] for key in ['success', 'tests', 'portable_equal',
    'source_unchanged', 'runtime_unchanged', 'root_package_configuration_unchanged']}), flush=True)
raise SystemExit(0 if report['success'] else 1)
