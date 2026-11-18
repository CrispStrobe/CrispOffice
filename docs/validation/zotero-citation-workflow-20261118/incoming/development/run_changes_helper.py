#!/usr/bin/env python3
"""Focused helper development receipt, excluded from full-cohort acceptance."""
import argparse
import fcntl
import gzip
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
TOOLCHAIN = REPO.parent / 'zotero-toolchain'
WORKSPACE = REPO.parent / 'zotero-validation'
SDK = TOOLCHAIN / 'flutter-sdk'
SOURCE_COMMIT = '00ac2edf606359cea003b4ebb3a5f3aaac7b67cf'
TARGET = 'packages/quds_office_editor/test/word_live_review_changes_test.dart'
spec = importlib.util.spec_from_file_location('incoming_runner', HERE.parent / 'run_incoming_editor.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        raise RuntimeError('Existing development evidence is never overwritten.')
    baseline = json.loads(gzip.decompress((HERE.parent / 'attempt-2/inputs.json.gz').read_bytes()))['before']
    config_path = WORKSPACE / '.dart_tool/package_config.json'
    config = {p['name']: p for p in json.loads(config_path.read_text())['packages']}
    roots = {name: Path(unquote(urlparse(urljoin(config_path.as_uri(), config[name]['rootUri'])).path))
             for name in baseline['dependencies']}

    def snapshot():
        result = {area: {p: runner.record(root / p) for p in baseline[area]}
                  for area, root in [('source', REPO), ('workspace', WORKSPACE), ('runtime', SDK)]}
        dependencies = {}
        for name, root in sorted(roots.items()):
            files = {root / 'pubspec.yaml'}
            for sub in ['lib', 'bin']:
                files.update(p for p in (root / sub).rglob('*') if p.is_file())
            records = {str(p.relative_to(root)): runner.record(p) for p in sorted(files)}
            dependencies[name] = dict(file_count=len(records), inventory_sha256=runner.digest(records))
        result['dependencies'] = dependencies
        return result

    env = dict(os.environ, FLUTTER_ROOT=str(SDK), PUB_CACHE=str(TOOLCHAIN / 'pub-cache'),
               TMPDIR=str(TOOLCHAIN / 'tmp'), XDG_CONFIG_HOME=str(TOOLCHAIN / 'config'),
               XDG_CACHE_HOME=str(TOOLCHAIN / 'cache'), XDG_DATA_HOME=str(TOOLCHAIN / 'data'),
               CI='true', DART_SUPPRESS_ANALYTICS='true', DASH__SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true')
    env['PATH'] = str(SDK / 'bin') + ':' + env['PATH']
    env.pop('QUDS_REVIEW_SCREENSHOT_DIR', None)
    env['QUDS_REVIEW_ICON_FONT'] = str(SDK / 'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
    with (TOOLCHAIN / 'flutter-cli.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        before = snapshot()
        tree = subprocess.check_output(['git', 'ls-tree', '-r', SOURCE_COMMIT], cwd=REPO, text=True)
        blobs = {line.split('\t', 1)[1]: line.split('\t', 1)[0].split()[2] for line in tree.splitlines()}
        overrides = [p for p, r in before['source'].items() if blobs.get(p) != r['git_blob_sha1']]
        if overrides != [TARGET]:
            raise RuntimeError(f'Only the authorized helper test may differ from the frozen base: {overrides}')
        out.mkdir(parents=True)
        (out / 'source-diff.patch').write_bytes(subprocess.check_output(['git', 'diff', SOURCE_COMMIT, '--', TARGET], cwd=REPO))
        started = runner.utc()
        checks = []
        dart = str(SDK / 'bin/cache/dart-sdk/bin/dart')
        for name, command in [('format', [dart, 'format', '--output=none', '--set-exit-if-changed', TARGET]),
                              ('analyze', [dart, 'analyze', '--fatal-infos', '--fatal-warnings', TARGET])]:
            result = subprocess.run(command, cwd=WORKSPACE, env=env, capture_output=True, text=True, timeout=240)
            checks.append(dict(name=name, command=command, cwd=str(WORKSPACE), exit_code=result.returncode,
                               stdout=result.stdout, stderr=result.stderr))
        command = [str(SDK / 'bin/flutter'), 'test', '--no-pub', '--machine', '--concurrency', '1', 'test/' + Path(TARGET).name]
        cwd = WORKSPACE / 'packages/quds_office_editor'
        elapsed = time.monotonic()
        result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=240)
        elapsed = time.monotonic() - elapsed
        after = snapshot()
        fcntl.flock(lock, fcntl.LOCK_UN)
    raw = out / 'events.jsonl.gz'
    raw.write_bytes(gzip.compress(result.stdout, mtime=0))
    audit = runner.audit_events(raw)
    guards = {area + '_unchanged': before[area] == after[area] for area in before}
    guards['only_authorized_test_differs_from_frozen_base'] = overrides == [TARGET]
    guards['every_started_test_finished_once'] = audit['every_started_test_finished_once']
    guards['expected_suite_executed'] = audit['suite_count'] == 1 and Path(audit['suites'][0]['path']).name == Path(TARGET).name
    guards['final_event_success'] = len(audit['final_events']) == 1 and audit['final_events'][0].get('success') is True
    passed = (result.returncode == 0 and all(c['exit_code'] == 0 for c in checks) and all(guards.values())
              and audit['passed'] > 0 and not audit['failed'] and not audit['skipped']
              and not any(audit[k] for k in ['error_events', 'parse_errors', 'excluded_failures', 'layout_or_tap_diagnostics']))
    inputs = dict(before=before, before_sha256={k: runner.digest(v) for k, v in before.items()},
                  after_sha256={k: runner.digest(v) for k, v in after.items()},
                  source_base_commit=SOURCE_COMMIT, authorized_source_overrides=overrides)
    (out / 'inputs.json.gz').write_bytes(gzip.compress((json.dumps(inputs, sort_keys=True) + '\n').encode(), mtime=0))
    runner.write_json(out / 'summary.json', dict(status='passed' if passed else 'failed', started_at_utc=started,
                      finished_at_utc=runner.utc(), command=command, cwd=str(cwd), actual_process_exit=result.returncode,
                      elapsed_seconds=elapsed, checks=checks, guards=guards, tests=audit,
                      stderr=result.stderr.decode(errors='replace'), source_base_commit=SOURCE_COMMIT,
                      authorized_source_overrides=overrides, runner_sha256=runner.record(Path(__file__))['sha256'],
                      auditor_sha256=runner.record(HERE.parent / 'run_incoming_editor.py')['sha256'],
                      artifacts={p.name: runner.record(p) for p in sorted(out.iterdir())},
                      scope='One helper-development suite on explicitly uncommitted test bytes. This run is excluded from acceptance and all final passing totals.'))
    print(json.dumps(dict(status='passed' if passed else 'failed', exit_code=result.returncode,
                         passed=audit['passed'], failed=audit['failed'], skipped=audit['skipped'], guards=guards)), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
