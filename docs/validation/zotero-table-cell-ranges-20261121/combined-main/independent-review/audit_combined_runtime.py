#!/usr/bin/env python3
"""Independently inspect fixed supplemental execution bytes; never run tests."""
import collections
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tarfile

sys.dont_write_bytecode = True
ROOT = Path('/workspace/scratch/a4ce103494d8')
REPO = ROOT / 'quds_office_suite'
BASE = ROOT / 'cell-validation/combined-main'
RUN = BASE / 'frozen-5289b90'
REVIEW = ROOT / 'zotero-cell-review'
COMMIT = '5289b90a83ce9042a4f4cfb73ba8115fe501513a'
SOURCE_SHA = '86723cbca9b7f6eb17f3be8223e1bd20c09cec46ca68a9efa82bb498fe646cc4'
ORIGINAL_ARCHIVE_SHA = '7605bf4f72509aa52d5544fcca515e0b15997679ecab0ddf717db2068ab83229'
PARSER_SHA = 'e4f999fe672c0f11eef0d18d4b6488434ba02737e34f30dc2d1f86459b3610fb'


def read(path):
    return json.loads(path.read_text())


def packed(path):
    return json.loads(gzip.decompress(path.read_bytes()))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


parser_file = REVIEW / 'audit_qualification.py'
assert sha(parser_file.read_bytes()) == PARSER_SHA
spec = importlib.util.spec_from_file_location('original_independent_parser', parser_file)
parser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser)
plan = read(BASE / 'selection.json')
assert plan == read(RUN / 'selection.json')
assert plan['frozen_commit'] == COMMIT
assert git('rev-parse', COMMIT + '^{tree}').decode().strip() == plan['frozen_git_tree']
source = packed(RUN / 'frozen-source.json.gz')
assert len(source) == 2994 and sha(canonical(source)) == SOURCE_SHA
assert packed(RUN / 'final-source.json.gz') == source

tree = {}
for row in git('ls-tree', '-rz', COMMIT).split(b'\0'):
    if not row:
        continue
    meta, path = row.split(b'\t', 1)
    mode, kind, blob = meta.decode().split()
    tree[path.decode()] = (mode, kind, blob)
derived = set()
for path in tree:
    p = Path(path)
    if path in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'):
        derived.add(path)
    if not path.startswith(('packages/', 'third_party/')):
        continue
    if any(part in p.parts for part in ('.dart_tool', 'build', 'docs')):
        continue
    if (p.suffix == '.dart' or p.name in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')
            or '/test/fixtures/' in path
            or (path.startswith('packages/quds_office_engine/example/macros/') and p.suffix == '.bas')):
        derived.add(path)
metadata_exclusion = 'packages/quds_office_engine/test/fixtures/word_reviews/.gitattributes'
assert derived - set(source) == {metadata_exclusion} and not set(source) - derived
for path, record in source.items():
    data = (REPO / path).read_bytes()
    blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    assert record == {'size': len(data), 'sha256': sha(data),
                      'git_blob_sha1': blob, 'executable': bool((REPO / path).stat().st_mode & 0o111)}, path
    assert tree[path] == ('100755' if record['executable'] else '100644', 'blob', blob), path
metadata = (REPO / metadata_exclusion).read_bytes()
assert git('show', COMMIT + ':' + metadata_exclusion) == metadata
environment = read(RUN / 'environment-before.json')
assert len(environment) == 33
assert read(RUN / 'environment-after.json') == environment
assert read(ROOT / 'cell-validation/frozen-remaining/environment-before.json') == environment
run = read(RUN / 'run.json')
assert run['runner_sha256'] == sha((BASE / 'run_qualification.py').read_bytes())
assert run['selection_sha256'] == sha((BASE / 'selection.json').read_bytes())
assert run['source_head_at_start'] == COMMIT and run['source_map_sha256'] == SOURCE_SHA

all_cases, cohorts, files = [], [], []
for cohort in plan['cohorts']:
    directory = RUN / cohort['name']
    command = read(directory / 'command.json')
    selected = [cohort['package'] + '/' + path for path in cohort['tests']]
    assert command['selected_test_files'] == selected
    prefix = ([str(ROOT / 'runtime-setup/dart-test.sh')]
              if cohort['runner'] == 'dart'
              else [str(ROOT / 'runtime-setup/flutter-sdk/bin/flutter'), 'test', '--no-pub'])
    expected_command = prefix + ['--reporter', 'json', '--concurrency', str(cohort['concurrency']),
                                 '--timeout', cohort['test_timeout'], *cohort['tests']]
    assert command['command'] == expected_command
    exit_record = read(directory / 'process-exit.json')
    assert exit_record['exit_code'] == 0 and not exit_record['timed_out']
    assert packed(directory / 'source-before.json.gz') == source
    assert packed(directory / 'source-after.json.gz') == source
    result = parser.inspect_events(directory, command, selected, REPO)
    recorded = read(directory / 'summary.json')
    assert result['stdout_sha256'] == recorded['stdout_sha256']
    assert result['passed'] == recorded['counts']['passed']
    assert result['suites'] == recorded['counts']['suites']
    actual = result.pop('cases')
    recorded_cases = packed(directory / 'cases.json.gz')
    normalized = []
    for case in recorded_cases:
        p = Path(case['suite'])
        p = (p if p.is_absolute() else Path(command['cwd']) / p).resolve()
        normalized.append((str(p.relative_to(REPO)), case['name']))
    assert normalized == [(c['suite'], c['name']) for c in actual]
    all_cases.extend(actual)
    files.extend(selected)
    result.pop('excluded_events')
    cohorts.append({'name': cohort['name'], **result})
