#!/usr/bin/env python3
"""Compile the narrow continuation probe against an exact product revision."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
from urllib.parse import urljoin, urlparse, unquote


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--dart', type=Path, required=True)
    parser.add_argument('--node', default=shutil.which('node'))
    parser.add_argument('--expected-source', required=True)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    probe = Path(__file__).resolve().with_name('new_behavior_web_probe.dart')
    package_config = repo / '.dart_tool/package_config.json'
    source = subprocess.check_output(['git', 'rev-parse', args.expected_source], cwd=repo, text=True).strip()
    rows = subprocess.check_output([
        'git', 'ls-tree', '-r', source, '--',
        'packages/quds_office_engine/lib/src/proofing',
        'packages/quds_office_engine/lib/src/opc/zip/deflate_codec.dart',
        'packages/quds_office_engine/pubspec.yaml', 'pubspec.yaml',
    ], cwd=repo, text=True).splitlines()
    tree = {row.split('\t', 1)[1]: row.split('\t', 1)[0].split()[2] for row in rows}

    def product_inputs():
        result = {}
        for relative, expected_blob in sorted(tree.items()):
            data = (repo / relative).read_bytes()
            actual_blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            result[relative] = {
                'sha256': hashlib.sha256(data).hexdigest(),
                'expected_git_blob': expected_blob,
                'actual_git_blob': actual_blob,
                'matches_source_commit': expected_blob == actual_blob,
            }
        return result

    config = json.loads(package_config.read_text())
    characters = next(p for p in config['packages'] if p['name'] == 'characters')
    dependency = Path(unquote(urlparse(urljoin(package_config.as_uri(), characters['rootUri'])).path))
    dependency_paths = [p for p in (dependency / 'lib').rglob('*') if p.is_file()]
    dependency_paths += [dependency / 'pubspec.yaml']
    runtime_paths = [args.dart.resolve(), args.dart.resolve().parent / 'snapshots/dart2js_aot.dart.snapshot', Path(args.node).resolve()]

    def other_inputs():
        paths = [probe, Path(__file__).resolve(), package_config, repo / 'pubspec.lock'] + dependency_paths + runtime_paths
        return {str(p): digest(p) for p in sorted(paths)}

    before = product_inputs()
    other_before = other_inputs()
    record = {
        'started_at_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': source,
        'scope': 'Twenty targeted checks of URL and Swiss capital-sharp-s behavior, using compiled Dart JavaScript in Node. This is not browser HTTP/CSP acceptance.',
        'source_inputs_before': before,
        'dependency_runtime_probe_inputs_before': other_before,
        'package_config': str(package_config),
        'commands': [],
    }
    success = False
    try:
        if not all(v['matches_source_commit'] for v in before.values()):
            raise RuntimeError('Product inputs do not match the requested commit.')
        javascript = output / 'new_behavior_web_probe.js'
        commands = [
            ('new-behavior-dart-version', [str(args.dart), '--version']),
            ('new-behavior-node-version', [args.node, '--version']),
            ('new-behavior-compile', [str(args.dart), 'compile', 'js', '-O2', f'--packages={package_config}', str(probe), '-o', str(javascript)]),
            ('new-behavior-node', [args.node, '-e', 'globalThis.self=globalThis; require(process.argv[1]);', str(javascript)]),
        ]
        for label, command in commands:
            start = time.monotonic()
            log = output / f'{label}.log'
            with log.open('w') as handle:
                result = subprocess.run(command, cwd=repo, stdout=handle, stderr=subprocess.STDOUT)
            record['commands'].append({
                'label': label, 'command': command, 'working_directory': str(repo),
                'exit_code': result.returncode, 'duration_seconds': round(time.monotonic() - start, 3),
                'log': log.name, 'log_sha256': digest(log),
            })
            print(f'{label}: exit {result.returncode}', flush=True)
            if result.returncode:
                raise RuntimeError(f'{label} failed; see {log}')
        smoke = (output / 'new-behavior-node.log').read_text()
        record['passed_behavior_checks'] = sum(line.startswith('PASS ') for line in smoke.splitlines())
        if record['passed_behavior_checks'] != 20:
            raise RuntimeError('Unexpected check count.')
        record['compiled_javascript_sha256'] = digest(javascript)
        success = True
    finally:
        after = product_inputs()
        other_after = other_inputs()
        record['source_inputs_after'] = after
        record['dependency_runtime_probe_inputs_after'] = other_after
        record['product_matches_source_commit'] = all(v['matches_source_commit'] for v in after.values())
        record['inputs_unchanged'] = before == after and other_before == other_after
        record['passed'] = success and record['inputs_unchanged'] and record['product_matches_source_commit']
        record['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        (output / 'new-behavior-web-receipt.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    if not record['passed']:
        raise SystemExit('Probe failed, inputs changed, or product revision mismatched.')


if __name__ == '__main__':
    main()
