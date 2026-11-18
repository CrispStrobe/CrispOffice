"""Verify the saved local results and bind their inputs to the product commit.

This verifies retained evidence; it does not execute tests or contact GitHub.
Run from any directory inside a checkout containing the qualified commit.
"""

import gzip
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PRODUCT = 'b2bcfc23e692476d16d9a7a534ea95a93ae94cd3'
COHORTS = [
    ('engine', 22, 445),
    ('editor', 20, 278),
    ('studio', 1, 18),
    ('incoming/engine', 2, 39),
    ('incoming/editor', 2, 31),
    ('incoming/studio', 1, 8),
    ('incoming/spelling/engine', 19, 526),
    ('incoming/spelling/editor', 7, 64),
]


def read(path):
    raw = path.read_bytes()
    return json.loads(gzip.decompress(raw) if path.suffix == '.gz' else raw)


def record(path):
    raw = path.read_bytes()
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def write(name, data):
    (HERE / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


tree = {}
for row in subprocess.check_output(
    ['git', 'ls-tree', '-r', '-z', PRODUCT], cwd=REPO
).split(b'\0'):
    if not row:
        continue
    metadata, name = row.split(b'\t', 1)
    tree[name.decode()] = metadata.split()[2].decode()

selected = set()
bound_inputs = {}
results = []
bindings = []
for directory, suites, cases in COHORTS:
    folder = HERE / directory
    summary = read(folder / 'summary.json')
    assert summary['status'] == 'passed', directory
    assert summary.get('actual_process_exit_code', summary.get('exit_code')) == 0
    assert summary['suite_count'] == suites
    assert summary['substantive_test_count'] == cases
    assert summary['substantive_results'] == {'success': cases}
    assert summary.get('substantive_skips', summary.get('skipped', 0)) == 0
    assert all(summary['guards'].values()), directory
    files = summary.get('selected_test_files', summary.get('selected_files'))
    assert files and len(files) == suites, directory
    assert not selected.intersection(files), 'Overlapping cohort selection'
    selected.update(files)
    suffix = '.json.gz' if (folder / 'source-before.json.gz').exists() else '.json'
    before_file = folder / ('source-before' + suffix)
    after_file = folder / ('source-after' + suffix)
    before, after = read(before_file), read(after_file)
    assert before == after, directory
    for path, value in before.items():
        assert tree.get(path) == value['git_blob_sha1'], (directory, path)
        if path in bound_inputs:
            assert bound_inputs[path] == value, path
        bound_inputs[path] = value
    bindings.append({
        'cohort': directory,
        'input_count': len(before),
        'before': record(before_file),
        'after': record(after_file),
        'all_inputs_match_product_commit': True,
    })
    results.append({
        'cohort': directory, 'suites': suites, 'passed': cases,
        'skipped': 0, 'errors': 0, 'actual_process_exit': 0,
        'summary': record(folder / 'summary.json'),
    })

checks = read(HERE / 'checks/summary.json')
assert checks['all_passed'] and checks['source_unchanged']
assert all(row['exit_code'] == 0 for row in checks['checks'])
for path, value in checks['source'].items():
    assert tree.get(path) == value['git_blob_sha1'], path

panel = read(HERE / 'incoming/spelling/panel/summary.json')
assert panel['status'] == 'passed' and panel['actual_process_exit_code'] == 0
assert panel['case_count'] == 48 and all(panel['guards'].values())
for path, value in read(HERE / 'incoming/spelling/panel/source-before.json').items():
    assert tree.get(path) == value['git_blob_sha1'], path

write('source-commit-binding.json', {
    'qualified_product': PRODUCT,
    'all_cohorts_bound': True,
    'cohorts': bindings,
    'unique_source_inputs': len(bound_inputs),
    'selected_test_files': sorted(selected),
    'selected_suites_are_disjoint': True,
    'strict_checks_match_product': True,
    'portable_panel_matches_product': True,
})
write('status.json', {
    'status': 'passed', 'qualified_product': PRODUCT,
    'passed': sum(row['passed'] for row in results),
    'suites': sum(row['suites'] for row in results),
    'skipped': 0, 'errors': 0,
    'zotero': {'passed': 741, 'suites': 43, 'new_cases': 21},
    'incoming_comparison_review': {'passed': 78, 'suites': 5},
    'incoming_spelling': {'passed': 590, 'suites': 26},
    'separate_dart_vm_panel': {'passed': 48, 'included_in_test_total': False},
    'cohorts': results, 'strict_target_count': len(checks['targets']),
    'all_source_bindings_passed': True,
    'limits': 'Controlled transports and native-channel responses; no fresh live Zotero account, installed OS dictionary, full application build, native OS or Word/LibreOffice acceptance.',
})
index = {
    str(path.relative_to(HERE)): record(path)
    for path in sorted(HERE.rglob('*'))
    if path.is_file() and path != HERE / 'index.json'
}
write('index.json', {'files': index, 'file_count': len(index)})
print(json.dumps({'passed': 1409, 'suites': len(selected),
                  'unique_bound_inputs': len(bound_inputs), 'indexed_files': len(index)}))
