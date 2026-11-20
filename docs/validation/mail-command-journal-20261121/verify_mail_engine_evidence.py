#!/usr/bin/env python3
"""Independently verify retained execution events, hashes and case accounting."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    root = Path(__file__).resolve().parent
    index = json.loads((root / 'mail-engine-evidence-index.json').read_text())
    archive = root / index['archive']
    assert sha(archive.read_bytes()) == index['archive_sha256']
    with tarfile.open(archive, 'r:xz') as tar:
        members = tar.getmembers()
        assert all(m.isfile() and not m.name.startswith('/') and
                   '..' not in Path(m.name).parts for m in members)
        data = {m.name: tar.extractfile(m).read() for m in members}
    assert len(data) == len(members) == len(index['members'])
    assert set(data) == {m['path'] for m in index['members']}
    for member in index['members']:
        value = data[member['path']]
        assert len(value) == member['bytes']
        assert sha(value) == member['sha256']

    def read(name):
        return json.loads(data[name])

    def cohort(prefix, name):
        base = prefix + '/' + name
        receipt = read(base + '-receipt.json')
        assert receipt['accepted'] and receipt['exit_code'] == 0
        assert receipt['clean_terminal'] and receipt['source_stable']
        assert not receipt['errors'] and not receipt['changed_sources']
        assert data[base + '-sources-before.json'] == data[base + '-sources-after.json']
        assert sha(data[base + '-sources-before.json']) == receipt['source_manifest_sha256']
        assert sha(data[base + '.jsonl']) == receipt['log_sha256']
        assert sha(data[base + '.stderr']) == receipt['stderr_sha256']
        events = []
        for line in data[base + '.jsonl'].decode().splitlines():
            try:
                row = json.loads(line)
                if isinstance(row, dict) and 'type' in row:
                    events.append(row)
            except ValueError:
                pass
        starts = {row['test']['id']: row['test'] for row in events if row['type'] == 'testStart'}
        ends = [row for row in events if row['type'] == 'testDone']
        terminals = [row for row in events if row['type'] == 'done']
        assert len(terminals) == 1 and terminals[0]['success'] is True
        assert not [row for row in events if row['type'] == 'error']
        assert len(ends) == len({row['testID'] for row in ends})
        assert set(starts) == {row['testID'] for row in ends}
        cases = []
        for row in ends:
            title = starts[row['testID']]['name']
            if row.get('hidden') or title.startswith('loading ') or title.endswith('(setUpAll)') or title.endswith('(tearDownAll)'):
                continue
            outcome = 'skipped' if row.get('skipped') else row['result']
            cases.append({'name': title, 'outcome': outcome})
        assert cases == read(base + '-cases.json')
        counts = dict(Counter(case['outcome'] for case in cases))
        assert counts == receipt['counts']
        assert set(counts) == {'success'}
        return cases, receipt

    results = {}
    case_sets = {}
    for prefix, name in [
        ('engine', 'engine_vm'), ('engine', 'engine_node'),
        ('mail', 'mail_ui'), ('mail', 'host_existing'),
        ('mail', 'transport_flags'), ('late-mail/attempt-2', 'late_host'),
    ]:
        cases, receipt = cohort(prefix, name)
        results[name] = len(cases)
        case_sets[name] = {case['name'] for case in cases}
    exclusions = set(read('engine/engine-node-filesystem-cases.json')['cases'])
    assert len(exclusions) == 17
    assert exclusions <= case_sets['engine_vm']
    assert case_sets['engine_vm'] - exclusions == case_sets['engine_node']
    assert not exclusions & case_sets['engine_node']
    interrupted = read('late-mail/attempt-1/late_host-interrupted-receipt.json')
    assert interrupted['accepted'] is False
    for item in json.loads((root / 'visual-review.json').read_text())['images']:
        value = (root / item['path']).read_bytes()
        assert sha(value) == item['sha256'] and len(value) == item['bytes']
    print(json.dumps({'accepted': True, 'cohorts': results,
                      'exact_portable_engine_case_match': True,
                      'vm_only_cases': len(exclusions),
                      'visuals_verified': 9,
                      'note': 'Cohort counts are not added: platform reruns and later host subsets overlap.'}, indent=2))


if __name__ == '__main__':
    main()
