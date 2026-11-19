#!/usr/bin/env python3
"""Read-only inventory of the one newly observed bounded main head."""
from __future__ import annotations
from collections import Counter
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent
REPO = ROOT / 'quds_office_suite'
MAIN = '666e9a2ea46f7aeaaa1d01b60aabea0c2fe6f0fd'
INTEGRATION = '656ff82366c6d835acee29affb9f77371e4cd383'
QUALIFIED = '22ffa8bdcc11e5e10eb37f2326f832066f609a08'
TREES = {}


def git(*args: str) -> bytes:
    return subprocess.check_output(['git', '--no-lazy-fetch', '--no-replace-objects', '-C', str(REPO), *args])


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tree(commit: str) -> dict:
    if commit not in TREES:
        entries = {}
        for item in git('ls-tree', '-r', '-z', commit).split(b'\0'):
            if item:
                fields, name = item.split(b'\t', 1)
                mode, kind, blob = fields.decode().split()
                entries[name.decode()] = {'mode': mode, 'kind': kind, 'blob': blob}
        TREES[commit] = entries
    return TREES[commit]


def category(path: str) -> str:
    if path.startswith('docs/validation/'):
        return 'validation_evidence_or_driver'
    if path.startswith(('packages/', 'apps/', 'third_party/')):
        if path.endswith('pubspec.yaml'):
            return 'package_manifest'
        if '/test/' in path:
            return 'product_test_or_fixture'
        if path.endswith('.dart'):
            return 'product_implementation'
        return 'product_documentation_or_asset'
    if path.startswith(('tools/', 'tool/')):
        return 'repository_tool'
    return 'other_documentation_or_configuration'


def delta(left: str, right: str) -> list[dict]:
    fields = git('diff', '--name-status', '--no-renames', '-z', left, right, '--').decode().split('\0')
    rows = []
    for index in range(0, len(fields) - 1, 2):
        status, path = fields[index:index + 2]
        rows.append({'status': status, 'path': path, 'category': category(path), 'before': tree(left).get(path), 'after': tree(right).get(path)})
    return rows


def commit_record(commit: str) -> dict:
    # Read the commit object directly: some git-show merge presentation options
    # request unmaterialized parent blobs even with --no-patch.
    header, body = git('cat-file', 'commit', commit).decode().split('\n\n', 1)
    lines = header.splitlines()
    def stamp(kind: str) -> datetime:
        row = next(line for line in lines if line.startswith(kind + ' '))
        _, epoch, offset = row.rsplit(' ', 2)
        minutes = int(offset[1:3]) * 60 + int(offset[3:])
        if offset.startswith('-'):
            minutes = -minutes
        return datetime.fromtimestamp(int(epoch), timezone(timedelta(minutes=minutes)))
    return {'commit': commit, 'parents': [line[7:] for line in lines if line.startswith('parent ')], 'author_date': stamp('author').isoformat(), 'committer_date': stamp('committer').isoformat(), 'committer_date_utc': stamp('committer').astimezone(timezone.utc).isoformat(), 'subject': body.splitlines()[0], 'tree': next(line[5:] for line in lines if line.startswith('tree '))}


def plan_tests(commit: str, path: str) -> tuple[dict, list[str]]:
    plan = json.loads(git('show', commit + ':' + path))
    return plan, [str(Path(group['cwd']) / test) for group in plan['groups'] for test in group['tests']]


