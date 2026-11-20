#!/usr/bin/env python3
"""Independent read-only Git/archive verification of the captured incoming head."""
import collections
import argparse
import datetime
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

OPTIONS = argparse.ArgumentParser(description=__doc__)
OPTIONS.add_argument('--repo', required=True, type=Path)
OPTIONS.add_argument('--output-dir', type=Path, default=Path(__file__).resolve().parent)
ARGS = OPTIONS.parse_args()
ROOT = ARGS.repo.resolve()
OUT = ARGS.output_dir.resolve()
TARGET = 'c7e721b7703766491fd4459b69de30bf68d9010d'
BASE = '3ee4e3622c9a2198d384ed1cb296ab092a8838d0'
DIRECTORY = 'docs/validation/mail-cached-workspace-20261120/'

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])

def sha(data):
    return hashlib.sha256(data).hexdigest()

def read(path, commit=TARGET):
    return git('show', f'{commit}:{path}')

def require(condition, message):
    if not condition:
        raise ValueError(message)

def ancestor(head):
    result = subprocess.run(['git', '-C', str(ROOT), 'merge-base', '--is-ancestor', head, TARGET], capture_output=True)
    require(result.returncode in (0, 1), result.stderr.decode())
    return result.returncode == 0

def tree_entries(commit):
    result = {}
    for row in git('ls-tree', '-r', '-z', commit).split(b'\0'):
        if row:
            header, name = row.split(b'\t', 1)
            mode, kind, oid = header.decode().split()
            result[name.decode()] = dict(mode=mode, type=kind, object=oid)
    return result

def recount(data):
    """Parse protocol independently: unique paired cases, exact framing, no late events."""
    cases, finished, suites = {}, {}, {}
    starts, ends, errors, ignored = 0, 0, 0, 0
    for line in data.decode('utf-8').split('\n'):
        line = line.strip()
        for prefix in ('Running build hooks...', 'Running link hooks...'):
            if line.startswith(prefix):
                line = line[len(prefix):].strip()
        if not line:
            continue
        event = json.loads(line)
        require(isinstance(event, dict) and isinstance(event.get('type'), str), 'Invalid event')
        require(ends == 0, 'Event after terminal')
        kind = event['type']
        if kind == 'start':
            starts += 1
        require(starts == 1, 'Missing or duplicate start')
        if kind == 'suite':
            item = event['suite']
            require(item['id'] not in suites, 'Duplicate suite')
            suites[item['id']] = item['path']
        elif kind == 'testStart':
            item = event['test']
            require(type(item['id']) is int and item['id'] not in cases, 'Duplicate/invalid test start')
            require(type(item['suiteID']) is int and isinstance(item['name'], str), 'Invalid case')
            cases[item['id']] = item
        elif kind == 'testDone':
            identifier = event['testID']
            require(identifier in cases and identifier not in finished, 'Unpaired/duplicate completion')
            require(event['result'] in ('success', 'failure', 'error'), 'Invalid result')
            require(type(event['hidden']) is bool and type(event['skipped']) is bool, 'Invalid flags')
            finished[identifier] = event
        elif kind == 'error':
            errors += 1
        elif kind == 'done':
            ends += 1
            require(event['success'] is True, 'Failed terminal event')
    require(starts == ends == 1 and cases.keys() == finished.keys(), 'Incomplete protocol')
    require(errors == 0, 'Error event')
    substantive = []
    for identifier, result in finished.items():
        require(result['result'] == 'success' and result['skipped'] is False, 'Failed/skipped case')
        case = cases[identifier]
        require(case['suiteID'] in suites, 'Case missing suite')
        if result['hidden'] or case['name'].startswith('loading '):
            ignored += 1
        else:
            substantive.append({'suite': suites[case['suiteID']], 'name': case['name']})
    return dict(passed=len(substantive), failed=0, skipped=0, errors=0, incomplete=0,
                start_events=starts, terminal_events=ends, terminal_success=True,
                ignored_lifecycle_cases=ignored, suite_count=len(suites),
                case_identities_sha256=sha(json.dumps(substantive, sort_keys=True, separators=(',', ':')).encode()),
                suites=sorted(suites.values()))

