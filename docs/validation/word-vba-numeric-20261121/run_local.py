#!/usr/bin/env python3
"""Reproduce local numeric qualification with resolved packages and pinned Dart."""
import argparse
import base64
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--dart', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--phase', choices=['regression', 'static', 'portable'], required=True)
    args = parser.parse_args()
    repo, dart, output = args.repo.resolve(), args.dart.resolve(), args.output.resolve()
    engine = repo / 'packages/quds_office_engine'
    config = repo / '.dart_tool/package_config.json'
    temporary = output / 'tmp'
    temporary.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, DART_DISABLE_ANALYTICS='1', TMPDIR=str(temporary))
    env['PATH'] = str(dart.parent) + os.pathsep + env.get('PATH', '')
    packages = json.loads(config.read_text())['packages']
    test_package = next(p for p in packages if p['name'] == 'test')
    test_root = Path(unquote(urlparse(urljoin(config.as_uri(), test_package['rootUri'])).path))
    paths = subprocess.check_output(['git', 'ls-files', '-z', '--', 'packages/quds_office_engine', 'packages/legacy_doc_parser', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.fvmrc'], cwd=repo).decode().split('\0')
    def snapshot():
        return {p: sha(repo / p) for p in paths if p}
    before = snapshot()
    (output / 'source-before.json').write_text(json.dumps(before, indent=2, sort_keys=True) + '\n')
    summary = {
        'phase': args.phase,
        'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo).decode().strip(),
        'sourceTree': subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=repo).decode().strip(),
        'inputCount': len(before), 'dartSha256': sha(dart), 'packageConfigSha256': sha(config),
        'dartVersion': subprocess.check_output([str(dart), '--version'], env=env).decode().strip(),
        'commands': [],
    }
    def save():
        (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    def run(name, command, *, recorded=None, tests=False):
        started = time.time()
        result = subprocess.run(command, cwd=engine, env=env, capture_output=True)
        for suffix, data in [('stdout', result.stdout), ('stderr', result.stderr)]:
            (output / (name + '.' + suffix + '.gz')).write_bytes(gzip.compress(data, mtime=0))
        record = {'name': name, 'command': recorded or command, 'cwd': str(engine), 'exitCode': result.returncode, 'seconds': round(time.time() - started, 3), 'stdoutBytes': len(result.stdout), 'stderrBytes': len(result.stderr), 'stdoutSha256': hashlib.sha256(result.stdout).hexdigest(), 'stderrSha256': hashlib.sha256(result.stderr).hexdigest()}
        if tests:
            events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith(b'{')]
            starts = {e['test']['id']: e['test'] for e in events if e['type'] == 'testStart'}
            completed = [e for e in events if e['type'] == 'testDone' and not e.get('hidden')]
            record['tests'] = {'passed': sum(e['result'] == 'success' and not e.get('skipped') for e in completed), 'failed': sum(e['result'] != 'success' for e in completed), 'skipped': sum(bool(e.get('skipped')) for e in completed), 'errorEvents': sum(e['type'] == 'error' for e in events), 'doneSuccess': bool(events and events[-1].get('type') == 'done' and events[-1].get('success'))}
            cases = [{**starts[e['testID']], 'result': e['result'], 'skipped': e.get('skipped', False)} for e in completed]
            (output / (name + '.cases.json.gz')).write_bytes(gzip.compress(json.dumps(cases, indent=2).encode(), mtime=0))
            stats = record['tests']
            record['rejected'] = bool(stats['failed'] or stats['skipped'] or stats['errorEvents'] or not stats['doneSuccess'])
        summary['commands'].append(record)
        save()
        print(json.dumps({'name': name, 'exit': result.returncode, 'seconds': record['seconds'], 'tests': record.get('tests')}), flush=True)
        if result.returncode or record.get('rejected'):
            raise RuntimeError(name + ' failed; retained raw logs are authoritative')
        return result.stdout
    common = [str(dart), '--packages=' + str(config)]
    if args.phase == 'regression':
        files = {p.relative_to(engine).as_posix() for pattern in ['office_vba*_test.dart', 'office_macro*_test.dart'] for p in (engine / 'test').glob(pattern)}
        files.update('test/' + name for name in ['office_operations_test.dart', 'office_steps_test.dart', 'word_step_atomicity_test.dart', 'word_steps_vocabulary_test.dart', 'word_structure_steps_test.dart', 'word_position_test.dart', 'sheet_macro_preservation_test.dart', 'style_cascade_test.dart'])
        summary['suiteFiles'] = sorted(files)
        run('macro-regressions', common + [str(test_root / 'bin/test.dart'), '--reporter=json', '--concurrency=2', *sorted(files)], tests=True)
    elif args.phase == 'static':
        run('analysis', [str(dart), 'analyze', '--fatal-infos'])
        run('format', [str(dart), 'format', '--output=none', '--set-exit-if-changed', 'lib/src/automation/office_vba_language.dart', 'test/office_vba_numeric_intrinsics_test.dart', 'test/office_vba_numeric_intrinsics_integration_test.dart', 'test/office_vba_numeric_conformance_test.dart', 'tool/macros/web_vba_word_numeric_smoke.dart'])
        run('whitespace', ['git', 'diff', '--check'])
    else:
        definitions = [
            ('word-numeric', 'WORD_NUMERIC_BAS_BASE64', 'example/macros/word_numeric_report.bas', 'tool/macros/web_vba_word_numeric_smoke.dart'),
            ('numeric-corpus', 'VBA_CONFORMANCE_BASE64', 'test/fixtures/vba_conformance/word_numeric_intrinsics_v1.json', 'tool/macros/web_vba_conformance.dart'),
            ('variant-composition', 'VBA_CONFORMANCE_BASE64', 'test/fixtures/vba_conformance/variant_composition_v1.json', 'tool/macros/web_vba_conformance.dart'),
            ('variant-conversions', 'VBA_CONFORMANCE_BASE64', 'test/fixtures/vba_conformance/variant_conversions_v1.json', 'tool/macros/web_vba_conformance.dart'),
        ]
        summary['portableInputs'] = []
        for name, define, source_file, runner in definitions:
            source = engine / source_file
            option = '-D' + define + '=' + base64.b64encode(source.read_bytes()).decode()
            display = '-D' + define + '=<base64 of ' + source_file + '; sha256=' + sha(source) + '>'
            vm = run(name + '-vm', common + [option, runner], recorded=common + [display, runner])
            javascript = temporary / (name + '.js')
            compile_command = [str(dart), 'compile', 'js', '-O1', '--packages=' + str(config)]
            run(name + '-compile', compile_command + [option, runner, '-o', str(javascript)], recorded=compile_command + [display, runner, '-o', str(javascript)])
            node = run(name + '-node', ['node', '-e', 'globalThis.self=globalThis; require(process.argv[1]);', str(javascript)])
            if vm != node:
                raise RuntimeError(name + ' VM/JavaScript receipts differ')
            receipt = json.loads(vm)
            (output / (name + '-receipt.json')).write_bytes(vm)
            summary['portableInputs'].append({'name': name, 'file': source_file, 'inputSha256': sha(source), 'receiptSha256': hashlib.sha256(vm).hexdigest(), 'byteIdentical': True, 'cases': receipt.get('caseCount'), 'operations': receipt.get('operations')})
    after = snapshot()
    (output / 'source-after.json').write_text(json.dumps(after, indent=2, sort_keys=True) + '\n')
    summary['inputsUnchanged'] = before == after
    summary['sourceManifestSha256'] = sha(output / 'source-before.json')
    summary['success'] = before == after
    save()
    if before != after:
        raise RuntimeError('Source inputs changed during qualification')
    print(json.dumps({'phase': args.phase, 'success': True, 'inputs': len(before)}), flush=True)


if __name__ == '__main__':
    main()
