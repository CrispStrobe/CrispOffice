#!/usr/bin/env python3
"""Independently reconstruct local qualification and evidence integrity.

This checker imports no qualification/consumer helper. It runs no product tests,
office conversions, package resolution or GitHub requests. Pass the accepted
qualification and consumer directories, either original or restored from their
archives. Every archive indexed below this report is also restored independently.
"""
from __future__ import annotations

import argparse
import ast
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import tempfile
from urllib.parse import unquote, urljoin, urlparse


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
LOCK = 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
PACKAGES = ('quds_office_engine', 'quds_office_editor', 'legacy_doc_parser',
            'quds_proofing_harper', 'quds_proofing_gector', 'quds_reports')
FRAMEWORK = '737ba8f885dc774b53b442759999a312c9461e4e'
ENGINE = 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8'
BASELINE = '8eb01db06c1457fa04ab3f3b8b2ef8fef791fb43'
EXPECTED_LOCK = '344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def git(*args, cwd=REPO):
    return subprocess.check_output(['git', *args], cwd=cwd)


def label(path):
    path = Path(path)
    return str(path.relative_to(REPO)) if path.is_relative_to(REPO) else str(path)


def files_below(path):
    path = Path(path)
    if path.is_file():
        return {path}
    return {p for p in path.rglob('*') if p.is_file()} if path.is_dir() else set()


class FileAudit:
    """Hash each current input once, checking its metadata again at the end."""

    def __init__(self):
        self.identities = {}

    @staticmethod
    def stat(path):
        s = path.stat()
        return s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns

    def identity(self, path):
        path = Path(path).absolute()
        current = self.stat(path)
        if path in self.identities:
            saved, identity = self.identities[path]
            require(current == saved, 'Input changed during audit: ' + str(path))
            return identity
        sha256 = hashlib.sha256()
        blob = hashlib.sha1(('blob ' + str(current[2]) + '\0').encode())
        with path.open('rb') as handle:
            while chunk := handle.read(1024 * 1024):
                sha256.update(chunk)
                blob.update(chunk)
        require(self.stat(path) == current, 'Input changed while hashing: ' + str(path))
        identity = {'sha256': sha256.hexdigest(), 'git_blob': blob.hexdigest(),
                    'bytes': current[2]}
        self.identities[path] = (current, identity)
        return identity

    def check(self, path, expected):
        actual = self.identity(path)
        require(actual['sha256'] == expected, 'SHA-256 mismatch: ' + str(path))
        return actual

    def stable(self):
        for path, (saved, _) in self.identities.items():
            require(self.stat(path) == saved, 'Input changed during audit: ' + str(path))


def package_map(config):
    result = {}
    for entry in read_json(config)['packages']:
        name = entry['name']
        require(name not in result, 'Duplicate activated package: ' + name)
        root_url = urlparse(urljoin(config.as_uri(), entry['rootUri']))
        require(root_url.scheme == 'file', 'Non-file activated package: ' + name)
        root = Path(unquote(root_url.path)).resolve()
        library_url = urlparse(urljoin(root.as_uri().rstrip('/') + '/',
                                      entry.get('packageUri', 'lib/')))
        require(library_url.scheme == 'file', 'Non-file activated library: ' + name)
        result[name] = (root, Path(unquote(library_url.path)).resolve())
    return result


def expected_source_paths():
    paths = {HERE / 'run_qualification.py',
             REPO / 'docs/validation/office-fidelity-continuation-20261117/validate.py',
             REPO / LOCK, REPO / 'pubspec.lock', REPO / '.dart_tool/package_config.json'}
    for name in PACKAGES:
        root = REPO / 'packages' / name
        for directory in ('lib', 'assets', 'fonts', 'templates', 'third_party',
                          'test', 'example/fonts'):
            paths |= files_below(root / directory)
        for pattern in ('pubspec.*', 'analysis_options.yaml', 'dart_test.yaml'):
            paths |= set(root.glob(pattern))
    paths |= set(REPO.glob('pubspec.*')) | set(REPO.glob('analysis_options.yaml'))
    return {str(p.relative_to(REPO)) for p in paths if p.is_file()}


def expected_runtime_paths(metadata):
    environment = metadata['environment']
    root = Path(environment['FLUTTER_ROOT']).resolve()
    paths = set()
    for directory in ('bin/internal', 'bin/cache/dart-sdk', 'bin/cache/artifacts',
                      'packages/flutter/lib', 'packages/flutter_test/lib',
                      'packages/flutter_tools/lib', 'packages/flutter_tools/bin'):
        paths |= files_below(root / directory)
    for config in (REPO / '.dart_tool/package_config.json',
                   root / 'packages/flutter_tools/.dart_tool/package_config.json'):
        paths.add(config)
        for package_root, library in package_map(config).values():
            if not package_root.is_relative_to(REPO):
                for path in (library, package_root / 'bin', package_root / 'pubspec.yaml',
                             package_root / 'pubspec.lock'):
                    paths |= files_below(path)
    for member in ('version', 'bin/internal/engine.version', 'bin/cache/flutter.version.json'):
        paths |= files_below(root / member)
    if environment.get('QUDS_FLUTTER_TOOL_SNAPSHOT'):
        paths.add(Path(environment['QUDS_FLUTTER_TOOL_SNAPSHOT']).resolve())
    return {str(p) for p in paths if p.is_file()}


