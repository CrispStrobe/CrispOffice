#!/usr/bin/env python3
"""Validate the full editor Zotero cohort and five changed Dart targets locally.

Evidence is deliberately compact: one raw machine-event gzip, one input
inventory gzip, and a summary containing commands, exit codes and check logs.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse

import yaml

PACKAGE = Path('packages/quds_office_editor')
TARGETS = [str(PACKAGE / p) for p in [
    'lib/src/embed/word_zotero_library.dart',
    'lib/src/embed/word_zotero_dialog.dart',
    'lib/src/embed/word_zotero_stored_details.dart',
    'test/word_zotero_stored_details_test.dart',
    'test/word_zotero_stored_details_dialog_test.dart',
]]
NEW_SUITES = {Path(p).name for p in TARGETS[-2:]}


def utc():
    return datetime.now(timezone.utc).isoformat()


def record(path):
    size = path.stat().st_size
    sha = hashlib.sha256()
    blob = hashlib.sha1(f'blob {size}\0'.encode())
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(chunk)
            blob.update(chunk)
    return dict(bytes=size, sha256=sha.hexdigest(), git_blob_sha1=blob.hexdigest())


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')


def audit_events(path):
    """Count completed real cases; retain failures in excluded lifecycle events."""
    events, parse_errors, envelope_count = [], [], 0
    opener = gzip.open if path.suffix == '.gz' else open
    with opener(path, 'rt', encoding='utf-8') as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                parse_errors.append(dict(line=number, text=line.rstrip()))
                continue
            if isinstance(value, dict) and isinstance(value.get('type'), str):
                events.append(value)
            elif isinstance(value, list) and all(isinstance(v, dict) and 'event' in v for v in value):
                envelope_count += 1  # Flutter process notifications, not cases.
            else:
                parse_errors.append(dict(line=number, value=value))
    start_events = [e['test'] for e in events if e['type'] == 'testStart']
    starts = {e['id']: e for e in start_events}
    dones = [e for e in events if e['type'] == 'testDone']
    suites = [e['suite'] for e in events if e['type'] == 'suite']
    finals = [e for e in events if e['type'] == 'done']
    errors = [e for e in events if e['type'] == 'error']
    excluded, real, excluded_reasons = [], [], Counter()
    for done in dones:
        test = starts.get(done['testID'], {})
        name = test.get('name', '')
        reason = ('hidden_lifecycle' if done.get('hidden') else
                  'loading' if name.startswith('loading ') else
                  'group_lifecycle' if name.endswith(('(setUpAll)', '(tearDownAll)')) else None)
        if reason:
            excluded.append(done)
            excluded_reasons[reason] += 1
        else:
            real.append(done)
    skipped = [e for e in real if e.get('skipped') or starts.get(e['testID'], {}).get('metadata', {}).get('skip')]
    skipped_ids = {e['testID'] for e in skipped}
    passed = [e for e in real if e['result'] == 'success' and e['testID'] not in skipped_ids]
    failed = [e for e in real if e['result'] != 'success' and e['testID'] not in skipped_ids]
    counts = Counter(e['testID'] for e in dones)
    every_finished = (len(start_events) == len(starts) and set(starts) == set(counts)
                      and all(n == 1 for n in counts.values()))
    per_suite = []
    for suite in suites:
        case_ids = {i for i, t in starts.items() if t.get('suiteID') == suite['id']}
        per_suite.append(dict(path=suite['path'],
                              passed=sum(e['testID'] in case_ids for e in passed),
                              skipped=sum(e['testID'] in case_ids for e in skipped),
                              failed=sum(e['testID'] in case_ids for e in failed)))
    diagnostics = [e for e in events if e['type'] == 'print' and re.search(
        r'A Render\w+ overflowed|would not hit test on the specified widget|does not receive pointer events',
        e.get('message', ''))]
    return dict(passed=len(passed), failed=len(failed), skipped=len(skipped),
                substantive_cases=len(real), suite_count=len(suites), suites=per_suite,
                excluded_pseudo_cases=len(excluded), excluded_reasons=dict(excluded_reasons),
                excluded_failures=[e for e in excluded if e['result'] != 'success' or e.get('skipped')],
                test_start_events=len(start_events), test_done_events=len(dones),
                every_started_test_finished_once=every_finished, final_events=finals,
                error_events=errors, parse_errors=parse_errors, layout_or_tap_diagnostics=diagnostics,
                flutter_envelopes=envelope_count)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    default_toolchain = Path(__file__).resolve().parent
    parser.add_argument('--repo', type=Path, default=default_toolchain.parent / 'quds_office_suite')
    parser.add_argument('--workspace', type=Path, default=default_toolchain.parent / 'zotero-validation')
    parser.add_argument('--toolchain', type=Path, default=default_toolchain)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--concurrency', type=int, default=4)
    parser.add_argument('--timeout', type=int, default=900)
    args = parser.parse_args()
    repo, workspace, toolchain, out = (p.resolve() for p in (args.repo, args.workspace, args.toolchain, args.output))
    if out.exists():
        raise RuntimeError('Choose a fresh output directory; existing evidence is never overwritten.')
    selected = sorted((repo / PACKAGE / 'test').glob('word_zotero*_test.dart'))
    assert NEW_SUITES <= {p.name for p in selected}, 'Both new suites must be present.'
    assert all((repo / target).is_file() for target in TARGETS)
    sdk = toolchain / 'flutter-sdk'
    dart, flutter = sdk / 'bin/cache/dart-sdk/bin/dart', sdk / 'bin/flutter'
    config_path = workspace / '.dart_tool/package_config.json'
    graph_path = workspace / '.dart_tool/package_graph.json'
    config = {p['name']: p for p in json.loads(config_path.read_text())['packages']}
    graph = {p['name']: p for p in json.loads(graph_path.read_text())['packages']}
    reachable, queue = set(), ['quds_office_editor'] + graph['quds_office_editor']['devDependencies']
    while queue:
        name = queue.pop()
        if name not in reachable:
            reachable.add(name)
            queue.extend(graph[name].get('dependencies', []))
    roots = {name: Path(unquote(urlparse(urljoin(config_path.as_uri(), config[name]['rootUri'])).path)) for name in reachable}
    local = {name: repo / path.relative_to(workspace) for name, path in roots.items() if path.is_relative_to(workspace)}
    root_manifest = yaml.safe_load((repo / 'pubspec.yaml').read_text())
    manifests = ['pubspec.yaml'] + [p + '/pubspec.yaml' for p in root_manifest['workspace']]

    def source_files():
        paths = set(selected)
        for root in local.values():
            paths.update(p for p in (root / 'lib').rglob('*') if p.is_file())
            paths.add(root / 'pubspec.yaml')
            manifest = yaml.safe_load((root / 'pubspec.yaml').read_text())
            assets = list((manifest.get('flutter') or {}).get('assets', []))
            assets += [f['asset'] for family in (manifest.get('flutter') or {}).get('fonts', []) for f in family.get('fonts', [])]
            for asset in assets:
                path = root / (asset if isinstance(asset, str) else asset['path'])
                paths.update(p for p in path.rglob('*') if p.is_file()) if path.is_dir() else paths.add(path)
        # Retain relative test imports and all source fixture bytes used by Zotero suites.
        queue = list(selected)
        while queue:
            path = queue.pop()
            for uri in re.findall(r"^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]", path.read_text(), re.M):
                if ':' not in uri:
                    child = (path.parent / uri).resolve()
                    if child.is_relative_to(repo) and child.is_file() and child not in paths:
                        paths.add(child)
                        queue.append(child)
        for sub in ['packages/quds_office_engine/test/fixtures/zotero', str(PACKAGE / 'test/fixtures')]:
            paths.update(p for p in (repo / sub).rglob('*') if p.is_file())
        paths.update(repo / p for p in manifests)
        for root in [repo] + list(local.values()):
            if (root / 'analysis_options.yaml').is_file():
                paths.add(root / 'analysis_options.yaml')
        return {str(p.relative_to(repo)): record(p) for p in sorted(paths)}

    def workspace_inputs():
        paths = [workspace / p for p in manifests] + [workspace / 'pubspec.lock', config_path, graph_path]
        return {str(p.relative_to(workspace)): record(p) for p in sorted(paths)}

    def runtime_inputs():
        paths = ['bin/flutter', 'bin/cache/dart-sdk/bin/dart', 'bin/cache/dart-sdk/bin/dartaotruntime',
                 'bin/cache/dart-sdk/bin/snapshots/analysis_server_aot.dart.snapshot',
                 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
                 'bin/cache/artifacts/engine/linux-x64/flutter_tester', 'bin/cache/flutter_tools.snapshot',
                 'packages/flutter_tools/pubspec.yaml', 'packages/flutter_tools/pubspec.lock']
        return {p: record(sdk / p) for p in paths if (sdk / p).is_file()}

    def dependency_inputs():
        # Compact binding to the full reachable dependency source tree.
        result = {}
        for name, root in sorted(roots.items()):
            if name in local:
                continue
            files = {root / 'pubspec.yaml'}
            for sub in ['lib', 'bin']:
                files.update(p for p in (root / sub).rglob('*') if p.is_file())
            records = {str(p.relative_to(root)): record(p) for p in sorted(files)}
            result[name] = dict(file_count=len(records), inventory_sha256=digest(records))
        return result

    def head():
        return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()

    def snapshot():
        return dict(source=source_files(), workspace=workspace_inputs(), runtime=runtime_inputs(), dependencies=dependency_inputs())

    env = dict(os.environ, FLUTTER_ROOT=str(sdk), PUB_CACHE=str(toolchain / 'pub-cache'),
               TMPDIR=str(toolchain / 'tmp'), XDG_CONFIG_HOME=str(toolchain / 'config'),
               XDG_CACHE_HOME=str(toolchain / 'cache'), XDG_DATA_HOME=str(toolchain / 'data'),
               CI='true', DART_SUPPRESS_ANALYTICS='true', DASH__SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true')
    env['PATH'] = str(sdk / 'bin') + ':' + env['PATH']
    lock = (toolchain / 'flutter-cli.lock').open('a')
    print('Acquiring shared local validation lock', flush=True)
    fcntl.flock(lock, fcntl.LOCK_EX)
    out.mkdir(parents=True)
    started, initial_head = utc(), head()
    before = snapshot()
    tree = subprocess.check_output(['git', 'ls-tree', '-r', initial_head], cwd=repo, text=True)
    blobs = {line.split('\t', 1)[1]: line.split('\t', 1)[0].split()[2] for line in tree.splitlines()}
    source_matches_commit = all(blobs.get(p) == r['git_blob_sha1'] for p, r in before['source'].items())
    selected_paths = [str(p.relative_to(repo)) for p in selected]
    run = dict(status='running', started_at_utc=started, source_head_at_start=initial_head,
               selected_suites=selected_paths, strict_targets=TARGETS, runner_sha256=record(Path(__file__))['sha256'])
    write_json(out / 'summary.json', run)
    checks = []
    for label, command in [
        ('format', [str(dart), 'format', '--output=none', '--set-exit-if-changed', *TARGETS]),
        ('analyze', [str(dart), 'analyze', '--fatal-infos', '--fatal-warnings', *TARGETS]),
    ]:
        print('Running ' + label + ' on exactly five targets', flush=True)
        start = time.monotonic()
        process = subprocess.run(command, cwd=workspace, env=env, capture_output=True, text=True, timeout=240)
        checks.append(dict(name=label, command=command, cwd=str(workspace), exit_code=process.returncode,
                           elapsed_seconds=time.monotonic()-start, stdout=process.stdout, stderr=process.stderr))
    command = [str(flutter), 'test', '--no-pub', '--machine', '--concurrency', str(args.concurrency)] + ['test/' + p.name for p in selected]
    cwd = workspace / PACKAGE
    print(f'Running {len(selected)} full editor Zotero suites', flush=True)
    raw, stderr_path = out / 'events.jsonl', out / 'stderr.log'
    start, timed_out = time.monotonic(), False
    with raw.open('wb') as stdout, stderr_path.open('wb') as stderr:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            exit_code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                exit_code = process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                exit_code = process.wait()
    elapsed = time.monotonic()-start
    after, final_head = snapshot(), head()
    fcntl.flock(lock, fcntl.LOCK_UN)
    lock.close()
    audit = audit_events(raw)
    actual_suites = {str((Path(s['path']) if Path(s['path']).is_absolute() else cwd / s['path']).resolve()) for s in audit['suites']}
    expected_suites = {str(p.resolve()) for p in selected}
    changes = {area: [p for p in sorted(before[area].keys() | after[area].keys()) if before[area].get(p) != after[area].get(p)] for area in before}
    guards = {area + '_unchanged': not values for area, values in changes.items()}
    guards.update(source_matches_recorded_commit=source_matches_commit,
                  all_manifests_match=all(record(repo / p) == record(workspace / p) for p in manifests),
                  selected_suites_unchanged=selected == sorted((repo / PACKAGE / 'test').glob('word_zotero*_test.dart')),
                  all_selected_suites_executed=actual_suites == expected_suites and len(audit['suites']) == len(selected),
                  every_started_test_finished_once=audit['every_started_test_finished_once'],
                  final_event_success=len(audit['final_events']) == 1 and audit['final_events'][0].get('success') is True)
    passed = (exit_code == 0 and not timed_out and all(c['exit_code'] == 0 for c in checks)
              and all(guards.values()) and audit['passed'] > 0 and not audit['failed'] and not audit['skipped']
              and not any(audit[k] for k in ['error_events', 'parse_errors', 'excluded_failures', 'layout_or_tap_diagnostics']))
    # Keep source inventories once; after hashes and explicit diffs prove stability.
    inputs = dict(before=before, before_sha256={k:digest(v) for k,v in before.items()},
                  after_sha256={k:digest(v) for k,v in after.items()}, changed_paths=changes,
                  manifest_paths=manifests, dependency_packages=sorted(reachable),
                  runtime_receipt=json.loads((toolchain / 'runtime-ready.json').read_text()),
                  package_archive_receipt_sha256=record(toolchain / 'setup/prefetch-current.json')['sha256'],
                  scope='Local dependency libraries/assets, selected tests and their relative imports, Zotero fixtures, all manifests/locks, reachable dependency trees, and listed runtime executables. Existing historical evidence is not duplicated.')
    (out / 'inputs.json.gz').write_bytes(gzip.compress((json.dumps(inputs, sort_keys=True) + '\n').encode(), mtime=0))
    (out / 'events.jsonl.gz').write_bytes(gzip.compress(raw.read_bytes(), mtime=0))
    raw.unlink()
    stderr = stderr_path.read_text(errors='replace')
    stderr_path.unlink()
    summary = dict(**{k:v for k,v in run.items() if k!='status'}, status='passed' if passed else 'failed',
                   finished_at_utc=utc(), source_head_at_end=final_head, command=command, cwd=str(cwd),
                   actual_process_exit=exit_code, timed_out=timed_out, elapsed_seconds=elapsed,
                   checks=checks, guards=guards, tests=audit, stderr=stderr,
                   artifacts={p.name:record(p) for p in sorted(out.iterdir()) if p.name != 'summary.json'},
                   scope='Full editor word_zotero*_test.dart cohort only. Focused runs and previous engine/Studio/incoming cohorts are excluded. Passed counts exclude hidden/lifecycle/loading notifications and skipped cases; parameterized real cases remain included.')
    write_json(out / 'summary.json', summary)
    print(json.dumps(dict(status=summary['status'], exit_code=exit_code, suites=audit['suite_count'],
                          passed=audit['passed'], skipped=audit['skipped'], failed=audit['failed'], guards=guards)), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
