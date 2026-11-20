#!/usr/bin/env python3
"""Independent immutable final-checkpoint verification; no tests or CI calls."""
import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

BASE = Path(__file__).resolve().parent.parent
REPO = BASE / 'quds_office_suite'
OUT = BASE / 'intake-review'
QUALIFIED = '0201b549d0dc3f601c50e36255d557034cb01699'
INTEGRATED = 'ed750f1f6b8acab88406fd506e0dd511adcc4485'
DOCS = 'docs/validation/word-vba-paragraph-spacing-20261120/'
SELECTED = ['a51c20737b1932d9c6475ea6dddc33fbd50b2c17',
            '5a73a056f7c757a64d56345c31eabdd6de6eb18a',
            '3bbd414d8f1129bd802b33c3af961d5c12489da2']


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    raw = path.read_bytes()
    return json.loads(gzip.decompress(raw) if path.suffix == '.gz' else raw)


def tree(commit):
    entries = {}
    for row in git('ls-tree', '-rz', commit).split(b'\0'):
        if row:
            meta, path = row.split(b'\t', 1)
            mode, kind, blob = meta.decode().split()
            entries[path.decode()] = {'mode': mode, 'type': kind, 'blob': blob}
    return entries


def contents(entries):
    names = sorted(entries)
    raw = subprocess.run(['git', 'cat-file', '--batch'], cwd=REPO,
                         input=''.join(entries[n]['blob'] + '\n' for n in names).encode(),
                         stdout=subprocess.PIPE, check=True).stdout
    cursor, result = 0, {}
    for name in names:
        end = raw.index(b'\n', cursor)
        oid, kind, length = raw[cursor:end].decode().split()
        length = int(length)
        cursor = end + 1
        data = raw[cursor:cursor + length]
        cursor += length
        require(raw[cursor:cursor + 1] == b'\n', 'Git blob batch framing')
        cursor += 1
        require(kind == 'blob' and oid == entries[name]['blob'], 'Git object type/ID')
        require(hashlib.sha1(f'blob {length}\0'.encode() + data).hexdigest() == oid,
                'Recomputed Git object identity: ' + name)
        result[name] = data
    require(cursor == len(raw), 'Complete Git batch consumption')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True)
    parser.add_argument('--expected-tree', required=True)
    parser.add_argument('--scope-report', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    target = git('rev-parse', args.target + '^{commit}').decode().strip()
    actual_tree = git('rev-parse', target + '^{tree}').decode().strip()
    require(actual_tree == args.expected_tree, 'Expected immutable checkpoint tree')
    ancestors = set(git('rev-list', target).decode().splitlines())
    require({QUALIFIED, INTEGRATED, *SELECTED} <= ancestors, 'Required qualified and selected ancestors')
    parents = git('show', '-s', '--format=%P', target).decode().strip().split()
    chain = git('rev-list', '--reverse', INTEGRATED + '..' + target).decode().splitlines()
    prior = INTEGRATED
    for commit in chain:
        require(git('show', '-s', '--format=%P', commit).decode().strip() == prior,
                'Final evidence checkpoints form a direct single-parent chain')
        prior = commit
    before, current = tree(INTEGRATED), tree(target)
    changed = sorted(n for n in set(before) | set(current) if before.get(n) != current.get(n))
    require(changed and all(n.startswith(DOCS) for n in changed),
            'Final checkpoint changes only the validation directory')

    manifest = load(BASE / 'runtime/line-spacing-portable-final/inputs-before.json.gz')
    selection = manifest['selection']
    def selected(name):
        return name in selection['configuration_files'] or any(
            name.startswith(p + '/') for p in selection['directories'])
    selected_tree = {n: row for n, row in current.items() if selected(n)}
    require(selected_tree == {n: row['head'] for n, row in manifest['entries'].items()},
            'Complete qualified selection, modes, types and objects')
    require(len(selected_tree) == 1131, 'Qualified input count')
    docs_tree = {n: row for n, row in current.items() if n.startswith(DOCS)}
    contract = 'docs/VBA_WORD_MACROS.md'
    script = 'packages/quds_office_editor/example/tool/build_macos_app.sh'
    payloads = contents({**selected_tree, **docs_tree, contract: current[contract], script: current[script]})
    for name, expected in manifest['entries'].items():
        data = payloads[name]
        require(len(data) == expected['bytes'] and sha(data) == expected['sha256'],
                'Qualified source bytes: ' + name)
    require(current[contract] == tree(QUALIFIED)[contract], 'Reviewed Word contract object/mode')
    candidate = (BASE / 'macos-build-correction-20261120/build_macos_app.corrected.sh').read_bytes()
    require(payloads[script] == candidate and current[script]['mode'] == '100755',
            'Exact reviewed executable macOS correction')
    require(sha(candidate) == '8592dd41fb59da7fa3ead05287005cfa06d90c02bb5de495e9f985062ffff904',
            'Frozen corrected script SHA256')

    def document(name):
        return payloads[DOCS + name]
    def parsed(name):
        return json.loads(document(name))
    index = parsed('publication-files.json')
    expected_names = {n[len(DOCS):] for n in docs_tree} - {'publication-files.json'}
    require(set(index['files']) == expected_names, 'Artifact index exactly covers final validation directory')
    for name, row in index['files'].items():
        data = document(name)
        require(row == {'bytes': len(data), 'sha256': sha(data)}, 'Artifact indexed bytes: ' + name)
        require(docs_tree[DOCS + name]['type'] == 'blob', 'Artifact Git object kind')
    evidence = parsed('evidence-review.json')
    require(evidence['status'] == 'PASS' and not evidence['outstanding_findings'], 'Independent final evidence accepted')
    for name in ['evidence-review.json', 'evidence-review.md', 'source-review.json', 'source-review.md',
                 'verify_final_evidence.py', 'audit_batched_regression.py', 'audit_checkpoint_archives.py',
                 'audit_bounded_progress_archive.py', 'late-integration-review.json',
                 'late-integration-review.md', 'publication-scope-review.json', 'publication-scope-review.md']:
        require(document(name) == (OUT / name).read_bytes(), 'Exact frozen independent review artifact: ' + name)
    reviewed_sources = parsed('source-review.json')['source_files']
    require(len(reviewed_sources) == 10, 'Separate source/contract review selection')
    for name, row in reviewed_sources.items():
        require(len(payloads[name]) == row['bytes'] and sha(payloads[name]) == row['sha256']
                and current[name] == {'mode': row['git_mode'], 'type': 'blob', 'blob': row['git_blob']},
                'All ten reviewed inputs retained: ' + name)
    archive_map = {
        'regression-evidence.tar.xz': evidence['packaging']['archives']['regression'],
        'portable-static-evidence.tar.xz': evidence['packaging']['archives']['portable_static'],
        'development-review-evidence.tar.xz': evidence['packaging']['archives']['development_and_source_review'],
        'interrupted-regression-evidence.tar.xz': evidence['checkpoint_archives']['archives']['interrupted-regression-evidence'],
        'late-intake-evidence.tar.xz': evidence['checkpoint_archives']['archives']['late-intake-evidence'],
        'bounded-progress-evidence.tar.xz': evidence['checkpoint_archives']['archives']['bounded-progress-evidence'],
    }
    for name, row in archive_map.items():
        require(len(document(name)) == row['bytes'] and sha(document(name)) == row['sha256'],
                'Exact previously member-verified archive: ' + name)

    stored_scope = parsed('publication-scope-review.json')
    fresh_scope = load(args.scope_report)
    require(fresh_scope['publication_target'] == target and fresh_scope['publication_tree'] == actual_tree,
            'Independent recomputed scope target')
    for key in ['capture_generation', 'deferred_predecessor_ancestry', 'all_initial_captured_work_included',
                'initial_captured_references', 'initial_review_sha256', 'all_selected_late_heads_integrated',
                'selected_late_heads', 'all_current_captured_heads_incorporated', 'unclassified_references',
                'counts', 'captures', 'references', 'explicitly_deferred', 'raw_inclusion_uncovered',
                'raw_inclusion_audit_exit_code', 'historical_proofs_recomputed']:
        require(stored_scope[key] == fresh_scope[key], 'Exact scope classification retained: ' + key)
    captures = []
    for row in fresh_scope['captures']:
        role = row['repository_role']
        original = (BASE / row['path']).read_bytes()
        for name in [Path(row['path']).name, 'latest-captured-' + role + '-refs.txt']:
            require(document(name) == original, 'Exact final scope capture alias: ' + name)
        require(row['bytes'] == len(original) and row['sha256'] == sha(original), 'Scope capture raw binding')
        captures.append(row)
    for name in ['recovery-scope-fork-refs.txt', 'recovery-scope-upstream-refs.txt']:
        require(document(name) == (OUT / name).read_bytes(), 'Prior capture preserved: ' + name)
    # Both historical and subsequent timestamped initial-review reports must be
    # available by their exact referenced digest; substantive equality alone is
    # insufficient to resolve an immutable source-hash reference.
    intake_sources = {}
    findings = []
    for report_name in ['publication-scope-review.json', 'publication-intake.json',
                        'publication-intake-before-reconciliation.json']:
        digest = parsed(report_name)['initial_review_sha256']
        matches = sorted(n for n in expected_names if sha(document(n)) == digest)
        intake_sources[report_name] = {'initial_review_sha256': digest, 'matching_indexed_files': matches}
        if not matches:
            findings.append({'severity': 'evidence_provenance', 'report': report_name,
                             'finding': 'Referenced initial-review SHA256 has no exact indexed payload',
                             'sha256': digest})
    require(git('rev-parse', 'HEAD').decode().strip() == target, 'Local HEAD is checkpoint')
    require(not git('status', '--porcelain').strip(), 'Local worktree clean')
    for name, data in payloads.items():
        path = REPO / name
        require(path.is_file() and not path.is_symlink() and path.read_bytes() == data,
                'Actual checkout matches immutable reviewed payload: ' + name)
        mode = '100755' if path.stat().st_mode & 0o111 else '100644'
        require(mode == current[name]['mode'], 'Actual executable mode: ' + name)
    result = {
        'schema': 'quds-independent-final-checkpoint-review/v1',
        'status': 'PASS' if not findings else 'EVIDENCE_PROVENANCE_FINDING',
        'reviewed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'target': target, 'tree': actual_tree, 'actual_parents': parents,
        'reviewed_late_integration': INTEGRATED, 'final_evidence_commit_chain': chain,
        'all_changes_since_integration_limited_to_validation_directory': True,
        'changed_evidence_paths': changed, 'qualified_source': QUALIFIED,
        'qualified_source_paths': 1131, 'exact_selected_modes_types_objects_bytes_verified': True,
        'all_ten_reviewed_sources_and_contract_unchanged': True,
        'word_contract': {'bytes': len(payloads[contract]), 'sha256': sha(payloads[contract]), **current[contract]},
        'macos_correction': {'bytes': len(candidate), 'sha256': sha(candidate), **current[script]},
        'artifact_index': {'files': len(index['files']), 'bytes': len(document('publication-files.json')),
                           'sha256': sha(document('publication-files.json')), 'all_indexed_bytes_verified': True},
        'archive_copies': {name: {'members': row['member_count'], 'bytes': row['bytes'], 'sha256': row['sha256']}
                           for name, row in archive_map.items()},
        'exact_scope_captures': captures, 'scope_counts': fresh_scope['counts'],
        'deferred_references': len(fresh_scope['explicitly_deferred']),
        'deferred_unique_heads': len({r['sha'] for r in fresh_scope['explicitly_deferred']}),
        'unclassified_references': fresh_scope['unclassified_references'],
        'initial_review_payload_resolution': intake_sources,
        'local_head': target, 'local_branch': git('symbolic-ref', '--short', 'HEAD').decode().strip(),
        'local_worktree_clean': True, 'outstanding_findings': findings,
        'scope_report': {'path': str(args.scope_report), 'sha256': sha(args.scope_report.read_bytes())},
        'verifier_sha256': sha(Path(__file__).read_bytes()),
        'github_actions_queried_or_awaited': False,
        'limits': ['This verifies a frozen checkpoint and its previously qualified evidence; no tests were rerun.',
                   'Remote main publication remains a separate subsequent verification.',
                   'Explicit later-head deferrals remain outside Word publication qualification.'],
    }
    output = args.output.resolve()
    require(output.is_relative_to(OUT), 'Write only independent scratch review')
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ['status', 'target', 'tree', 'qualified_source_paths',
                                            'artifact_index', 'deferred_references', 'unclassified_references',
                                            'outstanding_findings']}, indent=2))


if __name__ == '__main__':
    main()
