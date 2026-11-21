#!/usr/bin/env python3
"""Qualify Word section macros locally without GitHub Actions.

Requires Dart >=3.12, Node, and access to the locked pub dependencies (or an
existing PUB_CACHE). Example, from this checkout:
  python3 docs/validation/word-vba-sections-20261121/reproduce.py \
    --dart /path/to/dart --node node --work-dir /empty/path/outside/checkout

Only copied workspace-resolution lines are removed. Source files, both font
fixture directories, and the root lock are captured and checked for changes.
The final evidence archive contains receipts and logs, never an SDK, package
cache, copied checkout, or compiled JavaScript.
"""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import time


TREES = (
    'packages/quds_office_engine',
    'packages/legacy_doc_parser',
    'packages/quds_office_editor/fonts',
    'packages/quds_office_editor/example/fonts',
)
CHANGED_TESTS = (
    'office_macro_word_orientation_test.dart',
    'office_macro_word_section_start_test.dart',
    'office_vba_word_sections_test.dart',
    'office_vba_word_sections_integration_test.dart',
    'office_vba_word_page_setup_test.dart',
    'office_vba_word_page_setup_integration_test.dart',
)
NATIVE_TESTS = (
    'office_operations_test.dart',
    'office_steps_test.dart',
    'word_steps_vocabulary_test.dart',
    'word_step_atomicity_test.dart',
    'word_structure_steps_test.dart',
    'word_structure_integrity_test.dart',
    'word_section_clone_fidelity_test.dart',
    'word_header_picture_identity_test.dart',
    'word_header_visual_reconciliation_test.dart',
    'word_layout_test.dart',
    'fidelity_waves_test.dart',
)
PORTABLE = (
    ('sections', 'word_sections.bas', 'WORD_SECTIONS_BAS_BASE64',
     'web_vba_word_sections_smoke.dart'),
    ('page-setup', 'word_page_setup.bas', 'WORD_PAGE_SETUP_BAS_BASE64',
     'web_vba_word_page_setup_smoke.dart'),
)
IGNORED = {'.dart_tool', 'build', '__pycache__'}
ENGINE_LOCK = 'packages/quds_office_engine/pubspec.lock'
EXAMPLE_LOCK = 'packages/quds_office_engine/example/pubspec.lock'


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def snapshot(root, extra=(), exclude=()):
    files = [root / name for name in extra]
    for name in TREES:
        files.extend(path for path in (root / name).rglob('*')
                     if path.is_file() and
                     not IGNORED.intersection(path.relative_to(root).parts))
    return {str(path.relative_to(root)): digest(path) for path in sorted(files)
            if str(path.relative_to(root)) not in exclude}


def changes(before, after):
    return sorted(name for name in before.keys() | after.keys()
                  if before.get(name) != after.get(name))


def hosted_lock(path):
    """Read the scalar hosted-package identity fields in a Dart pub lock."""
    packages, current = {}, None
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'  ([a-zA-Z0-9_]+):', line)
        if match:
            current = packages.setdefault(match.group(1), {})
        elif line and not line.startswith(' '):
            current = None
        elif current is not None:
            match = re.fullmatch(r'    (source|version): (.+)', line)
            match = match or re.fullmatch(r'      (sha256|url): (.+)', line)
            if match:
                current[match.group(1)] = match.group(2).strip('"\'')
    return {name: fields for name, fields in packages.items()
            if fields.get('source') == 'hosted'}


