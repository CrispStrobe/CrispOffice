#!/usr/bin/env python3
"""Verify archived journal receipts and their current core/store package sources.

This audits retained evidence; it does not run Dart tests or qualify a new runtime.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile
from urllib.parse import urlparse


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=here.parents[2])
    parser.add_argument('--archive', type=Path,
                        default=here / 'journal-evidence.tar.xz')
    parser.add_argument('--index', type=Path,
                        default=here / 'journal-evidence-index.json')
    args = parser.parse_args()
    repo = args.repo.resolve()
    index = json.loads(args.index.read_text())
    archive_bytes = args.archive.read_bytes()
    require(index['format_version'] == 1, 'Unsupported index version')
    require(len(archive_bytes) == index['archive_bytes'], 'Archive size mismatch')
    require(sha256(archive_bytes) == index['archive_sha256'], 'Archive hash mismatch')
    entries = index['members']
    require(len({row['path'] for row in entries}) == len(entries),
            'Duplicate index member')
    expected = {row['path']: row for row in entries}
    contents = {}
    with tarfile.open(args.archive, 'r:xz') as archive:
        members = archive.getmembers()
        require([m.name for m in members] == sorted(expected),
                'Archive members differ from sorted index')
        for member in members:
            path = PurePosixPath(member.name)
            require(member.isfile() and not path.is_absolute()
                    and '..' not in path.parts
                    and path.parts[0] == 'journal-acceptance',
                    f'Invalid archive member: {member.name}')
            require(member.uid == member.gid == member.mtime == 0
                    and member.mode == 0o644
                    and member.uname == member.gname == '',
                    f'Non-deterministic metadata: {member.name}')
            row = expected[member.name]
            require(member.size == row['bytes'], f'Size mismatch: {member.name}')
            data = archive.extractfile(member).read()
            require(sha256(data) == row['sha256'], f'Hash mismatch: {member.name}')
            contents[str(path.relative_to('journal-acceptance'))] = data
    require(sum(len(data) for data in contents.values()) == index['source_bytes'],
            'Uncompressed size mismatch')

    def read_json(name):
        return json.loads(contents[name])

    summary = read_json('summary.json')
    package_sources = read_json('package-final-source-manifest.json')
    require(len(package_sources) == 115, 'Expected the final 115 package files')
    require(sha256(contents['package-final-source-manifest.json'])
            == summary['final_package_source_manifest_sha256'],
            'Final package manifest hash mismatch')
    for name, expected_hash in package_sources.items():
        path = PurePosixPath(name)
        require(not path.is_absolute() and '..' not in path.parts
                and name.startswith(('packages/quds_mail_core/',
                                     'packages/quds_mail_store/')),
                f'Invalid package source path: {name}')
        current = repo / name
        require(current.is_file() and sha256(current.read_bytes()) == expected_hash,
                f'Current package source differs: {name}')

    def check_manifest(prefix, receipt):
        name = prefix + '-sources-before.json'
        before = read_json(name)
        require(before == read_json(prefix + '-sources-after.json'),
                f'Changed before/after source manifest: {prefix}')
        require(sha256(contents[name]) == receipt['source_manifest_sha256']
                and len(before) == receipt['source_count'],
                f'Invalid source manifest binding: {prefix}')
        require(receipt['source_stable'] is True and not receipt['changed_sources'],
                f'Unstable source receipt: {prefix}')
        for path, digest in before.items():
            if path in package_sources:
                require(digest == package_sources[path],
                        f'Receipt does not bind the final package source: {path}')
            if Path(path).name.startswith('run_journal_'):
                require(sha256(contents['runners/' + Path(path).name]) == digest,
                        f'Runner hash mismatch: {path}')

    expected_totals = {'core_vm': 235, 'core_node': 235, 'store_vm': 749}
    records = {row['cohort']: row for row in summary['cohorts']}
    require(set(records) == set(expected_totals), 'Unexpected accepted cohorts')
    cases_by_cohort = {}
    for cohort, expected_total in expected_totals.items():
        receipt_name = cohort + '-receipt.json'
        receipt = read_json(receipt_name)
        record = records[cohort]
        require(receipt['accepted'] is True and receipt['exit_code'] == 0
                and receipt['clean_terminal'] is True and not receipt['errors'],
                f'Unaccepted receipt: {cohort}')
        require(sha256(contents[receipt_name]) == record['receipt_sha256'],
                f'Summary receipt binding differs: {cohort}')
        check_manifest(cohort, receipt)
        require(sha256(contents[cohort + '.jsonl']) == receipt['log_sha256']
                and sha256(contents[cohort + '.stderr']) == receipt['stderr_sha256'],
                f'Log binding differs: {cohort}')
        events = [json.loads(line) for line in contents[cohort + '.jsonl'].splitlines()]
        require(all(isinstance(row, dict) and 'type' in row for row in events),
                f'Malformed test events: {cohort}')
        terminal = [row for row in events if row['type'] == 'done']
        require(len(terminal) == 1 and terminal[0]['success'] is True
                and events[-1] == terminal[0]
                and not any(row['type'] == 'error' for row in events),
                f'Unclean terminal event: {cohort}')
        starts = [row['test'] for row in events if row['type'] == 'testStart']
        tests = {row['id']: row for row in starts}
        completions = [row for row in events if row['type'] == 'testDone']
        completed_ids = [row['testID'] for row in completions]
        require(len(starts) == len(tests) and bool(tests)
                and len(completed_ids) == len(set(completed_ids))
                and set(completed_ids) == set(tests),
                f'Missing or duplicate test events: {cohort}')
        suites = {row['suite']['id']: row['suite']['path']
                  for row in events if row['type'] == 'suite'}
        cases, identities, by_file = [], Counter(), Counter()
        for result in completions:
            test = tests[result['testID']]
            name = test['name']
            if (result.get('hidden') or name.startswith('loading ')
                    or name.endswith('(setUpAll)') or name.endswith('(tearDownAll)')):
                continue
            require(result['result'] == 'success' and not result.get('skipped'),
                    f'Unsuccessful test: {cohort}: {name}')
            source = Path(urlparse(test['url']).path if test.get('url')
                          else suites[test['suiteID']]).name
            by_file[source] += 1
            identities[(source, name)] += 1
            cases.append({'name': name, 'outcome': 'success'})
        require(cases == read_json(cohort + '-cases.json')
                and len(cases) == expected_total == record['passed']
                and receipt['counts'] == {'success': expected_total}
                and dict(by_file) == record['by_test_file']
                and record['failures'] == record['skips'] == 0,
                f'Test recount disagrees with receipts: {cohort}')
        cases_by_cohort[cohort] = identities
    require(cases_by_cohort['core_vm'] == cases_by_cohort['core_node'],
            'Core VM/Node case sets differ')
    require(summary['accepted_test_executions'] == sum(expected_totals.values()) == 1219,
            'Accepted total mismatch')

    static = read_json('static-checks-receipt.json')
    require(static['accepted'] is True, 'Static checks are not accepted')
    check_manifest('static-checks', static)
    require([row['name'] for row in static['checks']]
            == ['analysis', 'format', 'whitespace'], 'Missing strict static checks')
    for check in static['checks']:
        require(check['exit_code'] == 0
                and sha256(contents[check['log']]) == check['log_sha256'],
                f'Static check failed or log changed: {check["name"]}')
    print(json.dumps({
        'accepted': True, 'archive_members': len(contents),
        'archive_sha256': index['archive_sha256'],
        'accepted_test_executions': 1219, 'cohorts': expected_totals,
        'core_vm_node_same_case_set': True, 'strict_static_checks': 3,
        'current_package_files_verified': len(package_sources),
        'diagnostic_files_retained': sum(k.startswith('diagnostics/') for k in contents),
        'prior_accepted_files_retained': sum(k.startswith('prior-accepted/') for k in contents),
        'note': 'Retained evidence audit, not a new test execution.',
    }, indent=2))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError, tarfile.TarError) as error:
        print(f'Journal evidence verification failed: {error}', file=sys.stderr)
        raise SystemExit(1)
