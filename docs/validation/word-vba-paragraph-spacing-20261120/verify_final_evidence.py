#!/usr/bin/env python3
"""Independent, read-only review of the Word line-spacing final evidence.

This does not import any producer or gate helper and does not execute tests.
It reconstructs reporter cases and validates the evidence against actual files
and the immutable qualified Git tree. Only its own review output is written.
"""
from __future__ import annotations

import argparse
import base64
import collections
import datetime as dt
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
from urllib.parse import unquote, urljoin, urlparse

QUALIFIED = '0201b549d0dc3f601c50e36255d557034cb01699'
TREE = '86531c002a6b1d6e748849f7370a87072a5fa768'
MAIL = 'c7e721b7703766491fd4459b69de30bf68d9010d'
PREFIXES = [
    'packages/quds_office_engine/lib',
    'packages/quds_office_engine/test',
    'packages/quds_office_engine/tool',
    'packages/quds_office_engine/example',
    'packages/legacy_doc_parser/lib',
]
CONFIGS = [
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
    'packages/quds_office_engine/pubspec.yaml',
    'packages/quds_office_engine/analysis_options.yaml',
    'packages/legacy_doc_parser/pubspec.yaml',
    'packages/legacy_doc_parser/analysis_options.yaml',
    'packages/quds_office_editor/fonts/LiberationSans-Regular.ttf',
    'packages/quds_office_editor/fonts/LiberationMono-Regular.ttf',
]
ADDED = {
    'office_vba_word_line_spacing_test.dart': 99,
    'office_macro_word_line_spacing_test.dart': 96,
    'office_vba_word_line_spacing_integration_test.dart': 23,
    'word_font_line_metrics_test.dart': 5,
    'word_line_box_fidelity_test.dart': 7,
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def identity(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return {'bytes': path.stat().st_size, 'sha256': digest.hexdigest()}


def git_blob_identity(path):
    size = path.stat().st_size
    digest = hashlib.sha1(f'blob {size}\0'.encode())
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f'Duplicate JSON key: {key}')
        result[key] = value
    return result


def decode(data):
    return json.loads(data, object_pairs_hook=unique_pairs)


def load(path):
    data = path.read_bytes()
    return decode(gzip.decompress(data) if path.suffix == '.gz' else data)


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


class Audit:
    def __init__(self, base):
        self.base = base
        self.repo = base / 'quds_office_suite'
        self.engine = self.repo / 'packages/quds_office_engine'
        self.runtime = base / 'runtime'
        self.tc = self.runtime / 'toolchain'
        self.source_entries = None

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo)

    def tree(self, *paths):
        result = {}
        for row in self.git('ls-tree', '-rz', QUALIFIED, '--', *paths).split(b'\0'):
            if row:
                meta, path = row.split(b'\t', 1)
                mode, kind, blob = meta.decode().split()
                result[path.decode()] = {'mode': mode, 'type': kind, 'blob': blob}
        return result

    def sources(self, recorded):
        require(recorded['source_commit'] == QUALIFIED, 'Manifest source commit')
        require(recorded['source_tree'] == TREE, 'Manifest source tree')
        require(recorded['selection'] == {'directories': PREFIXES, 'configuration_files': CONFIGS}, 'Complete source selection')
        require(recorded['head_matches_worktree'] is True, 'Recorded Git/source mismatch')
        entries = recorded['entries']
        if self.source_entries is None:
            expected = self.tree(*PREFIXES, *CONFIGS)
            actual_names = set(CONFIGS)
            for prefix in PREFIXES:
                actual_names.update(str(p.relative_to(self.repo)) for p in (self.repo / prefix).rglob('*') if p.is_file() or p.is_symlink())
            require(set(entries) == set(expected) == actual_names, 'Source path inventory differs from Git or filesystem')
            require(len(entries) == 1131, 'Source input count')
            for name, row in entries.items():
                path = self.repo / name
                require(path.is_file() and not path.is_symlink(), f'Source missing/symlink: {name}')
                data = path.read_bytes()
                mode = '100755' if path.stat().st_mode & 0o111 else '100644'
                blob = hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()
                computed = {'bytes': len(data), 'sha256': sha(data), 'head': expected[name], 'worktree_blob': blob, 'worktree_mode': mode}
                require(row == computed, f'Source identity mismatch: {name}')
                require(expected[name] == {'mode': mode, 'type': 'blob', 'blob': blob}, f'Git content/mode mismatch: {name}')
            self.source_entries = entries
        require(entries == self.source_entries, 'Different source snapshots across final phases')
        return {'qualified_paths': len(entries), 'actual_contents_modes_and_git_objects_verified': True, 'selection_sha256': sha(canonical(recorded['selection'])), 'entries_sha256': sha(canonical(entries))}

    def runtime_inputs(self, entries, expected_count):
        require(len(entries) == expected_count, 'Recorded runtime count')
        for name, row in entries.items():
            path = Path(name)
            require(path.is_file(), f'Runtime input missing: {name}')
            actual = identity(path)
            if 'git_blob' in row:
                actual['git_blob'] = git_blob_identity(path)
            if 'mode' in row:
                actual['mode'] = oct(path.stat().st_mode & 0o777)
            if 'link_target' in row:
                require(path.is_symlink(), f'Runtime link identity: {name}')
                actual['link_target'] = os.readlink(path)
            require(row == actual, f'Runtime identity mismatch: {name}')
        return {'recorded_paths': len(entries), 'all_recorded_actual_contents_verified': True, 'entries_sha256': sha(canonical(entries))}

    def bindings(self, directory, count):
        before = load(directory / 'inputs-before.json.gz')
        after = load(directory / 'inputs-after.json.gz')
        require(before == after, f'Before/after manifest inequality: {directory.name}')
        source = self.sources(before)
        runtime = self.runtime_inputs(before['runtime_inputs'], count)
        return before, {'source': source, 'runtime': runtime, 'before_after_exactly_equal': True}

    def files(self, directory, recursive=False):
        paths = directory.rglob('*') if recursive else directory.iterdir()
        return {str(p.relative_to(directory)): identity(p) for p in sorted(paths) if p.is_file() and p.name != 'archive-index.json'}

    def receipts(self, path, names):
        rows = load(path)
        require([r['name'] for r in rows] == names, 'Command names/order')
        for row in rows:
            require(row['exit_code'] == 0 and row['seconds'] > 0, f'Command result {row["name"]}')
            require(row['cwd'] == str(self.engine), 'Command cwd')
            dt.datetime.fromisoformat(row['started_utc'])
        return rows

    def portable(self):
        d = self.runtime / 'line-spacing-portable-final'
        s = load(d / 'summary.json')
        before, binding = self.bindings(d, 20)
        commands = self.receipts(d / 'commands.json', ['vm', 'compile-js', 'node'])
        require(commands == s['commands'], 'Portable command receipts differ')
        bas_path = self.engine / 'example/macros/word_line_spacing.bas'
        bas = bas_path.read_bytes()
        require((d / 'actual-example.bas').read_bytes() == bas, 'Exact BAS snapshot')
        define = '-DWORD_LINE_SPACING_BAS_BASE64=' + base64.b64encode(bas).decode()
        dart = str(self.tc / 'dart-sdk/bin/dart')
        packages = '--packages=' + str(self.repo / '.dart_tool/package_config.json')
        driver = self.engine / 'tool/macros/web_vba_word_line_spacing_smoke.dart'
        expected = [
            [dart, packages, define, str(driver)],
            [dart, 'compile', 'js', '-O1', packages, define, '-o', str(d / 'word-line-spacing.js'), str(driver)],
            [str(Path(shutil.which('node')).resolve()), '-e', 'globalThis.self = globalThis; require(process.argv[1]);', str(d / 'word-line-spacing.js')],
        ]
        require([c['argv'] for c in commands] == expected, 'Exact portable commands / define')
        require((d / 'runner.py').read_bytes() == (self.runtime / 'run_line_spacing_portable.py').read_bytes(), 'Portable runner snapshot')
        require((d / 'gate-helper.py').read_bytes() == (self.runtime / 'line_spacing_gate_helper.py').read_bytes(), 'Portable helper snapshot')
        for name in ['vm', 'compile-js', 'node']:
            require((d / f'{name}.stderr').read_bytes() == b'', f'Portable stderr {name}')
        vm = (d / 'vm.stdout').read_bytes()
        js = (d / 'node.stdout').read_bytes()
        require(vm == js and len(vm) == 1393, 'Raw VM/Node equality/length')
        result = decode(vm)
        require(result == decode(js), 'JSON VM/Node equality')
        require((d / 'result.json').read_bytes() == canonical(result), 'Canonical output bytes')
        expected_paragraphs = [
            {'text': 'Exact paragraph', 'rule': 'exact', 'amount': 14.25, 'nativeLine': '285', 'nativeRule': 'exact', 'directBefore': '120', 'directAfter': '180', 'effectiveBefore': 6, 'effectiveAfter': 9, 'token': 'first'},
            {'text': 'Minimum paragraph', 'rule': 'atLeast', 'amount': 18, 'nativeLine': '360', 'nativeRule': 'atLeast', 'directBefore': None, 'directAfter': None, 'effectiveBefore': 9, 'effectiveAfter': 12, 'token': 'second'},
            {'text': '', 'rule': 'auto', 'amount': 1.75, 'nativeLine': '420', 'nativeRule': 'auto', 'directBefore': '0', 'directAfter': '0', 'effectiveBefore': 0, 'effectiveAfter': 0, 'token': 'third'},
            {'text': 'Untouched paragraph', 'rule': 'exact', 'amount': 30, 'nativeLine': '600', 'nativeRule': 'exact', 'directBefore': None, 'directAfter': None, 'effectiveBefore': 9, 'effectiveAfter': 12, 'token': 'untouched'},
        ]
        expected_result = {
            'example': {'operations': 6, 'revision': 1, 'additionalReopens': 2, 'opaqueVbaPreserved': True, 'paragraphs': expected_paragraphs},
            'exampleReplay': {'operationsPerRun': 6, 'revision': 2, 'sameSavedState': True},
            'ordinaryDecimals': {'linesToPoints': 13.8, 'pointsToLines': 1.15, 'nativeLines': ['276', '276', '23'], 'savedMultiple': 1.15, 'additionalReopens': 2},
            'presetGuards': {'refusedSourcePlans': 4, 'validateAndRunRollback': True, 'failedNativeCallsExcluded': 4},
            'policies': {'refusedPolicies': 3, 'completeAllowlistRevision': 1},
            'rollback': {'failedStep': 2, 'validateAndRunRollback': True},
            'recording': {'recordedSteps': 3, 'failedCallExcluded': True, 'replayRevision': 1},
            'refusedSources': 15,
        }
        require(result == expected_result, 'Portable independently expected results')
        for field, value in {
            'qualified': True, 'development_only': False, 'commands_succeeded': True,
            'source_commit_before': QUALIFIED, 'source_tree_before': TREE,
            'complete_source_input_count': 1131, 'runtime_input_count': 20,
            'head_matches_worktree': True, 'head_matches_worktree_after': True,
            'source_inputs_unchanged': True, 'runtime_inputs_unchanged': True,
            'raw_outputs_equal': True, 'canonical_results_equal': True,
            'raw_output_bytes': 1393, 'raw_output_sha256': sha(vm),
            'canonical_sha256': sha(canonical(result)), 'bas_sha256': sha(bas),
            'driver_sha256': identity(driver)['sha256'], 'runner_sha256': identity(d / 'runner.py')['sha256'],
        }.items():
            require(s[field] == value, f'Portable summary {field}')
        compile_output = (d / 'compile-js.stdout').read_text()
        require('Compiled ' in compile_output and ' characters JavaScript in ' in compile_output, 'Compilation stdout')
        require((d / 'word-line-spacing.js').stat().st_size > 1_000_000, 'Compiled JavaScript output exists')
        return {'status': 'PASS', **binding, 'commands': commands, 'raw_bytes': len(vm), 'raw_sha256': sha(vm), 'canonical_sha256': sha(canonical(result)), 'result': result, 'artifact_manifest': self.files(d)}

    def static(self):
        d = self.runtime / 'line-spacing-checks-final'
        s = load(d / 'summary.json')
        _, binding = self.bindings(d, 19)
        commands = self.receipts(d / 'commands.json', ['analysis', 'format'])
        require(commands == s['commands'], 'Static command receipts differ')
        paths = sorted(n for n in self.git('diff', '--name-only', MAIL, QUALIFIED, '--', 'packages/quds_office_engine').decode().splitlines() if n.endswith('.dart'))
        require(len(paths) == 8, 'Eight changed Dart paths')
        plan = load(d / 'plan.json')
        require(plan['format_paths'] == paths and plan['expected_commit'] == QUALIFIED and plan['source_tree'] == TREE, 'Static plan/source binding')
        dart = str(self.tc / 'dart-sdk/bin/dart')
        require(commands[0]['argv'] == [dart, 'analyze', '--fatal-infos', '--fatal-warnings'], 'Whole-engine strict analysis command')
        require(commands[1]['argv'] == [dart, 'format', '--output=none', '--set-exit-if-changed', *[str(self.repo / p) for p in paths]], 'Exact nonmutating format command')
        require((d / 'analysis.stdout').read_text() == 'Analyzing quds_office_engine...\nNo issues found!\n', 'Raw strict analysis output')
        require((d / 'format.stdout').read_text().startswith('Formatted 8 files (0 changed) in '), 'Raw formatting output')
        require(not (d / 'analysis.stderr').read_bytes() and not (d / 'format.stderr').read_bytes(), 'Static stderr')
        require((d / 'runner.py').read_bytes() == (self.runtime / 'run_line_spacing_checks.py').read_bytes(), 'Static runner snapshot')
        require((d / 'gate-helper.py').read_bytes() == (self.runtime / 'line_spacing_gate_helper.py').read_bytes(), 'Static helper snapshot')
        actual = self.files(d)
        require(s['artifacts'] == {k: v for k, v in actual.items() if k != 'summary.json'}, 'Static complete artifact hashes')
        for field, value in {
            'qualified': True, 'commands_succeeded': True, 'source_commit_before': QUALIFIED, 'source_commit_after': QUALIFIED,
            'source_tree': TREE, 'head_matches_worktree_before': True, 'head_matches_worktree_after': True,
            'source_inputs_unchanged': True, 'runtime_inputs_unchanged': True,
            'source_input_count': 1131, 'runtime_input_count': 19,
            'format_is_non_mutating': True, 'format_path_count': 8,
        }.items():
            require(s[field] == value, f'Static summary {field}')
        return {'status': 'PASS', **binding, 'commands': commands, 'format_paths': paths, 'analysis_scope': 'Whole engine package, fatal infos and warnings', 'artifact_manifest': actual}

    def reporter(self, raw, expected_files, legacy=False):
        require(raw.endswith(b'\n'), 'Reporter missing complete final LF')
        lines = raw.split(b'\n')[:-1]
        require(all(line.strip() for line in lines), 'Blank reporter line')
        events = [decode(line) for line in lines]
        kinds = collections.Counter(e['type'] for e in events)
        require(set(kinds) <= {'start', 'suite', 'allSuites', 'group', 'testStart', 'testDone', 'print', 'done'}, 'Unknown/error reporter event')
        require(kinds['start'] == kinds['done'] == kinds['allSuites'] == 1, 'Unique protocol boundary events')
        require(events[0]['type'] == 'start' and events[0]['protocolVersion'] == '0.1.1', 'Protocol start')
        require(events[-1]['type'] == 'done' and events[-1]['success'] is True, 'Final success event')
        require(all(isinstance(e.get('time'), int) and e['time'] >= 0 for e in events), 'Reporter event times')
        require(all(a['time'] <= b['time'] for a, b in zip(events, events[1:])), 'Monotonic reporter event times')
        suites, groups, tests, completions, ids = {}, {}, {}, {}, set()
        expected_files = set(expected_files)
        for event in events:
            kind = event['type']
            if kind in {'suite', 'group', 'testStart'}:
                obj = event['test' if kind == 'testStart' else kind]
                ident = obj['id']
                require(isinstance(ident, int) and ident not in ids, 'Unique global reporter identity')
                ids.add(ident)
                if kind == 'suite':
                    require(obj['platform'] == 'vm', 'VM suite platform')
                    suites[ident] = obj
                else:
                    require(obj['suiteID'] in suites, 'Reporter suite reference')
                    if kind == 'group':
                        parent = obj['parentID']
                        require(parent is None or (parent in groups and groups[parent]['suiteID'] == obj['suiteID']), 'Group parent reference')
                        require(obj['metadata'].get('skip') is False, 'Skipped group')
                        groups[ident] = obj
                    else:
                        require(obj['metadata'].get('skip') is False, 'Skipped test start')
                        ancestors = obj['groupIDs']
                        require(len(ancestors) == len(set(ancestors)), 'Repeated test group')
                        parent = None
                        for group_id in ancestors:
                            require(group_id in groups and groups[group_id]['suiteID'] == obj['suiteID'], 'Test group reference')
                            require(groups[group_id]['parentID'] == parent, 'Complete ordered group ancestry')
                            parent = group_id
                        tests[ident] = obj
            elif kind == 'testDone':
                ident = event['testID']
                require(ident in tests and ident not in completions, 'Unique completion for an existing start')
                require(event['result'] == 'success' and event['skipped'] is False, 'Unsuccessful/skipped completion')
                require(isinstance(event['hidden'], bool), 'Hidden completion flag')
                completions[ident] = event
            elif kind == 'print':
                require(event['testID'] in tests, 'Print event test reference')
        require(set(tests) == set(completions), 'Exact complete start/end identity set')
        declared_suites = next(e['count'] for e in events if e['type'] == 'allSuites')
        require(declared_suites == len(suites) == (1 if legacy else len(expected_files)), 'Complete suite inventory')
        roots = [g for g in groups.values() if g['parentID'] is None]
        require(len(roots) == len(suites) and {r['suiteID'] for r in roots} == set(suites), 'One root per suite')
        suite_files = {}
        if not legacy:
            for ident, suite in suites.items():
                path = Path(suite['path'])
                path = path if path.is_absolute() else self.engine / path
                suite_files[ident] = str(path.relative_to(self.engine / 'test'))
            require(set(suite_files.values()) == expected_files and len(set(suite_files.values())) == len(suite_files), 'Original file suite mapping')
        cases, records, occurrences = [], [], collections.Counter()
        group_counts = collections.Counter()
        for ident, test in tests.items():
            if completions[ident]['hidden']:
                continue
            for group_id in test['groupIDs']:
                group_counts[group_id] += 1
            require(test['groupIDs'], 'Visible case missing root group')
            if legacy:
                matches = [groups[g]['name'] for g in test['groupIDs'] if groups[g]['name'] in expected_files]
                require(len(matches) == 1, 'Unique prior filename group')
                filename = matches[0]
                prefix = filename + ' '
                require(test['name'].startswith(prefix), 'Prior filename test prefix')
                name = test['name'][len(prefix):]
            else:
                filename = suite_files[test['suiteID']]
                name = test['name']
            require(urlparse(test['url']).path.endswith('/packages/quds_office_engine/test/' + filename), 'Case source URL/file binding')
            require(isinstance(test['line'], int) and test['line'] > 0 and isinstance(test['column'], int) and test['column'] > 0, 'Case source coordinates')
            occurrences[filename, name] += 1
            case = {'file': filename, 'name': name, 'occurrence': occurrences[filename, name]}
            cases.append(case)
            records.append({**case, 'test_id': ident, 'suite_id': test['suiteID'],
                            'group_ids': test['groupIDs'], 'result': 'success', 'skipped': False,
                            'line': test['line'], 'column': test['column'], 'url': test['url']})
        for ident, group in groups.items():
            require(group['testCount'] == group_counts[ident], 'Every group declaration equals observed complete cases')
        counts = dict(sorted(collections.Counter(c['file'] for c in cases).items()))
        require(set(counts) == expected_files, 'Every expected file has completed cases')
        identities = {(c['file'], c['name'], c['occurrence']) for c in cases}
        require(len(identities) == len(cases), 'Unique qualified case identities')
        return {'cases': cases, 'records': records, 'start_ids': sorted(tests), 'completion_ids': sorted(completions), 'identities': identities, 'counts': counts, 'events': dict(sorted(kinds.items())), 'raw_sha256': sha(raw), 'raw_bytes': len(raw), 'suite_count': len(suites), 'start_completion_count': len(tests), 'hidden_completions': len(tests) - len(cases), 'passed_cases': len(cases), 'failed_cases': 0, 'skipped_cases': 0, 'protocol_and_all_group_declarations_verified': True}

    def regression_runtime_selection(self, entries, directory):
        expected = {
            self.runtime / 'run_word_spacing_full_gate.py', directory / 'plan.json',
            directory / 'prior-cases.json.gz', directory / 'prior-inputs-before.json.gz', directory / 'prior-report.json',
            self.tc / 'env.sh', self.tc / 'run-engine-tests.sh', self.tc / 'test-runner/test-runner.dill', self.tc / 'environment.json',
            self.repo / '.dart_tool/package_config.json', self.repo / '.dart_tool/package_graph.json',
            self.tc / 'engine-validation/packages/quds_office_engine/pubspec.yaml',
            self.tc / 'engine-validation/packages/quds_office_engine/pubspec.lock',
            self.tc / 'engine-validation/packages/legacy_doc_parser/pubspec.yaml',
            Path(sys.executable).resolve(), Path(shutil.which('bash')).resolve(), Path(shutil.which('git')).resolve(),
        }
        sdk = self.tc / 'dart-sdk'
        expected.update(p for prefix in [sdk / 'bin', sdk / 'lib'] for p in prefix.rglob('*') if p.is_file() and p.suffix != '.sym')
        expected.update(sdk / name for name in ['version', 'revision', 'sdk_packages.yaml'] if (sdk / name).is_file())
        config_path = self.repo / '.dart_tool/package_config.json'
        packages = load(config_path)['packages']
        external_roots = []
        for package in packages:
            parsed = urlparse(urljoin(config_path.as_uri(), package['rootUri']))
            require(parsed.scheme == 'file', 'Resolved dependency URI is local')
            root = Path(unquote(parsed.path)).resolve()
            if root.is_relative_to(self.repo):
                continue
            require(root.is_relative_to(self.tc), 'External dependency within recorded toolchain')
            external_roots.append({'name': package['name'], 'root': str(root)})
            expected.add(root / 'pubspec.yaml')
            expected.update(p for prefix in [root / 'lib', root / 'bin'] if prefix.is_dir() for p in prefix.rglob('*') if p.is_file())
        if directory.name == 'word-spacing-batched-final-0201b549':
            expected.update([self.runtime / 'run_word_spacing_batched_gate.py', directory / 'batches.json'])
        require({str(p) for p in expected} == set(entries), 'Regression complete declared runtime selection')
        return {'verified_recorded_selection': True, 'external_dependency_roots': external_roots, 'sdk_scope': 'bin and lib recursively, excluding .sym, plus version/revision/sdk_packages.yaml'}

    def regression(self, allow_running):
        from audit_batched_regression import audit_batched_regression
        return audit_batched_regression(self, allow_running)

    def checkpoint_archives(self):
        from audit_checkpoint_archives import audit_checkpoint_archives
        from audit_bounded_progress_archive import audit_bounded_progress_archive
        result = audit_checkpoint_archives(self)
        result['archives']['bounded-progress-evidence'] = audit_bounded_progress_archive(self)
        return result

    def supplemental(self):
        d = self.base / 'intake-review'
        review = load(d / 'source-review.json')
        receipt = load(d / 'source-review-probes-final.json')
        require(review['outstanding_findings'] == [], 'Outstanding source review finding')
        require(review['accepted_supplemental_expectations'] == 56 and review['regression_total_contribution'] == 0, 'Supplemental count separation')
        require(receipt['status'] == 'PASS' and receipt['exit_code'] == 0 and receipt['passed_supplemental_expectations'] == 56 and not receipt['failed'], 'Supplemental final receipt')
        require(receipt['source_head_at_start'] == receipt['source_head_at_finish'] == QUALIFIED, 'Supplemental qualified source')
        require(receipt['source_before'] == receipt['source_after'] and receipt['recorded_runtime_before'] == receipt['recorded_runtime_after'], 'Supplemental source/runtime immutable')
        require(review['source_files'] == receipt['source_before'], 'Source review/probe source identities')
        source_tree = self.tree(*receipt['source_before'])
        require(len(source_tree) == 10, 'Ten reviewed source/contract inputs')
        for name, row in receipt['source_before'].items():
            path = self.repo / name
            mode = '100755' if path.stat().st_mode & 0o111 else '100644'
            computed = {**identity(path), 'git_blob': git_blob_identity(path), 'git_mode': mode}
            require(row == computed, 'Supplemental current source/contract content: ' + name)
            require(source_tree[name] == {'mode': mode, 'type': 'blob', 'blob': computed['git_blob']}, 'Supplemental source/contract immutable Git object: ' + name)
        runtime = self.runtime_inputs(receipt['recorded_runtime_before'], 38)
        require(receipt['command'] == [str(self.tc / 'dart-sdk/bin/dart'), '--old_gen_heap_size=768', '--packages=' + str(self.repo / '.dart_tool/package_config.json'), str(d / 'word-spacing-all-probes.dart')], 'Supplemental command')
        require(receipt['cwd'] == str(self.base), 'Supplemental cwd')
        for name, row in review['probe_record_manifest'].items():
            require(identity(d / name) == row, 'Source review probe record manifest: ' + name)
        for label in ['stdout', 'stderr']:
            row = receipt[label]
            path = d / row['path']
            require(row == {'path': path.name, **identity(path), 'git_blob': git_blob_identity(path)}, 'Supplemental raw output receipt')
        require(not (d / 'word-spacing-all-probes-final.stderr').read_bytes(), 'Supplemental stderr')
        rows = [decode(row) for row in (d / 'word-spacing-all-probes-final.jsonl').read_bytes().split(b'\n') if row]
        require(len(rows) == 56, 'Supplemental raw result count')
        require(all(r['status'] == 'accepted' for r in rows[:32]), 'Supplemental successful methods/helpers/conversions')
        require(all(r['status'] == 'rejected' for r in rows[32:38]), 'Supplemental native source refusals')
        require(all(r['matched'] is True for r in rows[38:54]), 'Supplemental boundaries and alias expectations')
        require(all(r['status'] == 'rejected' for r in rows[54:]), 'Supplemental pPr MC source refusals')
        return {'status': 'PASS', 'expectations': 56, 'counted_in_regression': 0, 'source_and_contract_inputs': 10, 'recorded_runtime': runtime, 'source_review_receipt': identity(d / 'source-review.json'), 'final_probe_receipt': identity(d / 'source-review-probes-final.json'), 'raw_output': identity(d / 'word-spacing-all-probes-final.jsonl'), 'scope': 'Independently authored adversarial probes are supplemental. Early and corrected development attempts are not final regression cases.'}

    def archives(self, allow_running):
        descriptors = [
            ('portable_static', self.runtime / 'line-spacing-portable-static-packaging.json', 'members_manifest', 60),
            ('development_and_source_review', self.runtime / 'line-spacing-development-review/packaging.json', 'member_index', 110),
            ('regression', self.runtime / 'word-spacing-regression-packaging.json', 'member_index', None),
        ]
        results = {}
        for label, receipt_path, index_key, expected_count in descriptors:
            if not receipt_path.exists():
                require(allow_running and label == 'regression', 'Missing archive receipt: ' + label)
                results[label] = {'status': 'PENDING'}
                continue
            receipt = load(receipt_path)
            archive_path, index_path = Path(receipt['archive']), Path(receipt[index_key])
            require(archive_path.is_relative_to(self.base) and index_path.is_relative_to(self.base), 'Archive/index within workspace')
            archive_identity, index_identity = identity(archive_path), identity(index_path)
            require(archive_identity == {'bytes': receipt['bytes'], 'sha256': receipt['sha256']}, 'Archive exact size/digest: ' + label)
            require(index_identity['sha256'] == receipt['member_index_sha256'], 'External member index digest: ' + label)
            index = load(index_path)
            index_name = str(index_path.relative_to(self.base))
            member_total = len(index) + 1
            require(member_total == receipt['member_count'], 'Complete archive member count: ' + label)
            require(expected_count is None or expected_count == member_total, 'Expected archive member count: ' + label)
            seen = set()
            archive_paths = []
            with tarfile.open(archive_path, 'r:xz') as archive:
                members = archive.getmembers()
                require(len(members) == member_total, 'Actual archive member count: ' + label)
                order_key = str if label == 'development_and_source_review' else Path
                require([m.name for m in members] == sorted((m.name for m in members), key=order_key), 'Declared deterministic archive member order: ' + label)
                for member in members:
                    name = member.name
                    path = Path(name)
                    require(not path.is_absolute() and '..' not in path.parts and name not in seen, 'Safe unique archive member path')
                    seen.add(name)
                    require(member.isfile() and member.mtime == member.uid == member.gid == 0 and member.uname == member.gname == '', 'Normalized regular archive member: ' + name)
                    payload = archive.extractfile(member).read()
                    actual = {'bytes': len(payload), 'sha256': sha(payload)}
                    original = self.base / name
                    require(original.is_file() and not original.is_symlink(), 'Existing regular original archive input: ' + name)
                    require(identity(original) == actual, 'Archive payload equals actual input: ' + name)
                    require(member.mode == original.stat().st_mode & 0o7777, 'Archived actual permission bits: ' + name)
                    if name == index_name:
                        require(payload == index_path.read_bytes(), 'Embedded index exact external identity')
                    else:
                        require(name in index, 'Unindexed archive member: ' + name)
                        row = index[name]
                        require(actual == {'bytes': row['bytes'], 'sha256': row['sha256']}, 'Indexed member size/digest: ' + name)
                        if 'mode' in row:
                            expected_mode = ('100755' if member.mode & 0o111 else '100644') if row['mode'].startswith('100') else f'{member.mode:04o}'
                            require(row['mode'] == expected_mode, 'Indexed archive member mode: ' + name)
                    archive_paths.append((member, payload))
            require(seen == set(index) | {index_name}, 'Exact archive/index set equality: ' + label)
            required = set()
            if label == 'portable_static':
                for phase in ['line-spacing-portable-final', 'line-spacing-checks-final']:
                    required.update(str(p.relative_to(self.base)) for p in (self.runtime / phase).iterdir() if p.is_file())
                require(receipt['source_commit'] == QUALIFIED and receipt['source_tree'] == TREE, 'Portable/static archive source binding')
                require(receipt['portable_qualified'] is True and receipt['analysis_format_qualified'] is True, 'Portable/static archive qualification')
            elif label == 'development_and_source_review':
                review = load(self.base / 'intake-review/source-review.json')
                required.update('intake-review/' + name for name in review['probe_record_manifest'])
                required.update('intake-review/' + name for name in ['source-review.json', 'source-review.md', 'source-review-probes-final.json', 'run_final_source_review.py'])
                require(receipt['review_source_commit'] == QUALIFIED, 'Source-review archive source binding')
                require(receipt['accepted_independent_supplemental_expectations'] == 56 and receipt['regression_total_contribution'] == 0 and receipt['development_publication_acceptance'] is False, 'Development/supplemental count separation')
                require(receipt['omitted_generated_artifact_count'] == 0, 'Development artifacts omitted')
                attempts = load(self.runtime / 'line-spacing-development-review/attempts.json')
                require(attempts['development_publication_acceptance'] is False and attempts['sum_of_attempt_counts_is_not_an_acceptance_total'] is True, 'Attempt classification')
                for path, row in attempts['reporter_streams'].items():
                    require(path in index, 'Development raw stream included')
                    events = [decode(line) for line in (self.base / path).read_bytes().split(b'\n') if line]
                    dones = [e for e in events if e['type'] == 'testDone']
                    visible = [e for e in dones if not e['hidden']]
                    observed = {
                        'visible_completed_cases': len(visible),
                        'visible_passed': sum(e['result'] == 'success' and not e['skipped'] for e in visible),
                        'visible_failed': sum(e['result'] != 'success' for e in visible),
                        'visible_skipped': sum(e['skipped'] for e in visible),
                        'failed_completions_including_hidden_loads': sum(e['result'] != 'success' for e in dones),
                        'reporter_error_events': sum(e['type'] == 'error' for e in events),
                        'last_reporter_success': [e['success'] for e in events if e['type'] == 'done'][-1],
                        'scope': 'development_only', 'publication_acceptance': False, 'parse_problems': [],
                    }
                    require(row == observed, 'Development raw outcome classification: ' + path)
                for phase, row in attempts['portable_development_runs'].items():
                    summary = load(self.runtime / phase / 'summary.json')
                    require(row == {key: summary[key] for key in row}, 'Portable development classification')
                    require(row['qualified'] is False and row['development_only'] is True, 'Portable development excluded from acceptance')
            else:
                required.update(str(p.relative_to(self.base)) for p in (self.runtime / 'word-spacing-batched-final-0201b549').rglob('*') if p.is_file())
                required.update(str(p.relative_to(self.base)) for p in (self.runtime / 'word-spacing-final-0201b549').rglob('*') if p.is_file())
                required.update(str(p.relative_to(self.base)) for p in (self.runtime / 'word-spacing-interrupted-observation').rglob('*') if p.is_file())
                require(receipt['accepted_batch_count'] == 8 and receipt['interrupted_attempt_included_as_diagnostic_only'] is True, 'Complete bounded recovery and interrupted evidence inclusion')
                require(receipt['accepted'] is True and receipt['source_commit'] == QUALIFIED and receipt['source_tree'] == TREE, 'Regression archive qualification/source binding')
                require(receipt['regression_cases'] == 2799 and receipt['regression_modules'] == 75, 'Regression archive total binding')
                require(receipt['deterministic_archive_second_build_matches'] is True, 'Producer reproducible archive receipt')
                # Independently reconstruct normalized TarInfo records and XZ bytes
                # in memory, without invoking or importing the producer packager.
                repeated = io.BytesIO()
                with tarfile.open(fileobj=repeated, mode='w:xz', preset=6) as target:
                    for original, payload in archive_paths:
                        info = tarfile.TarInfo(original.name)
                        info.mode = original.mode
                        info.size = len(payload)
                        target.addfile(info, io.BytesIO(payload))
                require(sha(repeated.getvalue()) == archive_identity['sha256'], 'Independent normalized archive reconstruction')
            require(required <= set(index), 'Complete phase/source-review payload archived: ' + label)
            results[label] = {
                'status': 'PASS', 'path': str(archive_path), **archive_identity,
                'member_count': member_total, 'all_member_contents_modes_and_live_inputs_verified': True,
                'embedded_and_external_index_identical': True, 'index': str(index_path), 'index_identity': index_identity,
                'receipt': str(receipt_path), 'receipt_identity': identity(receipt_path),
                'required_phase_files_complete': True,
                **({'independent_archive_reconstruction_identical': True} if label == 'regression' else {}),
                **({'development_raw_streams_independently_recounted': len(attempts['reporter_streams']), 'development_cases_added_to_acceptance': 0} if label == 'development_and_source_review' else {}),
            }
        return {'status': 'PASS' if all(r['status'] == 'PASS' for r in results.values()) else 'IN_PROGRESS', 'archives': results}


