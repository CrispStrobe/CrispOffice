#!/usr/bin/env python3
"""Check exact qualified input continuity across documentation publication/merge."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--incoming-main', required=True)
    parser.add_argument('--common-base', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()

    def git(*words):
        return subprocess.check_output(['git', '--no-replace-objects', *words], cwd=args.repo)

    def text(*words):
        return git(*words).decode()

    def tree(commit):
        entries = {}
        for line in text('ls-tree', '-r', commit).splitlines():
            metadata, path = line.split('\t', 1)
            mode, kind, blob = metadata.split(' ')
            entries[path] = {'mode': mode, 'type': kind, 'git_blob': blob}
        return entries

    def digest(data):
        return hashlib.sha256(data).hexdigest()

    source_tree, target_tree = tree(args.source), tree(args.target)
    base_tree, incoming_tree = tree(args.common_base), tree(args.incoming_main)
    issues, gates, union = [], {}, set()
    runner = 'docs/validation/document-review-notes-20261118/run_checks.py'
    for label in ['native', 'node']:
        directory = args.workspace / ('qualification-release-' + label)
        before_raw = (directory / 'source-before.json').read_bytes()
        after_raw = (directory / 'source-after.json').read_bytes()
        manifest = json.loads(before_raw)
        receipt = json.loads((directory / 'verification.json').read_text())
        if before_raw != after_raw or digest(before_raw) != receipt['manifest_sha256']['source-before.json']:
            issues.append(label + ': original manifest/receipt mismatch')
        if not receipt['success'] or receipt['source_commit'] != args.source:
            issues.append(label + ': qualification identity mismatch')
        plan_name = receipt['plan']
        plan = json.loads(git('show', args.source + ':' + plan_name))
        selected = {path for path in target_tree if path.startswith(('packages/', 'apps/', 'third_party/'))}
        selected.update(path for path in target_tree if '/' not in path and Path(path).suffix in {'.yaml', '.lock'})
        selected.update([plan_name, runner, 'tools/mail/check_store.py', 'tools/mail/check_reader.py'])
        selected.update(plan['analysis'])
        selected.update(plan['format'])
        selected.update(plan.get('extra_inputs', []))
        selected.update(item['path'] for item in plan.get('whitespace_preserved_inputs', []))
        for group in plan['groups']:
            selected.update((Path(group['cwd']) / path).as_posix() for path in group['tests'])
        mismatches = []
        for path, bound in manifest.items():
            expected = {'mode': bound['mode'], 'type': 'blob', 'git_blob': bound['git_blob']}
            if source_tree.get(path) != expected or target_tree.get(path) != expected:
                mismatches.append(path)
        added, removed = sorted(selected - set(manifest)), sorted(set(manifest) - selected)
        if mismatches or added or removed:
            issues.append(label + ': qualified input tree/scope changed')
        gates[label] = {'bound_inputs': len(manifest), 'source_manifest_sha256': digest(before_raw),
                        'qualification_receipt_sha256': digest((directory / 'verification.json').read_bytes()),
                        'all_modes_and_blobs_identical': not mismatches, 'mismatched_paths': mismatches,
                        'added_scoped_inputs': added, 'removed_scoped_inputs': removed,
                        'exact_scope_unchanged': not added and not removed}
        union.update(manifest)

    store_directory = args.workspace / 'qualification-release-store/results'
    store_receipt = json.loads((store_directory / 'receipt.json').read_text())
    store_bound = store_receipt['source_before']
    store_expected = {'.fvmrc', 'analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock',
                      'tools/mail/check_store.py', 'tools/mail/check_reader.py', 'tools/mail/test_check_store.py'}
    for package in ['quds_mail_core', 'quds_mail_store']:
        prefix = 'packages/' + package + '/'
        store_expected.add(prefix + 'pubspec.yaml')
        store_expected.update(path for path in target_tree
                              if path.startswith(tuple(prefix + item + '/' for item in ['lib', 'test', 'tool']))
                              and not any(part in {'.dart_tool', 'build', '__pycache__'} for part in Path(path).parts))
    store_changed = [path for path in store_bound if source_tree.get(path) != target_tree.get(path)]
    if store_changed or set(store_bound) != store_expected or store_bound != store_receipt['source_after']:
        issues.append('store: qualified input tree/scope changed')
    gates['store'] = {'bound_inputs': len(store_bound), 'all_modes_and_blobs_identical': not store_changed,
                      'mismatched_paths': store_changed, 'exact_scope_unchanged': set(store_bound) == store_expected,
                      'qualification_receipt_sha256': digest((store_directory / 'receipt.json').read_bytes())}
    union.update(store_bound)
    support_path = args.workspace / 'qualification-release-support/receipt.json'
    support = json.loads(support_path.read_text())
    support_changed = [path for path in support['source_before'] if source_tree.get(path) != target_tree.get(path)]
    if support_changed or support['source_commit'] != args.source or not support['success']:
        issues.append('support: qualified input identity changed')
    gates['support'] = {'bound_inputs': len(support['source_before']),
                        'all_modes_and_blobs_identical': not support_changed, 'mismatched_paths': support_changed,
                        'qualification_receipt_sha256': digest(support_path.read_bytes())}
    union.update(support['source_before'])
    for path in union:
        bound_sha = (store_bound.get(path) or support['source_before'].get(path))
        if bound_sha and digest(git('show', args.source + ':' + path)) != bound_sha:
            issues.append('Supplemental source SHA-256 mismatch: ' + path)

    incoming_paths = text('diff', '--name-only', args.common_base, args.incoming_main).splitlines()
    target_paths = text('diff', '--name-only', args.source, args.target).splitlines()
    incoming_touches_inputs = sorted(set(incoming_paths) & union)
    target_touches_inputs = sorted(set(target_paths) & union)
    if incoming_touches_inputs or target_touches_inputs:
        issues.append('Incoming or publication delta changes a qualified input')
    allowed_documentation = lambda path: path == 'README.md' or path.startswith('docs/')
    incoming_other = [path for path in incoming_paths if not allowed_documentation(path)]
    target_other = [path for path in target_paths if not allowed_documentation(path)]
    if incoming_other or target_other:
        issues.append('Unexpected non-documentation publication delta')
    incoming_bound_delta = [path for path in union if base_tree.get(path) != incoming_tree.get(path)]
    if incoming_bound_delta:
        issues.append('Incoming main changed a bound input relative to common ancestor')
    is_incoming_ancestor = subprocess.run(['git', '--no-replace-objects', 'merge-base', '--is-ancestor',
                                          args.incoming_main, args.target], cwd=args.repo).returncode == 0
    result = {
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'qualified_source_commit': args.source, 'qualified_source_tree': text('rev-parse', args.source + '^{tree}').strip(),
        'checked_publication_commit': args.target, 'checked_publication_tree': text('rev-parse', args.target + '^{tree}').strip(),
        'incoming_main_commit': args.incoming_main, 'incoming_main_tree': text('rev-parse', args.incoming_main + '^{tree}').strip(),
        'incoming_main_parents': text('show', '-s', '--format=%P', args.incoming_main).split(),
        'common_ancestor': args.common_base,
        'incoming_main_is_ancestor_of_checked_publication': is_incoming_ancestor,
        'actual_merge_tree_verified': is_incoming_ancestor,
        'qualification_gate_input_checks': gates, 'distinct_bound_input_union': len(union),
        'incoming_main_changed_paths_since_common_ancestor': incoming_paths,
        'incoming_main_delta_bound_input_changes': incoming_bound_delta,
        'publication_changed_paths_since_qualification': target_paths,
        'publication_bound_input_changes': target_touches_inputs,
        'incoming_delta_documentation_and_evidence_only': not incoming_other,
        'publication_delta_documentation_and_evidence_only': not target_other,
        'original_execution_identity_preserved': True,
        'new_product_test_execution_required_for_this_delta': bool(issues),
        'method': 'Immutable Git tree/mode/blob comparison against all four original qualification manifests. Gate inventories remain unchanged; no original execution is relabeled. No tests, CI, index or worktree writes.',
        'audit_script_sha256': digest(Path(__file__).read_bytes()),
        'issues': issues, 'passed': not issues,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['checked_publication_commit', 'incoming_main_commit',
                                                 'actual_merge_tree_verified', 'distinct_bound_input_union',
                                                 'incoming_delta_documentation_and_evidence_only',
                                                 'publication_delta_documentation_and_evidence_only', 'passed', 'issues']}, indent=2))
    raise SystemExit(0 if not issues else 1)


if __name__ == '__main__':
    main()
