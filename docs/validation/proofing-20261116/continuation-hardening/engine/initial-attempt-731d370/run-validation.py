#!/usr/bin/env python3
"""Validate the frozen engine source in its resolved Flutter/Dart workspace.

Adapted from integration-followup/engine/run-validation.py. This runner uses
the actual repository package configuration and lock, never an isolated pub
harness. It performs no package downloads, builds of native/Wasm Harper, or
GitHub Actions queries. Exact runtime/source/dependency manifests are retained.
"""

from pathlib import Path
from datetime import datetime, timezone
from urllib.parse import unquote, urljoin, urlparse
import argparse
import gzip
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--expected-source', required=True)
    parser.add_argument('--output', required=True, type=Path)
    return parser.parse_args()


ARGS = arguments()
REPO = ARGS.repo.resolve()
RUNTIME = ARGS.runtime.resolve()
OUT = ARGS.output.resolve()
OUT.mkdir(parents=True, exist_ok=True)
ENGINE = REPO / 'packages/quds_office_engine'
HARPER = REPO / 'packages/quds_proofing_harper'
DART = RUNTIME / 'flutter/bin/cache/dart-sdk/bin/dart'
SDK = DART.parent.parent
CONFIG = REPO / '.dart_tool/package_config.json'
LOCK = REPO / 'pubspec.lock'
PACKAGE_CONFIG = json.loads(CONFIG.read_text())


def package_root(entry):
    uri = urljoin(CONFIG.as_uri(), entry['rootUri'])
    parsed = urlparse(uri)
    if parsed.scheme != 'file':
        raise ValueError(f'Non-file package root: {entry["name"]}: {uri}')
    return Path(unquote(parsed.path)).resolve()


PACKAGES = {entry['name']: package_root(entry)
            for entry in PACKAGE_CONFIG['packages']}
TEST_RUNNER = PACKAGES['test'] / 'bin/test.dart'
TEST = [DART, '--packages=' + str(CONFIG), TEST_RUNNER]


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO).decode().strip()


def sources():
    paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=REPO)
    return {name: sha(REPO / name)
            for name in paths.decode().split('\0')
            if name and not name.startswith('docs/validation/')
            and (REPO / name).is_file()}


def runtime():
    paths = [DART, SDK / 'bin/dartaotruntime', SDK / 'version',
             SDK / 'revision', CONFIG, LOCK, REPO / 'pubspec.yaml',
             RUNTIME / 'env.sh', Path(sys.executable),
             Path(__file__).resolve(), TEST_RUNNER,
             RUNTIME / 'flutter/bin/cache/flutter.version.json',
             RUNTIME / 'flutter/bin/internal/engine.version']
    paths += list((SDK / 'bin/snapshots').glob('*'))
    paths += list((SDK / 'lib/_internal').glob('*.dill'))
    return {str(path): sha(path) for path in paths if path.is_file()}


def dependencies():
    # Include every file in resolved non-workspace packages, except generated
    # cache/build/version-control directories. Workspace packages are covered
    # by the tracked source manifest, and lock/config are covered separately.
    result = {}
    ignored = {'.git', '.dart_tool', '.cache', 'build', 'node_modules'}
    for name, root in sorted(PACKAGES.items()):
        if root == REPO or REPO in root.parents:
            continue
        for directory, directories, filenames in os.walk(root):
            directories[:] = sorted(d for d in directories if d not in ignored)
            for filename in sorted(filenames):
                path = Path(directory) / filename
                if path.is_file():
                    result[f'{name}/{path.relative_to(root)}'] = sha(path)
    return result


def compressed(name, data):
    path = OUT / name
    content = (json.dumps(data, sort_keys=True, indent=2) + '\n').encode()
    path.write_bytes(gzip.compress(content, mtime=0))
    return {'file': name, 'sha256': sha(path), 'entries': len(data)}


assert git('rev-parse', 'HEAD') == ARGS.expected_source
assert not git('status', '--porcelain', '--untracked-files=no'), \
    'Tracked source changes before validation'
