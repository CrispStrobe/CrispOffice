#!/usr/bin/env python3
"""Qualify incoming spaCy installer/host boundaries with synthetic local fixtures."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REPO = ROOT / 'quds_office_suite'
RUNTIME = ROOT / 'runtime'
spec = importlib.util.spec_from_file_location('incoming_engine', HERE / 'run-engine-validation-direct.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
PLAN = json.loads((RUNTIME / 'incoming-test-plan.json').read_text())
PACKAGE = REPO / 'packages/quds_proofing_spacy'
STUDIO = REPO / 'packages/quds_office_editor/example'
WEB_OUTPUT = 'Local text analysis is unavailable in this browser.'


def source_snapshot():
    snapshot = helper.source_snapshot(REPO)
    paths = {PACKAGE / 'pubspec.yaml', STUDIO / 'pubspec.yaml'}
    for directory in ['lib', 'test', 'tool']:
        paths.update(path for path in (PACKAGE / directory).rglob('*') if path.is_file())
    paths.update(path for path in (STUDIO / 'lib').glob('studio_spacy_*.dart'))
    paths.add(STUDIO / 'test/studio_spacy_web_import_gate.dart')
    if (PACKAGE / 'analysis_options.yaml').is_file():
        paths.add(PACKAGE / 'analysis_options.yaml')
    snapshot.update({str(path.relative_to(REPO)): helper.file_info(path) for path in sorted(paths)})
    return snapshot


parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
shutil.copyfile(Path(__file__), out / 'executed-runner.py')
before = source_snapshot()
dependencies_before = helper.dependency_snapshot(REPO)
helper.write_json(out / 'source-before.json', before)
helper.write_json(out / 'dependencies-before.json', dependencies_before)
started = helper.utc_now()
head = helper.git(REPO, 'rev-parse', 'HEAD')
dart = str(RUNTIME / 'bin/dart')
node = shutil.which('node')
artifact = out / 'studio_spacy_web_import_gate.js'
tests = PLAN['spacy_tests']
format_targets = ['lib/src/installer_io.dart', 'lib/src/native_backend.dart',
                  'lib/src/native_backend_unsupported.dart', 'test/ner_removal_test.dart']
commands = []


def run(name, command, cwd, timeout=600):
    began = datetime.now(timezone.utc).isoformat()
    start = time.monotonic()
    with (out / (name + '.stdout.log')).open('wb') as stdout, (out / (name + '.stderr.log')).open('wb') as stderr:
        try:
            result = subprocess.run(command, cwd=cwd, stdout=stdout, stderr=stderr, timeout=timeout)
            code, timed_out = result.returncode, False
        except subprocess.TimeoutExpired:
            code, timed_out = None, True
    record = {'name': name, 'command': command, 'cwd': str(cwd),
              'started_at_utc': began, 'finished_at_utc': datetime.now(timezone.utc).isoformat(),
              'elapsed_seconds': round(time.monotonic()-start, 3),
              'exit_code': code, 'timed_out': timed_out,
              'stdout_sha256': helper.digest(out / (name + '.stdout.log')),
              'stderr_sha256': helper.digest(out / (name + '.stderr.log'))}
    commands.append(record)
    helper.write_json(out / (name + '.json'), record)
    print(json.dumps({'check': name, 'exit_code': code, 'elapsed_seconds': record['elapsed_seconds']}), flush=True)
    return code == 0


run('tests', [dart, '--disable-dart-dev', '--packages=' + str(REPO / '.dart_tool/package_config.json'),
              str(RUNTIME / 'pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart'),
              '--platform=vm', '--compiler=kernel', '--reporter=json', '--concurrency=2', *tests], PACKAGE)
run('analysis', [dart, 'analyze', '--fatal-infos', '--fatal-warnings', *PLAN['spacy_analysis_targets']], PACKAGE)
run('format', [dart, 'format', '--output=none', '--set-exit-if-changed', *format_targets], PACKAGE)
compiled = run('web-compile', [dart, 'compile', 'js', '-O1',
                              'test/studio_spacy_web_import_gate.dart', '-o', str(artifact)], STUDIO)
if compiled:
    run('web-run', [node, '-e', 'globalThis.self = globalThis; require(' + json.dumps(str(artifact)) + ');'], STUDIO)
web_output = (out / 'web-run.stdout.log').read_text().strip() if (out / 'web-run.stdout.log').is_file() else None
summary = helper.parse_tests(out / 'tests.stdout.log', tests)
helper.write_json(out / 'test-summary.json', summary)
summary.pop('tests')
after = source_snapshot()
dependencies_after = helper.dependency_snapshot(REPO)
helper.write_json(out / 'source-after.json', after)
helper.write_json(out / 'dependencies-after.json', dependencies_after)
changes = helper.changed_inputs(before, after)
dep_changes = helper.changed_inputs(dependencies_before, dependencies_after)
receipt = {
    'success': (len(commands) == 5 and all(c['exit_code'] == 0 for c in commands)
                and summary['success'] and not changes and not dep_changes and web_output == WEB_OUTPUT),
    'started_at_utc': started, 'finished_at_utc': helper.utc_now(),
    'source_commit_before': head, 'source_commit_after': helper.git(REPO, 'rev-parse', 'HEAD'),
    'commands': commands, 'summary': summary, 'test_selection': tests,
    'analysis_targets': PLAN['spacy_analysis_targets'],
    'format_targets': format_targets, 'source_inputs': len(before), 'dependency_inputs': len(dependencies_before),
    'changed_source_inputs': changes, 'changed_dependency_inputs': dep_changes,
    'executed_runner': helper.file_info(Path(__file__)),
    'generated_javascript': {'path': str(artifact), **helper.file_info(artifact)} if artifact.is_file() else None,
    'web_assertion': {'required_output': WEB_OUTPUT, 'actual_output': web_output, 'passed': web_output == WEB_OUTPUT},
    'limits': ['Synthetic installer/worker fixtures and Linux status checks; no installed macOS application or real model inference.',
               'The JavaScript program verifies the explicit unsupported browser boundary only.'],
}
helper.write_json(out / 'receipt.json', receipt)
print(json.dumps(receipt, indent=2), flush=True)
raise SystemExit(0 if receipt['success'] else 1)
