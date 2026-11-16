#!/usr/bin/env python3
"""Validate the current German proofing inputs without regenerating data."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path('/workspace/scratch/a450b8f86aed/quds_office_suite')
PACKAGE = ROOT / 'packages/quds_office_engine'
OUTPUT = Path(__file__).resolve().parent
DART = '/workspace/scratch/a450b8f86aed/runtime/flutter/bin/cache/dart-sdk/bin/dart'
NODE = shutil.which('node')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inputs():
    paths = []
    for folder in ['lib/src/proofing', 'test/proofing', 'tool/proofing', 'third_party/proofing']:
        paths.extend(p for p in (PACKAGE / folder).rglob('*')
                     if p.is_file() and '__pycache__' not in p.parts)
    paths += [PACKAGE / 'lib/src/opc/zip/deflate_codec.dart',
              PACKAGE / 'pubspec.yaml', ROOT / 'pubspec.lock',
              ROOT / '.dart_tool/package_config.json']
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}


def main():
    before = inputs()
    record = {
        'started_at_utc': datetime.now(timezone.utc).isoformat(),
        'scope': 'Full shared proofing/German test directory, fatal-info analysis, compiled JavaScript smoke in Node. No dictionary or pattern regeneration; no browser or native Harper claim.',
        'source_sha256_before': before,
        'runtime_sha256': {'dart': digest(DART), 'node': digest(NODE)},
        'head_at_start': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'commands': [],
    }
    success = False
    try:
        commands = [
            ('dart-version', [DART, '--version']),
            ('node-version', [NODE, '--version']),
            ('analyze', [DART, 'analyze', '--fatal-infos', 'lib/src/proofing', 'test/proofing', 'tool/proofing/german_js_smoke.dart']),
            ('tests', [DART, 'test', 'test/proofing', '--reporter', 'expanded']),
            ('compile-javascript', [DART, 'compile', 'js', '-O2', 'tool/proofing/german_js_smoke.dart', '-o', str(OUTPUT / 'german-proofing.js')]),
            ('javascript-smoke', [NODE, '-e', 'globalThis.self=globalThis; require(process.argv[1]);', str(OUTPUT / 'german-proofing.js')]),
        ]
        for label, command in commands:
            start = time.monotonic()
            log = OUTPUT / f'{label}.log'
            with log.open('w') as handle:
                result = subprocess.run(command, cwd=PACKAGE, stdout=handle, stderr=subprocess.STDOUT)
            record['commands'].append({
                'label': label, 'command': command,
                'working_directory': str(PACKAGE),
                'exit_code': result.returncode,
                'duration_seconds': round(time.monotonic() - start, 3),
                'log': log.name, 'log_sha256': digest(log),
            })
            print(f'{label}: exit {result.returncode}', flush=True)
            if result.returncode:
                raise RuntimeError(f'{label} failed; see {log}')
        record['compiled_javascript_sha256'] = digest(OUTPUT / 'german-proofing.js')
        success = True
    finally:
        after = inputs()
        record['source_sha256_after'] = after
        record['inputs_unchanged'] = before == after
        record['passed'] = success and before == after
        record['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        (OUTPUT / 'receipt.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    if not record['passed']:
        raise SystemExit('Validation failed or input hashes changed.')


if __name__ == '__main__':
    main()
