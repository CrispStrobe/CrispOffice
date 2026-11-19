import collections
import datetime
import gzip
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path('/workspace/scratch/e9fb10bfe870/quds_office_suite')
BASE = ROOT / 'docs/validation/mail-archive-portability-20261119'
OUT = pathlib.Path('/workspace/scratch/e9fb10bfe870/mail-publication-audit.json')
SOURCE = '9bdef4895922ae74f6275e421af5665552d18b4e'
PUBLISHED = '82b20dc8b52d0b95efeff590c6023ed84704fa7a'

def sha(b):
    return hashlib.sha256(b).hexdigest()

def read(p):
    return json.loads(p.read_bytes())

def unpack(p):
    raw = p.read_bytes()
    return gzip.decompress(raw) if p.suffix == '.gz' else raw

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

started = datetime.datetime.now(datetime.timezone.utc).isoformat()
result = {'schema': 1, 'started_at_utc': started, 'audited_source': SOURCE,
          'publication': PUBLISHED, 'local_head': git('rev-parse', 'HEAD').decode().strip(),
          'method': 'Read-only independent retained-artifact hashing, raw Dart/Flutter reporter replay, exact Git blob source binding and publication diff inspection. No tests rerun in this audit.',
          'github_actions_used': False}
summary = read(BASE / 'receipt.json')
receipt = read(BASE / 'final/receipt.json')
assert sha((BASE / 'final/receipt.json').read_bytes()) == summary['final_run_sha256']
assert sha((BASE / 'independent-audit.json').read_bytes()) == summary['independent_audit_sha256']
assert summary['accepted_source_head'] == receipt['source_head'] == SOURCE
assert git('rev-parse', SOURCE + '^{tree}').decode().strip() == receipt['source_tree']
retained = []
for directory in [BASE / 'final', BASE / 'attempts/01-analysis']:
    retention = read(directory / 'retention.json')
    for entry in retention['retained']:
        data = (directory / entry['retained_as']).read_bytes()
        if entry['encoding'].startswith('gzip;'):
            data = gzip.decompress(data)
        assert len(data) == entry['bytes'], entry['path']
        assert sha(data) == entry['sha256'], entry['path']
    retained.append({'directory': str(directory.relative_to(BASE)), 'artifacts_verified': len(retention['retained'])})
result['retained_artifacts'] = retained

fingerprints = {}
for name in ['source', 'dependencies', 'runtime']:
    before_raw = unpack(BASE / 'final' / (name + '-before.json.gz'))
    after_raw = unpack(BASE / 'final' / (name + '-after.json.gz'))
    assert before_raw == after_raw
    before = json.loads(before_raw)
    fingerprints[name] = {'entries': len(before), 'before_after_identical': True, 'retained_uncompressed_sha256': sha(before_raw)}
