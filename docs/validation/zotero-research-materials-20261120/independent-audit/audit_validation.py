#!/usr/bin/env python3
"""Independent, read-only recount of qualification evidence; never runs tests."""
from __future__ import annotations

import argparse
import ast
from collections import Counter
from datetime import datetime, timezone
from fnmatch import fnmatchcase
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urljoin, urlparse

import yaml


ROOT = Path('/workspace/scratch/ee4fc9e59992')
REPO = ROOT / 'quds_office_suite'
EVIDENCE = ROOT / 'final-validation/qualified'
OUT = EVIDENCE / 'independent-audit'
SDK = ROOT / 'zotero-toolchain/flutter-sdk'
FROZEN = 'f0122cb5bff5b6cf6a6f69f043545dabc2930791'
BASELINE = 'a452efdadc9000c51a8e5e9ba2f16405d4979e2e'
HISTORICAL_SOURCE = False
GIT_RECORDS = {}
STATIC_ROOT = EVIDENCE / 'static'
DEFAULT_RUNNER = ROOT / 'final-validation/run_validation.py'
NAMED_RUNTIME = {
    'bin/flutter', 'bin/cache/flutter.version.json',
    'bin/cache/dart-sdk/bin/dart', 'bin/cache/dart-sdk/bin/dartaotruntime',
    'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
    'bin/cache/dart-sdk/bin/snapshots/analysis_server_aot.dart.snapshot',
    'bin/cache/artifacts/engine/linux-x64/flutter_tester',
    'bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill',
    'bin/cache/artifacts/engine/common/flutter_patched_sdk_product/platform_strong.dill',
    'bin/cache/flutter_tools.snapshot', 'packages/flutter_tools/pubspec.yaml',
    'packages/flutter_tools/pubspec.lock',
}
CLI_SUITES = {
    'office_macro_cli_test.dart', 'office_vba_integration_test.dart',
    'office_vba_arrays_integration_test.dart', 'office_vba_control_flow_integration_test.dart',
    'office_vba_dynamic_arrays_integration_test.dart', 'office_vba_procedures_integration_test.dart',
    'office_vba_string_intrinsics_integration_test.dart',
}

# Independently transcribed selections from the intended validation plan.
PLAN = {
    'engine-zotero': ('packages/quds_office_engine', ['*zotero*_test.dart'], [], 'dart'),
    'editor-zotero': ('packages/quds_office_editor', ['*zotero*_test.dart'], [], 'flutter'),
    'engine-rendering': ('packages/quds_office_engine', ['slide*_test.dart'], ['office_pdf_export_test.dart', 'word_small_caps_test.dart'], 'dart'),
    'editor-rendering': ('packages/quds_office_editor', ['slide*_test.dart'], ['office_dark_slide_test.dart', 'paint_run_text_unicode_test.dart', 'word_small_caps_test.dart', 'word_tab_stops_editor_test.dart'], 'flutter'),
    'engine-vba': ('packages/quds_office_engine', ['office_vba_*_test.dart', 'office_macro_*_test.dart'], [], 'dart'),
    'mail-host': ('packages/quds_office_editor/example', [], ['studio_mail_attachment_test.dart', 'studio_mail_attachment_loader_test.dart', 'studio_mail_attachment_compose_test.dart', 'studio_mail_cloud_test.dart', 'studio_mail_ews_test.dart', 'studio_mail_session_test.dart', 'studio_mail_compose_test.dart', 'studio_mail_recipients_test.dart', 'studio_mail_reply_test.dart', 'studio_mail_threading_test.dart', 'studio_mail_test.dart'], 'flutter'),
    'mail-mime': ('third_party/enough_mail', [], ['codecs/quoted_printable_mail_codec_test.dart', 'message_builder_test.dart', 'quds_portable_mime_test.dart', 'mail/mail_send_transaction_test.dart', 'mail/mail_submission_acceptance_test.dart', 'smtp/smtp_transparency_test.dart'], 'dart'),
    'mail-transport': ('packages/quds_mail_transport', [], ['cloud_provider_test.dart', 'ews_provider_test.dart'], 'dart'),
    'engine-docx': ('packages/quds_office_engine', [], ['word_extended_revision_test.dart'], 'dart'),
    'editor-docx': ('packages/quds_office_editor', [], ['word_extended_review_test.dart'], 'flutter'),
}


def utc():
    return datetime.now(timezone.utc).isoformat()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def read_json(path):
    data = path.read_bytes()
    if path.suffix == '.gz':
        data = gzip.decompress(data)
    return json.loads(data)


FILE_CACHE = {}


