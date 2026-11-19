#!/usr/bin/env python3
"""Prove accepted qualification inputs reach a later publication commit unchanged.

Only immutable Git objects and completed receipts/audits are read. The candidate
must descend from the qualified commit. Direct final/ evidence additions, four
exactly pinned audit scripts, and the validation README may differ. This does
not run tests, fetch objects, update refs, or expand the original test coverage.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess

RUNNER = 'docs/validation/document-review-notes-20261118/run_checks.py'
PYTHON_DRIVER = 'docs/validation/office-resume-main-20261119/run_python_controls.py'
EVIDENCE_PREFIX = 'docs/validation/office-resume-main-20261119/'
FINAL_PREFIX = EVIDENCE_PREFIX + 'main-followup/final/'
DOCUMENT_PATH = EVIDENCE_PREFIX + 'README.md'
CODE_NAMES = {'audit_fresh_gate.py', 'audit_python_controls.py',
              'audit_publication_continuity.py', 'archive_evidence.py'}
INERT_SUFFIXES = {'.json', '.jsonl', '.md', '.txt', '.log', '.xz', '.gz', '.csv', '.tsv', '.png', '.pdf'}
CONFIG_NAMES = {'package.json', 'package-lock.json', 'npm-shrinkwrap.json',
                'tsconfig.json', 'jsconfig.json', 'deno.json', 'composer.json',
                'launch.json', 'settings.json', 'project.json', 'package_config.json'}
REGULAR_MODES = {'100644', '100755'}


def check(value: object, detail: str) -> None:
    if not value:
        raise AssertionError(detail)


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def allowed_unbound_delta(path: str, before: dict | None, after: dict | None) -> str | None:
    """Bound paths are checked first by the caller and never enter this allowlist."""
    if after is None or after['kind'] != 'blob' or after['mode'] not in REGULAR_MODES:
        return None
    if before is not None and (before['kind'] != 'blob' or before['mode'] != after['mode']):
        return None
    if path == DOCUMENT_PATH and before is not None:
        return 'validation_readme_update'
    relative = path.removeprefix(FINAL_PREFIX)
    if before is None and path.startswith(FINAL_PREFIX) and '/' not in relative and not relative.startswith('.'):
        if relative in CODE_NAMES:
            return 'exact_pinned_audit_script_addition'
        if after['mode'] == '100644' and relative not in CONFIG_NAMES and PurePosixPath(relative).suffix in INERT_SUFFIXES:
            return 'new_inert_final_evidence'
    return None


def policy_controls() -> int:
    regular = {'mode': '100644', 'kind': 'blob', 'blob': 'a' * 40}
    executable = {**regular, 'mode': '100755'}
    symlink = {**regular, 'mode': '120000'}
    cases = [
        ('packages/new_product/lib.dart', None, regular, False),
        ('apps/existing/new-config.json', None, regular, False),
        ('third_party/new_package/pubspec.yaml', None, regular, False),
        ('tools/new_tool.py', None, regular, False),
        ('new-root-config.yml', None, regular, False),
        ('.gitignore', regular, regular, False),
        ('.github/new-config.json', None, regular, False),
        (FINAL_PREFIX + 'new-report.json', None, regular, True),
        (EVIDENCE_PREFIX + 'old-archive.tar.xz', regular, regular, False),
        (EVIDENCE_PREFIX + 'new-script.sh', None, executable, False),
        (EVIDENCE_PREFIX + 'new-link.md', None, symlink, False),
        (DOCUMENT_PATH, regular, regular, True),
        (DOCUMENT_PATH, regular, executable, False),
        (DOCUMENT_PATH, regular, None, False),
        ('README.md', regular, regular, False),
        (EVIDENCE_PREFIX + 'json.py', None, regular, False),
        (FINAL_PREFIX + 'json.py', None, regular, False),
        (FINAL_PREFIX + 'json.pyc', None, regular, False),
        (FINAL_PREFIX + '__pycache__/json.pyc', None, regular, False),
        (FINAL_PREFIX + 'package.json', None, regular, False),
        (FINAL_PREFIX + 'analysis_options.yaml', None, regular, False),
        (FINAL_PREFIX + 'nested/report.json', None, regular, False),
        (FINAL_PREFIX + 'audit_fresh_gate.py', None, regular, True),
    ]
    for path, before, after, expected in cases:
        check(bool(allowed_unbound_delta(path, before, after)) == expected, 'policy control: ' + path)
    return len(cases)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path)
    parser.add_argument('--source')
    parser.add_argument('--candidate')
    parser.add_argument('--native', type=Path)
    parser.add_argument('--node', type=Path)
    parser.add_argument('--python', type=Path, dest='python_evidence')
    parser.add_argument('--dart-audit', type=Path)
    parser.add_argument('--python-audit', type=Path)
    parser.add_argument('--archive-script', type=Path, help='Trusted local archive_evidence.py whose exact bytes may be published in final/. Required if that file is added.')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps({'policy_controls': policy_controls(), 'application_tests_executed': 0, 'qualification_claim': False}))
        return 0
    for name in ('repo', 'source', 'candidate', 'native', 'node', 'python_evidence', 'dart_audit', 'python_audit', 'output'):
        if getattr(args, name) is None:
            parser.error('--' + name.replace('_', '-') + ' is required')
    repo = args.repo.resolve()
    check(not args.output.resolve().is_relative_to(repo), 'Write the report outside the source checkout')
    command = ['git', '--no-lazy-fetch', '--no-replace-objects', '-C', str(repo)]
    environment = {**os.environ, 'GIT_OPTIONAL_LOCKS': '0'}

    def git(*values: str) -> bytes:
        return subprocess.check_output([*command, *values], env=environment)

    def resolve(value: str) -> str:
        return git('rev-parse', '--verify', '--end-of-options', value + '^{commit}').decode().strip()

    def tree(commit: str) -> dict:
        result = {}
        for item in git('ls-tree', '-r', '-z', commit).split(b'\0'):
            if item:
                fields, path = item.split(b'\t', 1)
                mode, kind, blob = fields.decode().split()
                result[path.decode()] = {'mode': mode, 'kind': kind, 'blob': blob}
        return result

    source, candidate = resolve(args.source), resolve(args.candidate)
    source_tree, candidate_tree = tree(source), tree(candidate)
    source_tree_id = git('rev-parse', source + '^{tree}').decode().strip()
    candidate_tree_id = git('rev-parse', candidate + '^{tree}').decode().strip()
    violations = []
    ancestor = subprocess.run([*command, 'merge-base', '--is-ancestor', source, candidate], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    check(ancestor.returncode in (0, 1), 'Candidate ancestry lookup failed')
    if ancestor.returncode != 0:
        violations.append({'kind': 'qualified_source_not_ancestor', 'source': source, 'candidate': candidate})

    def read_audit(path: Path, flag: str) -> tuple[dict, dict]:
        raw = path.read_bytes()
        data = json.loads(raw)
        check(data.get(flag) is True and data.get('source_commit') == source and data.get('source_tree') == source_tree_id, 'Acceptance audit source/result mismatch: ' + str(path))
        return data, {'file': str(path.resolve()), 'sha256': digest(raw)}

    dart_audit, dart_audit_pin = read_audit(args.dart_audit, 'passed')
    python_audit, python_audit_pin = read_audit(args.python_audit, 'all_passed')
    check(dart_audit.get('node_phase_included') is True and dart_audit.get('other_source_or_rejected_case_contribution') == 0, 'Both current-source Dart phases required')
    code_pins = {
        FINAL_PREFIX + 'audit_fresh_gate.py': dart_audit['script_sha256'],
        FINAL_PREFIX + 'audit_python_controls.py': python_audit['script_sha256'],
        FINAL_PREFIX + 'audit_publication_continuity.py': digest(Path(__file__).read_bytes()),
    }
    if args.archive_script:
        code_pins[FINAL_PREFIX + 'archive_evidence.py'] = digest(args.archive_script.read_bytes())
    phases = {row['phase']: row for row in dart_audit['phases']}
    check(set(phases) == {'native', 'node'} and len(dart_audit['phases']) == 2, 'Exactly two independent Dart phases required')
    manifests = {}
    receipts = []
    memberships = []

    def changed(commit: str, base: str) -> list[str]:
        return [path for path in git('diff', '--name-only', '--diff-filter=ACMRT', '-z', base, commit, '--').decode().split('\0') if path.endswith('.dart') and path.startswith(('packages/', 'apps/'))]

    def dart_inputs(entries: dict, plan: dict, plan_path: str, changes: list[str]) -> set[str]:
        selected = {path for path in entries if path.startswith(('packages/', 'apps/', 'third_party/'))}
        selected |= {path for path in entries if '/' not in path and Path(path).suffix in {'.yaml', '.lock'}}
        selected |= {plan_path, RUNNER, 'tools/mail/check_store.py', 'tools/mail/check_reader.py'}
        selected |= set(plan.get('extra_inputs', []))
        selected |= {row['path'] for row in plan.get('whitespace_preserved_inputs', [])}
        for group in plan['groups']:
            selected |= {(PurePosixPath(group['cwd']) / path).as_posix() for path in group['tests']}
        for category in ('analysis', 'format'):
            selection = plan.get(category, 'changed')
            selected |= set(changes if selection == 'changed' else selection)
        return selected

    def add_pin(path: str, mode: str, blob: str, sha256: str, owner: str) -> None:
        pin = {'mode': mode, 'kind': 'blob', 'git_blob': blob, 'sha256': sha256}
        if path in manifests:
            check({k: manifests[path][k] for k in pin} == pin, 'Cross-phase source pin mismatch: ' + path)
            manifests[path]['owners'].append(owner)
        else:
            manifests[path] = {**pin, 'owners': [owner]}

    for label, folder in (('native', args.native), ('node', args.node)):
        raw = (folder / 'verification.json').read_bytes()
        receipt = json.loads(raw)
        check(digest(raw) == phases[label]['verification_sha256'], 'Recounted receipt bytes changed: ' + label)
        check(receipt.get('success') is True and receipt.get('finished_at_utc') and receipt['source_commit'] == source and receipt['source_tree'] == source_tree_id, 'Completed accepted source required: ' + label)
        for field in ('source_unchanged', 'environment_unchanged', 'source_head_unchanged', 'source_index_unchanged', 'tracked_worktree_clean_before', 'tracked_worktree_clean_after'):
            check(receipt.get(field) is True, 'Receipt invariant: ' + field)
        check(receipt['passed'] == phases[label]['passed_executions'] and not receipt['failed'] and not receipt['skipped'], 'Recount totals mismatch: ' + label)
        for name, sha256 in receipt['manifest_sha256'].items():
            check(digest((folder / name).read_bytes()) == sha256, 'Manifest changed: ' + label + '/' + name)
        before = (folder / 'source-before.json').read_bytes()
        check(before == (folder / 'source-after.json').read_bytes(), 'Source changed during accepted run')
        check((folder / 'environment-before.json').read_bytes() == (folder / 'environment-after.json').read_bytes(), 'Runtime changed during accepted run')
        entries = json.loads(before)
        check(len(entries) == receipt['source_input_count'] == receipt['materialized_source_inputs'] and not receipt['sparse_source_omissions'], 'Incomplete source manifest')
        plan_raw = git('show', source + ':' + receipt['plan'])
        check(digest(plan_raw) == receipt['plan_sha256'], 'Source plan changed')
        plan = json.loads(plan_raw)
        check(plan['groups'] == receipt['planned_groups'], 'Accepted plan group mismatch')
        expected_source = dart_inputs(source_tree, plan, receipt['plan'], changed(source, receipt['source_base']))
        expected_candidate = dart_inputs(candidate_tree, plan, receipt['plan'], changed(candidate, receipt['source_base']))
        check(set(entries) == expected_source, 'Accepted source membership does not match pinned plan: ' + label)
        if expected_candidate != expected_source:
            violations.append({'kind': 'candidate_dart_input_membership_changed', 'phase': label, 'added': sorted(expected_candidate - expected_source), 'removed': sorted(expected_source - expected_candidate)})
        for path, row in entries.items():
            check(row.get('materialized') is True and row.get('sparse_omission') is False, 'Unmaterialized input: ' + path)
            add_pin(path, row['mode'], row['git_blob'], row['sha256'], label)
        memberships.append({'phase': label, 'source_count': len(expected_source), 'candidate_count': len(expected_candidate), 'same_membership': expected_source == expected_candidate})
        receipts.append({'phase': label, 'file': str((folder / 'verification.json').resolve()), 'sha256': digest(raw)})

    def python_inputs(entries: dict) -> set[str]:
        selected = {PYTHON_DRIVER, 'tools/mail/check_store.py', 'tools/mail/check_reader.py', 'packages/quds_proofing_hunspell/tool/build.py', 'packages/quds_proofing_hunspell/tool/test_build.py', 'packages/quds_proofing_hunspell/LICENSE'}
        selected |= {path for path in entries if path.startswith('tools/proofing/ayaspell/') and path.endswith('.py')}
        selected |= {path for path in entries if path.startswith('packages/quds_proofing_hunspell/licenses/')}
        return selected

    raw = (args.python_evidence / 'verification.json').read_bytes()
    receipt = json.loads(raw)
    check(digest(raw) == python_audit['receipt_sha256'], 'Independently recounted Python receipt changed')
    check(receipt.get('success') is True and receipt.get('finished_at_utc') and receipt['source_commit'] == source and receipt['source_tree'] == source_tree_id, 'Completed accepted Python source required')
    for field in ('source_unchanged', 'runtime_unchanged', 'source_head_unchanged', 'source_index_unchanged', 'tracked_worktree_clean_after'):
        check(receipt.get(field) is True, 'Python invariant: ' + field)
    check(receipt['source_before'] == receipt['source_after'] and receipt['runtime_before'] == receipt['runtime_after'], 'Python source/runtime manifests changed')
    check(receipt['passed'] == python_audit['passed'], 'Independent Python count mismatch')
    expected_source = python_inputs(source_tree)
    expected_candidate = python_inputs(candidate_tree)
    check(set(receipt['source_before']) == expected_source, 'Complete Python source closure required')
    if expected_candidate != expected_source:
        violations.append({'kind': 'candidate_python_input_membership_changed', 'added': sorted(expected_candidate - expected_source), 'removed': sorted(expected_source - expected_candidate)})
    for path, row in receipt['source_before'].items():
        add_pin(path, source_tree[path]['mode'], row['git_blob'], row['sha256'], 'python')
    memberships.append({'phase': 'python', 'source_count': len(expected_source), 'candidate_count': len(expected_candidate), 'same_membership': expected_source == expected_candidate})
    receipts.append({'phase': 'python', 'file': str((args.python_evidence / 'verification.json').resolve()), 'sha256': digest(raw)})

    hashes = {}
    process = subprocess.Popen([*command, 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=environment)
    for blob in sorted({row['git_blob'] for row in manifests.values()}):
        process.stdin.write((blob + '\n').encode()); process.stdin.flush()
        header = process.stdout.readline().decode().strip().split()
        check(len(header) == 3 and header[0] == blob and header[1] == 'blob', 'Missing bound Git object: ' + blob)
        raw = process.stdout.read(int(header[2]))
        check(len(raw) == int(header[2]) and process.stdout.read(1) == b'\n', 'Invalid Git blob read')
        hashes[blob] = digest(raw)
    process.stdin.close()
    check(process.wait() == 0, 'Git object hash process failed')
    for path, pin in manifests.items():
        expected = {'mode': pin['mode'], 'kind': pin['kind'], 'blob': pin['git_blob']}
        check(source_tree.get(path) == expected and hashes[pin['git_blob']] == pin['sha256'], 'Accepted manifest does not match immutable source: ' + path)
        if candidate_tree.get(path) != expected:
            violations.append({'kind': 'bound_input_changed', 'path': path, 'accepted': expected, 'candidate': candidate_tree.get(path), 'accepted_sha256': pin['sha256']})

    permitted = []
    changes = sorted(path for path in source_tree.keys() | candidate_tree.keys() if source_tree.get(path) != candidate_tree.get(path))
    for path in changes:
        before, after = source_tree.get(path), candidate_tree.get(path)
        if path in manifests:
            continue  # Never allow a bound path because it resembles documentation.
        category = allowed_unbound_delta(path, before, after)
        row = {'path': path, 'before': before, 'after': after}
        if category == 'exact_pinned_audit_script_addition':
            actual_sha256 = digest(git('cat-file', 'blob', after['blob']))
            if code_pins.get(path) != actual_sha256:
                violations.append({'kind': 'new_audit_script_missing_or_mismatched_pin', **row, 'expected_sha256': code_pins.get(path), 'actual_sha256': actual_sha256})
                continue
            row['sha256'] = actual_sha256
        elif category:
            row['sha256'] = digest(git('cat-file', 'blob', after['blob']))
        if category:
            permitted.append({**row, 'category': category})
        else:
            violations.append({'kind': 'unapproved_tracked_delta_outside_tested_manifest', **row})
    canonical = [{ 'path': path, **{k: row[k] for k in ('mode', 'kind', 'git_blob', 'sha256')}, 'owners': sorted(row['owners'])} for path, row in sorted(manifests.items())]
    canonical_bytes = (json.dumps(canonical, sort_keys=True, separators=(',', ':')) + '\n').encode()
    result = {
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'scope': 'Tracked Git publication continuity only. Accepted source manifests and existing audit reports are verified, without rerunning application tests or extending their coverage. The original runtime bindings remain historical receipt evidence; this check does not requalify an installed runtime or prove absence of ignored untracked files during the original run.',
        'qualified_source': source, 'qualified_tree': source_tree_id,
        'candidate_commit': candidate, 'candidate_tree': candidate_tree_id,
        'qualified_source_is_ancestor': ancestor.returncode == 0,
        'acceptance_audits': {'dart': dart_audit_pin, 'python': python_audit_pin}, 'receipts': receipts,
        'input_membership_checks': memberships,
        'union_input_count': len(manifests), 'unique_git_blobs_rehashed': len(hashes),
        'canonical_input_union_sha256': digest(canonical_bytes),
        'bound_path_mode_type_blob_sha256_preserved': not any(row['kind'] == 'bound_input_changed' for row in violations),
        'complete_tracked_tree_diff_inspected': True,
        'source_tracked_entry_count': len(source_tree), 'candidate_tracked_entry_count': len(candidate_tree),
        'tracked_delta_count': len(changes), 'permitted_evidence_and_documentation_deltas': permitted,
        'policy': {'new_evidence_prefix': FINAL_PREFIX, 'direct_children_only': True, 'inert_suffixes': sorted(INERT_SUFFIXES), 'configuration_basenames_rejected': sorted(CONFIG_NAMES), 'only_existing_document_edit': DOCUMENT_PATH, 'exact_new_code_sha256_pins': code_pins, 'deletions_allowed': False, 'existing_evidence_rewrites_allowed': False, 'bound_paths_override_all_allowlists': True},
        'violations': violations, 'passed': not violations,
        'script_sha256': digest(Path(__file__).read_bytes()),
        'application_tests_executed': 0, 'git_lazy_fetch_disabled': True, 'git_replace_objects_disabled': True,
        'git_ref_index_worktree_mutations': 0, 'github_actions_calls': 0,
    }
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ('qualified_source', 'candidate_commit', 'union_input_count', 'tracked_delta_count', 'passed')}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