assert PACKAGES['quds_office_engine'] == ENGINE
assert PACKAGES['quds_proofing_harper'] == HARPER
assert PACKAGES['flutter'] == RUNTIME / 'flutter/packages/flutter'

print('Capturing frozen source, resolved dependencies, and runtime.', flush=True)
before = sources()
runtime_before = runtime()
dependencies_before = dependencies()
record = {
    'schema_version': 2,
    'source_commit': ARGS.expected_source,
    'started_at_utc': now(),
    'scope': 'Engine hyphenation/bidi/layout/DOCX/PDF, contextual run metrics, '
             'incoming ODS reader/writer and Zotero/comment regressions, '
             'optional Harper Dart provider and native lifecycle contracts.',
    'dependency_mode': 'Real resolved Flutter workspace; actual root '
                       'pubspec.lock and package_config.json; no isolated harness.',
    'github_actions': 'Not queried or waited for.',
    'excluded_claims': ['browser interaction', 'HTTP/CSP delivery',
                        'new native/WebAssembly Harper build',
                        'real mobile dictionary acceptance'],
    'platform': platform.platform(),
    'python': sys.version,
    'package_count': len(PACKAGES),
    'source_manifest': compressed('source-before.json.gz', before),
    'runtime_manifest': compressed('runtime-before.json.gz', runtime_before),
    'dependency_manifest': compressed('dependencies-before.json.gz',
                                      dependencies_before),
    'source_manifest_exclusions': ['docs/validation/**'],
    'dependency_manifest_excluded_directories': [
        '.git', '.dart_tool', '.cache', 'build', 'node_modules'],
    'commands': [],
}
for origin, name in [(LOCK, 'resolved-pubspec.lock'),
                     (CONFIG, 'resolved-package-config.json'),
                     (REPO / 'pubspec.yaml', 'workspace-pubspec.yaml')]:
    shutil.copyfile(origin, OUT / name)
(OUT / 'package-roots.json').write_text(json.dumps(
    {name: str(path) for name, path in sorted(PACKAGES.items())}, indent=2) + '\n')


def save():
    (OUT / 'receipt.json').write_text(
        json.dumps(record, ensure_ascii=False, indent=2) + '\n')


def test_summary(path):
    counts = {'passed': 0, 'failed': 0, 'skipped': 0, 'hidden': 0}
    tests = {}
    failures = []
    skipped = []
    done = None
    errors = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            errors.append(number)
            continue
        if event.get('type') == 'testStart':
            tests[event['test']['id']] = event['test']['name']
        elif event.get('type') == 'testDone':
            name = tests.get(event['testID'], str(event['testID']))
            if event.get('hidden'):
                counts['hidden'] += 1
            elif event.get('skipped'):
                counts['skipped'] += 1
                skipped.append(name)
            elif event.get('result') == 'success':
                counts['passed'] += 1
            else:
                counts['failed'] += 1
                failures.append(name)
        elif event.get('type') == 'done':
            done = event
    return {**counts, 'failed_tests': failures, 'skipped_tests': skipped,
            'done': done, 'malformed_event_lines': errors}


