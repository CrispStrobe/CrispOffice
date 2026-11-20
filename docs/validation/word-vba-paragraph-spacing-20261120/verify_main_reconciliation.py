#!/usr/bin/env python3
"""Independently verify the final Word checkpoint/live-main reconciliation.

Reads immutable Git objects and the actual checkout. It does not import a
producer helper, run a test, query GitHub Actions, or create Git objects.
"""
import argparse
import collections
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

BASE = Path(__file__).resolve().parent.parent
REPO = BASE / 'quds_office_suite'
OUT = BASE / 'intake-review'
WORD = '8b9be399da380b0b8ab3abf238833eb221996c7d'
MAIN = 'd1e9cbc0c5dd38f0c8d28e3d76e7fdd59990f3f4'
MAIN_BASE = '5ad4461a93c835479bf67acab63623944b3900a3'
ARABIC = 'be47bed22a88382f016d823e526bae49590bd0eb'
QUALIFIED = '0201b549d0dc3f601c50e36255d557034cb01699'
MERGE_TREE = '089f8a66e34efb05a3270523b140c4ced2d07950'
DOCS = 'docs/validation/word-vba-paragraph-spacing-20261120/'
UPDATED = {'README.md', 'publication-files.json', 'verify_word_spacing_publication.py'}
ADDED = {'main-reconciliation.json', 'main-reconciliation.md', 'prepare_main_reconciliation.py',
         'verify_main_reconciliation.py', 'publication-checkpoint-8b9be399.json'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


def tree(commit):
    result = {}
    for row in git('ls-tree', '-rz', commit).split(b'\0'):
        if row:
            meta, name = row.split(b'\t', 1)
            mode, kind, oid = meta.decode().split()
            result[name.decode()] = {'mode': mode, 'type': kind, 'blob': oid}
    return result


def tree_oid(entries):
    """Compute Git tree identity from the complete map without writing objects."""
    root = {}
    for name, row in entries.items():
        node = root
        parts = name.split('/')
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = (row['mode'], row['blob'])
    def digest(node):
        ordered = sorted(node, key=lambda n: (n + ('/' if isinstance(node[n], dict) else '')).encode())
        payload = bytearray()
        for name in ordered:
            value = node[name]
            mode, oid = ('40000', digest(value)) if isinstance(value, dict) else value
            payload.extend(mode.encode() + b' ' + name.encode() + b'\0' + bytes.fromhex(oid))
        return hashlib.sha1(f'tree {len(payload)}\0'.encode() + payload).hexdigest()
    return digest(root)


def blobs(entries):
    names = sorted(entries)
    raw = subprocess.run(['git', 'cat-file', '--batch'], cwd=REPO,
                         input=''.join(entries[n]['blob'] + '\n' for n in names).encode(),
                         stdout=subprocess.PIPE, check=True).stdout
    cursor, result = 0, {}
    for name in names:
        end = raw.index(b'\n', cursor)
        oid, kind, length = raw[cursor:end].decode().split()
        cursor, length = end + 1, int(length)
        data = raw[cursor:cursor + length]
        cursor += length
        require(raw[cursor:cursor + 1] == b'\n', 'Git batch framing')
        cursor += 1
        require(kind == 'blob' and oid == entries[name]['blob'], 'Blob object/type identity')
        require(hashlib.sha1(f'blob {length}\0'.encode() + data).hexdigest() == oid,
                'Recomputed blob identity: ' + name)
        result[name] = data
    require(cursor == len(raw), 'Complete Git blob stream')
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--target', required=True)
    p.add_argument('--expected-tree', required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    target = git('rev-parse', args.target + '^{commit}').decode().strip()
    actual_tree = git('rev-parse', target + '^{tree}').decode().strip()
    require(actual_tree == args.expected_tree, 'Expected immutable reconciliation tree')
    parents = git('show', '-s', '--format=%P', target).decode().strip().split()
    require(parents == [WORD, MAIN], 'Actual two reconciliation parents and order')
    require(git('show', '-s', '--format=%P', MAIN).decode().strip().split() == [MAIN_BASE, ARABIC],
            'Incoming main is the captured PR267 merge')
    require(git('merge-base', WORD, MAIN).decode().strip() == MAIN_BASE, 'Exact merge base')
    word, base, incoming, current = tree(WORD), tree(MAIN_BASE), tree(MAIN), tree(target)
    for commit, entries in [(WORD, word), (MAIN, incoming), (target, current)]:
        require(tree_oid(entries) == git('rev-parse', commit + '^{tree}').decode().strip(),
                'Independent full Git tree reconstruction: ' + commit)
    incoming_paths = sorted(n for n in set(base) | set(incoming) if base.get(n) != incoming.get(n))
    require(len(incoming_paths) == 9 and all(n.startswith(('.github/workflows/', 'packages/quds_arabic_morph/'))
                                            for n in incoming_paths), 'Exact nine incoming main paths')
    merged = dict(word)
    for name in incoming_paths:
        require(word.get(name) == base.get(name), 'Incoming destination unchanged from merge base: ' + name)
        require(incoming.get(name) is not None and current[name] == incoming[name],
                'Incoming main payload/mode/type retained exactly: ' + name)
        merged[name] = incoming[name]
    require(tree_oid(merged) == MERGE_TREE, 'Independently reconstructed merge tree before new evidence')
    expected_outside = {n: row for n, row in merged.items() if not n.startswith(DOCS)}
    require({n: row for n, row in current.items() if not n.startswith(DOCS)} == expected_outside,
            'Every non-evidence path equals the independently reconstructed merge')
    old_docs = {n[len(DOCS):]: row for n, row in word.items() if n.startswith(DOCS)}
    new_docs = {n[len(DOCS):]: row for n, row in current.items() if n.startswith(DOCS)}
    require(set(new_docs) - set(old_docs) == ADDED and not set(old_docs) - set(new_docs),
            'Exactly the five declared new reconciliation evidence files')
    require({n for n in old_docs if old_docs[n] != new_docs[n]} == UPDATED,
            'Only README, artifact index and publication helper updated')

    manifest = json.loads(gzip.decompress((BASE / 'runtime/line-spacing-portable-final/inputs-before.json.gz').read_bytes()))
    selection = manifest['selection']
    selected = {n: row for n, row in current.items()
                if n in selection['configuration_files'] or any(n.startswith(d + '/') for d in selection['directories'])}
    require(len(selected) == 1131 and selected == {n: row['head'] for n, row in manifest['entries'].items()},
            'Exact 1131 qualified input selection and objects/modes')
    contract, macos = 'docs/VBA_WORD_MACROS.md', 'packages/quds_office_editor/example/tool/build_macos_app.sh'
    wanted = {**selected, **{DOCS + n: row for n, row in new_docs.items()},
              **{n: current[n] for n in incoming_paths}, contract: current[contract], macos: current[macos]}
    payloads = blobs(wanted)
    for name, row in manifest['entries'].items():
        require(len(payloads[name]) == row['bytes'] and sha(payloads[name]) == row['sha256'],
                'Qualified source content SHA256 and size: ' + name)
    def document(name):
        return payloads[DOCS + name]
    def parsed(name):
        return json.loads(document(name))
    reviewed_sources = parsed('source-review.json')['source_files']
    require(len(reviewed_sources) == 10, 'Ten separate source-review inputs')
    for name, row in reviewed_sources.items():
        require(current[name] == {'mode': row['git_mode'], 'type': 'blob', 'blob': row['git_blob']}
                and len(payloads[name]) == row['bytes'] and sha(payloads[name]) == row['sha256'],
                'Separately reviewed source/contract retained: ' + name)
    require(current[contract] == tree(QUALIFIED)[contract], 'Original reviewed Word contract unchanged')
    require(sha(payloads[macos]) == '8592dd41fb59da7fa3ead05287005cfa06d90c02bb5de495e9f985062ffff904'
            and current[macos]['mode'] == '100755', 'Reviewed executable macOS correction retained')
    index = parsed('publication-files.json')
    require(set(index['files']) == set(new_docs) - {'publication-files.json'}, 'Complete final artifact index')
    for name, row in index['files'].items():
        require(row == {'bytes': len(document(name)), 'sha256': sha(document(name))}, 'Indexed artifact: ' + name)
    accepted_raw = document('publication-checkpoint-8b9be399.json')
    accepted = json.loads(accepted_raw)
    require(accepted_raw == (OUT / 'publication-checkpoint-8b9be399.json').read_bytes()
            and accepted['status'] == 'PASS' and accepted['target'] == WORD
            and not accepted['outstanding_findings'], 'Exact preceding independent acceptance')
    for name, row in accepted['archive_copies'].items():
        require(len(document(name)) == row['bytes'] and sha(document(name)) == row['sha256'],
                'Previously fully member-verified archive retained: ' + name)
    require(document('verify_main_reconciliation.py') == Path(__file__).read_bytes(), 'Exact independent verifier snapshot')

    historical_raw = document('publication-scope-review.json')
    scope = json.loads(historical_raw)
    require(historical_raw == git('show', WORD + ':' + DOCS + 'publication-scope-review.json'),
            'Historical scope and captures preserved')
    ancestors = set(git('rev-list', target).decode().splitlines())
    require({WORD, MAIN, QUALIFIED, ARABIC} <= ancestors, 'Required integrated ancestors')
    for item in scope['selected_late_heads']:
        require(item['sha'] in ancestors, 'Every previously selected late head retained')
    incorporated, remaining = [], []
    for row in scope['explicitly_deferred']:
        (incorporated if row['sha'] in ancestors else remaining).append(row)
    require(len(incorporated) == 2 and {row['sha'] for row in incorporated} == {ARABIC},
            'Only the two captured Arabic head references change classification')
    require(len(remaining) == 12 and len({row['sha'] for row in remaining}) == 7,
            'Twelve deferred references identify seven remaining heads')
    counts = {}
    for kind in sorted(scope['counts']):
        rows = [row for row in scope['references'] if row['kind'] == kind]
        observed = collections.Counter()
        for row in rows:
            if row['sha'] in ancestors:
                observed['incorporated_or_equivalent'] += 1
            elif row['disposition'] == 'equivalent':
                require(row['accepted_ancestor'] in ancestors, 'Historical equivalence ancestor retained')
                observed['incorporated_or_equivalent'] += 1
            else:
                require(row in remaining, 'No unclassified captured references')
                observed['explicitly_deferred'] += 1
        counts[kind] = {'captured': len(rows), 'incorporated_or_equivalent': observed['incorporated_or_equivalent'],
                        'selected_pending': 0, 'explicitly_deferred': observed['explicitly_deferred'], 'unclassified': 0}
    require(counts['fork_branches']['incorporated_or_equivalent'] == 26
            and counts['fork_pull_requests']['incorporated_or_equivalent'] == 265,
            'Independently recomputed final captured scope counts')
    for row in scope['captures']:
        name = Path(row['path']).name
        require(sha(document(name)) == row['sha256'] and len(document(name)) == row['bytes'], 'Exact scope capture')
        require(document(name) == document('latest-captured-' + row['repository_role'] + '-refs.txt'),
                'Exact latest-captured aliases retained')
    incoming_rows = {n: {**incoming[n], 'bytes': len(payloads[n]), 'sha256': sha(payloads[n])} for n in incoming_paths}
    receipt = parsed('main-reconciliation.json')
    expected_receipt = {
        'schema': 'quds-word-spacing-final-main-reconciliation/v1', 'accepted': True,
        'word_checkpoint': WORD, 'word_checkpoint_tree': git('rev-parse', WORD + '^{tree}').decode().strip(),
        'incoming_main': MAIN, 'incoming_main_parents': [MAIN_BASE, ARABIC],
        'incoming_main_tree': git('rev-parse', MAIN + '^{tree}').decode().strip(),
        'expected_parents': [WORD, MAIN], 'merge_tree_without_evidence': MERGE_TREE,
        'clean_three_way_merge': True, 'incoming_main_paths': incoming_rows,
        'all_nine_incoming_paths_retained_exactly': True, 'qualified_source_paths': 1131,
        'all_qualified_source_and_ten_reviewed_inputs_unchanged': True,
        'historical_scope': {'path': 'publication-scope-review.json', 'bytes': len(historical_raw),
                             'sha256': sha(historical_raw), 'deferred_references': 14},
        'accepted_word_checkpoint_review': {'path': 'publication-checkpoint-8b9be399.json',
                                            'bytes': len(accepted_raw), 'sha256': sha(accepted_raw)},
        'incorporated_from_deferred': incorporated, 'counts': counts, 'remaining_deferred': remaining,
        'remaining_deferred_references': 12, 'remaining_deferred_unique_heads': 7, 'unclassified_references': 0,
        'all_initial_captured_work_included': True, 'all_selected_late_heads_integrated': True,
        'github_actions': 'not queried or awaited',
    }
    for name, value in expected_receipt.items():
        require(receipt[name] == value, 'Independently recomputed reconciliation receipt: ' + name)
    require(any('No new Arabic runtime' in value for value in receipt['limits']), 'Arabic runtime qualification boundary')
    require(git('rev-parse', 'HEAD').decode().strip() == target and not git('status', '--porcelain').strip(),
            'Local checkout is the clean immutable reconciliation checkpoint')
    for name, data in payloads.items():
        path = REPO / name
        require(path.is_file() and not path.is_symlink() and path.read_bytes() == data,
                'Actual checkout bytes match immutable payload: ' + name)
        require(('100755' if path.stat().st_mode & 0o111 else '100644') == current[name]['mode'],
                'Actual checkout executable mode: ' + name)
    result = {
        'schema': 'quds-independent-final-main-reconciliation-review/v1', 'status': 'PASS',
        'reviewed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'target': target, 'tree': actual_tree, 'actual_parents': parents,
        'merge_base': MAIN_BASE, 'independently_reconstructed_merge_tree': MERGE_TREE,
        'all_non_evidence_paths_exactly_reconciled': True, 'incoming_main_paths': incoming_rows,
        'incoming_destinations_unchanged_from_merge_base': True,
        'qualified_source': QUALIFIED, 'qualified_source_paths': 1131,
        'all_selected_source_modes_types_objects_bytes_verified': True,
        'all_ten_reviewed_source_and_contract_inputs_unchanged': True,
        'reviewed_macos_correction_unchanged': True,
        'artifact_index': {'files': len(index['files']), 'sha256': sha(document('publication-files.json')),
                           'all_indexed_bytes_verified': True},
        'previously_verified_archive_copies_unchanged': accepted['archive_copies'],
        'prior_evidence_preserved_except': sorted(UPDATED), 'new_evidence_paths': sorted(ADDED),
        'historical_scope_sha256': sha(historical_raw), 'scope_captures': scope['captures'],
        'incorporated_from_historical_deferrals': incorporated, 'counts': counts,
        'remaining_deferred': remaining, 'remaining_deferred_references': 12,
        'remaining_deferred_unique_heads': 7, 'unclassified_references': 0,
        'receipt_sha256': sha(document('main-reconciliation.json')),
        'receipt_fields_independently_recomputed': True,
        'local_checkout_clean': True, 'outstanding_findings': [],
        'verifier_sha256': sha(Path(__file__).read_bytes()), 'github_actions_queried_or_awaited': False,
        'limits': ['Read-only source, ancestry and evidence verification; no new test or workflow execution.',
                   'Incoming Arabic feature is retained from existing main; no Arabic runtime/parity acceptance is claimed.',
                   'Final live remote-main equality is a separate post-publication check.'],
    }
    output = args.output.resolve()
    require(output.is_relative_to(OUT), 'Write only independent scratch review')
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ['status', 'target', 'tree', 'actual_parents', 'qualified_source_paths',
                                            'artifact_index', 'remaining_deferred_references',
                                            'remaining_deferred_unique_heads', 'outstanding_findings']}, indent=2))


if __name__ == '__main__':
    main()
