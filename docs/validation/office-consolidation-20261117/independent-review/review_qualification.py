#!/usr/bin/env python3
"""Independent reconstruction of the frozen f5021f1c local qualification.

This audit does not import or execute any qualification, consumer, or project
test code. It reads raw reporter events, unittest output, committed sources,
hash maps, and the previous published qualification's selected-file plan.
"""

import ast
import collections
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile


BASE = Path('/workspace/scratch/2a07827fdeed')
REPO = BASE / 'quds_office_suite'
RUN = BASE / 'qualification-final'
OUT = BASE / 'independent-review'
SOURCE = 'f5021f1c364baf010049fda2dd4bf7f414deda79'
TREE = 'afd7a513dfa91472f58c27ead4d8be3f4b75c262'
PACKAGES = {
    'engine': 'packages/quds_office_engine',
    'editor': 'packages/quds_office_editor',
    'aot': 'packages/quds_proofing_aot',
    'gector': 'packages/quds_proofing_gector',
    'harper': 'packages/quds_proofing_harper',
    'studio': 'packages/quds_office_editor/example',
}
PDF_NAMES = {
    'JPEG with DCT SMask attaches softMaskJpeg for the host',
    'TrueType subsets without cmap get ToUnicode cmap for the host',
}
PRIVATE_PDF = Path('/home/mohammed/Desktop/al_tahreer_profile.pdf')
NATIVE_NAME = 'real native dual heads own their output and reject use after dispose'
PY_MODULES = [
    'test_export_reference', 'test_qualification', 'test_native_pack',
    'test_native_qualification', 'test_gector_aot_build',
    'test_guarded_provider_comparison', 'test_candidate_admission',
]
NEW_FILES = {
    ('aot', 'test/client_test.dart'),
    ('aot', 'test/german_rules_test.dart'),
    ('aot', 'test/models_test.dart'),
    ('aot', 'test/provider_test.dart'),
    ('aot', 'test/transport_test.dart'),
    ('aot', 'test/upstream_morphology_test.dart'),
    ('engine', 'test/odt_paragraph_decoration_resume_test.dart'),
    ('engine', 'test/odt_table_tab_fidelity_test.dart'),
    ('engine', 'test/proofing/german_noun_agreement_test.dart'),
    ('studio', 'test/studio_aot_test.dart'),
    ('studio', 'test/widget_test.dart'),
}
checks = 0
failures = []
report = {
    'schema': 'independent-qualification-audit-v1',
    'source_commit': SOURCE,
    'source_tree': TREE,
    'qualification_root': str(RUN),
    'scope': (
        'Raw Dart/Flutter event reconstruction; prior selected-file preservation; '
        'VM/Node case identity and outcome parity; Python source enumeration and '
        'raw unittest outcomes; six analysis scopes; format and generated-data '
        'checks; independent before/after/current input hashes. Audit checks are '
        'not additional product test cases. Producer code is not imported.'
    ),
}


def check(condition, name, detail=None):
    global checks
    checks += 1
    if not condition:
        failures.append({'check': name, 'detail': detail})


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while block := stream.read(1024 * 1024):
            h.update(block)
    return h.hexdigest()


def read_json(path):
    return json.loads(Path(path).read_bytes())


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def hash_map(mapping, label, links=False):
    for name, expected in mapping.items():
        path = Path(name)
        if expected is None:
            check(not path.exists(), label + ': absent fixture', name)
        elif links and path.is_symlink():
            check(sha(os.readlink(path).encode()) == expected,
                  label + ': symlink target hash', name)
        else:
            check(path.is_file(), label + ': file exists', name)
            if path.is_file():
                check(file_sha(path) == expected, label + ': current hash', name)


def selected_files(plan):
    return [(group['kind'], path)
            for group in plan['cohorts'].values() for path in group['tests']]


