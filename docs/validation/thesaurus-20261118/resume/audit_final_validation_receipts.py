#!/usr/bin/env python3
"""Read saved receipts and independently audit them; never execute tests."""
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path('/workspace/scratch/a686c23de6c7')
REPO = ROOT / 'quds_office_suite'
WORKSPACE = ROOT / 'zotero-validation'
FIXTURE = REPO / 'docs/validation/thesaurus-20261118/continuation/local/fixtures'
FROZEN = 'af4971352fa14247e2de7be8c9b5733921e2ff30'
NEW_NAMES = [
    'Shift F7 refuses thesaurus without interrupting active IME',
    'an earlier ready capture refuses thesaurus without interrupting active IME',
    'a host without Scaffold refuses thesaurus without interrupting active IME',
    'text language controls and undo retire an earlier thesaurus lookup',
    '390px English review keeps language and thesaurus actions usable at 1.5x text',
    '390px Arabic RTL review keeps language and thesaurus actions usable at 1.5x text',
    'Alt Shift F7 keeps reverse review navigation while Shift F7 opens thesaurus',
]


def read_json(path):
    opener = gzip.open if path.suffix == '.gz' else open
    with opener(path, 'rt') as stream:
        return json.load(stream)


def file_hash(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO, text=True).strip()


def event_audit(path, run):
    events, parse_errors = [], []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
            if not isinstance(value, dict) or not isinstance(value.get('type'), str):
                raise ValueError('not a test event')
            events.append(value)
        except (ValueError, TypeError):
            parse_errors.append(number)
    starts = [event['test'] for event in events if event['type'] == 'testStart']
    by_id = {test['id']: test for test in starts}
    dones = [event for event in events if event['type'] == 'testDone']
    suites = [event['suite'] for event in events if event['type'] == 'suite']
    excluded, cases = [], []
    for done in dones:
        name = by_id.get(done['testID'], {}).get('name', '')
        (excluded if done.get('hidden') or name.startswith('loading ')
         or name.endswith(('(setUpAll)', '(tearDownAll)')) else cases).append(done)
    skipped = [done for done in cases if done.get('skipped') or
               by_id.get(done['testID'], {}).get('metadata', {}).get('skip')]
    skipped_ids = {done['testID'] for done in skipped}
    passed = [done for done in cases if done['result'] == 'success' and done['testID'] not in skipped_ids]
    failed = [done for done in cases if done['result'] != 'success' and done['testID'] not in skipped_ids]
    once = (len(starts) == len(by_id) and
            Counter(test['id'] for test in starts) == Counter(done['testID'] for done in dones))
    finals = [event for event in events if event['type'] == 'done']
    errors = [event for event in events if event['type'] == 'error']
    diagnostics = [event for event in events if event['type'] == 'print' and re.search(
        r'A Render\w+ overflowed|would not hit test on the specified widget|does not receive pointer events',
        event.get('message', ''))]
    bad_excluded = [done for done in excluded if done['result'] != 'success' or done.get('skipped')]
    command, cwd = run['command'], Path(run['cwd'])
    selected = command[command.index('--reporter') + 2:]
    actual_paths = {str((cwd / suite['path']).resolve()) for suite in suites}
    expected_paths = {str((cwd / name).resolve()) for name in selected}
    guards = {
        'exit_success': run['exit_code'] == 0,
        'all_selected_suites_executed': actual_paths == expected_paths and len(suites) == len(selected),
        'nonempty_cases': bool(passed),
        'no_failed_or_skipped_cases': not failed and not skipped,
        'every_started_test_finished_once': once,
        'final_event_success': len(finals) == 1 and finals[0].get('success') is True,
        'clean_event_stream': not any((parse_errors, errors, diagnostics, bad_excluded)),
    }
    return {
        'passed': len(passed), 'failed': len(failed), 'skipped': len(skipped),
        'suite_count': len(suites), 'test_start_events': len(starts), 'test_done_events': len(dones),
        'excluded_lifecycle_events': len(excluded), 'guards': guards,
        'all_guards_pass': all(guards.values()),
        'parse_errors': parse_errors, 'error_events': len(errors),
        'layout_or_tap_diagnostics': len(diagnostics), 'excluded_failures': len(bad_excluded),
        'suites': [{'path': suite['path'], 'passed': sum(by_id[done['testID']]['suiteID'] == suite['id']
                                                       for done in passed)} for suite in suites],
    }, [{'name': by_id[done['testID']]['name'], 'result': done['result'],
         'skipped': done.get('skipped', False), 'hidden': done.get('hidden', False)}
        for done in dones if by_id[done['testID']]['name'] in NEW_NAMES]


