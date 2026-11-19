#!/usr/bin/env python3
"""Read-only selected-plan and retained-source audit for this continuation."""
from pathlib import Path
from collections import Counter
from datetime import datetime, timezone
import argparse
import gzip
import hashlib
import json
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--head', required=True)
parser.add_argument('--evidence', type=Path, required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
repo = args.repo.resolve()
out = args.output_dir.resolve()
evidence = args.evidence.resolve()


def git(*arguments):
    return subprocess.check_output(['git', '-C', str(repo), *arguments])


head = git('rev-parse', args.head + '^{commit}').decode().strip()
tree = git('rev-parse', head + '^{tree}').decode().strip()
batch = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE)
cache = {}


def blob(path):
    if path in cache:
        return cache[path]
    batch.stdin.write((head + ':' + path + '\n').encode())
    batch.stdin.flush()
    line = batch.stdout.readline().decode().strip()
    if line.endswith(' missing'):
        cache[path] = None
        return None
    _, kind, size = line.split()
    assert kind == 'blob', (path, kind)
    data = batch.stdout.read(int(size))
    assert batch.stdout.read(1) == b'\n'
    cache[path] = data
    return data


def digest(data):
    return hashlib.sha256(data).hexdigest()


def compare_map(records):
    differences, missing = [], []
    for path, spec in records.items():
        expected = spec if isinstance(spec, str) else spec['sha256']
        current = blob(path)
        if current is None:
            missing.append(path)
        elif digest(current) != expected:
            differences.append({'path': path, 'recorded_sha256': expected,
                                'current_sha256': digest(current)})
    return {'entries': len(records), 'matching_entries': len(records) - len(differences) - len(missing),
            'different': differences, 'missing': missing}


plan_path = 'docs/validation/thesaurus-20261118/reconciled/plan.json'
plan_bytes = (repo / plan_path).read_bytes()
plan = json.loads(plan_bytes)
notes_path = 'docs/validation/document-review-notes-20261118/test-plan.json'
zotero_path = 'docs/validation/zotero-word-parity-20261118/plan.json'
notes = json.loads(blob(notes_path))
zotero = json.loads(blob(zotero_path))
selected = {(group['cwd'] + '/' + path, group.get('platform', 'vm'))
            for group in plan['groups'] for path in group['tests']}
notes_suites = {(group['cwd'] + '/' + path, group.get('platform', 'vm'))
                for group in notes['groups'] for path in group['tests']}
zotero_suites = {(group['package'] + '/' + path, group.get('platform', 'vm'))
                 for group in zotero['test_gates'].values() for path in group['tests']}
mail = json.loads((evidence / 'mail/summary.json').read_text())
mail_suites = {(case['file'], case['platform'])
               for cohort in mail['cohorts'] for case in cohort['cases']}
all_satisfied = selected | mail_suites
direct_tests = git('grep', '-l', '-E', r'WordLists\.|WordListNumberingSnapshot',
                   head, '--', 'packages/quds_office_engine/test',
                   'packages/quds_office_editor/test',
                   'packages/quds_office_editor/example/test').decode().splitlines()
direct_tests = [path.split(':', 1)[1] for path in direct_tests]
changed_dart = git('diff', '--name-only', '7e4adc08fce78fb95524f304962f9c1804e18691', head,
                   '--', 'packages', 'apps').decode().splitlines()
