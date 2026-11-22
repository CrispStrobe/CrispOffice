#!/usr/bin/env python3
"""Re-analyze immutable qualification output without invoking any test runner.

JSON Lines is delimited by LF bytes. Python str.splitlines() additionally splits
Unicode NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR inside valid JSON strings.
This audit reads only captured evidence, never the mutable package source tree.
"""

import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import re


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
TEST_GATES = [
    'incoming_engine', 'incoming_editor', 'incoming_store',
    'studio_zotero', 'studio_mail',
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    # Escape Unicode separators in the attestation so every name is reviewable.
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + '\n').encode()


def write(path, value):
    path.write_bytes(encoded(value))


def verify_index(directory):
    verified = {}
    for line in (directory / 'SHA256SUMS.txt').read_text().split('\n'):
        if not line:
            continue
        expected, name = line.split('  ', 1)
        if Path(name).name != name or name in ('.', '..'):
            raise RuntimeError('Unsafe evidence checksum entry')
        actual = sha((directory / name).read_bytes())
        if actual != expected:
            raise RuntimeError(f'Evidence changed: {name}')
        verified[name] = actual
    return verified


def unpack(directory, metadata):
    packed = (directory / metadata['path']).read_bytes()
    data = gzip.decompress(packed)
    if sha(packed) != metadata['gzip_sha256'] or sha(data) != metadata['raw_sha256']:
        raise RuntimeError(f'Raw/compressed checksum mismatch: {metadata["path"]}')
    return data