def audit_receipt(directory, native=False):
    path = directory / 'receipt.json'
    if not path.exists():
        return {'status': 'not_yet_available'}
    receipt = read_json(path)
    result = {'receipt': str(path.relative_to(ROOT)), 'receipt_sha256': file_hash(path),
              'status': receipt['status'], 'started_at_utc': receipt.get('started_at_utc'),
              'finished_at_utc': receipt.get('finished_at_utc')}
    if receipt['status'] == 'running':
        return result
    runs = []
    for run in receipt['runs']:
        record = {'name': run['name'], 'exit_code': run['exit_code'], 'seconds': run['seconds']}
        for stream in ('stdout', 'stderr'):
            record[stream + '_hash_matches'] = file_hash(directory / run[stream]) == run[stream + '_sha256']
        runs.append(record)
        if run['name'] in ('native-acceptance', 'tests'):
            audit, regressions = event_audit(directory / run['stdout'], run)
            reported = read_json(directory / ('native-test-audit.json' if native else 'test-audit.json'))
            audit['recorded_counts_match'] = all(audit[key] == reported[key]
                for key in ('passed', 'failed', 'skipped', 'suite_count', 'test_start_events', 'test_done_events'))
            recorded_guards = receipt['native_acceptance_guards' if native else 'acceptance_guards']
            audit['recorded_guards_match'] = audit['guards'] == recorded_guards
            result['independent_event_audit'] = audit
            if native:
                result['new_regressions'] = regressions
                result['seven_new_regressions_executed_successfully'] = (
                    Counter(item['name'] for item in regressions) == Counter(NEW_NAMES) and
                    all(item['result'] == 'success' and not item['skipped'] and not item['hidden']
                        for item in regressions))
    result['runs'] = runs
    if native:
        before = read_json(directory / 'source-inputs.json.gz')
        result['source_receipt_checks'] = {
            'file_count': len(before),
            'input_digest_matches': hashlib.sha256(json.dumps(before, sort_keys=True,
                separators=(',', ':')).encode()).hexdigest() == receipt['input_digest'],
            'recorded_source_unchanged_during_tests': receipt['source_unchanged_during_tests'],
            'recorded_source_unchanged_during_build': receipt['source_unchanged_during_build'],
            'note': 'The native runner retained the initial inventory and stability flags; current source and execution-workspace hashes are independently rechecked below.',
        }
    if 'artifact' in receipt:
        artifact = receipt['artifact']
        result['artifact_hash_matches'] = file_hash(directory / artifact['path']) == artifact['sha256']
        result['artifact_bytes_match'] = (directory / artifact['path']).stat().st_size == artifact['bytes']
    if 'targets' in receipt:
        result['static_target_count'] = len(receipt['targets'])
    if (directory / 'source-after.json.gz').exists():
        before, after = [read_json(directory / name) for name in ('source-inputs.json.gz', 'source-after.json.gz')]
        digest = lambda value: hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
        result['source_receipt_checks'] = {
            'file_count': len(before), 'before_equals_after': before == after,
            'input_digest_matches': digest(before) == receipt['input_digest'],
            'output_digest_matches': digest(after) == receipt['output_digest'],
            'recorded_source_unchanged': receipt['source_unchanged'],
        }
    return result


