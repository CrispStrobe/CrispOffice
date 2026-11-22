#!/usr/bin/env python3
"""Compare the exact canonical corpus/BAS on Dart VM and compiled JavaScript.

Use the pinned SDK and locked package configuration before invoking:
  python3 run_portable.py --workspace /path/to/checkout --output /path/to/receipts
An isolated pure-Dart workspace is allowed when its source bytes match the
checkout; the emitted hashes make that boundary explicit. No CI is consulted.
"""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    engine = workspace / 'packages/quds_office_engine'
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    dart = str(Path(shutil.which('dart')).resolve())
    node = str(Path(shutil.which('node')).resolve())
    config = workspace / '.dart_tool/package_config.json'
    commands = []

    def snapshot():
        paths = {
            path
            for directory in (
                engine / 'lib',
                engine / 'tool/macros',
                engine / 'test/support',
                engine / 'test/fixtures/vba_conformance',
                engine / 'example/macros',
                workspace / 'packages/legacy_doc_parser/lib',
            )
            for path in directory.rglob('*') if path.is_file()
        }
        paths.update((config, workspace / 'pubspec.lock'))
        return {str(p.relative_to(workspace)): digest(p) for p in sorted(paths)}

    def run(name, command):
        start = time.monotonic()
        with (output / f'{name}.stdout').open('wb') as stdout, (output / f'{name}.stderr').open('wb') as stderr:
            result = subprocess.run(command, cwd=engine, stdout=stdout, stderr=stderr)
        commands.append({
            'name': name,
            'command': [item if not item.startswith('-D') else item.split('=', 1)[0] + '=<base64 of recorded source>' for item in command],
            'exit_code': result.returncode,
            'seconds': round(time.monotonic() - start, 3),
        })
        (output / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
        if result.returncode:
            raise RuntimeError(f'{name} failed; see retained stdout/stderr')
        print(name, 'passed', flush=True)

    before = snapshot()
    (output / 'inputs-before.json').write_text(json.dumps(before, indent=2) + '\n')
    results = []
    cases = [
        (name, engine / f'test/fixtures/vba_conformance/{name}.json',
         'VBA_CONFORMANCE_BASE64', 'tool/macros/web_vba_conformance.dart')
        for name in (
            'word_integer_arithmetic_v1',
            'variant_conversions_v1',
            'variant_composition_v1',
        )
    ]
    cases.append((
        'word_grouped_report', engine / 'example/macros/word_grouped_report.bas',
        'WORD_GROUPED_REPORT_BAS_BASE64',
        'tool/macros/web_vba_word_integer_arithmetic_smoke.dart',
    ))
    for name, source, define, driver in cases:
        encoded = base64.b64encode(source.read_bytes()).decode()
        definition = f'-D{define}={encoded}'
        js = output / f'{name}.js'
        run(name + '-vm', [dart, f'--packages={config}', definition, driver])
        run(name + '-compile', [dart, 'compile', 'js', '-O1', f'--packages={config}', definition, driver, '-o', str(js)])
        run(name + '-js', [node, '-e', 'globalThis.self=globalThis;require(process.argv[1]);', str(js)])
        vm = (output / f'{name}-vm.stdout').read_bytes()
        javascript = (output / f'{name}-js.stdout').read_bytes()
        if vm != javascript:
            raise RuntimeError(f'{name}: VM and JavaScript receipts differ')
        receipt = json.loads(vm)
        results.append({
            'name': name,
            'source': str(source.relative_to(workspace)),
            'source_sha256': digest(source),
            'receipt_sha256': hashlib.sha256(vm).hexdigest(),
            'byte_identical': True,
            'case_count': receipt.get('caseCount'),
            'operations': receipt.get('operations'),
        })
        # Compiled outputs can be recreated from the bound source and runtime;
        # retain the execution receipts without occupying hundreds of MiB.
        for temporary in output.glob(name + '.js*'):
            temporary.unlink()
    after = snapshot()
    (output / 'inputs-after.json').write_text(json.dumps(after, indent=2) + '\n')
    changed = [p for p in sorted(before.keys() | after.keys()) if before.get(p) != after.get(p)]
    summary = {
        'dart': subprocess.check_output([dart, '--version'], text=True).strip(),
        'node': subprocess.check_output([node, '--version'], text=True).strip(),
        'source_input_count': len(before),
        'changed_inputs': changed,
        'results': results,
    }
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    if changed:
        raise RuntimeError('Source changed during portable qualification')


if __name__ == '__main__':
    main()
