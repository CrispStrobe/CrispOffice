"""Run the complete Studio Mail cohort with a frozen, explicit input boundary."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path('/workspace/scratch/7fc035b3e3ba/quds_office_suite')
parser = argparse.ArgumentParser()
parser.add_argument('--editor-zotero', action='store_true')
arguments = parser.parse_args()
WORKING = ROOT / ('packages/quds_office_editor' if arguments.editor_zotero
                  else 'packages/quds_office_editor/example')
OUTPUT = Path('/workspace/scratch/7fc035b3e3ba') / (
    'editor-zotero-final-validation' if arguments.editor_zotero
    else 'studio-mail-final-validation')
OUTPUT.mkdir(exist_ok=True)


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT, text=True).strip()


paths = git('ls-files', '--', 'packages', 'third_party', 'pubspec.yaml',
            'pubspec.lock', '.fvmrc', 'analysis_options.yaml').splitlines()
paths.append('.dart_tool/package_config.json')
tests = ([
    'test/word_zotero_converter_controller_test.dart',
    'test/word_zotero_field_context_controller_test.dart',
    'test/word_zotero_rich_controller_test.dart',
] if arguments.editor_zotero else sorted(
    str(path.relative_to(WORKING))
    for path in (WORKING / 'test').glob('*mail*_test.dart')))


def snapshot():
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            for path in paths}


def write(name, content):
    (OUTPUT / name).write_text(json.dumps(content, indent=2) + '\n')


before = snapshot()
write('inputs-before.json', before)
command = ['flutter', 'test', '--no-pub', '--concurrency=1',
           '--reporter=json', *tests]
receipt = {
    'started_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'head_at_start': git('rev-parse', 'HEAD'),
    'command': command,
    'cwd': str(WORKING),
    'selected_suite_count': len(tests),
    'captured_input_count': len(before),
    'environment': {key: os.environ.get(key) for key in [
        'CI', 'FLUTTER_ROOT', 'PUB_CACHE', 'TMPDIR',
        'DART_SUPPRESS_ANALYTICS', 'FLUTTER_SUPPRESS_ANALYTICS']},
    'status': 'running',
}
write('qualification.json', receipt)
print(json.dumps({'selected_suites': len(tests), 'captured_inputs': len(before),
                  'status': 'running'}), flush=True)
with (OUTPUT / 'tests.jsonl').open('w') as out, (OUTPUT / 'stderr.log').open('w') as err:
    result = subprocess.run(command, cwd=WORKING, stdout=out, stderr=err)
receipt['exit_code'] = result.returncode
write('qualification.json', receipt)
after = snapshot()
write('inputs-after.json', after)
starts, suites, cases, errors = {}, {}, [], []
completed_ids = set()
done = None
for line in (OUTPUT / 'tests.jsonl').read_text().splitlines():
    try:
        item = json.loads(line)
    except json.JSONDecodeError:
        continue
    kind = item.get('type')
    if kind == 'suite':
        suites[item['suite']['id']] = item['suite']
    elif kind == 'testStart':
        starts[item['test']['id']] = item['test']
    elif kind == 'error':
        errors.append(item)
    elif kind == 'testDone':
        completed_ids.add(item['testID'])
        if item.get('hidden'):
            continue
        test = starts.get(item['testID'])
        if test is None:
            errors.append({'type': 'unmatched_test_done', 'event': item})
            continue
        if (test['name'].endswith('(setUpAll)')
                or test['name'].endswith('(tearDownAll)')):
            continue
        cases.append({
            'id': item['testID'], 'suite_id': test['suiteID'],
            'suite': suites[test['suiteID']]['path'], 'name': test['name'],
            'result': item['result'], 'skipped': item['skipped'],
        })
    elif kind == 'done':
        done = item
write('cases.json', cases)
expected_suites = {str((WORKING / path).resolve()) for path in tests}
observed_suites = {suite['path'] for suite in suites.values()}
receipt.update({
    'finished_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'head_at_finish': git('rev-parse', 'HEAD'),
    'exit_code': result.returncode,
    'source_unchanged': before == after,
    'changed_inputs': [path for path in before if before[path] != after.get(path)],
    'suites': list(suites.values()),
    'observed_suite_count': len(observed_suites),
    'missing_suites': sorted(expected_suites - observed_suites),
    'unexpected_suites': sorted(observed_suites - expected_suites),
    'unfinished_test_ids': sorted(set(starts) - completed_ids),
    'passed': sum(case['result'] == 'success' and not case['skipped'] for case in cases),
    'failed': sum(case['result'] != 'success' and not case['skipped'] for case in cases),
    'skipped': sum(case['skipped'] for case in cases),
    'reporter_errors': errors,
    'reporter_done': done,
})
receipt['status'] = ('passed' if result.returncode == 0 and before == after
                     and done and done.get('success') and not errors
                     and expected_suites == observed_suites
                     and not receipt['unfinished_test_ids']
                     and not receipt['failed'] and not receipt['skipped'] else 'failed')
write('qualification.json', receipt)
print(json.dumps({key: receipt[key] for key in ['status', 'passed', 'failed',
      'skipped', 'exit_code', 'source_unchanged', 'changed_inputs']}), flush=True)
sys.exit(0 if receipt['status'] == 'passed' else 1)
