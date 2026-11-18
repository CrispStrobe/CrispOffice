from pathlib import Path
from contextlib import redirect_stdout, redirect_stderr
from datetime import datetime, timezone
import ast
import hashlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
from unittest.mock import patch

repo = Path('/workspace/scratch/ab53c04e2d5e/quds_office_suite')
script = repo / 'tools/mail/check_reader.py'
evidence = repo / 'docs/validation/mail-reader-20261118/checks'
scratch = Path('/workspace/scratch/ab53c04e2d5e/runner-receipt-checks')
scratch.mkdir(exist_ok=True)
log = io.StringIO()
checks = []
ast.parse(script.read_text())
checks.append({'name': 'python-syntax', 'status': 'PASS'})
help_result = subprocess.run([sys.executable, str(script), '--help'], cwd=repo, capture_output=True, text=True)
assert help_result.returncode == 0 and '--web-build' in help_result.stdout
checks.append({'name': 'cli-help', 'status': 'PASS', 'exit_code': help_result.returncode})
log.write('$ python3 tools/mail/check_reader.py --help\n' + help_result.stdout)
spec = importlib.util.spec_from_file_location('mail_runner', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
expected_hashes = {'tools/mail/check_reader.py', 'third_party/enough_mail/pubspec.yaml', 'third_party/enough_mail/analysis_options.yaml', 'third_party/enough_mail/LICENSE', 'third_party/enough_mail/UPSTREAM.json', 'third_party/enough_mail/DEPENDENCIES.json', 'third_party/enough_mail/PORTABLE_CLOSURE.json', 'third_party/enough_mail/QUDS_PATCHES.md'}
assert expected_hashes <= module.source_hashes(repo).keys()
checks.append({'name': 'required-source-hashes', 'status': 'PASS', 'included_paths': sorted(expected_hashes)})

fake_sdk = scratch / 'sdk'
(fake_sdk / 'bin/cache/dart-sdk/bin').mkdir(parents=True, exist_ok=True)
(fake_sdk / 'bin/cache/dart-sdk/bin/dart').touch()
(fake_sdk / 'bin/cache/flutter_tools.snapshot').touch()
original_write = module.write_receipt

for case in ('missing-sdk', 'spawn-oserror', 'keyboard-interrupt', 'failed-compile-stale-js'):
    output = scratch / case
    output.mkdir(exist_ok=True)
    receipt_path = output / 'receipt.json'
    receipt_path.write_text(json.dumps({'status': 'PASS', 'run_id': 'stale-run', 'checks': [{'name': 'stale-check'}]}))
    (output / 'portable.js').write_text('throw new Error("old output must not run");\n')
    snapshots = []
    observed_commands = []
    def capture_write(path, receipt):
        original_write(path, receipt)
        snapshots.append(json.loads(path.read_text()))
    def fake_run(command, **kwargs):
        state = json.loads(receipt_path.read_text())
        assert state['status'] == 'RUNNING'
        assert state['active_check'] is not None
        assert state['checks'][-1]['status'] == 'RUNNING'
        assert state['run_id'] != 'stale-run'
        observed_commands.append(command)
        if case == 'spawn-oserror':
            raise OSError('synthetic spawn failure for receipt control-flow validation')
        if case == 'keyboard-interrupt':
            raise KeyboardInterrupt()
        assert command[0] != '/synthetic/node', 'stale JavaScript output was executed'
        kwargs['stdout'].write(b'synthetic output for runner control-flow validation\n')
        return subprocess.CompletedProcess(command, 7 if 'compile' in command else 0)
    sdk = scratch / 'nonexistent-sdk' if case == 'missing-sdk' else fake_sdk
    argv = [str(script), '--flutter-sdk', str(sdk), '--output', str(output), '--web-build']
    with patch.object(sys, 'argv', argv), patch.object(module.shutil, 'which', return_value='/synthetic/node'), patch.object(module.subprocess, 'run', side_effect=fake_run), patch.object(module, 'write_receipt', side_effect=capture_write), redirect_stdout(log), redirect_stderr(log):
        exit_code = module.main()
    state = json.loads(receipt_path.read_text())
    assert snapshots[0]['status'] == 'RUNNING' and snapshots[0]['checks'] == []
    assert snapshots[0]['run_id'] != 'stale-run'
    assert snapshots[-1]['status'] == state['status']
    assert state['active_check'] is None and state['finished_utc']
    assert not list(output.glob('.receipt-*.tmp'))
    assert exit_code == (130 if case == 'keyboard-interrupt' else 1)
    assert state['status'] == ('INTERRUPTED' if case == 'keyboard-interrupt' else 'FAIL')
    if case == 'spawn-oserror':
        assert state['checks'][0]['status'] == 'ERROR'
    if case == 'keyboard-interrupt':
        assert state['checks'][0]['status'] == 'INTERRUPTED'
    if case == 'failed-compile-stale-js':
        projection = next(item for item in state['checks'] if item['name'] == 'mime-js-projection')
        assert projection['status'] == 'SKIPPED'
        assert state['checks'][-1]['status'] == 'FAIL'
        assert '--no-web-resources-cdn' in next(command for command in observed_commands if 'web' in command)
        assert state['source_unchanged'] is True
    checks.append({'name': case, 'status': 'PASS', 'observed_runner_exit_code': exit_code, 'observed_receipt_status': state['status'], 'atomic_checkpoint_count': len(snapshots), 'subprocess_calls': len(observed_commands)})
    log.write(f'{case}: receipt assertions PASS ({len(snapshots)} atomic checkpoints)\n')

log.write('All synthetic control-flow checks passed. No real Dart, Flutter, Node, package tests or network calls were performed by the synthetic cases.\n')
log_path = evidence / 'late-engine-editor-runner-checks.txt'
log_path.write_text(log.getvalue())
receipt = {'status': 'PASS', 'recorded_utc': datetime.now(timezone.utc).isoformat(), 'kind': 'runner syntax/CLI and synthetic failure-control-flow validation; not Mail qualification', 'runner_source_sha256': hashlib.sha256(script.read_bytes()).hexdigest(), 'validation_script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'checks': checks, 'raw_log': log_path.name, 'raw_log_sha256': hashlib.sha256(log_path.read_bytes()).hexdigest()}
(evidence / 'late-engine-editor-runner-checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
