"""Verify the two remote progress-checkpoint archives independently."""
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


def load(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)


def audit_checkpoint_archives(a):
    directory = a.runtime / 'progress-checkpoint-files'
    results = {}
    for stem, expected_count in [('interrupted-regression-evidence', 17), ('late-intake-evidence', 249)]:
        receipt = load(directory / (stem + '-packaging.json'))
        index_path = directory / (stem + '-members.json')
        index = load(index_path)
        archive_path = directory / receipt['archive']
        data = archive_path.read_bytes()
        require(len(data) == receipt['bytes'] and sha(data) == receipt['sha256'], 'Checkpoint archive size/digest')
        require(sha(index_path.read_bytes()) == receipt['member_index_sha256'], 'Checkpoint member index digest')
        require(len(index['files']) + 1 == expected_count == receipt['member_count'], 'Checkpoint archive complete count')
        for key, value in index['metadata'].items():
            require(receipt[key] == value, 'Checkpoint embedded metadata/receipt equality')
        with tarfile.open(archive_path, 'r:xz') as archive:
            members = archive.getmembers()
            require(len(members) == expected_count and len({m.name for m in members}) == expected_count, 'Unique checkpoint members')
            require([m.name for m in members] == sorted(index['files']) + ['members.json'], 'Declared checkpoint member order')
            require(archive.extractfile('members.json').read() == index_path.read_bytes(), 'Exact embedded/external checkpoint index')
            for member in members:
                path = Path(member.name)
                require(not path.is_absolute() and '..' not in path.parts, 'Safe checkpoint member path')
                require(member.isfile() and member.mtime == member.uid == member.gid == 0 and member.uname == member.gname == '', 'Normalized regular checkpoint member')
                payload = archive.extractfile(member).read()
                if member.name == 'members.json':
                    continue
                entry = index['files'][member.name]
                require(len(payload) == entry['bytes'] and sha(payload) == entry['sha256'] and f'{member.mode:04o}' == entry['mode'], 'Indexed checkpoint member identity')
                if stem == 'interrupted-regression-evidence':
                    original = a.runtime / member.name
                elif member.name.startswith('candidate/'):
                    original = a.base / 'macos-build-correction-20261120' / member.name[len('candidate/'):]
                else:
                    require(member.name.startswith('independent-review/'), 'Known checkpoint late-input mapping')
                    original = a.base / 'intake-review' / member.name[len('independent-review/'):]
                require(original.read_bytes() == payload, 'Checkpoint archived/live input identity: ' + member.name)
                require(('0755' if original.stat().st_mode & 0o111 else '0644') == entry['mode'], 'Checkpoint live permission class')
        if stem == 'interrupted-regression-evidence':
            require(receipt['publication_acceptance'] is False and receipt['regression_total_contribution'] == 0, 'Interrupted attempt exclusion')
            raw_dir = a.runtime / 'word-spacing-final-0201b549'
            events = [json.loads(row) for row in (raw_dir / 'stdout.jsonl').read_bytes().split(b'\n') if row]
            require(sum(e['type'] == 'testDone' and not e['hidden'] for e in events) == receipt['completed_visible_cases'] == 2679, 'Interrupted partial count')
            require(sum(e['type'] == 'suite' for e in events) == receipt['observed_suites'] == 64, 'Interrupted suite count')
            require(not any(e['type'] in ['done', 'error'] for e in events), 'Interrupted lack of terminal result/error')
            observation_dir = a.runtime / 'word-spacing-interrupted-observation'
            observation = load(observation_dir / 'observation.json')
            before = load(raw_dir / 'inputs-before.json.gz')
            observed = load(observation_dir / 'inputs-at-observation.json.gz')
            require(before == observed, 'Post-interruption observation unchanged but separate from completion')
            require(observation['accepted'] is False and observation['automatic_after_snapshot_present'] is False and observation['execution_receipt_present'] is False, 'Observation cannot assert acceptance')
            require(observation['raw_evidence_hashes'] == {name: row['sha256'] for name, row in a.files(raw_dir).items()}, 'Observation binds every raw interrupted file')
        else:
            require(receipt['word_regression_total_contribution'] == 0 and receipt['actual_macos_build'] is False and receipt['actual_bash3_execution'] is False, 'Late correction scope limits')
            candidate = a.base / 'macos-build-correction-20261120'
            require(sha((candidate / 'build_macos_app.corrected.sh').read_bytes()) == receipt['candidate_sha256'], 'Reviewed exact late correction candidate')
            checks = load(candidate / 'checks-bash5/summary.json')
            rows = checks['checks_manifest']
            require(len(rows) == checks['checks'] == receipt['producer_isolated_checks'] == 61, 'Producer isolated check count')
            require(checks['failures'] == [] and checks['real_macos_build_or_sign'] is False and checks['host'] == 'Linux', 'Producer local-check qualification boundary')
            for row in rows:
                require(row['accepted'] is True and row['actual_exit'] == row['expected_exit'], 'Producer raw return code expectation')
                for stream in ['stdout', 'stderr']:
                    raw = (candidate / 'checks-bash5' / row[stream]).read_bytes()
                    require(sha(raw) == row[stream + '_sha256'], 'Producer isolated raw output identity')
                if row['expected_diagnostic']:
                    require(row['expected_diagnostic'] in (candidate / 'checks-bash5' / row['stderr']).read_text(), 'Producer expected diagnostic')
            independent = load(a.base / 'intake-review/late-macos-independent/review.json')
            require(independent['passed'] == len(independent['cases']) == receipt['independent_expectations'] == 36 and independent['failed'] == 0, 'Independent separate late expectation count')
            require(all(c['pass'] and c['expected_exit'] == c['actual_exit'] for c in independent['cases']), 'Independent late raw outcomes')
            late = load(a.base / 'intake-review/late-intake-review.json')
            require(late['correction_review']['status'] == 'ACCEPTED_FOR_INTEGRATION' and late['correction_review']['candidate_sha256'] == receipt['candidate_sha256'], 'Late correction review binds exact candidate')
            require(all(f['status'] == 'RESOLVED_IN_REVIEWED_SCRATCH_CORRECTION' for f in late['findings']), 'Initial late findings have reviewed correction')
            require(not any('/bash-3.2/' in p or p.endswith('/bash-3.2.tar.gz') for p in index['files']), 'Recreatable interpreter setup excluded as declared')
        results[stem] = {'status': 'PASS', 'archive': str(archive_path), 'bytes': len(data),
                         'sha256': sha(data), 'member_count': expected_count,
                         'complete_members_modes_indexes_metadata_and_live_inputs_verified': True,
                         'index_sha256': sha(index_path.read_bytes()), 'metadata': index['metadata']}
    return {'status': 'PASS', 'archives': results,
            'no_actual_macos_or_bash3_execution_claimed': True,
            'additional_word_regression_cases': 0}
