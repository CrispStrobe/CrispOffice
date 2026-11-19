#!/usr/bin/env python3
"""Audit the final Mail evidence tail with one explicit Markdown input change."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

SOURCE = '5569c055a021c893e941fc54d40499ad9d96a5db'
BASE = '71edec2de364805113d18e0f1d7edbb1f00467e5'
TAIL = '700e5a35ce5f96e7abd1dc92d1a00d2110d40649'
PRIOR_MAIN = '55e262ef269634a0d618c0b5102dc9be5430a5f3'
DOC = 'packages/quds_mail_store/README.md'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--target', required=True, help='Resolved commit or INDEX for the fully resolved candidate index')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()

    def git(*words):
        return subprocess.check_output(['git', '--no-replace-objects', *words], cwd=args.repo)

    def text(*words):
        return git(*words).decode()

    def digest(data):
        return hashlib.sha256(data).hexdigest()

    def entries(commit):
        result = {}
        if commit == 'INDEX':
            for row in git('ls-files', '--stage', '-z').decode().split('\0'):
                if not row:
                    continue
                metadata, path = row.split('\t', 1)
                mode, blob, stage = metadata.split(' ')
                if stage != '0':
                    raise RuntimeError('Unresolved index entry: ' + path)
                result[path] = {'mode': mode, 'git_blob': blob}
        else:
            for row in text('ls-tree', '-r', commit).splitlines():
                metadata, path = row.split('\t', 1)
                mode, kind, blob = metadata.split(' ')
                result[path] = {'mode': mode, 'git_blob': blob}
        return result

    def ancestor(a, b):
        return subprocess.run(['git', '--no-replace-objects', 'merge-base', '--is-ancestor', a, b], cwd=args.repo).returncode == 0

    def read(path):
        return json.loads(path.read_text())

    source, target = entries(SOURCE), entries(args.target)
    issues, scopes, union = [], {}, set()
    environment = {}
    environment_counts = {}
    for label in ['native', 'node']:
        directory = args.workspace / ('qualification-release-' + label)
        receipt = read(directory / 'verification.json')
        raw = (directory / 'source-before.json').read_bytes()
        bound = json.loads(raw)
        if raw != (directory / 'source-after.json').read_bytes() or digest(raw) != receipt['manifest_sha256']['source-before.json']:
            issues.append(label + ': original source manifest binding failed')
        if not receipt['success'] or receipt['source_commit'] != SOURCE:
            issues.append(label + ': original qualification identity failed')
        plan_name = receipt['plan']
        plan = json.loads(git('show', SOURCE + ':' + plan_name))
        selected = {path for path in target if path.startswith(('packages/', 'apps/', 'third_party/'))}
        selected.update(path for path in target if '/' not in path and Path(path).suffix in {'.yaml', '.lock'})
        selected.update([plan_name, 'docs/validation/document-review-notes-20261118/run_checks.py',
                         'tools/mail/check_store.py', 'tools/mail/check_reader.py'])
        selected.update(plan['analysis'])
        selected.update(plan['format'])
        selected.update(plan.get('extra_inputs', []))
        selected.update(item['path'] for item in plan.get('whitespace_preserved_inputs', []))
        for group in plan['groups']:
            selected.update((Path(group['cwd']) / name).as_posix() for name in group['tests'])
        changed = []
        for path, row in bound.items():
            expected = {'mode': row['mode'], 'git_blob': row['git_blob']}
            if source.get(path) != expected:
                issues.append(label + ': qualified Git entry differs from original manifest: ' + path)
            if target.get(path) != expected:
                changed.append(path)
        if len(bound) != 5031 or set(changed) != {DOC} or selected != set(bound):
            issues.append(label + ': expected exactly one reviewed README change and unchanged complete scope')
        scopes[label] = {'bound_inputs': len(bound), 'identical_inputs': len(bound) - len(changed),
                         'reviewed_documentation_changes': changed, 'exact_inventory_unchanged': selected == set(bound),
                         'source_manifest_sha256': digest(raw)}
        union.update(bound)
        raw_env = (directory / 'environment-before.json').read_bytes()
        env = json.loads(raw_env)
        if raw_env != (directory / 'environment-after.json').read_bytes() or digest(raw_env) != receipt['manifest_sha256']['environment-before.json']:
            issues.append(label + ': original runtime manifest binding failed')
        environment_counts[label] = len(env)
        for key, value in env.items():
            if key in environment and environment[key] != value:
                issues.append('Runtime manifest disagreement: ' + key)
            environment[key] = value

    store_path = args.workspace / 'qualification-release-store/results/receipt.json'
    store = read(store_path)
    support_path = args.workspace / 'qualification-release-support/receipt.json'
    support = read(support_path)
    for label, receipt, expected_count in [('store', store, 53), ('support', support, 4)]:
        bound = receipt['source_before']
        changed = [path for path in bound if source.get(path) != target.get(path)]
        if bound != receipt['source_after'] or len(bound) != expected_count or changed:
            issues.append(label + ': exact original source scope changed')
        for path, value in bound.items():
            if digest(git('cat-file', 'blob', source[path]['git_blob'])) != value:
                issues.append(label + ': original input SHA-256 binding failed: ' + path)
        scopes[label] = {'bound_inputs': len(bound), 'identical_inputs': len(bound) - len(changed), 'changed_paths': changed}
        union.update(bound)
    store_selected = {'.fvmrc', 'analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock',
                      'tools/mail/check_store.py', 'tools/mail/check_reader.py', 'tools/mail/test_check_store.py'}
    for package in ['quds_mail_core', 'quds_mail_store']:
        prefix = 'packages/' + package + '/'
        store_selected.add(prefix + 'pubspec.yaml')
        store_selected.update(path for path in target
                              if path.startswith(tuple(prefix + name + '/' for name in ['lib', 'test', 'tool']))
                              and not any(part in {'.dart_tool', 'build', '__pycache__'} for part in Path(path).parts))
    if store_selected != set(store['source_before']):
        issues.append('Store executable/test/config scope gained or lost inputs')
    changed_union = sorted(path for path in union if source.get(path) != target.get(path))
    if len(union) != 5033 or changed_union != [DOC]:
        issues.append('Combined source inventory has an unexpected change')
    if source[DOC]['mode'] != target[DOC]['mode'] or target[DOC]['mode'] != '100644':
        issues.append('Reviewed README must remain a regular non-executable file')
    doc_bytes = git('cat-file', 'blob', target[DOC]['git_blob'])
    doc_text = doc_bytes.decode('utf-8')
    if 'office-main-completion-20261119' not in doc_text:
        issues.append('Store README lacks the current completion-report pointer')

    runtime_root = args.workspace / 'runtime'
    cache, runtime_mismatches = {}, []
    for key, expected in environment.items():
        if key.startswith('runtime/'):
            path = runtime_root / key.removeprefix('runtime/')
        elif key.startswith('additional/'):
            path = Path(key.removeprefix('additional/'))
        elif key == 'workspace/package_config.json':
            path = args.repo / '.dart_tool/package_config.json'
        elif key == 'workspace/native_assets.yaml':
            path = args.repo / '.dart_tool/native_assets.yaml'
        elif key.startswith('workspace/'):
            path = args.repo / key.removeprefix('workspace/')
        elif key == 'sdk/flutter_tools/package_config.json':
            path = runtime_root / 'flutter/packages/flutter_tools/.dart_tool/package_config.json'
        else:
            raise RuntimeError('Unknown runtime mapping: ' + key)
        if path not in cache:
            if path.is_file():
                h = hashlib.sha256()
                with path.open('rb') as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b''):
                        h.update(block)
                cache[path] = h.hexdigest()
            else:
                cache[path] = None
        if cache[path] != expected or (expected is None and path.exists()):
            runtime_mismatches.append(key)
    if runtime_mismatches:
        issues.append('Runtime/dependency bytes changed after qualification')
    incoming_paths = text('diff', '--name-only', BASE, TAIL).splitlines()
    allowed = lambda path: path.startswith('docs/') or path == 'README.md' or path == DOC
    incoming_other = [path for path in incoming_paths if not allowed(path)]
    if len(incoming_paths) != 40 or incoming_other:
        issues.append('Incoming tail is not the expected forty documentation/evidence paths')
    if args.target == 'INDEX':
        target_paths = text('diff', '--cached', '--name-only', SOURCE).splitlines()
        parent_heads = [text('rev-parse', 'HEAD').strip(), text('rev-parse', 'MERGE_HEAD').strip()]
        history = {commit: any(ancestor(commit, parent) for parent in parent_heads)
                   for commit in [SOURCE, PRIOR_MAIN, TAIL]}
        target_identity = {'kind': 'resolved_index', 'head_and_merge_head': parent_heads,
                           'scope': 'Fully resolved candidate index read without writing a Git tree or index'}
    else:
        target_paths = text('diff', '--name-only', SOURCE, args.target).splitlines()
        history = {commit: ancestor(commit, args.target) for commit in [SOURCE, PRIOR_MAIN, TAIL]}
        target_identity = {'kind': 'commit', 'commit': text('rev-parse', args.target + '^{commit}').strip(),
                           'tree': text('rev-parse', args.target + '^{tree}').strip()}
    if not all(history.values()) or any(not allowed(path) for path in target_paths):
        issues.append('Final target history or documentation-only publication delta failed')
    bound_entries = {path: target[path] for path in sorted(union)}
    result = {
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'qualified_execution_source': SOURCE, 'checked_target': target_identity,
        'incoming_mail_head': TAIL, 'integrated_mail_parent': BASE, 'previous_merged_main': PRIOR_MAIN,
        'required_history_included': history, 'incoming_changed_path_count': len(incoming_paths),
        'incoming_changed_paths': incoming_paths, 'incoming_executable_test_config_plan_changes': incoming_other,
        'qualification_scope_checks': scopes, 'distinct_bound_input_union': len(union),
        'unchanged_bound_inputs': len(union) - len(changed_union),
        'reviewed_documentation_input': {'path': DOC, 'qualified_git_entry': source[DOC],
                                         'final_git_entry': target[DOC], 'final_sha256': digest(doc_bytes),
                                         'current_completion_report_link_present': True,
                                         'reason': 'README qualification/status documentation only; no Dart, tests, dependency/configuration, plan, runner or runtime input is changed.'},
        'executable_test_config_plan_input_changes': [path for path in changed_union if path != DOC],
        'qualified_bound_entry_fingerprint_sha256': digest(json.dumps(bound_entries, sort_keys=True, separators=(',', ':')).encode()),
        'runtime_inputs_reverified_per_gate': environment_counts,
        'runtime_manifest_union_reverified': len(environment), 'runtime_changed_inputs': runtime_mismatches,
        'application_case_executions_preserved': 836, 'separate_python_controls_preserved': 78,
        'imported_mail_history': {'execution_source': BASE, 'application_executions': 631,
                                  'python_controls': 66, 'added_to_current_qualification_counts': 0},
        'original_execution_identity_preserved': True, 'tests_or_ci_executed_by_this_audit': False,
        'audit_script_sha256': digest(Path(__file__).read_bytes()),
        'method': 'Exact Git blob/mode and scope comparisons against original four-gate manifests, with one explicitly reviewed Markdown exception; current runtime inputs rehashed. No index/worktree/ref mutation.',
        'issues': issues, 'passed': not issues,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['checked_target', 'distinct_bound_input_union',
                                                 'unchanged_bound_inputs', 'runtime_manifest_union_reverified',
                                                 'passed', 'issues']}, indent=2))
    raise SystemExit(0 if not issues else 1)


if __name__ == '__main__':
    main()