def audit_scope(plan):
    old_archive = REPO / (
        'docs/validation/office-recovery-20261117/qualification/evidence/'
        'qualification-966196f3.tar.xz')
    with tarfile.open(old_archive, 'r:xz') as archive:
        old_bytes = archive.extractfile('qualification/plan.json').read()
    old_plan = json.loads(old_bytes)
    old = selected_files(old_plan)
    now = selected_files(plan)
    check(len(old) == len(set(old)) == 180, 'prior 180 files are distinct')
    check(len(now) == len(set(now)) == 191, 'current 191 files are distinct')
    check(set(old) <= set(now), 'every prior selected file retained',
          sorted(set(old) - set(now)))
    check(set(now) - set(old) == NEW_FILES, 'exact eleven file additions',
          sorted(set(now) - set(old)))
    check(plan['unique_test_files'] == 191, 'plan unique-file total')
    check(plan['source_commit'] == SOURCE, 'plan source commit')
    check(set(plan['coverage_exclusions_if_private_pdf_absent']) == PDF_NAMES,
          'exactly two named private PDF exclusions')
    report['scope_preservation'] = {
        'baseline_archive': str(old_archive),
        'baseline_plan_sha256': sha(old_bytes),
        'prior_file_count': len(old), 'primary_file_count': len(now),
        'missing_prior_files': sorted(set(old) - set(now)),
        'new_files': [{'kind': k, 'path': p} for k, p in sorted(set(now) - set(old))],
    }


def audit_input_maps(receipt):
    kinds = ['source', 'dependencies', 'runtime', 'workspace', 'harness',
             'system', 'native_fixtures']
    maps = {}
    for kind in kinds:
        before = read_json(RUN / (kind + '-before.json'))
        after = read_json(RUN / (kind + '-after.json'))
        check(before == after, kind + ': before and after exact equality')
        check(receipt['input_integrity'].get(kind + '_unchanged') is True,
              kind + ': receipt identity claim')
        maps[kind] = before
    source = maps['source']
    entries = {}
    for item in git('ls-tree', '-r', '-z', SOURCE).split(b'\0'):
        if not item:
            continue
        metadata, path = item.split(b'\t', 1)
        mode, object_type, oid = metadata.decode().split()
        entries[path.decode()] = (mode, object_type, oid)
    selected = {p for p in entries if not p.startswith('docs/')}
    check(set(source['files']) == selected,
          'source map covers every committed non-documentation file')
    check(source['count'] == len(selected) == 3483, 'source map exact file count')
    check(source['commit_mismatches'] == [], 'source has no commit mismatches')
    check(source['untracked_non_evidence_paths'] == [],
          'source has no untracked non-evidence files')
    for path, item in source['files'].items():
        mode, object_type, oid = entries[path]
        check(object_type == 'blob', 'source object is a blob', path)
        check((item['git_mode'], item['git_blob']) == (mode, oid),
              'source snapshot identity matches frozen Git tree', path)
        local = REPO / path
        data = os.readlink(local).encode() if mode == '120000' else local.read_bytes()
        check(sha(data) == item['sha256'], 'source current SHA256', path)
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        check(blob == oid, 'source current bytes equal frozen Git blob', path)
    deps = maps['dependencies']
    check(deps['count'] == len(deps['sha256_by_path']) == 5099,
          'dependency map exact file count')
    check(len(deps['package_roots']) == 99, 'dependency package root count')
    hash_map(deps['sha256_by_path'], 'dependency')
    for kind in ['runtime', 'workspace', 'harness', 'system']:
        hash_map(maps[kind], kind, links=(kind == 'workspace'))
    for var, item in maps['native_fixtures'].items():
        path = Path(item['path'])
        check(path.stat().st_size == item['bytes'], 'native fixture size', var)
        check(file_sha(path) == item['sha256'], 'native fixture hash', var)
    check(set(maps['native_fixtures']) == {'GECTOR_TEST_LIBRARY', 'GECTOR_TEST_MODEL'},
          'both native fixture identities present')
    check(maps['system'].get(str(PRIVATE_PDF)) is None and not PRIVATE_PDF.exists(),
          'inherited private PDF fixture absent before, after, and at audit')
    check(git('rev-parse', SOURCE + '^{tree}').decode().strip() == TREE,
          'source commit resolves to recorded Git tree')
    check(receipt['source_tree'] == TREE, 'receipt frozen source tree')
    check(receipt['working_head_after'] == SOURCE, 'run ended on frozen source HEAD')
    check(receipt['source_matches_frozen_commit'] is True, 'receipt source frozen claim')
    check(receipt['analysis_config_restored'] is True, 'analysis config restored claim')
    config = REPO / '.dart_tool/package_config.json'
    check(receipt['original_analyzer_config_sha256'] is None and not config.exists(),
          'temporary analyzer config is absent, matching original state')
    check(file_sha(RUN / 'plan.json') == receipt['plan_sha256'], 'plan receipt SHA256')
    check(file_sha(RUN / 'run-used.py') == receipt['runner_sha256'], 'runner receipt SHA256')
    lock = Path(receipt['test_workspace']) / 'pubspec.lock'
    check(file_sha(lock) == receipt['enforced_workspace_lock_sha256'],
          'isolated workspace uses recorded pinned dependency lock')
    pinned_lock = 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
    committed_lock = git('show', SOURCE + ':' + pinned_lock)
    check(lock.read_bytes() == committed_lock,
          'isolated dependency lock equals committed pinned workspace lock')
    report['input_integrity'] = {
        'source_files': len(selected), 'dependency_files': len(deps['sha256_by_path']),
        'dependency_package_roots': len(deps['package_roots']),
        'runtime_files': len(maps['runtime']), 'workspace_entries': len(maps['workspace']),
        'harness_files': len(maps['harness']), 'system_entries': len(maps['system']),
        'native_fixture_files': len(maps['native_fixtures']),
        'before_after_exact': True,
        'current_hashes_recomputed': True,
        'source_file_selection': 'All 3,483 tracked paths outside docs/ in the frozen Git tree.',
        'native_fixtures': maps['native_fixtures'],
    }


