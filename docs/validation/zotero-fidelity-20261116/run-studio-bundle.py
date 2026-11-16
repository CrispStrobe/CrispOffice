#!/usr/bin/env python3
"""Compile the complete Studio Dart bundle with the genuine resolved graph.

This is an application Dart/assets compilation, not a native executable build
or a GUI/operating-system integration acceptance test. No CI is accessed.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    'qualification', HERE.parent / 'zotero-citing-20261115/run-focused-checks.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=HERE.parents[2])
    parser.add_argument('--harness', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=HERE / 'studio-bundle')
    args = parser.parse_args()
    source, harness, output = (p.resolve() for p in
                               (args.source, args.harness, args.output))
    output.mkdir(parents=True, exist_ok=True)
    dart, snapshot, runtime = runner.runtime_info()
    inputs, _ = runner.harness_info('studio', harness, source,
                                    runner.STUDIO_TESTS)
    before = runner.source_fingerprint(source)
    command = [str(dart), str(snapshot), 'build', 'bundle', '--debug',
               '--no-pub', '--target-platform', 'linux-x64']
    receipt = {
        'started_at_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': runner.git_text(source, 'rev-parse', 'HEAD'),
        'source_before': runner.write_source_map(output, 'source-before', before),
        'runtime': runtime, 'harness': inputs, 'command': command,
        'cwd': str(harness), 'uses_github_actions': False,
        'native_executable_built': False, 'gui_acceptance': False,
    }
    log = output / 'build.log'
    error = None
    try:
        with log.open('w') as stream:
            result = subprocess.run(command, cwd=harness, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=180)
        receipt['exit_code'] = result.returncode
        if result.returncode:
            error = f'Flutter bundle failed with exit {result.returncode}'
    except subprocess.TimeoutExpired:
        error = 'Flutter bundle exceeded the bounded 180-second build window'
        receipt['exit_code'] = 124
    after = runner.source_fingerprint(source)
    receipt['source_after'] = runner.write_source_map(output, 'source-after', after)
    receipt['source_unchanged'] = before == after
    receipt['source_commit_after'] = runner.git_text(source, 'rev-parse', 'HEAD')
    receipt['log_sha256'] = hashlib.sha256(log.read_bytes()).hexdigest()
    bundle = harness / 'build/flutter_assets'
    receipt['bundle_files'] = {
        str(path.relative_to(bundle)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(bundle.rglob('*')) if path.is_file()
    } if bundle.exists() else {}
    if not receipt['source_unchanged']:
        error = (error + '; ' if error else '') + 'source changed during build'
    if not (bundle / 'kernel_blob.bin').is_file() and error is None:
        error = 'The application kernel bundle was not produced'
    receipt['error'] = error
    receipt['passed'] = error is None
    receipt['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: receipt[k] for k in
                      ('passed', 'source_unchanged', 'exit_code', 'error')}, indent=2))
    return 0 if error is None else 1


if __name__ == '__main__':
    raise SystemExit(main())