source_manifest = json.loads(unpack(BASE / 'final/source-before.json.gz'))
process = subprocess.Popen(['git', 'cat-file', '--batch'], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
for path, entry in source_manifest.items():
    process.stdin.write((SOURCE + ':' + path + '\n').encode())
    process.stdin.flush()
    header = process.stdout.readline().decode().strip().split()
    assert len(header) == 3 and header[1] == 'blob', (path, header)
    data = process.stdout.read(int(header[2]))
    assert process.stdout.read(1) == b'\n'
    assert len(data) == entry['bytes'], path
    assert sha(data) == entry['sha256'], path
process.stdin.close()
assert process.wait() == 0
fingerprints['source']['all_entries_bound_to_accepted_git_blobs'] = True
result['fingerprints'] = fingerprints

cohorts = []
for cases_path in sorted((BASE / 'final').glob('*/test-cases.json.gz')):
    directory = cases_path.parent
    expected = read(directory / 'result.json')
    manifest = json.loads(unpack(cases_path))
    raw = unpack(directory / 'stdout.log.gz')
    err = unpack(directory / 'stderr.log.gz')
    assert sha(raw) == expected['stdout_sha256']
    assert sha(err) == expected['stderr_sha256']
    assert sha(cases_path.read_bytes()) == expected['test_cases_sha256']
    assert expected['exit_code'] == 0 and expected['accepted']
    events = [json.loads(line) for line in raw.decode().splitlines()]
    assert not [e for e in events if e['type'] == 'error']
    dones = [e for e in events if e['type'] == 'done']
    assert len(dones) == 1 and dones[0]['success']
    starts = {e['test']['id']: e['test'] for e in events if e['type'] == 'testStart'}
    suites = {e['suite']['id']: e['suite'] for e in events if e['type'] == 'suite'}
    finishes = [e for e in events if e['type'] == 'testDone']
    assert len(starts) == len(finishes)
    actual = []
    for event in finishes:
        if event['hidden']:
            assert event['result'] == 'success' and not event['skipped']
            continue
        test = starts[event['testID']]
        suite = suites[test['suiteID']]
        suite_path = suite['path'] if suite['path'].startswith('/') else expected['cwd'] + '/' + suite['path']
        actual.append({'file': suite_path.split('/quds_office_suite/', 1)[1], 'name': test['name'],
                       'platform': suite['platform'], 'result': event['result'], 'skipped': event['skipped']})
    canonical = lambda c: json.dumps(c, sort_keys=True)
    assert collections.Counter(map(canonical, actual)) == collections.Counter(map(canonical, manifest['cases']))
    assert set(c['file'] for c in actual) == set(expected['expected_test_files'])
    counts = {'passed': sum(c['result'] == 'success' and not c['skipped'] for c in actual),
              'failed': sum(c['result'] != 'success' for c in actual),
              'skipped': sum(c['skipped'] for c in actual)}
    assert counts == expected['test_counts']
    cohorts.append({'name': directory.name, 'test_counts': counts, 'test_files': len(expected['expected_test_files']),
                    'raw_logs_and_case_manifest_verified': True})
result['author_reporter_replay'] = cohorts
result['author_total'] = {key: sum(c['test_counts'][key] for c in cohorts) for key in ['passed', 'failed', 'skipped']}
assert result['author_total'] == summary['test_totals']
result['mail_ui_author_total'] = {key: sum(c['test_counts'][key] for c in cohorts if c['name'] in ['mail-ui-widgets', 'studio-mail-widgets']) for key in ['passed', 'failed', 'skipped']}
publication_paths = git('diff', '--name-only', SOURCE, PUBLISHED).decode().splitlines()
allowed = lambda p: p.startswith('docs/validation/mail-archive-portability-20261119/') or p in ['packages/quds_mail_store/README.md', 'packages/quds_mail_store/CHANGELOG.md', 'packages/quds_office_editor/CHANGELOG.md']
assert len(publication_paths) == 151 and all(map(allowed, publication_paths))
result['publication_delta'] = {'changed_paths': publication_paths, 'changed_path_count': len(publication_paths), 'product_or_test_changes': []}
current_delta = git('diff', '--name-only', SOURCE, result['local_head'], '--', 'packages/quds_mail_ui', 'packages/quds_office_editor/example/lib', 'packages/quds_office_editor/example/test').decode().splitlines()
mail_paths = [p for p in current_delta if p.startswith('packages/quds_mail_ui/') or pathlib.PurePosixPath(p).name.startswith(('studio_mail', 'studio_saved_mail'))]
result['current_mail_ui_related_differences_from_author_source'] = mail_paths
result['current_studio_all_differences_from_author_source'] = current_delta
result['limits'] = ['Author test execution is independently audited, not rerun by this worker; do not add author counts to our local test counts.', 'The author acceptance source is 9bdef489, predating incoming GUI and our macro control flow / manifest exact-byte fixes. Current GUI acceptance is separate.', 'Original dependency/runtime files are in a separate author environment and are not accessed; only their retained before/after manifests and artifact integrity are verified here.', 'No installed macOS application, live provider network, real CLD3 classifier, or GitHub Actions claim.']
result['status'] = 'passed'
result['finished_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
OUT.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: result[k] for k in ['status', 'started_at_utc', 'finished_at_utc', 'local_head', 'retained_artifacts', 'fingerprints', 'author_total', 'mail_ui_author_total', 'current_mail_ui_related_differences_from_author_source']}, indent=2))
print(str(OUT))
