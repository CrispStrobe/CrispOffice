import hashlib
import json
import pathlib
import shlex
import subprocess
import time


workspace = pathlib.Path('/home/agent/.codex/skills/remote-skills/.workspaces/quds-word-vba-20261121')
repository = workspace / 'quds_office_suite'
engine = repository / 'packages/quds_office_engine'
staging = workspace / 'validation/packages/quds_office_engine'
logs = workspace / 'validation/logs'
prefix = 'word-comparison-colors-latest'
names = [
    'office_vba_word_colors_footnote_separator_integration',
    'word_footnote_separator_docx',
    'word_footnote_separator_layout',
    'odt_footnote_separator',
    'odt_footnote_separator_libreoffice',
    'odt_reader_libreoffice_defaults',
    'odt_libreoffice_fixture',
    'word_zotero_note_images_integration',
    'office_macro_word_font_colors',
    'office_vba_word_comparison_colors_integration',
    'word_package_preservation',
    'word_step_atomicity',
    'word_footnote_reference',
    'word_note_numbering',
    'odt_note_fidelity',
    'odt_note_configuration_styles',
    'word_zotero_transfer',
    'word_zotero_transfer_session',
]
files = ['test/' + name + '_test.dart' for name in names]
for path in files:
    if not (engine / path).is_file():
        raise SystemExit('Requested test file is missing: ' + path)


def write_json(suffix, value):
    (logs / (prefix + suffix)).write_text(json.dumps(value, indent=2) + '\n')


def manifest(paths):
    return ''.join(
        hashlib.sha256(path.read_bytes()).hexdigest() + '  '
        + str(path.relative_to(repository)) + '\n'
        for path in sorted(paths)
    )


def source_manifest():
    # Include the complete engine input scopes, fixtures, helpers, and source
    # examples so the receipt identifies more than just the selected test files.
    paths = {
        path
        for directory in ['lib', 'test', 'tool/macros', 'tool/zotero', 'example/macros']
        for path in (engine / directory).rglob('*')
        if path.is_file()
    }
    paths.add(engine / 'pubspec.yaml')
    return manifest(paths)


def command_record(command):
    return (
        'source ' + str(workspace / 'validation-env.sh') + '\n'
        + 'cd ' + str(staging) + '\n' + shlex.join(command) + '\n'
    )


checkpoint = subprocess.check_output(
    ['git', 'rev-parse', 'HEAD'], cwd=repository, text=True,
).strip()
sdk = subprocess.check_output(['dart', '--version'], text=True).strip()
(logs / (prefix + '-test-manifest.txt')).write_text('\n'.join(files) + '\n')
(logs / (prefix + '-test-source.sha256')).write_text(
    manifest([engine / path for path in files]),
)
before = source_manifest()
(logs / (prefix + '-source-before.sha256')).write_text(before)
environment_inputs = [
    staging / 'pubspec.yaml',
    staging / '.dart_tool/package_config.json',
    workspace / 'validation/pubspec.lock',
    workspace / 'validation-env.sh',
]
(logs / (prefix + '-harness-inputs.sha256')).write_text(''.join(
    hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + str(path) + '\n'
    for path in environment_inputs if path.is_file()
))
json_reporter = logs / (prefix + '-tests.jsonl')
command = [
    'dart', 'test', '--reporter=expanded', '--concurrency=2',
    '--file-reporter=json:' + str(json_reporter), *files,
]
(logs / (prefix + '-command.txt')).write_text(command_record(command))
started = time.time()
print(json.dumps({
    'status': 'tests started', 'checkpoint': checkpoint, 'testFiles': len(files),
    'sourceInputs': len(before.splitlines()), 'sdk': sdk,
}), flush=True)
with (logs / (prefix + '-tests.log')).open('w') as output:
    result = subprocess.run(command, cwd=staging, stdout=output, stderr=subprocess.STDOUT)
after = source_manifest()
(logs / (prefix + '-source-after-tests.sha256')).write_text(after)
starts = {}
ends = {}
suites = {}
if json_reporter.is_file():
    for line in json_reporter.read_text().splitlines():
        event = json.loads(line)
        if event['type'] == 'suite':
            suites[event['suite']['id']] = event['suite']['path']
        elif event['type'] == 'testStart':
            starts[event['test']['id']] = event['test']
        elif event['type'] == 'testDone':
            ends[event['testID']] = event
counts = {'passed': 0, 'failed': 0, 'skipped': 0}
failed = []
for test_id, event in ends.items():
    test = starts.get(test_id, {})
    if event.get('hidden') or test.get('name', '').startswith('loading '):
        continue
    category = (
        'skipped' if event.get('skipped') else
        'passed' if event['result'] == 'success' else 'failed'
    )
    counts[category] += 1
    if category == 'failed':
        failed.append({
            'name': test.get('name'), 'result': event['result'],
            'suite': suites.get(test.get('suiteID')),
        })
lines = (logs / (prefix + '-tests.log')).read_text().splitlines()
receipt = {
    'checkpointAtStart': checkpoint,
    'sdk': sdk,
    'testFiles': len(files),
    'sourceInputs': len(before.splitlines()),
    'sourceManifestSha256': hashlib.sha256(before.encode()).hexdigest(),
    'command': command,
    'exitCode': result.returncode,
    'durationSeconds': round(time.time() - started, 3),
    'inputsUnchangedDuringTests': before == after,
    'counts': counts,
    'failedTests': failed,
    'lastOutput': lines[-20:],
}
write_json('-result.json', receipt)
print(json.dumps({'status': 'tests complete', **receipt}, indent=2), flush=True)
if result.returncode or before != after:
    raise SystemExit(result.returncode or 99)

analysis_command = ['dart', 'analyze', '--fatal-infos', 'lib', 'test', 'tool/macros', 'tool/zotero']
(logs / (prefix + '-analysis-command.txt')).write_text(command_record(analysis_command))
started = time.time()
print(json.dumps({'status': 'analysis started', 'command': analysis_command}), flush=True)
with (logs / (prefix + '-analysis.log')).open('w') as output:
    analysis = subprocess.run(analysis_command, cwd=staging, stdout=output, stderr=subprocess.STDOUT)
after_analysis = source_manifest()
(logs / (prefix + '-source-after-analysis.sha256')).write_text(after_analysis)
analysis_receipt = {
    'checkpointAtStart': checkpoint,
    'sdk': sdk,
    'command': analysis_command,
    'exitCode': analysis.returncode,
    'durationSeconds': round(time.time() - started, 3),
    'inputsUnchangedDuringAnalysis': after == after_analysis,
    'output': (logs / (prefix + '-analysis.log')).read_text(),
}
write_json('-analysis-result.json', analysis_receipt)
print(json.dumps({'status': 'analysis complete', **analysis_receipt}, indent=2), flush=True)
raise SystemExit(analysis.returncode if after == after_analysis else 99)
