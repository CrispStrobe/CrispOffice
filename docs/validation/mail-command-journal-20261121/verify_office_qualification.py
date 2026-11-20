#!/usr/bin/env python3
"""Verify the archived Office evidence without extracting or executing it."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify_run(files, prefix, expected_receipt, expected_counts):
    receipt = json.loads(files[prefix + '-receipt.json'])
    assert receipt == expected_receipt
    assert receipt['accepted'] and receipt['exit_code'] == 0
    assert receipt['source_stable'] and not receipt['changed_sources']
    assert receipt['clean_terminal'] and not receipt['errors']
    before_bytes = files[prefix + '-sources-before.json']
    before = json.loads(before_bytes)
    assert before == json.loads(files[prefix + '-sources-after.json'])
    assert len(before) == receipt['source_count']
    assert sha(before_bytes) == receipt['source_manifest_sha256']
    assert sha(files[prefix + '.jsonl']) == receipt['log_sha256']
    assert sha(files[prefix + '.stderr']) == receipt['stderr_sha256']
    events = [json.loads(line) for line in files[prefix + '.jsonl'].decode().splitlines()
              if line.startswith('{')]
    starts = {row['test']['id']: row['test']['name']
              for row in events if row['type'] == 'testStart'}
    completions = [row for row in events if row['type'] == 'testDone']
    assert len(completions) == len(starts)
    assert {row['testID'] for row in completions} == set(starts)
    counted = Counter()
    for row in completions:
        name = starts[row['testID']]
        if row.get('hidden') or name.startswith('loading ') or name.endswith('(setUpAll)') or name.endswith('(tearDownAll)'):
            continue
        counted['skipped' if row.get('skipped') else row['result']] += 1
    assert dict(counted) == receipt['counts'] == expected_counts
    terminal = [row for row in events if row['type'] == 'done']
    assert len(terminal) == 1 and terminal[0]['success']
    assert not [row for row in events if row['type'] == 'error']
    return before


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path)
    args = parser.parse_args()
    folder = Path(__file__).resolve().parent
    qualification = json.loads((folder / 'office-qualification.json').read_text())
    archive = folder / qualification['archive']['path']
    assert sha(archive.read_bytes()) == qualification['archive']['sha256']
    assert archive.stat().st_size == qualification['archive']['bytes']
    with tarfile.open(archive, 'r:*') as bundle:
        members = bundle.getmembers()
        assert len(members) == len({member.name for member in members})
        assert all(member.isfile() for member in members)
        assert all(not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
                   for member in members)
        files = {member.name: bundle.extractfile(member).read() for member in members}
    manifest = json.loads(files['archive-manifest.json'])
    assert set(files) == set(manifest) | {'archive-manifest.json'}
    for name, row in manifest.items():
        assert len(files[name]) == row['bytes'], name
        assert sha(files[name]) == row['sha256'], name

    prefix = 'accepted/goldens/goldens'
    receipt = json.loads(files[prefix + '-receipt.json'])
    assert receipt == qualification['final_golden_receipt']
    assert receipt['accepted'] and receipt['exit_code'] == 0
    assert receipt['source_stable'] and not receipt['changed_sources']
    assert receipt['clean_terminal'] and not receipt['errors']
    assert '--update-goldens' not in receipt['command']
    before_bytes = files[prefix + '-sources-before.json']
    before = json.loads(before_bytes)
    after = json.loads(files[prefix + '-sources-after.json'])
    assert before == after
    assert len(before) == receipt['source_count']
    assert sha(before_bytes) == receipt['source_manifest_sha256']
    assert sha(files[prefix + '.jsonl']) == receipt['log_sha256']
    assert sha(files[prefix + '.stderr']) == receipt['stderr_sha256']
    events = [json.loads(line) for line in files[prefix + '.jsonl'].decode().splitlines()
              if line.startswith('{')]
    starts = {row['test']['id']: row['test']['name']
              for row in events if row['type'] == 'testStart'}
    completions = [row for row in events if row['type'] == 'testDone']
    assert len(completions) == len(starts)
    assert {row['testID'] for row in completions} == set(starts)
    counted = Counter()
    for row in completions:
        name = starts[row['testID']]
        if row.get('hidden') or name.startswith('loading ') or name.endswith('(setUpAll)') or name.endswith('(tearDownAll)'):
            continue
        counted['skipped' if row.get('skipped') else row['result']] += 1
    assert dict(counted) == receipt['counts'] == {'success': 17}
    terminal = [row for row in events if row['type'] == 'done']
    assert len(terminal) == 1 and terminal[0]['success']
    assert not [row for row in events if row['type'] == 'error']
    repeated = json.loads(files['reviewed_scenes/repeated-render-hashes.json'])
    assert len(repeated) == 26
    for scene, renders in repeated.items():
        assert len({row['sha256'] for row in renders}) == 1, scene
        first = renders[0]
        assert sha(files['reviewed_scenes/' + first['file']]) == first['sha256']

    editor = verify_run(files, 'accepted/editor/editor', qualification['editor_receipt'],
                        {'success': 578, 'skipped': 8})
    supplement = verify_run(files, 'accepted/reference_supplement/editor',
                            qualification['editor_reference_supplement_receipt'], {'success': 20})
    bridge = qualification['editor_current_source_bridge']
    cloud = verify_run(files, bridge['archive_prefix'], bridge['receipt'], {'success': 105})
    assert json.loads(files['accepted/editor/source-authored-skips.json']) == qualification['editor_source_authored_skips']
    assert len(qualification['editor_source_authored_skips']) == 8
    assert {row['reason'] for row in qualification['editor_source_authored_skips']} == {'no paragraphs to edit'}
    main_cases = json.loads(files['accepted/editor/editor-cases.json'])
    extra_cases = json.loads(files['accepted/reference_supplement/editor-cases.json'])
    assert not any('docs/validation/' in row['name'] for row in main_cases)
    assert len(extra_cases) == 20
    assert all('docs/validation/' in row['name'] and row['outcome'] == 'success' for row in extra_cases)
    inputs = json.loads(files['accepted/reference_supplement/fixture-inputs.json'])
    assert len(inputs) == 20 and len({row['path'] for row in inputs}) == 20
    for row in inputs:
        data = files['accepted/reference_supplement/inputs/' + row['path']]
        assert len(data) == row['bytes']
        assert sha(data) == row['sha256'] == supplement[row['path']]
        assert hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == row['git_blob']
    assert len(bridge['changed_paths']) == 1
    change = bridge['changed_paths'][0]
    assert change['path'] == 'packages/quds_mail_transport/lib/src/cloud/provider.dart'
    assert editor[change['path']] == change['qualified_old_sha256']
    assert cloud[change['path']] == change['current_sha256']
    assert sha(files['accepted/cloud_continuity/provider.dart']) == change['current_sha256']

    current = {'checked': 0, 'distinct_paths': 0, 'changed': [], 'qualified_bridges': []}
    if args.repo:
        distinct = set()
        for cohort, sources in [('goldens', before), ('editor', editor),
                                ('reference_supplement', supplement), ('cloud_bridge', cloud)]:
            for name, expected in sources.items():
                # External SDK/pub sources are sealed in the receipt. Comparing
                # this checkout does not claim a new SDK installation matches.
                if Path(name).is_absolute():
                    continue
                path = args.repo / name
                current['checked'] += 1
                distinct.add(name)
                actual = sha(path.read_bytes()) if path.is_file() else None
                if actual != expected:
                    if cohort == 'editor' and name == change['path'] and actual == change['current_sha256']:
                        current['qualified_bridges'].append(name)
                    else:
                        current['changed'].append({'cohort': cohort, 'path': name})
        current['distinct_paths'] = len(distinct)
        assert not current['changed'], current
    print(json.dumps({'verified_archive_entries': len(files),
                      'golden_tests_passed': counted['success'],
                      'reviewed_scene_count': len(repeated),
                      'editor_unique_passed': 598, 'editor_source_authored_skips': 8,
                      'later_transport_bridge_passed': 105,
                      'current_repository_sources': current}, indent=2))


if __name__ == '__main__':
    main()
