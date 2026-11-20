#!/usr/bin/env python3
"""Audit the added post-main guard without relabeling the earlier134-suite wave."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('independent_core', HERE / 'audit_validation.py')
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)
REPO, SDK = core.REPO, core.SDK
PRIMARY = 'f0122cb5bff5b6cf6a6f69f043545dabc2930791'
GUARD = 'packages/quds_office_engine/test/office_macro_word_revision_guard_test.dart'
EXTRA_INPUTS = {GUARD, 'packages/quds_office_engine/test/fixtures/word_reviews/.gitattributes'}
ADAPTER_SHA = '05948848ca260398505f78e430291524e490447b75dd3a30a45e99c8ca8bbdc0'
RUNNER_SHA = '4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO).decode().strip()


def require(condition, message):
    if not condition:
        failures.append(message)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--receipt-dir', type=Path, default=HERE.parent/'post-main/accepted-word-revision-guard')
parser.add_argument('--static', type=Path, required=True, help='New55-target post-main static receipt directory.')
parser.add_argument('--main-head', required=True, help='Exact remote main commit integrated after primary qualification.')
args = parser.parse_args()
folder = args.receipt_dir.resolve()
receipt = core.read_json(folder/'receipt.json')
post_head = receipt['source_head_at_start']
main_head = git('rev-parse', args.main_head+'^{commit}')
current_head = git('rev-parse', 'HEAD')
failures = []
require(receipt['status'] == 'passed' and receipt['exit_code'] == 0 and not receipt['timed_out'], 'Post-main guard process did not pass')
require(receipt['source_head_at_finish'] == post_head and receipt['head_unchanged'], 'Guard source changed during execution')
require(all(receipt['guards'].values()), 'A guard receipt acceptance condition failed')
require(post_head != PRIMARY, 'The additional suite must retain its distinct post-main source attribution')
require(subprocess.run(['git', 'merge-base', '--is-ancestor', PRIMARY, post_head], cwd=REPO).returncode == 0, 'Primary source is not ancestor of guard source')
require(subprocess.run(['git', 'merge-base', '--is-ancestor', main_head, post_head], cwd=REPO).returncode == 0, 'Captured publication main is not ancestor of guard source')
require(subprocess.run(['git', 'merge-base', '--is-ancestor', post_head, current_head], cwd=REPO).returncode == 0, 'Current checkout does not descend from the qualified guard commit')

for name, expected in receipt['artifacts'].items():
    require(core.file_record(folder/name) == expected, f'Guard artifact hash mismatch: {name}')
require(core.read_json(folder/'input-check.json') == receipt['fingerprints'], 'Guard input-check artifact differs')
adapter = core.read_json(folder/'selection-adapter.json')
require(adapter == receipt['selection_adapter'], 'Adapter artifact differs from receipt')
require(adapter['code_before'] == adapter['code_after'] and adapter['code_unchanged'], 'Adapter/runner code changed')
require(adapter['primary_runner_exit_code'] == 0 and adapter['primary_test_audit_and_fingerprint_logic_unchanged'], 'Adapter did not delegate unchanged primary qualification')
expected_spec = {'package':'packages/quds_office_engine', 'patterns':[], 'additional':['office_macro_word_revision_guard_test.dart'], 'runner':'dart'}
require(adapter['selection'] == expected_spec and adapter['cohort'] == receipt['cohort'] == 'word-revision-guard', 'Unexpected adapter selection')
for label, expected_sha in [('adapter', ADAPTER_SHA), ('primary_runner', RUNNER_SHA)]:
    recorded = adapter['code_before'][label]
    actual = core.file_record(Path(recorded['path']))
    require(recorded['sha256'] == actual['sha256'] == expected_sha and recorded['bytes'] == actual['bytes'], f'Unexpected executed {label} bytes')
require(receipt['validation_runner']['sha256'] == RUNNER_SHA, 'Guard runner hash differs from frozen core runner')
cwd = REPO/'packages/quds_office_engine'
expected_command = [str(SDK/'bin/cache/dart-sdk/bin/dart'), f'--packages={REPO}/.dart_tool/package_config.json', str(core.package_roots()['test']/'bin/test.dart'), '--reporter','json','--concurrency','1','test/office_macro_word_revision_guard_test.dart']
require(receipt['command'] == expected_command and receipt['cwd'] == str(cwd), 'Guard did not execute exact intended native-VM command')
require(receipt['runner'] == 'dart' and receipt['package'] == 'packages/quds_office_engine' and receipt['concurrency'] == 1 and not receipt['application_timeouts_modified'], 'Unexpected guard runtime/timeout metadata')
require(receipt['selected_repository_paths'] == [GUARD] and receipt['selected_files'] == ['test/office_macro_word_revision_guard_test.dart'], 'Guard selected additional or wrong suites')

actual, extra_cases = core.recount(folder/'events.jsonl.gz', cwd)
failures.extend(actual['errors'])
require(actual['passed'] == 2 and actual['failed'] == actual['skipped'] == 0 and actual['suite_count'] == 1, 'Guard raw completion counts differ from two successful cases')
require([suite['path'] for suite in actual['suites']] == [GUARD], 'Guard executed unexpected suite paths')
for key in ['passed','failed','skipped','application_cases','suite_count','test_start_events','test_done_events']:
    require(actual[key] == receipt['tests'][key], f'Guard receipt count mismatch: {key}')
require(actual['excluded_lifecycle_cases'] == receipt['tests']['excluded_pseudo_cases'], 'Guard lifecycle count mismatch')

core.FROZEN = post_head
post_blobs = core.committed_blobs()
manifest = core.read_json(folder/'inputs.json.gz')
inputs = core.verify_inputs(receipt, manifest, post_blobs)
failures.extend(inputs['failures'])
core.STATIC_ROOT = args.static.resolve()
post_static = core.verify_static(post_blobs)
require(post_static['status'] == 'verified' and post_static['target_count'] == 55, 'Post-main55-target static qualification did not verify')
failures.extend(post_static.get('failures', []))

primary = core.read_json(HERE/'audit.json')
primary_cases = core.read_json(HERE/'application-cases.json.gz')
require(primary['status'] == 'verified_complete' and primary['frozen_product_commit'] == PRIMARY, 'Primary final audit is not complete at f012')
require(primary['aggregate']['completed_verified_cohorts'] == 10 and primary['aggregate']['verified_suites'] == 134, 'Primary134-suite scope differs')
require(core.file_record(HERE/'application-cases.json.gz') == primary['application_cases_artifact'], 'Primary case file is not the artifact certified by its audit')
require(len(primary_cases) == primary['aggregate']['verified_passed'], 'Primary case file count differs from verified aggregate')
require(all(case['result'] == 'success' and not case['skipped'] for case in primary_cases), 'Primary case file contains failed or skipped cases')
require(len({case['suite'] for case in primary_cases}) == 134, 'Primary case file suite count differs')
primary_inputs = core.read_json(HERE.parent/'accepted-engine-zotero/inputs.json.gz')['before']['source']
post_inputs = manifest['before']['source']
require(len(primary_inputs) == 3994, 'Primary source inventory count differs')
require(primary['aggregate']['source_inventory_sha256'] == [core.digest(primary_inputs)], 'Primary source inventory is not bound to the completed primary audit')
missing = sorted(set(primary_inputs)-set(post_inputs))
changed = sorted(name for name in primary_inputs if primary_inputs[name] != post_inputs.get(name))
extra_inputs = sorted(set(post_inputs)-set(primary_inputs))
require(not missing and not changed, 'A previously qualified source input changed or disappeared')
require(set(extra_inputs) == EXTRA_INPUTS, 'Unexpected additional post-main source inputs')
blobs_identical = all(post_blobs.get(name) == record['git_blob_sha1'] for name,record in primary_inputs.items())
require(blobs_identical, 'Existing source blobs differ in guard commit')
dart_changes = git('diff','--name-only',PRIMARY,post_head,'--','*.dart').splitlines()
require(dart_changes == [GUARD], 'Post-main integration changes product Dart source beyond the new test')

identities = Counter((case['suite'],case['name']) for case in primary_cases+extra_cases)
duplicates = [{'suite':key[0],'name':key[1],'count':count} for key,count in identities.items() if count != 1]
require(not duplicates, 'Additional suite duplicates primary application identities')
require(len(identities) == primary['aggregate']['verified_passed'] + 2 and len({suite for suite,_ in identities}) == 135, 'Combined total does not equal primary plus two cases across135 suites')
expanded_catalog = core.selected_paths()
catalog_paths = {path for paths in expanded_catalog.values() for path in paths}
executed_paths = {suite for suite,_ in identities}
require(catalog_paths == executed_paths and len(catalog_paths) == 135, 'Combined executed suites do not cover the expanded post-main135-path selection')
require(all(case['result'] == 'success' and not case['skipped'] for case in extra_cases), 'Additional cases are not successful unskipped completions')
before_sdk = core.read_json(HERE/'runtime-supplement-before.json.gz')
after_sdk = core.read_json(HERE/'runtime-supplement-after.json.gz')
require(after_sdk['unchanged'], 'Final full SDK inventory changed')
for label, inventory in [('before', before_sdk), ('after', after_sdk)]:
    require(inventory['file_count'] == len(inventory['files']) and inventory['inventory_sha256'] == core.digest(inventory['files']), f'Full SDK {label} metadata differs from its mapping')
require(before_sdk['files'] == after_sdk['files'] and not after_sdk['changed_paths'] and not after_sdk['extra_paths'], 'Full SDK mappings show input drift')
require(primary['runtime_supplement']['inventory_sha256'] == before_sdk['inventory_sha256'] and primary['runtime_supplement']['after']['inventory_sha256'] == after_sdk['inventory_sha256'], 'Full SDK mappings are not bound to the completed primary audit')
require(datetime.fromisoformat(before_sdk['capture_finished_utc']) < datetime.fromisoformat(receipt['started_at_utc']), 'Full SDK baseline was not before guard dispatch')
require(datetime.fromisoformat(after_sdk['capture_started_utc']) > datetime.fromisoformat(receipt['finished_at_utc']), 'Full SDK after inventory was captured before guard completion')

result = {
    'audited_at_utc':datetime.now(timezone.utc).isoformat(),
    'status':'verified' if not failures else 'rejected',
    'primary_commit':PRIMARY, 'post_main_guard_commit':post_head, 'integrated_remote_main':main_head, 'current_head':current_head,
    'qualification_attribution':'134 suites ran at f012; the added two-case suite ran separately at the post-main commit. Existing3994 qualified inputs are byte-identical. No claim that all135 suites ran at one commit.',
    'primary':{'cohorts':10,'passed':primary['aggregate']['verified_passed'],'suites':134,'audit_sha256':core.file_record(HERE/'audit.json')['sha256']},
    'additional':{'passed':actual['passed'],'suites':actual['suite_count'],'source_commit':post_head,'receipt_sha256':core.file_record(folder/'receipt.json')['sha256'],'inputs':inputs},
    'combined':{'distinct_passed_cases':len(identities),'distinct_suites':len({suite for suite,_ in identities}),'duplicate_identities':duplicates,'supplemental_case_count_addition':0},
    'selection':{'primary_executed_at':PRIMARY,'primary_paths':sorted({case['suite'] for case in primary_cases}),'additional_executed_at':post_head,'additional_paths':[GUARD],'expanded_post_main_catalog':expanded_catalog,'combined_executed_paths':sorted(executed_paths),'note':'The expanded135-path catalog is covered by the two explicitly attributed executions; it is not a claim that the earlier134 suites were rerun at the post-main commit.'},
    'source_identity':{'previously_qualified_inputs':len(primary_inputs),'post_main_input_count':len(post_inputs),'missing':missing,'changed':changed,'additional':extra_inputs,'dart_changes':dart_changes,'all_existing_blobs_identical':not missing and not changed and blobs_identical},
    'post_main_static':post_static, 'sdk_after_covers_additional_guard':not any('SDK' in str(error) for error in failures),
    'failures':failures, 'auditor_sha256':core.file_record(Path(__file__))['sha256'], 'imported_auditor_sha256':core.file_record(HERE/'audit_validation.py')['sha256'],
    'limits':['Read-only audit of existing evidence; no application tests or commands were rerun.','The69 portable VBA cases overlap the conformance unit suite;30 MIME receiver assertions are supplementary and add zero unit cases.'],
}
(HERE/'post-main-audit.json').write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
(HERE.parent/'post-main/audit.json').write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
print(json.dumps(result,indent=2))
raise SystemExit(1 if failures else 0)
