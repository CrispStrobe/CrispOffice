#!/usr/bin/env python3
"""Bind a sequential native acceptance run and web compile to current sources."""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

from build_binding import FIXTURE_FILES, SOURCE_HELPER_FILES, binding_metadata
from workspace_binding import snapshot_sources

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True,
                    help='Task root containing the checkout, zotero-validation and zotero-toolchain.')
parser.add_argument('--output', type=Path,
                    help='New evidence directory; an existing receipt is never overwritten.')
parser.add_argument('--browser-build-output', type=Path)
args = parser.parse_args()
task = args.root.resolve()
repo = task / 'quds_office_suite'
workspace = task / 'zotero-validation'
toolchain = task / 'zotero-toolchain'
fixture = Path(__file__).resolve().parent
output = (args.output or task / 'thesaurus-final-validation').resolve()
if (output / 'receipt.json').exists():
    parser.error('The output already contains a receipt; choose an unused --output directory.')
output.mkdir(parents=True, exist_ok=True)
compiled = (args.browser_build_output or output / 'browser-build').resolve()
if compiled.exists() and any(compiled.iterdir()):
    parser.error('The browser build output is not empty; choose an unused directory.')
logs = output / 'logs'
logs.mkdir(exist_ok=True)
env = os.environ.copy()
env['QUDS_THESAURUS_NATIVE_REPORT'] = str(output / 'native-pack-report.json')
env['QUDS_THESAURUS_VISUAL_OUTPUT'] = str(output / 'visuals')
sdk = toolchain / 'flutter-sdk'
flutter = str(sdk / 'bin/flutter')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def snapshot():
    result = snapshot_sources(repo, workspace)
    for name in FIXTURE_FILES:
        result['__fixture__/' + name] = {'sha256': sha(fixture / name)}
    for name in SOURCE_HELPER_FILES:
        result['__helper__/' + name] = {'sha256': sha(repo / name)}
    return result

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

receipt = {'started_at_utc': datetime.now(timezone.utc).isoformat(),
           'base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
           'runs': [], 'status': 'running'}
def write():
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

def run(name, command, cwd):
    print('START ' + name, flush=True)
    begin = time.monotonic()
    stdout = logs / (name + '.stdout')
    stderr = logs / (name + '.stderr')
    with stdout.open('wb') as out, stderr.open('wb') as err:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=out, stderr=err, timeout=600)
    record = {'name': name, 'command': command, 'cwd': str(cwd),
              'exit_code': result.returncode, 'seconds': time.monotonic() - begin,
              'stdout': str(stdout.relative_to(output)), 'stderr': str(stderr.relative_to(output)),
              'stdout_sha256': sha(stdout), 'stderr_sha256': sha(stderr)}
    receipt['runs'].append(record)
    write()
    print('END ' + name + ' ' + json.dumps({'exit_code': result.returncode, 'seconds': record['seconds']}), flush=True)
    return result.returncode

