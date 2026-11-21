#!/usr/bin/env python3
"""Independently verify captured fork, PR and upstream source coverage.

No CI/status endpoint, ref mutation or product write is used. Historical
mapping entries are candidates: every run recomputes their Git identities and
verifies that the accepted replacement belongs to the requested target history.
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--head', default='origin/main')
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--candidates', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--own-branch', default='codex/zotero-parity-20261121-next')
    args = parser.parse_args()
    env = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_TERMINAL_PROMPT='0')

    def git(*command):
        return subprocess.check_output(['git', *command], cwd=args.repo, env=env)

    def text(*command):
        return git(*command).decode().strip()

    def ancestor(source, target):
        code = subprocess.run(['git', 'merge-base', '--is-ancestor', source, target],
                              cwd=args.repo, env=env).returncode
        if code not in (0, 1):
            raise RuntimeError(f'Ancestry error {code}: {source} -> {target}')
        return code == 0

    def tree_paths(ref, paths):
        raw = git('ls-tree', '-rz', ref, '--', *paths)
        mapping = {}
        for entry in raw.split(b'\0'):
            if not entry:
                continue
            metadata, path = entry.split(b'\t', 1)
            mode, kind, object_id = metadata.decode().split()
            mapping[path.decode()] = {'mode': mode, 'type': kind, 'object': object_id}
        return mapping

    def digest(value):
        return hashlib.sha256(json.dumps(value, sort_keys=True,
                                         separators=(',', ':')).encode()).hexdigest()

    if args.capture:
        if args.snapshot.exists():
            raise RuntimeError('Refusing to replace a captured snapshot')
        refs = []
        for line in text('for-each-ref', '--format=%(refname) %(objectname) %(symref)',
                         'refs/remotes/origin', 'refs/remotes/pull',
                         'refs/remotes/upstream').splitlines():
            parts = line.split()
            if len(parts) == 3:  # symbolic origin/HEAD is not an independent ref
                continue
            ref, sha = parts
            if ref.startswith('refs/remotes/origin/'):
                branch = ref.removeprefix('refs/remotes/origin/')
                kind = 'branch'
                remote_ref = 'refs/heads/' + branch
                repository = 'CrispStrobe/quds_office_suite'
                scope = 'checkpoint' if branch == args.own_branch else 'external'
            elif ref.startswith('refs/remotes/pull/'):
                kind = 'pull_request'
                remote_ref = 'refs/pull/' + ref.removeprefix('refs/remotes/pull/') + '/head'
                repository = 'CrispStrobe/quds_office_suite'
                scope = 'external'
            else:
                kind = 'upstream_branch'
                remote_ref = 'refs/heads/' + ref.removeprefix('refs/remotes/upstream/')
                repository = 'MohammedAsaadAsaad/quds_office_suite'
                scope = 'external'
            refs.append({'repository': repository, 'kind': kind, 'ref': remote_ref,
                         'local_ref': ref, 'sha': sha, 'scope': scope})
        snapshot = {'captured_at': datetime.now(timezone.utc).isoformat(),
                    'source': 'Local refs after root fetched all fork/PR/upstream heads',
                    'refs': refs}
        args.snapshot.write_text(json.dumps(snapshot, indent=2) + '\n')
    snapshot = json.loads(args.snapshot.read_text())
    candidates = json.loads(args.candidates.read_text())
    head = text('rev-parse', args.head)
    proofs = {}
    for source, candidate in candidates.items():
        replacement = candidate['replacement']
        if not ancestor(replacement, head):
            raise RuntimeError(f'Replacement is outside target history: {replacement}')
        proof = {'source': source, 'replacement': replacement,
                 'replacement_is_ancestor': True, 'kind': candidate['kind']}
        if candidate['kind'] == 'full_tree':
            source_tree = text('rev-parse', source + '^{tree}')
            replacement_tree = text('rev-parse', replacement + '^{tree}')
            if source_tree != replacement_tree:
                raise RuntimeError(f'Unequal full trees for {source}')
            proof.update(source_tree=source_tree, replacement_tree=replacement_tree,
                         identical=True)
        elif candidate['kind'] == 'changed_paths':
            base = candidate.get('base') or text('merge-base', source, replacement)
            if not ancestor(base, source) or not ancestor(base, replacement):
                raise RuntimeError(f'Invalid changed-path base: {base}')
            paths = [path.decode() for path in
                     git('diff', '--no-renames', '--name-only', '-z', base, source).split(b'\0')
                     if path]
            if not paths:
                raise RuntimeError(f'No paths to prove for {source}')
            source_map = tree_paths(source, paths)
            replacement_map = tree_paths(replacement, paths)
            if source_map != replacement_map:
                raise RuntimeError(f'Changed-path mode/object mismatch for {source}')
            proof.update(base=base, changed_paths=paths, changed_path_count=len(paths),
                         source_entries=source_map,
                         replacement_entries=replacement_map,
                         canonical_map_sha256=digest(source_map), identical=True)
        else:
            raise RuntimeError(f'Unknown proof kind for {source}')
        proofs[source] = proof

    refs = []
    for ref in snapshot['refs']:
        disposition = ('ancestor' if ancestor(ref['sha'], head)
                       else 'verified_historical_equivalent' if ref['sha'] in proofs
                       else 'uncovered')
        refs.append({**ref, 'disposition': disposition})
    external = [ref for ref in refs if ref['scope'] == 'external']
    uncovered = [ref for ref in external if ref['disposition'] == 'uncovered']
    receipt = {
        'target': head,
        'target_tree': text('rev-parse', head + '^{tree}'),
        'snapshot_at': snapshot['captured_at'],
        'snapshot_sha256': hashlib.sha256(args.snapshot.read_bytes()).hexdigest(),
        'candidate_map_sha256': hashlib.sha256(args.candidates.read_bytes()).hexdigest(),
        'external_count': len(external),
        'external_kinds': dict(Counter(ref['kind'] for ref in external)),
        'external_dispositions': dict(Counter(ref['disposition'] for ref in external)),
        'checkpoint_count': len(refs) - len(external),
        'all_external_covered': not uncovered,
        'proof_count': len(proofs),
        'proof_kinds': dict(Counter(proof['kind'] for proof in proofs.values())),
        'proofs': proofs,
        'refs': refs,
        'uncovered': uncovered,
        'github_actions': 'Neither queried nor awaited',
        'qualification_scope': 'Source inclusion only; no fresh runtime validation is claimed',
    }
    args.output.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in
                      ['target', 'external_count', 'external_kinds',
                       'external_dispositions', 'checkpoint_count',
                       'all_external_covered', 'proof_kinds']}, indent=2))
    return 1 if uncovered else 0


if __name__ == '__main__':
    raise SystemExit(main())
