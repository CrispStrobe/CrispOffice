#!/usr/bin/env python3
"""Run the final Zotero editor cohort and scoped canonical Dart analysis."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import time


ROOT = Path('/workspace/scratch/60be9067b9f9')
SOURCE = ROOT / 'quds_office_suite'
OUTPUT = ROOT / 'zotero-editor-final'
HARNESSES = ROOT / 'zotero-toolchain/harness'
EXPECTED_HEAD = '91c725feb5517db3c5f686e80662e2cb4f77f0d4'
BASELINE = '933dff0833b9aa2f6daa350c57bca93d57c6fd7f'
RUNNER = SOURCE / 'docs/validation/zotero-citing-20261115/run-focused-checks.py'


def save(name, data):
    (OUTPUT / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def git(*args):
    return subprocess.check_output(['git', '-C', str(SOURCE), *args], text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    assert git('rev-parse', 'HEAD') == EXPECTED_HEAD
    assert not git('status', '--porcelain'), 'Canonical source must be clean.'
    spec = importlib.util.spec_from_file_location('existing_checks', RUNNER)
    checks = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checks)
    before = checks.source_fingerprint(SOURCE)
    save('source-before.json', before)
    dart = Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/dart-sdk/bin/dart'
    flutter = Path(os.environ['FLUTTER_ROOT']) / 'bin/flutter'
    tests = sorted(path.name for path in (SOURCE / 'packages/quds_office_editor/test').glob('word_zotero*.dart'))
    save('editor-tests.json', tests)
    changed = git('diff', '--name-only', BASELINE, EXPECTED_HEAD, '--', '*.dart').splitlines()
    assert len(changed) == 6, changed
    graphs = {}
    inputs = {}
    for name in ('engine', 'editor'):
        harness = HARNESSES / ('quds_office_' + name)
        for path in ('lib', 'test'):
            assert (harness / path).resolve() == SOURCE / 'packages' / ('quds_office_' + name) / path
        graphs[name] = checks.normalize_config(harness / '.dart_tool/package_config.json', SOURCE)
        (OUTPUT / (name + '-analysis-package-config.json')).write_bytes(graphs[name])
        inputs[name] = {
            path: digest(harness / path)
            for path in ('pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json')
        }
    receipt = {
        'source_commit': EXPECTED_HEAD,
        'source_tree': git('rev-parse', 'HEAD^{tree}'),
        'baseline': BASELINE,
        'editor_tests': tests,
        'changed_dart_targets': changed,
        'dart_version': subprocess.check_output([str(dart), '--version'], text=True).strip(),
        'harness_input_sha256_before': inputs,
        'commands': [],
        'uses_github_actions': False,
        'prior_run_counts_included': False,
    }

    def command(name, parts, cwd):
        started = time.monotonic()
        print('Running ' + name, flush=True)
        with (OUTPUT / (name + '.log')).open('w') as log:
            result = subprocess.run(parts, cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
        text = (OUTPUT / (name + '.log')).read_text()
        item = {
            'name': name,
            'command': parts,
            'cwd': str(cwd),
            'exit_code': result.returncode,
            'seconds': round(time.monotonic() - started, 3),
            'log': name + '.log',
            'log_sha256': digest(OUTPUT / (name + '.log')),
            'tail': text.splitlines()[-4:],
        }
        if name == 'editor-tests':
            match = re.search(r'\+(\d+): All tests passed!', text)
            item['passed_tests'] = int(match.group(1)) if match else None
        receipt['commands'].append(item)
        save('receipt.json', receipt)
        print(json.dumps(item), flush=True)
        if result.returncode:
            raise RuntimeError(name + ' failed')

    config = SOURCE / '.dart_tool/package_config.json'
    original = config.read_bytes() if config.exists() else None
    try:
        command('editor-tests', [str(flutter), 'test', '--no-pub', '--reporter', 'expanded', *('test/' + test for test in tests)], HARNESSES / 'quds_office_editor')
        for name in ('engine', 'editor'):
            config.parent.mkdir(exist_ok=True)
            config.write_bytes(graphs[name])
            targets = [path for path in changed if path.startswith('packages/quds_office_' + name + '/')]
            command(name + '-analysis', [str(dart), 'analyze', '--fatal-infos', *targets], SOURCE)
        command('format-check', [str(dart), 'format', '--language-version=3.12', '--output=none', '--set-exit-if-changed', *changed], SOURCE)
    finally:
        if original is None:
            config.unlink(missing_ok=True)
        else:
            config.write_bytes(original)
        receipt['analysis_config_restored'] = (config.read_bytes() if config.exists() else None) == original
        after = checks.source_fingerprint(SOURCE)
        save('source-after.json', after)
        receipt['source_inputs_unchanged'] = before == after
        receipt['head_after'] = git('rev-parse', 'HEAD')
        receipt['head_unchanged'] = receipt['head_after'] == EXPECTED_HEAD
        receipt['harness_input_sha256_after'] = {
            name: {path: digest(HARNESSES / ('quds_office_' + name) / path) for path in hashes}
            for name, hashes in inputs.items()
        }
        receipt['harness_inputs_unchanged'] = receipt['harness_input_sha256_after'] == inputs
        receipt['passed_tests'] = next((item['passed_tests'] for item in receipt['commands'] if item['name'] == 'editor-tests'), None)
        receipt['all_passed'] = all(item['exit_code'] == 0 for item in receipt['commands']) and len(receipt['commands']) == 4 and all(receipt[key] for key in ('analysis_config_restored', 'source_inputs_unchanged', 'head_unchanged', 'harness_inputs_unchanged'))
        save('receipt.json', receipt)
        print(json.dumps({key: receipt[key] for key in ('all_passed', 'passed_tests', 'analysis_config_restored', 'source_inputs_unchanged', 'head_unchanged', 'harness_inputs_unchanged')}), flush=True)


if __name__ == '__main__':
    main()
