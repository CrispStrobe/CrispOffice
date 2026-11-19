#!/usr/bin/env python3
"""Independently audit a completed Mail store gate; never execute product tests.

The auditor reads raw reporter events, immutable Git blobs, exact command
arguments, runtime recovery receipts and actual current files. It does not
import either qualification runner or its reporter parser.
"""
from __future__ import annotations

import argparse
import ast
from collections import Counter
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urljoin, urlsplit
import yaml


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_hash(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


class StoreAudit:
    def __init__(self, args):
        self.args = args
        self.repo = args.repo.resolve()
        self.gate = args.gate.resolve()
        self.runtime = args.runtime.resolve()
        self.outer = args.outer.resolve()
        self.issues = []
        self.report = {}
        self.tree = {}

    def check(self, condition, message):
        if not condition:
            self.issues.append(message)

    def git(self, *args):
        return subprocess.check_output(['git', '--no-replace-objects', *args], cwd=self.repo)

    def load(self, path):
        return json.loads(Path(path).read_bytes())

    def tests(self, package):
        prefix = 'packages/' + package + '/'
        return sorted(path[len(prefix):] for path in self.tree
                      if path.startswith(prefix + 'test/') and path.endswith('_test.dart'))

    def dependency_closure(self, package_rows):
        """Read effective resolved manifests, including root test dependencies."""
        config = self.repo / '.dart_tool/package_config.json'
        resolved = {row['name']: row for row in package_rows}
        roots = {'quds_mail_core', 'quds_mail_store'}
        pending = list(roots)
        inspected = {}
        while pending:
            name = pending.pop()
            if name in inspected:
                continue
            self.check(name in resolved, 'dependency package is resolved: ' + name)
            if name not in resolved:
                continue
            uri = urlsplit(urljoin(config.as_uri(), resolved[name]['rootUri']))
            self.check(uri.scheme == 'file' and not (uri.netloc or uri.query or uri.fragment), 'local dependency root: ' + name)
            root = Path(unquote(uri.path)).resolve()
            path = root / 'pubspec.yaml'
            raw = path.read_bytes()
            manifest = yaml.safe_load(raw)
            self.check(manifest['name'] == name, 'resolved manifest package identity: ' + name)
            children = set((manifest.get('dependencies') or {}).keys())
            if name in roots:
                children.update((manifest.get('dev_dependencies') or {}).keys())
            inspected[name] = {'name': name, 'manifest': str(path), 'sha256': digest(raw),
                               'dependencies': sorted(children), 'include_dev_dependencies': name in roots}
            pending.extend(sorted(children - inspected.keys()))
        excluded = {'quds_mail_transport', 'enough_mail'}
        self.check(not excluded.intersection(inspected), 'core/store declared execution and test dependency closure excludes changed transport/parser packages')
        imported = set()
        for path in self.tree:
            if path.endswith('.dart') and path.startswith(('packages/quds_mail_core/lib/', 'packages/quds_mail_core/test/', 'packages/quds_mail_core/tool/',
                                                         'packages/quds_mail_store/lib/', 'packages/quds_mail_store/test/', 'packages/quds_mail_store/tool/')):
                raw = (self.repo / path).read_text()
                imported.update(re.findall(r"\b(?:import|export)\s+['\"]package:([^/]+)/", raw))
                self.check(not re.search(r"\b(?:import|export|part)\s+['\"][^'\"]*(?:quds_mail_transport|enough_mail)", raw), 'no direct changed-package reference: ' + path)
        self.check(imported <= set(inspected), 'all core/store static package imports lie in declared closure')
        return {'roots': sorted(roots), 'packages': [inspected[n] for n in sorted(inspected)],
                'package_count': len(inspected), 'direct_static_package_imports': sorted(imported),
                'excluded_changed_packages': sorted(excluded), 'changed_packages_absent': not excluded.intersection(inspected),
                'yaml_parser_version': yaml.__version__}

    def recount(self, entry, expected_tests, platform):
        name = entry['name']
        cwd = Path(entry['cwd'])
        raw = (self.gate / entry['log']).read_bytes()
        events = []
        for number, line in enumerate(raw.decode('utf-8').splitlines(), 1):
            line = line.strip()
            # Only actual build-hook progress may precede a reporter record.
            while line.startswith(('Running build hooks...', 'Running link hooks...')):
                prefix = next(p for p in ('Running build hooks...', 'Running link hooks...') if line.startswith(p))
                line = line[len(prefix):].lstrip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except ValueError:
                self.check(False, f'{name}: malformed JSON at line {number}')
                continue
            self.check(isinstance(event, dict) and isinstance(event.get('type'), str),
                       f'{name}: invalid event object at line {number}')
            if isinstance(event, dict) and isinstance(event.get('type'), str):
                events.append(event)
        self.check(bool(events), name + ': empty reporter')
        if not events:
            return {'name': name, 'passed': 0, 'failed': 0, 'skipped': 0, 'suite_paths': []}
        kinds = Counter(event['type'] for event in events)
        self.check(kinds['start'] == kinds['done'] == 1, name + ': exact reporter lifecycle count')
        self.check(events[0]['type'] == 'start' and events[-1]['type'] == 'done'
                   and events[-1].get('success') is True, name + ': successful ordered reporter terminal')
        self.check(kinds['error'] == 0, name + ': reporter errors')
        suites, starts, completions = {}, {}, {}
        terminal_seen = False
        start_seen = False
        for event in events:
            kind = event['type']
            self.check(not terminal_seen, name + ': event after terminal')
            if kind == 'start':
                self.check(not start_seen, name + ': duplicate reporter start')
                start_seen = True
            else:
                self.check(start_seen, name + ': event before reporter start')
            if kind == 'suite':
                suite = event['suite']
                self.check(type(suite.get('id')) is int and isinstance(suite.get('path'), str), name + ': valid suite identity')
                self.check(suite['id'] not in suites, name + ': unique suite id')
                self.check(suite.get('platform') == platform, name + ': exact suite platform')
                suites[suite['id']] = str((cwd / suite['path']).resolve())
            elif kind == 'testStart':
                case = event['test']
                ident = case['id']
                self.check(type(ident) is int and type(case.get('suiteID')) is int
                           and isinstance(case.get('name'), str), name + ': valid test identity')
                self.check(ident not in starts and ident not in completions, name + ': unique test start')
                starts[ident] = case
            elif kind == 'testDone':
                ident = event['testID']
                self.check(ident in starts and ident not in completions, name + ': unique ordered test completion')
                self.check(type(event.get('hidden')) is bool and type(event.get('skipped')) is bool
                           and event.get('result') in {'success', 'failure', 'error'}, name + ': valid completion fields')
                completions[ident] = event
            elif kind == 'done':
                terminal_seen = True
        self.check(set(starts) == set(completions), name + ': no unfinished or orphan cases')
        expected = {str((cwd / path).resolve()) for path in expected_tests}
        self.check(set(suites.values()) == expected and len(suites) == len(expected), name + ': exact requested suite inventory')
        substantive, runner_rows = [], []
        hidden = 0
        per_suite = Counter()
        counts = Counter()
        for ident, start in starts.items():
            end = completions.get(ident)
            if end is None:
                continue
            self.check(start['suiteID'] in suites, name + ': case references known suite')
            self.check(end.get('result') == 'success' and end.get('skipped') is False
                       and not start.get('metadata', {}).get('skip'), name + ': every case and fixture succeeds without skip: ' + start['name'])
            row = {'name': start['name'], 'suite_id': start['suiteID'],
                   'result': end.get('result'), 'skipped': end.get('skipped'), 'hidden': end.get('hidden')}
            if not end.get('hidden') and not start['name'].startswith('loading '):
                runner_rows.append(row)
            excluded = (end.get('hidden') or start['name'].startswith('loading ')
                        or re.search(r'(?:^| )\((?:setUpAll|tearDownAll)\)$', start['name']))
            if excluded:
                hidden += 1
                continue
            suite = suites.get(start['suiteID'])
            substantive.append({'id': ident, 'name': start['name'], 'suite': suite,
                                'platform': platform, 'result': end.get('result'), 'skipped': end.get('skipped')})
            per_suite[suite] += 1
            counts['passed'] += int(end.get('result') == 'success' and not end.get('skipped'))
            counts['failed'] += int(end.get('result') in {'failure', 'error'})
            counts['skipped'] += int(bool(end.get('skipped')))
        self.check(set(per_suite) == expected, name + ': no empty requested suites')
        details_path = self.gate / entry['case_list']
        details = self.load(details_path)
        self.check(details['cases'] == runner_rows, name + ': recorded raw case inventory')
        # A visible fixture would be reported separately, never inflated into this audit's application count.
        self.check(len(runner_rows) == len(substantive), name + ': runner excludes all loading/setup/teardown fixtures')
        for key in ('passed', 'failed', 'skipped'):
            self.check(counts[key] == entry['tests'][key] == details[key], name + ': independently derived ' + key)
        self.check(details['valid'] is True and entry['tests']['valid'] is True, name + ': accepted recorded reporter status')
        self.check(details['terminal_success'] is True and details['start_events'] == details['terminal_events'] == 1, name + ': recorded reporter lifecycle')
        for key in ('errors', 'all_failed', 'all_skipped', 'excluded_failed', 'excluded_skipped', 'incomplete', 'protocol_errors'):
            self.check(details[key] == entry['tests'][key] == 0, name + ': recorded zero ' + key)
        return {'name': name, 'platform': platform, 'suites': len(expected),
                'suite_paths': sorted(str(Path(path).relative_to(self.repo)) for path in expected),
                'passed': counts['passed'], 'failed': counts['failed'], 'skipped': counts['skipped'],
                'excluded_successful_fixture_events': hidden, 'raw_log_sha256': digest(raw),
                'case_file_sha256': file_hash(details_path), 'cases': substantive}

    def run(self):
        source = self.git('rev-parse', self.args.source + '^{commit}').decode().strip()
        target = self.git('rev-parse', (self.args.target_source or self.args.source) + '^{commit}').decode().strip()
        receipt = self.load(self.gate / 'receipt.json')
        runtime = self.load(self.runtime / 'runtime.json')
        for item in self.git('ls-tree', '-rz', source).split(b'\0'):
            if item:
                metadata, path = item.split(b'\t', 1)
                mode, kind, blob = metadata.decode().split()
                self.tree[path.decode()] = {'mode': mode, 'kind': kind, 'blob': blob}
        target_tree = {}
        for item in self.git('ls-tree', '-rz', target).split(b'\0'):
            if item:
                metadata, path = item.split(b'\t', 1)
                mode, kind, blob = metadata.decode().split()
                target_tree[path.decode()] = {'mode': mode, 'kind': kind, 'blob': blob}
        self.check(receipt['status'] == 'PASS' and receipt['active_check'] is None
                   and bool(receipt.get('finished_utc')), 'complete successful store gate')
        self.check(receipt['starting_commit'] == source, 'exact store source commit')
        self.check(receipt['source_unchanged'] is True and receipt['source_before'] == receipt['source_after'], 'unchanged store source manifests')
        outer_raw = (self.outer / 'execution.json').read_bytes()
        outer = json.loads(outer_raw)
        self.check(outer['status'] == 'PASS' and bool(outer.get('finished_at_utc')), 'complete successful outer qualification envelope')
        self.check(outer['source_commit'] == source and outer['source_tree'] == self.git('rev-parse', source + '^{tree}').decode().strip(), 'outer exact execution source/tree')
        for field in ['source_unchanged', 'runtime_unchanged', 'source_head_unchanged', 'tracked_worktree_clean_after']:
            self.check(outer[field] is True, 'outer stability: ' + field)
        source_before = self.load(self.outer / 'source-before.json')
        source_after = self.load(self.outer / 'source-after.json')
        runtime_before = self.load(self.outer / 'runtime-before.json')
        runtime_after = self.load(self.outer / 'runtime-after.json')
        self.check(source_before == source_after and runtime_before == runtime_after, 'outer full source/runtime inventories unchanged')
        native_plan = json.loads(self.git('show', source + ':' + self.args.native_plan))
        node_plan = json.loads(self.git('show', source + ':' + self.args.node_plan))
        outer_expected_sources = {
            path for path in self.tree if path.startswith(('packages/', 'apps/', 'third_party/', 'tools/mail/'))
            or ('/' not in path and Path(path).suffix in {'.yaml', '.lock'}) or path == '.fvmrc'
        }
        outer_expected_sources.update([self.args.driver, self.args.native_plan, self.args.node_plan,
                                       'docs/validation/document-review-notes-20261118/run_checks.py',
                                       'docs/validation/document-review-notes-20261118/test_run_checks.py'])
        outer_expected_sources.update(native_plan['extra_inputs'])
        self.check(set(source_before) == outer_expected_sources, 'exact complete outer source inventory')
        for path, expected in source_before.items():
            self.check(digest(self.git('show', source + ':' + path)) == expected == file_hash(self.repo / path), 'outer immutable/current source binding: ' + path)
        retained = self.load(self.runtime / 'retained-inputs.json')
        outer_expected_runtime = {'runtime/' + name: self.runtime / name for name in retained}
        for name in ['runtime.json', 'retained-inputs.json', 'pub-cache-receipt.json', 'cache-omissions.json', 'archive-members.json', 'env.sh', 'bin/dart', 'bin/flutter']:
            outer_expected_runtime['runtime/' + name] = self.runtime / name
        outer_expected_runtime.update({'additional/' + name: Path(name) for name in runtime['additional_inputs']})
        outer_expected_runtime['workspace/package_config.json'] = self.repo / '.dart_tool/package_config.json'
        outer_expected_runtime['sdk/flutter_tools/package_config.json'] = self.runtime / 'flutter/packages/flutter_tools/.dart_tool/package_config.json'
        outer_expected_runtime['python/executable'] = Path(outer['python_executable'])
        for run in outer['runs']:
            program = run['command'][0]
            if Path(program).name.startswith('python'):
                self.check(Path(program).resolve() == Path(outer['python_executable']), 'outer command Python identity: ' + run['name'])
        self.check(set(runtime_before) == set(outer_expected_runtime), 'exact complete outer runtime inventory including Python')
        for name, path in outer_expected_runtime.items():
            self.check(file_hash(path) == runtime_before.get(name), 'outer runtime input readback: ' + name)
        for name, bound in retained.items():
            self.check(runtime_before['runtime/' + name] == bound['sha256'], 'retained runtime manifest binding: ' + name)
        for run in outer['runs']:
            self.check(run['accepted'] is True and run['exit_code'] == 0, 'outer successful command: ' + run['name'])
            self.check(file_hash(self.outer / run['log']) == run['log_sha256'], 'outer raw log binding: ' + run['name'])
            if 'receipt' in run:
                self.check(file_hash(self.outer / run['receipt']) == run['receipt_sha256'], 'outer child receipt binding: ' + run['name'])
        store_runs = [run for run in outer['runs'] if run['name'] == 'core-store']
        self.check(len(store_runs) == 1, 'exactly one Store execution in outer envelope')
        store_run = store_runs[0]
        self.check(self.outer / store_run['receipt'] == self.gate / 'receipt.json', 'outer binds this exact Store receipt')
        expected_store_command = [str(self.repo / 'tools/mail/check_store.py'), '--flutter-sdk', str(self.runtime / 'flutter'), '--offline', '--direct-tests', '--command-timeout']
        self.check(store_run['command'][1:1 + len(expected_store_command)] == expected_store_command and store_run['command'][-2:] == ['--output', str(self.gate)], 'outer exact Store invocation')
        self.check(int(store_run['command'][1 + len(expected_store_command)]) > 0, 'bounded Store child commands')
        self.check(outer['runtime_receipt_sha256'] == file_hash(self.runtime / 'runtime.json'), 'outer runtime recovery receipt binding')
        expected_inputs = {'.fvmrc', 'analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock',
                           'tools/mail/check_store.py', 'tools/mail/check_reader.py', 'tools/mail/test_check_store.py'}
        for package in ('quds_mail_core', 'quds_mail_store'):
            prefix = 'packages/' + package + '/'
            expected_inputs.add(prefix + 'pubspec.yaml')
            expected_inputs.update(path for path in self.tree if path.startswith(tuple(prefix + x + '/' for x in ('lib', 'test', 'tool')))
                                   and not any(part in {'.dart_tool', 'build', '__pycache__'} for part in Path(path).parts))
        inputs = receipt['source_before']
        self.check(set(inputs) == expected_inputs, 'complete exact store source scope')
        self.check(all(target_tree.get(path) == self.tree[path] for path in expected_inputs), 'every core/store source input has identical blob and mode in the final source')
        final_scoped_paths = {path for path in target_tree if path in expected_inputs or
                              path.startswith(('packages/quds_mail_core/lib/', 'packages/quds_mail_core/test/', 'packages/quds_mail_core/tool/',
                                               'packages/quds_mail_store/lib/', 'packages/quds_mail_store/test/', 'packages/quds_mail_store/tool/'))}
        self.check(final_scoped_paths == expected_inputs, 'no added/removed final-source core/store execution inputs')
        query = ''.join(self.tree[path]['blob'] + '\n' for path in inputs).encode()
        result = subprocess.run(['git', '--no-replace-objects', 'cat-file', '--batch'], cwd=self.repo,
                                input=query, stdout=subprocess.PIPE, check=True)
        stream = io.BytesIO(result.stdout)
        source_rows = []
        for path, expected_hash in inputs.items():
            blob, kind, size = stream.readline().decode().strip().split()
            data = stream.read(int(size))
            self.check(stream.read(1) == b'\n', 'Git blob record boundary')
            self.check(blob == self.tree[path]['blob'] and kind == 'blob', 'Git blob identity: ' + path)
            self.check(digest(data) == expected_hash == file_hash(self.repo / path), 'exact frozen/current source bytes: ' + path)
            source_rows.append({'path': path, 'git_blob': blob, 'mode': self.tree[path]['mode'], 'sha256': expected_hash})
        self.check(stream.read() == b'', 'Git blob stream has no trailing data')

        launcher = receipt['direct_launcher_inputs_before']
        self.check(launcher == receipt['direct_launcher_inputs_after'] and not receipt.get('runtime_inputs_changed'), 'unchanged direct launcher inputs')
        for name, expected in launcher.items():
            path = Path(name)
            self.check(not path.is_symlink(), 'launcher/native input not redirected: ' + name)
            self.check((file_hash(path) if path.is_file() else None) == expected and
                       (expected is not None or not path.exists()), 'current launcher/native input: ' + name)
        config = self.repo / '.dart_tool/package_config.json'
        packages = self.load(config)['packages']
        closure = self.dependency_closure(packages)
        selected = [p for p in packages if p['name'] == 'test']
        self.check(len(selected) == 1, 'unique resolved package:test')
        uri = urlsplit(urljoin(config.as_uri(), selected[0]['rootUri']))
        self.check(uri.scheme == 'file' and not (uri.netloc or uri.query or uri.fragment), 'local exact package:test URI')
        test_entry = Path(unquote(uri.path)).resolve() / 'bin/test.dart'
        archives = self.load(self.runtime / 'pub-cache-receipt.json')
        test_packages = [p for p in archives if p['name'] == 'test' and p['verified'] is True]
        self.check(len(test_packages) == 1 and test_entry.parent.parent == self.runtime / 'pub-cache/hosted/pub.dev' / ('test-' + test_packages[0]['version']), 'verified hosted test launcher')
        self.check(str(test_entry) in launcher and str(config) in launcher, 'launcher/config explicitly bound')
        mapping_path = self.repo / '.dart_tool/native_assets.yaml'
        mapping = json.loads('\n'.join(line for line in mapping_path.read_text().splitlines() if not line.lstrip().startswith('#')))
        native_inputs = {str(mapping_path), str(config), str(test_entry)}
        sqlite_found = False
        for assets in mapping['native-assets'].values():
            for name, location in assets.items():
                self.check(len(location) == 2 and location[0] == 'absolute', 'absolute native mapping')
                native_inputs.add(location[1])
                self.check(location[1] in launcher and runtime['additional_inputs'].get(location[1]) == launcher[location[1]], 'native mapping bound to runtime receipt')
                if name == 'package:sqlite3/src/ffi/libsqlite3.g.dart':
                    sqlite_found = True
                    self.check(launcher[location[1]] == '0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b', 'pinned SQLite native library')
        self.check(sqlite_found, 'actual SQLite mapping present')
        for package in ('quds_mail_core', 'quds_mail_store'):
            for directory in (self.repo / 'packages' / package, self.repo / 'packages'):
                native_inputs.add(str(directory / '.dart_tool/native_assets.yaml'))
        self.check(set(launcher) == native_inputs, 'complete launcher/native/shadowing inventory')
        self.check(runtime['status'] == 'ready' and runtime['archive']['verified'] is True, 'ready verified runtime receipt')
        self.check(runtime['workspace_lock_sha256'] == inputs['pubspec.lock'], 'runtime locked dependency identity')
        for name, expected in runtime['executables_sha256'].items():
            self.check(file_hash(Path(name)) == expected, 'runtime executable: ' + name)
        for name, expected in runtime['additional_inputs'].items():
            self.check(file_hash(Path(name)) == expected, 'runtime additional input: ' + name)
        for run in runtime['runs']:
            self.check(run['exit_code'] == 0 and file_hash(Path(run['log'])) == run['log_sha256'], 'actual setup command/log: ' + run['name'])
            if run['name'] == 'native-assets-smoke':
                self.check(b'in-memory FTS5 passed' in Path(run['log']).read_bytes(), 'genuine SQLite FTS5 smoke')
        self.check(any(r['name'] == 'native-assets-smoke' for r in runtime['runs']), 'package-owned native smoke included')

        dart = str(self.runtime / 'flutter/bin/cache/dart-sdk/bin/dart')
        base = [dart, '--disable-dart-dev', '--packages=' + str(config), str(test_entry)]
        core = self.repo / 'packages/quds_mail_core'
        store = self.repo / 'packages/quds_mail_store'
        core_tests = self.tests('quds_mail_core')
        store_tests = [p for p in self.tests('quds_mail_store') if p.count('/') == 1 and p != 'test/browser_problem_test.dart']
        portable = ['test/codec_test.dart', 'test/platform_configuration_test.dart', 'test/browser_problem_test.dart']
        groups = {'core-vm': (core, core_tests, 'vm'), 'core-node': (core, core_tests, 'node'),
                  'store-vm': (store, store_tests, 'vm'), 'portable-node': (store, portable, 'node')}
        names = ['runtime', 'runner-regressions', 'locked-resolution', 'core-analysis', 'store-analysis',
                 'format', 'core-vm', 'core-node', 'store-vm', 'portable-node', 'browser-entry', 'browser-worker', 'whitespace']
        self.check([r['name'] for r in receipt['checks']] == names, 'exact complete 13-command store gate')
        commands = {
            'runtime': [dart, '--version'],
            'locked-resolution': [dart, 'pub', 'get', '--enforce-lockfile', '--offline'],
            'core-analysis': [dart, 'analyze', '--fatal-infos'],
            'store-analysis': [dart, 'analyze', '--fatal-infos'],
            'format': [dart, 'format', '--output=none', '--set-exit-if-changed', str(core / 'lib'), str(core / 'test'), str(store / 'lib'), str(store / 'test'), str(store / 'tool')],
            'core-vm': base + ['--compiler=kernel', '--platform', 'vm', '--reporter', 'json'],
            'core-node': base + ['--platform', 'node', '--reporter', 'json'],
            'store-vm': base + ['--compiler=kernel', '--platform', 'vm', '--reporter', 'json', '--concurrency=2', *store_tests],
            'portable-node': base + ['--platform', 'node', '--reporter', 'json', *portable],
            'browser-entry': [dart, 'compile', 'js', 'tool/browser_compile_probe.dart', '-o', str(self.gate / 'browser-entry.js')],
            'browser-worker': [dart, 'compile', 'js', 'tool/mail_store_worker.dart', '-o', str(self.gate / 'browser-worker.js')],
            'whitespace': ['git', 'diff', '--check', 'HEAD'],
        }
        results, controls, outputs = [], None, []
        for entry in receipt['checks']:
            name = entry['name']
            raw = (self.gate / entry['log']).read_bytes()
            self.check(entry['status'] == 'PASS' and entry['exit_code'] == 0 and not entry.get('timed_out'), name + ': successful completed command')
            self.check(digest(raw) == entry['log_sha256'], name + ': raw log hash')
            self.check(isinstance(entry['timeout_seconds'], (int, float)) and 0 < entry['timeout_seconds'] < float('inf'), name + ': bounded timeout')
            cwd = core if name in {'core-analysis', 'core-vm', 'core-node'} else store if name in {'store-analysis', 'store-vm', 'portable-node', 'browser-entry', 'browser-worker'} else self.repo
            self.check(Path(entry['cwd']) == cwd, name + ': exact command directory')
            if name in commands:
                self.check(entry['command'] == commands[name], name + ': exact command arguments')
            if name in groups:
                directory, tests, platform = groups[name]
                results.append(self.recount(entry, tests, platform))
            elif name == 'runner-regressions':
                self.check(entry['command'][1:] == ['-m', 'unittest', 'discover', '-s', 'tools/mail', '-p', 'test_check_store.py', '-v'], 'exact separate Python controls command')
                matches = re.findall(rb'Ran (\d+) tests? in [^\n]+\n\s*\nOK\s*$', raw)
                rows = re.findall(r'^(test\S+) \(([^)]+)\) \.\.\. (ok|FAIL|ERROR|skipped[^\n]*)$', raw.decode(), re.MULTILINE)
                self.check(len(matches) == 1 and len(rows) == int(matches[0]) and
                           len({(m, c) for m, c, _ in rows}) == len(rows) and all(r == 'ok' for _, _, r in rows), 'independently recounted distinct Python controls')
                syntax = ast.parse(self.git('show', source + ':tools/mail/test_check_store.py'))
                expected_ids = {'test_check_store.' + cls.name + '.' + method.name for cls in syntax.body if isinstance(cls, ast.ClassDef) for method in cls.body if isinstance(method, (ast.FunctionDef, ast.AsyncFunctionDef)) and method.name.startswith('test')}
                self.check({owner for method, owner, result in rows} == expected_ids, 'all frozen Store Python control definitions execute exactly once')
                self.check(entry['command'][0] == store_run['command'][0], 'Store Python controls use the outer-bound interpreter')
                controls = {'cases': len(rows), 'case_ids': [owner for method, owner, result in rows], 'source': 'tools/mail/test_check_store.py', 'raw_log_sha256': digest(raw),
                            'python_executable_sha256': file_hash(Path(entry['command'][0])), 'included_in_application_total': False}
            elif name in {'browser-entry', 'browser-worker'}:
                path = self.gate / (name + '.js')
                self.check(path.is_file() and path.stat().st_size > 0, name + ': newly emitted JS output present')
                outputs.append({'name': path.name, 'bytes': path.stat().st_size, 'sha256': file_hash(path)})
        distinct = sorted({path for row in results for path in row['suite_paths']})
        self.report.update({'source_commit': source, 'source_tree': self.git('rev-parse', source + '^{tree}').decode().strip(),
                            'target_source_commit': target, 'target_source_tree': self.git('rev-parse', target + '^{tree}').decode().strip(),
                            'source_equivalence': {'execution_source_preserved': True,
                                                   'all_bound_inputs_identical_in_target': all(target_tree.get(path) == self.tree[path] for path in expected_inputs),
                                                   'bound_inputs': len(expected_inputs),
                                                   'changed_paths_between_execution_and_target': self.git('diff', '--name-only', source, target).decode().splitlines(),
                                                   'dependency_closure': closure,
                                                   'decision': 'Store results retain their actual execution commit. Applicability to the final source rests on identical bound source/config/lock bytes and a declared/static dependency closure excluding transport and enough_mail.'},
                            'receipt_sha256': file_hash(self.gate / 'receipt.json'), 'groups': results,
                            'application_case_executions': sum(r['passed'] for r in results),
                            'suite_platform_executions': sum(r['suites'] for r in results),
                            'distinct_test_files': len(distinct), 'distinct_test_paths': distinct,
                            'failed': sum(r['failed'] for r in results), 'skipped': sum(r['skipped'] for r in results),
                            'source_inputs_reverified': len(source_rows), 'source_inputs': source_rows,
                            'launcher_inputs_reverified': len(launcher), 'source_manifests_equal': receipt['source_before'] == receipt['source_after'],
                            'runtime_receipt_sha256': file_hash(self.runtime / 'runtime.json'),
                            'outer_execution_receipt_sha256': digest(outer_raw),
                            'outer_runtime_inputs_reverified': len(runtime_before), 'outer_source_inputs_reverified': len(source_before),
                            'outer_source_and_runtime_before_after_identical': source_before == source_after and runtime_before == runtime_after,
                            'runtime_binding_scope': 'The outer frozen driver binds the complete retained runtime, Python, SDK/Node/native executables, configuration and source before and after all gates. The Store gate separately binds its exact launcher/native/shadowing inputs. Original event, source and runtime identities are independently rechecked.',
                            'separate_python_controls': controls, 'compiled_browser_outputs': outputs,
                            'browser_runtime_execution': 'NOT ESTABLISHED: compile and Node checks only', 'github_actions': 'NOT QUERIED OR AWAITED'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--gate', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--outer', required=True, type=Path)
    parser.add_argument('--driver', required=True)
    parser.add_argument('--native-plan', required=True)
    parser.add_argument('--node-plan', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--target-source', help='Optional final source to prove equivalent for every store gate input; never relabels the execution source.')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    audit = StoreAudit(args)
    try:
        audit.run()
    except Exception as error:
        audit.issues.append('Audit could not complete: ' + repr(error))
        import traceback
        traceback.print_exc()
    audit.report.update({'audited_at_utc': datetime.now(timezone.utc).isoformat(),
                         'audit_script_sha256': file_hash(Path(__file__)), 'issues': audit.issues,
                         'method': 'Independent raw event/suite/platform recount, immutable Git blob and current-file SHA-256 comparisons, exact command checks, actual runtime/native input readback. No runner parser imported, product tests executed or CI queried.',
                         'passed': not audit.issues})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(audit.report, indent=2) + '\n')
    print(json.dumps({k: audit.report[k] for k in ('source_commit', 'application_case_executions', 'suite_platform_executions', 'distinct_test_files', 'passed', 'issues') if k in audit.report}, indent=2))
    raise SystemExit(bool(audit.issues))


if __name__ == '__main__':
    main()
