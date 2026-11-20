#!/usr/bin/env python3
"""Independently verify source applicability against Git and retained evidence.

Use --evidence-root for the original qualification directories, or --archive
for packaged evidence. With neither option, sibling evidence archives are read.
This is an evidence audit, not another test execution or a new runtime gate.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=here.parents[2])
    parser.add_argument('--audit', type=Path, default=here / 'source-applicability.json')
    parser.add_argument('--evidence-root', type=Path)
    parser.add_argument('--archive', type=Path, action='append', default=[])
    args = parser.parse_args()
    repo = args.repo.resolve()
    audit = json.loads(args.audit.read_text())
    require(audit['format_version'] == 1 and not audit['blockers']
            and audit['status'] == 'applicable_with_explicit_deltas', 'Audit is blocked')
    target = audit['evaluated_publication']
    tree = subprocess.check_output(['git', 'rev-parse', target + '^{tree}'],
                                   cwd=repo, text=True).strip()
    require(tree == audit['evaluated_tree'], 'Publication tree mismatch')
    archive_files = args.archive or ([] if args.evidence_root else sorted(here.glob('*.tar.*')))
    archived = []
    for path in archive_files:
        with tarfile.open(path, 'r:*') as archive:
            archived.extend((member.name, archive.extractfile(member).read())
                            for member in archive.getmembers() if member.isfile())

    def aliases(logical):
        special = {
            'integrated-acceptance/run_integrated_acceptance.py': 'runners/engine-original.py',
            'run_integrated_acceptance.py': 'runners/final-mail.py',
            'run_late_mail_acceptance.py': 'runners/late-mail.py',
        }
        if logical in special:
            return [logical, special[logical]]
        for old, new in [('integrated-acceptance/', 'engine/'),
                         ('final-mail-acceptance/', 'mail/'),
                         ('late-mail-acceptance/', 'late-mail/')]:
            if logical.startswith(old):
                return [logical, new + logical[len(old):]]
        return [logical]

    def evidence(logical, expected=None):
        found = []
        names = aliases(logical)
        if args.evidence_root:
            found.extend((args.evidence_root / name).read_bytes() for name in names
                         if (args.evidence_root / name).is_file())
        found.extend(data for name, data in archived
                     if any(name == wanted or name.endswith('/' + wanted) for wanted in names))
        if expected is not None:
            found = [data for data in found if sha(data) == expected]
        require(found and len({sha(data) for data in found}) == 1,
                'Missing, ambiguous or hash-mismatched evidence: ' + logical)
        return found[0]

    published_objects = {}
    for entry in subprocess.check_output(['git', 'ls-tree', '-r', '-z', target], cwd=repo).split(b'\0'):
        if entry:
            header, path = entry.split(b'\t', 1)
            mode, kind, oid = header.decode().split()
            if kind == 'blob':
                published_objects[path.decode()] = oid
    published_hashes = {}

    def published_hash(path):
        if path not in published_hashes:
            current = (repo / path).read_bytes()
            object_id = hashlib.sha1(b'blob ' + str(len(current)).encode() + b'\0' + current).hexdigest()
            require(object_id == published_objects[path],
                    'Working source differs from audited publication: ' + path)
            published_hashes[path] = sha(current)
        return published_hashes[path]

    expected_counts = {'engine_vm': 836, 'engine_node': 819, 'mail_ui': 200,
                       'host_existing': 505, 'transport_flags': 105, 'late_host': 176}
    snapshots, cases, receipts, records = {}, {}, {}, {}
    for record in audit['cohorts']:
        folder, cohort = record['id'].rsplit('/', 1)
        prefix = folder + '/' + cohort
        require(cohort in expected_counts and cohort not in records, 'Unexpected cohort')
        records[cohort] = record
        receipt = json.loads(evidence(record['evidence_receipt'], record['receipt_sha256']))
        receipts[cohort] = receipt
        before_bytes = evidence(record['source_manifest'], record['source_manifest_sha256'])
        before = json.loads(before_bytes)
        after = json.loads(evidence(prefix + '-sources-after.json'))
        require(before == after and sha(before_bytes) == receipt['source_manifest_sha256']
                and len(before) == receipt['source_count'] and receipt['accepted'] is True
                and receipt['exit_code'] == 0 and receipt['clean_terminal'] is True
                and receipt['source_stable'] is True and not receipt['changed_sources']
                and not receipt['errors'], 'Invalid strict receipt: ' + cohort)
        snapshots[cohort] = before
        raw = evidence(prefix + '.jsonl', receipt['log_sha256'])
        evidence(prefix + '.stderr', receipt['stderr_sha256'])
        events = []
        for line in raw.splitlines():
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if isinstance(row, dict) and 'type' in row:
                events.append(row)
        starts = [row['test'] for row in events if row['type'] == 'testStart']
        tests = {row['id']: row for row in starts}
        done = [row for row in events if row['type'] == 'testDone']
        ids = [row['testID'] for row in done]
        terminal = [row for row in events if row['type'] == 'done']
        require(len(starts) == len(tests) and tests and len(ids) == len(set(ids))
                and set(ids) == set(tests) and len(terminal) == 1
                and terminal[0]['success'] is True and events[-1] == terminal[0]
                and not any(row['type'] == 'error' for row in events),
                'Unclean raw test events: ' + cohort)
        substantive = []
        for result in done:
            name = tests[result['testID']]['name']
            if (result.get('hidden') or name.startswith('loading ')
                    or name.endswith('(setUpAll)') or name.endswith('(tearDownAll)')):
                continue
            require(result['result'] == 'success' and not result.get('skipped'),
                    'Unsuccessful case: ' + cohort + ': ' + name)
            substantive.append({'name': name, 'outcome': 'success'})
        require(substantive == json.loads(evidence(prefix + '-cases.json'))
                and len(substantive) == expected_counts[cohort] == record['accepted_executions']
                and receipt['counts'] == {'success': expected_counts[cohort]},
                'Case recount mismatch: ' + cohort)
        cases[cohort] = Counter(row['name'] for row in substantive)
        actual_changes, compared = {}, 0
        for path, recorded_hash in before.items():
            if path in published_objects:
                compared += 1
                current_hash = published_hash(path)
                if current_hash != recorded_hash:
                    actual_changes[path] = (recorded_hash, current_hash)
            elif not Path(path).is_absolute():
                require(path.startswith('.dart_tool/'), 'Missing published input: ' + path)
                if (repo / path).is_file():
                    require(sha((repo / path).read_bytes()) == recorded_hash,
                            'Available generated runtime input changed: ' + path)
        reported = record['source_comparison']
        require(compared == reported['published_repository_inputs']
                and compared - len(actual_changes) == reported['unchanged_published_inputs']
                and actual_changes == {row['path']: (row['recorded_sha256'], row['published_sha256'])
                                       for row in reported['published_changes']},
                'Source delta inventory mismatch: ' + cohort)
        runner_paths = [path for path in before if Path(path).name in
                        ('run_integrated_acceptance.py', 'run_late_mail_acceptance.py')]
        require(len(runner_paths) == 1, 'Missing unique validation runner: ' + cohort)
        runner = runner_paths[0]
        logical_runner = ('integrated-acceptance/run_integrated_acceptance.py'
                          if cohort.startswith('engine_') else Path(runner).name)
        evidence(logical_runner, before[runner])
    require(set(records) == set(expected_counts), 'Missing accepted cohort')
    require(not (cases['engine_node'] - cases['engine_vm'])
            and cases['engine_vm'] - cases['engine_node']
            == Counter(receipts['engine_node']['excluded_filesystem_cases'])
            and len(receipts['engine_node']['excluded_filesystem_cases']) == 17,
            'Engine VM/Node filesystem distinction changed')

    metadata = audit['metadata_exception']['path']
    old_metadata = subprocess.check_output(
        ['git', 'show', receipts['engine_vm']['head'] + ':' + metadata], cwd=repo)
    current_metadata = (repo / metadata).read_bytes()
    require(current_metadata.replace(b'  drift: 2.35.4\n', b'', 1) == old_metadata,
            'Example metadata change is not exactly the declared Drift addition')
    provider = 'packages/quds_mail_transport/lib/src/cloud/provider.dart'
    workspace = 'packages/quds_office_editor/example/test/studio_mail_workspace_test.dart'
    backend = 'packages/quds_office_editor/example/test/studio_mail_credential_backend_switch_test.dart'
    allowed = {'engine_vm': {metadata}, 'engine_node': {metadata},
               'host_existing': {provider, workspace, backend},
               'mail_ui': set(), 'transport_flags': set(), 'late_host': set()}
    for cohort, record in records.items():
        require({row['path'] for row in record['source_comparison']['published_changes']}
                == allowed[cohort], 'Unexpected relevant source delta: ' + cohort)
    for path, focus in [(provider, 'transport_flags'), (workspace, 'late_host'), (backend, 'late_host')]:
        require(snapshots[focus][path] == published_hash(path),
                'Later focused coverage does not bind publication: ' + path)
    resolution = audit['resolved_initial_publication_difference']
    initial = subprocess.check_output(
        ['git', 'show', resolution['earlier_publication'] + ':' + workspace], cwd=repo)
    require(resolution['resolved'] and resolution['exact_test_only_cleanup']
            and sha(initial) == resolution['earlier_published_sha256']
            and initial.replace(b'      await lateBody.close();\n', b'') == (repo / workspace).read_bytes()
            and resolution['current_published_sha256'] == snapshots['late_host'][workspace],
            'Earlier publication mismatch was not resolved by the declared cleanup')
    print(json.dumps({'accepted': True, 'publication': target, 'tree': tree,
                      'unique_published_source_files_verified': len(published_hashes),
                      'cohort_counts': expected_counts,
                      'unexpected_source_deltas': [], 'earlier_publication_mismatch_resolved': True,
                      'note': 'Retained evidence and current working-source audit. External SDK/pub inputs are bound by captured manifests, not requalified on this machine.'}, indent=2))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print('Source applicability verification failed: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
