#!/usr/bin/env python3
"""Audit completed local evidence independently; never execute application tests."""
from __future__ import annotations

import argparse
import collections
import datetime
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import posixpath
import re
import subprocess
import tarfile


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Audit:
    def __init__(self, args):
        self.args = args
        self.repo = args.repo.resolve()
        self.gate = args.gate.resolve()
        self.runtime = args.runtime.resolve()
        self.issues = []
        self.report = {}
        self.layout_scan = []

    def check(self, predicate, message):
        if not predicate:
            self.issues.append(message)

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo)

    def frozen(self, path):
        return self.git('show', self.args.source + ':' + path)

    def sha_file(self, path):
        return digest(Path(path).read_bytes())

    def read_json(self, path):
        return json.loads(Path(path).read_bytes())

    def audit_group(self, run, group):
        raw = (self.gate / run['log']).read_bytes()
        events = [json.loads(line) for line in raw.splitlines() if line.strip()]
        name = run['name']
        diagnostic_patterns = {
            'renderflex_overflow': r'A RenderFlex overflowed',
            'missed_widget_hit_test': r'would not hit test on the specified widget',
            'pointer_events_unavailable': r'does not receive pointer events',
            'layout_assertion': r'The following assertion was thrown during layout',
            'rendering_exception_banner': r'EXCEPTION CAUGHT BY RENDERING LIBRARY',
        }
        text = raw.decode('utf-8')
        hits = []
        for label, pattern in diagnostic_patterns.items():
            for match in re.finditer(pattern, text, flags=re.IGNORECASE):
                hits.append({'diagnostic': label, 'line': text.count('\n', 0, match.start()) + 1, 'context': text[max(0, match.start() - 80):min(len(text), match.end() + 160)]})
        self.layout_scan.append({'name': name, 'log': run['log'], 'raw_log_sha256': digest(raw), 'patterns': diagnostic_patterns, 'findings': hits})
        self.check(not hits, name + ': layout or missed-tap diagnostics present')
        self.check(all(isinstance(e, dict) and isinstance(e.get('type'), str) for e in events), name + ': malformed reporter events')
        kinds = collections.Counter(e['type'] for e in events)
        self.check(kinds['start'] == kinds['done'] == 1, name + ': runner lifecycle count')
        self.check(events[0]['type'] == 'start' and events[-1]['type'] == 'done' and events[-1]['success'] is True, name + ': runner lifecycle order/result')
        self.check(not kinds['error'], name + ': raw reporter errors')
        suite_rows = [e['suite'] for e in events if e['type'] == 'suite']
        suites = {row['id']: posixpath.normpath(row['path'] if row['path'].startswith('/') else posixpath.join(str(self.repo), group['cwd'], row['path'])) for row in suite_rows}
        expected = {str(self.repo / group['cwd'] / path) for path in group['tests']}
        self.check(len(suite_rows) == len(suites) == len(expected) and set(suites.values()) == expected, name + ': exact planned suite inventory')
        self.check(all(row.get('platform') == ('node' if group.get('platform') == 'node' else 'vm') for row in suite_rows), name + ': suite platform')
        starts_list = [e['test'] for e in events if e['type'] == 'testStart']
        starts = {row['id']: row for row in starts_list}
        ends_list = [e for e in events if e['type'] == 'testDone']
        ends = {row['testID']: row for row in ends_list}
        self.check(len(starts_list) == len(starts) and len(ends_list) == len(ends), name + ': duplicate test lifecycle ids')
        self.check(set(starts) == set(ends), name + ': unfinished/orphan test lifecycle')
        # Verify event order too; set equality cannot detect completion-before-start.
        live = set()
        finished = set()
        for event in events:
            if event['type'] == 'testStart':
                test_id = event['test']['id']
                self.check(test_id not in live and test_id not in finished, name + ': duplicate/restarted test')
                live.add(test_id)
            elif event['type'] == 'testDone':
                test_id = event['testID']
                self.check(test_id in live and test_id not in finished, name + ': completion before start')
                live.discard(test_id)
                finished.add(test_id)
        self.check(not live, name + ': tests remain running')
        cases = []
        hidden = 0
        counts = collections.Counter()
        per_suite = collections.defaultdict(collections.Counter)
        for end in ends_list:
            start = starts[end['testID']]
            self.check(start['suiteID'] in suites, name + ': test references unknown suite')
            self.check(end.get('result') == 'success' and end.get('skipped') is False and not start.get('metadata', {}).get('skip'), name + ': non-success test/hidden lifecycle: ' + start['name'])
            if end.get('hidden'):
                hidden += 1
                continue
            suite = suites[start['suiteID']]
            cases.append({'id': start['id'], 'name': start['name'], 'suite': suite, 'result': end['result'], 'skipped': end['skipped']})
            bucket = 'skipped' if end['skipped'] else ('passed' if end['result'] == 'success' else 'failed')
            counts[bucket] += 1
            per_suite[suite][bucket] += 1
        for kind in ['cases', 'errors']:
            path = self.gate / run[kind + '_file']
            self.check(self.sha_file(path) == run[kind + '_sha256'], name + ': ' + kind + ' file hash')
        self.check(cases == self.read_json(self.gate / run['cases_file']), name + ': exact raw case inventory')
        self.check(self.read_json(self.gate / run['errors_file']) == [], name + ': error inventory not empty')
        self.check(hidden == sum(run['excluded_events'].values()), name + ': hidden count')
        self.check(set(per_suite) == expected, name + ': empty requested suite')
        for key in ['passed', 'failed', 'skipped']:
            self.check(counts[key] == run[key], name + ': recorded ' + key + ' count')
        for suite, recorded in run['per_suite'].items():
            self.check(all(per_suite[suite][key] == recorded[key] for key in ['passed', 'failed', 'skipped']), name + ': per-suite recorded counts')
        self.check(run['command'][-len(group['tests']):] == group['tests'], name + ': exact command test targets')
        self.check('--concurrency=1' in run['command'] and '--reporter=json' in run['command'], name + ': serial machine reporter command')
        self.check(run['cwd'] == group['cwd'], name + ': command directory')
        for key in ['missing_requested_suites', 'unexpected_suites', 'empty_requested_suites', 'unfinished_reporter_events', 'protocol_anomalies']:
            self.check(not run[key], name + ': ' + key)
        self.check(run['reporter_error_count'] == 0 and run['reporter_success'] is True, name + ': accepted reporter result')
        return {'name': name, 'suites': len(expected), 'passed': counts['passed'], 'failed': counts['failed'], 'skipped': counts['skipped'], 'excluded_hidden_success_events': hidden, 'raw_log_sha256': digest(raw), 'exact_case_inventory_match': cases == self.read_json(self.gate / run['cases_file'])}

    def environment_path(self, name):
        if name.startswith('runtime/'):
            return self.runtime / name.removeprefix('runtime/')
        if name.startswith('additional/'):
            return Path(name.removeprefix('additional/'))
        if name == 'workspace/package_config.json':
            return self.repo / '.dart_tool/package_config.json'
        if name == 'workspace/native_assets.yaml':
            return self.repo / '.dart_tool/native_assets.yaml'
        if name.startswith('workspace/'):
            return self.repo / name.removeprefix('workspace/')
        if name == 'sdk/flutter_tools/package_config.json':
            return self.runtime / 'flutter/packages/flutter_tools/.dart_tool/package_config.json'
        raise ValueError('Unrecognized environment mapping: ' + name)

    def run(self):
        v = self.read_json(self.gate / 'verification.json')
        self.check(v['success'] is True and 'finished_at_utc' in v, 'gate incomplete or unsuccessful')
        self.check(v['source_commit'] == self.args.source, 'source commit mismatch')
        self.check(self.git('rev-parse', self.args.source + '^{tree}').decode().strip() == v['source_tree'], 'source tree mismatch')
        self.check(v['plan'] == self.args.plan, 'plan path mismatch')
        plan_bytes = self.frozen(self.args.plan)
        plan = json.loads(plan_bytes)
        self.check(digest(plan_bytes) == v['plan_sha256'] and plan['groups'] == v['planned_groups'], 'frozen plan hash/content mismatch')
        self.check(len({g['name'] for g in plan['groups']}) == len(plan['groups']), 'duplicate planned groups')
        planned_paths = [str(PurePosixPath(g['cwd']) / path) for g in plan['groups'] for path in g['tests']]
        self.check(len(set(planned_paths)) == len(planned_paths) == self.args.expected_suites, 'unique planned suite total')
        manifests = {}
        for name, expected in v['manifest_sha256'].items():
            data = (self.gate / name).read_bytes()
            self.check(digest(data) == expected, 'manifest receipt binding: ' + name)
            manifests[name] = json.loads(data)
        self.check(manifests['source-before.json'] == manifests['source-after.json'], 'source manifest changed')
        self.check(manifests['environment-before.json'] == manifests['environment-after.json'], 'environment manifest changed')
        source = manifests['source-before.json']
        env = manifests['environment-before.json']
        tree = {}
        for entry in self.git('ls-tree', '-r', '-z', self.args.source).split(b'\0'):
            if entry:
                metadata, path = entry.split(b'\t', 1)
                mode, _, blob = metadata.decode().split()
                tree[path.decode()] = mode, blob
        expected_inputs = {path for path in tree if path.startswith(('packages/', 'apps/', 'third_party/')) or ('/' not in path and Path(path).suffix in {'.yaml', '.lock'})}
        expected_inputs.update([self.args.plan, self.args.runner, *planned_paths, *v['analysis_files'], *v['formatted_files'], *plan.get('extra_inputs', [])])
        expected_inputs.update(item['path'] for item in plan['whitespace_preserved_inputs'])
        self.check(set(source) == expected_inputs, 'complete expected source inventory')
        self.check(len(source) == v['source_input_count'] == v['materialized_source_inputs'], 'materialized source count')
        self.check(not v['sparse_source_omissions'], 'sparse omissions')
        for path, item in source.items():
            self.check(tree.get(path) == (item['mode'], item['git_blob']), 'frozen source tree row: ' + path)
            self.check(item['materialized'] is True and item['sparse_omission'] is False, 'source materialization row: ' + path)
            self.check(self.sha_file(self.repo / path) == item['sha256'], 'materialized source bytes: ' + path)
        # Independently compare SHA-256 with the immutable Git objects themselves.
        query = ''.join(item['git_blob'] + '\n' for item in source.values()).encode()
        output = subprocess.run(['git', 'cat-file', '--batch'], input=query, stdout=subprocess.PIPE, check=True, cwd=self.repo).stdout
        stream = io.BytesIO(output)
        for path, item in source.items():
            obj, kind, size = stream.readline().decode().strip().split()
            self.check(obj == item['git_blob'] and kind == 'blob', 'Git blob lookup: ' + path)
            data = stream.read(int(size))
            self.check(stream.read(1) == b'\n' and digest(data) == item['sha256'], 'Git blob source SHA-256: ' + path)
        self.check(stream.read() == b'', 'Git blob stream trailing content')
        changed_dart = [p for p in self.git('diff', '--name-only', '--diff-filter=ACMRT', v['source_base'], self.args.source).decode().splitlines() if p.startswith(('apps/', 'packages/')) and p.endswith('.dart')]
        for key, target in [('analysis', 'analysis_files'), ('format', 'formatted_files')]:
            expected = changed_dart if plan[key] == 'changed' else plan[key]
            self.check(set(expected) == set(v[target]), 'full ' + key + ' target coverage')
        self.check(v['whitespace_preserved_inputs'] == plan['whitespace_preserved_inputs'], 'whitespace exception list')
        for entry in plan['whitespace_preserved_inputs']:
            self.check(source[entry['path']]['git_blob'] == entry['git_blob'] and entry['path'].startswith('docs/validation/') and not any(char in entry['path'] for char in '*?[('), 'exact whitespace exception: ' + entry['path'])
        groups = {g['name']: g for g in plan['groups']}
        expected_runs = list(groups) + (['analysis'] if v['analysis_files'] else []) + (['format'] if v['formatted_files'] else []) + ['whitespace']
        self.check([r['name'] for r in v['runs']] == expected_runs, 'exact completed command inventory/order')
        results = []
        for run in v['runs']:
            raw = (self.gate / run['log']).read_bytes()
            self.check(digest(raw) == run['log_sha256'], 'command log hash: ' + run['name'])
            compressed = (self.gate / run['compressed_log']).read_bytes()
            self.check(digest(compressed) == run['compressed_log_sha256'] and gzip.decompress(compressed) == raw, 'compressed/raw log match: ' + run['name'])
            self.check(run['exit_code'] == 0 and run['accepted'] is True and not run.get('runner_error'), 'command accepted: ' + run['name'])
            if run['name'] in groups:
                results.append(self.audit_group(run, groups[run['name']]))
            elif run['name'] == 'whitespace':
                expected = ['git', 'diff', '--check', v['source_base'], self.args.source, '--', '.', *[':(exclude)' + p['path'] for p in plan['whitespace_preserved_inputs']]]
                self.check(run['command'] == expected, 'whitespace command exact exclusions')
            elif run['name'] == 'analysis':
                self.check('--fatal-infos' in run['command'] and '--fatal-warnings' in run['command'], 'strict analysis flags')
                self.check(run['command'][4:] == v['analysis_files'], 'analysis exact command targets')
            elif run['name'] == 'format':
                self.check(run['command'][2:4] == ['--output=none', '--set-exit-if-changed'] and run['command'][4:] == v['formatted_files'], 'format exact command/targets')
        for key in ['passed', 'failed', 'skipped']:
            self.check(sum(row[key] for row in results) == v[key], 'actual total ' + key)
        self.check(sum(row['suites'] for row in results) == self.args.expected_suites, 'actual suite total')
        for key in ['source_unchanged', 'environment_unchanged', 'source_head_unchanged', 'source_index_unchanged', 'tracked_worktree_clean_before', 'tracked_worktree_clean_after']:
            self.check(v[key] is True, 'gate stability flag: ' + key)
        for key in ['source_mismatches', 'environment_mismatches', 'unexpected_native_mappings_after']:
            self.check(not v[key], 'gate stability discrepancies: ' + key)

        self.check(len(env) == v['runtime_input_count'], 'runtime inventory count')
        for name, expected in env.items():
            path = self.environment_path(name)
            actual = self.sha_file(path) if path.is_file() else None
            self.check(actual == expected, 'current runtime input: ' + name)
        receipt_data = (self.runtime / 'runtime.json').read_bytes()
        runtime = json.loads(receipt_data)
        self.check(digest(receipt_data) == v['runtime_receipt_sha256'], 'runtime receipt binding')
        self.check(runtime['status'] == 'ready' and runtime['archive']['verified'] is True, 'verified runtime receipt')
        self.check(runtime['runtime'] == v['runtime'], 'runtime version identity')
        self.check(runtime['workspace_lock_sha256'] == v['workspace_lock_sha256'] == source['pubspec.lock']['sha256'], 'locked dependencies')
        restore_runs = []
        self.check([run['name'] for run in runtime['runs']] == ['flutter-tools-pub-get', 'workspace-pub-get', 'native-assets-smoke', 'flutter-version'], 'fresh complete restore command coverage')
        for run in runtime['runs']:
            log_data = Path(run['log']).read_bytes()
            self.check(digest(log_data) == run['log_sha256'] and run['exit_code'] == 0, 'fresh restore command/hash: ' + run['name'])
            if run['name'] == 'native-assets-smoke':
                self.check(b'in-memory FTS5 passed' in log_data, 'fresh native SQLite FTS5 smoke result')
            restore_runs.append({'name': run['name'], 'exit_code': run['exit_code'], 'log_sha256': digest(log_data)})
        restore_source = 'docs/validation/document-review-notes-20261118/runtime/restore_runtime.py'
        smoke_source = 'docs/validation/document-review-notes-20261118/runtime/native_asset_smoke.dart'
        self.check(runtime['test_input_binding']['implementation_sha256'] == digest(self.frozen(restore_source)), 'fresh corrected restorer source binding')
        self.check(runtime['native_smoke']['source_sha256'] == runtime['native_smoke']['entrypoint_sha256'] == digest(self.frozen(smoke_source)), 'fresh staged native smoke exact source binding')
        self.check(runtime['native_smoke']['owning_package'] == 'quds_mail_store', 'native smoke package ownership')
        self.check(not Path(runtime['native_smoke']['entrypoint']).parent.exists(), 'generated native smoke entrypoint cleaned')
        retained = self.read_json(self.runtime / 'retained-inputs.json')
        for path, item in retained.items():
            self.check(env.get('runtime/' + path) == item['sha256'], 'retained runtime mapping: ' + path)
        for path, expected in runtime['additional_inputs'].items():
            self.check(v['additional_runtime_inputs'].get(path) == env.get('additional/' + path) == expected, 'native/Node receipt mapping: ' + path)
        icon = 'runtime/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        self.check(isinstance(env.get(icon), str), 'real icon font present and bound')
        font_paths = ['packages/quds_office_editor/fonts/LiberationSans-Regular.ttf', 'packages/quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf']
        for path in font_paths:
            self.check(path in source, 'real text font source bound: ' + path)
        self.report.update({'source_commit': self.args.source, 'source_tree': v['source_tree'], 'gate_receipt_sha256': self.sha_file(self.gate / 'verification.json'), 'plan': self.args.plan, 'plan_sha256': digest(plan_bytes), 'groups': results, 'actual_dart_flutter_cases': sum(r['passed'] for r in results), 'failed': sum(r['failed'] for r in results), 'skipped': sum(r['skipped'] for r in results), 'unique_suites': sum(r['suites'] for r in results), 'source_inputs_reverified': len(source), 'runtime_inputs_reverified': len(env), 'analysis_format_targets': {'analysis': len(v['analysis_files']), 'format': len(v['formatted_files'])}, 'exact_whitespace_exceptions': len(plan['whitespace_preserved_inputs']), 'real_fonts_bound': [icon, *font_paths], 'source_manifests_equal': manifests['source-before.json'] == manifests['source-after.json'], 'environment_manifests_equal': manifests['environment-before.json'] == manifests['environment-after.json']})
        self.report['layout_diagnostic_scan'] = {'raw_logs_scanned': len(self.layout_scan), 'total_findings': sum(len(row['findings']) for row in self.layout_scan), 'logs': self.layout_scan}
        self.report['fresh_runtime_restore'] = {'receipt_sha256': digest(receipt_data), 'status': runtime['status'], 'runs': restore_runs, 'archive': runtime['archive'], 'source_implementation_sha256': runtime['test_input_binding']['implementation_sha256'], 'smoke_source_sha256': runtime['native_smoke']['source_sha256'], 'staged_smoke_source_matches': runtime['native_smoke']['source_sha256'] == runtime['native_smoke']['entrypoint_sha256'], 'generated_smoke_entrypoint_removed': not Path(runtime['native_smoke']['entrypoint']).parent.exists()}
        if self.args.python_evidence:
            self.audit_python(self.args.python_evidence.resolve())
        if self.args.runtime_helper_receipt:
            self.audit_runtime_helper(self.args.runtime_helper_receipt.resolve())
        if self.args.original_runtime:
            self.audit_original_runtime(self.args.original_runtime.resolve())
        if self.args.runtime_provenance:
            self.audit_runtime_provenance(self.args.runtime_provenance.resolve())

    def audit_python(self, root):
        summary = self.read_json(root / 'independent-summary.json')
        checked = []
        bound = {}
        all_case_ids = []
        for target in summary['targets']:
            name = target['name']
            receipt_path = root / target['receipt']
            receipt = self.read_json(receipt_path)
            raw = (root / target['log']).read_bytes()
            self.check(digest(raw) == target['log_sha256'] == receipt['raw_log_sha256'], name + ': Python log binding')
            self.check(self.sha_file(receipt_path) == target['receipt_sha256'], name + ': Python receipt binding')
            count_matches = re.findall(rb'Ran (\d+) tests? in [^\n]+\n\s*\nOK\s*$', raw)
            self.check(len(count_matches) == 1, name + ': Python successful terminal')
            count = int(count_matches[0])
            case_rows = re.findall(r'^(test\S+) \(([^)]+)\) \.\.\. (ok|FAIL|ERROR|skipped[^\n]*)$', raw.decode(), flags=re.MULTILINE)
            derived = [{'id': owner + '.' + method, 'result': result} for method, owner, result in case_rows]
            self.check(len(derived) == count and len({row['id'] for row in derived}) == count and all(row['result'] == 'ok' for row in derived), name + ': Python distinct actual cases')
            self.check(derived == receipt['cases'], name + ': Python raw case inventory equality')
            all_case_ids.extend(name + '::' + row['id'] for row in derived)
            self.check(count == target['actual_cases'] == receipt['actual_cases'] and receipt['exit_code'] == 0 and receipt['passed'] is True, name + ': Python actual counts/result')
            before = self.read_json(receipt_path.parent / 'source-before.json')
            after = self.read_json(receipt_path.parent / 'source-after.json')
            self.check(before == after and receipt['source_unchanged'] is True, name + ': Python source stability')
            for path, expected in before.items():
                data = self.frozen(path)
                self.check(len(data) == expected['bytes'] and digest(data) == expected['sha256'], name + ': Python source frozen binding: ' + path)
                self.check(path not in bound or bound[path] == expected, name + ': inconsistent repeated Python source binding: ' + path)
                bound[path] = expected
            self.check(self.sha_file(Path(receipt['python_executable'])) == receipt['python_executable_sha256'], name + ': Python executable binding')
            checked.append({'name': name, 'actual_cases': count, 'source_inputs_reverified': len(before), 'raw_log_sha256': digest(raw)})
        self.check(len(checked) == 7 and sum(row['actual_cases'] for row in checked) == summary['actual_cases'] == 143, 'seven accepted Python targets / 143 cases')
        self.check(all_case_ids == summary['case_ids'] and len(set(all_case_ids)) == 143, 'Python aggregate distinct case inventory')
        self.check(bound == summary['source_inputs'] and len(bound) == summary['bound_input_count'] == 23, 'Python aggregate 23-input binding')
        excluded = []
        for attempt in summary.get('excluded_attempts', []):
            receipt_path = root / attempt['receipt']
            receipt = self.read_json(receipt_path)
            raw = (receipt_path.parent / 'raw.log').read_bytes()
            self.check(receipt['passed'] is False and receipt['exit_code'] != 0, 'excluded Python attempt remains failed')
            self.check(digest(raw) == receipt['raw_log_sha256'] == attempt['raw_log_sha256'], 'excluded Python attempt raw-log binding')
            self.check(b'FAILED (failures=1)' in raw, 'excluded Python attempt preserves failing raw result')
            excluded.append({'receipt': attempt['receipt'], 'raw_log_sha256': digest(raw), 'failed': True, 'counted_in_accepted_total': False})
        self.report['separate_python_groups'] = checked
        self.report['separate_python_cases'] = sum(row['actual_cases'] for row in checked)
        self.report['separate_python_source_inputs'] = len(bound)
        self.report['excluded_python_attempts'] = excluded

    def audit_runtime_helper(self, path):
        receipt = self.read_json(path)
        raw = Path(receipt['log']['path']).read_bytes()
        self.check(len(raw) == receipt['log']['bytes'] and digest(raw) == receipt['log']['sha256'], 'runtime helper original log binding')
        rows = re.findall(r'^(test\S+) \(([^)]+)\) \.\.\. (ok|FAIL|ERROR|skipped[^\n]*)$', raw.decode(), flags=re.MULTILINE)
        self.check(len(rows) == len({owner for _, owner, _ in rows}) == receipt['actual_cases'] == 4 and all(result == 'ok' for _, _, result in rows), 'four distinct successful runtime helper cases')
        self.check([method for method, _, _ in rows] == receipt['cases'], 'runtime helper exact case names')
        self.check(re.search(rb'Ran 4 tests in [^\n]+\n\s*\nOK\s*$', raw) is not None, 'runtime helper successful raw terminal')
        self.check(receipt['status'] == 'passed' and receipt['process_exit_code'] == 0 and receipt['raw_summary_ok'] is True, 'runtime helper qualified process result')
        self.check(receipt['source_before'] == receipt['source_after'] and receipt['inputs_unchanged'] is True, 'runtime helper unchanged source inputs')
        for source, expected in receipt['source_before'].items():
            data = self.frozen(source)
            self.check(len(data) == expected['bytes'] and digest(data) == expected['sha256'], 'runtime helper frozen source: ' + source)
        self.check(self.sha_file(receipt['python']['executable']) == receipt['python']['sha256_before'] == receipt['python']['sha256_after'], 'runtime helper Python executable')
        self.check(receipt['temporary_children_after'] == [], 'runtime helper temporary children cleaned')
        original = receipt['original_observation']
        self.check(self.sha_file(original['path']) == original['sha256'] and original['aggregate_contribution'] == 0, 'original unqualified helper observation retained and excluded')
        old = self.read_json(original['path'])
        self.check(self.sha_file(old['log']['path']) == old['log']['sha256'] and old['process_exit_code'] is None, 'original helper raw log and process-status limitation retained')
        self.report['separate_runtime_helper_controls'] = {'receipt_sha256': self.sha_file(path), 'qualified_successful_cases': 4, 'log_sha256': digest(raw), 'frozen_sources_verified': len(receipt['source_before']), 'process_exit_code': 0, 'original_observation_sha256': original['sha256'], 'original_observation_aggregate_contribution': 0, 'included_in_143_python_cases': False, 'included_in_dart_flutter_cases': False}
        if 'separate_python_cases' in self.report:
            self.report['combined_python_cases_without_repeats'] = self.report['separate_python_cases'] + 4

    def audit_original_runtime(self, root):
        path = root / 'runtime-initial-failed.json'
        receipt = self.read_json(path)
        self.check(receipt['status'] == 'failed', 'original initial runtime receipt remains failed')
        failed = [run for run in receipt['runs'] if run['exit_code'] != 0]
        self.check(any(run['name'] == 'native-assets-smoke' and run['exit_code'] == 255 for run in failed), 'original restore retains native smoke failure')
        for run in failed:
            self.check(self.sha_file(run['log']) == run['log_sha256'], 'original failed restore log preserved: ' + run['name'])
        self.report['original_runtime_repair_provenance'] = {'receipt_sha256': self.sha_file(path), 'receipt_status': receipt['status'], 'failed_commands_preserved': [{'name': run['name'], 'exit_code': run['exit_code'], 'log_sha256': run['log_sha256']} for run in failed], 'error_preserved': bool(receipt.get('error')), 'interpretation': 'Original failed restore is preserved separately from the later diagnostic recovery. The separate fresh runtime receipt and successful four-command run bind the accepted corrected restoration.'}

    def audit_runtime_provenance(self, path):
        receipt = self.read_json(path)
        runtime = self.read_json(self.runtime / 'runtime.json')
        self.check(receipt['fresh_restore_process_exit_code'] == 0 and '--node-tests' in receipt['command'], 'fresh full node-tests restore process result')
        self.check(receipt['implementation_sha256'] == digest(self.frozen('docs/validation/document-review-notes-20261118/runtime/restore_runtime.py')), 'runtime provenance frozen restorer source')
        self.check(receipt['runs'] == runtime['runs'] and receipt['archive'] == runtime['archive'], 'fresh runtime provenance receipt alignment')
        for key in ['runtime_receipt', 'outer_log', 'original_failure_receipt', 'native_mapping']:
            item = receipt[key]
            self.check(self.sha_file(item['path']) == item['sha256'], 'runtime provenance raw binding: ' + key)
        for filename, expected in receipt['native_libraries'].items():
            self.check(self.sha_file(filename) == expected == '0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b', 'pinned native library: ' + filename)
        diagnostic = receipt['diagnostic_outputs_preserved_before_clean_restore']
        archive = Path(diagnostic['archive']).read_bytes()
        self.check(digest(archive) == diagnostic['archive_sha256'], 'original diagnostic archive hash')
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:xz') as handle:
            members = [member for member in handle.getmembers() if member.isfile()]
            self.check(len(members) == len(diagnostic['files']) == 13 and {member.name for member in members} == set(diagnostic['files']), 'original diagnostic archive 13-file coverage')
            for member in members:
                data = handle.extractfile(member).read()
                expected = diagnostic['files'][member.name]
                self.check(len(data) == expected['bytes'] and digest(data) == expected['sha256'], 'original diagnostic archive member: ' + member.name)
        snapshot_root = Path(__file__).parent / 'runtime_provenance'
        hook_rows = []
        for item in receipt['genuine_hook_records']:
            data = (snapshot_root / Path(item['path']).name).read_bytes()
            self.check(digest(data) == item['sha256'] and json.loads(data) == item['content'], 'independent hook raw snapshot binding: ' + item['path'])
            hook_rows.append({'name': Path(item['path']).name, 'sha256': digest(data)})
        self.report['runtime_repair_evidence'] = {'receipt_sha256': self.sha_file(path), 'fresh_restore_process_exit_code': receipt['fresh_restore_process_exit_code'], 'outer_log_sha256': receipt['outer_log']['sha256'], 'original_failure_receipt_sha256': receipt['original_failure_receipt']['sha256'], 'diagnostic_archive_sha256': diagnostic['archive_sha256'], 'diagnostic_archive_members_reverified': len(members), 'genuine_hook_raw_snapshots': hook_rows, 'both_sqlite_libraries_match_pinned_hash': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--gate', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--source', required=True)
    parser.add_argument('--plan', required=True)
    parser.add_argument('--runner', default='docs/validation/document-review-notes-20261118/run_checks.py')
    parser.add_argument('--expected-suites', type=int, default=79)
    parser.add_argument('--python-evidence', type=Path)
    parser.add_argument('--runtime-helper-receipt', type=Path)
    parser.add_argument('--original-runtime', type=Path)
    parser.add_argument('--runtime-provenance', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    audit = Audit(args)
    try:
        audit.run()
    except Exception as error:
        import traceback
        audit.issues.append('Audit could not complete: ' + repr(error))
        traceback.print_exc()
    audit.report.update({'audited_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'method': 'Independent raw JSON event recount, immutable Git blob SHA-256 comparisons, actual runtime inventory readback, and original Python-log recount. No repository reporter/parser imported, application tests executed, or GitHub Actions queried.', 'audit_script_sha256': digest(Path(__file__).read_bytes()), 'issues': audit.issues, 'passed': not audit.issues})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(audit.report, indent=2) + '\n')
    print(json.dumps(audit.report, indent=2))
    raise SystemExit(bool(audit.issues))


if __name__ == '__main__':
    main()
