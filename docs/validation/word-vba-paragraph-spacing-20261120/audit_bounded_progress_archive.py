"""Validate the historical bounded-progress checkpoint without counting it twice."""
import gzip
import hashlib
import json
from pathlib import Path
import tarfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def audit_bounded_progress_archive(a):
    folder = a.runtime / 'bounded-progress-checkpoint-files'
    receipt = json.loads((folder / 'bounded-progress-packaging.json').read_bytes())
    index_path = folder / 'bounded-progress-members.json'
    index = json.loads(index_path.read_bytes())
    archive_path = folder / receipt['archive']
    raw = archive_path.read_bytes()
    require(len(raw) == receipt['bytes'] and sha(raw) == receipt['sha256'], 'Bounded-progress archive identity')
    require(sha(index_path.read_bytes()) == receipt['member_index_sha256'], 'Bounded-progress index identity')
    require(len(index['files']) + 1 == receipt['member_count'] == 67, 'Bounded-progress complete member count')
    for key, value in index['metadata'].items():
        require(receipt[key] == value, 'Bounded-progress metadata equality')
    payloads, revisions = {}, []
    gate = a.runtime / 'word-spacing-batched-final-0201b549'
    with tarfile.open(archive_path, 'r:xz') as archive:
        members = archive.getmembers()
        require([m.name for m in members] == sorted(index['files']) + ['members.json'], 'Bounded-progress exact member order/set')
        for member in members:
            require(member.isfile() and member.mtime == member.uid == member.gid == 0 and member.uname == member.gname == '', 'Bounded-progress normalized member')
            data = archive.extractfile(member).read()
            payloads[member.name] = data
            if member.name == 'members.json':
                require(data == index_path.read_bytes(), 'Bounded-progress embedded index bytes')
                continue
            row = index['files'][member.name]
            require(len(data) == row['bytes'] and sha(data) == row['sha256'] and f'{member.mode:04o}' == row['mode'], 'Bounded-progress member content/mode identity')
            prefix, relative = member.name.split('/', 1)
            if prefix == 'accepted':
                live = gate / relative
            elif prefix == 'diagnostics':
                live = gate / member.name
            elif prefix == 'gate':
                live = gate / relative
            elif prefix == 'runners':
                live = a.runtime / relative
            elif prefix == 'independent-review':
                live = a.base / 'intake-review' / relative
            else:
                raise ValueError('Unknown bounded-progress mapping: ' + member.name)
            live_sha = sha(live.read_bytes())
            if live_sha != row['sha256']:
                require(prefix == 'independent-review' or member.name == 'runners/package_word_spacing_batched_regression.py', 'Frozen gate evidence/runtime changed after progress checkpoint')
                revisions.append({'member': member.name, 'archived_sha256': row['sha256'], 'current_sha256': live_sha, 'classification': 'Historical snapshot of an evolving review/packaging tool; not a frozen test input or final acceptance claim'})
    plan = json.loads(payloads['gate/plan.json'])
    observed_total = 0
    observed_files = set()
    reference = None
    accepted_snapshots = []
    for selected in receipt['accepted_batches']:
        name = selected['batch']
        bid = int(name.split('-')[1])
        command = json.loads(payloads[f'accepted/{name}/command.json'])
        files = [arg[len('test/'):] for arg in command['argv'] if arg.startswith('test/')]
        require(files == plan['files'][(bid - 1) * 10:bid * 10], 'Progress exact command selection against full immutable plan')
        observed = a.reporter(payloads[f'accepted/{name}/stdout.jsonl'], files)
        require(not observed_files & set(files), 'Progress snapshot case-file sets are disjoint')
        observed_files.update(files)
        require(observed['passed_cases'] == selected['passing_cases'] == sum(plan['expected_per_file_cases'][f] for f in files), 'Progress raw independently observed cases')
        require(observed['counts'] == {f: plan['expected_per_file_cases'][f] for f in files}, 'Progress raw per-file counts')
        before = json.loads(gzip.decompress(payloads[f'accepted/{name}/inputs-before.json.gz']))
        after = json.loads(gzip.decompress(payloads[f'accepted/{name}/inputs-after.json.gz']))
        require(before == after, 'Progress before/after snapshot equality')
        if reference is None:
            reference = before
        require(before == reference and len(before['entries']) == 1131 and len(before['runtime_inputs']) == 3489, 'Progress identical frozen source/runtime manifests')
        result = json.loads(payloads[f'accepted/{name}/execution.json'])
        require(result['exit_code'] == selected['exit_code'] == 0, 'Progress successful invocation receipt')
        expected_cases = [dict(c, batch_id=bid) for c in observed['records']]
        require(json.loads(gzip.decompress(payloads[f'accepted/{name}/cases.json.gz'])) == expected_cases, 'Progress exact reconstructed case records')
        accepted_snapshots.append({'batch_id': bid, 'passing_cases': observed['passed_cases'], 'suites': observed['suite_count']})
        observed_total += observed['passed_cases']
    require(observed_total == receipt['accepted_subset_cases'] == 1012, 'Progress qualified subset count')
    require(receipt['publication_acceptance'] is False and receipt['final_gate_complete'] is False and receipt['additional_regression_cases'] == receipt['failed_attempts_contribution'] == 0, 'Historical progress snapshot is not final acceptance or additional cases')
    return {'status': 'PASS', 'archive': str(archive_path), 'bytes': len(raw), 'sha256': sha(raw), 'member_count': 67,
            'index_sha256': sha(index_path.read_bytes()), 'metadata': index['metadata'],
            'archived_member_hashes_modes_indexes_and_metadata_verified': True,
            'accepted_batch_snapshots_independently_reconstructed': accepted_snapshots,
            'actual_frozen_batch_inputs_and_diagnostics_unchanged': True,
            'evolving_reviewer_tool_snapshots': revisions,
            'additional_word_regression_cases': 0}