def mapped_path(name):
    if name.startswith('__fixture__/'):
        return FIXTURE / name.removeprefix('__fixture__/')
    return {'__workspace_lock__': WORKSPACE / 'pubspec.lock',
            '__workspace_package_config__': WORKSPACE / '.dart_tool/package_config.json',
            '__runtime_ready__': ROOT / 'zotero-toolchain/runtime-ready.json'}.get(name, REPO / name)


def compare_inputs(path):
    inventory = read_json(path)
    missing, mismatches, workspace_missing, workspace_mismatches = [], [], [], []
    workspace_count = 0
    for name, record in inventory.items():
        actual = mapped_path(name)
        if not actual.is_file():
            missing.append(name)
        elif file_hash(actual) != record['sha256'] or ('bytes' in record and actual.stat().st_size != record['bytes']):
            mismatches.append(name)
        if name.startswith(('packages/', 'apps/')):
            workspace_count += 1
            actual = WORKSPACE / name
            if not actual.is_file():
                workspace_missing.append(name)
            elif file_hash(actual) != record['sha256']:
                workspace_mismatches.append(name)
    return {'inventory': str(path.relative_to(ROOT)), 'file_count': len(inventory),
            'current_missing': missing, 'current_mismatches': mismatches,
            'workspace_package_application_file_count': workspace_count,
            'workspace_missing': workspace_missing, 'workspace_mismatches': workspace_mismatches}


