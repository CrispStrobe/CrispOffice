#!/usr/bin/env python3
"""Bind the publication follow-up to preserved source and fresh scoped gates."""

import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    here = Path(__file__).resolve().parent
    continuation = here.parent

    def git(*command):
        return subprocess.check_output(['git', '-C', str(repo), *command])

    def read(path):
        data = path.read_bytes()
        return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)

    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def tree(ref):
        result = {}
        for row in git('ls-tree', '-r', '-z', ref).decode().split('\0'):
            if row:
                identity, path = row.split('\t', 1)
                result[path] = identity
        return result

    candidate = git('rev-parse', args.candidate + '^{commit}').decode().strip()
    tested = 'f3f98987824e021ed22a4d909e38d6307495267b'
    lint = '3cba1810b41a2fff5b2cd1eb355137a46b09f225'
    historical_publication = 'b1c8c8e534c41914b934defd6023839b851b28a2'
    script = 'packages/quds_office_editor/example/tool/build_macos_app.sh'
    distribution = 'packages/quds_proofing_spacy/lib/src/distribution.dart'
    evaluator = 'packages/quds_proofing_spacy/tool/evaluate_grammar_v2.dart'
    source_trees = {ref: tree(ref) for ref in [tested, lint, historical_publication, candidate]}
    final_tree = source_trees[candidate]
    summary = read(continuation / 'summary.json')
    old_audit = read(continuation / 'publication-audit.json')
    assert old_audit['publication_source_candidate'] == historical_publication
    assert old_audit['only_changed_path_from_tests_to_publication'] == evaluator
    assert summary['fresh_distinct_passed_cases'] == 3201
    assert summary['fresh_successful_application_executions'] == 3209

    selected = []
    recorded = {}
    for cohort in summary['cohorts']:
        directory = continuation / ('accepted-' + cohort['name'])
        receipt = read(directory / 'receipt.json')
        assert sha(directory / 'receipt.json') == cohort['receipt_sha256']
        selected.extend(receipt['selected_repository_paths'])
        for path, entry in read(directory / 'inputs.json.gz')['before']['source'].items():
            assert source_trees[tested][path].split()[2] == entry['git_blob_sha1']
            if path in recorded:
                assert recorded[path] == entry
            recorded[path] = entry
    assert len(selected) == len(set(selected)) == 129
    assert all(all(mapping[path] == final_tree[path] for mapping in source_trees.values()) for path in selected)
    differences = {}
    for ref in [tested, lint, historical_publication]:
        differences[ref] = sorted(path for path in recorded if source_trees[ref][path] != final_tree.get(path))
    assert differences[tested] == sorted([script, distribution, evaluator])
    assert differences[lint] == differences[historical_publication] == sorted([script, distribution])
    assert source_trees[lint][evaluator] == source_trees[historical_publication][evaluator] == final_tree[evaluator]

    manifest_paths = [p for p in source_trees[tested] if Path(p).name in {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}]
    library_paths = [p for p in source_trees[tested] if p.startswith(('packages/', 'apps/', 'third_party/')) and '/lib/' in p]
    assert all(source_trees[tested][p] == final_tree[p] for p in manifest_paths)
    changed_libraries = [p for p in library_paths if source_trees[tested][p] != final_tree[p]]
    assert changed_libraries == [distribution]
    dart_delta = git('diff', '--name-only', lint, candidate, '--', '*.dart').decode().splitlines()
    assert dart_delta == [distribution]
    old_distribution = git('show', f'{lint}:{distribution}').decode()
    final_distribution = git('show', f'{candidate}:{distribution}').decode()
    non_docs = lambda text: '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('///'))
    assert non_docs(old_distribution) == non_docs(final_distribution)

    review_path = here / 'macos-build-review.json'
    review = read(review_path)
    assert review['candidate_commit'] == candidate and review['status'] == 'passed'
    assert review['merged_tree'] == git('rev-parse', candidate + '^{tree}').decode().strip()
    assert review['shell_control_flow']['passed'] == 10
    assert all(case['passed'] for case in review['shell_control_flow']['cases'])
    assert review['all_script_pins_unchanged'] and review['distribution_executable_tokens_unchanged']
    fixture = read(continuation / 'spacy-qualified-bytes.json')
    assert fixture['sha256'] == review['pins']['SPACY_PIN_SHA256']
    assert str(fixture['bytes']) == review['pins']['SPACY_PIN_BYTES']

    pin_root = here / 'accepted-studio-pin'
    pin = read(pin_root / 'receipt.json')
    assert pin['status'] == 'passed' and pin['exit_code'] == 0
    assert pin['source_head_at_start'] == pin['source_head_at_finish'] == candidate
    assert all(pin['guards'].values())
    assert pin['tests']['passed'] == pin['tests']['application_cases'] == pin['tests']['suite_count'] == 1
    assert pin['tests']['failed'] == pin['tests']['skipped'] == 0
    assert set(pin['selected_repository_paths']).issubset(selected)
    for name, artifact in pin['artifacts'].items():
        file = pin_root / name
        assert len(file.read_bytes()) == artifact['bytes'] and sha(file) == artifact['sha256']
    for path, entry in read(pin_root / 'inputs.json.gz')['before']['source'].items():
        assert final_tree[path].split()[2] == entry['git_blob_sha1']

    static_root = here / 'static'
    static = read(static_root / 'receipt.json')
    assert static['head'] == candidate and static['accepted'] and static['inputs_identical']
    assert static['before'] == static['after']
    assert len(static['paths']) == 83 and all(item['exit_code'] == 0 for item in static['checks'].values())
    expected_static = git('diff', '--name-only', static['base'], candidate, '--', '*.dart').decode().splitlines()
    assert sorted(static['paths']) == sorted(expected_static)
    for path in static['paths']:
        assert hashlib.sha256(git('show', f'{candidate}:{path}')).hexdigest() == static['after'][path]

    result = {
        'status': 'verified_publication_followup_with_scoped_build_validation',
        'audited_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'candidate_commit': candidate, 'candidate_tree': review['merged_tree'],
        'candidate_parents': git('show', '-s', '--format=%P', candidate).decode().split(),
        'earlier_tested_source': tested, 'earlier_lint_corrected_source': lint,
        'earlier_publication_candidate': historical_publication,
        'earlier_publication_audit_sha256': sha(continuation / 'publication-audit.json'),
        'recorded_source_inputs': len(recorded),
        'changed_recorded_source_paths_by_reference': differences,
        'unchanged_recorded_source_inputs_from_tested_source': len(recorded) - len(differences[tested]),
        'all_recorded_source_inputs_unchanged': False,
        'selected_test_files_unchanged': len(selected),
        'manifest_lock_analysis_paths_unchanged': len(manifest_paths),
        'tracked_library_paths': len(library_paths),
        'byte_identical_library_paths': len(library_paths) - 1,
        'only_library_byte_change': distribution,
        'library_change_only_documentation_comments': True,
        'all_dart_executable_tokens_unchanged_since_lint_correction': True,
        'earlier_evaluator_brace_change_unmodified_and_retains_original_isolation_proof': True,
        'script_pins_and_qualified_byte_identity_unchanged': True,
        'qualified_file_sha256': fixture['sha256'], 'qualified_file_bytes': fixture['bytes'],
        'qualified_code_digest_pin': review['pins']['SPACY_PIN_CODE_SHA256'],
        'build_review': {'path': 'macos-build-review.json', 'sha256': sha(review_path), 'controlled_shell_cases_passed': 10, 'native_build_or_signing_executed': False},
        'fresh_pin_followup': {'path': 'accepted-studio-pin/receipt.json', 'sha256': sha(pin_root / 'receipt.json'), 'passed': 1, 'failed': 0, 'skipped': 0, 'all_primary_guards_passed': True, 'distinct_case_total_increment': 0},
        'fresh_static': {'path': 'static/receipt.json', 'sha256': sha(static_root / 'receipt.json'), 'head': candidate, 'targets': 83, 'analysis_exit_code': static['checks']['analysis']['exit_code'], 'format_exit_code': static['checks']['format']['exit_code']},
        'case_accounting': {'original_five_cohort_successful_executions': 3209, 'distinct_application_cases_remain': 3201, 'distinct_files_remain': 129, 'followup_application_execution_is_one_existing_case_repeated': True, 'controlled_shell_checks_are_separate': 10, 'proofing_primary_uniqueness_rejection_and_independent_eight_pair_accounting_retained': True},
        'limits': ['The earlier 3,201 distinct cases retain their recorded source attribution. The one script-reading case is freshly rerun on this candidate; the entire five-cohort selection is not rerun.', 'The original standalone evaluator isolation audit remains unchanged. This supplement reports the newer script behavior and documentation differences explicitly.', 'Command stubs check the exact changed shell control flow, not Apple signing tools or cryptographic implementations. No macOS build, native library execution, notarization, live account, or Office interoperability run is claimed.'],
        'github_actions_queried': False, 'remote_refs_mutated': False,
        'verifier_sha256': sha(Path(__file__)),
    }
    output = args.output or here / 'final-audit.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['status', 'candidate_commit', 'recorded_source_inputs', 'selected_test_files_unchanged', 'all_dart_executable_tokens_unchanged_since_lint_correction']}, indent=2))


if __name__ == '__main__':
    main()
