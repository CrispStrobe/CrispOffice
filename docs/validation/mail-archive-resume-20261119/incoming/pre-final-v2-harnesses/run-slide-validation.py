#!/usr/bin/env python3
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REPO = ROOT / 'quds_office_suite'
RUNTIME = ROOT / 'runtime'
spec = importlib.util.spec_from_file_location('incoming_engine', HERE / 'run-engine-validation-direct.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
out = HERE / 'slide-parser-final'
out.mkdir(exist_ok=False)
tests = ['test/slide_table_cell_color_test.dart', 'test/slide_test.dart',
         'test/slide_import_fidelity_test.dart', 'test/slide_text_fidelity_test.dart']
before = helper.source_snapshot(REPO)
dependencies_before = helper.dependency_snapshot(REPO)
helper.write_json(out / 'source-before.json', before)
helper.write_json(out / 'dependencies-before.json', dependencies_before)
dart = str(RUNTIME / 'bin/dart')
package = REPO / 'packages/quds_office_engine'
commands = []
for name, command in [
    ('tests', [dart, '--disable-dart-dev', '--packages=' + str(REPO / '.dart_tool/package_config.json'),
               str(RUNTIME / 'pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart'),
               '--platform=vm', '--compiler=kernel', '--reporter=json', '--concurrency=1', *tests]),
    ('analysis', [dart, 'analyze', '--fatal-infos', '--fatal-warnings',
                  'lib/src/slide/shapes/drawingml.dart', 'test/slide_table_cell_color_test.dart']),
    ('format', [dart, 'format', '--output=none', '--set-exit-if-changed',
                'lib/src/slide/shapes/drawingml.dart', 'test/slide_table_cell_color_test.dart']),
]:
    started = datetime.now(timezone.utc).isoformat()
    start = time.monotonic()
    with (out / (name + '.stdout.log')).open('wb') as stdout, (out / (name + '.stderr.log')).open('wb') as stderr:
        result = subprocess.run(command, cwd=package, stdout=stdout, stderr=stderr, timeout=300)
    commands.append({'name': name, 'command': command, 'cwd': str(package),
                     'started_at_utc': started, 'elapsed_seconds': round(time.monotonic()-start, 3),
                     'exit_code': result.returncode, 'stdout_sha256': helper.digest(out / (name + '.stdout.log')),
                     'stderr_sha256': helper.digest(out / (name + '.stderr.log'))})
after = helper.source_snapshot(REPO)
dependencies_after = helper.dependency_snapshot(REPO)
helper.write_json(out / 'source-after.json', after)
helper.write_json(out / 'dependencies-after.json', dependencies_after)
summary = helper.parse_tests(out / 'tests.stdout.log', tests)
helper.write_json(out / 'test-summary.json', summary)
summary.pop('tests')
changes = helper.changed_inputs(before, after)
dep_changes = helper.changed_inputs(dependencies_before, dependencies_after)
receipt = {'success': all(c['exit_code'] == 0 for c in commands) and summary['success'] and not changes and not dep_changes,
           'commands': commands, 'summary': summary, 'source_inputs': len(before),
           'changed_source_inputs': changes, 'changed_dependency_inputs': dep_changes,
           'executed_runner': helper.file_info(Path(__file__))}
helper.write_json(out / 'receipt.json', receipt)
print(json.dumps(receipt, indent=2), flush=True)
raise SystemExit(0 if receipt['success'] else 1)
