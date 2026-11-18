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

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
args = parser.parse_args()
task = args.root.resolve()
repo = task / 'quds_office_suite'
workspace = task / 'zotero-validation'
toolchain = task / 'zotero-toolchain'
fixture = Path(__file__).resolve().parent
output = task / 'thesaurus-final-validation'
output.mkdir(exist_ok=True)
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
    files = {repo / 'pubspec.yaml', repo / '.fvmrc'}
    for package in (repo / 'packages').iterdir():
        if not package.is_dir(): continue
        if (package / 'pubspec.yaml').is_file(): files.add(package / 'pubspec.yaml')
        for name in ['lib', 'test', 'assets']:
            directory = package / name
            if directory.exists(): files.update(p for p in directory.rglob('*') if p.is_file())
    result = {str(p.relative_to(repo)): {'sha256': sha(p), 'bytes': p.stat().st_size}
              for p in sorted(files)}
    result['__workspace_lock__'] = {'sha256': sha(workspace / 'pubspec.lock')}
    result['__workspace_package_config__'] = {'sha256': sha(workspace / '.dart_tool/package_config.json')}
    for name in ['lib/main.dart', 'native_pack_test.dart', 'native_visual_test.dart']:
        result['__fixture__/' + name] = {'sha256': sha(fixture / name)}
    return result

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

receipt = {'started_at_utc': datetime.now(timezone.utc).isoformat(),
           'base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
           'runs': [], 'status': 'running'}
before = snapshot()
receipt['input_digest'] = digest(before)
with gzip.open(output / 'source-inputs.json.gz', 'wt') as stream:
    json.dump(before, stream, indent=2, sort_keys=True)

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
    test_command = [flutter, 'test', '--no-pub', '--concurrency=1', '--reporter', 'json',
                    'test/word_thesaurus_dialog_test.dart', 'test/word_thesaurus_controller_test.dart',
                    'test/word_proofing_correction_test.dart', 'test/word_proofing_capture_cache_test.dart',
                    'test/word_proofing_context_test.dart', 'test/word_review_pane_test.dart',
                    str(fixture / 'native_pack_test.dart'), str(fixture / 'native_visual_test.dart')]
    test_exit = run('native-acceptance', test_command, workspace / 'packages/quds_office_editor')
    spec = importlib.util.spec_from_file_location('event_audit', repo / 'docs/validation/zotero-citation-workflow-20261118/editor/run_editor_zotero.py')
    audit_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit_module)
    audit = audit_module.audit_events(logs / 'native-acceptance.stdout')
    (output / 'native-test-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
    receipt['test_audit'] = {k: audit[k] for k in ['passed', 'failed', 'skipped', 'suite_count', 'every_started_test_finished_once', 'layout_or_tap_diagnostics']}
    if test_exit != 0: raise RuntimeError('native acceptance failed')
    after_tests = snapshot()
    receipt['source_unchanged_during_tests'] = after_tests == before
    if after_tests != before: raise RuntimeError('source changed during native test run')
    build_command = [flutter, 'build', 'web', '--no-pub', '--release', '--csp',
                     '--no-web-resources-cdn', '--no-wasm-dry-run',
                     '--target=' + str(fixture / 'lib/main.dart'),
                     '--output=' + str(task / 'thesaurus-browser-build-final')]
    build_exit = run('browser-build', build_command, workspace / 'packages/quds_office_editor/example')
    if build_exit != 0: raise RuntimeError('browser compile failed')
    after = snapshot()
    receipt['source_unchanged_during_build'] = after == before
    if after != before: raise RuntimeError('source changed during browser compile')
    compiled = task / 'thesaurus-browser-build-final'
    inventory = [{'path': str(p.relative_to(compiled)), 'bytes': p.stat().st_size, 'sha256': sha(p)}
                 for p in sorted(compiled.rglob('*')) if p.is_file()]
    with gzip.open(output / 'browser-build-files.json.gz', 'wt') as stream:
        json.dump(inventory, stream, indent=2)
    receipt['compiled_browser_files'] = len(inventory)
    receipt['compiled_browser_bytes'] = sum(p['bytes'] for p in inventory)
    receipt['browser_execution'] = {'status': 'blocked_by_environment',
                                   'local_chromium': 'Sandbox denied Unix socket creation before application startup.',
                                   'supported_cloud_browser': 'Could not connect to the local origin (ERR_CONNECTION_REFUSED).',
                                   'offline_gate': 'pending; compilation is not actual-browser acceptance'}
    receipt['status'] = 'native_passed_web_compiled_browser_execution_blocked'
except BaseException as error:
    receipt['status'] = 'failed'
    receipt['error'] = repr(error)
    raise
finally:
    receipt['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    write()
    print(json.dumps({'status': receipt['status'], 'error': receipt.get('error')}), flush=True)