def main():
    native = ROOT / 'thesaurus-resume-native-attempt1'
    supplemental = ROOT / 'thesaurus-supplemental'
    result = {'audited_at_utc': datetime.now(timezone.utc).isoformat(),
              'audit_method': 'Independent standard-library parsing and hashing of saved local receipts; no tests executed; no remote queries.',
              'frozen_application_source': FROZEN, 'current_head': git('rev-parse', 'HEAD'),
              'native': audit_receipt(native, native=True),
              'supplemental': {name: audit_receipt(supplemental / name) for name in
                              ('static', 'engine', 'editor-zotero', 'spacy', 'studio', 'web-import')}}
    changed = git('diff', '--name-only', FROZEN, 'HEAD').splitlines()
    working = git('diff', '--name-only', 'HEAD').splitlines()
    result['source_freeze'] = {
        'tracked_changes_since_frozen': changed,
        'non_documentation_changes_since_frozen': [name for name in changed if not name.startswith('docs/')],
        'non_documentation_worktree_changes': [name for name in working if not name.startswith('docs/')],
        'non_documentation_untracked_files': [name for name in git('ls-files', '--others', '--exclude-standard').splitlines()
                                             if not name.startswith('docs/')],
        'native_inventory': compare_inputs(native / 'source-inputs.json.gz'),
        'supplemental_inventory': compare_inputs(supplemental / 'engine/source-inputs.json.gz'),
    }
    browser_path = REPO / 'docs/validation/thesaurus-20261118/resume/browser-attempt/browser-report.json'
    browser = read_json(browser_path)
    result['actual_browser'] = {
        'status': 'launch_blocked', 'receipt': str(browser_path.relative_to(ROOT)),
        'receipt_sha256': file_hash(browser_path), 'recorded_status': browser['status'],
        'completed_steps': len(browser['steps']), 'recorded_requests': len(browser['requests']),
        'launch_error_contains_socket_denial': 'socket() failed: Operation not permitted' in browser.get('error', ''),
        'offline_browser_acceptance_passed': False,
    }
    compiled = read_json(native / 'browser-build-files.json.gz')
    installed = read_json(browser_path.with_name('installed-build-files.json'))
    compiled_by_path, installed_by_path = [{entry['path']: entry for entry in inventory}
                                          for inventory in (compiled, installed)]
    result['web_build_artifacts'] = {
        'compiled_files': len(compiled), 'compiled_bytes': sum(entry['bytes'] for entry in compiled),
        'installed_files': len(installed), 'installed_bytes': sum(entry['bytes'] for entry in installed),
        'installer_added_files': sorted(installed_by_path.keys() - compiled_by_path.keys()),
        'installer_removed_files': sorted(compiled_by_path.keys() - installed_by_path.keys()),
        'installer_changed_files': sorted(name for name in compiled_by_path.keys() & installed_by_path.keys()
                                           if compiled_by_path[name] != installed_by_path[name]),
        'installed_files_match': all((native / 'browser-build' / entry['path']).is_file()
                                    and file_hash(native / 'browser-build' / entry['path']) == entry['sha256']
                                    and (native / 'browser-build' / entry['path']).stat().st_size == entry['bytes']
                                    for entry in installed),
        'compile_log_has_cupertino_font_notice': 'Expected to find fonts for' in
                                                (native / 'logs/browser-build.stdout').read_text(),
    }
    result['visual_artifacts'] = []
    for path in sorted((native / 'visuals').glob('*.png')):
        header = path.read_bytes()[:24]
        result['visual_artifacts'].append({'name': path.name, 'sha256': file_hash(path),
            'width': int.from_bytes(header[16:20], 'big'), 'height': int.from_bytes(header[20:24], 'big')})
    result['python_test_logs'] = []
    for name, expected in (('compiler-tests.log', 5), ('harness-controls.log', 10)):
        path = REPO / 'docs/validation/thesaurus-20261118/resume' / name
        text = path.read_text()
        count = re.findall(r'^Ran (\d+) tests? in ', text, re.MULTILINE)
        result['python_test_logs'].append({'path': str(path.relative_to(ROOT)), 'sha256': file_hash(path),
            'passed_count': int(count[0]) if len(count) == 1 else None,
            'expected_count_and_final_OK': count == [str(expected)] and text.rstrip().endswith('OK'),
            'evidence_kind': 'Saved unittest text log, not Dart machine events.'})
    result['classification'] = {
        'native_and_editor_studio_tests': 'Dart VM / Flutter native headless tests, not installed desktop acceptance.',
        'real_pack_panel': '15 source-identified queries within one passing native case, not independent linguistic review.',
        'visual_fixtures': 'Three rendered native headless widget fixtures, not screenshots of an installed desktop app.',
        'release_web_compile': 'Successful compiled thesaurus acceptance fixture, not actual browser execution.',
        'web_import': 'Dart-to-JavaScript compile plus Node import capability check, not browser execution.',
        'spaCy': 'Local selected unit/model-contract tests; no model-download or real EN/FR model acceptance claim.',
        'open_release_checks': ['Actual installed-offline browser acceptance', 'Installed native desktop acceptance', 'Independent human linguistic review'],
        'scope': 'Targeted validation only; not the full repository suite. Hidden/lifecycle events excluded from case counts.',
    }
    result['completed_machine_test_cases'] = sum(
        group.get('independent_event_audit', {}).get('passed', 0)
        for group in [result['native'], *result['supplemental'].values()])
    suite_paths = [suite['path'] for group in [result['native'], *result['supplemental'].values()]
                   for suite in group.get('independent_event_audit', {}).get('suites', [])]
    result['machine_test_suite_count'] = len(suite_paths)
    result['selected_suites_are_distinct'] = len(set(suite_paths)) == len(suite_paths)
    result['combined_test_count_including_python'] = result['completed_machine_test_cases'] + sum(
        entry['passed_count'] for entry in result['python_test_logs'] if entry['expected_count_and_final_OK'])
    result['pending_cohorts'] = [name for name, group in result['supplemental'].items()
                                 if group['status'] in ('running', 'not_yet_available')]
    destination = ROOT / 'final-validation-peer-audit.json'
    destination.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'output': str(destination), 'completed_machine_test_cases': result['completed_machine_test_cases'],
                      'pending_cohorts': result['pending_cohorts'], 'current_head': result['current_head']}, indent=2))


if __name__ == '__main__':
    main()