def parse(raw, command, previous):
    starts, ends, suites, errors, done = {}, {}, {}, [], []
    duplicate_starts, duplicate_ends, progress, invalid = [], [], [], []
    raw_events = {}
    for number, physical_line in enumerate(raw.split(b'\n'), 1):
        if not physical_line.strip(b' \t\r'):
            continue
        line = physical_line
        prefix = b'Running build hooks...'
        prefix_count = 0
        while line.startswith(prefix):
            line = line[len(prefix):]
            prefix_count += 1
        try:
            event = json.loads(line.decode('utf-8'))
        except (UnicodeDecodeError, json.JSONDecodeError):
            invalid.append({'physical_line': number, 'raw_sha256': sha(physical_line)})
            continue
        if not isinstance(event, dict):
            invalid.append({'physical_line': number, 'raw_sha256': sha(physical_line)})
            continue
        kind = event.get('type')
        if prefix_count:
            if kind != 'start' or event.get('protocolVersion') != '0.1.1':
                raise RuntimeError('Unexpected build-hook prefix outside reporter start')
            progress.append({'physical_line': number, 'prefix': prefix.decode(),
                'repetitions': prefix_count, 'following_event': kind,
                'raw_line_sha256': sha(physical_line)})
        if kind == 'testStart':
            identifier = event['test']['id']
            if identifier in starts:
                duplicate_starts.append(identifier)
            starts[identifier] = event['test']
            raw_events[identifier] = {'physical_line': number,
                'raw_line_sha256': sha(physical_line)}
        elif kind == 'testDone':
            identifier = event['testID']
            if identifier in ends:
                duplicate_ends.append(identifier)
            ends[identifier] = event
        elif kind == 'suite':
            suite = event['suite']
            value = suite.get('path')
            if value:
                absolute = Path(value) if Path(value).is_absolute() else REPO / command['cwd'] / value
                suite['canonical_path'] = str(absolute.relative_to(REPO))
            suites[suite['id']] = suite
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            done.append(event)
    cases, excluded = [], []
    for identifier, test in starts.items():
        end = ends.get(identifier, {})
        name = test['name']
        reason = ('hidden' if end.get('hidden') else
            'suite_loader' if name.startswith('loading ') else
            'fixture_hook' if re.search(r'(?:^| )\((?:setUpAll|tearDownAll)\)$', name) else None)
        row = {'id': identifier, 'suite': suites.get(test.get('suiteID'), {}).get('canonical_path'),
            'name': name, 'result': end.get('result', 'incomplete'), 'skipped': bool(end.get('skipped', False))}
        (excluded if reason else cases).append(row)
    canonical = defaultdict(list)
    for row in cases:
        canonical[(row['suite'], row['name'])].append(row)
    counts, per_file = Counter(), defaultdict(Counter)
    for (file, name), attempts in canonical.items():
        status = ('incomplete' if any(row['result'] == 'incomplete' for row in attempts) else
            'failed' if any(row['result'] in ('failure', 'error') for row in attempts) else
            'skipped' if any(row['skipped'] for row in attempts) else 'passed')
        counts[status] += 1
        per_file[file][status] += 1
    old_ids = {row['id'] for row in previous['cases'] + previous['excluded_lifecycles']}
    recovered = []
    for row in cases:
        if row['id'] not in old_ids:
            recovered.append(row | raw_events[row['id']] | {
                'unicode_line_separators': sorted({f'U+{ord(char):04X}'
                    for char in row['name'] if char in '\u0085\u2028\u2029'}),
            })
    observed = {suite.get('canonical_path') for suite in suites.values()} - {None}
    expected = set(command['expected_suites'])
    result = {
        'suite_count': len(suites), 'expected_suite_count': len(expected),
        'missing_suites': sorted(expected - observed), 'unexpected_suites': sorted(observed - expected),
        'unique_started_cases': len(canonical),
        'unique_completed_cases': len(canonical) - counts['incomplete'],
        'passed_cases': counts['passed'], 'failed_cases': counts['failed'],
        'skipped_cases': counts['skipped'], 'incomplete_cases': counts['incomplete'],
        'started_lifecycles': len(starts), 'completed_lifecycles': len(ends),
        'excluded_loader_hook_lifecycles': len(excluded),
        'incomplete_lifecycle_ids': sorted(set(starts) - set(ends)),
        'orphan_completion_ids': sorted(set(ends) - set(starts)),
        'duplicate_start_ids': duplicate_starts, 'duplicate_completion_ids': duplicate_ends,
        'duplicate_case_names': sum(len(rows) > 1 for rows in canonical.values()),
        'per_file_counts': dict(per_file), 'errors': errors, 'done_events': done,
        'unrecognized_physical_lines': invalid, 'native_build_hook_progress': progress,
        'recovered_test_starts': recovered,
        'case_registry_sha256': sha(encoded(cases)),
        'complete_lifecycle_registry_sha256': sha(encoded({'starts': starts, 'ends': ends})),
    }
    result['accepted_reporter'] = (command['exit_code'] == 0 and len(done) == 1
        and done[0].get('success') is True and not errors and not invalid
        and not counts['failed'] and not counts['skipped'] and not counts['incomplete']
        and not result['missing_suites'] and not result['unexpected_suites']
        and not result['incomplete_lifecycle_ids'] and not result['orphan_completion_ids']
        and not duplicate_starts and not duplicate_ends and not result['duplicate_case_names'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-run', required=True)
    parser.add_argument('--output-id', required=True)
    args = parser.parse_args()
    if not all(re.fullmatch(r'[a-zA-Z0-9_-]+', name) for name in [args.source_run, args.output_id]):
        parser.error('Evidence names must be simple directory names')
    original, output = HERE / args.source_run, HERE / args.output_id
    output.mkdir()  # Never overwrite any prior attempt.
    script_before = sha(Path(__file__).read_bytes())
    verified_before = verify_index(original)
    old_summary = json.loads((original / 'summary.json').read_text())
    archived = json.loads((HERE / 'runner_versions/index.json').read_text())[args.source_run]
    archived_bytes = (HERE / 'runner_versions' / archived['path']).read_bytes()
    archive_matches = sha(archived_bytes) == archived['sha256'] == old_summary['runner_sha256_before'] == old_summary['runner_sha256_after']
    manifests = [json.loads(unpack(original, record)) for record in old_summary['input_manifests']]
    first = manifests[0]
    fingerprint = lambda value: ({path: (row.get('sha256'), row.get('symlink_target_sha256'), row.get('missing'))
        for path, row in value['entries'].items()}, value['generated'])
    captured_stable = all(fingerprint(value) == fingerprint(first) for value in manifests)
    frozen_match = (not old_summary['inputs_not_matching_source_commit']
        and all(row['matches_expected_head'] for row in first['entries'].values())
        and all(value['expected_head'] == old_summary['expected_source_head'] for value in manifests))
    gates = []
    for name in TEST_GATES:
        command = json.loads((original / (name + '-result.json')).read_text())
        raw = unpack(original, command['stdout'])
        unpack(original, command['stderr'])
        report = parse(raw, command, command['reporter'])
        write(output / (name + '-reanalysis.json'), report | {
            'original_result': f'../{args.source_run}/{name}-result.json',
            'raw_reporter_sha256': command['stdout']['raw_sha256'],
            'original_command': command['command'], 'original_cwd': command['cwd'],
            'original_exit_code': command['exit_code'],
        })
        gates.append({'name': name, **{key: report[key] for key in [
            'suite_count', 'passed_cases', 'failed_cases', 'skipped_cases', 'incomplete_cases',
            'started_lifecycles', 'completed_lifecycles', 'accepted_reporter', 'recovered_test_starts',
        ]}})
    retention = json.loads((original / 'retained-continuity.json').read_text())
    verified_after = verify_index(original)
    accepted = (archive_matches and captured_stable and frozen_match
        and old_summary['all_commands_exit_zero'] and old_summary['all_planned_gates_completed']
        and all(gate['accepted_reporter'] for gate in gates) and retention['accepted']
        and verified_before == verified_after and script_before == sha(Path(__file__).read_bytes()))
    fresh = sum(gate['passed_cases'] for gate in gates)
    summary = {
        'source_run': args.source_run, 'source_commit': old_summary['expected_source_head'],
        'evidence_only_reanalysis': True, 'test_processes_reexecuted': False,
        'mutable_package_source_read': False, 'original_summary_changed': False,
        'original_summary_accepted': old_summary['accepted'], 'accepted_reanalysis': accepted,
        'explanation': 'LF-only decoding recovers three valid JSON testStart events containing Unicode NEL/LINE SEPARATOR/PARAGRAPH SEPARATOR. Original str.splitlines() incorrectly treated those characters inside JSON strings as record separators. Normal build-hook progress preceding the store reporter start is recorded explicitly.',
        'archived_runner': archived, 'archived_runner_verified': archive_matches,
        'script_sha256_before': script_before, 'script_sha256_after': sha(Path(__file__).read_bytes()),
        'original_artifact_hashes_verified_before_and_after': verified_before,
        'captured_source_manifest_count': len(manifests), 'captured_source_input_count': len(first['entries']),
        'captured_inputs_stable': captured_stable, 'captured_inputs_match_frozen_source': frozen_match,
        'gate_summaries': gates, 'fresh_unique_passed_cases': fresh,
        'fresh_suite_count': sum(gate['suite_count'] for gate in gates),
        'retained_accepted_cases': retention['retained_passed_cases'],
        'retained_evidence': f'../{args.source_run}/retained-continuity.json',
        'combined_accepted_case_count': fresh + retention['retained_passed_cases'] if accepted else None,
        'scope': 'Retrospective acceptance of captured pinned VM/widget execution on the exact recorded source only. This does not qualify subsequent source edits or add JavaScript/browser, live-provider or installed-platform coverage.',
    }
    write(output / 'summary.json', summary)
    (output / 'SHA256SUMS.txt').write_text(''.join(
        f'{sha(path.read_bytes())}  {path.name}\n' for path in sorted(output.iterdir())
        if path.is_file() and path.name != 'SHA256SUMS.txt'))
    print(json.dumps({key: summary[key] for key in [
        'accepted_reanalysis', 'fresh_unique_passed_cases', 'retained_accepted_cases',
        'combined_accepted_case_count', 'fresh_suite_count',
    ]}, indent=2))
    return 0 if accepted else 1


if __name__ == '__main__':
    raise SystemExit(main())