def run(label, command, cwd, timeout=1200, events=None):
    start = time.monotonic()
    begin = now()
    log = OUT / (label + '.log')
    print('Running ' + label, flush=True)
    with log.open('w') as stream:
        try:
            code = subprocess.run([str(part) for part in command], cwd=cwd,
                                  stdout=stream, stderr=subprocess.STDOUT,
                                  timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            code = 124
            stream.write('\nValidation timeout reached.\n')
    entry = {'label': label, 'command': [str(part) for part in command],
             'working_directory': str(cwd), 'started_at_utc': begin,
             'exit_code': code, 'duration_seconds': round(time.monotonic() - start, 3),
             'log': log.name, 'log_sha256': sha(log)}
    if events is not None and events.is_file():
        entry['events'] = {'file': events.name, 'sha256': sha(events)}
        entry['summary'] = test_summary(events)
    record['commands'].append(entry)
    save()
    print(label, code, entry.get('summary', {}), flush=True)
    if code:
        print('\n'.join(log.read_text().splitlines()[-40:]), flush=True)
    return code == 0 and (events is None or (
        events.is_file() and entry['summary']['done'] is not None
        and entry['summary']['done'].get('success') is True
        and not entry['summary']['malformed_event_lines']))


def run_tests(label, names, cwd):
    events = OUT / (label + '.events.jsonl')
    return run(label, [*TEST, '--concurrency=4', '--reporter=expanded',
                       '--file-reporter=json:' + str(events),
                       *[f'test/{name}_test.dart' for name in names]],
               cwd, events=events)


success = True
save()
try:
    success = run('dart-version', [DART, '--version'], REPO) and success
    tests = [
        'proofing_hyphenation', 'variable_line_breaker', 'bidi', 'word_layout',
        'word_styles_layout', 'style_cascade', 'word_style_introduction',
        'styleless_import_fidelity', 'word_referenced_styles_and_breaks',
        'word_package_preservation', 'word_preserved_header',
        'word_note_numbering', 'word_footnote_reference',
        'word_note_script_break', 'word_table_tall_frame_layout',
        'word_table_tall_toc_layout', 'word_table_nested_layout',
        'word_small_caps', 'office_pdf_export', 'arabic_pdf_export',
        'word_zotero_bibliography_layout', 'line_breaker_controls',
        'line_breaker_measure_line', 'word_run_measure',
        'word_run_measure_boundaries', 'word_run_fragment_fallback',
    ]
    success = run_tests('hyphenation-layout-export-tests', tests, ENGINE) and success
    incoming = ['ods_sheet_reader', 'ods_sheet_writer',
                'word_comment_proofing_styles'] + sorted(
        path.stem[:-5] for path in (ENGINE / 'test').glob('*zotero*_test.dart'))
    success = run_tests('incoming-ods-zotero-tests', incoming, ENGINE) and success
    success = run_tests('harper-provider-tests', ['harper_provider'], HARPER) and success
    success = run_tests('harper-native-guards', ['harper_native'], HARPER) and success
finally:
    print('Checking final source, dependencies, and runtime.', flush=True)
    after = sources()
    runtime_after = runtime()
    dependencies_after = dependencies()
    head_after = git('rev-parse', 'HEAD')
    status_after = git('status', '--porcelain', '--untracked-files=no')
    record.update({
        'source_unchanged': before == after,
        'runtime_unchanged': runtime_before == runtime_after,
        'dependencies_unchanged': dependencies_before == dependencies_after,
        'head_after': head_after,
        'head_unchanged': head_after == ARGS.expected_source,
        'git_tracked_status': status_after,
        'finished_at_utc': now(),
        'passed': success and before == after and runtime_before == runtime_after
                  and dependencies_before == dependencies_after
                  and head_after == ARGS.expected_source and not status_after,
        'source_after_manifest': compressed('source-after.json.gz', after),
        'runtime_after_manifest': compressed('runtime-after.json.gz', runtime_after),
        'dependency_after_manifest': compressed('dependencies-after.json.gz',
                                                 dependencies_after),
    })
    for kind, initial, final in [
        ('source', before, after), ('runtime', runtime_before, runtime_after),
        ('dependencies', dependencies_before, dependencies_after),
    ]:
        if initial != final:
            record['changed_' + kind + '_paths'] = [
                path for path in sorted(initial.keys() | final.keys())
                if initial.get(path) != final.get(path)]
    save()
    print(json.dumps({key: record[key] for key in [
        'passed', 'source_unchanged', 'runtime_unchanged',
        'dependencies_unchanged', 'head_unchanged', 'source_manifest',
        'dependency_manifest']}), flush=True)

sys.exit(0 if record['passed'] else 1)
