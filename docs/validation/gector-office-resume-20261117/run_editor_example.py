#!/usr/bin/env python3
"""Verify the retained AOT-removal example controls on one frozen source."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
QUALIFICATION = HERE.parent / 'office-reconciled-20261117/qualification'
sys.path.insert(0, str(QUALIFICATION))
import prior_run_qualification as audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'workspace', 'flutter-root', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--source-commit', required=True)
    args = parser.parse_args()
    repo, workspace, runtime, output = [p.resolve() for p in
        (args.repo, args.workspace, args.flutter_root, args.output)]
    assert audit.git_text(repo, 'rev-parse', 'HEAD') == args.source_commit
    output.mkdir(parents=True, exist_ok=False)
    config = workspace / '.dart_tool/package_config.json'
    graph = audit.normalized_graph(config, repo)
    cwd = workspace / 'packages/quds_office_editor/example'
    selected = ['test/widget_test.dart']
    dart = runtime / 'bin/cache/dart-sdk/bin/dart'
    command = [str(dart), str(runtime / 'bin/cache/flutter_tools.snapshot'),
               '--suppress-analytics', 'test', '--no-pub', '--reporter=json', *selected]

    def snapshot():
        return {'source': audit.source_snapshot(repo, args.source_commit),
                'dependencies': audit.dependency_snapshot(graph, repo),
                'runtime': audit.runtime_snapshot(runtime),
                'workspace': audit.workspace_snapshot(workspace),
                'harness': {str(Path(__file__).resolve()): audit.sha(Path(__file__)),
                    str(QUALIFICATION / 'prior_run_qualification.py'):
                        audit.sha(QUALIFICATION / 'prior_run_qualification.py')}}

    before = snapshot()
    assert not before['source']['commit_mismatches']
    assert not before['source']['untracked_non_evidence_paths']
    (output / 'inputs-before.json.gz').write_bytes(gzip.compress(json.dumps(before, sort_keys=True).encode(), mtime=0))
    env = dict(os.environ, DASH__SUPPRESS_ANALYTICS='true', CI='true',
               FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true',
               FLUTTER_ROOT=str(runtime), PUB_CACHE=str(runtime.parent / 'pub-cache'),
               TMPDIR=str(workspace / 'tmp'), XDG_CONFIG_HOME=str(workspace / 'config'))
    started = time.monotonic()
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=900)
    summary = audit.test_summary(result.stdout, selected, False, cwd)
    after = snapshot()
    (output / 'inputs-after.json.gz').write_bytes(gzip.compress(json.dumps(after, sort_keys=True).encode(), mtime=0))
    outputs = {}
    for name, raw in [('stdout', result.stdout), ('stderr', result.stderr)]:
        data = gzip.compress(raw, mtime=0)
        (output / (name + '.gz')).write_bytes(data)
        outputs[name] = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
                         'compressed_sha256': hashlib.sha256(data).hexdigest()}
    integrity = {key + '_unchanged': before[key] == after[key] for key in before}
    head_unchanged = audit.git_text(repo, 'rev-parse', 'HEAD') == args.source_commit
    passed = (result.returncode == 0 and summary['passed'] and all(integrity.values())
              and head_unchanged and not summary.get('allowed_skipped_cases'))
    receipt = {'source_commit': args.source_commit, 'command': command, 'cwd': str(cwd),
               'selected_files': selected, 'duration_seconds': round(time.monotonic() - started, 3),
               'exit_code': result.returncode, 'test_summary': summary,
               'input_integrity': integrity, 'head_unchanged': head_unchanged,
               'outputs': outputs, 'passed': passed, 'historical_results_counted': False,
               'github_actions_queried_or_awaited': False}
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'passed': passed, 'exit_code': result.returncode,
                      'outcomes': summary['raw_runner_outcomes'], 'input_integrity': integrity}), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
