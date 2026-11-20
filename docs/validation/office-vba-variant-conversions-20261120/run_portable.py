#!/usr/bin/env python3
"""Freshly compile portable macro programs and compare canonical VM/JS receipts.

Requires the pinned Flutter SDK, Node, and an already resolved locked workspace.
The output must be a new directory outside the repository. No pub or hosted CI
command is run; all commands, raw output and guarded source manifests are kept.
"""
from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from run_validation import digest, inputs, stamp, write_json


SMOKES = (
    'web_smoke', 'web_vba_smoke', 'web_vba_procedures_smoke',
    'web_vba_control_flow_smoke', 'web_vba_arrays_smoke',
    'web_vba_dynamic_arrays_smoke',
)
CORPORA = {
    'string_intrinsics_v1': 69,
    'variant_conversions_v1': 120,
    'variant_composition_v1': 38,
}


def source_inputs(repo: Path) -> dict[str, dict[str, object]]:
    result = inputs(repo)
    for name in ('run_validation.py', 'run_portable.py'):
        path = Path(__file__).resolve().with_name(name)
        result[str(path)] = {'sha256': digest(path), 'bytes': path.stat().st_size}
    return result


def save_manifest(path: Path, value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
    path.write_bytes(gzip.compress(encoded, mtime=0))
    return hashlib.sha256(encoded).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True, help='Flutter SDK root')
    parser.add_argument('--node', type=Path, required=True, help='Node executable')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, sdk, node, output = (
        path.resolve() for path in (args.repo, args.sdk, args.node, args.output)
    )
    if output.is_relative_to(repo):
        parser.error('--output must be outside the repository')
    dart = sdk / 'bin/cache/dart-sdk/bin/dart'
    config = repo / '.dart_tool/package_config.json'
    for path in (dart, node, config):
        if not path.is_file():
            parser.error(f'Required existing input is missing: {path}')
    output.mkdir(parents=True, exist_ok=False)
    logs, build = output / 'logs', output / 'build'
    logs.mkdir()
    build.mkdir()
    temporary = output / 'tmp'
    temporary.mkdir()
    cwd = repo / 'packages/quds_office_engine'
    tool = cwd / 'tool/macros'
    fixtures = cwd / 'test/fixtures/vba_conformance'
    env = dict(os.environ, FLUTTER_ROOT=str(sdk), CI='true', TMPDIR=str(temporary),
               FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true',
               DASH__SUPPRESS_ANALYTICS='true')
    env['PATH'] = os.pathsep.join((str(dart.parent), str(sdk / 'bin'), env.get('PATH', '')))
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    before = source_inputs(repo)
    before_sha = save_manifest(output / 'inputs-before.json.gz', before)
    commands, smoke_results, corpus_results = [], [], []
    failure = None

    def run(name: str, command: list[str]) -> Path:
        stdout_path, stderr_path = logs / f'{name}.stdout', logs / f'{name}.stderr'
        record = {
            'name': name, 'command': command, 'cwd': str(cwd),
            'source_head': head, 'input_manifest_sha256': before_sha,
            'started_at': stamp(), 'stdout': str(stdout_path.relative_to(output)),
            'stderr': str(stderr_path.relative_to(output)),
        }
        write_json(logs / f'{name}.command.json', record)
        print(json.dumps({'started': name}), flush=True)
        start = time.monotonic()
        with stdout_path.open('wb') as stdout, stderr_path.open('wb') as stderr:
            try:
                result = subprocess.run(command, cwd=cwd, env=env, stdout=stdout,
                                        stderr=stderr, timeout=900)
                record['exit_code'] = result.returncode
            except subprocess.TimeoutExpired:
                record['exit_code'] = 'timeout'
            except OSError as error:
                record['exit_code'] = 'spawn-error'
                record['error'] = str(error)
        record.update(finished_at=stamp(), seconds=time.monotonic() - start,
                      stdout_sha256=digest(stdout_path), stderr_sha256=digest(stderr_path))
        commands.append(record)
        write_json(logs / f'{name}.command.json', record)
        print(json.dumps({'finished': name, 'exit_code': record['exit_code']}), flush=True)
        if record['exit_code'] != 0:
            raise RuntimeError(f'{name} failed: {record["exit_code"]}')
        return stdout_path

    def compile_js(name: str, source: Path, defines: list[str]) -> Path:
        target = build / f'{name}.js'
        run(f'{name}-compile', [str(dart), 'compile', 'js', '-O1',
                               f'--packages={config}', *defines, str(source), '-o', str(target)])
        return target

    def execute_js(name: str, target: Path) -> Path:
        return run(f'{name}-js', [str(node), '-e',
                                 'globalThis.self=globalThis; require(process.argv[1]);', str(target)])

    try:
        dart_version = run('dart-version', [str(dart), '--version'])
        node_version = run('node-version', [str(node), '--version'])
        write_json(output / 'runtime.json', {
            'flutter_sdk': str(sdk), 'dart': str(dart), 'node': str(node),
            'dart_sha256': digest(dart), 'node_sha256': digest(node),
            'dart_version_stdout': dart_version.read_text(),
            'dart_version_stderr': (logs / 'dart-version.stderr').read_text(),
            'node_version_stdout': node_version.read_text(),
            'node_version_stderr': (logs / 'node-version.stderr').read_text(),
            'python': sys.version, 'package_config_sha256': digest(config),
        })
        for name in SMOKES:
            target = compile_js(name, tool / f'{name}.dart', [])
            receipt = execute_js(name, target)
            smoke_results.append({'name': name, 'accepted': True,
                                  'javascript_sha256': digest(target),
                                  'stdout_sha256': digest(receipt)})
        for name, count in CORPORA.items():
            fixture = fixtures / f'{name}.json'
            raw = fixture.read_bytes()
            suite = json.loads(raw)
            if len(suite['cases']) != count:
                raise RuntimeError(f'{name}: expected exactly {count} canonical cases')
            define = '-DVBA_CONFORMANCE_BASE64=' + base64.b64encode(raw).decode('ascii')
            source = tool / 'web_vba_conformance.dart'
            vm = run(f'{name}-vm', [str(dart), f'--packages={config}', define, str(source)])
            target = compile_js(name, source, [define])
            js = execute_js(name, target)
            if vm.read_bytes() != js.read_bytes():
                raise RuntimeError(f'{name}: VM and JavaScript receipts differ')
            receipt = json.loads(vm.read_bytes())
            if (receipt.get('suite') != suite['suite'] or receipt.get('caseCount') != count
                    or [case['id'] for case in receipt['cases']]
                    != [case['id'] for case in suite['cases']]):
                raise RuntimeError(f'{name}: receipt does not cover the exact canonical suite')
            corpus_results.append({
                'name': name, 'case_count': count, 'accepted': True,
                'fixture_sha256': hashlib.sha256(raw).hexdigest(),
                'javascript_sha256': digest(target), 'receipt_sha256': digest(vm),
                'receipts_byte_identical': True,
            })
    except Exception as error:
        failure = f'{type(error).__name__}: {error}'
    finally:
        after = source_inputs(repo)
        after_sha = save_manifest(output / 'inputs-after.json.gz', after)
        changed = [path for path in sorted(before.keys() | after.keys())
                   if before.get(path) != after.get(path)]
        check = {
            'input_count': len(before), 'unchanged': not changed, 'changed': changed,
            'before_manifest_sha256': before_sha, 'after_manifest_sha256': after_sha,
            'checked_at': stamp(),
        }
        write_json(output / 'input-check.json', check)
        accepted = (failure is None and not changed and len(smoke_results) == len(SMOKES)
                    and len(corpus_results) == len(CORPORA))
        summary = {
            'source_head': head, 'accepted': accepted, 'failure': failure,
            'input_check': check, 'smoke_programs': smoke_results, 'corpora': corpus_results,
            'canonical_cases_per_runtime': sum(item['case_count'] for item in corpus_results),
            'commands': commands, 'no_hosted_ci_queried_or_awaited': True,
        }
        write_json(output / 'summary.json', summary)
        print(json.dumps({'accepted': accepted, 'smoke_programs': len(smoke_results),
                          'cases_per_runtime': summary['canonical_cases_per_runtime'],
                          'changed_inputs': changed, 'failure': failure}), flush=True)
    raise SystemExit(0 if accepted else 1)


if __name__ == '__main__':
    main()
