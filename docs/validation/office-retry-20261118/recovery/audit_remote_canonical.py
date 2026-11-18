from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
import base64
import collections
import gzip
import hashlib
import io
import json
import tarfile

ROOT = Path(__file__).resolve().parent
INPUT = ROOT / 'remote-checkpoint-7b449f1b'
META = json.loads((INPUT / 'retrieval.json').read_text())
SOURCE = '9d060658ee6be8ec97d73f56b9aec10d346b7952'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()

def text_file(name, expected_blob):
    path = INPUT / name
    data = path.read_bytes()
    if blob(data) != expected_blob:
        data = data.rstrip(b'\n') + b'\n'
        assert blob(data) == expected_blob, name
        path.write_bytes(data)
    return data

index_bytes = text_file('canonical-complete.tar.index.json', META['index']['blob'])
review_bytes = text_file('canonical-review.json', META['review']['blob'])
index = json.loads(index_bytes)
review = json.loads(review_bytes)
archive_bytes = base64.b64decode((INPUT / 'canonical-complete.archive.base64').read_bytes())
assert len(archive_bytes) == index['bytes'] == 1038316
assert sha(archive_bytes) == index['sha256']
assert blob(archive_bytes) == META['archive']['blob']
expected = {m['path']: m for m in index['members']}
assert len(expected) == len(index['members']) == index['member_count'] == 90
members = {}
with tarfile.open(fileobj=io.BytesIO(archive_bytes)) as tar:
    names = tar.getnames()
    assert len(names) == len(set(names)) == len(expected)
    assert set(names) == set(expected)
    for member in tar.getmembers():
        path = PurePosixPath(member.name)
        assert member.isfile() and not path.is_absolute() and '..' not in path.parts
        data = tar.extractfile(member).read()
        assert len(data) == expected[member.name]['bytes']
        assert sha(data) == expected[member.name]['sha256']
        members[member.name] = data
(INPUT / 'canonical-complete.tar.xz').write_bytes(archive_bytes)
receipt = json.loads(members['receipt.json'])
state = json.loads(members['checkpoint-state.json'])
plan = json.loads(members['plan.json'])
assert receipt['source_commit'] == state['source_commit'] == plan['source_commit'] == review['source_commit'] == SOURCE
assert receipt['status'] == state['whole_run_status'] == 'passed'
assert receipt['all_passed'] and state['whole_run_accepted'] and state['final_input_integrity_available']
assert not state['running_commands_omitted']
assert receipt['working_head_after'] == SOURCE and receipt['source_matches_frozen_commit']
assert receipt['analysis_config_restored'] and receipt['cohorts_disjoint']
assert not receipt['github_actions_queried_awaited_or_rerun']
assert not receipt['historical_qualifications_counted']
assert review['canonical_qualification_accepted'] and review['evidence_integrity_accepted']
assert not review['overall_office_qualification_accepted']
assert not review['findings'] and not review['gate_failures']
assert review['original_receipt_sha256'] == sha(members['receipt.json'])
assert review['plan_sha256'] == receipt['plan_sha256'] == sha(members['plan.json'])
integrity = {}
for family in ['source', 'dependencies', 'runtime', 'workspace', 'system', 'harness']:
    before, after = (members[family + '-' + phase + '.json'] for phase in ['before', 'after'])
    assert before == after
    assert receipt['input_integrity'][family + '_unchanged']
    assert review['input_integrity'][family]['byte_identical']
    assert review['input_integrity'][family]['before_sha256'] == sha(before)
    assert review['input_integrity'][family]['after_sha256'] == sha(after)
    integrity[family] = {'sha256': sha(before), 'byte_identical': True}
