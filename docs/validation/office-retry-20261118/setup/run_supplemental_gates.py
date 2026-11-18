#!/usr/bin/env python3
"""Run unchanged portable/example/timezone gates with bounded outer logging."""
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
REPO = ROOT / 'quds_office_suite'
WORK = ROOT / 'flutter-qualification/workspace'
SDK = (ROOT / 'toolchains/flutter').resolve()
SOURCE = '9d060658ee6be8ec97d73f56b9aec10d346b7952'
RUNS = ROOT / 'flutter-qualification/runs'
assert json.loads((RUNS / 'canonical-9d060658/receipt.json').read_text())['all_passed']
spec = importlib.util.spec_from_file_location('pack', REPO / 'docs/validation/office-reconciled-20261117/resume/package_checkpoint.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)
env = dict(os.environ, FLUTTER_ROOT=str(SDK), PUB_CACHE=str(ROOT / 'toolchains/pub-cache'),
           TMPDIR=str(WORK / 'tmp'), XDG_CONFIG_HOME=str(WORK / 'config'), CI='true',
           DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true',
           DASH__SUPPRESS_ANALYTICS='true', PYTHONDONTWRITEBYTECODE='1',
           OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1', MKL_NUM_THREADS='1')
env['PATH'] = str(SDK / 'bin/cache/dart-sdk/bin') + os.pathsep + env['PATH']
GATES = [
    ('portable', 'docs/validation/gector-office-resume-20261117/run_portable.py'),
    ('editor-example', 'docs/validation/gector-office-resume-20261117/run_editor_example.py'),
    ('calendar-timezones', 'docs/validation/office-local-20261118/setup/run_calendar_timezones.py'),
]
for name, script in GATES:
    folder = RUNS / (name + '-9d060658')
    folder.mkdir(exist_ok=False)
    command = [sys.executable, str(REPO / script), '--repo', str(REPO),
               '--source-commit', SOURCE, '--flutter-root', str(SDK),
               '--workspace', str(WORK), '--output', str(folder / 'result')]
    row = {'gate': name, 'source_commit': SOURCE, 'argv': command,
           'started_utc': datetime.now(timezone.utc).isoformat(), 'timeout_seconds': 960,
           'passed': False, 'github_actions_queried_or_awaited': False}
    (folder / 'orchestration.json').write_text(json.dumps(row, indent=2) + '\n')
    print(json.dumps({'event': 'gate-start', 'gate': name}), flush=True)
    began = time.monotonic()
    with (folder / 'outer.stdout').open('wb') as stdout, (folder / 'outer.stderr').open('wb') as stderr:
        process = subprocess.Popen(command, cwd=REPO, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            code = process.wait(timeout=960)
        except subprocess.TimeoutExpired:
            row['timeout'] = True
            code = 124
        finally:
            # Stop any descendants left after a helper timeout or early failure.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    receipt_path = folder / 'result/receipt.json'
    child = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
    row.update(exit_code=code, duration_seconds=time.monotonic() - began,
               finished_utc=datetime.now(timezone.utc).isoformat(),
               child_receipt_present=child is not None,
               passed=code == 0 and child is not None and child.get('passed') is True)
    (folder / 'orchestration.json').write_text(json.dumps(row, indent=2) + '\n')
    files = {str(path.relative_to(folder)): path for path in folder.rglob('*') if path.is_file() and not path.is_symlink() and '__pycache__' not in path.parts}
    files['run_supplemental_gates.py'] = Path(__file__).resolve()
    archive = folder.with_suffix('.tar.xz')
    pack.pack(archive, files, ('Passed ' if row['passed'] else 'Failed/incomplete ') + name + ' gate on frozen ' + SOURCE)
    print(json.dumps({'event': 'gate-finish', 'gate': name, 'passed': row['passed'], 'archive': str(archive)}), flush=True)
    if not row['passed']:
        raise SystemExit(1)
