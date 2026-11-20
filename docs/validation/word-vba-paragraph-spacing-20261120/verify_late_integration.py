#!/usr/bin/env python3
"""Independently verify the immutable late-head integration checkpoint."""
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
PREVIOUS = 'd906a2d3c930b404571a223f4addc3e00ccf84e0'
SELECTED = ['a51c20737b1932d9c6475ea6dddc33fbd50b2c17',
            '5a73a056f7c757a64d56345c31eabdd6de6eb18a',
            '3bbd414d8f1129bd802b33c3af961d5c12489da2']
BINDING = 'docs/validation/word-vba-paragraph-spacing-20261120/late-integration-binding.json'
PREPARER = 'docs/validation/word-vba-paragraph-spacing-20261120/prepare_external_reconciliation.py'
SCRIPT = 'packages/quds_office_editor/example/tool/build_macos_app.sh'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def tree(commit, *paths):
    result = {}
    for row in git('ls-tree', '-rz', commit, '--', *paths).split(b'\0'):
        if row:
            meta, name = row.split(b'\t', 1)
            mode, kind, blob = meta.decode().split()
            result[name.decode()] = {'mode': mode, 'type': kind, 'blob': blob}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', default='ed750f1f6b8acab88406fd506e0dd511adcc4485')
    args = parser.parse_args()
    target = git('rev-parse', args.target + '^{commit}').decode().strip()
    parents = git('show', '-s', '--format=%P', target).decode().strip().split()
    require(parents == [PREVIOUS, *SELECTED], 'Actual integration parent identities/order')
    raw_binding = git('show', target + ':' + BINDING)
    binding = json.loads(raw_binding)
    require(binding['parent_checkpoint'] == PREVIOUS and binding['additional_actual_parents'] == SELECTED and binding['qualified_word_source'] == QUALIFIED, 'Recorded integration ancestry')
    previous, actual = tree(PREVIOUS), tree(target)
    expected = dict(previous)
    changed = set()
    proofs = []
    for head, recorded in zip(SELECTED, binding['delta_proofs']):
        base = git('merge-base', PREVIOUS, head).decode().strip()
        paths = git('diff', '--name-only', base, head).decode().splitlines()
        require(recorded['head'] == head and recorded['merge_base'] == base, 'Actual selected merge base')
        require(len(paths) == recorded['changed_path_count'] and paths == [p['path'] for p in recorded['paths']], 'Complete incoming path selection')
        require(not changed & set(paths), 'Disjoint incoming path deltas')
        base_tree, head_tree = tree(base, *paths), tree(head, *paths)
        for row in recorded['paths']:
            name = row['path']
            require(row['before'] == base_tree.get(name) == previous.get(name), 'Incoming destination unchanged from merge base: ' + name)
            require(row['imported'] == head_tree.get(name), 'Incoming object/mode/type identity: ' + name)
            if row['imported'] is None:
                expected.pop(name, None)
            else:
                expected[name] = row['imported']
        changed.update(paths)
        proofs.append({'head': head, 'merge_base': base, 'paths': paths, 'all_before_and_imported_objects_verified': True})
    require(len(changed) == 12, 'Complete selected late delta count')
    candidate = (BASE / 'macos-build-correction-20261120/build_macos_app.corrected.sh').read_bytes()
    script_bytes = git('show', target + ':' + SCRIPT)
    require(script_bytes == candidate, 'Exact independently reviewed correction bytes')
    script_blob = hashlib.sha1(f'blob {len(candidate)}\0'.encode() + candidate).hexdigest()
    expected[SCRIPT] = {'mode': '100755', 'type': 'blob', 'blob': script_blob}
    for name in [BINDING, PREPARER]:
        require(name not in previous and actual[name]['mode'] == '100644', 'New checkpoint-only evidence path')
        expected[name] = actual[name]
    require(actual == expected, 'Exact full tree equals prior checkpoint plus selected deltas, correction, and two evidence files')
    qualified = json.loads(gzip.decompress((BASE / 'runtime/line-spacing-portable-final/inputs-before.json.gz').read_bytes()))
    selection = qualified['selection']
    paths = [*selection['directories'], *selection['configuration_files']]
    actual_source = tree(target, *paths)
    expected_source = {name: row['head'] for name, row in qualified['entries'].items()}
    require(actual_source == expected_source and len(actual_source) == 1131, 'Exact qualified Word selection and modes/types/objects unchanged')
    require(tree(target, 'docs/VBA_WORD_MACROS.md') == tree(QUALIFIED, 'docs/VBA_WORD_MACROS.md'), 'Reviewed Word contract unchanged')
    correction = binding['macos_correction']
    require(correction['blob'] == script_blob and correction['mode'] == '100755' and correction['bytes'] == len(candidate) and correction['sha256'] == hashlib.sha256(candidate).hexdigest(), 'Recorded corrected script object/content/mode binding')
    require(correction['actual_macos_build'] is False and correction['actual_bash3_execution'] is False, 'Platform qualification limits retained')
    require(git('rev-parse', 'HEAD').decode().strip() == QUALIFIED and not git('status', '--porcelain').strip(), 'Local gate HEAD/worktree remained frozen')
    report = {'schema': 'quds-independent-late-integration-verification/v1', 'status': 'PASS',
              'reviewed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'commit': target, 'tree': git('rev-parse', target + '^{tree}').decode().strip(),
              'actual_parents': parents, 'delta_proofs': proofs,
              'whole_tree_exactly_reconciled': True, 'imported_delta_paths': 12,
              'additional_evidence_paths': [BINDING, PREPARER],
              'qualified_word_inputs': 1131, 'qualified_word_selection_modes_types_blobs_unchanged': True,
              'word_contract_unchanged': True, 'macos_correction': correction,
              'binding_record_sha256': hashlib.sha256(raw_binding).hexdigest(),
              'local_gate_head_and_worktree_unchanged': True,
              'scope': 'Source/ancestry integration proof only. This does not claim completion of the still-running Word regression or a real macOS/Bash3 execution.',
              'github_actions_queried_or_awaited': False}
    (OUT / 'late-integration-review.json').write_text(json.dumps(report, indent=2) + '\n')
    (OUT / 'late-integration-review.md').write_text(f'''# Independent late-integration verification

**PASS** for checkpoint `{target}` (tree `{report['tree']}`).

The actual Git commit has exactly the previous checkpoint and the three selected
original late heads as its four parents. All 12 imported path deltas were
independently reconstructed from their merge bases. Every destination was
unchanged before integration; the deltas are disjoint.

The complete resulting tree is exactly the prior checkpoint plus those deltas,
the independently reviewed macOS guard correction, and the two checkpoint
evidence files. No unrelated changes are present. The corrected shell script
matches SHA-256 `{correction['sha256']}` and retains executable Git mode
`100755`.

All 1,131 qualified Word inputs preserve their exact selected path set, modes,
types and Git blob identities. The reviewed Word contract is unchanged. Local
HEAD remains the qualified source `{QUALIFIED}`, with a clean worktree for the
ongoing tests.

This is a source/ancestry proof. It does not claim that the pending Word gate
has completed, and it preserves the explicit absence of a real macOS build or
actual Bash 3 execution. No GitHub Actions were queried or awaited.
''')
    print(json.dumps({'status': 'PASS', 'commit': target, 'parents': parents, 'qualified_word_inputs': 1131, 'imported_delta_paths': 12}, indent=2))


if __name__ == '__main__':
    main()