changed_dart = [path for path in changed_dart if path.endswith('.dart')]
changed_cases = [path for path in changed_dart if path.endswith('_test.dart')]
helper = 'packages/quds_office_editor/test/support/review_fonts.dart'
coverage = {
    'schema': 1, 'checked_at_utc': datetime.now(timezone.utc).isoformat(),
    'head': head, 'tree': tree,
    'scope': 'Selected runtime suite-path/platform coverage and changed callers; not a whole-repository or runtime pass claim.',
    'plan': {'path': plan_path, 'sha256': digest(plan_bytes),
             'matches_committed_plan': plan_bytes == blob(plan_path),
             'groups': [{'name': g['name'], 'suites': len(g['tests'])} for g in plan['groups']],
             'declared_suites': sum(len(g['tests']) for g in plan['groups']),
             'distinct_suite_platform_pairs': len(selected)},
    'incoming_plan_checks': [],
    'direct_numbering_test_callers': [{'path': p, 'selected': (p, 'vm') in selected} for p in direct_tests],
    'changed_application_dart_paths_since_saved_head': changed_dart,
    'changed_test_suites': [{'path': p, 'selected': (p, 'vm') in selected} for p in changed_cases],
    'font_helper': {'path': helper, 'included_in_analysis': helper in plan['analysis'],
                    'included_in_format': helper in plan['format'],
                    'importing_suites': [p for p in changed_cases if b"support/review_fonts.dart" in blob(p)]},
    'separate_runtime_fixture': {
        'path': 'docs/validation/document-review-notes-20261118/runtime/native_asset_smoke.dart',
        'scope': 'Incoming runtime-restoration smoke, not an application test suite or part of the selected 129 suites.'},
    'decision': 'Keep the 129-suite plan; retain separately source-bound Mail gate for omitted Mail core/store/MIME platform cohorts.',
    'github_actions_calls': 0,
}
for name, source_path, suites in [('notes', notes_path, notes_suites), ('zotero', zotero_path, zotero_suites)]:
    excluded = suites - selected
    uncovered = suites - all_satisfied
    coverage['incoming_plan_checks'].append({
        'name': name, 'path': source_path, 'sha256': digest(blob(source_path)),
        'suite_platform_pairs': len(suites), 'included_in_selected_plan': len(suites & selected),
        'preserved_mail_coverage': [{'path': p, 'platform': platform} for p, platform in sorted(excluded & mail_suites)],
        'uncovered': [{'path': p, 'platform': platform} for p, platform in sorted(uncovered)]})
coverage['passed'] = (all(not x['uncovered'] for x in coverage['incoming_plan_checks'])
                      and all(x['selected'] for x in coverage['direct_numbering_test_callers'])
                      and all(x['selected'] for x in coverage['changed_test_suites'])
                      and coverage['font_helper']['included_in_analysis']
                      and coverage['font_helper']['included_in_format']
                      and len(selected) == 129)
(out / 'selected-plan-review.json').write_text(json.dumps(coverage, indent=2) + '\n')

native_root = evidence / 'thesaurus-release/thesaurus-release-validation/run-3'
native_receipt_bytes = (native_root / 'receipt.json').read_bytes()
native_receipt = json.loads(native_receipt_bytes)
native_inputs_bytes = gzip.decompress((native_root / 'source-inputs.json.gz').read_bytes())
native = json.loads(native_inputs_bytes)
plain = {p: v for p, v in native.items() if not p.startswith('__')}
native_plain = compare_map(plain)
fixture_prefix = 'docs/validation/thesaurus-20261118/continuation/local/fixtures/'
auxiliary = {fixture_prefix + p.removeprefix('__fixture__/'): v for p, v in native.items() if p.startswith('__fixture__/')}
auxiliary.update({p.removeprefix('__helper__/'): v for p, v in native.items() if p.startswith('__helper__/')})
native_auxiliary = compare_map(auxiliary)
application_records = {p: v for p, v in plain.items()
                       if '/lib/' in p or p.startswith('lib/') or '/assets/' in p or '/fonts/' in p
                       or p.endswith(('pubspec.yaml', 'pubspec.lock')) or p in ('.fvmrc', 'analysis_options.yaml')}
application_check = compare_map(application_records)
suite_paths = []
for argument in native_receipt['runs'][0]['command']:
    if argument.endswith('_test.dart'):
        suite_paths.append(argument.split('/quds_office_suite/', 1)[1]
                           if '/quds_office_suite/' in argument
                           else 'packages/quds_office_editor/' + argument)
