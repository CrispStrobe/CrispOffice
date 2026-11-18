#!/usr/bin/env python3
"""Independently audit captured local validation without rerunning any tests.

Use --task-root for an extracted evidence/workspace root containing the named
cohort directories, --repo for its checkout, and --runtime for the restored
runtime/validation tree. The browser overlay and runtime bytes must be present
for the complete byte-level replay. This script never fetches or changes Git
refs/index. It writes only its output receipt and compressed case inventory.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile

sys.dont_write_bytecode = True
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--task-root', type=Path, required=True)
parser.add_argument('--repo', type=Path)
parser.add_argument('--runtime', type=Path)
parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parent)
args = parser.parse_args()
TASK = args.task_root.resolve()
REPO = (args.repo or TASK / 'quds_office_suite').resolve()
RUNTIME = (args.runtime or TASK / 'runtime').resolve()
WORKSPACE = RUNTIME / 'validation'
OUT = args.output.resolve()
OUT.mkdir(parents=True, exist_ok=True)
FIXTURE_REL = 'docs/validation/thesaurus-20261118/continuation/local/fixtures'
FIXTURE = REPO / FIXTURE_REL
INTEGRATION_COMMIT = '813a7cdd7d55f2028e377393ae6bbc7388f5db73'
ACCEPTANCE_COMMIT = '7530f83a5503987dbee5b9678af56116ca98621f'
failures = []
inputs = {}
all_cases = []


def check(value, label, detail=None):
    if not value:
        failures.append({'check': label, 'detail': detail})
    return bool(value)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def record(path):
    data = path.read_bytes()
    return {'bytes': len(data), 'sha256': sha(data)}


def tracked_read(path):
    data = path.read_bytes()
    try:
        key = path.relative_to(TASK).as_posix()
    except ValueError:
        key = str(path)
    inputs[key] = {'bytes': len(data), 'sha256': sha(data)}
    return data


def read_json(path):
    return json.loads(tracked_read(path))


def read_gzip_json(path):
    return json.loads(gzip.decompress(tracked_read(path)))


def canonical_digest(value):
    return sha(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def git(*arguments):
    return subprocess.check_output(['git', '-C', str(REPO), *arguments], text=True).strip()


def source_name(path, cwd=None):
    path = str(path).replace('\\', '/')
    if not path.startswith('/') and not path.startswith('file:') and cwd:
        path = str(cwd).rstrip('/') + '/' + path
    for marker in ('/packages/', '/apps/', '/docs/'):
        if marker in path:
            return path[path.index(marker) + 1:]
    if path.startswith(('packages/', 'apps/', 'docs/')):
        return path
    raise ValueError('Cannot map captured source path: ' + path)


DIAGNOSTICS = re.compile(
    r'A Render\w+ overflowed|overflowed by [0-9]|EXCEPTION CAUGHT BY|'
    r'Warning: A call to (?:tap|drag)|would not hit test|missed (?:the )?hit test|'
    r'hitTestWarningShouldBeFatal', re.I)


def audit_events(directory, run):
    stdout = tracked_read(directory / run['stdout'])
    stderr = tracked_read(directory / run['stderr'])
    check(sha(stdout) == run['stdout_sha256'], run['name'] + ': stdout hash')
    check(sha(stderr) == run['stderr_sha256'], run['name'] + ': stderr hash')
    check(run['exit_code'] == 0, run['name'] + ': process exit')
    events, parse_errors = [], []
    for line_number, line in enumerate(stdout.decode().splitlines(), 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            if not isinstance(event, dict) or 'type' not in event:
                raise ValueError('Not a test event')
            events.append(event)
        except Exception as error:
            parse_errors.append({'line': line_number, 'error': str(error)})
    check(not parse_errors, run['name'] + ': valid JSON event stream', parse_errors)
    suites, starts, dones = {}, defaultdict(list), defaultdict(list)
    for event in events:
        if event['type'] == 'suite':
            suite = event['suite']
            suites[suite['id']] = source_name(suite['path'], run['cwd'])
        elif event['type'] == 'testStart':
            starts[event['test']['id']].append(event['test'])
        elif event['type'] == 'testDone':
            dones[event['testID']].append(event)
    check(set(starts) == set(dones) and all(len(v) == 1 for v in starts.values())
          and all(len(v) == 1 for v in dones.values()),
          run['name'] + ': every start has one completion')
    final = [e for e in events if e['type'] == 'done']
    check(len(final) == 1 and final[0].get('success') is True
          and events[-1]['type'] == 'done', run['name'] + ': final success event')
    error_events = [e for e in events if e['type'] == 'error']
    check(not error_events, run['name'] + ': no error events', error_events)
    messages = [str(e.get('message', '')) for e in events if e['type'] in ('print', 'error')]
    messages.extend(stderr.decode().splitlines())
    diagnostic_messages = [m for m in messages if DIAGNOSTICS.search(m)]
    check(not diagnostic_messages, run['name'] + ': no layout or tap diagnostics', diagnostic_messages)
    substantive, excluded = [], []
    for test_id, values in starts.items():
        if len(values) != 1 or len(dones.get(test_id, [])) != 1:
            continue
        start, done = values[0], dones[test_id][0]
        check(done.get('result') == 'success' and not done.get('skipped')
              and not start.get('metadata', {}).get('skip'),
              run['name'] + ': all completions pass without skip', start['name'])
        name = start['name']
        lifecycle = done.get('hidden') is True or name.startswith('loading ') or bool(
            re.search(r'\((?:setUpAll|tearDownAll)\)$', name))
        case = {'cohort': run['name'], 'suite': suites[start['suiteID']], 'name': name,
                'result': done['result'], 'skipped': bool(done.get('skipped'))}
        (excluded if lifecycle else substantive).append(case)
    expected = {source_name(p, run['cwd']) for p in run['command'] if p.endswith('_test.dart')}
    actual = {c['suite'] for c in substantive}
    check(actual == expected, run['name'] + ': exact selected suites',
          {'missing': sorted(expected - actual), 'extra': sorted(actual - expected)})
    counts = Counter(c['suite'] for c in substantive)
    all_cases.extend(substantive)
    return {'cohort': run['name'], 'passed': len(substantive), 'suite_count': len(counts),
            'per_suite': dict(sorted(counts.items())), 'excluded_lifecycle_cases': len(excluded),
            'start_events': len(starts), 'completion_events': len(dones),
            'final_success': len(final) == 1 and final[0].get('success') is True,
            'error_events': len(error_events), 'parse_errors': parse_errors,
            'layout_or_tap_diagnostics': diagnostic_messages,
            'stdout_sha256': sha(stdout), 'stderr_sha256': sha(stderr)}


def tree(commit):
    result = {}
    for line in git('ls-tree', '-r', commit).splitlines():
        metadata, path = line.split('\t', 1)
        mode, kind, oid = metadata.split()
        if kind == 'blob':
            result[path] = (mode, oid)
    return result


TREES = {c: tree(c) for c in (INTEGRATION_COMMIT, ACCEPTANCE_COMMIT)}
OBJECT_FORMAT = git('rev-parse', '--show-object-format')


def inventory_audit(name, snapshot, commit, external):
    mismatches, commit_mismatches, workspace_mismatches = [], [], []
    normal_count = special_count = workspace_count = commit_count = 0
    for key, expected in snapshot.items():
        repository_path = None
        if key.startswith('__fixture__/'):
            repository_path = FIXTURE_REL + '/' + key.removeprefix('__fixture__/')
            path = REPO / repository_path
            special_count += 1
        elif key.startswith('__'):
            path = external[key]
            special_count += 1
        else:
            repository_path = key
            path = REPO / key
            normal_count += 1
        if not path.is_file():
            mismatches.append({'path': key, 'reason': 'missing'})
            continue
        raw = path.read_bytes()
        actual = {'sha256': sha(raw), 'bytes': len(raw)}
        if any(actual.get(k) != v for k, v in expected.items()):
            mismatches.append({'path': key, 'expected': expected, 'actual': actual})
        if repository_path is not None:
            entry = TREES[commit].get(repository_path)
            if entry:
                mode, oid = entry
                git_bytes = os.readlink(path).encode() if mode == '120000' else raw
                actual_oid = hashlib.new(OBJECT_FORMAT,
                    b'blob ' + str(len(git_bytes)).encode() + b'\0' + git_bytes).hexdigest()
                commit_count += 1
                if actual_oid != oid:
                    commit_mismatches.append(repository_path)
            else:
                commit_mismatches.append(repository_path)
            counterpart = WORKSPACE / repository_path
            if counterpart.is_file():
                workspace_count += 1
                if sha(counterpart.read_bytes()) != actual['sha256']:
                    workspace_mismatches.append(repository_path)
            elif repository_path.endswith('.dart') and '/docs/' not in '/' + repository_path:
                workspace_mismatches.append(repository_path + ' (missing workspace Dart source)')
    check(not mismatches, name + ': current inventory bytes', mismatches)
    check(not commit_mismatches, name + ': declared commit bytes', commit_mismatches)
    check(not workspace_mismatches, name + ': execution workspace bytes', workspace_mismatches)
    return {'entries': len(snapshot), 'repository_entries': normal_count,
            'special_entries': special_count, 'commit': commit,
            'commit_entries_checked': commit_count, 'execution_workspace_entries_checked': workspace_count,
            'current_mismatches': mismatches, 'commit_mismatches': commit_mismatches,
            'execution_workspace_mismatches': workspace_mismatches,
            'canonical_digest': canonical_digest(snapshot)}


integration_dir = TASK / 'integration-validation'
integration = read_json(integration_dir / 'summary.json')
check(integration['status'] == 'passed', 'integration receipt finalized successfully')
check(integration['source_sha'] == INTEGRATION_COMMIT, 'integration declared source commit')
before = read_gzip_json(integration_dir / 'source-before.json.gz')
after = read_gzip_json(integration_dir / 'source-after.json.gz')
check(before == after, 'integration before/after source inventory unchanged')
check(canonical_digest(before) == integration['input_digest'] == integration['output_digest'],
      'integration source inventory digests')
external = {
    '__workspace_lock__': WORKSPACE / 'pubspec.lock',
    '__package_config__': WORKSPACE / '.dart_tool/package_config.json',
    '__runtime_ready__': RUNTIME / 'runtime-ready.json',
    '__dart__': RUNTIME / 'flutter-sdk/bin/cache/dart-sdk/bin/dart',
    '__flutter_tester__': RUNTIME / 'flutter-sdk/bin/cache/artifacts/engine/linux-x64/flutter_tester',
    '__audit_source__': REPO / 'docs/validation/zotero-citation-workflow-20261118/editor/run_editor_zotero.py',
    '__runner__': integration_dir / 'run_cohorts.py',
}
integration_sources = inventory_audit('integration', before, INTEGRATION_COMMIT, external)
expected_integration_keys = {'.fvmrc', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', *external}
for name in TREES[INTEGRATION_COMMIT]:
    p = Path(name)
    if p.parts[0] in ('packages', 'apps', 'third_party') and (
            p.suffix in ('.dart', '.yaml', '.json', '.gz', '.png', '.ttf', '.otf', '.bin', '.js', '.html', '.css', '.wasm')
            or p.name == 'CMakeLists.txt') and not any(x in ('doc', 'docs', 'verification', 'notices') for x in p.parts[2:]):
        expected_integration_keys.add(name)
check(set(before) == expected_integration_keys, 'integration exact declared source scope',
      {'missing': sorted(expected_integration_keys - set(before)), 'extra': sorted(set(before) - expected_integration_keys)})
integration_sources['exact_declared_scope_verified'] = set(before) == expected_integration_keys
cohorts = [audit_events(integration_dir, r) for r in integration['runs'] if r['name'] != 'analysis']
check(sum(c['passed'] for c in cohorts) == integration['passed_cases'], 'integration aggregate case count')
for run, result in zip([r for r in integration['runs'] if r['name'] != 'analysis'], cohorts):
    check(run['test_audit']['passed'] == result['passed'] and
          run['test_audit']['suite_count'] == result['suite_count'], run['name'] + ': receipt count matches events')
index = read_json(integration_dir / 'evidence-index.json')
for name, expected in index['files'].items():
    check(record(integration_dir / name) == expected, 'integration evidence index: ' + name)
analysis = next(r for r in integration['runs'] if r['name'] == 'analysis')
analysis_stdout = tracked_read(integration_dir / analysis['stdout'])
analysis_stderr = tracked_read(integration_dir / analysis['stderr'])
check(sha(analysis_stdout) == analysis['stdout_sha256'] and sha(analysis_stderr) == analysis['stderr_sha256'],
      'strict analysis log hashes')
check(analysis['exit_code'] == 0 and '--fatal-infos' in analysis['command']
      and b'No issues found!' in analysis_stdout and not analysis_stderr,
      'strict analysis success')
check(len(integration['analysis_targets']) == 5 and all(p in before for p in integration['analysis_targets']),
      'all five analysis source files bound')
check({p for p in analysis['command'] if p.endswith('.dart')} == set(integration['analysis_targets']),
      'analysis command selected the five bound files')

native_dir = TASK / 'thesaurus-acceptance-validation'
native = read_json(native_dir / 'receipt.json')
check(native['status'] == 'native_passed_web_compiled_browser_not_run', 'native/build receipt finalized')
check(native['base_commit'] == ACCEPTANCE_COMMIT, 'native/build declared source commit')
check(native.get('source_unchanged_during_tests') is True and native.get('source_unchanged_during_build') is True,
      'native/build receipt records stable inputs')
native_inputs = read_gzip_json(native_dir / 'source-inputs.json.gz')
check(canonical_digest(native_inputs) == native['input_digest'], 'native input digest')
native_sources = inventory_audit('native/build', native_inputs, ACCEPTANCE_COMMIT,
    {'__workspace_lock__': WORKSPACE / 'pubspec.lock',
     '__workspace_package_config__': WORKSPACE / '.dart_tool/package_config.json'})
expected_native_keys = {'.fvmrc', 'pubspec.yaml', '__workspace_lock__', '__workspace_package_config__'}
expected_native_keys.update('__fixture__/' + name for name in (
    'lib/main.dart', 'native_pack_test.dart', 'native_visual_test.dart', 'install_offline.py',
    'run_browser.py', 'run_final_validation.py', 'test_browser_harness.py', 'build_binding.py'))
for package in (REPO / 'packages').iterdir():
    if not package.is_dir():
        continue
    if (package / 'pubspec.yaml').is_file():
        expected_native_keys.add((package / 'pubspec.yaml').relative_to(REPO).as_posix())
    for kind in ('lib', 'test', 'assets'):
        if (package / kind).exists():
            expected_native_keys.update(p.relative_to(REPO).as_posix()
                for p in (package / kind).rglob('*') if p.is_file())
check(set(native_inputs) == expected_native_keys, 'native exact current source scope',
      {'missing': sorted(expected_native_keys - set(native_inputs)), 'extra': sorted(set(native_inputs) - expected_native_keys)})
native_sources['exact_current_scope_verified'] = set(native_inputs) == expected_native_keys
native_run = next(r for r in native['runs'] if r['name'] == 'native-acceptance')
native_cohort = audit_events(native_dir, native_run)
check(native_cohort['passed'] == native['test_audit']['passed'] and
      native_cohort['suite_count'] == native['test_audit']['suite_count'], 'native receipt counts match raw events')
cohorts.append(native_cohort)
build = next(r for r in native['runs'] if r['name'] == 'browser-build')
for stream in ('stdout', 'stderr'):
    check(sha(tracked_read(native_dir / build[stream])) == build[stream + '_sha256'], 'web build ' + stream + ' hash')
check(build['exit_code'] == 0, 'web build process succeeded')
sys.path.insert(0, str(FIXTURE))
spec = importlib.util.spec_from_file_location('audited_offline_installer', FIXTURE / 'install_offline.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
records, cache_identity, provenance = installer.validate_installation(native_dir / 'browser-build', native_dir / 'receipt.json')
compiled = read_gzip_json(native_dir / 'browser-build-files.json.gz')
check(len(compiled) == native['compiled_browser_files'] and sum(x['bytes'] for x in compiled) == native['compiled_browser_bytes'],
      'compiled inventory totals')
native_panel = read_json(native_dir / 'native-pack-report.json')
check(native_panel.get('status') == 'passed' and len(native_panel.get('queries', [])) == 15,
      'native 15-query panel completed')


def audit_unittest(folder, receipt, source_records, relative_base):
    text = ''
    for filename, checksum in receipt['logs'].items():
        raw = tracked_read(folder / filename)
        check(sha(raw) == checksum, folder.name + ': log hash ' + filename)
        text += raw.decode()
    names = re.findall(r'^(test_\S+) \([^\n]+\) \.\.\. ok$', text, re.M)
    counts = re.findall(r'^Ran (\d+) tests? in [0-9.]+s$', text, re.M)
    check(len(counts) == 1 and len(names) == int(counts[0]) == receipt['cases'],
          folder.name + ': count independently parsed from named cases')
    check(text.rstrip().endswith('\nOK') and receipt['exit_code'] == 0
          and not re.search(r'\.\.\. (?:FAIL|ERROR|skipped)|^FAILED|^ERROR:', text, re.M),
          folder.name + ': all named controls passed')
    current = {}
    for name, expected in source_records.items():
        actual = record(relative_base / name)
        if isinstance(expected, str):
            check(actual['sha256'] == expected, folder.name + ': current input ' + name)
        else:
            check(actual == expected, folder.name + ': current input ' + name)
        current[name] = actual
    return {'cases': len(names), 'names': names, 'passed': receipt['exit_code'] == 0,
            'source_inputs_checked': current, 'scope': receipt['scope']}


harness_dir = TASK / 'acceptance-harness-review'
harness_receipt = read_json(harness_dir / 'receipt.json')
check(harness_receipt['source_unchanged'] is True, 'harness receipt stable sources')
harness = audit_unittest(harness_dir, harness_receipt, harness_receipt['source_sha256'], FIXTURE)
export_dir = TASK / 'review-packet-validation'
export_receipt = read_json(export_dir / 'receipt.json')
check(export_receipt['status'] == 'passed' and export_receipt['source_unchanged'] is True
      and export_receipt['source_before'] == export_receipt['source_after'], 'exporter before/after source binding')
exporter = audit_unittest(export_dir, export_receipt, export_receipt['source_before'], REPO)

browser_dir = TASK / 'thesaurus-browser-acceptance'
browser = read_json(browser_dir / 'browser-report.json')
check(browser['status'] == 'failed' and not browser['steps'] and not browser['requests']
      and 'socket() failed: Operation not permitted' in browser.get('error', ''),
      'browser attempt remains an explicitly pre-startup failure')
check(browser['cache_identity'] == cache_identity and
      browser['compile_provenance']['receipt_sha256'] == provenance['receipt_sha256'],
      'blocked browser attempt binds the verified installed build')

changes = git('diff', '--name-only', INTEGRATION_COMMIT, ACCEPTANCE_COMMIT).splitlines()
allowed_tools = {'tools/thesaurus/README.md', 'tools/thesaurus/export_review_packet.py',
                 'tools/thesaurus/test_export_review_packet.py'}
check(all(p.startswith('docs/') or p in allowed_tools for p in changes),
      'acceptance checkpoint changed only documentation and acceptance tooling', changes)
acceptance_dir = REPO / 'docs/validation/thesaurus-20261118/acceptance'
archive_index = read_json(acceptance_dir / 'evidence-index.json')
archive_path = acceptance_dir / archive_index['archive']
archive_record = record(archive_path)
check(archive_record == {'bytes': archive_index['bytes'], 'sha256': archive_index['sha256']},
      'published evidence archive bytes and hash')
source_prefixes = {
    'browser/': browser_dir,
    'controls/harness/': harness_dir,
    'controls/review-packet/': export_dir,
    'integration/': integration_dir,
    'native/': native_dir,
}
expected_members = {m['path']: m for m in archive_index['members']}
archive_mismatches = []
with tarfile.open(archive_path, 'r:gz') as archive:
    members = archive.getmembers()
    check(len(members) == len(expected_members) == len(archive_index['members'])
          and {m.name for m in members} == set(expected_members), 'exact archive member inventory')
    for member in members:
        check(member.isfile() and not Path(member.name).is_absolute()
              and '..' not in Path(member.name).parts, 'archive member is a safe regular file', member.name)
        if not member.isfile() or member.name not in expected_members:
            continue
        data = archive.extractfile(member).read()
        expected = expected_members[member.name]
        actual = {'path': member.name, 'bytes': len(data), 'sha256': sha(data)}
        source = (TASK / 'thesaurus-browser-launcher.log'
                  if member.name == 'browser/launcher.log'
                  else next(root / member.name.removeprefix(prefix)
                            for prefix, root in source_prefixes.items() if member.name.startswith(prefix)))
        if actual != expected or not source.is_file() or data != source.read_bytes():
            archive_mismatches.append(member.name)
check(not archive_mismatches, 'archive members preserve original raw evidence', archive_mismatches)
pack_continuity = read_json(acceptance_dir / 'pack-continuity.json')
pack_path = pack_continuity['path']
handoff_pack_tree = git('rev-parse', pack_continuity['handoff'] + ':' + pack_path)
qualified_pack_tree = git('rev-parse', ACCEPTANCE_COMMIT + ':' + pack_path)
check(handoff_pack_tree == qualified_pack_tree == pack_continuity['handoff_tree'] == pack_continuity['current_tree'],
      'qualified corpus tree is identical to handoff')
pack_inventory_count = sum(p.startswith(pack_path + '/') for p in native_inputs)
check(pack_inventory_count == 1037, 'all 1037 packaged lexical files are in native source inventory')
identities = Counter((c['suite'], c['name']) for c in all_cases)
duplicates = [{'suite': s, 'name': n, 'count': k} for (s, n), k in identities.items() if k != 1]
check(not duplicates, 'no duplicated substantive cases across selected cohorts', duplicates)
case_bytes = json.dumps(all_cases, indent=2).encode() + b'\n'
(OUT / 'substantive-cases.json.gz').write_bytes(gzip.compress(case_bytes, mtime=0))
report = {
    'schema_version': 1,
    'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
    'scope': 'Independent reconstruction from existing logs and byte inventories. No tests rerun; no Git refs/index changed.',
    'audit_script_sha256': sha(Path(__file__).read_bytes()),
    'status': 'verified_with_open_release_gates' if not failures else 'audit_failed',
    'passed': not failures,
    'failures': failures,
    'cohorts': cohorts,
    'totals': {'dart_flutter_cases': sum(c['passed'] for c in cohorts),
               'dart_flutter_suites': sum(c['suite_count'] for c in cohorts),
               'python_controls': harness['cases'] + exporter['cases'],
               'all_targeted_cases_and_controls': len(all_cases) + harness['cases'] + exporter['cases'],
               'strict_analysis_files': len(integration['analysis_targets'])},
    'case_inventory': {'path': 'substantive-cases.json.gz', **record(OUT / 'substantive-cases.json.gz')},
    'integration_sources': integration_sources,
    'native_sources': native_sources,
    'python_harness': harness,
    'python_exporter': exporter,
    'evidence_archive': {**archive_record, 'members': len(expected_members),
                         'original_evidence_mismatches': archive_mismatches,
                         'all_member_hashes_and_original_bytes_match': not archive_mismatches},
    'pack_continuity': {'handoff': pack_continuity['handoff'], 'checkpoint': ACCEPTANCE_COMMIT,
                        'tree': qualified_pack_tree, 'packaged_files_checked': pack_inventory_count,
                        'new_full_rebuild_claimed': False},
    'commit_delta': {'base': INTEGRATION_COMMIT, 'head': ACCEPTANCE_COMMIT,
                     'paths': changes, 'application_source_changed': False},
    'web_compile': {'exit_code': build['exit_code'], 'compiled_files': len(compiled),
                    'compiled_bytes': sum(r['bytes'] for r in compiled),
                    'installed_files': len(records), 'installed_bytes': sum(r['bytes'] for r in records),
                    'installed_overlay_verified': True, 'cache_identity': cache_identity,
                    'warning': 'Flutter reports that --pwa-strategy is deprecated; compilation succeeded.'},
    'actual_browser': {'status': 'blocked_before_application_start', 'completed_steps': 0,
                       'application_requests': 0, 'acceptance_passed': False,
                       'reason': 'Chromium socket() startup failed with Operation not permitted (EPERM).'},
    'release_gates': {'actual_offline_browser': 'open', 'installed_native_desktop': 'open',
                      'independent_human_linguistic_review': 'open'},
    'limits': [
        'These are targeted cohorts, not a complete repository suite.',
        'The native 15-query panel is one test case; queries are not counted as extra cases.',
        'Python/Node mocked-worker controls and release web compilation do not establish browser acceptance.',
        'Before/after inventories and captured subprocess receipts are local evidence, not signed attestations.',
        'Current source equality covers the recorded input scopes, not unrelated repository documents.',
    ],
    'input_evidence': inputs,
}
(OUT / 'peer-final-audit.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'status': report['status'], 'totals': report['totals'], 'failures': failures}, indent=2))
if failures:
    raise SystemExit(1)
