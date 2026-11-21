#!/usr/bin/env python3
"""Recount PR277 Mail results and verify the source-bound retained union; no tests."""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

PREVIOUS = '0e4e999a08996a6b8696ca3adba11e303331b73e'
PREVIOUS_EXECUTION = '58cc4283b35b29a4036528f65ee0590230d583f6'
INCOMING = '383c0c0c5d3b4b1a6edccc8d09ffd1ca64029537'
CURRENT = '5c7b76a6137bc9373276ce2e7fccc6ed48903998'
OLD_PACKAGE = 'docs/validation/mail-latest-main-integration-20261120/'
MAIL_CHANGED = {
    'packages/quds_mail_ui/lib/src/reader/controller.dart',
    'packages/quds_mail_ui/lib/src/reader/presentation.dart',
    'packages/quds_mail_ui/lib/src/workspace/message_list.dart',
    'packages/quds_office_editor/example/lib/studio_mail_native.dart',
    'packages/quds_office_editor/example/lib/studio_mail_remote_images.dart',
}


def read(path):
    return json.loads(Path(path).read_text())


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    return digest(Path(path).read_bytes())


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def identity(case):
    return case['file'], case['name'], case['occurrence']


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args],
        env={**os.environ, 'GIT_NO_LAZY_FETCH': '1'})


def blob(repo, head, path):
    return git(repo, 'show', head + ':' + path)


def verify_blobs(repo, head, manifest):
    process = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env={**os.environ, 'GIT_NO_LAZY_FETCH': '1'})
    for path, row in sorted(manifest.items()):
        process.stdin.write((head + ':' + path + '\n').encode())
        process.stdin.flush()
        header = process.stdout.readline().decode().strip().split()
        assert len(header) == 3 and header[1] == 'blob', (path, header)
        data = process.stdout.read(int(header[2]))
        assert process.stdout.read(1) == b'\n'
        assert len(data) == row['bytes'] and digest(data) == row['sha256'], path
    process.stdin.close()
    assert process.wait() == 0


def remove_regions(text, regions):
    for start, end in regions:
        a = text.index(start)
        b = text.index(end, a)
        text = text[:a] + text[b:]
    return text