def render_markdown(result):
    regression = result['regression']
    portable = result['portable']
    diagnostics = regression['failed_bounded_attempts']
    lines = [
        '# Independent final evidence review', '',
        '**PASS for the qualified Word source and the reviewed evidence.**', '',
        f'Qualified commit: `{result["qualified_source"]}`. Qualified tree: `{result["qualified_tree"]}`.', '',
        'This review independently read the actual source and runtime files, recomputed their hashes and Git identities, reconstructed raw reporter events, and reopened the packaged archives. It did not import producer audit helpers or execute the final test suite again. The final remote merge is a separate publication check.', '',
        '## Accepted checks', '',
        '| Check | Independently verified result |',
        '| --- | --- |',
        '| Word/Office regression | 2,799 successful cases, 75 original VM suites, eight accepted bounded invocations; zero failures, skips or reporter errors in this accepted set |',
        '| Previous coverage | All 70 prior modules have exactly the same 2,569 `(file, name, occurrence)` identities and unchanged source content/modes/Git objects |',
        '| New feature coverage, included above | 99 compiler, 96 native and 23 integration cases: 218 total |',
        '| Additional existing line-layout coverage, included above | 12 cases in two modules |',
        '| VBA selection | All 48 current `office_vba_*` modules included |',
        '| Strict analysis | Entire engine package; fatal infos and warnings; no issues found |',
        '| Formatting | All eight changed Dart files, nonmutating verification, zero changes |',
        '| Exact BAS portability | Byte-identical 1,393-byte VM and compiled JavaScript output; exact canonical result equality |',
        '| Independent source-review probes | 56 successful expectations, counted separately from regression |',
        '| Later macOS correction checks | 61 producer checks and 36 separate independent expectations; excluded from Word totals |', '',
        'The raw-event review verifies LF framing, unique protocol start/end events, complete and unique reporter IDs, valid suite/group ancestry, every declared group count, file/source-coordinate bindings, all outcomes, and exact stored case metadata. Global start/end IDs are namespaced by batch. Each of the 75 original files occurs exactly once within the eight accepted invocations; no aggregate shared test library was introduced.', '',
        '## Source and runtime binding', '',
        'All phases use the same 1,131 selected repository inputs. Actual filesystem bytes, modes, byte sizes, SHA-256 values and recomputed Git blob IDs match the immutable qualified tree. The scope includes engine libraries/tests/tools/examples, legacy parser libraries, configurations and the two font fixtures used by line-layout cases. The separate source review also binds the Word contract and exact BAS.', '',
        'The bounded regression has 16 before/after snapshots plus a final audit snapshot. All 17 are identical. Its 3,489 recorded runtime inputs include the frozen runner/launcher, SDK binaries and libraries, configured hosted package sources/manifests, package configurations and coordinator executables. Portable execution separately binds 20 runtime inputs, and static checks bind 19. These are explicitly selected phase-specific inventories, not a claim that every shared operating-system dependency was fingerprinted.', '',
        f'Raw VM/JavaScript SHA-256: `{portable["raw_sha256"]}`.', '',
        f'Canonical output SHA-256: `{portable["canonical_sha256"]}`.', '',
        'The actual BAS bytes in both command-line defines and the stored snapshot match the committed example. The reviewed results include exact, minimum and multiple spacing, repeat save/reopen, DOCM opaque parts, replay, decimal conversions, policy refusals, transactional rollback, source guards and recording exclusion after failed native calls.', '',
        '## Attempts kept outside acceptance', '',
        'The original long invocation ended without a process-exit receipt, automatic after snapshot or terminal reporter event. Its 2,679 visible completions are retained as incomplete diagnostic evidence and add zero cases to the accepted total. The later observation of unchanged inputs is explicitly separate from normal completion.', '',
    ]
    for row in diagnostics:
        lines.append(f'- Diagnostic batch {row["batch_id"]}: {row["visible_completed_cases"]} visible completions, including {row["visible_failed_cases"]} timeout failures. Recorded tool exit: {row["recorded_tool_exit_code"]}; normal execution receipt present: {row["normal_execution_receipt_present"]}. Contribution to accepted cases: zero.')
    lines += [
        '', 'All original failed-attempt bytes survived relocation. Exact timeout errors were independently recounted. Resource contention is an inference, supported by overlapping CLI-heavy invocations and separate successful retries; this review does not assert a proven root cause. The final accepted files are reconstructed only from their eight accepted batch directories. Earlier development failures and all 15 development reporter streams are also preserved and excluded.', '',
        '## Archive verification', '',
        'Every indexed member, byte size, SHA-256 value, permission class, normalized archive header and embedded/external index was checked against the actual archived payload. Frozen source/evidence payloads match their mapped source files; historical snapshots of evolving reviewer tools are explicitly identified when their current versions differ. Required phase files are complete. The final regression archive was also rebuilt independently in memory from normalized records and produced the same compressed bytes.', '',
    ]
    for name, row in result['packaging']['archives'].items():
        lines.append(f'- **{name}**: {row["member_count"]} members, {row["bytes"]:,} bytes; SHA-256 `{row["sha256"]}`.')
    for name, row in result['checkpoint_archives']['archives'].items():
        lines.append(f'- **{name}**: {row["member_count"]} members, {row["bytes"]:,} bytes; SHA-256 `{row["sha256"]}`.')
    lines += [
        '', 'The late-intake archive preserves the initial findings, exact corrected candidate, Apple source provenance, isolated outputs and stopped optional interpreter-setup diagnostics. It explicitly claims neither an actual macOS build/signing run nor actual Bash 3 execution. The reviewed correction is approved for integration; its final Git ancestry, executable mode and publication are checked separately.', '',
        '## Review boundaries', '',
        'There are no outstanding findings in the qualified Word source/evidence scope. Final main/remote consistency, incorporation of the three selected original late heads, preservation of the Word inputs after integration, and the explicit later-head deferral inventory remain separate publication checks. A classified deferred reference is not represented as incorporated. No GitHub Actions were queried or awaited.', '',
        'The JSON companion contains the complete audit details, per-module identity comparison, exact command receipts, every artifact digest, snapshot bindings, diagnostic classification, archive proofs and hashes of the independent verifier sources.', '',
    ]
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--allow-running', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    base = args.base.resolve()
    audit = Audit(base)
    require(audit.git('rev-parse', QUALIFIED + '^{tree}').decode().strip() == TREE, 'Immutable qualified tree')
    current_head = audit.git('rev-parse', 'HEAD').decode().strip()
    require(subprocess.run(['git', 'merge-base', '--is-ancestor', QUALIFIED, current_head], cwd=audit.repo).returncode == 0, 'Qualified source remains current ancestor')
    result = {
        'schema': 'quds-word-line-spacing-independent-evidence-review/v1',
        'reviewer': 'Independent source/intake reviewer; no producer/helper imports and no new test execution',
        'qualified_source': QUALIFIED, 'qualified_tree': TREE,
        'current_head_at_review': current_head,
        'review_started_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
        'dart_version': (audit.tc / 'dart-sdk/version').read_text().strip(),
        'verifier': identity(Path(__file__).resolve()),
        'additional_verifier_sources': {name: identity(Path(__file__).with_name(name)) for name in ['audit_batched_regression.py', 'audit_checkpoint_archives.py', 'audit_bounded_progress_archive.py']},
    }
    for name, callback in [('portable', audit.portable), ('static', audit.static), ('regression', lambda: audit.regression(args.allow_running)), ('supplemental', audit.supplemental), ('packaging', lambda: audit.archives(args.allow_running)), ('checkpoint_archives', audit.checkpoint_archives)]:
        result[name] = callback()
        print(json.dumps({'phase': name, 'review_status': result[name]['status']}), flush=True)
    result['status'] = 'PASS' if result['regression']['status'] == result['packaging']['status'] == 'PASS' else 'IN_PROGRESS'
    result['review_finished_utc'] = dt.datetime.now(dt.timezone.utc).isoformat()
    result['outstanding_findings'] = []
    result['limits'] = [
        'Recorded runtime inputs are phase-specific: 20 portable, 19 static, and 3489 regression across eight bounded invocations. The smaller manifests are not represented as a full dependency/runtime closure.',
        'This is independent evidence replay and integrity verification, not a new execution of the final test suite.',
        'The source manifest covers the stated 1131 selected inputs. The separate source review also binds the Word contract and exact BAS, with preservation limited as documented.',
        'Development attempts, the interrupted invocation with 2,679 completions, and the 56 independent supplemental expectations are excluded from the 2,799 regression total.',
        'Final publication and remote merge consistency are separate checks and are not implied by this pre-publication review.',
    ]
    result['github_actions_queried_or_awaited'] = False
    out = args.output or base / 'intake-review' / ('evidence-review-partial.json' if args.allow_running else 'evidence-review.json')
    require(out.resolve().is_relative_to(base / 'intake-review'), 'Only independent review output directory may be written')
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if result['status'] == 'PASS':
        out.with_suffix('.md').write_text(render_markdown(result))
    print(json.dumps({'status': result['status'], 'output': str(out)}))


if __name__ == '__main__':
    main()
