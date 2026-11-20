#!/usr/bin/env python3
"""Recount the final focused Mail gate and prove its c623 retention boundary."""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess


BASELINE = 'c62338c65571aa399da5592455b651fa5c6a9317'
INITIAL = '4163368b63b35414f25c3830fcc49055e6088953'
FIXTURE_FILES = {
    'packages/quds_office_editor/example/test/' + name for name in [
        'studio_layout_theme_test.dart',
        'studio_mail_credential_backend_switch_test.dart',
        'studio_mail_lifecycle_test.dart', 'studio_mail_test.dart',
        'studio_mail_workspace_test.dart', 'studio_saved_mail_test.dart',
    ]
}
CASE_RENAME = {
    'file': 'packages/quds_office_editor/example/test/studio_mail_credential_backend_switch_test.dart',
    'old_name': 'pending account save also disables storage in the File menu',
    'new_name': 'pending account save disables storage in the ribbon',
    'reason': 'The captured main replaced the File menu with the ribbon; ownership assertions remain.',
}



def read(path):
    return json.loads(Path(path).read_text())


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def identity(case):
    return case['file'], case['name'], case['occurrence']


def git_bytes(repo, head, path):
    return subprocess.check_output(['git', '-C', str(repo), 'show', head + ':' + path])


def verify_git_blobs(repo, head, manifest):
    process = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for path, row in sorted(manifest.items()):
        process.stdin.write((head + ':' + path + '\n').encode())
        process.stdin.flush()
        header = process.stdout.readline().decode().strip().split()
        assert len(header) == 3 and header[1] == 'blob', (path, header)
        data = process.stdout.read(int(header[2]))
        assert process.stdout.read(1) == b'\n'
        assert len(data) == row['bytes']
        assert hashlib.sha256(data).hexdigest() == row['sha256'], path
    process.stdin.close()
    assert process.wait() == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--baseline-accepted', type=Path, required=True)
    parser.add_argument('--baseline-sealed', type=Path, required=True)
    parser.add_argument('--baseline-config', type=Path, required=True)
    parser.add_argument('--focused', type=Path, required=True)
    parser.add_argument('--focused-config', type=Path, required=True)
    parser.add_argument('--correction', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    old = read(args.baseline_accepted / 'qualification.json')
    initial = read(args.focused / 'qualification.json')
    current = read(args.correction / 'qualification.json')
    assert old['source_head'] == BASELINE and old['status'] == 'passed'
    assert old['accepted_passed'] == 1161 and old['accepted_suites'] == 52
    assert initial['source_head'] == INITIAL and initial['status'] == 'failed'
    assert initial['failed'] == 18 and initial['logical_passed'] == 847
    assert current['status'] == 'passed'
    head = current['source_head']
    for directory, receipt in [(args.focused, initial), (args.correction, current)]:
        assert receipt['source_head_after'] == receipt['source_head']
        assert receipt['source_tree_after'] == receipt['source_tree']
        assert receipt['git_status_after'] == ''
        for key in ['source', 'dependencies', 'runtime']:
            assert receipt[key + '_unchanged'] is True
            assert read(directory / (key + '-before.json')) == read(directory / (key + '-after.json'))
    initial_source = read(args.focused / 'source-after.json')
    final_source = read(args.correction / 'source-after.json')
    changed = {key for key in set(initial_source) | set(final_source)
        if initial_source.get(key) != final_source.get(key)}
    assert changed == FIXTURE_FILES, changed
    for key in ['dependencies', 'runtime']:
        assert read(args.focused / (key + '-after.json')) == read(args.correction / (key + '-after.json'))
    for key in ['resolved-packages.json', 'hosted-lock-verification.json']:
        assert read(args.focused / key) == read(args.correction / key)
    assert initial['runner_sha256'] == current['runner_sha256']
    assert initial['dart_version'] == current['dart_version']
    assert initial['node_version'] == current['node_version']
    assert initial['flutter_runtime'] == current['flutter_runtime']
    assert old['dart_version'] == current['dart_version']
    assert old['node_version'] == current['node_version']
    assert old['flutter_runtime'] == current['flutter_runtime']
    old_source = read(args.baseline_sealed / 'source-after.json')
    source = final_source
    old_dependencies = read(args.baseline_sealed / 'dependencies-after.json')
    dependencies = read(args.focused / 'dependencies-after.json')
    assert old_dependencies == dependencies
    old_runtime = read(args.baseline_sealed / 'runtime-after.json')
    runtime = read(args.focused / 'runtime-after.json')
    shared_keys = set(old_runtime) & set(runtime)
    assert all(old_runtime[key] == runtime[key] for key in shared_keys)
    old_root = Path(old['commands'][0]['cwd'])
    new_root = Path(current['commands'][0]['cwd'])
    expected_old_only = {old_root.name + '/.dart_tool/' + name for name in
        ['lib/libsqlite3.so', 'native_assets.yaml', 'package_config.json', 'package_graph.json']}
    expected_old_only.add('runtime/qualify_mail_final_union.py')
    expected_new_only = {new_root.name + '/.dart_tool/' + name for name in
        ['lib/libsqlite3.so', 'native_assets.yaml', 'package_config.json', 'package_graph.json']}
    expected_new_only.add('runtime/qualify_mail_latest_delta.py')
    assert set(old_runtime) - shared_keys == expected_old_only
    assert set(runtime) - shared_keys == expected_new_only
    for name in ['lib/libsqlite3.so', 'package_config.json', 'package_graph.json']:
        assert old_runtime[old_root.name + '/.dart_tool/' + name] == runtime[new_root.name + '/.dart_tool/' + name]
    old_native = args.baseline_config / 'native_assets.yaml'
    new_native = args.focused_config / 'native_assets.yaml'
    assert sha(old_native) == old_runtime[old_root.name + '/.dart_tool/native_assets.yaml']['sha256']
    assert sha(new_native) == runtime[new_root.name + '/.dart_tool/native_assets.yaml']['sha256']
    old_native_normalized = old_native.read_text().replace(str(old_root), '$REPO')
    new_native_normalized = new_native.read_text().replace(str(new_root), '$REPO')
    assert json.loads(old_native_normalized) == json.loads(new_native_normalized)
    def normalize_packages(path, root):
        return json.loads(Path(path).read_text().replace(str(root), '$REPO'))
    assert normalize_packages(args.baseline_sealed / 'resolved-packages.json', old_root) == normalize_packages(args.focused / 'resolved-packages.json', new_root)
    assert read(args.baseline_sealed / 'hosted-lock-verification.json') == read(args.focused / 'hosted-lock-verification.json')
    def recount(directory, receipt, allow_failures=False):
        spec = importlib.util.spec_from_file_location('focused_runner', directory / 'qualification-runner.py')
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        assert sha(directory / 'qualification-runner.py') == receipt['runner_sha256']
        executions = []
        failed_files = set()
        for command in receipt['commands']:
            for stream in ['stdout', 'stderr']:
                assert sha(directory / command[stream]) == command[stream + '_sha256']
            if command['expected_test_files']:
                summary, cases = runner.test_report(directory / command['stdout'], Path(command['cwd']),
                    new_root, command['expected_test_files'], command['platform'])
                summary['accepted'] = summary['accepted'] and command['exit_code'] == 0
                assert summary == receipt['test_results'][command['name']]
                assert summary['terminal_events'] == 1
                assert not any(summary[key] for key in ['unfinished_test_ids', 'missing_suites',
                    'unexpected_suites', 'duplicate_start_ids', 'duplicate_completion_ids',
                    'incomplete_case_metadata', 'non_json_stdout_lines'])
                cases = [{**case, 'gate': command['name']} for case in cases]
                assert cases == read(directory / (command['name'] + '-cases.json'))
                if not summary['accepted']:
                    assert allow_failures and command['exit_code'] == 1
                    failed_files.update(case['file'] for case in cases)
                else:
                    assert command['exit_code'] == 0
                executions.extend(cases)
            else:
                assert command['exit_code'] == 0
        assert executions == read(directory / 'test-cases.json')
        canonical = [case for case in executions if case['gate'] not in runner.PLATFORM_RECHECKS]
        portable = [case for case in executions if case['gate'] in runner.PLATFORM_RECHECKS]
        assert canonical == read(directory / 'logical-test-cases.json')
        assert portable == read(directory / 'portable-test-cases.json')
        assert len(set(map(identity, canonical))) == len(canonical) == receipt['logical_case_identity_count']
        assert receipt['platform_recheck_ids_match_vm'] is True
        return canonical, portable, failed_files

    initial_cases, portable, failed_files = recount(args.focused, initial, True)
    corrected_cases, corrected_portable, corrected_failed = recount(args.correction, current)
    assert failed_files == FIXTURE_FILES and not corrected_failed and not corrected_portable
    assert {case['file'] for case in corrected_cases} == FIXTURE_FILES
    assert len(corrected_cases) == 171 and current['logical_passed'] == 171
    superseded = [case for case in initial_cases if case['file'] in FIXTURE_FILES]
    def corrected_identity(case):
        value = identity(case)
        if case['file'] == CASE_RENAME['file'] and case['name'] == CASE_RENAME['old_name']:
            value = (case['file'], CASE_RENAME['new_name'], case['occurrence'])
        return value
    assert Counter(map(corrected_identity, superseded)) == Counter(map(identity, corrected_cases))
    original_retained = [case for case in initial_cases if case['file'] not in FIXTURE_FILES]
    assert len(original_retained) == 694
    fresh = [{**case, 'execution_source_head': INITIAL} for case in original_retained] + [
        {**case, 'execution_source_head': head} for case in corrected_cases]
    assert len(fresh) == 865 and len(set(map(identity, fresh))) == 865
    assert all(case['result'] == 'success' and not case['skipped'] for case in fresh + portable)
    assert len(portable) == 131
    previous = read(args.baseline_accepted / 'accepted-test-cases.json')
    previous_node = read(args.baseline_accepted / 'platform-recheck-cases.json')
    fresh_files = {case['file'] for case in fresh}
    retained = [case for case in previous if case['file'] not in fresh_files]
    replaced = [case for case in previous if case['file'] in fresh_files]
    retained_files = {case['file'] for case in retained}
    assert len(retained) == 606 and len(retained_files) == 33 and len(replaced) == 555
    assert all(old_source[path] == source[path] for path in retained_files)
    def unchanged_prefix(prefix):
        old_rows = {key: value for key, value in old_source.items() if key.startswith(prefix)}
        new_rows = {key: value for key, value in source.items() if key.startswith(prefix)}
        assert old_rows == new_rows, prefix
        return len(old_rows)
    unchanged = {prefix: unchanged_prefix(prefix) for prefix in [
        'packages/quds_mail_core/lib/', 'packages/quds_mail_mime/',
        'packages/quds_mail_store/', 'packages/quds_mail_transport/lib/src/native/',
        'third_party/enough_mail/',
    ]}
    for path in ['pubspec.lock', 'pubspec.yaml', 'analysis_options.yaml',
        'packages/quds_office_editor/example/lib/studio_mail_message_loader.dart']:
        assert old_source[path] == source[path]
    transport_delta = [key for key in set(old_source) | set(source)
        if key.startswith('packages/quds_mail_transport/lib/') and old_source.get(key) != source.get(key)]
    cloud_path = 'packages/quds_mail_transport/lib/src/cloud/provider.dart'
    assert transport_delta == [cloud_path]
    cloud_old = git_bytes(args.repo, BASELINE, cloud_path).decode()
    cloud_new = git_bytes(args.repo, head, cloud_path).decode()
    a = cloud_old.index('    // Only explicit request/auth/resource/precondition')
    b = cloud_old.index('    operation.check();', a)
    c = cloud_new.index('    // Foreground message mutations use a narrow')
    d = cloud_new.index('    operation.check();', c)
    assert cloud_old[:a] + cloud_old[b:] == cloud_new[:c] + cloud_new[d:]
    new_retained = [{**case, 'accepted_at_source_head': head, 'execution_source_head': BASELINE,
        'acceptance': 'retained_with_input_and_impact_proof'} for case in retained]
    new_fresh = [{**case, 'accepted_at_source_head': head, 'acceptance': 'fresh_execution_with_exact_source_attribution'} for case in fresh]
    union = new_retained + new_fresh
    assert len(set(map(identity, union))) == len(union)
    retained_node = [case for case in previous_node if case['file'] not in fresh_files]
    assert len(retained_node) == 97
    accepted_node = [{**case, 'execution_source_head': BASELINE} for case in retained_node] + [
        {**case, 'execution_source_head': INITIAL} for case in portable]
    portable_files = {case['file'] for case in accepted_node}
    assert Counter(map(identity, accepted_node)) == Counter(identity(case) for case in union if case['file'] in portable_files)
    assert not any(case['skipped'] or case['result'] != 'success' for case in union + accepted_node)
    verify_git_blobs(args.repo, BASELINE, old_source)
    verify_git_blobs(args.repo, INITIAL, initial_source)
    verify_git_blobs(args.repo, head, source)
    initial_failed_cases = [case for case in initial_cases if case['result'] != 'success']
    assert len(initial_failed_cases) == 18
    layout = 'packages/quds_office_editor/example/test/studio_layout_theme_test.dart'
    marker = b"  testWidgets(\n    'Mail uses shared chrome"
    prefix_before = git_bytes(args.repo, INITIAL, layout).split(marker)[0]
    prefix_after = git_bytes(args.repo, head, layout).split(marker)[0]
    assert prefix_before == prefix_after and len(prefix_before) == 17845

    proof = {'schema_version': 1, 'status': 'passed', 'accepted_source_head': head,
        'accepted_source_tree': current['source_tree'], 'baseline_execution_head': BASELINE,
        'accepted_passed': len(union), 'accepted_suites': len({case['file'] for case in union}),
        'fresh_passed': len(fresh), 'fresh_suites': len(fresh_files), 'retained_passed': 606,
        'initial_focused_execution_head': INITIAL,
        'initial_focused_aggregate_status': initial['status'], 'initial_focused_failed': 18,
        'retained_focused_passed': len(original_retained), 'retained_focused_suites': 31,
        'corrective_execution_head': head, 'corrective_passed': len(corrected_cases),
        'corrective_suites': 6, 'superseded_initial_focused_cases': len(superseded),
        'corrected_fixture_files': sorted(FIXTURE_FILES), 'case_identity_renames': [CASE_RENAME],
        'correction_changes_only_six_test_files': True,
        'shared_layout_word_prefix_unchanged_bytes': len(prefix_before),
        'retained_suites': 33, 'replaced_prior_passed': 555, 'failed': 0, 'skipped': 0,
        'platform_recheck_passed': len(accepted_node), 'fresh_platform_rechecks': len(portable),
        'retained_platform_rechecks': 97, 'platform_recheck_ids_match_canonical': True,
        'git_source_blob_count': len(source), 'dependency_file_count': len(dependencies),
        'source_seals_unchanged': True, 'dependency_seals_unchanged': True,
        'runtime_seals_unchanged': True, 'cross_run_external_dependencies_equal': True,
        'cross_run_sdk_and_shared_runtime_hashes_equal': True,
        'package_config_and_graph_byte_identical': True, 'native_library_byte_identical': True,
        'native_asset_path_only_rewired': True, 'configured_packages_equal_after_checkout_root_rewire': True,
        'changed_runtime_inputs': 'Only the qualifier script and worktree-local path for native-assets registration.',
        'unchanged_source_prefix_file_counts': unchanged,
        'retained_case_files': sorted(retained_files),
        'transport_production_delta_only': cloud_path,
        'cloud_old_mutation_evidence_block': cloud_old[a:b],
        'cloud_new_mutation_evidence_block': cloud_new[c:d],
        'impact_reasoning': [
            'All retained core production, fixtures and test files are unchanged.',
            'Only the cloud _request mutation-evidence block changes within transport production; its VM and Node provider suite is rerun.',
            'Retained cloud_store cases execute pullChanges with mutation=false and controlled 200 responses, leaving the changed branch without an observable effect.',
            'Retained JavaScript unsupported suites select unchanged conditional factories/stubs; they do not execute the native cloud provider.',
            'The 95 retained loader cases and their native loader/transport/MIME/store implementation are unchanged.',
        ],
        'per_file': dict(sorted(Counter(case['file'] for case in union).items())),
        'node_version': current['node_version'], 'github_actions_used': False,
        'counting_note': 'Canonical case identities are unique. Node rechecks are not additional cases. 606 retained cases executed at c623; 694 unchanged focused cases at 416; 171 complete corrective-file cases at the final source. The initial 18-failure aggregate remains failed and is preserved. All 171 original executions of corrected files are replaced, including 153 prior passes; one obsolete File-menu case title is explicitly renamed.'}
    args.out.mkdir(parents=True, exist_ok=True)
    write(args.out / 'accepted-union.json', proof)
    write(args.out / 'accepted-test-cases.json', sorted(union, key=identity))
    write(args.out / 'accepted-platform-recheck-cases.json', sorted(accepted_node, key=identity))
    write(args.out / 'retained-test-cases.json', sorted(new_retained, key=identity))
    write(args.out / 'replaced-prior-test-cases.json', sorted(replaced, key=identity))
    write(args.out / 'superseded-initial-focused-cases.json', sorted(superseded, key=identity))
    write(args.out / 'initial-focused-failed-cases.json', sorted(initial_failed_cases, key=identity))
    print(json.dumps({key: proof[key] for key in ['status', 'accepted_source_head', 'accepted_passed',
        'accepted_suites', 'fresh_passed', 'fresh_suites', 'retained_passed', 'platform_recheck_passed']}, indent=2))


if __name__ == '__main__':
    main()