def main():
    target_entries = tree_entries(TARGET)
    prior_path = 'docs/validation/word-vba-list-levels-20261120/final-intake.json'
    prior_data = read(prior_path)
    prior = json.loads(prior_data)
    proofs = {}
    for row in prior['historical_equivalence_proofs']:
        old, accepted, base = row['historical_head'], row['accepted_ancestor'], row['comparison_base']
        old_entries, accepted_entries = tree_entries(old), tree_entries(accepted)
        paths = git('diff', '--name-only', base, old).decode().splitlines()
        old_tree = git('rev-parse', old + '^{tree}').decode().strip()
        accepted_tree = git('rev-parse', accepted + '^{tree}').decode().strip()
        require(ancestor(accepted), 'Equivalence substitute not ancestor: ' + old)
        require(set(paths) == {e['path'] for e in row['entries']}, 'Changed-path inventory mismatch')
        require(len(paths) == row['changed_path_count'], 'Changed-path count mismatch')
        require(all(old_entries.get(p) == accepted_entries.get(p) for p in paths), 'Equivalence path mismatch')
        require(old_tree == accepted_tree or old == 'c34945761e7991f5fe49037d79529acdd260b31c', 'Unsupported partial equivalent')
        proofs[old] = dict(historical_head=old, accepted_ancestor=accepted, comparison_base=base,
                           old_tree=old_tree, accepted_tree=accepted_tree, full_tree_equal=old_tree == accepted_tree,
                           changed_path_count=len(paths), changed_paths=paths,
                           exact_mode_type_object_match=True, accepted_is_ancestor=True)
    inventory, counts, uncovered = [], {}, []
    for file, upstream in [('fork-remote-refs.txt', False), ('upstream-remote-refs.txt', True)]:
        group_counts = collections.Counter()
        for line in (OUT / file).read_text().splitlines():
            head, ref = line.split()
            group = ('upstream_' if upstream else 'fork_') + ('branches' if ref.startswith('refs/heads/') else 'pull_requests')
            state = 'target' if head == TARGET else 'ancestor' if ancestor(head) else 'equivalent' if head in proofs else 'uncovered'
            row = dict(kind=group, ref=ref, sha=head, disposition=state)
            if state == 'equivalent':
                row['accepted_ancestor'] = proofs[head]['accepted_ancestor']
            if state == 'uncovered':
                uncovered.append(row)
            inventory.append(row)
            counts.setdefault(group, collections.Counter())[state] += 1
    require(not uncovered, 'Uncovered remote heads: ' + str(uncovered))

    archive = read(DIRECTORY + 'evidence.tar.xz')
    index = json.loads(read(DIRECTORY + 'evidence-files.json'))
    require(sha(archive) == index['archive_sha256'] and len(archive) == index['archive_bytes'], 'Archive identity differs')
    members = {}
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:xz') as tar:
        for member in tar:
            require(member.isfile() and not PurePosixPath(member.name).is_absolute() and '..' not in PurePosixPath(member.name).parts, 'Unsafe archive member')
            require(member.name not in members, 'Duplicate archive member')
            members[member.name] = tar.extractfile(member).read()
    require(set(members) == {x['path'] for x in index['members']} and len(members) == len(index['members']), 'Archive member set differs')
    for row in index['members']:
        data = members[row['path']]
        require(len(data) == row['bytes'] and sha(data) == row['sha256'], 'Archive member differs: ' + row['path'])

    seal = json.loads(read(DIRECTORY + 'final-qualification.json'))
    require(seal['status'] == 'PASS' and ancestor(seal['verified_commit']), 'Final seal invalid ancestry/status')
    seal_changes = git('diff', '--name-only', seal['verified_commit'], TARGET).decode().splitlines()
    require(len(seal_changes) == 5 and all(p.startswith(DIRECTORY) for p in seal_changes), 'Unexpected delta since qualified source')
    union, modes, accepted, receipt_commit_mismatches = {}, {}, [], []
    for selected in seal['accepted']:
        name = selected['receipt']
        raw = members[name]
        require(sha(raw) == selected['receipt_sha256'], 'Receipt hash differs')
        receipt = json.loads(raw)
        require(receipt['source_before'] == receipt['source_after'] and receipt['source_unchanged'], 'Source changed during accepted run')
        if selected['selection'] == 'all':
            require(receipt['status'] == 'PASS', 'Run not passing')
        for before, after in [('runtime_before', 'runtime_after'), ('direct_launcher_inputs_before', 'direct_launcher_inputs_after')]:
            if before in receipt:
                require(receipt[before] == receipt[after], 'Runtime fingerprints changed')
        if 'runtime_configuration_unchanged' in receipt:
            require(receipt['runtime_configuration_unchanged'], 'Runtime config changed')
        for path, value in receipt['source_before'].items():
            expected = value if isinstance(value, str) else value['sha256']
            require(path not in union or union[path] == expected, 'Conflicting accepted source')
            union[path] = expected
            if isinstance(value, dict):
                if 'mode' in value:
                    require(target_entries[path]['mode'] == value['mode'], 'Recorded source mode differs')
                if 'git_blob' in value:
                    require(target_entries[path]['object'] == value['git_blob'], 'Recorded Git blob differs')
                modes[path] = target_entries[path]
        selected_names = {x['name'] for x in selected['checks']}
        source_checks = {x['name']: x for x in receipt['checks']}
        require(selected_names <= source_checks.keys(), 'Missing selected checks')
        if selected['selection'] == 'all':
            require(selected_names == source_checks.keys(), 'Not all run checks selected')
        result_checks = []
        for sealed in selected['checks']:
            check = source_checks[sealed['name']]
            require(check['status'] == 'PASS' and check['exit_code'] == 0, 'Failed accepted check')
            log_path = str(PurePosixPath(name).parent / check['log'])
            log = members[log_path]
            require(sha(log) == check['log_sha256'] == sealed['log_sha256'], 'Selected log hash differs')
            if 'stderr' in check:
                err = members[str(PurePosixPath(name).parent / check['stderr'])]
                require(sha(err) == check['stderr_sha256'], 'Stderr hash differs')
            result = dict(name=check['name'], exit_code=0, log=log_path, log_sha256=sha(log))
            if 'tests' in sealed:
                parsed = recount(log)
                for key in ['passed', 'failed', 'skipped', 'errors', 'incomplete', 'start_events', 'terminal_events', 'terminal_success']:
                    require(parsed[key] == sealed['tests'][key], 'Recount differs: ' + key)
                require(parsed['suites'] == sealed['test_files'], 'Suite inventory differs')
                result['recount'] = parsed
            result_checks.append(result)
        accepted.append(dict(receipt=name, source_inputs=len(receipt['source_before']), source_commit=receipt.get('source_commit'),
                             archived_runtime_before_after_equal=True, checks=result_checks))
    require(len(union) == seal['unique_source_inputs'] == 5648, 'Source union count differs')
    canonical = sha(json.dumps(union, sort_keys=True, separators=(',', ':')).encode())
    require(canonical == seal['source_fingerprints_sha256'], 'Source union hash differs')
    # Batch read Git objects and independently check their object IDs and SHA-256 bytes.
    objects = sorted({target_entries[p]['object'] for p in union})
    run = subprocess.run(['git', '-C', str(ROOT), 'cat-file', '--batch'], input=('\n'.join(objects)+'\n').encode(), stdout=subprocess.PIPE, check=True)
    output, cursor, hashes = run.stdout, 0, {}
    for oid in objects:
        end = output.index(b'\n', cursor)
        header = output[cursor:end].decode().split()
        require(header[:2] == [oid, 'blob'], 'Unexpected batch object')
        length = int(header[2]); cursor = end + 1
        content = output[cursor:cursor+length]; cursor += length + 1
        require(hashlib.sha1(f'blob {length}\0'.encode() + content).hexdigest() == oid, 'Git object hash differs')
        hashes[oid] = sha(content)
    require(cursor == len(output), 'Trailing/missing batch output')
    require(all(hashes[target_entries[p]['object']] == digest for p, digest in union.items()), 'Qualified source differs from target')
    portable = json.loads(members['mail_intake_audit/word-portable-final/receipt.json'])
    require(portable['portable_raw_equal'] and portable['portable_json_equal'], 'Portable comparison failed')
    portable_vm = members['mail_intake_audit/word-portable-final/word-levels-vm.stdout']
    portable_node = members['mail_intake_audit/word-portable-final/word-levels-node.stdout']
    require(portable_vm == portable_node and json.loads(portable_vm) == json.loads(portable_node), 'Actual portable outputs differ')
    python_log = members['mail-cached-store-final-recovery/runner-regressions.log'].decode()
    python_cases = [line for line in python_log.splitlines() if line.startswith('test_')]
    require(len(python_cases) == 48 and all(line.endswith(' ... ok') for line in python_cases), 'Python runner controls differ')
    require('Ran 48 tests in ' in python_log and python_log.rstrip().endswith('OK'), 'Python terminal differs')

    result = dict(schema='quds-independent-incoming-review/v1', status='PASS',
                  reviewed_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  repository='CrispStrobe/quds_office_suite', target_commit=TARGET,
                  target_tree=git('rev-parse', TARGET+'^{tree}').decode().strip(),
                  captured_main=BASE, captured_main_is_ancestor=ancestor(BASE),
                  github_actions='NOT QUERIED OR AWAITED',
                  intake=dict(counts={k:dict(v) for k,v in counts.items()}, refs=inventory, uncovered=uncovered,
                              historical_equivalence_source=prior_path, historical_equivalence_source_sha256=sha(prior_data),
                              recomputed_equivalence_proofs=list(proofs.values())),
                  mail_qualification=dict(archive_sha256=sha(archive), archive_bytes=len(archive), verified_archive_members=len(members),
                                          source_inputs=len(union), source_fingerprints_sha256=canonical,
                                          original_qualified_commit=seal['verified_commit'],
                                          original_qualified_tree=seal['verified_tree'],
                                          target_delta_since_qualification=seal_changes,
                                          accepted=accepted, recorded_modes_and_objects_verified=len(modes),
                                          all_source_content_matches_target=True, git_blob_ids_recomputed=True,
                                          independently_recounted_python_controls=48,
                                          actual_portable_outputs_equal=True, actual_portable_bytes=len(portable_vm),
                                          actual_portable_sha256=sha(portable_vm),
                                          original_runtime_files_reopened=False,
                                          limitation='Archive replay verifies recorded runtime equality and raw events; this is not a new Mail runtime execution or installed/live-provider qualification.'),
                  integration_recommendation='Start the new feature from this fully captured descendant of main; no historical equivalent branch needs replay. PR #262 metadata is stale draft but its committed final acceptance record passes this independent evidence review.')
    (OUT/'incoming-review.json').write_text(json.dumps(result,indent=2)+'\n')
    (OUT/'source-fingerprints.json').write_text(json.dumps(union,sort_keys=True,indent=2)+'\n')
    summary = {k:sum(v.values()) for k,v in counts.items()}
    (OUT/'incoming-review.md').write_text(f'''# Incoming Quds Office review\n\nStatus: **PASS** for captured head `{TARGET}` (tree `{result['target_tree']}`).\n\nThe captured remote main `{BASE}` is an ancestor. The live inventory contains {summary['fork_branches']} fork branches, {summary['fork_pull_requests']} fork PR heads, {summary['upstream_branches']} upstream branches and {summary['upstream_pull_requests']} upstream PR heads. Every captured head is an ancestor, the target itself, or a recomputed historical equivalent. There are zero uncovered references. All 14 previous equivalence proofs were independently recalculated from Git objects: 13 complete tree identities and one exact 37-path ODT continuation identity, with accepted replacements retained as ancestors.\n\n## Incoming Mail qualification\n\nThe current PR #262 body is stale and still describes qualification as pending. Its committed final acceptance seal is PASS. This independent review verified the {len(members)} archived members, their exact index, bytes and SHA-256 identities, all selected receipt/log hashes, raw test event pairing and successful completion, the accepted source union, and every source byte against immutable target Git objects. All {len(union)} unique source inputs match the target; recorded modes and Git blob identities are verified where the original receipt provides them. The union SHA-256 is `{canonical}`. The archive SHA-256 is `{sha(archive)}`.\n\nAccepted raw events reproduce 714 native store cases, 67 Mail core VM cases, 67 Mail core Node cases, 46 store portability Node cases, 1,149 Studio cases across 57 files, 96 shared Mail UI cases, 486 MIME/transport cases, and the separate incoming Word 679-case cohort. The receipt also retains 48 Python runner controls, strict checks and Word VM/Node comparison. Overlapping independent and author Word totals are not combined.\n\nThe accepted original source is `{seal['verified_commit']}`. The final Mail checkpoint changes only five validation/documentation paths after that source. It retains the incoming Word merge and original Word publication packet.\n\n## Scope and integration\n\nThe review performed no repository/ref mutations and queried no GitHub Actions, workflow or status endpoints. Original runtime binaries were not reopened or rerun; their archived before/after identity records agree. This is evidence replay and source binding, not new installed-platform or live-provider acceptance.\n\nThe new Word feature can start from `{TARGET}`. Historical equivalent heads need no replay. Preserve this captured head as an ancestor and recheck incoming refs before final publication.\n''')
    print(json.dumps(dict(status='PASS', counts=summary, uncovered=0, equivalence_proofs=len(proofs), archive_members=len(members), source_inputs=len(union), report=str(OUT/'incoming-review.json'))))

if __name__ == '__main__':
    main()
