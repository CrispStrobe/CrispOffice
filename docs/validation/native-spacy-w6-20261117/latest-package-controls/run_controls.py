"""Local, model-free package/browser controls; never reads a qualification panel."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True)
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--scratch', required=True)
    args = parser.parse_args()
    root = Path(args.root).resolve()
    runtime = Path(args.runtime).resolve()
    scratch = Path(args.scratch).resolve()
    scratch.mkdir(parents=True, exist_ok=True)
    output = Path(__file__).resolve().parent
    receipt_file = output / 'completion.json'
    if receipt_file.exists():
        raise RuntimeError('Existing receipt must be retained.')
    dart = runtime / 'flutter/bin/cache/dart-sdk/bin/dart'
    config = root / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text())['packages']
    test_root = next(p['rootUri'] for p in packages if p['name'] == 'test')
    if not test_root.startswith('file://'):
        raise RuntimeError('Expected resolved local cached test package.')
    test_runner = Path(test_root.removeprefix('file://')) / 'bin/test.dart'
    node = shutil.which('node')
    if not node:
        raise RuntimeError('Node is unavailable.')
    replacements = sorted([
        (str(root), 'QUDS_REPOSITORY'),
        (str(runtime), 'VALIDATION_RUNTIME'),
        (str(scratch), 'BROWSER_ARTIFACTS'),
    ], key=lambda item: len(item[0]), reverse=True)

    def sanitize(value):
        if isinstance(value, str):
            for original, replacement in replacements:
                value = value.replace(original, replacement)
            return value
        if isinstance(value, list):
            return [sanitize(v) for v in value]
        if isinstance(value, dict):
            return {k: sanitize(v) for k, v in value.items()}
        return value

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def source_hashes():
        paths = {root / p for p in [
            'pubspec.yaml', 'pubspec.lock',
            'packages/quds_office_engine/pubspec.yaml',
            'packages/quds_proofing_spacy/pubspec.yaml',
            'packages/quds_office_editor/example/test/studio_spacy_web_import_gate.dart',
        ]}
        for prefix in [
            'packages/quds_office_engine/lib',
            'packages/quds_proofing_spacy/lib',
            'packages/quds_proofing_spacy/test',
            'packages/quds_proofing_spacy/tool',
            'packages/quds_office_editor/example/lib',
        ]:
            paths.update(p for p in (root / prefix).rglob('*') if p.is_file())
        return {str(p.relative_to(root)): digest(p) for p in sorted(paths)}

    environment = dict(os.environ)
    environment['TMPDIR'] = str(scratch / 'tmp')
    Path(environment['TMPDIR']).mkdir(exist_ok=True)
    environment['PUB_CACHE'] = str(runtime / 'pub-cache')
    environment['DART_SUPPRESS_ANALYTICS'] = 'true'
    environment['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    environment.pop('CRISPEMBED_SPACY', None)
    for key in list(environment):
        if key.startswith('QUDS_SPACY_'):
            environment.pop(key)

    before = source_hashes()
    receipt = {
        'schema': 'quds.spacy.w6.latest-package-controls.v1',
        'started_at': datetime.now(timezone.utc).isoformat(),
        'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        'git_tree': subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=root, text=True).strip(),
        'scope': 'Package implementation controls after incoming deterministic baseline merge; browser gates retained separately because public imports and platform selection are unchanged.',
        'native_inference_executions': 0,
        'native_acceptance_executions': 0,
        'qualification_panel_or_outputs_read': False,
        'github_actions_queried_or_waited': False,
        'source_sha256_before': before,
        'package_config_sha256_before': digest(config),
        'environment': sanitize({key: environment[key] for key in ['TMPDIR', 'PUB_CACHE', 'DART_SUPPRESS_ANALYTICS', 'FLUTTER_SUPPRESS_ANALYTICS']}),
        'native_asset_environment_removed': True,
        'retained_browser_receipt': 'docs/validation/native-spacy-w6-20261117/package-refresh-controls/completion.json',
        'commands': [],
        'completed': False,
        'passed': False,
    }

    def save():
        pending = output / 'completion.next.json'
        pending.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
        pending.replace(receipt_file)

    save()

    def run(label, argv):
        print(json.dumps({'started': label}), flush=True)
        start = time.monotonic()
        try:
            process = subprocess.run(argv, cwd=root, env=environment, text=True,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     timeout=300)
            code, log = process.returncode, process.stdout
        except subprocess.TimeoutExpired as error:
            code = 124
            log = error.stdout or ''
            if isinstance(log, bytes):
                log = log.decode(errors='replace')
            log += '\nLocal command timed out after 300 seconds.\n'
        log = sanitize(log)
        (output / f'{label}.log').write_text(log)
        item = {'label': label, 'argv': sanitize([str(v) for v in argv]),
                'cwd': 'QUDS_REPOSITORY', 'exit_code': code,
                'elapsed_seconds': round(time.monotonic() - start, 3),
                'log': f'{label}.log', 'log_sha256': digest(output / f'{label}.log')}
        if label == 'package-tests':
            matches = re.findall(r'\+(\d+): All tests passed!', log)
            item['tests_passed'] = int(matches[-1]) if matches else None
            item['passed'] = code == 0 and bool(matches)
        elif label == 'package-analysis':
            item['passed'] = code == 0 and 'No issues found!' in log
        else:
            item['passed'] = code == 0
        print(json.dumps({'finished': label, 'exit_code': code}), flush=True)
        return item

    def browser(label, input_path):
        artifact = scratch / f'{label}.js'
        build = run(f'{label}-build', [str(dart), 'compile', 'js', '-O1', '-o', str(artifact), input_path])
        records = [build]
        if build['passed']:
            result = run(f'{label}-run', [node, '-e', 'global.self = globalThis; require(process.argv[1]);', str(artifact)])
            result['js_sha256'] = digest(artifact)
            if label != 'studio-web':
                try:
                    capability = json.loads((output / result['log']).read_text())
                    result['capability'] = capability
                    result['passed'] = result['passed'] and capability['passed'] is True and capability['native_calls'] == 0
                except (KeyError, ValueError):
                    result['passed'] = False
            records.append(result)
        return records

    jobs = [
        lambda: [run('package-tests', [str(dart), f'--packages={config}', str(test_runner), 'packages/quds_proofing_spacy/test', '--reporter', 'expanded'])],
        lambda: [run('package-analysis', [str(dart), 'analyze', 'packages/quds_proofing_spacy'])],
    ]
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(job) for job in jobs]
        for future in as_completed(futures):
            receipt['commands'].extend(future.result())
            save()
    after = source_hashes()
    receipt['source_sha256_after'] = after
    receipt['source_unchanged'] = before == after
    receipt['package_config_sha256_after'] = digest(config)
    receipt['package_config_unchanged'] = receipt['package_config_sha256_before'] == receipt['package_config_sha256_after']
    receipt['completed'] = len(receipt['commands']) == 2
    receipt['passed'] = receipt['completed'] and receipt['source_unchanged'] and receipt['package_config_unchanged'] and all(c['passed'] for c in receipt['commands'])
    receipt['finished_at'] = datetime.now(timezone.utc).isoformat()
    receipt['runner_sha256'] = digest(Path(__file__).resolve())
    save()
    print(json.dumps({key: receipt[key] for key in ['completed', 'passed', 'source_unchanged', 'package_config_unchanged']}), flush=True)
    raise SystemExit(0 if receipt['passed'] else 1)


if __name__ == '__main__':
    main()