assert len(files) == len(set(files)) == 6
actual_keys = {(case['suite'], case['name']) for case in all_cases}
assert len(actual_keys) == len(all_cases) == 151

evidence = REPO / 'docs/validation/zotero-table-cell-ranges-20261121/evidence.tar.xz'
assert sha(evidence.read_bytes()) == ORIGINAL_ARCHIVE_SHA
old_cases = []
with tarfile.open(evidence, 'r:xz') as archive:
    original = json.loads(archive.extractfile('qualification/qualification.json').read())
    old_source = json.loads(gzip.decompress(archive.extractfile('qualification/frozen-final/frozen-source.json.gz').read()))
    for cohort in original['cohorts']:
        directory = 'qualification/' + cohort['execution_directory']
        command = json.loads(archive.extractfile(directory + '/command.json').read())
        cases = json.loads(gzip.decompress(archive.extractfile(directory + '/cases.json.gz').read()))
        for case in cases:
            assert case['result'] == 'success' and not case['skipped']
            p = Path(case['suite'])
            p = (p if p.is_absolute() else Path(command['cwd']) / p).resolve()
            old_cases.append((str(p.relative_to(REPO)), case['name']))
old_keys = set(old_cases)
assert len(old_keys) == len(old_cases) == 2551
repeat_suites = set(files[:4])
expected_overlap = {key for key in old_keys if key[0] in repeat_suites}
assert len(expected_overlap) == 72 and actual_keys & old_keys == expected_overlap
new_regression = ('packages/quds_office_editor/example/test/studio_saved_mail_test.dart',
                  'saved and account Mail views each expose one localized Close')
assert new_regression in actual_keys and new_regression not in old_keys
counts = dict(sorted(collections.Counter(c['suite'] for c in all_cases).items()))
published = read(BASE / 'supplemental-qualification.json')
assert counts == published['case_counts_by_suite']
assert published['source_map_sha256'] == SOURCE_SHA and published['actual_passed'] == 151
modified = sorted(p for p in old_source if p in source and old_source[p] != source[p])
added = sorted(set(source) - set(old_source))
removed = sorted(set(old_source) - set(source))
assert len(modified) == 16 and len(added) == 16 and not removed

report = {
    'status': 'accepted', 'reviewed_commit': COMMIT,
    'reviewed_tree': plan['frozen_git_tree'], 'source_input_count': len(source),
    'source_map_sha256': SOURCE_SHA, 'recorded_sources_match_commit_and_current': True,
    'all_run_and_cohort_source_maps_equal': True,
    'input_changes_from_original': {'unchanged': len(old_source) - len(modified),
        'modified': modified, 'added': added, 'removed': removed},
    'explicit_hidden_nonruntime_metadata_exclusion': metadata_exclusion,
    'excluded_metadata_matches_commit': True, 'excluded_metadata_bound_during_run': False,
    'recorded_runtime_files': len(environment),
    'runtime_environment_unchanged_from_original_and_during_supplemental_run': True,
    'cohorts': cohorts, 'actual_cases': 151, 'suite_files': 6,
    'distinct_case_identities_within_this_execution': 151,
    'case_counts_by_suite': counts, 'failures': 0, 'skips': 0,
    'runtime_errors': 0, 'stderr_bytes': 0, 'processes_completed_successfully': 3,
    'original_case_identity_overlap': 72,
    'original_accepted_distinct_cases': 2551,
    'new_global_close_regression_success': True,
    'no_cross_archive_distinct_total_claimed': True,
    'original_archive_sha256': ORIGINAL_ARCHIVE_SHA,
    'runner_sha256': run['runner_sha256'], 'independent_event_parser_sha256': PARSER_SHA,
    'independent_audit_script_sha256': sha(Path(__file__).read_bytes()),
    'method': 'Exact original file commands and raw package:test/Flutter event reconstruction; only successful loading/lifecycle events excluded; one start/completion per case, unique successful terminal, no skips/errors/stderr. Source path population, bytes, Git blobs and modes checked independently against committed target.',
    'limits': 'Only six selected suites executed here; 72 cases repeat the original population. Mail includes existing cases and one new regression. Runtime environment coverage is 33 recorded files, not all extracted dependency bytes. No new test process was launched by this review.',
}
(REVIEW / 'combined-runtime-review.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({k: report[k] for k in ('status', 'reviewed_commit', 'source_input_count',
    'source_map_sha256', 'actual_cases', 'suite_files', 'original_case_identity_overlap',
    'failures', 'skips', 'runtime_errors', 'stderr_bytes')}, indent=2))
