#!/usr/bin/env python3
"""Independently verify the saved PR 175 evidence, without executing Dart."""
from __future__ import annotations

import collections
import datetime
import gzip
import hashlib
import json
import pathlib
import posixpath
import re
import subprocess
import tarfile

ROOT = pathlib.Path('/workspace/scratch/55e682a034c1/quds_office_suite')
OUT = pathlib.Path('/workspace/scratch/55e682a034c1/evidence_audit')
PUBLISHED = '840362cd74a3d4b4365cf2bc9a2ae326225009c3'
SOURCE = 'a7512e94da8208123aa2df5f5c2c0354d079ddc7'
BASE = 'docs/validation/document-review-notes-20261118/resumed/'
issues: list[str] = []


def check(condition: bool, description: str) -> None:
    if not condition:
        issues.append(description)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(*args: str) -> bytes:
    return subprocess.check_output(['git', *args], cwd=ROOT)


def published(path: str) -> bytes:
    return git('show', PUBLISHED + ':' + BASE + path)


def tree(commit: str) -> dict[str, tuple[str, str]]:
    answer = {}
    for line in git('ls-tree', '-r', '-z', commit).split(b'\0'):
        if not line:
            continue
        metadata, name = line.split(b'\t', 1)
        mode, _, blob = metadata.decode().split()
        answer[name.decode()] = mode, blob
    return answer


