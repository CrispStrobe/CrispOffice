#!/usr/bin/env python3
"""Re-run the bounded Word PageSetup acceptance without GitHub Actions.

Use a Dart >=3.12 SDK (the retained run used 3.14.1) and Node. The original
workspace remains unchanged; only copied workspace-resolution directives are
removed. Keep --work-dir to inspect the raw logs, dependency lock and receipts.
"""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--node', default='node')
    parser.add_argument('--work-dir', required=True, type=Path)
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[3]
    output = args.work_dir.resolve()
    if output == repository or repository in output.parents:
        raise SystemExit('--work-dir must be outside the source checkout')
    if output.exists() and any(output.iterdir()):
        raise SystemExit('--work-dir must be empty to avoid stale validation inputs')
    output.mkdir(parents=True, exist_ok=True)
    engine = output / 'packages/quds_office_engine'
    for name in ('quds_office_engine', 'legacy_doc_parser'):
        source = repository / 'packages' / name
        target = output / 'packages' / name
        shutil.copytree(source, target, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('.dart_tool', 'build'))
        for manifest in target.rglob('pubspec.yaml'):
            text = manifest.read_text()
            manifest.write_text(text.replace('resolution: workspace\n', ''))
    # Both directories supply shaping fixtures in fidelity_waves_test.dart.
    for relative in ('packages/quds_office_editor/fonts',
                     'packages/quds_office_editor/example/fonts'):
        shutil.copytree(repository / relative, output / relative,
                        dirs_exist_ok=True)
    shutil.copy2(repository / 'analysis_options.yaml', output / 'analysis_options.yaml')
    shutil.copy2(repository / 'pubspec.lock', engine / 'pubspec.lock')
    inputs = {str(path.relative_to(repository)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in (repository / 'packages/quds_office_engine').rglob('*')
              if path.is_file() and path.suffix in ('.dart', '.bas') and
              not any(part in ('build', '.dart_tool') for part in path.parts)}
    records = []

    def run(label, command):
        start = time.monotonic()
        with (output / (label + '.stdout')).open('w') as stdout, \
                (output / (label + '.stderr')).open('w') as stderr:
            result = subprocess.run(command, cwd=engine, stdout=stdout, stderr=stderr)
        record = {'label': label, 'command': command, 'exit_code': result.returncode,
                  'seconds': round(time.monotonic() - start, 3)}
        records.append(record)
        print(json.dumps(record), flush=True)
        (output / 'commands.json').write_text(json.dumps(records, indent=2) + '\n')
        if result.returncode:
            raise SystemExit(f'{label} failed; inspect {output}')

    run('dependencies', [args.dart, 'pub', 'get'])
    run('analysis', [args.dart, 'analyze', '--fatal-infos', 'lib', 'tool/macros',
                    'test/office_macro_word_page_setup_test.dart',
                    'test/office_vba_word_page_setup_test.dart',
                    'test/office_vba_word_page_setup_integration_test.dart'])
    tests = sorted({str(path.relative_to(engine))
                    for pattern in ('office_vba*_test.dart', 'office_macro*_test.dart')
                    for path in (engine / 'test').glob(pattern)})
    tests.extend('test/' + name for name in (
        'office_steps_test.dart', 'word_section_clone_fidelity_test.dart',
        'word_header_picture_identity_test.dart', 'word_structure_steps_test.dart',
        'fidelity_waves_test.dart'))
    run('regression', [args.dart, 'test', *tests, '--reporter', 'json', '--concurrency', '4'])
    source = (engine / 'example/macros/word_page_setup.bas').read_bytes()
    define = '-DWORD_PAGE_SETUP_BAS_BASE64=' + base64.b64encode(source).decode()
    smoke = 'tool/macros/web_vba_word_page_setup_smoke.dart'
    run('vm', [args.dart, define, smoke])
    compiled = output / 'page-setup.js'
    run('compile-js', [args.dart, 'compile', 'js', '-O1', define, smoke, '-o', str(compiled)])
    run('js', [args.node, '-e', 'globalThis.self=globalThis; require(process.argv[1]);',
               str(compiled)])
    vm = (output / 'vm.stdout').read_bytes()
    js = (output / 'js.stdout').read_bytes()
    if vm != js:
        raise SystemExit('VM and JavaScript receipts differ')
    events = [json.loads(line) for line in (output / 'regression.stdout').read_text().splitlines()
              if line.startswith('{')]
    cases = [event for event in events if event.get('type') == 'testDone' and
             not event.get('hidden')]
    changed = [path for path, digest in inputs.items()
               if hashlib.sha256((repository / path).read_bytes()).hexdigest() != digest]
    receipt = {'commands': records, 'test_files': tests,
               'passed': sum(event.get('result') == 'success' and not event.get('skipped')
                             for event in cases),
               'skipped': sum(bool(event.get('skipped')) for event in cases),
               'source_inputs_sha256': inputs, 'source_changed_during_run': changed,
               'actual_bas_sha256': hashlib.sha256(source).hexdigest(),
               'vm_js_byte_identical': True, 'portable_receipt': json.loads(vm)}
    (output / 'qualification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if changed:
        raise SystemExit('Source checkout changed during qualification')
    print(f'Acceptance passed; receipts and raw logs: {output}')


if __name__ == '__main__':
    main()