def normalized_native(text):
    text = remove_regions(text, [
        ('  Future<void> _loadCredentials()', '  void _applyCredentials('),
        ('  Future<void> _loadAccounts()', '  Future<void> _selectSavedAccount('),
        ('  Future<void> _loadRemoteImages()', '  Future<void> _reply()'),
    ])
    for part in [
        '    this.autoConnectSavedAccount,\n',
        '  bool _autoConnectScheduled = false;\n',
        '  Object? _autoConnectTicket;\n',
        '    _autoConnectTicket = null;\n',
        '  /// Connect after adopting remembered credentials. Built-in clients enable\n'
        '  /// this by default; hosts supplying their own factories can opt in explicitly.\n'
        '  final bool? autoConnectSavedAccount;\n\n',
    ]:
        text = text.replace(part, '')
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--baseline-accepted', type=Path, required=True)
    parser.add_argument('--baseline-sealed', type=Path, required=True)
    parser.add_argument('--focused', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    old = read(args.baseline_accepted / 'accepted-union.json')
    current = read(args.focused / 'qualification.json')
    assert old['status'] == current['status'] == 'passed'
    assert (old['accepted_passed'], old['accepted_suites'], old['platform_recheck_passed']) == (1471, 70, 228)
    assert old['accepted_source_head'] == PREVIOUS_EXECUTION
    assert current['source_head'] == CURRENT
    assert current['source_head_after'] == CURRENT
    assert current['source_tree_after'] == current['source_tree']
    assert current['git_status_after'] == ''
    assert current['full_default_scope'] is True
    assert (current['logical_passed'], current['logical_suite_count'], current['platform_recheck_passed']) == (411, 23, 28)
    assert current['failed'] == current['skipped'] == 0
    parents = git(args.repo, 'show', '-s', '--format=%P', CURRENT).decode().split()
    assert parents == [PREVIOUS, INCOMING], parents
    for key in ['source', 'dependencies', 'runtime']:
        assert current[key + '_unchanged'] is True
        assert read(args.focused / (key + '-before.json')) == read(args.focused / (key + '-after.json'))
    old_manifest = json.loads(blob(args.repo, PREVIOUS, OLD_PACKAGE + 'archive-manifest.json'))
    for local, exported in [
        ('accepted-union.json', 'accepted-union.json'),
        ('accepted-test-cases.json', 'accepted-test-cases.json'),
        ('accepted-platform-recheck-cases.json', 'platform-recheck-cases.json'),
    ]:
        assert (args.baseline_accepted / local).read_bytes() == blob(args.repo, PREVIOUS, OLD_PACKAGE + exported)
    for name in ['source-after.json', 'dependencies-after.json', 'runtime-after.json',
                 'resolved-packages.json', 'hosted-lock-verification.json']:
        assert sha(args.baseline_sealed / name) == old_manifest['members']['correction/' + name]['sha256']
    old_source = read(args.baseline_sealed / 'source-after.json')
    source = read(args.focused / 'source-after.json')
    for name in ['dependencies-after.json', 'resolved-packages.json', 'hosted-lock-verification.json']:
        assert read(args.baseline_sealed / name) == read(args.focused / name)
    old_runtime = read(args.baseline_sealed / 'runtime-after.json')
    runtime = read(args.focused / 'runtime-after.json')
    old_runner = old_runtime.pop('runtime/qualify_mail_latest_delta.py')
    new_runner = runtime.pop('runtime/qualify_mail_pr277.py')
    assert old_runtime == runtime
    assert new_runner['sha256'] == current['runner_sha256']
    prior_receipt = read(args.baseline_sealed / 'qualification.json')
    for key in ['dart_version', 'node_version', 'flutter_runtime']:
        assert prior_receipt[key] == current[key]

    spec = importlib.util.spec_from_file_location('pr277_runner', args.focused / 'qualification-runner.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    assert sha(args.focused / 'qualification-runner.py') == current['runner_sha256']
    execution_repo = Path(current['commands'][0]['cwd'])
    executions = []
    for command in current['commands']:
        assert command['exit_code'] == 0
        for stream in ['stdout', 'stderr']:
            assert sha(args.focused / command[stream]) == command[stream + '_sha256']
        if command['expected_test_files'] is None:
            continue
        summary, cases = runner.test_report(args.focused / command['stdout'],
            Path(command['cwd']), execution_repo, command['expected_test_files'], command['platform'])
        summary['accepted'] = summary['accepted'] and command['exit_code'] == 0
        assert summary == current['test_results'][command['name']]
        assert summary['accepted'] and summary['terminal_events'] == 1
        assert not any(summary[key] for key in ['unfinished_test_ids', 'missing_suites',
            'unexpected_suites', 'duplicate_start_ids', 'duplicate_completion_ids',
            'incomplete_case_metadata', 'non_json_stdout_lines'])
        cases = [{**case, 'gate': command['name']} for case in cases]
        assert cases == read(args.focused / (command['name'] + '-cases.json'))
        executions.extend(cases)
    assert executions == read(args.focused / 'test-cases.json')
    fresh = [case for case in executions if case['gate'] not in runner.PLATFORM_RECHECKS]
    portable = [case for case in executions if case['gate'] in runner.PLATFORM_RECHECKS]
    assert fresh == read(args.focused / 'logical-test-cases.json')
    assert portable == read(args.focused / 'portable-test-cases.json')
    assert len(fresh) == len(set(map(identity, fresh))) == 411
    assert len(portable) == 28 and current['platform_recheck_ids_match_vm'] is True
    fresh_files = {case['file'] for case in fresh}
    previous = read(args.baseline_accepted / 'accepted-test-cases.json')
    previous_node = read(args.baseline_accepted / 'accepted-platform-recheck-cases.json')
    retained = [case for case in previous if case['file'] not in fresh_files]
    replaced = [case for case in previous if case['file'] in fresh_files]
    retained_files = {case['file'] for case in retained}
    assert (len(retained), len(retained_files), len(replaced)) == (1125, 50, 346)
    assert set(map(identity, replaced)) <= set(map(identity, fresh))
    added = [case for case in fresh if identity(case) not in set(map(identity, replaced))]
    assert len(added) == 65
    assert all(old_source[path] == source[path] for path in retained_files)
    mail_production_delta = sorted(path for path in set(old_source) | set(source)
        if old_source.get(path) != source.get(path) and '/lib/' in path and
        (path.startswith('packages/quds_mail_') or path.startswith('packages/quds_office_editor/example/lib/studio_mail_')))
    assert set(mail_production_delta) == MAIL_CHANGED
    unchanged_prefixes = {}
    for prefix in ['packages/quds_mail_core/lib/', 'packages/quds_mail_transport/lib/',
        'packages/quds_mail_mime/', 'packages/quds_mail_store/', 'third_party/enough_mail/']:
        before = {key: value for key, value in old_source.items() if key.startswith(prefix)}
        after = {key: value for key, value in source.items() if key.startswith(prefix)}
        assert before == after, prefix
        unchanged_prefixes[prefix] = len(before)
    unchanged_paths = ['pubspec.lock', 'pubspec.yaml', 'analysis_options.yaml',
        'packages/quds_office_editor/example/lib/studio_mail_message_loader.dart',
        'packages/quds_office_editor/example/lib/studio_mail_ews.dart',
        'packages/quds_office_editor/example/lib/studio_mail_bulk_status.dart',
        'packages/quds_office_editor/example/lib/studio_mail_workspace_strings.dart']
    assert all(old_source[path] == source[path] for path in unchanged_paths)
    native = 'packages/quds_office_editor/example/lib/studio_mail_native.dart'
    native_before = normalized_native(blob(args.repo, PREVIOUS, native).decode())
    native_after = normalized_native(blob(args.repo, CURRENT, native).decode())
    assert native_before == native_after
    message_list = 'packages/quds_mail_ui/lib/src/workspace/message_list.dart'
    regions = [('  const MailMessageListStrings({', '  final String searchLoaded;'),
               ('  MailMessageList({', '  final List<MailMessageListItem> items;')]
    list_before = remove_regions(blob(args.repo, PREVIOUS, message_list).decode(), regions)
    list_after = remove_regions(blob(args.repo, CURRENT, message_list).decode(), regions)
    assert list_before == list_after
    reference_tokens = ['addImages(', 'remoteImage', 'loadStudioMailRemoteImages', 'autoConnectSavedAccount']
    reference_audit = {}
    for path in sorted(retained_files):
        if '/example/test/' in path or '/tool/' in path:
            text = blob(args.repo, CURRENT, path).decode()
            references = [{'line': index + 1, 'text': line.strip()}
                for index, line in enumerate(text.splitlines()) if any(token in line for token in reference_tokens)]
            assert not references, (path, references)
            reference_audit[path] = {'sha256': source[path]['sha256'], 'changed_api_references': references}

    accepted_retained = [{**case, 'accepted_at_source_head': CURRENT,
        'previous_accepted_at_source_head': case.get('accepted_at_source_head'),
        'acceptance': 'retained_with_input_and_impact_proof'} for case in retained]
    accepted_fresh = [{**case, 'execution_source_head': CURRENT, 'accepted_at_source_head': CURRENT,
        'acceptance': 'fresh_execution_with_exact_source_attribution'} for case in fresh]
    union = accepted_retained + accepted_fresh
    retained_node = [case for case in previous_node if case['file'] not in fresh_files]
    assert len(retained_node) == 202
    accepted_node = [{**case, 'accepted_at_source_head': CURRENT} for case in retained_node] + [
        {**case, 'execution_source_head': CURRENT, 'accepted_at_source_head': CURRENT} for case in portable]
    assert len(union) == len(set(map(identity, union))) == 1536
    assert len({case['file'] for case in union}) == 73
    assert len(accepted_node) == len(set(map(identity, accepted_node))) == 230
    node_files = {case['file'] for case in accepted_node}
    assert Counter(map(identity, accepted_node)) == Counter(identity(case) for case in union if case['file'] in node_files)
    assert not any(case['skipped'] or case['result'] != 'success' for case in union + accepted_node)
    verify_blobs(args.repo, PREVIOUS_EXECUTION, old_source)
    verify_blobs(args.repo, PREVIOUS, old_source)
    verify_blobs(args.repo, CURRENT, source)
    proof = {
        'schema_version': 1, 'status': 'passed', 'accepted_source_head': CURRENT,
        'accepted_source_tree': current['source_tree'], 'parents': parents,
        'prior_accepted_source_head': PREVIOUS_EXECUTION, 'prior_publication_head': PREVIOUS,
        'incoming_main': INCOMING, 'accepted_passed': 1536, 'accepted_suites': 73,
        'fresh_passed': 411, 'fresh_suites': 23, 'retained_passed': 1125, 'retained_suites': 50,
        'replaced_prior_passed': 346, 'replaced_prior_suites': len({case['file'] for case in replaced}),
        'new_case_identities': 65, 'removed_prior_case_identities': 0,
        'platform_recheck_passed': 230, 'fresh_platform_rechecks': 28, 'retained_platform_rechecks': 202,
        'platform_recheck_ids_match_canonical': True, 'failed': 0, 'skipped': 0,
        'retained_execution_source_counts': dict(sorted(Counter(case['execution_source_head'] for case in retained).items())),
        'accepted_execution_source_counts': dict(sorted(Counter(case['execution_source_head'] for case in union).items())),
        'fresh_commands_all_passed': True, 'format_passed': True, 'strict_analyzers_passed': ['core', 'ui', 'studio'],
        'source_seals_unchanged': True, 'dependency_seals_unchanged': True, 'runtime_seals_unchanged': True,
        'git_source_blob_count': len(source), 'baseline_source_blob_count': len(old_source),
        'dependency_file_count': current['dependency_file_count'],
        'cross_run_external_dependencies_equal': True, 'cross_run_shared_runtime_and_configuration_equal': True,
        'changed_runtime_inputs': {'prior_qualifier': old_runner, 'current_qualifier': new_runner},
        'previous_package_archive': old_manifest['archive'],
        'mail_production_delta': mail_production_delta,
        'unchanged_source_prefix_file_counts': unchanged_prefixes,
        'unchanged_shared_paths': unchanged_paths,
        'native_outside_autoconnect_and_explicit_remote_load_exact': True,
        'native_normalized_sha256': digest(native_after.encode()),
        'message_list_outside_constructor_alias_validation_exact': True,
        'message_list_normalized_sha256': digest(list_after.encode()),
        'retained_case_files': sorted(retained_files),
        'retained_host_reference_audit': reference_audit,
        'impact_reasoning': [
            'All 50 retained test files are byte-identical. Core, transport, MIME, store, enough_mail, EWS and native-loader production inputs are unchanged.',
            'The complete shared UI test directory is freshly executed. The retained five-case visual tool uses unchanged rendering/event paths with non-conflicting constructor aliases; all non-constructor message-list bytes are identical.',
            'Native host bytes outside saved-credential autoconnect ownership and explicit remote-image loading are identical. Injected client factories remain manual by default; new autoconnect and remote-image paths are freshly exercised.',
            'Retained host/tool tests contain no calls to the changed remote-image APIs or explicit autoconnect override. Account/credential race, cached Mail, workspace and visual integrations are freshly exercised.',
            'Word/editor table and Zotero changes are qualified separately. The nine-case shared Studio layout suite is fresh and overlaps Word evidence; do not sum project totals.',
        ],
        'per_file': dict(sorted(Counter(case['file'] for case in union).items())),
        'dart_version': current['dart_version'], 'node_version': current['node_version'],
        'github_actions_used': False,
        'counting_note': '1,125 prior cases retain their actual c623/416/58cc execution heads; 411 execute at 5c7. All 346 replaced identities remain present, with 65 additions. The 230 Node executions recheck canonical identities and are not added to 1,536. Historical failed aggregates remain failed in the prior immutable evidence package.',
    }
    args.out.mkdir(parents=True, exist_ok=True)
    for name, value in [
        ('accepted-union.json', proof), ('accepted-test-cases.json', sorted(union, key=identity)),
        ('accepted-platform-recheck-cases.json', sorted(accepted_node, key=identity)),
        ('retained-test-cases.json', sorted(accepted_retained, key=identity)),
        ('replaced-prior-test-cases.json', sorted(replaced, key=identity)),
        ('fresh-test-cases.json', sorted(accepted_fresh, key=identity)),
        ('new-test-cases.json', sorted(added, key=identity)),
    ]:
        write(args.out / name, value)
    print(json.dumps({key: proof[key] for key in ['status', 'accepted_source_head', 'accepted_passed',
        'accepted_suites', 'fresh_passed', 'retained_passed', 'platform_recheck_passed', 'new_case_identities']}, indent=2))


if __name__ == '__main__':
    main()
