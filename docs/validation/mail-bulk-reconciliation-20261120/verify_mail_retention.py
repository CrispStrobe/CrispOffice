#!/usr/bin/env python3
"""Verify retained Mail tests plus the formatter/analyzer corrective checkpoint."""
import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys


def read_json(path):
    return json.loads(Path(path).read_text())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def case_key(row):
    return (row['file'], row['name'], row['occurrence'], row['platform'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--final', type=Path, required=True)
    parser.add_argument('--nonmail-fixture-audit', type=Path)
    args = parser.parse_args()
    baseline, final = args.baseline.resolve(), args.final.resolve()
    first = read_json(baseline / 'qualification.json')
    last = read_json(final / 'qualification.json')
    original_cases = read_json(baseline / 'test-cases.json')
    final_cases = read_json(final / 'test-cases.json')
    expected_format = read_json(baseline / 'formatter-expectation.json')
    changed_path = expected_format['path']

    for label, directory, receipt in [('baseline', baseline, first), ('final', final, last)]:
        for seal in ['source', 'dependencies', 'runtime']:
            require(receipt[seal + '_unchanged'], f'{label}: {seal} changed during its gate.')
            require(read_json(directory / (seal + '-before.json')) ==
                    read_json(directory / (seal + '-after.json')),
                    f'{label}: saved {seal} manifests differ.')
        require(receipt['source_head'] == receipt['source_head_after'], f'{label}: HEAD moved.')
        require(digest(directory / 'qualification-runner.py') == receipt['runner_sha256'],
                f'{label}: executed runner copy differs.')
        for command in receipt['commands']:
            for kind in ['stdout', 'stderr']:
                require(digest(directory / command[kind]) == command[kind + '_sha256'],
                        f'{label}: raw {kind} changed for {command["name"]}.')
        require(all(row['accepted'] for row in receipt['test_results'].values()),
                f'{label}: a selected test group was not accepted.')

    first_commands = {row['name']: row for row in first['commands']}
    failed_commands = {name for name, row in first_commands.items() if row['exit_code']}
    recovered = {'format', 'ui-analysis', 'studio-analysis', 'editor-font-analysis'}
    require(failed_commands == recovered, 'Unexpected original failure outside documented corrective scope.')
    for name in recovered - {'format'}:
        error = (baseline / first_commands[name]['stderr']).read_text()
        require('Flutter failed to list directory' in error and '/flutter/dev' in error
                and 'PathNotFoundException' in error,
                'The original analyzer failure was not the recorded SDK-directory startup diagnostic.')
    for name in ['core-analysis', 'transport-analysis']:
        require(first_commands[name]['exit_code'] == 0, 'A retained strict analyzer did not pass.')
    for line in first['git_status_after'].splitlines():
        require(re.fullmatch(r'\?\? packages/quds_office_engine/arguments-cli-[A-Za-z0-9_-]+/', line),
                'Unexpected original worktree status outside the concurrent Word CLI temporary fixture.')

    require(last['status'] == 'passed' and not last['git_status_after'],
            'The corrective checkpoint is not passing and clean.')
    require(set(last['selected_gates']) == recovered | {'studio-tests'},
            'Corrective gate selection differs from the agreed focused scope.')
    require(last['studio_test_selection'] == ['test/studio_mail_cached_mail_test.dart'],
            'The corrective suite is not exactly the cached-host suite.')
    require(first['changed_dart_files'] == last['changed_dart_files'],
            'The final format gate did not check the same complete changed-file set.')
    require(first['format_base'] == last['format_base'], 'Format bases differ.')

    old_sources = read_json(baseline / 'source-after.json')
    new_sources = read_json(final / 'source-after.json')
    require(set(old_sources) == set(new_sources), 'Source files were added or removed between receipts.')
    source_changes = [path for path in old_sources if old_sources[path] != new_sources[path]]
    fixture_audit = read_json(args.nonmail_fixture_audit) if args.nonmail_fixture_audit else None
    expected_source_changes = {changed_path}
    if fixture_audit:
        fixture = fixture_audit['fixture']
        require(fixture == 'packages/quds_office_engine/test/word_contained_text_wrap_test.dart',
                'Unexpected unrelated fixture exception.')
        require(fixture_audit['status'] == 'passed' and fixture_audit.get('enumeration_review_complete'),
                'The unrelated fixture reference review is incomplete.')
        require(fixture_audit['repository_head_at_audit'] == last['source_head'],
                'The unrelated fixture audit does not bind the final checkpoint.')
        require(fixture_audit['original_sha256'] == old_sources[fixture]['sha256'] and
                fixture_audit['corrected_sha256'] == new_sources[fixture]['sha256'],
                'The unrelated fixture bytes differ from the reviewed change.')
        require(set(fixture_audit['mail_suite_entries']) == {row['file'] for row in original_cases},
                'The unrelated fixture audit omits a Mail suite.')
        require(not fixture_audit['target_in_selected_mail_suites'] and
                not fixture_audit['target_in_reachable_dart_sources'] and
                not fixture_audit['target_name_references'] and
                not fixture_audit['engine_test_directory_references'],
                'The Word-only fixture is consumed by a retained Mail suite.')
        for path, checksum in fixture_audit['repo_sources_reachable_by_import_export_part'].items():
            require(path in new_sources and new_sources[path]['sha256'] == checksum,
                    f'An audited reachable Mail source differs: {path}')
        expected_source_changes.add(fixture)
    require(set(source_changes) == expected_source_changes,
            'Source changes exceed the formatted cached-host test and separately audited unconsumed Word fixture.')
    require(expected_format['source_head'] == first['source_head'], 'Formatter proof has a different source head.')
    require(expected_format['input_sha256'] == old_sources[changed_path]['sha256'],
            'Formatter proof does not bind the original test bytes.')
    require(expected_format['expected_formatted_sha256'] == new_sources[changed_path]['sha256'],
            'Corrected test bytes differ from the previously recorded canonical formatter output.')
    require(expected_format['diff_sha256'] == digest(baseline / 'formatter-diff.patch'),
            'The captured formatter diff changed.')

    require(read_json(baseline / 'dependencies-after.json') == read_json(final / 'dependencies-after.json'),
            'Configured dependency contents changed between the receipts.')
    require(read_json(baseline / 'hosted-lock-verification.json') ==
            read_json(final / 'hosted-lock-verification.json'), 'Hosted lock/archive pins changed.')
    require(read_json(baseline / 'resolved-packages.json') == read_json(final / 'resolved-packages.json'),
            'Canonical package roots changed.')
    old_runtime = read_json(baseline / 'runtime-after.json')
    new_runtime = read_json(final / 'runtime-after.json')
    require(set(old_runtime) == set(new_runtime), 'Runtime inputs were added or removed.')
    runtime_changes = [path for path in old_runtime if old_runtime[path] != new_runtime[path]]
    require(len(runtime_changes) == 1, 'Expected only the documented qualification-driver change.')
    runner_key = runtime_changes[0]
    require(old_runtime[runner_key]['sha256'] == first['runner_sha256'] and
            new_runtime[runner_key]['sha256'] == last['runner_sha256'],
            'A compiler/runtime input changed rather than only the qualification driver.')
    for field in ['dart_version', 'node_version', 'flutter_runtime']:
        require(first[field] == last[field], f'Runtime identity differs: {field}.')

    for label, cases, receipt in [('original', original_cases, first), ('corrective', final_cases, last)]:
        require(all(row['result'] == 'success' and not row['skipped'] for row in cases),
                f'{label}: failed/skipped cases cannot be retained.')
        require(len(cases) == receipt['passed'], f'{label}: saved case count differs from its receipt.')
        require(len({case_key(row) for row in cases}) == len(cases), f'{label}: duplicate case identities.')
    replaced = [row for row in original_cases if row['file'] == changed_path]
    retained = [row for row in original_cases if row['file'] != changed_path]
    require({row['file'] for row in final_cases} == {changed_path}, 'Unexpected corrective test file.')
    require({case_key(row) for row in replaced} == {case_key(row) for row in final_cases},
            'The corrected cached-host test case identities changed.')
    accepted = [{**row, 'provenance_head': first['source_head']} for row in retained]
    accepted += [{**row, 'provenance_head': last['source_head']} for row in final_cases]
    require(len(accepted) == len(original_cases), 'Accepted logical case count changed.')
    require(len({case_key(row) for row in accepted}) == len(accepted), 'Accepted union has duplicate cases.')
    per_file = dict(sorted(collections.Counter(row['file'] for row in accepted).items()))
    require(len(per_file) == first['suite_count'], 'Accepted suite count differs from the full original scope.')

    record = {
        'verified_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'verifier_sha256': digest(__file__), 'verifier_argv': sys.argv,
        'status': 'passed', 'final_source_head': last['source_head'],
        'final_source_tree': last['source_tree'],
        'original_source_head': first['source_head'],
        'accepted_passed': len(accepted), 'accepted_suites': len(per_file),
        'retained_cases': len(retained), 'replaced_cases': len(replaced),
        'corrective_passed': len(final_cases), 'failed': 0, 'skipped': 0,
        'case_identity_sets_equal_for_corrected_suite': True,
        'mail_source_change': changed_path,
        'source_snapshot_changes': source_changes,
        'unconsumed_word_test_fixture': fixture_audit['fixture'] if fixture_audit else None,
        'source_change_is_exact_previously_captured_formatter_output': True,
        'all_other_consumed_source_files_unchanged': True,
        'all_production_source_files_unchanged': True,
        'dependency_contents_and_package_roots_unchanged': True,
        'all_compiler_sdk_and_native_library_inputs_unchanged': True,
        'qualification_driver_change': {
            'path': runner_key,
            'old_sha256': first['runner_sha256'], 'new_sha256': last['runner_sha256'],
            'reason': 'Use the pinned Dart analyzer directly to avoid Flutter CLI SDK-dev enumeration; allow an explicit cached-host-only corrective run.',
        },
        'strict_analysis': {
            'core': 'Passed in original receipt.', 'transport': 'Passed in original receipt.',
            'ui': 'Passed with direct pinned Dart in corrective receipt.',
            'studio': 'Passed with direct pinned Dart in corrective receipt.',
            'editor_font_io': 'Passed static analysis only; no platform font-discovery runtime claim.',
        },
        'format_checked_files': len(last['changed_dart_files']),
        'final_worktree_clean': True,
        'original_diagnostics_preserved': ['One noncanonical test assertion layout.',
            'Three Flutter analyzer startup errors caused by omitted SDK dev/ source directories.',
            'Concurrent Word macro CLI test-owned temporary directory; tracked source seal was unchanged.'],
        'screenshots_retained': len(first['screenshots']),
        'per_file': per_file,
        'evidence': {
            'original_receipt_sha256': digest(baseline / 'qualification.json'),
            'corrective_receipt_sha256': digest(final / 'qualification.json'),
            'formatter_expectation_sha256': digest(baseline / 'formatter-expectation.json'),
            'visual_review_sha256': digest(baseline / 'visual-review.json'),
            'nonmail_fixture_audit_sha256': digest(args.nonmail_fixture_audit) if fixture_audit else None,
        },
    }
    (final / 'accepted-union.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    (final / 'accepted-test-cases.json').write_text(json.dumps(accepted, indent=2) + '\n')
    shutil.copyfile(Path(__file__), final / 'verification-runner.py')
    if fixture_audit:
        shutil.copyfile(args.nonmail_fixture_audit, final / 'nonmail-fixture-audit.json')
    print(json.dumps({key: record[key] for key in ['status', 'accepted_passed', 'accepted_suites',
          'retained_cases', 'corrective_passed', 'final_worktree_clean']}, indent=2))


if __name__ == '__main__':
    main()