tested_records = {p: plain.get(p, auxiliary.get(p)) for p in suite_paths}
assert all(tested_records.values())
native_tests = compare_map(tested_records)
new_in_covered_roots = []
for path in git('diff', '--diff-filter=A', '--name-only', native_receipt['base_commit'], head).decode().splitlines():
    if path.startswith(('packages/', 'apps/', 'third_party/')) and path not in plain:
        new_in_covered_roots.append(path)
mail_results = []
for path in ['mail/store-attempt-2-offline/receipt.json', 'mail/mime-attempt-1/receipt.json',
             'mail/final-parser-reconciliation/controls-receipt.json']:
    receipt_bytes = (evidence / path).read_bytes()
    receipt = json.loads(receipt_bytes)
    check = compare_map(receipt['source_before'])
    runtime_source = {p: v for p, v in receipt['source_before'].items()
                      if not p.startswith('tools/mail/')}
    mail_results.append({'receipt': path, 'receipt_sha256': digest(receipt_bytes),
                         'recorded_starting_commit': receipt.get('starting_commit'),
                         'recorded_status': receipt.get('status'),
                         'recorded_exit_code': receipt.get('exit_code'),
                         'recorded_source_unchanged': receipt.get('source_unchanged'),
                         'all_recorded_inputs': check,
                         'non_runner_source_records': compare_map(runtime_source)})
continuity = {
    'schema': 1, 'checked_at_utc': datetime.now(timezone.utc).isoformat(),
    'head': head, 'tree': tree,
    'scope': 'SHA-256 of immutable current Git blobs compared with retained original source records; this is continuity verification, not rerunning or rebinding prior runtime receipts.',
    'native': {'original_source_commit': native_receipt['base_commit'],
               'receipt_sha256': digest(native_receipt_bytes), 'input_map_sha256': digest(native_inputs_bytes),
               'recorded_status': native_receipt['status'], 'recorded_input_entries': len(native),
               'ordinary_source_records': native_plain, 'application_assets_and_configuration': application_check,
               'fixture_and_helper_records': native_auxiliary, 'selected_suite_records': native_tests,
               'new_files_in_recorded_source_roots': new_in_covered_roots,
               'original_workspace_specific_records_not_rebound': [p for p in native if p.startswith('__workspace')],
               'entire_input_inventory_unchanged': False,
               'interpretation': 'Retain 208 native passes and the successful original source-bound web compilation/install evidence at source 3847d5f4. Current application/build-fixture bytes and the 14 selected native suites are unchanged, while the broader test/changelog inventory and workspace identity differ. Do not describe this as a fresh current-HEAD build or full inventory equality.'},
    'mail': mail_results,
    'mail_interpretation': 'Retain the 152 distinct Dart cases under their original recorded runs. Application/test sources still match; earlier check_store runner/control files were superseded and are bound separately by final-parser-reconciliation. Node browser_problem coverage is retained, but actual browser storage acceptance remains open.',
    'open_acceptance_gates': ['actual offline browser', 'installed native Studio and real OS/IME', 'independent human linguistic review'],
    'new_runtime_executions': 0, 'github_actions_calls': 0,
}
continuity['passed'] = (not application_check['different'] and not application_check['missing']
                        and not native_auxiliary['different'] and not native_auxiliary['missing']
                        and not native_tests['different'] and not native_tests['missing']
                        and all(not r['non_runner_source_records']['different'] and not r['non_runner_source_records']['missing'] for r in mail_results)
                        and not mail_results[-1]['all_recorded_inputs']['different']
                        and not mail_results[-1]['all_recorded_inputs']['missing'])
(out / 'retained-source-continuity.json').write_text(json.dumps(continuity, indent=2) + '\n')
batch.stdin.close()
batch.wait()
print(json.dumps({'plan_passed': coverage['passed'], 'selected_suites': len(selected),
                  'incoming_uncovered': {x['name']: x['uncovered'] for x in coverage['incoming_plan_checks']},
                  'source_continuity_passed': continuity['passed'],
                  'native_plain': native_plain,
                  'native_new_files': new_in_covered_roots,
                  'mail_differences': [{x['receipt']: x['all_recorded_inputs']['different']} for x in mail_results]}, indent=2))
