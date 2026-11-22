#!/usr/bin/env python3
"""Execute one serial source-bound cohort; never resolve dependencies or edit code."""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.parse

REPO = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
SDK = Path(os.environ.get('FLUTTER_ROOT', '/workspace/scratch/0bc03d5773e3/toolchains/flutter'))
DART = SDK / 'bin/cache/dart-sdk/bin/dart'
FLUTTER = SDK / 'bin/flutter'
TASK = REPO.parent
CHANGED = [
    'packages/quds_office_engine/lib/src/word/model/word_zotero_citing.dart',
    'packages/quds_office_engine/test/word_zotero_writing_position_test.dart',
    'packages/quds_office_editor/lib/src/embed/office_controller.dart',
    'packages/quds_office_editor/test/word_zotero_writing_position_test.dart',
    'packages/quds_office_editor/example/lib/studio_mail_cached_search_dialog.dart',
]

def sha(path: Path) -> str:
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def git(*args: str) -> str:
    return subprocess.check_output(['git', *args], cwd=REPO, text=True).strip()

def tree_files(base: Path):
    if base.is_file():
        yield base
    elif base.is_dir():
        yield from (p for p in sorted(base.rglob('*')) if p.is_file())

def snapshot() -> dict[str, dict[str, str | int]]:
    files: dict[str, Path] = {}
    names = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard',
         'packages', 'apps', 'third_party', 'tool', 'tools'], cwd=REPO).decode().split('\0')
    for name in names:
        if name and (REPO / name).is_file():
            files['repo/' + name] = REPO / name
    for name in ['pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml',
                 '.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
        if (REPO / name).is_file():
            files['repo/' + name] = REPO / name
    # Actual resolved third-party/framework inputs; workspace inputs are above.
    configs = [REPO / '.dart_tool/package_config.json',
               SDK / 'packages/flutter_tools/.dart_tool/package_config.json']
    visited: set[Path] = set()
    for config in configs:
        if not config.exists():
            continue
        files['resolved-config/' + str(config.relative_to(TASK))] = config
        for package in json.loads(config.read_text())['packages']:
            resolved = urllib.parse.urljoin(config.as_uri(), package['rootUri'])
            root = Path(urllib.parse.unquote(urllib.parse.urlparse(resolved).path)).resolve()
            if root in visited or root.is_relative_to(REPO):
                continue
            visited.add(root)
            if not root.is_relative_to(TASK / 'toolchains'):
                raise RuntimeError(f'Unexpected resolved dependency root: {root}')
            for part in ['lib', 'bin', 'hook', 'assets', 'fonts', 'pubspec.yaml', 'pubspec.lock']:
                for path in tree_files(root / part):
                    files['dependency/' + str(path.relative_to(TASK / 'toolchains'))] = path
    # Bind the compiler/platform and the headless engine, not just the CLI wrapper.
    for part in [
        'bin/flutter', 'bin/dart', 'bin/internal/engine.version',
        'bin/cache/flutter_tools.snapshot', 'bin/cache/flutter.version.json',
        'bin/cache/dart-sdk/bin', 'bin/cache/dart-sdk/lib',
        'bin/cache/artifacts/engine/linux-x64',
        'bin/cache/artifacts/engine/common/flutter_patched_sdk',
        'bin/cache/artifacts/material_fonts',
    ]:
        for path in tree_files(SDK / part):
            files['sdk/' + str(path.relative_to(SDK))] = path
    return {name: {'sha256': sha(path), 'size': path.stat().st_size}
            for name, path in sorted(files.items())}

def gz_write(path: Path, data: bytes):
    with path.open('wb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as f:
        f.write(data)

def parse_tests(raw: str):
    tests: dict[int, dict] = {}
    suites: dict[int, dict] = {}
    counts = Counter()
    cases = []
    errors = []
    other = []
    done_events = []
    for line in raw.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            other.append(line)
            continue
        kind = event.get('type')
        if kind == 'suite': suites[event['suite']['id']] = event['suite']
        elif kind == 'testStart': tests[event['test']['id']] = event['test']
        elif kind == 'error': errors.append(event)
        elif kind == 'done': done_events.append(event)
        elif kind == 'testDone':
            test = tests.get(event['testID'], {})
            name = test.get('name', '')
            hidden = event.get('hidden', False)
            is_hook = name.endswith('(setUpAll)') or name.endswith('(tearDownAll)')
            is_loader = name.startswith('loading ')
            if hidden or is_hook or is_loader:
                counts['excluded_loaders_or_hooks'] += 1
                if event['result'] != 'success' or event.get('skipped'):
                    counts['excluded_non_success'] += 1
                continue
            result = 'skipped' if event.get('skipped') else event['result']
            counts[result] += 1
            suite = suites.get(test.get('suiteID'), {})
            path = suite.get('path', '')
            if path.startswith(str(REPO) + '/'):
                path = path[len(str(REPO)) + 1:]
            cases.append({'path': path, 'name': name, 'result': result})
    return {'counts': dict(counts), 'substantive_cases': cases,
            'suite_count': len(suites), 'started_lifecycles': len(tests),
            'errors': errors, 'done_events': done_events,
            'non_json_lines': other}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('cohort', choices=['editor-position','analysis','format',
                                         'engine-zotero','editor-zotero','studio-zotero'])
    parser.add_argument('--label')
    args = parser.parse_args()
    name = args.label or args.cohort
    if not name.replace('-', '').replace('_', '').isalnum():
        raise SystemExit('Unsafe output label')
    tests: list[str] = []
    cwd = REPO
    kind = 'tests'
    if args.cohort == 'editor-position':
        cwd = REPO / 'packages/quds_office_editor'
        tests = ['test/word_zotero_writing_position_test.dart']
    elif args.cohort == 'engine-zotero':
        cwd = REPO / 'packages/quds_office_engine'
        tests = sorted(str(p.relative_to(cwd)) for p in (cwd/'test').glob('*zotero*.dart'))
    elif args.cohort == 'editor-zotero':
        cwd = REPO / 'packages/quds_office_editor'
        tests = sorted(str(p.relative_to(cwd)) for p in (cwd/'test').glob('word_zotero*_test.dart'))
    elif args.cohort == 'studio-zotero':
        cwd = REPO / 'packages/quds_office_editor/example'
        tests = [
            'test/studio_zotero_citing_transport_test.dart',
            'test/studio_zotero_shortcuts_test.dart',
            'test/studio_zotero_odt_export_test.dart',
            'test/studio_shortcut_host_ownership_test.dart',
        ]
    if args.cohort == 'analysis':
        kind = 'analysis'
        cmd = [str(DART), 'analyze', '--fatal-infos', *CHANGED]
    elif args.cohort == 'format':
        kind = 'format'
        cmd = [str(DART), 'format', '--output=none', '--set-exit-if-changed', *CHANGED]
    elif args.cohort == 'engine-zotero':
        cmd = [str(DART), 'test', '--concurrency=2', '--reporter=json', *tests]
    else:
        cmd = [str(FLUTTER), '--no-version-check', '--suppress-analytics',
               'test', '--no-pub', '--concurrency=2', '--reporter=json', *tests]
    output_path = OUT / (name + '.jsonl' if kind == 'tests' else name + '.stdout.txt')
    error_path = OUT / (name + '.stderr.txt')
    receipt_path = OUT / (name + '-receipt.json')
    if receipt_path.exists():
        raise SystemExit(f'Refusing to overwrite previous attempt: {receipt_path}')
    env = os.environ.copy()
    env.update({'TMPDIR':str(TASK/'toolchains/tmp'),
                'PUB_CACHE':str(TASK/'toolchains/pub-cache'),
                'FLUTTER_ROOT':str(SDK),
                'DART_SUPPRESS_ANALYTICS':'true','FLUTTER_SUPPRESS_ANALYTICS':'true'})
    start = datetime.now(timezone.utc).isoformat()
    head_before = git('rev-parse', 'HEAD')
    before = snapshot()
    print(json.dumps({'cohort':name,'stage':'running','inputs':len(before),
                      'test_files':len(tests),'command':cmd}), flush=True)
    with output_path.open('w') as stdout, error_path.open('w') as stderr:
        try:
            result = subprocess.run(cmd,cwd=cwd,env=env,stdout=stdout,stderr=stderr,timeout=1200)
            exit_code: int | str = result.returncode
        except subprocess.TimeoutExpired:
            exit_code = 'timeout'
    after = snapshot()
    differences = [p for p in sorted(before.keys() | after.keys()) if before.get(p) != after.get(p)]
    result_data = parse_tests(output_path.read_text()) if kind == 'tests' else None
    manifest_path = OUT/(name+'-inputs.json.gz')
    gz_write(manifest_path,(json.dumps({'before':before,'after':after},sort_keys=True)+'\n').encode())
    logs = {}
    for path in [output_path,error_path]:
        data = path.read_bytes()
        zipped = Path(str(path)+'.gz')
        gz_write(zipped,data)
        logs[zipped.name]={'raw_sha256':hashlib.sha256(data).hexdigest(),
                           'gzip_sha256':sha(zipped),'raw_bytes':len(data)}
        path.unlink()
    result_path = None
    if result_data is not None:
        result_path = OUT/(name+'-cases.json.gz')
        gz_write(result_path,(json.dumps(result_data,sort_keys=True)+'\n').encode())
    receipt={'cohort':name,'kind':kind,'started_utc':start,
             'finished_utc':datetime.now(timezone.utc).isoformat(),
             'head_before':head_before,'head_after':git('rev-parse','HEAD'),
             'command':cmd,'cwd':str(cwd.relative_to(REPO)) or '.',
             'selected_test_files':tests,'exit_code':exit_code,
             'input_count':len(before),'inputs_unchanged':not differences,
             'input_differences':differences,
             'input_manifest':{'path':manifest_path.name,'gzip_sha256':sha(manifest_path)},
             'logs':logs,'runner_path':Path(__file__).name,'runner_sha256':sha(Path(__file__)),
             'runtime':'Flutter 3.47.8 / Dart 3.13.7 Linux x64',
             'changed_sources':{p:after.get('repo/'+p) for p in CHANGED},
             'test_summary':({k:v for k,v in result_data.items() if k not in ['substantive_cases','errors','non_json_lines']} if result_data else None),
             'result_detail':({'path':result_path.name,'gzip_sha256':sha(result_path)} if result_path else None)}
    receipt_path.write_text(json.dumps(receipt,indent=2)+'\n')
    summary={'cohort':name,'exit_code':exit_code,'input_count':len(before),
             'inputs_unchanged':not differences,'input_differences':differences,
             'test_summary':receipt['test_summary']}
    print(json.dumps(summary),flush=True)
    if exit_code != 0 or differences:
        raise SystemExit(1)

if __name__ == '__main__':
    main()