def file_record(path):
    path = path.resolve()
    stat = path.stat()
    key = (str(path), stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
    if key not in FILE_CACHE:
        sha = hashlib.sha256()
        blob = hashlib.sha1(f'blob {stat.st_size}\0'.encode())
        with path.open('rb') as stream:
            for data in iter(lambda: stream.read(1024 * 1024), b''):
                sha.update(data)
                blob.update(data)
        FILE_CACHE[key] = {'bytes': stat.st_size, 'sha256': sha.hexdigest(), 'git_blob_sha1': blob.hexdigest()}
    return FILE_CACHE[key]


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


def selected_paths():
    frozen_paths = set(committed_blobs())
    result = {}
    for name, (package, patterns, extras, _) in PLAN.items():
        test_dir = Path(package) / 'test'
        paths = {str(test_dir / extra) for extra in extras}
        for pattern in patterns:
            paths.update(path for path in frozen_paths
                         if Path(path).parent == test_dir
                         and fnmatchcase(Path(path).name, pattern))
        if not paths or not paths.issubset(frozen_paths) or any(not (REPO / path).is_file() for path in paths):
            raise ValueError(f'Incomplete selection for {name}')
        result[name] = sorted(paths)
    return result


def committed_blobs():
    result = {}
    for row in git('ls-tree', '-rz', '--full-tree', FROZEN).split(b'\0'):
        if row:
            header, path = row.split(b'\t', 1)
            _, kind, blob = header.decode().split()
            if kind == 'blob':
                result[path.decode()] = blob
    return result


def committed_records(blobs):
    """Independently hash stored Git bytes, without rewriting the worktree."""
    by_blob = {}
    ids = sorted(set(blobs.values()))
    for start in range(0, len(ids), 128):
        batch = ids[start:start + 128]
        data = subprocess.check_output(
            ['git', 'cat-file', '--batch'], cwd=REPO,
            input=('\n'.join(batch) + '\n').encode())
        offset = 0
        for expected_oid in batch:
            end = data.index(b'\n', offset)
            oid, kind, size = data[offset:end].decode().split()
            size = int(size)
            assert oid == expected_oid and kind == 'blob'
            content = data[end + 1:end + 1 + size]
            assert len(content) == size and data[end + 1 + size] == 10
            blob_hash = hashlib.sha1(f'blob {size}\0'.encode() + content).hexdigest()
            assert blob_hash == oid
            by_blob[oid] = {'bytes': size, 'sha256': hashlib.sha256(content).hexdigest(), 'git_blob_sha1': oid}
            offset = end + size + 2
        assert offset == len(data)
    return {name: by_blob[oid] for name, oid in blobs.items()}


def source_record(relative):
    return GIT_RECORDS[relative] if HISTORICAL_SOURCE else file_record(REPO / relative)


def absolute_suite(path, cwd):
    if path.startswith('file:'):
        return Path(unquote(urlparse(path).path)).resolve()
    candidate = Path(path)
    return (candidate if candidate.is_absolute() else cwd / candidate).resolve()


def recount(path, cwd):
    raw = gzip.decompress(path.read_bytes()) if path.suffix == '.gz' else path.read_bytes()
    events, errors, envelopes = [], [], 0
    # NDJSON is framed by LF bytes. Unicode NEL/LINE SEPARATOR/PARAGRAPH
    # SEPARATOR are valid inside JSON test-name strings and must stay intact.
    for number, line in enumerate(raw.decode('utf-8').split('\n'), 1):
        if not line.strip(' \t\r'):
            continue
        try:
            value = json.loads(line)
        except ValueError:
            errors.append({'line': number, 'text': line})
            continue
        if isinstance(value, dict) and isinstance(value.get('type'), str):
            events.append(value)
        elif isinstance(value, list) and all(isinstance(item, dict) and 'event' in item for item in value):
            envelopes += 1
        else:
            errors.append({'line': number, 'value': value})
    starts_list = [event['test'] for event in events if event['type'] == 'testStart']
    starts = {test['id']: test for test in starts_list}
    suites_list = [event['suite'] for event in events if event['type'] == 'suite']
    suites = {suite['id']: suite for suite in suites_list}
    done_list = [event for event in events if event['type'] == 'testDone']
    completion = Counter(event['testID'] for event in done_list)
    bad = list(errors)
    if len(starts) != len(starts_list):
        bad.append('Duplicate testStart IDs')
    if len(suites) != len(suites_list):
        bad.append('Duplicate suite IDs')
    if set(completion) != set(starts) or any(count != 1 for count in completion.values()):
        bad.append('Started/completed test IDs do not match exactly once')
    exclusions, cases = [], []
    for event in done_list:
        test = starts.get(event['testID'])
        if test is None:
            bad.append({'missing_start': event['testID']})
            continue
        name = test['name']
        # Lifecycle records have no authored Dart source location. A legitimate
        # source-located case is never discarded because its name resembles one.
        pseudo = event.get('hidden', False) or (
            test.get('url') is None and
            (name.startswith('loading ') or name.endswith(('(setUpAll)', '(tearDownAll)')))
        )
        skipped = bool(event.get('skipped') or test.get('metadata', {}).get('skip'))
        passed = event.get('result') == 'success' and not skipped
        if not passed:
            bad.append({'test': name, 'result': event.get('result'), 'skipped': skipped, 'lifecycle': pseudo})
        suite = suites.get(test.get('suiteID'))
        if suite is None:
            bad.append({'test': name, 'missing_suite': test.get('suiteID')})
            continue
        suite_path = str(absolute_suite(suite['path'], cwd).relative_to(REPO))
        record = {'suite': suite_path, 'name': name, 'result': event.get('result'), 'skipped': skipped, 'source_url': test.get('url')}
        if pseudo:
            exclusions.append(record)
        else:
            cases.append(record)
    final = [event for event in events if event['type'] == 'done']
    if len(final) != 1 or final[0].get('success') is not True:
        bad.append({'invalid_final_events': final})
    emitted_errors = [event for event in events if event['type'] == 'error']
    bad.extend(emitted_errors)
    layout = [event for event in events if event['type'] == 'print' and re.search(
        r'A Render\w+ overflowed|would not hit test on the specified widget|does not receive pointer events', event.get('message', ''))]
    bad.extend(layout)
    identities = Counter((case['suite'], case['name']) for case in cases)
    if any(count != 1 for count in identities.values()):
        bad.append('Duplicate application identity within cohort')
    per_suite = []
    for suite in suites_list:
        name = str(absolute_suite(suite['path'], cwd).relative_to(REPO))
        group = [case for case in cases if case['suite'] == name]
        per_suite.append({'path': name, 'passed': sum(case['result'] == 'success' and not case['skipped'] for case in group), 'failed': sum(case['result'] != 'success' and not case['skipped'] for case in group), 'skipped': sum(case['skipped'] for case in group)})
    return {
        'passed': sum(case['result'] == 'success' and not case['skipped'] for case in cases),
        'failed': sum(case['result'] != 'success' and not case['skipped'] for case in cases),
        'skipped': sum(case['skipped'] for case in cases),
        'application_cases': len(cases), 'excluded_lifecycle_cases': len(exclusions),
        'suite_count': len(suites_list), 'test_start_events': len(starts_list),
        'test_done_events': len(done_list), 'notification_envelopes': envelopes,
        'final_events': final, 'suites': per_suite, 'errors': bad,
    }, cases


def dependency_files(root):
    manifest = yaml.safe_load((root / 'pubspec.yaml').read_text()) or {}
    flutter = manifest.get('flutter') or {}
    assets = [item if isinstance(item, str) else item['path'] for item in flutter.get('assets', [])]
    assets.extend(font['asset'] for family in flutter.get('fonts', []) for font in family.get('fonts', []))
    paths = {root / 'pubspec.yaml'}
    for part in ['lib', 'bin', *assets]:
        path = root / part
        if path.is_file():
            paths.add(path)
        elif path.is_dir():
            paths.update(candidate for candidate in path.rglob('*') if candidate.is_file())
    return {str(path.relative_to(root)) for path in paths}


def declared_asset_paths(root):
    manifest = yaml.safe_load((root / 'pubspec.yaml').read_text()) or {}
    flutter = manifest.get('flutter') or {}
    names = [item if isinstance(item, str) else item['path'] for item in flutter.get('assets', [])]
    names.extend(font['asset'] for family in flutter.get('fonts', []) for font in family.get('fonts', []))
    return [(root / name).resolve() for name in names]


def package_roots():
    config_path = REPO / '.dart_tool/package_config.json'
    config = {value['name']: value for value in read_json(config_path)['packages']}
    return {name: Path(unquote(urlparse(urljoin(config_path.as_uri(), item['rootUri'])).path)).resolve() for name, item in config.items()}


def expected_source_paths(blobs, roots, selected):
    relevant = [REPO / f'packages/{package}/{part}'
                for package in ['quds_office_engine', 'quds_office_editor']
                for part in ['lib', 'test']]
    for package in ['quds_office_engine', 'quds_office_editor']:
        relevant.extend(declared_asset_paths(REPO / 'packages' / package))
    for root in roots.values():
        if root.is_relative_to(REPO):
            relevant.extend(root / part for part in ['lib', 'bin', 'test', 'tool'])
            relevant.extend(declared_asset_paths(root))
    relevant.append(REPO / 'packages/quds_office_engine/example/macros')
    exact_roots = {str(root.relative_to(REPO)) for root in relevant}
    prefixes = tuple(root.rstrip('/') + '/' for root in exact_roots)
    expected = set(selected)
    for name in blobs:
        if name in exact_roots or name.startswith(prefixes):
            expected.add(name)
        relative = Path(name)
        if relative.parts[0] not in ['docs', '.git'] and relative.name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']:
            expected.add(name)
    return expected


def verify_inputs(receipt, manifest, blobs):
    failures, verified = [], Counter()
    before = manifest['before']
    fingerprints = receipt['fingerprints']
    roots = package_roots()
    required_sets = {
        'source': expected_source_paths(blobs, roots, receipt['selected_repository_paths']),
        'workspace': {'.dart_tool/package_config.json', '.dart_tool/package_graph.json'},
        'runtime': NAMED_RUNTIME,
    }
    for area, required in required_sets.items():
        if set(before[area]) != required:
            failures.append({'area': area, 'missing_fingerprint_paths': sorted(required - set(before[area])), 'extra_fingerprint_paths': sorted(set(before[area]) - required)})
    for area, records in before.items():
        actual = digest(records)
        if actual != fingerprints['before_sha256'][area] or actual != fingerprints['after_sha256'][area]:
            failures.append(f'{area}: before/after inventory digest mismatch')
        if fingerprints['changed_paths'][area]:
            failures.append(f'{area}: reported input drift')
    for area in ['source', 'workspace', 'runtime']:
        base = SDK if area == 'runtime' else REPO
        for relative, expected in before[area].items():
            path = base / relative
            if area == 'source' and HISTORICAL_SOURCE:
                if GIT_RECORDS.get(relative) != expected:
                    failures.append(f'{area}: frozen Git object bytes differ: {relative}')
            elif not path.is_file() or file_record(path) != expected:
                failures.append(f'{area}: current bytes differ: {relative}')
            if area == 'source' and blobs.get(relative) != expected['git_blob_sha1']:
                failures.append(f'source: does not match frozen commit: {relative}')
            verified[area] += 1
    for package, metadata in before['dependencies'].items():
        root = Path(metadata['root'])
        if root.resolve() != roots[package]:
            failures.append(f'Dependency root differs from verified package config: {package}')
        records = metadata['files']
        if metadata['inventory_sha256'] != digest(records) or metadata['file_count'] != len(records):
            failures.append(f'dependency: invalid inventory metadata: {package}')
        if set(records) != dependency_files(root):
            failures.append(f'dependency: inventory paths incomplete: {package}')
        for relative, expected in records.items():
            path = root / relative
            if not path.is_file() or file_record(path) != expected:
                failures.append(f'dependency: current bytes differ: {package}/{relative}')
            verified['dependency_files'] += 1
    for name, expected in before['host_fonts'].items():
        path = Path(name)
        actual = {'present': path.is_file()}
        if path.is_file():
            actual.update(file_record(path))
        if actual != expected:
            failures.append(f'host font: differs: {name}')
        verified['host_fonts'] += 1
    # Reconstruct the declared dependency closure independently from the graph.
    graph = {value['name']: value for value in read_json(REPO / '.dart_tool/package_graph.json')['packages']}
    package_name = yaml.safe_load((Path(receipt['cwd']) / 'pubspec.yaml').read_text())['name']
    pending = [package_name, *graph[package_name].get('devDependencies', [])]
    if receipt['runner'] == 'dart':
        pending.append('test')
    reachable = set()
    while pending:
        name = pending.pop()
        if name in reachable:
            continue
        reachable.add(name)
        pending.extend(graph[name].get('dependencies', []))
    external = {name for name in reachable if not roots[name].is_relative_to(REPO)}
    if sorted(reachable) != manifest['reachable_packages'] or external != set(before['dependencies']):
        failures.append('Dependency closure does not match resolved graph')
    return {'verified': dict(verified), 'failures': failures, 'source_inventory_sha256': digest(before['source']), 'workspace_inventory_sha256': digest(before['workspace']), 'runtime_inventory_sha256': digest(before['runtime'])}


def verify_static(blobs):
    path = STATIC_ROOT / 'receipt.json'
    if not path.exists():
        return {'status': 'pending'}
    receipt = read_json(path)
    failures = []
    changed = {line for line in git('diff', '--name-only', BASELINE, FROZEN, '--', '*.dart').decode().splitlines()}
    if changed != set(receipt['paths']):
        failures.append({'static_selection_missing': sorted(changed - set(receipt['paths'])), 'static_selection_extra': sorted(set(receipt['paths']) - changed)})
    if receipt['head'] != FROZEN or not receipt['accepted'] or not receipt['inputs_identical']:
        failures.append('Static final acceptance or commit mismatch')
    if receipt['before'] != receipt['after']:
        failures.append('Static input drift')
    if set(receipt['before']) != set(receipt['paths']) or set(receipt['after']) != set(receipt['paths']):
        failures.append('Static fingerprint inventory omits or adds target paths')
    if set(receipt['checks']) != {'format', 'analysis'}:
        failures.append('Static receipt must contain exactly format and analysis checks')
    for relative, sha in receipt['before'].items():
        record = source_record(relative)
        if record['sha256'] != sha or blobs.get(relative) != record['git_blob_sha1']:
            failures.append(f'Static input bytes differ: {relative}')
    for name, check in receipt['checks'].items():
        if check['exit_code'] != 0:
            failures.append(f'Static {name} did not pass')
    return {'status': 'verified' if not failures else 'rejected', 'target_count': len(receipt['paths']), 'failures': failures, 'artifacts': {name: file_record(path.parent / name) for name in ['receipt.json', 'format.log', 'analysis.log']}}


def supplement_after():
    before_path = OUT / 'runtime-supplement-before.json.gz'
    before = read_json(before_path)
    records = {}
    started = utc()
    for relative in before['files']:
        path = SDK / relative
        if path.is_file():
            record = file_record(path)
            records[relative] = {'bytes': record['bytes'], 'sha256': record['sha256']}
    roots = [SDK / 'bin/cache/dart-sdk', SDK / 'bin/internal', SDK / 'bin/cache/artifacts/engine/common/flutter_patched_sdk', SDK / 'bin/cache/artifacts/engine/common/flutter_patched_sdk_product', SDK / 'bin/cache/artifacts/engine/linux-x64']
    current_paths = {str(p.relative_to(SDK)) for root in roots for p in root.rglob('*') if p.is_file()}
    current_paths.update(['bin/flutter', 'bin/dart', 'bin/cache/flutter.version.json', 'bin/cache/flutter_tools.snapshot'])
    extra = sorted(current_paths - set(before['files']))
    changes = [name for name in sorted(set(before['files']) | set(records)) if before['files'].get(name) != records.get(name)]
    after = {'capture_started_utc': started, 'capture_finished_utc': utc(), 'scope': before['scope'], 'timing_limitation': before['timing_limitation'], 'sdk_root': str(SDK), 'file_count': len(records), 'inventory_sha256': digest(records), 'files': records, 'changed_paths': changes, 'extra_paths': extra, 'unchanged': not changes and not extra}
    path = OUT / 'runtime-supplement-after.json.gz'
    path.write_bytes(gzip.compress(canonical(after) + b'\n', mtime=0))
    return {key: value for key, value in after.items() if key != 'files'}


def main():
    global FROZEN, EVIDENCE, OUT, HISTORICAL_SOURCE, GIT_RECORDS, REPO, SDK, BASELINE, STATIC_ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--finish', action='store_true', help='Require all cohorts complete and capture the after-runtime supplement.')
    parser.add_argument('--frozen', default=FROZEN, help='Exact committed source qualified by this evidence wave.')
    parser.add_argument('--evidence', type=Path, default=EVIDENCE, help='Root containing runner and accepted cohort directories.')
    parser.add_argument('--out', type=Path, default=OUT, help='Directory for this audit and runtime supplement manifests.')
    parser.add_argument('--historical-source', action='store_true', help='Audit a superseded wave against frozen Git bytes, not the later current worktree. Never use for final qualification.')
    parser.add_argument('--repo', type=Path, default=REPO, help='Local repository containing the qualified commit.')
    parser.add_argument('--sdk', type=Path, default=SDK, help='Flutter SDK used by the evidence wave.')
    parser.add_argument('--baseline', default=BASELINE, help='Initial main commit for changed-target coverage.')
    parser.add_argument('--runner', type=Path, default=DEFAULT_RUNNER, help='Exact validation runner file used by the receipts.')
    parser.add_argument('--static', type=Path, default=STATIC_ROOT, help='Directory containing the static receipt and logs.')
    args = parser.parse_args()
    FROZEN, EVIDENCE, OUT = args.frozen, args.evidence.resolve(), args.out.resolve()
    REPO, SDK, BASELINE = args.repo.resolve(), args.sdk.resolve(), args.baseline
    STATIC_ROOT = args.static.resolve()
    HISTORICAL_SOURCE = args.historical_source
    if HISTORICAL_SOURCE and args.finish:
        raise ValueError('Historical source audit cannot claim final qualification')
    selections = selected_paths()
    owners = Counter(path for paths in selections.values() for path in paths)
    selection_errors = [path for path, count in owners.items() if count != 1]
    runner_path = args.runner.resolve()
    tree = ast.parse(runner_path.read_text())
    actual_plan = next(ast.literal_eval(node.value) for node in tree.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'COHORTS' for target in node.targets))
    expected_plan = {name: {'package': package, 'patterns': patterns, 'additional': extras, 'runner': runner} for name, (package, patterns, extras, runner) in PLAN.items()}
    if actual_plan != expected_plan:
        selection_errors.append('Runner plan differs from independently transcribed selection')
    blobs = committed_blobs()
    if HISTORICAL_SOURCE:
        GIT_RECORDS = committed_records(blobs)
    changed_tests = {name for name in git('diff', '--name-only', BASELINE, FROZEN, '--', '*_test.dart').decode().splitlines()}
    missed_changed_tests = sorted(changed_tests - set(owners))
    cli_sources = [REPO / 'packages/quds_office_engine/test/office_macro_cli_test.dart']
    cli_sources += sorted((REPO / 'packages/quds_office_engine/test').glob('office_vba_*integration_test.dart'))
    cli_sources = [path for path in cli_sources if 'Process.run(Platform.resolvedExecutable' in path.read_text()]
    if {path.name for path in cli_sources} != CLI_SUITES:
        selection_errors.append('CLI source suite set differs from the seven explicitly expected process suites')
    cli_checks = {str(path.relative_to(REPO)): {'selected': str(path.relative_to(REPO)) in selections['engine-vba'], 'uses_resolved_executable': True, 'uses_package_config': 'Platform.packageConfig' in path.read_text(), 'invokes_actual_macro_script': "'tool/macros/office_macro.dart'" in path.read_text(), 'sha256': file_record(path)['sha256']} for path in cli_sources}
    cli_executable = SDK / 'bin/cache/dart-sdk/bin/dart'
    with cli_executable.open('rb') as stream:
        native_executable = stream.read(4) == b'\x7fELF'
    cohorts, cases = {}, []
    for name in PLAN:
        folder = EVIDENCE / f'accepted-{name}'
        path = folder / 'receipt.json'
        if not path.exists():
            cohorts[name] = {'status': 'pending', 'expected_suites': len(selections[name])}
            continue
        receipt = read_json(path)
        if receipt['status'] == 'running':
            cohorts[name] = {'status': 'running', 'started_at_utc': receipt['started_at_utc'], 'expected_suites': len(selections[name])}
            continue
        failures = []
        if receipt['status'] != 'passed' or receipt['exit_code'] != 0 or receipt['timed_out']:
            failures.append('Receipt does not report successful process completion')
        if receipt['source_head_at_start'] != FROZEN or receipt['source_head_at_finish'] != FROZEN:
            failures.append('Run commit differs from frozen qualification commit')
        if not receipt['head_unchanged'] or not all(receipt['guards'].values()):
            failures.append('One or more receipt guards did not pass')
        for artifact, expected in receipt['artifacts'].items():
            if not (folder / artifact).is_file() or file_record(folder / artifact) != expected:
                failures.append(f'Artifact checksum mismatch: {artifact}')
        if receipt['validation_runner']['sha256'] != file_record(runner_path)['sha256']:
            failures.append('Qualification runner changed after execution')
        if receipt['selected_repository_paths'] != selections[name]:
            failures.append('Receipt selection differs from expected selection')
        actual, application_cases = recount(folder / 'events.jsonl.gz', Path(receipt['cwd']))
        failures.extend(actual['errors'])
        for field in ['passed', 'failed', 'skipped', 'application_cases', 'suite_count', 'test_start_events', 'test_done_events']:
            if actual[field] != receipt['tests'][field]:
                failures.append(f'Independent event accounting differs: {field}')
        if actual['excluded_lifecycle_cases'] != receipt['tests']['excluded_pseudo_cases']:
            failures.append('Lifecycle exclusion count differs')
        executed = [item['path'] for item in actual['suites']]
        if set(executed) != set(selections[name]) or len(executed) != len(selections[name]):
            failures.append('Executed suite paths differ from selection')
        for suite in actual['suites']:
            recorded = next((item for item in receipt['tests']['suites'] if str(absolute_suite(item['path'], Path(receipt['cwd'])).relative_to(REPO)) == suite['path']), None)
            if recorded is None or any(suite[key] != recorded[key] for key in ['passed', 'failed', 'skipped']):
                failures.append(f'Per-suite count differs: {suite["path"]}')
        manifest = read_json(folder / 'inputs.json.gz')
        inputs = verify_inputs(receipt, manifest, blobs)
        failures.extend(inputs['failures'])
        command = receipt['command']
        package, _, _, expected_runner = PLAN[name]
        expected_cwd = REPO / package
        expected_files = [str((REPO / relative).relative_to(expected_cwd)) for relative in selections[name]]
        if expected_runner == 'dart':
            expected_command = [str(cli_executable), f'--packages={REPO}/.dart_tool/package_config.json', str(package_roots()['test'] / 'bin/test.dart'), '--reporter', 'json', '--concurrency', '1', *expected_files]
        else:
            expected_command = [str(SDK / 'bin/flutter'), 'test', '--no-pub', '--reporter', 'json', '--concurrency', '1', *expected_files]
        if (command != expected_command or receipt['cwd'] != str(expected_cwd)
                or receipt['runner'] != expected_runner or receipt['package'] != package
                or receipt['selected_files'] != expected_files or receipt['concurrency'] != 1
                or receipt['application_timeouts_modified'] is not False):
            failures.append('Exact runtime command, runner, working directory or selected arguments differ')
        recorded_check = read_json(folder / 'input-check.json')
        if recorded_check != receipt['fingerprints']:
            failures.append('Input-check artifact differs from receipt')
        cases.extend({**case, 'cohort': name} for case in application_cases)
        cohorts[name] = {'status': 'verified' if not failures else 'rejected', 'passed': actual['passed'], 'failed': actual['failed'], 'skipped': actual['skipped'], 'suites': actual['suite_count'], 'excluded_lifecycle_cases': actual['excluded_lifecycle_cases'], 'test_start_events': actual['test_start_events'], 'test_done_events': actual['test_done_events'], 'failures': failures, 'inputs': inputs, 'command': command, 'receipt_sha256': file_record(path)['sha256'], 'event_log_sha256': file_record(folder / 'events.jsonl.gz')['sha256']}
    identities = Counter((case['suite'], case['name']) for case in cases)
    duplicates = [{'suite': identity[0], 'name': identity[1], 'count': count} for identity, count in identities.items() if count != 1]
    inventories = {value['inputs']['source_inventory_sha256'] for value in cohorts.values() if 'inputs' in value}
    all_finished = all(value['status'] == 'verified' for value in cohorts.values())
    supplement = read_json(OUT / 'runtime-supplement-before.json.gz')
    supplement_summary = {key: value for key, value in supplement.items() if key != 'files'}
    observed_core_starts = {
        name: read_json(EVIDENCE / f'accepted-{name}' / 'receipt.json')['started_at_utc']
        for name in PLAN if (EVIDENCE / f'accepted-{name}' / 'receipt.json').exists()
    }
    before_finished = datetime.fromisoformat(supplement['capture_finished_utc'])
    supplement_summary['observed_core_start_times'] = observed_core_starts
    supplement_summary['precedes_all_observed_core_starts'] = bool(observed_core_starts) and all(
        before_finished < datetime.fromisoformat(value) for value in observed_core_starts.values())
    if args.finish:
        if not all_finished:
            raise RuntimeError('Cannot finish audit while a cohort is missing, running, or rejected')
        supplement_summary['after'] = supplement_after()
    static = verify_static(blobs)
    cli_cases = [case for case in cases if case['cohort'] == 'engine-vba'
                 and cohorts['engine-vba']['status'] == 'verified'
                 and case['result'] == 'success' and not case['skipped']
                 and case['suite'] in cli_checks
                 and (case['suite'].endswith('/office_macro_cli_test.dart') or 'actual CLI processes' in case['name'] or case['name'].startswith('VBA command line '))]
    failures = [*selection_errors, *missed_changed_tests, *duplicates]
    if len(inventories) > 1:
        failures.append('Different product source inventories across cohorts')
    if static['status'] == 'rejected':
        failures.extend(static['failures'])
    if args.finish and static['status'] != 'verified':
        failures.append('Final qualification requires verified static analysis and formatting')
    if len(supplement['files']) != supplement['file_count'] or digest(supplement['files']) != supplement['inventory_sha256']:
        failures.append('Supplemental SDK inventory metadata differs from its file mapping')
    if args.finish and not supplement_summary['precedes_all_observed_core_starts']:
        failures.append('Final full SDK baseline must precede every core cohort start')
    if args.finish and not supplement_summary['after']['unchanged']:
        failures.append('Supplemental SDK inventory changed')
    if not native_executable or any(not all(value[field] for field in ['selected', 'uses_resolved_executable', 'uses_package_config', 'invokes_actual_macro_script']) for value in cli_checks.values()):
        failures.append('CLI execution source/runtime verification failed')
    current_head = git('rev-parse', 'HEAD').decode().strip()
    result = {
        'audited_at_utc': utc(), 'audit_kind': 'Independent raw-event recount and cryptographic verification; this script executes no application tests.',
        'frozen_product_commit': FROZEN, 'current_head': current_head, 'auditor_sha256': file_record(Path(__file__))['sha256'], 'runner_sha256': file_record(runner_path)['sha256'],
        'source_verification_mode': 'historical Git object bytes; superseded wave, not qualification of current worktree' if HISTORICAL_SOURCE else 'current worktree bytes and frozen Git object identity',
        'status': 'verified_complete' if all_finished and args.finish and not failures else 'rejected' if failures or any(value['status'] == 'rejected' for value in cohorts.values()) else 'partial',
        'selection': {'cohort_count': len(PLAN), 'suite_count': len(owners), 'counts': {key: len(value) for key, value in selections.items()}, 'paths': selections, 'overlaps': selection_errors, 'changed_test_files_since_initial_main': len(changed_tests), 'changed_test_files_not_selected': missed_changed_tests},
        'cohorts': cohorts, 'aggregate': {'completed_verified_cohorts': sum(value['status'] == 'verified' for value in cohorts.values()), 'verified_passed': sum(value.get('passed', 0) for value in cohorts.values() if value['status'] == 'verified'), 'verified_suites': sum(value.get('suites', 0) for value in cohorts.values() if value['status'] == 'verified'), 'observed_unique_application_identities': len(identities), 'cross_cohort_duplicate_identities': duplicates, 'source_inventory_sha256': sorted(inventories)},
        'static': static, 'cli': {'native_dart_elf': native_executable, 'executable': str(cli_executable), 'source_suites': cli_checks, 'completed_actual_process_cases': len(cli_cases), 'case_names': [{'suite': case['suite'], 'name': case['name']} for case in cli_cases], 'basis': 'The selected source-located CLI cases call Process.run on Platform.resolvedExecutable, forward Platform.packageConfig, invoke the real macro script and assert process results/output. Their cohort is launched with the ELF Dart VM, not flutter_tester. Count is test cases, not number of child process invocations.'},
        'runtime_supplement': supplement_summary, 'failures': failures,
        'limits': ['Counts cover the named local suites and controlled transports; no installed-app/live-account acceptance or external Office compatibility run is implied.', 'The original runner fingerprints named runtime files. The supplemental full compiler/core-library/launcher inventory begins at its recorded later timestamp; no earlier baseline is claimed.', 'Dependency fingerprints cover reachable library/bin/declared-asset files and manifests. Operating-system libraries and tools are not exhaustively fingerprinted.'],
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'application-cases.json.gz').write_bytes(gzip.compress(canonical(cases) + b'\n', mtime=0))
    result['application_cases_artifact'] = file_record(OUT / 'application-cases.json.gz')
    (OUT / 'audit.json').write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    rows = '\n'.join(f'| {name} | {value["status"]} | {value.get("passed", "—")} | {value.get("suites", value.get("expected_suites", "—"))} |' for name, value in cohorts.items())
    replay_mode = '--historical-source' if HISTORICAL_SOURCE else '--finish'
    replay_guidance = ('This is a superseded historical wave. Its missing cohorts remain pending; it must never be relabeled as final qualification.' if HISTORICAL_SOURCE else 'Use the final invocation only after all ten accepted receipts exist.')
    summary = f'''# Independent local-validation audit

Status: **{result['status']}**. Frozen product commit: `{FROZEN}`.

Source verification: **{result['source_verification_mode']}**.

{result['aggregate']['completed_verified_cohorts']} of {len(PLAN)} cohorts have completed and passed the independent audit: **{result['aggregate']['verified_passed']} application cases across {result['aggregate']['verified_suites']} suites**. Pending or running cohorts are excluded from this total.

| Cohort | Audit status | Passed cases | Suites |
|---|---|---:|---:|
{rows}

The independent selection contains {len(owners)} distinct suite paths, with no overlapping selections if the machine-readable errors list is empty. The audit verifies raw completion events, lifecycle exclusions, final success, per-suite counts, artifact checksums, source bytes against the frozen commit, resolved dependency inventories, workspace metadata, named runtime hashes and unchanged input digests. It checks identities by suite path and complete test name across cohorts.

Static final analysis/formatting audit: **{static['status']}**, {static.get('target_count', 0)} Dart targets. Actual CLI-process test cases completed: **{len(cli_cases)}**; genuine Dart executable: **{native_executable}**.

Supplemental SDK capture began `{supplement['capture_started_utc']}`, finished `{supplement['capture_finished_utc']}`, and contains {supplement['file_count']} files. It precedes every observed core-cohort start: **{supplement_summary['precedes_all_observed_core_starts']}**. Exact cohort start times and capture-boundary observations are retained in the machine-readable audit. No earlier baseline is claimed for any run already in progress. Final after-capture comparison is {'recorded in audit.json' if args.finish else 'pending'}.

See `audit.json` for exact checks, failures, paths and limitations, and `application-cases.json.gz` for every recounted application identity. This auditor ran no tests and modified no product or runtime files.

Existing-evidence verification requires the recorded checkout, SDK and dependency filesystem layout; absolute paths in receipts are not silently remapped. The exact replay invocation is:

```sh
python3 {Path(__file__).resolve()} --frozen {FROZEN} --repo {REPO} --sdk {SDK} --baseline {BASELINE} --evidence {EVIDENCE} --out {OUT} --runner {runner_path} --static {STATIC_ROOT} {replay_mode}
```

{replay_guidance} To reproduce tests in a different checkout, first use the portable qualification runners to create fresh receipts for that environment.
'''
    (OUT / 'README.md').write_text(summary)
    print(json.dumps({'status': result['status'], 'aggregate': result['aggregate'], 'static': {'status': static['status'], 'targets': static.get('target_count')}, 'cohorts': {key: {field: value.get(field) for field in ['status', 'passed', 'suites', 'failures']} for key, value in cohorts.items()}, 'failures': failures}, indent=2))
    return 1 if result['status'] == 'rejected' else 0


if __name__ == '__main__':
    raise SystemExit(main())
