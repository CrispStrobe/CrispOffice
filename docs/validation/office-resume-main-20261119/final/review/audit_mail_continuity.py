#!/usr/bin/env python3
"""Read-only Mail source continuity review; never executes product tests."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone

SCOPES = [
    'packages/quds_mail_core', 'packages/quds_mail_store',
    'packages/quds_mail_transport', 'packages/quds_mail_mime',
    'packages/quds_mail_ui', 'third_party/enough_mail',
]
CAPTURED_MAIN = 'b070e228a749e22cc8ce2098029a76ab5fb8eccb'
QUALIFIED_29DD = '29dd23a6edd0a0fbb916b3d9f73861a8aa4f435e'
QUALIFIED_5C18 = '5c18db77505f876bf70bf7e89c49e8c3b617e0d4'
CONSUMERS = [
    'packages/quds_office_editor/example/lib/studio_mail.dart',
    'packages/quds_office_editor/example/test/studio_mail_test.dart',
    'packages/quds_office_editor/example/test/studio_mail_lifecycle_test.dart',
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git_blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--target', default='worktree')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()

    def git(*cmd):
        return subprocess.check_output(['git', '-C', str(repo), *cmd])

    def tree(ref, paths=SCOPES):
        result = {}
        for entry in git('ls-tree', '-rz', ref, '--', *paths).split(b'\0'):
            if not entry:
                continue
            meta, path = entry.split(b'\t', 1)
            mode, kind, oid = meta.decode().split()
            result[path.decode()] = dict(mode=mode, kind=kind, git_blob=oid)
        return result

    def changes(left, right):
        return [dict(path=path, before=left.get(path), after=right.get(path))
                for path in sorted(left.keys() | right.keys())
                if left.get(path) != right.get(path)]

    def tree_digest(value):
        return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())

    old, current_main, prior_delta = (tree(ref) for ref in [QUALIFIED_29DD, CAPTURED_MAIN, QUALIFIED_5C18])
    untracked = []
    if args.target == 'worktree':
        target = {}
        tracked = set(git('ls-files', '-z', '--', *SCOPES).decode().split('\0')) - {''}
        untracked = sorted(set(git('ls-files', '--others', '--exclude-standard', '-z', '--', *SCOPES).decode().split('\0')) - {''})
        for name in sorted(tracked):
            path = repo / name
            if not path.exists() and not path.is_symlink():
                continue
            if path.is_symlink():
                data, mode = os.readlink(path).encode(), '120000'
            else:
                data = path.read_bytes()
                mode = '100755' if path.stat().st_mode & 0o111 else '100644'
            target[name] = dict(mode=mode, kind='blob', git_blob=git_blob(data))
        target_id = 'working tree reviewed; not a frozen qualification'
        def read_target(path):
            return (repo/path).read_bytes()
    else:
        target_id = git('rev-parse', args.target).decode().strip()
        target = tree(target_id)
        def read_target(path):
            return git('show', target_id + ':' + path)

    historic_path = 'docs/validation/office-main-integration-20261119/host-final/host_mail_continuity.json'
    historic_bytes = (repo / historic_path).read_bytes()
    historic = json.loads(historic_bytes)
    records = historic['final_mail_package_inventory']
    historic_errors = []
    if historic['qualified_source'] != QUALIFIED_29DD:
        historic_errors.append('Historical qualified source mismatch')
    if {r['path'] for r in records} != set(old):
        historic_errors.append('Historical inventory path set mismatch')
    requests = ''.join(r['git_blob'] + '\n' for r in records).encode()
    batch = subprocess.run(['git', '-C', str(repo), 'cat-file', '--batch'], input=requests,
                           stdout=subprocess.PIPE, check=True).stdout
    offset = 0
    for record in records:
        end = batch.index(b'\n', offset)
        header = batch[offset:end].decode().split()
        offset = end + 1
        if len(header) != 3 or header[1] != 'blob':
            raise RuntimeError('Bad cat-file batch response: ' + repr(header))
        size = int(header[2]); data = batch[offset:offset+size]; offset += size + 1
        if old.get(record['path']) != {k: record[k] for k in ('mode','kind','git_blob')}:
            historic_errors.append('Historical Git identity differs: ' + record['path'])
        if digest(data) != record['sha256']:
            historic_errors.append('Historical content SHA-256 differs: ' + record['path'])

    per_scope = []
    for scope in SCOPES:
        narrow = lambda value: {k:v for k,v in value.items() if k.startswith(scope + '/')}
        native = lambda value: {k:v for k,v in narrow(value).items() if '/lib/' in k}
        per_scope.append(dict(
            path=scope,
            historical_records=len(narrow(old)),
            current_main_records=len(narrow(current_main)),
            target_records=len(narrow(target)),
            identical_to_captured_main=narrow(current_main) == narrow(target),
            library_identical_to_29dd=native(old) == native(target),
            changes_since_29dd=changes(narrow(old), narrow(target)),
        ))

    current_changes = changes(current_main, target)
    old_changes = changes(old, target)
    prior_changes = changes(prior_delta, target)
    office_imports = []
    for path in sorted(target):
        if not path.endswith('.dart'):
            continue
        for uri in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", read_target(path).decode(errors='replace')):
            if uri.startswith(('package:quds_office_', 'package:quds_proofing_', 'package:quds_arabic_morph/')):
                office_imports.append(dict(path=path, uri=uri))

    config_comparison = []
    for path in ['analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock']:
        data = read_target(path)
        config_comparison.append(dict(path=path, target_sha256=digest(data),
            identical_to_captured_main=data == git('show', CAPTURED_MAIN + ':' + path),
            identical_to_29dd=data == git('show', QUALIFIED_29DD + ':' + path)))

    consumers = [dict(path=path, sha256=digest(read_target(path)),
                      differs_from_captured_main=read_target(path) != git('show', CAPTURED_MAIN + ':' + path)) for path in CONSUMERS]
    result = dict(
        schema=1,
        reviewed_at_utc=datetime.now(timezone.utc).isoformat(),
        method='Git mode/type/blob and actual content checks. Static review only; no product tests or runtime qualification executed.',
        target=target_id,
        observed_head=git('rev-parse','HEAD').decode().strip(),
        captured_main=CAPTURED_MAIN,
        qualified_historical_source=QUALIFIED_29DD,
        qualified_prior_delta_source=QUALIFIED_5C18,
        mail_scope_unchanged_from_captured_main=not current_changes and not untracked,
        main_delta=current_changes,
        untracked_mail_scope_files=untracked,
        historical_manifest_records_verified=len(records),
        historical_manifest_errors=historic_errors,
        historical_manifest=dict(path=historic_path, sha256=digest(historic_bytes)),
        inventory_counts=dict(historical_29dd=len(old), captured_main=len(current_main), current_target=len(target)),
        inventory_sha256=dict(historical_29dd=tree_digest(old), captured_main=tree_digest(current_main), current_target=tree_digest(target)),
        per_scope=per_scope,
        changes_since_29dd=old_changes,
        changes_since_5c18=prior_changes,
        office_imports_from_mail_scope=office_imports,
        root_config=config_comparison,
        current_consumer_files=consumers,
        implementation_review=[
            'Captured main already contains functional IMAP/SMTP Mail. The merged Studio implementation adds mounted/session-generation/client guards, failed-candidate cleanup, quiet asynchronous disconnect, safe reader retirement and empty-sender handling.',
            'The sole test merge conflict preserves current-client lifecycle cases and incoming full English/German/Arabic language cycle; obsolete saved-message picker assertions are adapted to account setup.',
            'A separate unchanged main lifecycle test still targeted the removed picker UI. It is reconciled to closing while a second message fetch is pending, preserving initial-reader disposal and rejecting a late fetch result.',
            'Core/store/MIME/UI and enough_mail library source remain identical to 29dd. Transport differs only in cursor.dart and native/provider.dart: v3 page revisions prevent stale completed sweeps from reusing a committed cursor token.',
            'Current transport code and tests already match the audited 5c18db77 Mail cohort. Differences from that full Mail file scope are store README and Mail UI analysis_options.yaml; no application or test source differs.',
        ],
        fresh_delta_validation=dict(
            required_studio_suites=CONSUMERS[1:],
            reason='These are the two Mail consumers changed by this merge relative to captured main; no Mail package implementation changes occur in the merge.',
            focused_transport_confirmation_if_selected=[
                dict(path='packages/quds_mail_transport/test/cursor_test.dart',platforms=['vm','node']),
                dict(path='packages/quds_mail_transport/test/uid_discovery_test.dart',platforms=['vm']),
                dict(path='packages/quds_mail_transport/test/host_store_integration_test.dart',platforms=['vm']),
            ],
            no_broad_rerun_needed_for_source_delta='There is no new source risk requiring all unchanged core/store/TLS/IMAP/POP/SMTP suites to repeat solely for this merge.',
        ),
        retained_evidence=dict(
            host_final='394 unchanged records is valid for 9833831a compared with 29dd23a6, not for captured current main. Keep the original statement source-bound.',
            main_delta_v4_path='docs/validation/office-main-sync-20261119/main-delta-v4/final/independent-summary.json',
            main_delta_v4_mail_cohorts='50 cases across four VM suites; 17 repeats across two Node suites. Existing source-bound evidence, not new executions in this audit.',
            previous_counts_added_to_fresh_tests=0,
            current_runtime_checked=False,
        ),
        acceptance_limits=['No live mail-provider session','No installed-app or cross-platform acceptance','No current runtime test execution by this audit'],
        github_actions='NOT QUERIED OR AWAITED',
    )
    result['review_checks_passed'] = not historic_errors and not current_changes and not untracked and not office_imports
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False)+'\n')
    print(json.dumps({k: result[k] for k in ['review_checks_passed','target','inventory_counts','mail_scope_unchanged_from_captured_main','historical_manifest_records_verified']}))
    if not result['review_checks_passed']:
        raise SystemExit(1)

if __name__ == '__main__':
    main()