def main() -> None:
    index = json.loads(published('evidence-index.json'))
    archive = published('evidence.tar.xz')
    check(len(archive) == index['archive']['bytes'], 'archive byte length')
    check(sha(archive) == index['archive']['sha256'], 'archive SHA-256')
    import io
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:xz') as handle:
        members = handle.getmembers()
        names = [member.name for member in members]
        check(len(names) == len(set(names)), 'duplicate archive members')
        check(all(member.isfile() for member in members), 'non-file archive members')
        check(all(not pathlib.PurePosixPath(name).is_absolute() and '..' not in pathlib.PurePosixPath(name).parts for name in names), 'unsafe archive member path')
        files = {member.name: handle.extractfile(member).read() for member in members}
    check(set(files) == set(index['files']), 'archive and index exact member set')
    for name, data in files.items():
        recorded = index['files'][name]
        check(len(data) == recorded['bytes'] and sha(data) == recorded['sha256'], 'archive member bytes/hash: ' + name)
        if name.endswith('.gz'):
            check(gzip.decompress(data) == files[name[:-3]], 'gzip/raw equivalence: ' + name)

    v = json.loads(files['final/cohort/verification.json'])
    check(files['final/cohort/verification.json'] == published('verification.json'), 'published/archived gate receipt')
    check(v['source_commit'] == SOURCE == index['source_commit'], 'frozen source commit identity')
    check(git('rev-parse', SOURCE + '^{tree}').decode().strip() == v['source_tree'] == index['source_tree'], 'frozen source tree identity')
    for name, expected in v['manifest_sha256'].items():
        check(sha(files['final/cohort/' + name]) == expected, 'gate-bound manifest hash: ' + name)
    check(files['final/cohort/source-before.json'] == files['final/cohort/source-after.json'], 'source before/after identity')
    check(files['final/cohort/environment-before.json'] == files['final/cohort/environment-after.json'], 'environment before/after identity')
    source = json.loads(files['final/cohort/source-before.json'])
    env = json.loads(files['final/cohort/environment-before.json'])
    check(len(source) == v['source_input_count'] == v['materialized_source_inputs'], 'source input count')
    check(len(env) == v['runtime_input_count'], 'runtime input count')
    source_tree = tree(SOURCE)
    published_tree = tree(PUBLISHED)
    for path, metadata in source.items():
        check(source_tree.get(path) == (metadata['mode'], metadata['git_blob']), 'source tree inventory: ' + path)
        check(published_tree.get(path) == source_tree.get(path), 'source unchanged in published tree: ' + path)
        check(metadata['materialized'] is True and metadata['sparse_omission'] is False, 'materialization state: ' + path)

    # Read the actual frozen Git blobs in one batch, never trusting the repository runner.
    requests = ''.join(item['git_blob'] + '\n' for item in source.values()).encode()
    blob_bytes = subprocess.run(['git', 'cat-file', '--batch'], input=requests, stdout=subprocess.PIPE, check=True, cwd=ROOT).stdout
    stream = io.BytesIO(blob_bytes)
    for path, metadata in source.items():
        header = stream.readline().decode().strip().split()
        check(len(header) == 3 and header[0] == metadata['git_blob'] and header[1] == 'blob', 'blob lookup: ' + path)
        data = stream.read(int(header[2]))
        check(stream.read(1) == b'\n', 'blob batch separator: ' + path)
        check(sha(data) == metadata['sha256'], 'frozen source SHA-256: ' + path)
    check(stream.read() == b'', 'trailing blob batch bytes')

    plan_bytes = git('show', SOURCE + ':' + v['plan'])
    check(sha(plan_bytes) == v['plan_sha256'], 'frozen plan hash')
    plan = json.loads(plan_bytes)
    check(plan['groups'] == v['planned_groups'], 'actual frozen plan/receipt group equality')
    planned = {group['name']: group for group in v['planned_groups']}
    old_root = json.loads(files['runtime/runtime.json'])['source']
    group_results = []
    total = collections.Counter()
    all_observed_suites = set()
    for run in v['runs']:
        log_path = 'final/cohort/' + run['log']
        data = files[log_path]
        check(sha(data) == run['log_sha256'], 'receipt log hash: ' + run['name'])
        check(run['exit_code'] == 0 and run['accepted'] is True, 'process acceptance: ' + run['name'])
        if 'cases_file' not in run:
            continue
        group = planned[run['name']]
        # JSON parsing is strict: every nonempty line must be a complete event.
        events = [json.loads(line) for line in data.splitlines() if line.strip()]
        starts = [e for e in events if e.get('type') == 'start']
        terminals = [e for e in events if e.get('type') == 'done']
        errors = [e for e in events if e.get('type') == 'error']
        check(len(starts) == 1 and events[0]['type'] == 'start', 'single first start: ' + run['name'])
        check(len(terminals) == 1 and events[-1]['type'] == 'done' and terminals[0]['success'] is True, 'single final successful done: ' + run['name'])
        check(not errors, 'raw reporter errors: ' + run['name'])
        suite_events = [e['suite'] for e in events if e.get('type') == 'suite']
        suites = {e['id']: posixpath.normpath(e['path'] if e['path'].startswith('/') else posixpath.join(old_root, run['cwd'], e['path'])) for e in suite_events}
        check(len(suites) == len(suite_events), 'unique suite ids: ' + run['name'])
        expected_suites = {posixpath.join(old_root, run['cwd'], name) for name in group['tests']}
        check(set(suites.values()) == expected_suites and len(suites) == len(expected_suites), 'exact planned suites: ' + run['name'])
        all_observed_suites.update(suites.values())
        start_events = [e['test'] for e in events if e.get('type') == 'testStart']
        test_starts = {e['id']: e for e in start_events}
        done_events = [e for e in events if e.get('type') == 'testDone']
        dones = {e['testID']: e for e in done_events}
        check(len(test_starts) == len(start_events) and len(dones) == len(done_events), 'unique test lifecycle ids: ' + run['name'])
        check(set(test_starts) == set(dones), 'all started tests finished: ' + run['name'])
        derived = []
        hidden = 0
        counts = collections.Counter()
        per_suite = collections.defaultdict(collections.Counter)
        for done in done_events:
            test = test_starts[done['testID']]
            check(done['result'] == 'success' and not done.get('skipped') and not test.get('metadata', {}).get('skip'), 'non-success lifecycle event: ' + run['name'] + ': ' + test['name'])
            if done.get('hidden'):
                hidden += 1
                continue
            suite = suites[test['suiteID']]
            case = {'id': test['id'], 'name': test['name'], 'suite': suite, 'result': done['result'], 'skipped': done['skipped']}
            derived.append(case)
            bucket = 'skipped' if done['skipped'] else ('passed' if done['result'] == 'success' else 'failed')
            counts[bucket] += 1
            per_suite[suite][bucket] += 1
        saved_cases = files['final/cohort/' + run['cases_file']]
        check(sha(saved_cases) == run['cases_sha256'], 'case inventory hash: ' + run['name'])
        check(derived == json.loads(saved_cases), 'exact raw-event/case-inventory match: ' + run['name'])
        check(hidden == sum(run['excluded_events'].values()), 'hidden accounting: ' + run['name'])
        for key in ['passed', 'failed', 'skipped']:
            check(counts[key] == run[key], 'count ' + key + ': ' + run['name'])
        check(set(per_suite) == expected_suites, 'every requested suite has cases: ' + run['name'])
        for suite, saved in run['per_suite'].items():
            check(all(per_suite[suite][key] == saved[key] for key in ['passed', 'failed', 'skipped']), 'per-suite counts: ' + suite)
        errors_bytes = files['final/cohort/' + run['errors_file']]
        check(sha(errors_bytes) == run['errors_sha256'] and json.loads(errors_bytes) == [], 'error inventory: ' + run['name'])
        total.update(counts)
        group_results.append({'name': run['name'], 'suites': len(expected_suites), 'passed': counts['passed'], 'failed': counts['failed'], 'skipped': counts['skipped'], 'hidden_success_events_excluded': hidden, 'exact_case_inventory_match': derived == json.loads(saved_cases)})

    for key in ['passed', 'failed', 'skipped']:
        check(total[key] == v[key], 'overall ' + key + ' count')
    check(total['passed'] == 1244 and len(all_observed_suites) == 77, 'expected total and suite count')
    check(v['success'] is True, 'gate result success')
    for key in ['source_unchanged', 'environment_unchanged', 'source_head_unchanged', 'source_index_unchanged', 'tracked_worktree_clean_before', 'tracked_worktree_clean_after']:
        check(v[key] is True, 'gate stability ' + key)
    for key in ['source_mismatches', 'environment_mismatches', 'unexpected_native_mappings_after', 'sparse_source_omissions']:
        check(not v[key], 'gate discrepancy ' + key)

    runtime = json.loads(files['runtime/runtime.json'])
    check(files['runtime/runtime.json'] == files['final/runtime-receipt-frozen.json'], 'frozen/published runtime receipt bytes')
    check(sha(files['runtime/runtime.json']) == v['runtime_receipt_sha256'], 'gate-bound runtime receipt hash')
    archived_runtime_matches = []
    for name, data in files.items():
        if name.startswith('runtime/') and name in env:
            check(sha(data) == env[name], 'archived runtime/environment mapping: ' + name)
            archived_runtime_matches.append(name)
    for path, expected in v['additional_runtime_inputs'].items():
        check(runtime['additional_inputs'].get(path) == expected == env.get('additional/' + path), 'additional native/Node binding: ' + path)
    for run in runtime['runs']:
        name = 'runtime/logs/' + pathlib.PurePosixPath(run['log']).name
        check(sha(files[name]) == run['log_sha256'] and run['exit_code'] == 0, 'runtime restore log binding: ' + run['name'])
    check(runtime['workspace_lock_sha256'] == v['workspace_lock_sha256'] == source['pubspec.lock']['sha256'], 'lockfile receipt binding')
    check(files['development/native-preparation.log'].strip().endswith(b'in-memory FTS5 passed'), 'native smoke output retained')
    compiler = json.loads(files['runtime/compiler-supplement.json'])
    check(compiler == runtime['compiler_supplement'], 'compiler supplement receipt binding')
    for relative, expected in compiler['retained'].items():
        check(env.get('runtime/' + relative) == expected['sha256'], 'compiler supplement environment binding: ' + relative)

    python = json.loads(files['final/python/verification.json'])
    python_counts = []
    check(files['final/python/verification.json'] == published('python-verification.json'), 'published/archived Python receipt')
    for run in python['runs']:
        data = files['final/python/' + run['log']]
        match = re.findall(rb'Ran (\d+) tests? in [^\n]+\n\s*\nOK\s*$', data)
        check(len(match) == 1 and int(match[0]) == run['completed_tests'], 'Python raw-log count: ' + run['name'])
        check(sha(data) == run['log_sha256'] and run['exit_code'] == 0, 'Python raw-log hash: ' + run['name'])
        test_path = run['command'][1]
        source_bytes = git('show', SOURCE + ':' + test_path)
        published_bytes = git('show', PUBLISHED + ':' + test_path)
        check(sha(source_bytes) == run['test_source_sha256'] and source_bytes == published_bytes, 'Python test source binding: ' + run['name'])
        python_counts.append({'name': run['name'], 'completed_tests': int(match[0]), 'test_source_present_in_main_manifest': test_path in source, 'test_source_matches_separate_receipt_and_published_tree': sha(source_bytes) == run['test_source_sha256'] and source_bytes == published_bytes})
    check(sum(item['completed_tests'] for item in python_counts) == python['completed_tests'] == 56, 'Python total count')

    visual = json.loads(files['final/visual-review.json'])
    check(files['final/visual-review.json'] == published('visual-review.json'), 'published/archived visual review receipt')
    for shot in visual['screenshots']:
        data = files['final/' + shot['path']]
        check(len(data) == shot['bytes'] and sha(data) == shot['sha256'], 'screenshot bytes/hash: ' + shot['path'])
        check(data == published(shot['path']), 'published/archived screenshot bytes: ' + shot['path'])

    first = json.loads(files['first-rejected-run/cohort/verification.json'])
    check(first['success'] is False and first['passed'] == 1243 and first['failed'] == 1 and first['skipped'] == 0, 'failed first gate retained as failed')
    publication = json.loads(published('publication-scope.json'))
    changed = git('diff', '--name-only', SOURCE, PUBLISHED).decode().splitlines()
    check(set(changed) == set(publication['publication_paths']), 'exact publication change scope')
    check(all(path.startswith('docs/validation/document-review-notes-20261118/') for path in changed), 'only document-review evidence publication paths')
    check(not set(changed).intersection(source), 'publication does not alter bound source inputs')
    report = {
        'audited_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'reviewer': 'audit_saved_evidence',
        'published_commit': PUBLISHED,
        'qualified_source': SOURCE,
        'qualified_tree': v['source_tree'],
        'method': 'Independent standard-library archive hashing, frozen Git blob verification and raw JSON reporter recount; no repository validation parser imported and no Dart tests or GitHub Actions queried or executed.',
        'archive': {**index['archive'], 'members_verified': len(files), 'uncompressed_bytes': sum(map(len, files.values()))},
        'all_archive_members_match_index': not any('archive' in issue for issue in issues),
        'frozen_source_blobs_reverified': len(source),
        'source_before_after_equal': files['final/cohort/source-before.json'] == files['final/cohort/source-after.json'],
        'runtime_before_after_equal': files['final/cohort/environment-before.json'] == files['final/cohort/environment-after.json'],
        'runtime_inventory_entries': len(env),
        'archived_runtime_inputs_bound_to_inventory': archived_runtime_matches,
        'runtime_qualification_limit': 'Verified the saved evidence and its internal bindings, not the historical binaries on their former host. No fresh combined runtime restoration or test execution was performed by this audit.',
        'groups': group_results,
        'actual_dart_flutter_cases': total['passed'],
        'unique_suites': len(all_observed_suites),
        'failed': total['failed'],
        'skipped': total['skipped'],
        'separate_python_groups': python_counts,
        'separate_python_cases': sum(item['completed_tests'] for item in python_counts),
        'screenshots_bytes_reverified': len(visual['screenshots']),
        'failed_first_run_preserved': first['success'] is False,
        'publication_paths_verified': changed,
        'issues': issues,
        'passed': not issues,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'saved-evidence-audit.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: value for k, value in report.items() if k not in {'publication_paths_verified', 'archived_runtime_inputs_bound_to_inventory'}}, indent=2))
    raise SystemExit(bool(issues))


if __name__ == '__main__':
    main()