def main() -> None:
    bases = git('merge-base', '--all', INTEGRATION, MAIN).decode().splitlines()
    commits = git('rev-list', '--reverse', '--topo-order', MAIN, '--not', INTEGRATION).decode().splitlines()
    net = delta(INTEGRATION, MAIN)
    base_rows = []
    for base in bases:
        changes = delta(base, MAIN)
        base_rows.append({'base': commit_record(base), 'main_delta_count': len(changes), 'main_delta_by_category': dict(Counter(row['category'] for row in changes)), 'main_delta': changes})
    manifest_paths = [row['path'] for row in net if Path(row['path']).name in {'pubspec.yaml', 'pubspec.lock', 'package.json', 'package-lock.json', 'analysis_options.yaml', '.fvmrc'}]
    assert manifest_paths == ['packages/quds_office_editor/example/pubspec.yaml'], manifest_paths
    dependency_diff = git('diff', INTEGRATION, MAIN, '--', *manifest_paths).decode()
    unchanged = []
    for path in ('pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml'):
        assert tree(INTEGRATION)[path] == tree(MAIN)[path]
        unchanged.append({'path': path, **tree(MAIN)[path]})
    imports = {}
    for row in net:
        if row['after'] and row['path'].endswith('.dart') and row['path'].startswith(('packages/', 'apps/', 'third_party/')):
            body = git('show', MAIN + ':' + row['path']).decode()
            for package in sorted(set(re.findall(r'''(?:import|export)\s+['"]package:([^/'"]+)''', body))):
                imports.setdefault(package, []).append(row['path'])
    config_path = REPO / '.dart_tool/package_config.json'
    config_raw = config_path.read_bytes()
    config = json.loads(config_raw)
    packages = {row['name']: row for row in config['packages']}
    missing = sorted(set(imports) - packages.keys())
    assert not missing, missing
    accepted_environment = json.loads((ROOT / 'qualification-release-native/environment-before.json').read_text())
    config_same = sha(config_raw) == accepted_environment['workspace/package_config.json']
    workspace_trees = []
    for name in ('quds_mail_transport', 'quds_mail_core', 'quds_mail_mime', 'quds_mail_store', 'quds_mail_ui'):
        old = git('rev-parse', INTEGRATION + ':packages/' + name).decode().strip()
        new = git('rev-parse', MAIN + ':packages/' + name).decode().strip()
        assert old == new
        workspace_trees.append({'name': name, 'tree': new, 'unchanged': True, 'retained_package_config_entry': packages[name]})
    native_plan, native = plan_tests(QUALIFIED, 'docs/validation/office-resume-main-20261119/native-plan.json')
    node_plan, node = plan_tests(QUALIFIED, 'docs/validation/office-resume-main-20261119/node-plan.json')
    removed = sorted(path for path in native if path not in tree(MAIN))
    incoming_tests = sorted(row['path'] for row in net if row['after'] and '/test/' in row['path'] and row['path'].endswith('_test.dart'))
    uncovered = sorted(set(incoming_tests) - set(native))
    real_morph = 'packages/quds_office_editor/example/test/studio_arabic_morph_native_test.dart'
    additions = sorted(set(uncovered) - {real_morph})
    recommended = sorted((set(native) - set(removed)) | set(additions))
    ref_reports = []
    for filename in ('reference-audit-656ff823-before-newmain.json', 'reference-audit-main-666e9a2.json'):
        raw = (ROOT / filename).read_bytes()
        report = json.loads(raw)
        assert report['passed'] and report['actual_reference_count'] == 465
        ref_reports.append({'file': filename, 'sha256': sha(raw), 'target': report['targets'][0], 'actual_reference_count': report['actual_reference_count'], 'classification': report['classification'], 'all_14_historical_equivalences_reverified': report['all_14_historical_equivalences_reverified'], 'unaccounted_refs': report['unaccounted_refs']})
    result = {
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'scope': 'Read-only inventory of the exact new main commit supplied by the parent. No additional branch discovery, remote observations, ref writes, application tests, or CI calls. Existing acceptance remains attributed to 22ffa8bd; no acceptance of 666e9a2 or an uncommitted merge is claimed.',
        'new_bounded_main_head': commit_record(MAIN), 'saved_integration_head': commit_record(INTEGRATION),
        'previous_qualified_source': QUALIFIED,
        'best_common_ancestors': bases, 'common_ancestor_count': len(bases),
        'crisscross_history': len(bases) > 1,
        'base_note': 'There is no unique last common ancestor. The three best merge bases require normal recursive/ort merge treatment; a d00-only delta would mislabel shared e80/2ab work.',
        'new_main_commit_count': len(commits), 'new_main_commits': [commit_record(commit) for commit in commits],
        'net_delta_from_saved_integration': {'count': len(net), 'categories': dict(Counter(row['category'] for row in net)), 'changes': net},
        'main_deltas_from_each_best_common_ancestor': base_rows,
        'dependency_and_runtime': {
            'sole_manifest_delta': manifest_paths[0], 'manifest_patch': dependency_diff,
            'new_declared_edge': 'quds_office_studio -> existing workspace quds_mail_transport',
            'unchanged_root_pins': unchanged, 'mail_workspace_package_trees': workspace_trees,
            'package_config_snapshot_sha256': sha(config_raw), 'package_config_matches_accepted_22_native_receipt': config_same,
            'new_or_modified_dart_package_imports': imports, 'package_imports_missing_from_retained_config': missing,
            'flutter_web_plugins_already_in_retained_config': 'flutter_web_plugins' in packages,
            'runtime_recommendation': 'Preserve prior package_config/package_graph and their hashes, resolve once offline with --enforce-lockfile, retain its raw output and before/after hashes, then bind the resulting runtime to the new frozen source. No changed SDK or package version pin is present in this delta.',
        },
        'followup_plan_scope': {
            'old_native_suite_paths': len(native), 'old_node_suite_paths': len(node),
            'old_native_suites_removed_on_new_main': removed,
            'changed_or_new_tests_not_in_old_native_plan': uncovered,
            'recommended_new_or_changed_native_additions': additions,
            'minimum_migrated_native_suite_count_before_optional_transport_contracts': len(recommended),
            'minimum_migrated_native_suite_paths': recommended,
            'retained_node_suite_paths': node,
            'node_suites_missing_on_main': [path for path in node if path not in tree(MAIN)],
            'recommended_transport_contracts': ['packages/quds_mail_transport/test/configuration_test.dart', 'packages/quds_mail_transport/test/native_provider_test.dart', 'packages/quds_mail_transport/test/uid_discovery_test.dart'],
            'new_real_native_morph_suite_excluded_without_distinct_inputs': {'path': real_morph, 'requires': ['QUDS_ARABIC_MORPH_TEST_LIBRARY', 'QUDS_ARABIC_MORPH_TEST_BUNDLE'], 'reason': 'Explicit real-native acceptance suite skips without both inputs; current three Hunspell lifecycle fixtures do not satisfy it.'},
            'web_widget_scope': 'studio_mail_web_test.dart imports the web widget directly and uses a fake FilePicker; host widget execution does not establish actual browser execution.',
            'static_scope': 'Recompute all changed Dart paths on the resolved new frozen source, explicitly including third_party/enough_mail, modular native/web Mail files, helper/test fixtures, About, Word/Arabic changes and every new selected test. Rerun 21 offline Python controls because the qualified source changes.',
        },
        'merge_attention': [
            'Preserve the 22-source SMTP abort override and withholding-response regression; they are absent on new main because that path did not change there from d00.',
            'New studio_mail_native.dart catches all Object after sendMessage(appendToSent:false) as uncertain; restore typed confirmed-submission cleanup outcome handling before the generic catch.',
            'Do not reuse new-main historical final/plan.json or earlier branch plans as proof of the current modular/reply-forward/read source; the new plan belongs in main-followup/.',
            'Preserve the existing 22-source final reports, plans, raw archive, case inventory and hashes unchanged as source-qualified history.',
        ],
        'validation_evidence_delta_paths': [row for row in net if row['category'] == 'validation_evidence_or_driver'],
        'old_465_reference_capture_audits': ref_reports,
        'additional_fixed_main_head_is_not_a_new_465_advertisement_capture': True,
        'script_sha256': sha(Path(__file__).read_bytes()), 'application_tests_executed': 0, 'github_actions_calls': 0, 'git_ref_mutations': 0,
    }
    output = ROOT / 'concurrent-main-666e9a2-inventory.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'output': str(output), 'new_main': MAIN, 'main_commits': len(commits), 'merge_bases': bases, 'net_delta_paths': len(net), 'sole_manifest_delta': manifest_paths[0], 'missing_runtime_packages': missing, 'removed_old_native_suites': len(removed), 'new_native_additions': len(additions), 'minimum_native_suites': len(recommended), 'node_suites': len(node)}))


if __name__ == '__main__':
    main()