def executable(value):
    result = shutil.which(value)
    if result is None:
        raise SystemExit(f'Executable not found: {value}')
    return str(Path(result).resolve())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--node', default='node')
    parser.add_argument('--work-dir', required=True, type=Path)
    args = parser.parse_args()
    dart, node = executable(args.dart), executable(args.node)
    repository = Path(__file__).resolve().parents[3]
    output = args.work_dir.resolve()
    if output == repository or repository in output.parents:
        raise SystemExit('--work-dir must be outside the source checkout')
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise SystemExit('--work-dir must be an empty directory')
    output.mkdir(parents=True, exist_ok=True)
    engine = output / 'packages/quds_office_engine'
    script = str(Path(__file__).resolve().relative_to(repository))
    original_extra = ('pubspec.lock', 'analysis_options.yaml', script)
    original = snapshot(repository, original_extra)
    write_json(output / 'source-before.json', original)

    for relative in TREES:
        shutil.copytree(repository / relative, output / relative,
                        ignore=shutil.ignore_patterns(*IGNORED))
    adapted = []
    for name in TREES[:2]:
        for manifest in (output / name).rglob('pubspec.yaml'):
            before = manifest.read_bytes()
            after = re.sub(rb'^resolution: workspace\r?\n', b'', before,
                           flags=re.MULTILINE)
            if before != after:
                manifest.write_bytes(after)
                adapted.append(str(manifest.relative_to(output)))
    shutil.copy2(repository / 'analysis_options.yaml', output / 'analysis_options.yaml')
    shutil.copy2(repository / 'pubspec.lock', engine / 'pubspec.lock')
    shutil.copy2(repository / 'pubspec.lock', output / 'root-pubspec.lock')
    copied = snapshot(output, ('analysis_options.yaml',), (ENGINE_LOCK,))
    write_json(output / 'copied-source-before.json', copied)
    write_json(output / 'manifest-adaptations.json', adapted)
    if changes(original, snapshot(repository, original_extra)):
        raise SystemExit('Source checkout changed while preparing validation')

    environment = os.environ.copy()
    for name, directory in (('PUB_CACHE', 'pub-cache'),
                            ('XDG_CONFIG_HOME', 'config')):
        environment.setdefault(name, str(output / directory))
    (output / 'tmp').mkdir()
    environment.update(TMPDIR=str(output / 'tmp'), CI='true',
                       DART_SUPPRESS_ANALYTICS='true')
    records, portable = [], {}
    receipt = {'status': 'running', 'python': sys.version, 'commands': records,
               'portable': portable, 'workspace_directives_removed': adapted}
    tests = sorted({str(path.relative_to(engine))
                    for pattern in ('office_macro*_test.dart', 'office_vba*_test.dart',
                                    'word_zotero*_test.dart', 'zotero*_test.dart')
                    for path in (engine / 'test').glob(pattern)} |
                   {'test/' + name for name in NATIVE_TESTS})
    receipt['test_files'] = tests
    (output / 'test-files.txt').write_text('\n'.join(tests) + '\n')

    def run(label, command):
        started = datetime.now(timezone.utc).isoformat()
        begin = time.monotonic()
        with (output / (label + '.stdout')).open('wb') as stdout, \
                (output / (label + '.stderr')).open('wb') as stderr:
            result = subprocess.run(command, cwd=engine, env=environment,
                                    stdout=stdout, stderr=stderr)
        record = {'label': label, 'command': command, 'cwd': str(engine),
                  'started_utc': started, 'exit_code': result.returncode,
                  'seconds': round(time.monotonic() - begin, 3)}
        records.append(record)
        write_json(output / 'commands.json', records)
        print(json.dumps(record), flush=True)
        if result.returncode:
            raise RuntimeError(f'{label} failed with exit {result.returncode}')

    failed = None
    effective_lock = None
    try:
        run('dart-version', [dart, '--version'])
        run('node-version', [node, '--version'])
        run('dependencies', [dart, 'pub', 'get'])
        root_lock = hosted_lock(output / 'root-pubspec.lock')
        resolved = hosted_lock(engine / 'pubspec.lock')
        mismatches = {name: {'root': root_lock.get(name), 'resolved': fields}
                      for name, fields in resolved.items()
                      if fields != root_lock.get(name)}
        write_json(output / 'dependency-comparison.json',
                   {'hosted_packages': len(resolved), 'mismatches': mismatches,
                    'resolved': resolved})
        if not resolved or mismatches:
            raise RuntimeError('Resolved dependencies differ from the root lock')
        shutil.copy2(engine / 'pubspec.lock', output / 'resolved-pubspec.lock')
        effective_lock = digest(engine / 'pubspec.lock')
        run('analysis', [dart, 'analyze', '--fatal-infos', 'lib', 'tool/macros',
                         *['test/' + name for name in CHANGED_TESTS]])
        run('regression', [dart, 'test', *tests, '--reporter', 'json',
                           '--concurrency', '4'])
        for label, example, variable, harness in PORTABLE:
            source = (engine / 'example/macros' / example).read_bytes()
            define = '-D' + variable + '=' + base64.b64encode(source).decode()
            smoke = 'tool/macros/' + harness
            compiled = output / (label + '.js')
            run(label + '-vm', [dart, define, smoke])
            run(label + '-compile-js', [dart, 'compile', 'js', '-O1', define,
                                       smoke, '-o', str(compiled)])
            run(label + '-js', [node, '-e',
                               'globalThis.self=globalThis; require(process.argv[1]);',
                               str(compiled)])
            vm = (output / (label + '-vm.stdout')).read_bytes()
            js = (output / (label + '-js.stdout')).read_bytes()
            portable[label] = {'actual_bas_sha256': hashlib.sha256(source).hexdigest(),
                               'vm_js_byte_identical': vm == js,
                               'output_sha256': hashlib.sha256(vm).hexdigest(),
                               'receipt': json.loads(vm)}
            if vm != js:
                raise RuntimeError(f'{label}: VM and JavaScript receipts differ')
        receipt['status'] = 'passed'
    except (OSError, RuntimeError, ValueError) as error:
        failed = str(error)
    finally:
        after = snapshot(repository, original_extra)
        copy_after = snapshot(output, ('analysis_options.yaml',), (ENGINE_LOCK,))
        write_json(output / 'source-after.json', after)
        write_json(output / 'copied-source-after.json', copy_after)
        source_changed = changes(original, after)
        comparable_copy_after = dict(copy_after)
        # Real CLI subprocesses may resolve the copied example package on first
        # use. Its new lock is a generated dependency receipt, not a changed
        # source input. Verify every hosted identity against the captured root
        # lock before excluding that one known output from source comparison.
        if EXAMPLE_LOCK not in copied and EXAMPLE_LOCK in copy_after:
            generated = hosted_lock(output / EXAMPLE_LOCK)
            root_locked = hosted_lock(output / 'root-pubspec.lock')
            generated_mismatches = {
                name: {'root': root_locked.get(name), 'generated': fields}
                for name, fields in generated.items()
                if fields != root_locked.get(name)
            }
            receipt['generated_example_lock'] = {
                'sha256': digest(output / EXAMPLE_LOCK),
                'hosted_packages': len(generated),
                'mismatches': generated_mismatches,
            }
            shutil.copy2(output / EXAMPLE_LOCK,
                         output / 'generated-example-pubspec.lock')
            if generated and not generated_mismatches:
                comparable_copy_after.pop(EXAMPLE_LOCK)
            else:
                failed = failed or 'Generated example dependencies differ from the root lock'
        copy_changed = changes(copied, comparable_copy_after)
        lock_changed = effective_lock is not None and effective_lock != digest(engine / 'pubspec.lock')
        receipt.update(source_changed_during_run=source_changed,
                       copied_source_changed_during_run=copy_changed,
                       resolved_lock_changed_during_run=lock_changed)
        if source_changed or copy_changed or lock_changed:
            failed = failed or 'Source inputs or resolved dependency lock changed during qualification'
        log = output / 'regression.stdout'
        if log.exists():
            events = [json.loads(line) for line in log.read_text().splitlines()
                      if line.startswith('{')]
            cases = [event for event in events if event.get('type') == 'testDone'
                     and not event.get('hidden')]
            receipt['tests'] = {
                'passed': sum(event.get('result') == 'success' and not event.get('skipped') for event in cases),
                'failed': sum(event.get('result') != 'success' and not event.get('skipped') for event in cases),
                'skipped': sum(bool(event.get('skipped')) for event in cases),
                'completed': any(event.get('type') == 'done' and event.get('success') is True for event in events),
            }
        if failed:
            receipt.update(status='failed', error=failed)
        write_json(output / 'qualification.json', receipt)
        evidence = sorted(path for path in output.iterdir()
                          if path.is_file() and path.suffix in
                          ('.json', '.stdout', '.stderr', '.txt', '.lock'))
        write_json(output / 'evidence-manifest.json',
                   {path.name: digest(path) for path in evidence})
        with tarfile.open(output / 'local-qualification-evidence.tar.gz', 'w:gz') as archive:
            for path in [*evidence, output / 'evidence-manifest.json']:
                archive.add(path, arcname=path.name)
    if failed:
        raise SystemExit(f'{failed}; inspect {output / "qualification.json"}')
    print(f'Acceptance passed; receipts and complete logs: {output}', flush=True)


if __name__ == '__main__':
    main()
