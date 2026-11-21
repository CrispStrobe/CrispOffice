#!/usr/bin/env python3
"""Verify retained local qualification using Python's standard library.

Default: verify every indexed archive, independently derive test results, and
compare captured inputs with this checkout. No original runtime paths, SDK,
network access, extraction, or test execution are required.

Exit codes: 0 verified; 1 invalid evidence; 2 accepted inputs differ/missing.
Use --integrity-only to inspect historical evidence without requiring a matching
checkout. --repack-check additionally checks deterministic archive reproduction
with the current Python/zlib implementation.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile

MAX_MEMBER_BYTES = 64 * 1024 * 1024
MAX_ARCHIVE_BYTES = 256 * 1024 * 1024
SHA256 = re.compile(r'^[0-9a-f]{64}$')
RUNTIME_PATTERNS = (
    ('flutter_error', r'\[(?:ERROR|FATAL):flutter/[^\]]+\]'),
    ('unhandled_exception', r'^\s*(?:Shell:\s*)?Unhandled\s+(?:exception|error|rejection)\b'),
    ('unhandled_promise_rejection', r'^\s*(?:Shell:\s*)?(?:UnhandledPromiseRejection|uncaughtException|uncaught\s+exception)\b'),
    ('fatal_runtime_error', r'^\s*(?:Shell:\s*)?(?:Fatal error:|FATAL:|(?:Dart|Flutter)\s+(?:VM|runtime)\s+error:|Segmentation fault\b)'),
    ('dart_compile_error', r'^\s*(?:Shell:\s*)?(?:[^\s]+\.dart:\d+:\d+:\s*Error:|Error:\s+(?:Compilation failed|The method|The getter|The setter|Type\s+.+not found|Couldn.t resolve)|Failed to compile\b|Compilation failed\b)'),
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def safe_relative(name: str) -> PurePosixPath:
    require(isinstance(name, str) and bool(name), 'Empty or non-string path')
    path = PurePosixPath(name)
    require(not path.is_absolute() and '..' not in path.parts and
            '\\' not in name and path.as_posix() == name and name != '.',
            f'Unsafe or noncanonical relative path: {name!r}')
    return path


def canonical_archive(members: dict[str, bytes]) -> bytes:
    """Rebuild the deterministic USTAR/gzip format used by these bundles."""
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode='wb', filename='', mtime=0,
                       compresslevel=9) as compressed:
        with tarfile.open(fileobj=compressed, mode='w',
                          format=tarfile.USTAR_FORMAT) as archive:
            for name, data in sorted(members.items()):
                safe_relative(name)
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                entry.mode = 0o644
                entry.uid = entry.gid = entry.mtime = 0
                entry.uname = entry.gname = ''
                archive.addfile(entry, io.BytesIO(data))
    return output.getvalue()


def load_archive(entry: dict, directory: Path, repack: bool) -> dict[str, bytes]:
    relative = safe_relative(entry['path'])
    path = (directory / relative).resolve()
    require(path.is_relative_to(directory.resolve()), 'Archive leaves evidence directory')
    require(path.stat().st_size == entry['bytes'], 'Archive byte length differs')
    require(file_digest(path) == entry['sha256'], 'Archive SHA256 differs')
    expected = entry['members']
    members: dict[str, bytes] = {}
    total = 0
    with tarfile.open(path, mode='r:gz') as archive:
        for member in archive:
            safe_relative(member.name)
            require(member.isfile(), f'Non-regular archive member: {member.name}')
            require(member.name not in members, f'Duplicate member: {member.name}')
            require(member.name in expected, f'Unindexed member: {member.name}')
            require(0 <= member.size <= MAX_MEMBER_BYTES, 'Archive member exceeds limit')
            total += member.size
            require(total <= MAX_ARCHIVE_BYTES, 'Expanded archive exceeds limit')
            stream = archive.extractfile(member)
            require(stream is not None, f'Unreadable member: {member.name}')
            data = stream.read(MAX_MEMBER_BYTES + 1)
            record = expected[member.name]
            require(len(data) == member.size == record['bytes'],
                    f'Member byte length differs: {member.name}')
            require(digest(data) == record['sha256'], f'Member SHA256 differs: {member.name}')
            members[member.name] = data
    require(set(members) == set(expected), 'Indexed archive members are missing')
    if repack and entry.get('canonical_archive'):
        require(digest(canonical_archive(members)) == entry['sha256'],
                'Deterministic repack differs; check recorded Python/zlib versions')
    return members


def json_member(members: dict[str, bytes], name: str):
    safe_relative(name)
    require(name in members, f'Missing referenced member: {name}')
    data = members[name]
    if name.endswith('.gz'):
        with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
            data = stream.read(MAX_MEMBER_BYTES + 1)
        require(len(data) <= MAX_MEMBER_BYTES, 'Expanded JSON member exceeds limit')
    return json.loads(data)


def relative_member(base: str, name: str) -> str:
    safe_relative(name)
    return (PurePosixPath(base).parent / name).as_posix()


def verify_hash_map(members: dict[str, bytes], base: str, mapping: dict) -> None:
    for name, expected in mapping.items():
        target = relative_member(base, name)
        require(target in members, f'Receipt references missing member: {target}')
        require(digest(members[target]) == expected, f'Receipt member hash differs: {target}')


def runtime_diagnostics(entry: dict, receipt: dict, members: dict[str, bytes]) -> list[dict]:
    """A successful case stream does not excuse uncaught background failures."""
    findings = []
    for name in [entry['case_events'], relative_member(entry['receipt'], 'stderr.log')]:
        for number, line in enumerate(members.get(name, b'').decode(errors='replace').splitlines(), 1):
            message = line
            try:
                event = json.loads(line)
            except ValueError:
                pass
            else:
                if not isinstance(event, dict) or event.get('type') != 'print':
                    continue
                message = str(event.get('message', ''))
            for segment in message.splitlines():
                kinds = [kind for kind, pattern in RUNTIME_PATTERNS
                         if re.search(pattern, segment, re.IGNORECASE)]
                if kinds:
                    findings.append({'file': PurePosixPath(name).name, 'line': number,
                                     'kinds': kinds, 'message': segment})
    return findings


def derive_cohort(entry: dict, receipt: dict, members: dict[str, bytes]) -> dict:
    events = []
    non_json = []
    for line in members[entry['case_events']].decode().splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            non_json.append(line)
        else:
            if isinstance(value, dict):
                events.append(value)
            else:
                non_json.append(line)
    starts = {}
    for event in events:
        if event.get('type') == 'testStart':
            test = event['test']
            require(test['id'] not in starts, 'Duplicate testStart identity')
            starts[test['id']] = test
    completions = [event for event in events
                   if event.get('type') == 'testDone' and not event.get('hidden')]
    require(len({event['testID'] for event in completions}) == len(completions),
            'Duplicate visible testDone identity')
    require(all(event['testID'] in starts for event in completions),
            'Completed case lacks its start event')
    cases = [{**starts[event['testID']], 'result': event['result'],
              'skipped': event.get('skipped', False)} for event in completions]
    require(cases == json_member(members, entry['cases']),
            'Stored case identities/results differ from raw events')
    counts = {
        'passed': sum(case['result'] == 'success' and not case['skipped'] for case in cases),
        'failed': sum(case['result'] != 'success' for case in cases),
        'skipped': sum(bool(case['skipped']) for case in cases),
    }
    require(counts == entry['expected'], 'Raw case counts differ from index')
    require(all(receipt[key] == value for key, value in counts.items()),
            'Raw case counts differ from receipt')
    errors = [event for event in events if event.get('type') == 'error']
    require(errors == receipt.get('errors', []), 'Raw errors differ from receipt')
    require(non_json == receipt.get('non_json_output_lines', []),
            'Non-JSON output differs from receipt')
    terminal = [event for event in events if event.get('type') == 'done']
    terminal_success = any(event.get('success') for event in terminal)
    require(terminal_success == receipt['terminal_success'],
            'Terminal success differs from raw events')
    expected_manifest = receipt.get('expected_skip_manifest')
    expected_skips = {item['name']: item['reason']
                      for item in (expected_manifest or {}).get('entries', [])}
    skip_details = []
    for case in cases:
        if not case['skipped']:
            continue
        reasons = [event['message'] for event in events
                   if event.get('type') == 'print' and event.get('messageType') == 'skip'
                   and event.get('testID') == case['id']]
        skip_details.append({'name': case['name'], 'reason': reasons,
                             'expected': expected_skips.get(case['name']) == reasons})
    require(skip_details == receipt.get('skip_details', []),
            'Skipped case reasons differ from receipt')
    unexpected = sum(not item['expected'] for item in skip_details)
    require(unexpected == receipt.get('unexpected_skips', 0),
            'Unexpected-skip count differs')
    if entry.get('expected_skip_manifest_member'):
        member = entry['expected_skip_manifest_member']
        require(digest(members[member]) == expected_manifest['sha256'],
                'Original expected-skip manifest hash differs')
        require(json_member(members, member) == expected_manifest['entries'],
                'Expected-skip manifest entries differ')
    diagnostics = runtime_diagnostics(entry, receipt, members)
    if 'raw_diagnostics' in receipt:
        require(receipt['raw_diagnostics'] == diagnostics and
                receipt['raw_diagnostics_clean'] == (not diagnostics),
                'Recorded runtime diagnostics differ from independent raw scan')
    if entry['status'] in ['accepted', 'superseded']:
        require(receipt['accepted_process'] is True and receipt['exit_code'] == 0
                and receipt.get('runtime_interruption') is None
                and len(terminal) == 1 and terminal_success
                and not errors and not counts['failed'] and not unexpected,
                'Accepted cohort has an unsuccessful or incomplete process')
        require(not diagnostics,
                'Accepted cohort contains unhandled/error/fatal diagnostics outside its case stream')
    return counts


def verify_interrupted(entry: dict, receipt: dict, members: dict[str, bytes]) -> dict:
    events = [json.loads(line) for line in members[entry['case_events']].decode().splitlines()]
    completed = [event for event in events
                 if event.get('type') == 'testDone' and not event.get('hidden')]
    counts = {
        'passed': sum(event['result'] == 'success' and not event.get('skipped') for event in completed),
        'failed': sum(event['result'] != 'success' for event in completed),
        'skipped': sum(bool(event.get('skipped')) for event in completed),
    }
    require(all(receipt[key] == value for key, value in counts.items()),
            'Interrupted-attempt partial counts differ from raw events')
    require(entry['status'] == 'rejected' and receipt['accepted_process'] is False
            and receipt['terminal_success'] is False
            and not any(event.get('type') == 'done' and event.get('success') for event in events),
            'Interrupted attempt was misclassified as completed acceptance')
    done_ids = {event['testID'] for event in events if event.get('type') == 'testDone'}
    pending = [event['test'] for event in events if event.get('type') == 'testStart'
               and event['test']['id'] not in done_ids]
    require(pending == receipt['pending_tests'], 'Interrupted pending-case identities differ')
    return counts


def verify_aggregate(entry: dict, receipt: dict, loaded: dict, entries: dict) -> dict:
    require(receipt['accepted'] is True and
            receipt['initial_interrupted_attempt_counted'] is False,
            'Aggregate includes an unaccepted initial attempt')
    all_suites = []
    counts_by_suite = {}
    totals = {'passed': 0, 'failed': 0, 'skipped': 0}
    frozen = None
    for child in receipt['cohorts']:
        name = child['name']
        child_entry = entries[name]
        members, result = loaded[name]
        require(child_entry['status'] == entry['status'] and result['accepted_process'] is True,
                f'Aggregate child is not accepted: {name}')
        require(digest(members[child_entry['receipt']]) == child['summary_sha256'],
                f'Aggregate child receipt hash differs: {name}')
        for key in totals:
            require(child[key] == result[key], f'Aggregate child count differs: {name}')
            totals[key] += result[key]
        suites = result['suite_files']
        require(child['suite_count'] == len(suites), f'Child suite count differs: {name}')
        all_suites.extend(suites)
        inputs = json_member(members, child_entry['source_snapshots']['before'])
        if frozen is None:
            frozen = inputs
        require(inputs == frozen and child['source_matches_initial_frozen_inputs'] is True,
                f'Aggregate child inputs differ: {name}')
        raw = [json.loads(line) for line in members[child_entry['case_events']].decode().splitlines()
               if line.startswith('{')]
        suite_paths = {}
        for event in raw:
            if event.get('type') != 'suite':
                continue
            suite = event['suite']
            path = suite['path']
            prefix = result['cwd'].rstrip('/') + '/'
            if path.startswith(prefix):
                path = path[len(prefix):]
            require(path in suites, f'Raw suite is outside the cohort: {path}')
            suite_paths[suite['id']] = path
        for case in json_member(members, child_entry['cases']):
            path = suite_paths[case['suiteID']]
            value = counts_by_suite.setdefault(path, {'passed': 0, 'failed': 0, 'skipped': 0})
            value['passed'] += case['result'] == 'success' and not case['skipped']
            value['failed'] += case['result'] != 'success'
            value['skipped'] += bool(case['skipped'])
    require(len(all_suites) == len(set(all_suites)) == receipt['observed_suite_count']
            == receipt['expected_suite_count'], 'Aggregate suite coverage is duplicated or incomplete')
    require(not receipt['missing_suites'] and not receipt['extra_suites']
            and not receipt['duplicated_suites'], 'Aggregate reports incomplete suite coverage')
    require(totals == entry['expected'] and
            all(receipt[key] == value for key, value in totals.items()),
            'Aggregate totals differ from accepted cohorts')
    grouped = []
    for group in receipt['groups'].values():
        suites = group['suites']
        grouped.extend(suites)
        require(group['suite_count'] == len(suites), 'Group suite count differs')
        for key in totals:
            require(group[key] == sum(counts_by_suite[path][key] for path in suites),
                    'Group totals differ from raw case identities')
    require(sorted(grouped) == sorted(all_suites), 'Group suite coverage differs')
    return totals


def verify_portable(entry: dict, receipt: dict, members: dict[str, bytes]) -> dict:
    require(receipt['status'] == 'passed' and receipt.get('error') is None,
            'Portable receipt did not pass')
    commands = {item['label']: item for item in receipt['commands']}
    results = {}
    for check in entry['portable_checks']:
        name = check['name']
        retained = receipt['portable'][name]
        vm = members[check['vm_stdout']]
        javascript = members[check['js_stdout']]
        require(vm == javascript, f'{name}: VM and JavaScript outputs differ')
        require(digest(vm) == retained['output_sha256'], f'{name}: output hash differs')
        require(json.loads(vm) == retained['receipt'], f'{name}: output receipt differs')
        require(retained['vm_js_byte_identical'] is True, f'{name}: equality flag is false')
        require(all(commands[name + suffix]['exit_code'] == 0
                    for suffix in ['-vm', '-compile-js', '-js']),
                f'{name}: a portable command failed')
        results[name] = {'vm_js_byte_identical': True,
                         'output_sha256': retained['output_sha256']}
    return results


def verify_environment(receipt: dict, members: dict[str, bytes]) -> None:
    for item in receipt['locked_files']:
        require(digest(members[item['member']]) == item['sha256'],
                f'Environment locked file differs: {item["member"]}')
    ready = json_member(members, receipt['runtime_ready_member'])
    sdk = json_member(members, receipt['runtime_version_member'])
    require(ready['sdk'] == sdk, 'Runtime version records differ')
    official = json_member(members, receipt['official_release_member'])
    require(any(item['sha256'] == ready['sdk_archive_sha256']
                and item['version'] == sdk['frameworkVersion']
                and item['dart_sdk_version'] == sdk['dartSdkVersion']
                for item in official['release']), 'SDK release metadata differs')
    for item in receipt['workspace_manifests']:
        recorded = ready['manifest_checks'][item['path']]
        require(digest(members[item['source_member']]) == recorded['source_sha256'],
                f'Source manifest differs: {item["path"]}')
        require(digest(members[item['workspace_member']]) == recorded['validation_sha256'],
                f'Workspace manifest differs: {item["path"]}')
        require(recorded['source_sha256'] == recorded['validation_sha256'],
                f'Workspace manifest was adapted: {item["path"]}')
    for name in receipt['hosted_archive_receipts']:
        for item in json_member(members, name)['packages']:
            require(item['status'] in ['verified-download', 'verified-cache'],
                    'Unverified hosted archive in setup receipt')
            if 'actual_sha256' in item:
                require(item['actual_sha256'] == item['sha256'],
                        'Hosted archive recorded a hash mismatch')


def input_applicability(entry: dict, receipt: dict, members: dict[str, bytes],
                        checkout: Path, check_current: bool, cache: dict) -> dict:
    snapshots = entry.get('source_snapshots')
    if not snapshots:
        return {'checked': False}
    before = json_member(members, snapshots['before'])
    after = json_member(members, snapshots['after'])
    require(isinstance(before, dict) and isinstance(after, dict), 'Invalid source snapshot')
    for name, value in {**before, **after}.items():
        safe_relative(name)
        require(isinstance(value, str) and SHA256.fullmatch(value) is not None,
                f'Invalid source hash: {name}')
    changed = sorted(name for name in before.keys() | after.keys()
                     if before.get(name) != after.get(name))
    if 'source_input_count' in receipt:
        require(receipt['source_input_count'] == len(before), 'Source input count differs')
    for key in ['source_inputs_changed', 'source_changed_during_run']:
        if key in receipt:
            require(receipt[key] == changed, 'Source change list differs from snapshots')
    if entry['status'] in ['accepted', 'superseded']:
        require(not changed, 'Accepted evidence inputs changed during execution')
        require(receipt.get('source_inputs_unchanged', True) is True
                and receipt.get('inputs_unchanged', True) is True,
                'Accepted receipt reports changed inputs')
    mismatches = []
    if check_current:
        for name, expected in after.items():
            if name not in cache:
                path = (checkout / safe_relative(name)).resolve()
                if not path.is_relative_to(checkout):
                    cache[name] = {'error': 'Source path leaves checkout'}
                else:
                    try:
                        cache[name] = {'sha256': file_digest(path)}
                    except OSError as error:
                        cache[name] = {'error': str(error)}
            actual = cache[name]
            if actual.get('sha256') != expected:
                mismatches.append({'path': name, 'expected_sha256': expected, **actual})
    return {'checked': check_current, 'inputs': len(after),
            'matches_current_checkout': not mismatches if check_current else None,
            'mismatches': mismatches}


def directive_uris(source: str) -> list[str]:
    """Conservative import/export/part URI inventory, including conditional URIs."""
    statements = re.findall(r'''(?m)^[ \t]*(?:import|export|part)\s+(["'][^;]*);''', source)
    return [match.group(2) for statement in statements
            for match in re.finditer(r"(['\"])(.*?)\1", statement, re.DOTALL)]


def apply_engine_scope_review(entry: dict, members: dict, loaded: dict,
                              result: dict, checkout: Path, check_current: bool) -> None:
    """Apply only the reviewed, exact old/new hash pair for editor proofing."""
    reference = entry['input_scope_review']
    proof_members, _ = loaded[reference['archive_id']]
    proof = json_member(proof_members, reference['member'])
    require(entry['id'] in proof['cohorts'] and proof['schema_version'] == 1,
            'Engine scope review does not cover this cohort')
    exception = proof['exception']
    require(exception['path'] == 'packages/quds_office_editor/lib/src/proofing/word_proofing.dart',
            'Engine scope review cannot exclude another path')
    snapshot = json_member(members, entry['source_snapshots']['after'])
    require(len(snapshot) == 1967 and snapshot[exception['path']] == exception['old_sha256'],
            'Engine exception is not bound to the retained broad snapshot')
    roots = ['packages/quds_office_engine/lib/', 'packages/quds_office_engine/test/',
             'packages/quds_office_engine/tool/', 'packages/legacy_doc_parser/lib/']
    examples = ['packages/quds_office_engine/example/pdf_widgets_' + name + '.dart'
                for name in ['invoice', 'proposal', 'report']]
    required = {name for name in snapshot if name.endswith('.dart') and
                any(name.startswith(root) for root in roots)}
    require(required <= proof['source_files'].keys(), 'Engine dependency inventory is incomplete')
    require(proof['historical_revision'] == entry['source_revision'],
            'Dependency inventory does not cover the executed revision')
    forbidden = {'flutter', 'flutter_test', 'quds_office_editor'}
    for name, record in proof['source_files'].items():
        require(name.endswith('.dart') and
                (name in examples or any(name.startswith(root) for root in roots)),
                'Dependency review contains an unexpected source path')
        if name in snapshot:
            require(record['sha256'] == snapshot[name], 'Dependency review source hash differs')
        for uri in record['directives']:
            if uri.startswith('package:'):
                require(uri.split(':', 1)[1].split('/', 1)[0] not in forbidden,
                        'Engine dependency review includes editor/Flutter imports')
            elif not uri.startswith('dart:'):
                target = (checkout / name).parent.joinpath(uri).resolve()
                require(target.is_relative_to(checkout) and
                        target.relative_to(checkout).as_posix() in proof['source_files'],
                        'Relative engine import leaves its reviewed package roots')
        if check_current:
            source = (checkout / safe_relative(name)).read_bytes()
            require(digest(source) == record['sha256'] and
                    directive_uris(source.decode()) == record['directives'],
                    f'Engine dependency proof no longer matches source: {name}')
    for name, member in proof['manifests'].items():
        require(name in ['packages/quds_office_engine/pubspec.yaml',
                         'packages/legacy_doc_parser/pubspec.yaml'],
                'Unexpected dependency manifest')
        data = proof_members[member]
        require(digest(data) == snapshot[name], 'Dependency manifest differs from execution')
        require(not any(re.search(r'^  ' + package + r'\s*:', data.decode(), re.MULTILINE)
                        for package in forbidden), 'Manifest declares editor/Flutter dependency')
        if check_current:
            require(file_digest(checkout / name) == digest(data), 'Current dependency manifest changed')
    require(len(proof['manifests']) == 2, 'Missing local dependency manifest')
    applicability = result['input_applicability']
    applicability['scope_review'] = reference
    if check_current:
        mismatches = applicability['mismatches']
        require(len(mismatches) == 1 and mismatches[0]['path'] == exception['path'] and
                mismatches[0]['expected_sha256'] == exception['old_sha256'] and
                mismatches[0].get('sha256') == exception['new_sha256'],
                'Engine scope exception does not exactly match the observed source change')
        applicability['captured_snapshot_matches_current_checkout'] = False
        applicability['reviewed_out_of_scope_mismatches'] = mismatches
        applicability['mismatches'] = []
        applicability['matches_current_checkout'] = True
        applicability['matching_captured_inputs'] = 1966


def verify(index_path: Path, checkout: Path, integrity_only: bool = False,
           repack: bool = False, scopes: list[str] | None = None) -> dict:
    index = json.loads(index_path.read_text())
    require(index['schema_version'] == 1, 'Unsupported index schema')
    entries = {entry['id']: entry for entry in index['archives']}
    require(len(entries) == len(index['archives']), 'Duplicate archive IDs')
    selected = set(scopes or entries)
    require(selected <= entries.keys(), 'Unknown selected archive ID')
    pending = list(selected)
    while pending:
        entry = entries[pending.pop()]
        dependencies = [*entry.get('dependencies', [])]
        if entry.get('environment_id'):
            dependencies.append(entry['environment_id'])
        for dependency in dependencies:
            require(dependency in entries, f'Missing dependency: {dependency}')
            if dependency not in selected:
                selected.add(dependency)
                pending.append(dependency)
    loaded = {}
    results = []
    by_id = {}
    cache = {}
    for name in sorted(selected):
        entry = entries[name]
        result = {'id': name, 'status': entry['status'], 'kind': entry['kind']}
        try:
            statuses = {
                'dart-test-cohort': {'accepted', 'superseded', 'rejected'},
                'portable-vm-js': {'accepted'},
                'source-gates': {'accepted', 'superseded'},
                'execution-environment': {'metadata'},
                'rejected-attempt': {'rejected'},
                'interrupted-test-attempt': {'rejected'},
                'cohort-aggregate': {'accepted', 'superseded'},
                'diagnostic-record': {'rejected'},
                'publication-review': {'metadata'},
            }
            require(entry['status'] in statuses.get(entry['kind'], set()),
                    'Unknown or inappropriate evidence classification')
            if entry['status'] == 'superseded':
                require(name in index.get('superseded_scopes', {}),
                        'Superseded evidence lacks its explicit disposition')
            members = load_archive(entry, index_path.parent, repack)
            receipt = json_member(members, entry['receipt'])
            if 'files' in receipt:
                verify_hash_map(members, entry['receipt'], receipt['files'])
            for manifest in entry.get('member_manifests', []):
                verify_hash_map(members, manifest, json_member(members, manifest))
            kind = entry['kind']
            if kind == 'dart-test-cohort':
                result['runtime_diagnostics'] = runtime_diagnostics(entry, receipt, members)
                result['test_executions'] = derive_cohort(entry, receipt, members)
            elif kind == 'portable-vm-js':
                result['portable'] = verify_portable(entry, receipt, members)
            elif kind == 'source-gates':
                diff = receipt.get('diff-check', receipt.get('diff_check', 0))
                diff_exit = diff.get('exit_code') if isinstance(diff, dict) else diff
                require(receipt['analysis']['exit_code'] == 0
                        and receipt['format']['exit_code'] == 0
                        and diff_exit == 0, 'A source gate failed')
            elif kind == 'execution-environment':
                verify_environment(receipt, members)
            elif kind == 'rejected-attempt':
                require(entry['status'] == 'rejected' and receipt['status'] == 'failed'
                        and any(item['exit_code'] != 0 for item in receipt['commands']),
                        'Rejected-attempt classification differs from receipt')
            elif kind == 'interrupted-test-attempt':
                result['partial_test_executions_excluded'] = verify_interrupted(entry, receipt, members)
            elif kind == 'cohort-aggregate':
                pass  # Cross-bundle verification follows after loading its children.
            elif kind == 'diagnostic-record':
                require(entry['status'] == 'rejected' and receipt['status'] == 'rejected'
                        and bool(receipt.get('reason')), 'Diagnostic record lacks rejection classification')
                require(all(name in members for name in receipt['original_records']),
                        'Diagnostic record references missing original evidence')
            elif kind == 'publication-review':
                require(receipt['schema_version'] == 1 and bool(receipt['scope']),
                        'Publication review lacks its scope')
            else:
                raise ValueError(f'Unknown archive kind: {kind}')
            result['input_applicability'] = input_applicability(
                entry, receipt, members, checkout, not integrity_only, cache)
            result['valid'] = True
            loaded[name] = (members, receipt)
        except (OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
            result['valid'] = False
            result['error'] = str(error)
        results.append(result)
        by_id[name] = result
    # Resolve hashes across bundles using archive members, never historic paths.
    for name, (members, receipt) in loaded.items():
        entry = entries[name]
        try:
            if entry.get('environment_id'):
                environment, metadata = loaded[entry['environment_id']]
                if 'package_config_sha256' in receipt:
                    require(receipt['package_config_sha256'] ==
                            digest(environment[metadata['package_config_member']]),
                            'Cohort package configuration differs from environment')
                if 'workspace_lock_sha256' in receipt:
                    require(receipt['workspace_lock_sha256'] ==
                            digest(environment[metadata['workspace_lock_member']]),
                            'Cohort dependency lock differs from environment')
                if 'runtime' in receipt:
                    require(receipt['runtime'] == json_member(
                        environment, metadata['runtime_version_member']),
                        'Cohort runtime differs from environment')
            for reference in entry.get('receipt_references', []):
                other, _ = loaded[reference['archive_id']]
                require(receipt[reference['sha256_field']] == digest(other[reference['member']]),
                        'Referenced receipt hash differs')
            if entry.get('input_scope_review'):
                apply_engine_scope_review(entry, members, loaded, by_id[name],
                                          checkout, not integrity_only)
        except (KeyError, ValueError) as error:
            by_id[name]['valid'] = False
            by_id[name]['error'] = str(error)
    for name, (members, receipt) in loaded.items():
        if entries[name]['kind'] != 'cohort-aggregate':
            continue
        try:
            by_id[name]['aggregate_test_executions'] = verify_aggregate(
                entries[name], receipt, loaded, entries)
        except (KeyError, ValueError) as error:
            by_id[name]['valid'] = False
            by_id[name]['error'] = str(error)
    all_valid = all(result['valid'] for result in results)
    stale = [result['id'] for result in results if result['status'] == 'accepted'
             and result.get('input_applicability', {}).get('matches_current_checkout') is False]
    totals = {key: sum(result.get('test_executions', {}).get(key, 0)
                      for result in results if result['status'] == 'accepted' and result['valid'])
              for key in ['passed', 'failed', 'skipped']}
    return {'schema_version': 1, 'index': str(index_path), 'checkout': str(checkout),
            'archives_valid': all_valid, 'current_checkout_checked': not integrity_only,
            'accepted_scopes_with_input_mismatches': stale,
            'superseded_scopes': {name: index['superseded_scopes'][name] for name in selected
                                  if entries[name]['status'] == 'superseded'},
            'accepted_test_executions': totals, 'scopes': results,
            'exit_code': 1 if not all_valid else 2 if stale else 0}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, default=Path(__file__).parent / 'evidence/index.json')
    parser.add_argument('--checkout', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--integrity-only', action='store_true')
    parser.add_argument('--repack-check', action='store_true')
    parser.add_argument('--scope', action='append')
    parser.add_argument('--json-output', type=Path)
    args = parser.parse_args()
    try:
        report = verify(args.index.resolve(), args.checkout.resolve(),
                        args.integrity_only, args.repack_check, args.scope)
    except (OSError, ValueError, KeyError, TypeError) as error:
        report = {'archives_valid': False, 'error': str(error), 'exit_code': 1}
    output = json.dumps(report, indent=2, sort_keys=True) + '\n'
    if args.json_output:
        args.json_output.write_text(output)
    print(output, end='')
    return report['exit_code']


if __name__ == '__main__':
    raise SystemExit(main())