def command_logs(command):
    name = command['name']
    check(command['status'] == 'passed' and command['exit_code'] == 0,
          'command completed successfully', name)
    check(command['timed_out'] is False, 'command did not time out', name)
    check(command['duration_seconds'] < command['timeout_seconds'],
          'command finished within deadline', name)
    streams = {}
    for channel in ['stdout', 'stderr']:
        compressed = (RUN / command[channel]).read_bytes()
        content = gzip.decompress(compressed)
        check(sha(compressed) == command[channel + '_gzip_sha256'],
              'compressed log hash', (name, channel))
        check(sha(content) == command[channel + '_sha256'],
              'raw log hash', (name, channel))
        streams[channel] = content.decode('utf-8')
    return streams


def audit_events(name, command, group, streams, is_node):
    events = []
    malformed = []
    for line_number, line in enumerate(streams['stdout'].splitlines(), 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            if not isinstance(event, dict) or 'type' not in event:
                raise ValueError('not a reporter event')
            events.append(event)
        except (ValueError, TypeError):
            malformed.append(line_number)
    check(not malformed, name + ': every nonempty line is a reporter event', malformed)
    check(not streams['stderr'].strip(), name + ': stderr empty')
    by_type = collections.defaultdict(list)
    for e in events:
        by_type[e['type']].append(e)
    check(len(by_type['start']) == 1 and events[0]['type'] == 'start',
          name + ': exactly one opening runner start')
    check(len(by_type['done']) == 1 and events[-1]['type'] == 'done'
          and by_type['done'][0]['success'] is True,
          name + ': exactly one final successful runner completion')
    check(not by_type['error'], name + ': no raw error events')
    check(len(by_type['allSuites']) == 1
          and by_type['allSuites'][0]['count'] == len(group['tests']),
          name + ': declared selected suite count')
    suite_records = [e['suite'] for e in by_type['suite']]
    suites = {s['id']: s for s in suite_records}
    check(len(suites) == len(suite_records) == len(group['tests']),
          name + ': exact distinct suite count')
    package = REPO / PACKAGES[group['kind']]
    expected_paths = {(package / p).resolve() for p in group['tests']}
    actual_paths = {(Path(command['cwd']) / s['path']).resolve() for s in suites.values()}
    check(actual_paths == expected_paths, name + ': all and only selected suites',
          {'missing': sorted(map(str, expected_paths - actual_paths)),
           'extra': sorted(map(str, actual_paths - expected_paths))})
    starts_list = [e['test'] for e in by_type['testStart']]
    starts = {s['id']: s for s in starts_list}
    done_list = by_type['testDone']
    done = {d['testID']: d for d in done_list}
    check(len(starts) == len(starts_list), name + ': no duplicate test starts')
    check(len(done) == len(done_list), name + ': no duplicate test completions')
    check(set(starts) == set(done), name + ': every start has exactly one completion')
    args = command['command']
    explicit_tests = [x for x in args if x.startswith('test/') and x.endswith('.dart')]
    check(explicit_tests == group['tests'], name + ': command exact selected tests')
    filters = ['--name', '--plain-name', '--tags', '--exclude-tags', '--run-skipped']
    check(not any(a == f or a.startswith(f + '=') for a in args for f in filters),
          name + ': no case filters or forced skipped execution')
    expected_platform = 'node' if is_node else 'vm'
    check(all(s['platform'] == expected_platform for s in suites.values()),
          name + ': actual runner platform')
    uses_flutter = any(a.endswith('/flutter_tools.snapshot') for a in args)
    check(uses_flutter == (group['kind'] in {'editor', 'studio'}),
          name + ': actual Flutter runner for editor and studio suites')
    if uses_flutter:
        check('--no-pub' in args, name + ': frozen dependency resolution for Flutter')
    if is_node:
        check('--platform=node' in args, name + ': Node command platform')
    groups = {e['group']['id']: e['group'] for e in by_type['group']}
    rows, hidden = [], []
    for tid, start in starts.items():
        finish = done.get(tid, {})
        check(start['suiteID'] in suites, name + ': test belongs to known suite', tid)
        check(start.get('metadata', {}).get('skip') is False,
              name + ': test start not marked skipped', tid)
        check(finish.get('result') == 'success' and finish.get('skipped') is False,
              name + ': test completion successful and not skipped', tid)
        suite = suites[start['suiteID']]
        path = (Path(command['cwd']) / suite['path']).resolve()
        row = {'kind': group['kind'], 'path': path.relative_to(package).as_posix(),
               'name': start['name'], 'result': finish.get('result'),
               'skipped': finish.get('skipped'), 'test_id': tid,
               'suite_id': start['suiteID'], 'hidden': finish.get('hidden', False)}
        if finish.get('hidden'):
            hidden.append(row)
            check(start['name'].startswith('loading ') or
                  start['name'] in {'(setUpAll)', '(tearDownAll)'},
                  name + ': hidden event is loader or suite lifecycle', start['name'])
        else:
            rows.append(row)
            check(bool(start['groupIDs']) and all(g in groups for g in start['groupIDs']),
                  name + ': visible test belongs to declared group', tid)
    loader_rows = [r for r in hidden if r['name'].startswith('loading ')]
    check(len(loader_rows) == len(suites), name + ': exactly one loader per suite')
    check(len({r['suite_id'] for r in loader_rows}) == len(suites),
          name + ': loader coverage every suite')
    for sid in suites:
        roots = [g for g in groups.values() if g['suiteID'] == sid and g['parentID'] is None]
        visible = [r for r in rows if r['suite_id'] == sid]
        check(len(roots) == 1 and roots[0]['testCount'] == len(visible),
              name + ': root group count equals executed visible cases', sid)
    excluded = []
    if name == 'engine-integration':
        excluded = [r for r in rows if r['path'] == 'test/pdf_file_test.dart'
                    and r['name'] in PDF_NAMES]
        check({r['name'] for r in excluded} == PDF_NAMES and len(excluded) == 2,
              name + ': exactly two named early-return private PDF cases')
    raw_count = len(rows)
    substantive = raw_count - len(excluded)
    producer = command['test_summary']
    check(producer['raw_success_count'] == raw_count,
          name + ': independently reconstructed raw successes agree')
    check(producer['substantive_success_count'] == substantive,
          name + ': independently reconstructed substantive successes agree')
    check(producer['raw_runner_outcomes'] == {'success': raw_count},
          name + ': independently reconstructed outcome histogram agrees')
    expected_completed = collections.Counter(
        (r['name'], r['result'], str(package / r['path']), r['suite_id'], r['test_id'])
        for r in rows)
    reported_completed = collections.Counter(
        (r['name'], r['outcome'], r['resolved_suite_path'], r['suite_id'], r['test_id'])
        for r in producer['completed_tests'])
    check(expected_completed == reported_completed,
          name + ': every receipt case identity agrees with raw events')
    for key in ['allowed_skipped_cases', 'unexpected_skipped_cases',
                'duplicate_test_completion_ids', 'duplicate_test_start_ids',
                'errors', 'missing_selected_suites', 'missing_test_completions',
                'unexpected_suites']:
        check(not producer[key], name + ': no reported ' + key)
    return {
        'suite_count': len(suites), 'runner_starts': len(by_type['start']),
        'runner_completions': len(by_type['done']),
        'test_starts': len(starts), 'test_completions': len(done),
        'hidden_loader_completions': len(loader_rows),
        'hidden_lifecycle_completions': len(hidden) - len(loader_rows),
        'raw_success_count': raw_count, 'substantive_success_count': substantive,
        'private_pdf_exclusion_count': len(excluded), 'skips': 0, 'failures': 0,
        'events_by_type': {k: len(v) for k, v in by_type.items() if v},
        'case_rows': rows,
    }


def audit_analysis_format(plan, commands, logs):
    expected_kinds = {'engine', 'editor', 'aot', 'gector', 'harper', 'studio'}
    check(set(plan['analysis_targets']) == expected_kinds, 'six strict analysis scopes')
    for kind, targets in plan['analysis_targets'].items():
        name = kind + '-strict-analysis'
        args = commands[name]['command']
        check(args[1:3] == ['analyze', '--fatal-infos'] and args[3:] == targets,
              name + ': strict flag and exact planned targets')
        check('No issues found!' in logs[name]['stdout'],
              name + ': raw analyzer output reports no issues')
        check(not logs[name]['stderr'].strip(), name + ': empty analyzer stderr')
    fmt = commands['format']['command']
    check(fmt[1:5] == ['format', '--language-version=3.12', '--output=none',
                       '--set-exit-if-changed'], 'format strict language and write policy')
    check(fmt[5:] == plan['format_targets'] and len(fmt[5:]) == 101,
          'format exact 101 handwritten targets')
    check(re.fullmatch(r'Formatted 101 files \(0 changed\) in [0-9.]+ seconds\.\n?',
                       logs['format']['stdout']) is not None,
          'format raw output reports zero changed files')
    check(not logs['format']['stderr'].strip(), 'format stderr empty')
    generated = plan['generated_data_manifest_check']
    excluded = plan['generated_format_exclusions']
    check(len(generated) == 34 and len(excluded) == 18,
          'exact generated data and format-exclusion counts')
    check(set(excluded) <= set(generated), 'all generated format exclusions hash checked')
    for path, row in generated.items():
        check(file_sha(REPO / path) == row['sha256'], 'generated output hash', path)
        manifest_bytes = (REPO / row['manifest']).read_bytes()
        check(sha(manifest_bytes) == row['manifest_sha256'], 'generated manifest hash', path)
        check(row['sha256'] in manifest_bytes.decode(),
              'generated output hash included in committed manifest', path)
    report['static_validation'] = {
        'analysis_scope_count': 6,
        'analysis_target_counts': {k: len(v) for k, v in plan['analysis_targets'].items()},
        'handwritten_format_targets': 101, 'format_language_version': '3.12',
        'format_changes': 0, 'generated_outputs_hash_checked': len(generated),
        'generated_format_exclusions': len(excluded),
    }


def audit_python(command, streams):
    summary = read_json(RUN / 'python-controls-summary.json')
    check(file_sha(RUN / 'python-controls-summary.json') == command['python_summary_sha256'],
          'Python summary exact recorded hash')
    check(summary['modules'] == PY_MODULES, 'Python exact seven selected modules')
    expected_ids = []
    module_counts = {}
    sources = {}
    for mod in PY_MODULES:
        path = REPO / 'tools/proofing/german_model' / (mod + '.py')
        sources[str(path)] = file_sha(path)
        tree = ast.parse(path.read_text(), filename=str(path))
        ids = []
        for cls in tree.body:
            if not isinstance(cls, ast.ClassDef):
                continue
            is_case = any((isinstance(b, ast.Attribute) and b.attr == 'TestCase')
                          or (isinstance(b, ast.Name) and b.id == 'TestCase')
                          for b in cls.bases)
            if not is_case:
                continue
            for method in cls.body:
                if isinstance(method, (ast.FunctionDef, ast.AsyncFunctionDef)) and method.name.startswith('test_'):
                    ids.append(f'{mod}.{cls.name}.{method.name}')
        expected_ids.extend(ids)
        module_counts[mod] = len(ids)
    check(len(expected_ids) == len(set(expected_ids)) == 117,
          'Python source independently declares 117 distinct tests')
    check(summary['test_source_sha256'] == sources,
          'Python recorded source identities match independently read files')
    stderr = streams['stderr']
    marker = re.compile(r'^test_\w+ \(([^()]+)\) \.\.\. ', re.MULTILINE)
    matches = list(marker.finditer(stderr))
    raw_ids = []
    for i, match in enumerate(matches):
        test_id = match.group(1)
        raw_ids.append(test_id)
        end = matches[i + 1].start() if i + 1 < len(matches) else len(stderr)
        body = stderr[match.end():end]
        check(re.search(r'^ok\s*$', body, re.MULTILINE) is not None,
              'Python raw unittest test passed', test_id)
        check(re.search(r'^(?:FAIL|ERROR|skipped\b|expected failure|unexpected success)',
                        body, re.MULTILINE) is None,
              'Python raw unittest no failure or skip', test_id)
    expected = collections.Counter(expected_ids)
    check(collections.Counter(raw_ids) == expected,
          'Python raw log covers every source-declared test exactly once')
    for key in ['selected_test_ids', 'successful_test_ids']:
        check(collections.Counter(summary[key]) == expected,
              'Python receipt exact ' + key)
    check(re.search(r'Ran 117 tests in [0-9.]+s\s+OK\s*$', stderr) is not None,
          'Python raw unittest terminal success count')
    for key in ['skipped_cases', 'unexpected_skipped_cases', 'missing_selected_tests',
                'failures', 'errors', 'expected_failures', 'unexpected_successes']:
        check(not summary[key], 'Python empty ' + key)
    check(summary['tests_run'] == summary['substantive_success_count'] == 117
          and summary['passed'] is True, 'Python substantive count agrees')
    check(summary['runtime_before'] == summary['runtime_after']
          and summary['runtime_unchanged'] is True,
          'Python before and after runtime maps equal')
    runtime = summary['runtime_before']
    check(file_sha(runtime['python_executable']) == runtime['python_executable_sha256'],
          'Python executable current hash')
    hash_map(runtime['numpy_inputs_sha256'], 'Python numpy input')
    for module, mapping in runtime['converter_module_inputs_sha256'].items():
        hash_map(mapping, 'Python ' + module + ' input')
    check(runtime['onnx_available'] is True and runtime['onnxruntime_available'] is True,
          'Python converter dependencies available')
    check('test_qualification.TinyConverterTests.test_real_quantizer_preserves_both_head_matrices'
          in raw_ids, 'Python real tiny quantizer case executed')
    brief = json.loads(streams['stdout'])
    check(brief['tests_run'] == brief['substantive_success_count'] == 117
          and brief['passed'] is True and brief['skipped_cases'] == [],
          'Python raw stdout summary agrees with unittest stderr')
    report['python'] = {
        'source_declared_tests': len(expected_ids), 'raw_unittest_successes': len(raw_ids),
        'module_test_counts': module_counts, 'skips': 0,
        'native_converter_executed': True, 'source_files': len(sources),
        'numpy_runtime_files': len(runtime['numpy_inputs_sha256']),
        'converter_runtime_files': {k: len(v) for k, v in runtime['converter_module_inputs_sha256'].items()},
        'runtime_before_after_equal': True, 'current_runtime_hashes_recomputed': True,
        'successful_test_ids': sorted(raw_ids),
    }


def main():
    plan = read_json(RUN / 'plan.json')
    receipt = read_json(RUN / 'receipt.json')
    check(receipt['status'] == 'passed' and receipt['all_passed'] is True,
          'completed qualification receipt')
    check(receipt['source_commit'] == SOURCE, 'receipt source commit')
    audit_scope(plan)
    audit_input_maps(receipt)
    commands = {c['name']: c for c in receipt['commands']}
    required_commands = set(plan['cohorts']) | set(plan['node_repetitions'])
    required_commands |= {k + '-strict-analysis' for k in PACKAGES}
    required_commands |= {'format', 'python-controls'}
    check(set(commands) == required_commands and len(commands) == len(receipt['commands']),
          'all and only 18 distinct planned commands ran')
    logs = {name: command_logs(command) for name, command in commands.items()}
    audit_analysis_format(plan, commands, logs)
    audit_python(commands['python-controls'], logs['python-controls'])
    primary, repetitions, inventory = {}, {}, {}
    for name, group in plan['cohorts'].items():
        result = audit_events(name, commands[name], group, logs[name], False)
        inventory[name] = result.pop('case_rows')
        primary[name] = result
    for name, group in plan['node_repetitions'].items():
        result = audit_events(name, commands[name], group, logs[name], True)
        rows = result.pop('case_rows')
        inventory[name] = rows
        baseline = inventory[group['repeats']]
        selected = set(group['tests'])
        identity = lambda row: (row['kind'], row['path'], row['name'], row['result'], row['skipped'])
        vm = collections.Counter(identity(row) for row in baseline if row['path'] in selected)
        node = collections.Counter(identity(row) for row in rows)
        check(vm == node, name + ': exact VM/Node case name, file, multiplicity, outcome parity',
              {'missing': list((vm - node).elements()), 'extra': list((node - vm).elements())})
        check(group['new_unique_test_cases_claimed'] is False,
              name + ': repetitions not counted as unique product cases')
        check(selected <= set(plan['cohorts'][group['repeats']]['tests']),
              name + ': repeated files all belong to primary VM cohort')
        for path, selection in group['selection_review'].items():
            package = REPO / PACKAGES[group['kind']]
            check(file_sha(package / path) == selection['source_sha256'],
                  name + ': Node selection source identity', path)
            for relative, digest in selection['relative_dart_closure_sha256'].items():
                check(file_sha(package / relative) == digest,
                      name + ': Node selection relative dependency identity', relative)
        result['vm_node_exact_case_parity'] = vm == node
        repetitions[name] = result
    native = [r for r in inventory['gector-contract'] if r['name'] == NATIVE_NAME]
    check(len(native) == 1 and native[0]['result'] == 'success'
          and native[0]['skipped'] is False, 'native real dual-head fixture case executed')
    private_source = (REPO / 'packages/quds_office_engine/test/pdf_file_test.dart').read_text()
    for name in PDF_NAMES:
        begin = private_source.find(name)
        body = private_source[begin:begin + 1000]
        check(begin >= 0 and str(PRIVATE_PDF) in body
              and re.search(r'if\s*\(!pdf\.existsSync\(\)\)\s*\{\s*return;', body),
              'private PDF exclusion corresponds to source early return', name)
    primary_raw = sum(v['raw_success_count'] for v in primary.values())
    primary_substantive = sum(v['substantive_success_count'] for v in primary.values())
    node_count = sum(v['substantive_success_count'] for v in repetitions.values())
    primary_files = sum(v['suite_count'] for v in primary.values())
    node_files = sum(v['suite_count'] for v in repetitions.values())
    check(primary_raw == receipt['raw_runner_success_total'] == 3543,
          'total primary raw successes')
    check(primary_substantive == receipt['substantive_success_total'] == 3541,
          'total primary substantive successes after exact two exclusions')
    check(node_count == receipt['node_substantive_success_total'] == 486,
          'total Node substantive repetitions')
    check(primary_substantive + node_count == receipt['all_runtime_successful_executions'] == 4027,
          'all-runtime execution count keeps Node repetition distinct')
    check(primary_files == 191 and node_files == 23
          and plan['primary_and_node_file_executions'] == 214,
          'exact primary and repeated file execution counts')
    check(primary['engine-zotero']['substantive_success_count'] == 390
          and primary['editor-zotero']['substantive_success_count'] == 186,
          'preserved exact engine/editor Zotero case counts')
    check(receipt['node_cases_are_repetitions'] is True
          and receipt['historical_qualifications_counted'] is False,
          'receipt distinguishes repetitions and excludes historical execution counts')
    check(receipt['github_actions_queried_awaited_or_rerun'] is False,
          'receipt records no GitHub Actions dependency')
    report['primary_cohorts'] = primary
    report['node_repetitions'] = repetitions
    report['totals'] = {
        'primary_files': primary_files, 'primary_raw_successes': primary_raw,
        'private_pdf_success_exclusions': primary_raw - primary_substantive,
        'primary_substantive_successes': primary_substantive,
        'node_repeated_files': node_files, 'node_repeated_successes': node_count,
        'python_successes': report['python']['raw_unittest_successes'],
        'unexpected_skips': 0, 'explicit_dart_skips': 0, 'python_skips': 0,
        'native_fixture_case_executed': True,
    }
    inventory_path = OUT / 'qualification-case-inventory.json.gz'
    content = json.dumps(inventory, ensure_ascii=False, indent=2, sort_keys=True).encode() + b'\n'
    inventory_path.write_bytes(gzip.compress(content, mtime=0))
    report['case_inventory'] = {'path': str(inventory_path), 'sha256': file_sha(inventory_path),
                                'raw_sha256': sha(content)}


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        failures.append({'check': 'audit execution completed',
                         'detail': type(exc).__name__ + ': ' + str(exc)})
        import traceback
        traceback.print_exc()
    report['audit_script_sha256'] = file_sha(__file__)
    report['checked_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    report['checks'] = checks
    report['failures'] = failures
    report['passed'] = not failures
    (OUT / 'qualification-audit.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'passed': not failures, 'checks': checks,
                      'failures': failures, 'totals': report.get('totals')}, indent=2))
    raise SystemExit(bool(failures))
