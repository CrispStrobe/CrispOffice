#!/usr/bin/env python3
"""Classify captured references with an explicit later-work publication boundary."""
import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

BASE = Path(__file__).resolve().parent.parent
REPO = BASE / 'quds_office_suite'
OUT = BASE / 'intake-review'
SELECTED = {
    'a51c20737b1932d9c6475ea6dddc33fbd50b2c17': 'Original macOS deployment PR265 head',
    '5a73a056f7c757a64d56345c31eabdd6de6eb18a': 'Original PDF early-return brace PR264 head',
    '3bbd414d8f1129bd802b33c3af961d5c12489da2': 'Original paragraph-controls intake-only head',
}
PREVIOUS_DEFERRED = {
    '7c64246b5bb7c441206ae0bca99948f33b091f13': 'Later paragraph-controls implementation; draft PR268 qualification in progress',
    'f4c3d582711b923b41a8ab37f917bc1564ab1a55': 'Later App Store submission documentation',
    '3c6637b6e5585de5fb4b8d27a0ceda6f96edb95f': 'Later App Store screenshot feature',
    'be47bed22a88382f016d823e526bae49590bd0eb': 'Later Arabic web context feature',
    '6117d3bd193d79ecc9e14530378bf3af614c3c33': 'Later Arabic web settings feature',
    'f4de5f4f1f3793c0aee5e654113c7220701dc30e': 'Later bookmark typing fix',
    '01224376ee0e86703b6b4723e40c72de7629e50b': 'Later main-green continuation; distinct from selected original PR264 head',
    'd219465a581d8082efa6909b4005c64d7a7624a2': 'Later Mail parity continuation',
}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', default='ed750f1f6b8acab88406fd506e0dd511adcc4485')
    parser.add_argument('--scope', choices=['previous', 'latest'], default='latest')
    parser.add_argument('--require-selected-integrated', action='store_true')
    parser.add_argument('--output', type=Path, default=OUT / 'publication-scope-review.json')
    args = parser.parse_args()
    target = git('rev-parse', args.target + '^{commit}').decode().strip()
    def read_refs(filename):
        return {ref: head for head, ref in (line.split() for line in (OUT / filename).read_text().splitlines())}
    predecessor_proofs = []
    if args.scope == 'latest':
        fork_filename, upstream_filename = 'latest-scope-fork-refs.txt', 'latest-scope-upstream-refs.txt'
        previous_refs = read_refs('recovery-scope-fork-refs.txt')
        current_refs = read_refs(fork_filename)
        deferred_heads = {}
        for ref, old_head in previous_refs.items():
            if not ref.startswith('refs/heads/') or old_head not in PREVIOUS_DEFERRED:
                continue
            new_head = current_refs[ref]
            require(old_head in set(git('rev-list', new_head).decode().splitlines()), 'A later deferred head lost its captured predecessor ancestry')
            deferred_heads[new_head] = PREVIOUS_DEFERRED[old_head]
            predecessor_proofs.append({'branch': ref, 'previous_head': old_head, 'current_head': new_head, 'previous_is_ancestor': True})
        require(len(deferred_heads) == 8, 'Eight explicitly selected deferred continuations')
    else:
        fork_filename, upstream_filename = 'recovery-scope-fork-refs.txt', 'recovery-scope-upstream-refs.txt'
        deferred_heads = dict(PREVIOUS_DEFERRED)
    ancestors = set(git('rev-list', target).decode().splitlines())
    selected_closure = set(git('rev-list', *SELECTED).decode().splitlines())
    initial = json.loads((OUT / 'incoming-review.json').read_text())
    proofs = initial['intake']['recomputed_equivalence_proofs']
    equivalent = {}
    for proof in proofs:
        old, accepted = proof['historical_head'], proof['accepted_ancestor']
        require(accepted in ancestors, 'Historical replacement not in publication ancestry')
        old_tree = git('rev-parse', old + '^{tree}').decode().strip()
        accepted_tree = git('rev-parse', accepted + '^{tree}').decode().strip()
        require(old_tree == proof['old_tree'] and accepted_tree == proof['accepted_tree'], 'Historical immutable tree binding')
        if old_tree != accepted_tree:
            paths = git('diff', '--name-only', proof['comparison_base'], old).decode().splitlines()
            require(len(paths) == 37 and sorted(paths) == sorted(proof['changed_paths']), 'Exact37-path continuation selection')
            require(git('ls-tree', '-rz', old, '--', *paths) == git('ls-tree', '-rz', accepted, '--', *paths), 'Continuation exact modes/types/objects')
        equivalent[old] = accepted
    require(len(equivalent) == 14 and sum(p['full_tree_equal'] for p in proofs) == 13, 'Complete historical equivalence inventory')
    initial_rows = initial['intake']['refs']
    require(all(row['sha'] in ancestors or row['sha'] in equivalent for row in initial_rows), 'All initial captured work is included/equivalent')
    captures = []
    rows = []
    for label, filename in [('fork', fork_filename), ('upstream', upstream_filename)]:
        path = OUT / filename
        raw = path.read_bytes()
        captures.append({'repository_role': label, 'path': str(path.relative_to(BASE)), 'bytes': len(raw), 'sha256': sha(raw)})
        for line in raw.decode().splitlines():
            head, ref = line.split()
            kind = label + ('_branches' if ref.startswith('refs/heads/') else '_pull_requests')
            if head in ancestors:
                disposition = 'incorporated'
            elif head in equivalent:
                disposition = 'equivalent'
            elif head in selected_closure:
                disposition = 'selected_for_integration'
            elif head in deferred_heads:
                disposition = 'explicitly_deferred'
            else:
                disposition = 'unclassified'
            row = {'kind': kind, 'ref': ref, 'sha': head, 'disposition': disposition}
            if disposition == 'equivalent':
                row['accepted_ancestor'] = equivalent[head]
            if disposition == 'explicitly_deferred':
                row['scope_reason'] = deferred_heads[head]
            rows.append(row)
    require(not any(r['disposition'] == 'unclassified' for r in rows), 'A captured head is unclassified')
    selected = [{'sha': h, 'description': label, 'integrated_as_ancestor': h in ancestors} for h, label in SELECTED.items()]
    if args.require_selected_integrated:
        require(all(s['integrated_as_ancestor'] for s in selected), 'Selected late head absent from actual publication ancestry')
    deferred = [r for r in rows if r['disposition'] == 'explicitly_deferred']
    require({r['sha'] for r in deferred} == set(deferred_heads), 'Explicit later deferred head inventory')
    counts = {}
    for kind in sorted({r['kind'] for r in rows}):
        bucket = [r for r in rows if r['kind'] == kind]
        counts[kind] = {'captured': len(bucket), 'incorporated_or_equivalent': sum(r['disposition'] in ['incorporated', 'equivalent'] for r in bucket),
                        'selected_pending': sum(r['disposition'] == 'selected_for_integration' for r in bucket),
                        'explicitly_deferred': sum(r['disposition'] == 'explicitly_deferred' for r in bucket), 'unclassified': 0}
    unresolved = [r for r in rows if r['disposition'] not in ['incorporated', 'equivalent']]
    integrated = all(s['integrated_as_ancestor'] for s in selected)
    result = {
        'schema': 'quds-independent-publication-scope/v1',
        'status': 'PASS_WITH_EXPLICIT_DEFERRALS' if integrated else 'CLASSIFIED_PENDING_SELECTED_INTEGRATION',
        'reviewed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'capture_generation': args.scope, 'deferred_predecessor_ancestry': predecessor_proofs,
        'publication_target': target, 'publication_tree': git('rev-parse', target + '^{tree}').decode().strip(),
        'all_initial_captured_work_included': True, 'initial_captured_references': len(initial_rows),
        'initial_review_sha256': sha((OUT / 'incoming-review.json').read_bytes()),
        'all_selected_late_heads_integrated': integrated, 'selected_late_heads': selected,
        'all_current_captured_heads_incorporated': not unresolved,
        'unclassified_references': 0, 'counts': counts, 'captures': captures,
        'references': rows, 'explicitly_deferred': deferred,
        'raw_inclusion_uncovered': unresolved, 'raw_inclusion_audit_exit_code': 1 if unresolved else 0,
        'historical_proofs_recomputed': {'whole_tree': 13, 'exact_37_path_continuation': 1},
        'scope': 'The initial full intake and three separately selected original late heads define this Word publication. Later heads in the captured inventory are explicitly deferred, including newer continuations of selected branches. Their remote refs and immutable commits remain intact. No claim that every later current head has been incorporated.',
        'upstream_capture_scope': 'Uses the exact separately saved upstream capture for the selected generation; every captured upstream head is included.',
        'github_actions_queried_or_awaited': False,
    }
    output = args.output.resolve()
    require(output.is_relative_to(OUT), 'Only independent scratch output is allowed')
    output.write_text(json.dumps(result, indent=2) + '\n')
    lines = ['# Independent publication-scope review', '', f'Status: **{result["status"]}** against `{target}`.', '',
             'Every reference from the original intake is included or historically equivalent. The three selected original late heads are tracked separately from their newer continuations. Later moving work is explicitly deferred; all captured entries are classified.', '',
             '| Captured source | Total | Incorporated or equivalent | Selected pending | Deferred | Unclassified |',
             '| --- | ---: | ---: | ---: | ---: | ---: |']
    for kind, c in counts.items():
        lines.append(f'| {kind} | {c["captured"]} | {c["incorporated_or_equivalent"]} | {c["selected_pending"]} | {c["explicitly_deferred"]} | 0 |')
    lines += ['', '## Explicitly deferred captured heads', '']
    for head, reason in deferred_heads.items():
        refs = [r['ref'] for r in deferred if r['sha'] == head]
        lines.append(f'- `{head}` — {reason}. Captured refs: ' + ', '.join(f'`{r}`' for r in refs) + '.')
    lines += ['', 'The raw inclusion audit intentionally retains all uncovered references and exit code 1. A fully classified publication scope does not turn deferred work into incorporated work. This review uses immutable captured SHAs and retains the 13 full-tree proofs plus the exact 37-path continuation proof. No GitHub Actions were queried or awaited.', '', 'The current report is an ancestry/source-inclusion review, not new runtime qualification of the deferred features.']
    output.with_suffix('.md').write_text('\n'.join(lines) + '\n')
    print(json.dumps({'status': result['status'], 'target': target, 'counts': counts, 'deferred_unique_heads': len(deferred_heads), 'unclassified': 0}, indent=2))


if __name__ == '__main__':
    main()