def declared_cohorts():
    module = ast.parse((HERE / 'run_qualification.py').read_text())
    selected = {}
    for statement in module.body:
        if isinstance(statement, ast.Assign):
            for target in statement.targets:
                if isinstance(target, ast.Name) and target.id in ('ENGINE', 'NODE'):
                    selected[target.id] = ast.literal_eval(statement.value)
    require(set(selected) == {'ENGINE', 'NODE'}, 'Missing declared final cohort lists')
    for name, tests in selected.items():
        require(tests and len(tests) == len(set(tests)), 'Empty/duplicate cohort: ' + name)
        require({'odt_list_fidelity_test.dart', 'odt_section_fidelity_test.dart'} <= set(tests),
                'List/section regression files omitted from ' + name)
    require(set(selected['NODE']) <= set(selected['ENGINE']), 'Node is not a VM subset')
    return {'odt-vm': selected['ENGINE'], 'odt-node': selected['NODE']}


def raw_events(raw, cwd, expected_tests):
    """Read LF-delimited events and reconstruct identities before counting cases."""
    events, non_json_lines = [], 0
    for number, line in enumerate(raw.decode('utf-8').split('\n'), 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            require(not line.lstrip().startswith('{'), 'Malformed JSON event at line ' + str(number))
            non_json_lines += 1
            continue
        require(isinstance(event, dict), 'Non-object event at line ' + str(number))
        events.append(event)
    starts, suites, completions = {}, {}, {}
    for event in events:
        kind = event.get('type')
        if kind == 'testStart':
            item = event['test']
            require(item['id'] not in starts, 'Duplicate testStart ID')
            starts[item['id']] = item
        elif kind == 'suite':
            item = event['suite']
            require(item['id'] not in suites, 'Duplicate suite ID')
            suites[item['id']] = item
        elif kind == 'testDone':
            require(event['testID'] not in completions, 'Duplicate testDone ID')
            completions[event['testID']] = event
    require(starts and starts.keys() == completions.keys(), 'Unbalanced test start/completion IDs')
    require(all(item.get('suiteID') in suites for item in starts.values()), 'Unknown suite reference')
    expected_paths = sorted(str((cwd / 'test' / test).resolve()) for test in expected_tests)
    require(all(suite.get('path') for suite in suites.values()), 'Suite has no path')
    observed_paths = sorted(str((cwd / suite['path']).resolve()) for suite in suites.values())
    require(observed_paths == expected_paths, 'Observed suite inventory differs from declared batch')
    visible, outcomes, failures, skipped = Counter(), Counter(), [], []
    hidden_count = 0
    for identifier, event in completions.items():
        if event.get('hidden'):
            require(event.get('result') == 'success' and not event.get('skipped'),
                    'Hidden loader/hook completion failed or skipped')
            hidden_count += 1
            continue
        start = starts[identifier]
        visible[start['suiteID']] += 1
        outcome = 'skipped' if event.get('skipped') else event.get('result', 'unknown')
        outcomes[outcome] += 1
        if outcome == 'skipped':
            skipped.append(start['name'])
        elif outcome != 'success':
            failures.append(start['name'])
    require(set(visible) == set(suites), 'A selected suite has no visible completions')
    terminal = [e for e in events if e.get('type') == 'done']
    require(len(terminal) == 1, 'Runner must have exactly one terminal event')
    summary = {'outcomes': dict(outcomes), 'failures': failures, 'skipped': skipped,
               'errors': [e for e in events if e.get('type') == 'error'],
               'runner_success': terminal[0].get('success') is True}
    return summary, {'unique_starts': len(starts), 'unique_completions': len(completions),
                     'hidden_successful_completions': hidden_count,
                     'observed_suite_paths': observed_paths, 'expected_suite_paths': expected_paths,
                     'visible_completions_by_suite': {str(k): visible[k] for k in sorted(suites)},
                     'platforms': sorted({suite.get('platform') for suite in suites.values()}),
                     'terminal_event_count': 1, 'non_json_information_lines': non_json_lines}


def read_log(directory, command, channel):
    path = directory / command[channel]
    data = path.read_bytes()
    raw = gzip.decompress(data) if path.suffix == '.gz' else data
    require(digest(raw) == command[channel + '_sha256'], 'Command log hash mismatch: ' + str(path))
    return raw


def audit_command_events(directory, receipt, *, final=False, declared=None, auditor=None):
    tests = receipt['tests']
    require(tests and len(tests) == len(set(tests)), 'Empty or duplicated receipt test selection')
    require(receipt['test_file_count'] == len(tests), 'Receipt test file count mismatch')
    if declared is not None:
        require(tests == declared, 'Receipt does not cover exact harness selection')
    commands = receipt['commands']
    batches = [tests[i:i + 3] for i in range(0, len(tests), 3)]
    require([c['name'] for c in commands] == ['analyze', 'format'] +
            ['test-' + str(i + 1) for i in range(len(batches))], 'Command coverage/order mismatch')
    total, per_batch = Counter(), []
    for item in commands:
        raw = read_log(directory, item, 'stdout')
        read_log(directory, item, 'stderr')
        require(item['executable_before_sha256'] == item['executable_after_sha256'],
                'Command executable changed')
        if auditor is not None:
            auditor.check(Path(item['command'][0]), item['executable_before_sha256'])
        if final:
            require(item['exit_code'] == 0 and item['passed_with_recorded_scope'] is True,
                    'Final command failed: ' + item['name'])
            require(not item.get('timed_out'), 'Final command timed out')
            require(item['command'][0] == receipt['runtime_before']['launchers']['dart']['path'],
                    'Final command did not use the recorded Dart launcher')
            require(Path(item['cwd']).resolve() == REPO / 'packages/quds_office_engine',
                    'Final command used another source package')
        if not item['name'].startswith('test-'):
            if final and item['name'] == 'analyze':
                require(item['command'][1:3] == ['analyze', '--fatal-infos'], 'Strict analysis missing')
            if final and item['name'] == 'format':
                require(item['command'][1:4] == ['format', '--output=none', '--set-exit-if-changed'],
                        'Strict formatting check missing')
            if final:
                scope = {'lib/src/word/serial/odt_document_writer.dart'} | {'test/' + t for t in tests}
                require(scope <= set(item['command']), 'Static check omits declared writer/test scope')
            continue
        batch = batches[int(item['name'].split('-')[1]) - 1]
        require(item['tests'] == batch, 'Test batch differs from declaration')
        arguments = item['command']
        require('--reporter=json' in arguments and '--concurrency=2' in arguments, 'Unexpected runner arguments')
        require(arguments[-len(batch):] == ['test/' + t for t in batch], 'Invoked tests differ from receipt')
        summary, integrity = raw_events(raw, Path(item['cwd']), batch)
        require(item['summary'] == summary, 'Recorded test summary differs from raw events')
        recorded = item['event_integrity']
        require(recorded.get('passed') is True, 'Recorded event integrity failed')
        for key in ('unique_starts', 'unique_completions', 'observed_suite_paths', 'expected_suite_paths',
                    'visible_completions_by_suite', 'terminal_event_count'):
            require(recorded[key] == integrity[key], 'Recorded event identity differs: ' + key)
        if final:
            require(summary['runner_success'] and not summary['failures'] and not summary['errors']
                    and not summary['skipped'] and item.get('expected_skips') == [],
                    'Final selected scope did not pass without skips/errors')
            expected_platform = 'node' if receipt['cohort'] == 'odt-node' else 'vm'
            require(integrity['platforms'] == [expected_platform], 'Unexpected test platform')
            require(('--platform' in arguments and arguments[arguments.index('--platform') + 1] == 'node')
                    if expected_platform == 'node' else '--platform' not in arguments,
                    'Wrong requested test platform')
        total.update(summary['outcomes'])
        per_batch.append({'name': item['name'], 'tests': batch, 'outcomes': summary['outcomes'],
                          'hidden_successful_completions': integrity['hidden_successful_completions'],
                          'runner_success': summary['runner_success']})
    return {'test_file_count': len(tests), 'outcomes': dict(total), 'batches': per_batch}


def audit_versions(directory, receipt, auditor):
    versions = receipt['versions']
    require(set(versions) == {'dart', 'flutter', 'node'}, 'Missing runtime version evidence')
    for name, item in versions.items():
        require(item['exit_code'] == 0, 'Version query failed: ' + name)
        data = []
        for channel in ('stdout', 'stderr'):
            path = directory / (name + '-version.' + channel)
            auditor.check(path, item[channel + '_sha256'])
            data.append(path.read_bytes())
        require(item['command'][0] == receipt['runtime_before']['launchers'][name]['path'],
                'Version and test runtime launchers differ')
        if name == 'flutter':
            require(json.loads(data[0]) == item['metadata'], 'Flutter metadata differs from raw log')
        else:
            require((data[0] + data[1]).decode().strip() == item['version'], 'Version string differs from log')
    flutter = versions['flutter']['metadata']
    require(flutter['frameworkVersion'] == '3.47.8' and flutter['dartSdkVersion'] == '3.13.7'
            and flutter['frameworkRevision'] == FRAMEWORK and flutter['engineRevision'] == ENGINE,
            'Unexpected genuine Flutter/Dart identity')
    require(versions['dart']['version'].startswith('Dart SDK version: 3.13.7 '), 'Unexpected Dart version')
    require(versions['node']['version'] == 'v24.22.1', 'Unexpected Node version')
    return {'flutter': '3.47.8', 'dart': '3.13.7', 'node': 'v24.22.1',
            'framework_revision': FRAMEWORK, 'engine_revision': ENGINE}


def source_tree(source):
    require(git('rev-parse', '--show-object-format').decode().strip() == 'sha1', 'Unsupported Git object format')
    result = {}
    for record in git('ls-tree', '-rz', source).split(b'\0'):
        if record:
            metadata, name = record.split(b'\t', 1)
            mode, kind, identity = metadata.decode().split()
            result[name.decode()] = (mode, kind, identity)
    return result


def audit_source(receipt, source, tree, auditor):
    before = receipt['source_before']
    require(receipt['source_commit'] == source, 'Final cohort ran on a different source commit')
    require(before == receipt['source_after'], 'Source inputs changed during qualification')
    require(set(before) == expected_source_paths(), 'Source manifest does not cover the full declared input scope')
    untracked = set(before) - set(tree)
    require(untracked == {'.dart_tool/package_config.json', 'pubspec.lock'}, 'Unexpected uncommitted source inputs')
    for name, expected in before.items():
        actual = auditor.check(REPO / name, expected)
        if name in tree:
            mode, kind, identity = tree[name]
            require(mode in ('100644', '100755') and kind == 'blob', 'Unsupported source tree member: ' + name)
            require(identity == actual['git_blob'], 'Current source differs from final Git blob: ' + name)
    activated = package_map(REPO / '.dart_tool/package_config.json')
    for package in PACKAGES:
        require(package in activated and activated[package][0] == REPO / 'packages' / package,
                'Activated package resolves outside final checkout: ' + package)
    for name in ('pubspec.lock', LOCK):
        auditor.check(REPO / name, EXPECTED_LOCK)
    require(receipt['lock_sha256'] == EXPECTED_LOCK, 'Dependency lock differs from preserved qualification lock')
    return before, activated


def audit_runtime(directory, receipt, auditor):
    require(receipt['runtime_before'] == receipt['runtime_after'], 'Runtime metadata changed during qualification')
    metadata = receipt['runtime_before']
    raw = gzip.decompress((directory / 'runtime-before.json.gz').read_bytes())
    after = gzip.decompress((directory / 'runtime-after.json.gz').read_bytes())
    require(raw == after, 'Runtime manifests changed during qualification')
    require(digest(raw) == metadata['runtime_input_manifest_sha256'], 'Runtime manifest hash mismatch')
    manifest = json.loads(raw)
    require(len(manifest) == metadata['runtime_input_count'], 'Runtime manifest count mismatch')
    require(set(manifest) == expected_runtime_paths(metadata), 'Runtime manifest omits or adds scoped inputs')
    for name, expected in manifest.items():
        auditor.check(Path(name), expected)
    for item in metadata['launchers'].values():
        require(str(Path(item['path']).resolve()) == item['resolved_path'], 'Runtime launcher resolution changed')
        auditor.check(Path(item['path']), item['sha256'])
    root = Path(metadata['environment']['FLUTTER_ROOT'])
    for member, expected in metadata['sdk_executables_sha256'].items():
        auditor.check(root / member, expected)
    require(git('rev-parse', 'HEAD', cwd=root).decode().strip() == metadata['framework_revision'] == FRAMEWORK,
            'Runtime framework revision mismatch')
    return manifest


def audit_import_closure(tests, sources, runtime, activated):
    covered = {(REPO / p).resolve() for p in sources} | {Path(p).resolve() for p in runtime}
    pending = [REPO / 'packages/quds_office_engine/test' / test for test in tests]
    seen = set()
    # A declaration starts with a URI literal; a variable called `part` followed
    # by a cascade is ordinary Dart code, not a part directive.
    directive = re.compile(r'''(?m)^[ \t]*(?:import|export|part)\s+(?=r?['"])([^;]+);''')
    while pending:
        path = pending.pop().resolve()
        if path in seen:
            continue
        require(path in covered and path.is_file(), 'Import/part is not bound to source/runtime manifest: ' + str(path))
        seen.add(path)
        for match in directive.finditer(path.read_text()):
            for uri in re.findall(r"['\"]([^'\"]+)['\"]", match.group(1)):
                if uri.startswith('dart:'):
                    continue
                if uri.startswith('package:'):
                    package, slash, relative = uri[8:].partition('/')
                    require(slash and package in activated, 'Unresolved package import: ' + uri)
                    target = activated[package][1] / relative
                elif ':' not in uri:
                    target = path.parent / uri
                else:
                    raise AssertionError('Unsupported import URI: ' + uri)
                pending.append(target)
    return len(seen)


def audit_incoming(source, tree=None, auditor=None):
    if auditor is not None:
        for name in ('api-inventory.json', 'git-fetch-inventory.json', 'integration.json'):
            path = HERE / 'incoming' / name
            identity = auditor.identity(path)
            relative = str(path.relative_to(REPO))
            require(relative in tree and identity['git_blob'] == tree[relative][2],
                    'Incoming snapshot differs from final published source tree: ' + name)
    inventories = [read_json(HERE / 'incoming' / name) for name in
                   ('api-inventory.json', 'git-fetch-inventory.json')]
    pairs = {(item['repository'], item['ref'], item['sha'])
             for data in inventories for item in data['refs']}
    named = {(repository, reference) for repository, reference, _ in pairs}
    heads = {sha for _, _, sha in pairs}
    require((len(named), len(pairs), len(heads)) == (240, 241, 162), 'Captured incoming inventory counts changed')
    ancestors = set(git('rev-list', source).decode().splitlines())
    require(heads <= ancestors and BASELINE in ancestors, 'Captured incoming revision missing from final ancestry')
    integration = read_json(HERE / 'incoming/integration.json')
    require(integration['named_references'] == len(named)
            and integration['captured_reference_revision_pairs'] == len(pairs)
            and integration['captured_distinct_heads'] == len(heads), 'Integration summary differs from raw inventories')
    require(set(integration['incoming_maximal_heads']) <= ancestors, 'Incoming maximal head missing')
    return {'named_references': len(named), 'captured_reference_revision_pairs': len(pairs),
            'captured_distinct_heads': len(heads), 'all_captured_heads_are_ancestors': True,
            'prior_checkpoint_is_ancestor': True, 'finite_cutoff': integration['cutoff']}


def audit_prior_evidence(source, tree, auditor):
    directory = 'docs/validation/office-fidelity-resume-20261117'
    prefix = directory + '/'
    baseline = source_tree(BASELINE)
    previous = {name: entry for name, entry in baseline.items() if name.startswith(prefix)}
    final = {name: entry for name, entry in tree.items() if name.startswith(prefix)}
    require(previous and previous == final, 'Prior office-fidelity evidence Git tree changed')
    current = {str(path.relative_to(REPO)) for path in files_below(REPO / directory)}
    require(current == set(previous), 'Prior evidence working-file inventory differs from preserved tree')
    total_bytes = 0
    for name, (mode, kind, blob) in previous.items():
        require(mode in ('100644', '100755') and kind == 'blob', 'Unsupported prior evidence tree member')
        identity = auditor.identity(REPO / name)
        require(identity['git_blob'] == blob, 'Prior evidence current bytes differ: ' + name)
        total_bytes += identity['bytes']
    prior_tree = git('rev-parse', BASELINE + ':' + directory).decode().strip()
    final_tree = git('rev-parse', source + ':' + directory).decode().strip()
    require(prior_tree == final_tree, 'Prior evidence subtree identity differs')
    return {'baseline_commit': BASELINE, 'qualified_source_commit': source,
            'directory': directory, 'baseline_tree': prior_tree, 'final_tree': final_tree,
            'verified_files': len(previous), 'verified_bytes': total_bytes,
            'git_tree_and_current_bytes_identical': True,
            'scope': 'Complete prior office-fidelity-resume validation directory: exact Git subtree, file inventory and current file bytes.'}


def audit_proofing_scope(source, tree, auditor):
    selection_path = HERE / 'proofing-equivalence-scope.json'
    selection = read_json(selection_path)
    reference = '56dc162bf9a1003189e36e1f2a4678620c824546'
    require(selection['qualified_commit'] == reference, 'Unexpected proofing reference commit')
    selected = selection['files']
    require(selection['selected_file_count'] == len(selected) == 85, 'Selected proofing scope changed')
    qualified = source_tree(reference)
    for name, expected in selected.items():
        path = PurePosixPath(name)
        require(not path.is_absolute() and '..' not in path.parts and str(path) == name,
                'Invalid selected proofing path')
        require(name in qualified and name in tree and qualified[name] == tree[name],
                'Selected proofing Git blob/mode differs: ' + name)
        mode, kind, blob = qualified[name]
        require(mode in ('100644', '100755') and kind == 'blob', 'Unsupported selected proofing tree member')
        identity = auditor.check(REPO / name, expected)
        require(identity['git_blob'] == blob, 'Selected proofing current bytes differ from qualified Git blob: ' + name)
    return {'qualified_reference_commit': reference, 'final_source_commit': source,
            'selection': label(selection_path),
            'selection_sha256': auditor.identity(selection_path)['sha256'],
            'selected_files': len(selected), 'different_paths': [],
            'git_blobs_modes_and_current_sha256_identical': True,
            'scope': selection['scope'],
            'whole_historical_import_closure_equivalence_claimed': False}


def audit_archives(restore_root, auditor):
    archives, restored = [], {}
    for index_path in sorted(HERE.rglob('*.json')):
        index = read_json(index_path)
        if not isinstance(index, dict) or not isinstance(index.get('files'), dict) or 'archive' not in index:
            continue
        archive = index_path.parent / index['archive']
        expected_hash = index.get('archive_sha256', index.get('sha256'))
        require(expected_hash, 'Archive index lacks digest: ' + str(index_path))
        identity = auditor.check(archive, expected_hash)
        expected_bytes = index.get('archive_bytes', index.get('bytes'))
        require(expected_bytes is None or expected_bytes == identity['bytes'], 'Archive byte count mismatch')
        auditor.identity(index_path)
        members = index['files']
        require(index.get('file_count', len(members)) == len(members), 'Archive manifest file count mismatch')
        destination = restore_root / str(index_path.relative_to(HERE)).replace('/', '__').removesuffix('.json')
        destination.mkdir()
        observed = set()
        total_bytes = 0
        prefix = index.get('archive_prefix', index.get('prefix', ''))
        if prefix:
            prefix = prefix.rstrip('/') + '/'
        with tarfile.open(archive, 'r:xz') as compressed:
            for member in compressed:
                require(member.isfile(), 'Non-regular evidence archive member: ' + member.name)
                require(member.name.startswith(prefix), 'Archive member prefix mismatch')
                name = member.name[len(prefix):]
                path = PurePosixPath(name)
                require(not path.is_absolute() and '..' not in path.parts and str(path) == name
                        and name not in ('', '.') and name not in observed, 'Unsafe/duplicate archive member: ' + name)
                require(name in members, 'Unindexed archive member: ' + name)
                expected = members[name]
                expected = {'sha256': expected} if isinstance(expected, str) else expected
                handle = compressed.extractfile(member)
                require(handle is not None, 'Unreadable archive member')
                data = handle.read()
                require(digest(data) == expected['sha256'], 'Archived evidence digest mismatch: ' + name)
                require(expected.get('bytes', len(data)) == len(data), 'Archived evidence byte count mismatch')
                target = destination / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                auditor.check(target, expected['sha256'])
                total_bytes += len(data)
                observed.add(name)
        require(observed == set(members), 'Archive is missing indexed evidence files')
        require(index.get('uncompressed_bytes', total_bytes) == total_bytes, 'Uncompressed byte count mismatch')
        restored[str(index_path.relative_to(HERE))] = destination
        archives.append({'index': label(index_path), 'archive': label(archive), 'sha256': expected_hash,
                         'compressed_bytes': identity['bytes'], 'restored_files': len(observed),
                         'restored_bytes': total_bytes, 'all_restored_hashes_verified': True,
                         'restoration_directory': str(destination)})
    require('incoming-validation/manifest.json' in restored, 'Incoming qualification archive missing')
    require(archives, 'No evidence archives found')
    return archives, restored


def audit_historical_incoming(directory):
    summary = read_json(HERE / 'incoming-validation/summary.json')
    totals, files, rows = Counter(), 0, []
    for declaration in summary['cohorts']:
        path = directory / declaration['receipt']
        receipt = read_json(path)
        result = audit_command_events(path.parent, receipt)
        require(result['outcomes'] == declaration['outcomes'], 'Incoming cohort count differs from raw events')
        require(result['test_file_count'] == declaration['test_file_count'], 'Incoming cohort file count mismatch')
        require(receipt['source_commit'] == declaration['source_commit'], 'Incoming source summary mismatch')
        require(receipt['passed_with_recorded_scope'] == declaration['passed_with_recorded_scope'],
                'Incoming qualification status summary mismatch')
        require(receipt['source_before'] == receipt['source_after']
                and receipt['runtime_before'] == receipt['runtime_after'], 'Historical unchanged-input guard failed')
        totals.update(result['outcomes'])
        files += result['test_file_count']
        rows.append({'name': declaration['name'], 'source_commit': receipt['source_commit'],
                     'outcomes': result['outcomes'], 'file_executions': result['test_file_count'],
                     'recorded_static_and_test_pass': receipt['passed_with_recorded_scope']})
    require(dict(totals) == summary['dart_flutter_execution_outcomes'] and files == summary['file_executions'],
            'Incoming aggregate differs from raw events')
    correction = read_json(directory / summary['engine_static_requalification'])
    require(digest((directory / correction['patch']).read_bytes()) == correction['patch_sha256'],
            'Incoming static correction patch mismatch')
    corrected = read_json(directory / correction['correction_static_evidence'])
    require(corrected['source_commit'] == correction['corrected_source_commit']
            and all(item['exit_code'] == 0 for item in corrected['commands'][:2]),
            'Incoming corrected strict gates did not pass')
    python_path = directory / summary['ancillary_python']['receipt']
    python = read_json(python_path)
    logs = []
    for channel in ('stdout', 'stderr'):
        raw = gzip.decompress((python_path.parent / (channel + '.gz')).read_bytes())
        require(digest(raw) == python[channel + '_sha256'], 'Ancillary Python log hash mismatch')
        logs.append(raw.decode())
    raw_python = '\n'.join(logs)
    cases = re.findall(r'(?m)^(test_\S+ \([^\n]+\)) \.\.\. ok$', raw_python)
    footer = re.findall(r'(?m)^Ran (\d+) tests in [^\n]+$', raw_python)
    require(len(cases) == len(set(cases)) == python['reported_test_count']
            == summary['ancillary_python']['reported_tests'] and footer == [str(len(cases))],
            'Ancillary Python raw case/footer counts disagree')
    require(raw_python.rstrip().endswith('\nOK') and python['reported_skips'] == 0
            and python['passed'] is True and python['exit_code'] == 0
            and python['source_before'] == python['source_after'], 'Ancillary Python scope did not pass')
    return {'cohorts': rows, 'outcomes': dict(totals), 'file_executions': files,
            'ancillary_python_successes': len(cases), 'ancillary_python_skips': 0,
            'corrected_engine_static_gates_verified': True,
            'scope': 'Historical incoming executions, separate from final source qualification. Original engine static failure and native inference skip remain explicit.'}


def archive_binding(required, archives):
    """Require every accepted receipt/log/output in one reconstructible archive."""
    for archive in archives:
        index = read_json(REPO / archive['index'])
        members = {name: value if isinstance(value, str) else value['sha256']
                   for name, value in index['files'].items()}
        if all(any((name == required_name or name.endswith('/' + required_name)) and value == expected
                   for name, value in members.items()) for required_name, expected in required.items()):
            return {'index': archive['index'], 'verified_required_files': len(required),
                    'archive_sha256': archive['sha256']}
    raise AssertionError('Accepted final evidence is not fully bound to an indexed archive: ' +
                         ', '.join(list(required)[:3]))


def accepted_archive_bindings(qualification, consumer, archives):
    bindings = {}
    for cohort in ('odt-vm', 'odt-node'):
        directory = qualification / cohort
        receipt = read_json(directory / 'receipt.json')
        names = {'receipt.json', 'runtime-before.json.gz', 'runtime-after.json.gz'}
        names |= {name + '-version.' + channel for name in receipt['versions']
                  for channel in ('stdout', 'stderr')}
        names |= {item[channel] for item in receipt['commands'] for channel in ('stdout', 'stderr')}
        required = {cohort + '/' + name: digest((directory / name).read_bytes()) for name in names}
        bindings[cohort] = archive_binding(required, archives)
    receipt = read_json(consumer / 'receipt.json')
    required = dict(receipt['output_hashes'])
    required['receipt.json'] = digest((consumer / 'receipt.json').read_bytes())
    required['inputs.json.gz'] = receipt['inputs_sha256']
    bindings['consumer'] = archive_binding(required, archives)
    return bindings


def audit_consumer(directory, source, tree, auditor):
    receipt_path = directory / 'receipt.json'
    receipt = read_json(receipt_path)
    require(receipt.get('passed') is True and not receipt.get('fatal_error'), 'Final consumer receipt did not pass')
    require(receipt['source_head'] == source, 'Consumer used another source commit')
    require(Path(receipt['source_root']).resolve() == REPO, 'Consumer used another source checkout')
    require(all(receipt[key] is True for key in ('source_unchanged', 'runtime_unchanged', 'fixtures_unchanged')),
            'Consumer unchanged-input guard failed')
    auditor.check(directory / 'inputs.json.gz', receipt['inputs_sha256'])
    inputs = json.loads(gzip.decompress((directory / 'inputs.json.gz').read_bytes()))
    require(receipt['input_counts'] == {name: len(values) for name, values in inputs.items()},
            'Consumer input counts mismatch')
    for category, values in inputs.items():
        for name, expected in values.items():
            path = Path(name)
            actual = auditor.check(path, expected)
            if category == 'source' and path.is_relative_to(REPO):
                relative = str(path.relative_to(REPO))
                if relative in tree:
                    require(actual['git_blob'] == tree[relative][2], 'Consumer source differs from final Git tree: ' + relative)
                else:
                    require(relative in ('.dart_tool/package_config.json', 'pubspec.lock'), 'Untracked consumer source input')
    for name, expected in receipt['output_hashes'].items():
        auditor.check(directory / name, expected)
    specs = read_json(directory / 'fixtures/fixtures.json')
    names = [item['name'] for item in specs]
    require(len(names) == len(set(names)) and names == [f['name'] for f in receipt['fixtures']],
            'Consumer fixture inventory mismatch')
    require(all(f['passed'] is True and not f['schema']['failures'] for f in receipt['fixtures']),
            'Consumer fixture failure')
    parts = {'content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml'}
    require(all(set(f['schema']['passed_parts']) == parts and len(f['schema']['passed_parts']) == 4
                for f in receipt['fixtures']), 'Incomplete official-schema part coverage')
    summary = {'fixtures': len(names), 'passed': len(names), 'failed': 0,
               'schema_parts_passed': 4 * len(names), 'schema_parts_total': 4 * len(names)}
    require(receipt['summary'] == summary, 'Consumer summary count mismatch')
    require(all(c['exit_code'] == 0 for c in receipt['commands']), 'Consumer tool command failed')
    return {'receipt': label(receipt_path), 'receipt_sha256': auditor.identity(receipt_path)['sha256'],
            'summary': summary, 'input_counts': receipt['input_counts'],
            'output_hashes_verified': len(receipt['output_hashes']),
            'fixture_names': names,
            'scope': 'Independent inventory, receipt and artifact hash review; semantic assertions remain in the source-bound consumer checker.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, help='Exact final published product-source commit')
    parser.add_argument('--qualification', type=Path, default=HERE / 'qualification')
    parser.add_argument('--consumer', required=True, type=Path, help='Accepted final consumer directory, original or restored')
    parser.add_argument('--output', type=Path, default=HERE / 'independent-review.json')
    parser.add_argument('--restore-root', type=Path, help='Fresh destination for independent archive reconstruction')
    args = parser.parse_args()
    result = {'started_at_utc': datetime.now(timezone.utc).isoformat(), 'source_commit': args.source,
              'passed': False, 'github_actions_queried_or_awaited': False,
              'scope': 'Independent raw-event reconstruction, exact source/runtime hashes, incoming ancestry and evidence archive reconstruction.'}
    auditor = FileAudit()
    try:
        result['auditor_sha256'] = auditor.identity(Path(__file__))['sha256']
        require(re.fullmatch('[0-9a-f]{40}', args.source) is not None, 'Use a full source commit SHA')
        result['source_tree'] = git('rev-parse', args.source + '^{tree}').decode().strip()
        result['checkout_head'] = git('rev-parse', 'HEAD').decode().strip()
        require(args.source in set(git('rev-list', 'HEAD').decode().splitlines()), 'Final source is not current-checkout ancestry')
        tree = source_tree(args.source)
        source_union, runtime_union, rows = {}, {}, []
        declarations = declared_cohorts()
        for name, selected in declarations.items():
            directory = args.qualification.resolve() / name
            receipt = read_json(directory / 'receipt.json')
            require(receipt['cohort'] == name and receipt.get('passed_with_recorded_scope') is True,
                    'Incomplete or failed accepted final cohort: ' + name)
            require(all(receipt.get(key) is True for key in
                        ('source_unchanged', 'runtime_unchanged', 'lock_unchanged', 'head_unchanged')),
                    'Final cohort unchanged-input guard failed')
            events = audit_command_events(directory, receipt, final=True, declared=selected, auditor=auditor)
            versions = audit_versions(directory, receipt, auditor)
            sources, activated = audit_source(receipt, args.source, tree, auditor)
            runtime = audit_runtime(directory, receipt, auditor)
            if source_union:
                require(source_union == sources and runtime_union == runtime, 'Final cohorts used different input sets/bytes')
            source_union.update(sources)
            runtime_union.update(runtime)
            rows.append({'cohort': name, 'receipt': label(directory / 'receipt.json'),
                         'receipt_sha256': auditor.identity(directory / 'receipt.json')['sha256'],
                         **events, 'versions': versions, 'source_inputs': len(sources), 'runtime_inputs': len(runtime),
                         'import_closure_files': audit_import_closure(selected, sources, runtime, activated)})
        result['final_cohorts'] = rows
        result['final_execution_outcomes'] = dict(sum((Counter(r['outcomes']) for r in rows), Counter()))
        result['final_file_executions'] = sum(r['test_file_count'] for r in rows)
        result['node_repeats_selected_vm_cases'] = True
        result['unique_final_source_inputs'] = len(source_union)
        result['unique_final_runtime_inputs'] = len(runtime_union)
        result['incoming_ancestry'] = audit_incoming(args.source, tree, auditor)
        result['prior_evidence_preservation'] = audit_prior_evidence(args.source, tree, auditor)
        result['selected_proofing_equivalence'] = audit_proofing_scope(args.source, tree, auditor)
        result['consumer'] = audit_consumer(args.consumer.resolve(), args.source, tree, auditor)
        restore_root = args.restore_root.resolve() if args.restore_root else Path(tempfile.mkdtemp(
            prefix='office-fidelity-independent-', dir=REPO.parent))
        if args.restore_root:
            restore_root.mkdir(parents=True, exist_ok=False)
        result['archives'], restored = audit_archives(restore_root, auditor)
        result['archive_restored_file_count'] = sum(item['restored_files'] for item in result['archives'])
        result['accepted_final_archive_bindings'] = accepted_archive_bindings(
            args.qualification.resolve(), args.consumer.resolve(), result['archives'])
        result['historical_incoming'] = audit_historical_incoming(restored['incoming-validation/manifest.json'])
        require(result['checkout_head'] == git('rev-parse', 'HEAD').decode().strip(),
                'Checkout HEAD changed during independent audit')
        auditor.stable()
        result['current_files_hash_verified'] = len(auditor.identities)
        result['passed'] = True
        result['limits'] = [
            'Selected cohorts and authored consumer fixtures; not complete package suites or universal office round trips.',
            'Node executions repeat selected VM cases and do not increase the unique-case count.',
            'Archived failed/development attempts are hash-verified historical evidence and are excluded from final passing totals.',
            'Historical incoming source/runtime receipts are reviewed as recorded executions, not asserted to equal final product bytes.',
            'Only the saved 85-file proofing selection is asserted equal to corrected source 56dc; this is not historical whole-import-closure equivalence.',
            'Hash review does not repeat LibreOffice conversion or replace the consumer checker semantic assertions.',
        ]
    except Exception as error:
        result['error'] = repr(error)
    finally:
        result['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ('passed', 'source_commit', 'error',
          'final_execution_outcomes', 'final_file_executions', 'archive_restored_file_count') if key in result}, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
