"""Run the focused Zotero/Word cohort against real, resolved package harnesses."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True, type=Path)
parser.add_argument('--engine-harness', required=True, type=Path)
parser.add_argument('--editor-harness', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
source = args.source.resolve()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
dart = shutil.which('dart')
flutter = shutil.which('flutter')


def git(*parts):
    return subprocess.check_output(['git', '-C', str(source), *parts], text=True).strip()


def fingerprint():
    paths = git('ls-files', '--', 'packages/*/lib/**',
                'packages/quds_office_engine/test/**',
                'packages/quds_office_editor/test/**').splitlines()
    entries = {path: hashlib.sha256((source / path).read_bytes()).hexdigest()
               for path in paths}
    return {
        'files': len(entries),
        'aggregate_sha256': hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest(),
    }


engine_tests = [
    'word_zotero_test.dart', 'word_zotero_simple_field_test.dart',
    'word_zotero_formatted_bibliography_test.dart',
    'zotero_client_test.dart', 'zotero_identity_client_test.dart',
    'zotero_formatted_text_test.dart', 'word_field_span_test.dart',
    'inline_field_fidelity_test.dart', 'word_bibliography_fidelity_test.dart',
    'word_revision_story_test.dart', 'word_fidelity_test.dart',
    'word_auxiliary_content_control_test.dart',
    'word_content_control_fidelity_test.dart', 'header_footer_sdt_test.dart',
]
editor_tests = ['word_zotero_controller_test.dart',
                'word_zotero_format_test.dart', 'word_zotero_dialog_test.dart']
changed = [path for path in git('diff', '--name-only',
           '0d9b008720b01371bc9db498efd063e3077be279', 'HEAD').splitlines()
           if path.endswith('.dart')]
engine_changed = [path for path in changed if '/quds_office_engine/' in path]
editor_changed = [path for path in changed if '/quds_office_editor/' in path]
commands = [
    ('engine-tests', args.engine_harness.resolve(),
     [dart, 'test', '--reporter', 'expanded', *['test/' + name for name in engine_tests]]),
    ('editor-tests', args.editor_harness.resolve(),
     [flutter, 'test', '--no-pub', '--concurrency=1', '--reporter', 'expanded',
      *['test/' + name for name in editor_tests]]),
    ('engine-analysis', source, [dart, 'analyze', '--fatal-infos', *engine_changed]),
    ('editor-analysis', source, [dart, 'analyze', '--fatal-infos', *editor_changed]),
    ('format-check', source, [dart, 'format', '--output=none', '--set-exit-if-changed', *changed]),
    ('diff-check', source, ['git', 'diff', '--check',
     '0d9b008720b01371bc9db498efd063e3077be279', 'HEAD']),
]
receipt = {
    'source_commit': git('rev-parse', 'HEAD'),
    'source_tree': git('rev-parse', 'HEAD^{tree}'),
    'source_status_at_start': git('status', '--porcelain'),
    'source_before': fingerprint(),
    'environment': {key: os.environ.get(key) for key in
                    ['FLUTTER_ROOT', 'PUB_CACHE', 'TMPDIR', 'CI']},
    'changed_dart_files': changed,
    'commands': [],
    'uses_github_actions': False,
}
for name, cwd, command in commands:
    started = time.monotonic()
    path = out / (name + '.log')
    with path.open('wb') as stream:
        result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
    log = path.read_text()
    tests = re.findall(r'\+(\d+)(?: -\d+)?: All tests passed!', log)
    entry = {
        'name': name, 'cwd': str(cwd), 'command': command,
        'exit_code': result.returncode, 'seconds': round(time.monotonic() - started, 3),
        'log': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
    }
    if tests:
        entry['passed_tests'] = int(tests[-1])
    receipt['commands'].append(entry)
    print(json.dumps(entry), flush=True)
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
receipt['source_after'] = fingerprint()
receipt['source_unchanged'] = receipt['source_before'] == receipt['source_after']
receipt['all_commands_passed'] = all(entry['exit_code'] == 0 for entry in receipt['commands'])
receipt['total_tests_passed'] = sum(entry.get('passed_tests', 0) for entry in receipt['commands'])
for name, harness in [('engine', args.engine_harness), ('editor', args.editor_harness)]:
    receipt[name + '_manifest'] = (harness / 'pubspec.yaml').read_text()
    receipt[name + '_lockfile'] = (harness / 'pubspec.lock').read_text()
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: receipt[key] for key in
                 ['all_commands_passed', 'source_unchanged', 'total_tests_passed']}), flush=True)
raise SystemExit(0 if receipt['all_commands_passed'] and receipt['source_unchanged'] else 1)