try:
    write()
    before = snapshot()
    receipt['input_digest'] = digest(before)
    receipt['workspace_binding'] = before['__workspace_binding__']
    with gzip.open(output / 'source-inputs.json.gz', 'wt') as stream:
        json.dump(before, stream, indent=2, sort_keys=True)
    write()
    selected_tests = ['test/word_thesaurus_dialog_test.dart', 'test/word_thesaurus_controller_test.dart',
                    'test/word_proofing_correction_test.dart', 'test/word_proofing_capture_cache_test.dart',
                    'test/word_proofing_context_test.dart', 'test/word_review_pane_test.dart',
                    'test/word_thesaurus_review_integration_test.dart',
                    'test/word_keyboard_review_test.dart',
                    'test/word_keyboard_review_identity_test.dart',
                    'test/word_keyboard_context_geometry_test.dart',
                    'test/word_text_proofing_controls_test.dart',
                    'test/word_text_proofing_pane_test.dart',
                    str(fixture / 'native_pack_test.dart'), str(fixture / 'native_visual_test.dart')]
    test_command = [flutter, 'test', '--no-pub', '--concurrency=1', '--reporter', 'json',
                    *selected_tests]
    test_exit = run('native-acceptance', test_command, workspace / 'packages/quds_office_editor')
    spec = importlib.util.spec_from_file_location('event_audit', repo / 'docs/validation/zotero-citation-workflow-20261118/editor/run_editor_zotero.py')
    audit_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit_module)
    audit = audit_module.audit_events(logs / 'native-acceptance.stdout')
    (output / 'native-test-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
    receipt['test_audit'] = {k: audit[k] for k in ['passed', 'failed', 'skipped', 'suite_count', 'every_started_test_finished_once', 'layout_or_tap_diagnostics']}
    test_cwd = workspace / 'packages/quds_office_editor'
    expected_suites = {str((test_cwd / path).resolve()) for path in selected_tests}
    actual_suites = {str((test_cwd / suite['path']).resolve()) for suite in audit['suites']}
    guards = {
        'exit_success': test_exit == 0,
        'all_selected_suites_executed': actual_suites == expected_suites
                                       and len(audit['suites']) == len(selected_tests),
        'nonempty_cases': audit['passed'] > 0,
        'no_failed_or_skipped_cases': audit['failed'] == 0 and audit['skipped'] == 0,
        'every_started_test_finished_once': audit['every_started_test_finished_once'],
        'final_event_success': len(audit['final_events']) == 1
                               and audit['final_events'][0].get('success') is True,
        'clean_event_stream': not any(audit[key] for key in (
            'error_events', 'parse_errors', 'excluded_failures', 'layout_or_tap_diagnostics')),
    }
    receipt['native_acceptance_guards'] = guards
    if not all(guards.values()):
        raise RuntimeError('Native acceptance audit failed: ' +
                           ', '.join(key for key, passed in guards.items() if not passed))
    after_tests = snapshot()
    receipt['source_unchanged_during_tests'] = after_tests == before
    if after_tests != before: raise RuntimeError('source changed during native test run')
    build_command = [flutter, 'build', 'web', '--no-pub', '--release', '--csp',
                     '--no-web-resources-cdn', '--no-wasm-dry-run',
                     '--pwa-strategy=none',
                     '--target=' + str(fixture / 'lib/main.dart'),
                     '--output=' + str(compiled)]
    build_exit = run('browser-build', build_command, workspace / 'packages/quds_office_editor/example')
    if build_exit != 0: raise RuntimeError('browser compile failed')
    after = snapshot()
    receipt['source_unchanged_during_build'] = after == before
    if after != before: raise RuntimeError('source changed during browser compile')
    inventory = [{'path': p.relative_to(compiled).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)}
                 for p in sorted(compiled.rglob('*')) if p.is_file()]
    with gzip.open(output / 'browser-build-files.json.gz', 'wt') as stream:
        json.dump(inventory, stream, indent=2)
    receipt['compiled_browser_files'] = len(inventory)
    receipt['compiled_browser_bytes'] = sum(p['bytes'] for p in inventory)
    receipt['browser_build_binding'] = binding_metadata(output)
    receipt['browser_execution'] = {
        'status': 'not_run',
        'offline_gate': 'pending; this runner compiles but does not launch a browser',
        'install_command': ['python', str(fixture / 'install_offline.py'), str(compiled),
                            '--compile-receipt', str(output / 'receipt.json')],
        'acceptance_command': ['python', str(fixture / 'run_browser.py'), str(compiled),
                               '--compile-receipt', str(output / 'receipt.json'),
                               '--output', str(output / 'browser-acceptance')],
    }
    receipt['status'] = 'native_passed_web_compiled_browser_not_run'
except BaseException as error:
    receipt['status'] = 'failed'
    receipt['error'] = repr(error)
    raise
finally:
    receipt['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    write()
    print(json.dumps({'status': receipt['status'], 'error': receipt.get('error')}), flush=True)