expected_commands = ['engine-strict-analysis', 'editor-strict-analysis', 'harper-strict-analysis', 'gector-strict-analysis', 'proofing-tools-strict-analysis', 'format', 'python-controls', 'engine-zotero', 'editor-zotero', 'engine-integration', 'editor-integration', 'harper-contract', 'gector-contract']
assert [r['name'] for r in receipt['commands']] == expected_commands == state['completed_command_names']
cohorts = {}
selected = []
for command in receipt['commands']:
    name = command['name']
    assert command['exit_code'] == 0 and not command['timed_out'] and command['status'] == 'passed'
    streams = {}
    for stream in ['stdout', 'stderr']:
        packed = members[name + '/' + stream + '.gz']
        unpacked = gzip.decompress(packed)
        assert sha(packed) == command[stream + '_gzip_sha256']
        assert sha(unpacked) == command[stream + '_sha256']
        streams[stream] = unpacked
    if name not in plan['cohorts']:
        continue
    events = [json.loads(line) for line in streams['stdout'].decode().splitlines() if line.strip()]
    starts = {row['test']['id']: row['test'] for row in events if row['type'] == 'testStart'}
    dones = [row for row in events if row['type'] == 'testDone']
    assert len(starts) == len(dones) == len({row['testID'] for row in dones})
    assert all(row['result'] == 'success' and not row['skipped'] for row in dones)
    assert not [row for row in events if row['type'] == 'error']
    finals = [row for row in events if row['type'] == 'done']
    assert len(finals) == 1 and finals[0]['success']
    visible = [row for row in dones if not row.get('hidden', False)]
    suites = []
    for row in events:
        if row['type'] != 'suite':
            continue
        path = PurePosixPath(row['suite']['path'].replace('\\', '/'))
        if path.is_absolute():
            path = path.relative_to(PurePosixPath(command['cwd']))
        suites.append(str(path))
    tests = plan['cohorts'][name]['tests']
    assert len(suites) == len(set(suites)) == len(tests)
    assert set(suites) == set(tests)
    selected.extend(plan['cohorts'][name]['kind'] + ':' + path for path in tests)
    summary = json.loads(members[name + '/test-summary.json'])
    assert summary['passed'] and summary['runner_success']
    assert not summary['errors'] and not summary['allowed_skipped_cases'] and not summary['unexpected_skipped_cases']
    assert not summary['missing_selected_suites'] and not summary['unexpected_suites']
    assert len(visible) == summary['raw_success_count'] == review['cohorts'][name]['raw_success_count']
    exclusions = summary['excluded_success_cases']
    allowed_exclusions = {'TrueType subsets without cmap get ToUnicode cmap for the host', 'JPEG with DCT SMask attaches softMaskJpeg for the host'} if name == 'engine-integration' else set()
    assert {r['matched_case_name'] for r in exclusions} == allowed_exclusions
    for exclusion in exclusions:
        assert starts[exclusion['test_id']]['name'] == exclusion['name']
        assert exclusion['test_id'] in {row['testID'] for row in visible}
    substantive = len(visible) - len(exclusions)
    assert substantive == summary['substantive_success_count'] == review['cohorts'][name]['substantive_success_count']
    cohorts[name] = {'selected_files': len(tests), 'raw_visible_successes': len(visible), 'excluded_private_fixture_early_returns': len(exclusions), 'substantive_successes': substantive, 'skipped': 0, 'errors': 0, 'runner_completed_successfully': True}
assert len(selected) == len(set(selected)) == plan['unique_test_files'] == review['unique_selected_test_files'] == 224
python = json.loads(members['python-controls-summary.json'])
assert python['passed'] and python['runtime_unchanged']
assert python['tests_run'] == python['substantive_success_count'] == review['python_controls'] == 117
for field in ['skipped_cases', 'unexpected_skipped_cases', 'missing_selected_tests', 'failures', 'errors', 'expected_failures', 'unexpected_successes']:
    assert not python[field]
raw = sum(row['raw_visible_successes'] for row in cohorts.values())
substantive = sum(row['substantive_successes'] for row in cohorts.values())
assert raw == receipt['raw_runner_success_total'] == review['raw_runner_success_total'] == 4236
assert substantive == receipt['substantive_success_total'] == review['substantive_success_total'] == 4234
report = {
    'schema': 'quds.office.remote-canonical-readback.v1',
    'commit': META['commit'], 'completed_utc': datetime.now(timezone.utc).isoformat(),
    'source_commit': SOURCE, 'retrieval': META['source'], 'local_producer_git_objects_used': False,
    'remote_archive_url': META['archive']['url'], 'archive_bytes': len(archive_bytes),
    'archive_sha256': sha(archive_bytes), 'archive_git_blob_sha': blob(archive_bytes),
    'index_sha256': sha(index_bytes), 'review_sha256': sha(review_bytes),
    'all_remote_git_blob_identities_verified': True,
    'members_verified': len(members), 'all_members_match_remote_index': True,
    'canonical_qualification_accepted': True, 'overall_office_qualification_accepted': False,
    'supplemental_acceptance': 'separate gates pending; not asserted by this audit',
    'commands_verified': len(expected_commands), 'input_integrity': integrity,
    'cohorts': cohorts, 'unique_selected_test_files': len(selected),
    'raw_runner_success_total': raw, 'substantive_success_total': substantive,
    'python_controls': 117, 'skipped_tests': 0, 'tests_rerun': False,
    'source_or_runtime_modified': False, 'github_actions_used': False, 'passed': True,
}
(ROOT / 'remote-checkpoint-7b449f1b-audit.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
