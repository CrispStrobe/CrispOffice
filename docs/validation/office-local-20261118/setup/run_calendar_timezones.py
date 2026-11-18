#!/usr/bin/env python3
"""Run the civil-calendar regression under verified distinct local timezones."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'workspace', 'flutter-root', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--source-commit', required=True)
    args = parser.parse_args()
    repo, workspace, runtime, output = [p.resolve() for p in
        (args.repo, args.workspace, args.flutter_root, args.output)]
    sys.path.insert(0, str(repo / 'docs/validation/office-reconciled-20261117/qualification'))
    import prior_run_qualification as audit
    assert audit.git_text(repo, 'rev-parse', 'HEAD') == args.source_commit
    output.mkdir(parents=True, exist_ok=False)
    config = workspace / '.dart_tool/package_config.json'
    graph = audit.normalized_graph(config, repo)
    test_package = next(p for p in json.loads(config.read_text())['packages'] if p['name'] == 'test')
    test_root = Path(unquote(urlparse(urljoin(config.as_uri(), test_package['rootUri'])).path))
    dart = runtime / 'bin/cache/dart-sdk/bin/dart'
    cwd = workspace / 'packages/quds_office_engine'
    selected = ['test/sheet_time_period_calendar_test.dart']
    command = [str(dart), '--packages=' + str(config), str(test_root / 'bin/test.dart'),
               '--reporter=json', '--concurrency=1', *selected]
    probe = output / 'timezone_probe.dart'
    probe.write_text("import 'dart:convert';\nvoid main() { print(jsonEncode([for (final month in [1, 7, 11]) {'month':month, 'iso':DateTime(2026, month, 17, 0, 30).toIso8601String(), 'zone':DateTime(2026, month, 17, 0, 30).timeZoneName, 'offsetMinutes':DateTime(2026, month, 17, 0, 30).timeZoneOffset.inMinutes}])); }\n")

    def snapshot():
        return {'source': audit.source_snapshot(repo, args.source_commit),
                'dependencies': audit.dependency_snapshot(graph, repo),
                'runtime': audit.runtime_snapshot(runtime),
                'workspace': audit.workspace_snapshot(workspace),
                'harness': {str(Path(__file__).resolve()): audit.sha(Path(__file__)),
                            str(probe): audit.sha(probe)}}

    before = snapshot()
    assert not before['source']['commit_mismatches']
    assert not before['source']['untracked_non_evidence_paths']
    (output / 'inputs-before.json.gz').write_bytes(gzip.compress(json.dumps(before, sort_keys=True).encode(), mtime=0))
    rows = []
    for zone, offsets in [('UTC', [0, 0, 0]), ('Europe/Berlin', [60, 120, 60]),
                          ('America/Los_Angeles', [-480, -420, -480])]:
        folder = output / zone.replace('/', '_')
        folder.mkdir()
        env = dict(os.environ, TZ=zone, DASH__SUPPRESS_ANALYTICS='true',
                   DART_SUPPRESS_ANALYTICS='true', CI='true',
                   PUB_CACHE=str(runtime.parent / 'pub-cache'),
                   XDG_CONFIG_HOME=str(workspace / 'config'), TMPDIR=str(workspace / 'tmp'))
        probe_result = subprocess.run([str(dart), str(probe)], env=env, capture_output=True, timeout=60)
        (folder / 'timezone-probe.stdout').write_bytes(probe_result.stdout)
        (folder / 'timezone-probe.stderr').write_bytes(probe_result.stderr)
        assert probe_result.returncode == 0, probe_result.stderr.decode(errors='replace')
        observed = json.loads(probe_result.stdout)
        assert [x['offsetMinutes'] for x in observed] == offsets, (zone, observed)
        started = time.monotonic()
        result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=180)
        summary = audit.test_summary(result.stdout, selected, False, cwd)
        logs = {}
        for label, data in [('stdout', result.stdout), ('stderr', result.stderr)]:
            payload = gzip.compress(data, mtime=0)
            (folder / (label + '.gz')).write_bytes(payload)
            logs[label] = {'sha256': hashlib.sha256(data).hexdigest(),
                           'compressed_sha256': hashlib.sha256(payload).hexdigest(),
                           'bytes': len(data)}
        row = {'timezone': zone, 'timezone_probe': observed, 'expected_offsets_minutes': offsets,
               'timezone_verified': True, 'command': command, 'cwd': str(cwd),
               'duration_seconds': round(time.monotonic() - started, 3),
               'exit_code': result.returncode, 'test_summary': summary, 'logs': logs,
               'passed': result.returncode == 0 and summary['passed'] and
                         summary['raw_success_count'] == 8 and not summary.get('allowed_skipped_cases')}
        rows.append(row)
        (folder / 'receipt.json').write_text(json.dumps(row, indent=2, sort_keys=True) + '\n')
        print(json.dumps({'timezone': zone, 'passed': row['passed'],
                          'outcomes': summary['raw_runner_outcomes']}), flush=True)
    after = snapshot()
    (output / 'inputs-after.json.gz').write_bytes(gzip.compress(json.dumps(after, sort_keys=True).encode(), mtime=0))
    integrity = {k + '_unchanged': before[k] == after[k] for k in before}
    head_unchanged = audit.git_text(repo, 'rev-parse', 'HEAD') == args.source_commit
    receipt = {'source_commit': args.source_commit, 'selected_files': selected, 'runs': rows,
               'test_executions': sum(r['test_summary']['raw_success_count'] for r in rows),
               'input_integrity': integrity, 'head_unchanged': head_unchanged,
               'historical_outcomes_counted': False, 'github_actions_queried_or_awaited': False,
               'passed': all(r['passed'] for r in rows) and all(integrity.values()) and head_unchanged}
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
