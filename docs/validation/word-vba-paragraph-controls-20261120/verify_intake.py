#!/usr/bin/env python3
"""Capture and verify fork/upstream branch and PR ancestry without CI queries.

Use --capture once to save current remote refs, then omit it for offline replay.
This script writes only its capture/review artifacts; it never changes Git refs.
"""

import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess


DEFAULT_TARGET = '0201b549d0dc3f601c50e36255d557034cb01699'
PROOF_PATH = 'docs/validation/word-vba-list-levels-20261120/final-intake.json'
PARTIAL_HEAD = 'c34945761e7991f5fe49037d79529acdd260b31c'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--target', default=DEFAULT_TARGET)
    parser.add_argument('--output-dir', type=Path,
                        default=Path(__file__).resolve().parent)
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--report-prefix', default='incoming-review')
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if not re.fullmatch(r'incoming[-a-z0-9]*', args.report_prefix):
        parser.error('report-prefix must be an incoming-prefixed filename stem')

    def git(*values):
        return subprocess.check_output(['git', '-C', str(repo), *values])

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    def require(condition, reason):
        if not condition:
            raise ValueError(reason)

    target = git('rev-parse', args.target + '^{commit}').decode().strip()

    def ancestor(head):
        result = subprocess.run(
            ['git', '-C', str(repo), 'merge-base', '--is-ancestor', head, target],
            capture_output=True,
        )
        require(result.returncode in (0, 1), result.stderr.decode())
        return result.returncode == 0

    def tree(commit):
        result = {}
        for row in git('ls-tree', '-r', '-z', commit).split(b'\0'):
            if row:
                header, name = row.split(b'\t', 1)
                mode, kind, oid = header.decode().split()
                result[name.decode()] = [mode, kind, oid]
        return result

    prior_bytes = git('show', target + ':' + PROOF_PATH)
    prior = json.loads(prior_bytes)
    proofs = {}
    for row in prior['historical_equivalence_proofs']:
        old = row['historical_head']
        accepted = row['accepted_ancestor']
        base = row['comparison_base']
        old_entries, accepted_entries = tree(old), tree(accepted)
        paths = git('diff', '--name-only', '-z', base, old).decode().split('\0')
        paths = [path for path in paths if path]
        require(ancestor(accepted), 'Equivalent replacement is not an ancestor: ' + old)
        require(set(paths) == {entry['path'] for entry in row['entries']},
                'Changed-path inventory differs: ' + old)
        require(len(paths) == row['changed_path_count'], 'Path count differs: ' + old)
        require(all(old_entries.get(path) == accepted_entries.get(path) for path in paths),
                'Changed path content/mode/type differs: ' + old)
        old_tree = git('rev-parse', old + '^{tree}').decode().strip()
        accepted_tree = git('rev-parse', accepted + '^{tree}').decode().strip()
        equal = old_tree == accepted_tree
        require(equal or (old == PARTIAL_HEAD and len(paths) == 37),
                'Unapproved partial equivalence: ' + old)
        proofs[old] = dict(historical_head=old, accepted_ancestor=accepted,
                           comparison_base=base, old_tree=old_tree,
                           accepted_tree=accepted_tree, full_tree_equal=equal,
                           changed_path_count=len(paths), changed_paths=paths,
                           exact_mode_type_object_match=True,
                           accepted_is_ancestor=True)

    refs, counts, captures, uncovered = [], {}, {}, []
    main_heads = {}
    for remote, label in [('origin', 'fork'), ('upstream', 'upstream')]:
        path = out / (label + '-remote-refs.txt')
        if args.capture:
            path.write_bytes(git('ls-remote', remote, 'refs/heads/*', 'refs/pull/*/head'))
        raw = path.read_bytes()
        captures[label] = dict(path=path.name, bytes=len(raw), sha256=sha(raw))
        seen = set()
        for line in raw.decode().splitlines():
            head, ref = line.split()
            require(re.fullmatch(r'[0-9a-f]{40}', head) is not None,
                    'Invalid captured object: ' + head)
            require(re.fullmatch(r'refs/(heads/.+|pull/[1-9][0-9]*/head)', ref) is not None,
                    'Unexpected captured reference: ' + ref)
            require(ref not in seen, 'Duplicate captured reference: ' + ref)
            seen.add(ref)
            kind = label + ('_branches' if ref.startswith('refs/heads/') else '_pull_requests')
            state = ('target' if head == target else 'ancestor' if ancestor(head)
                     else 'equivalent' if head in proofs else 'uncovered')
            item = dict(kind=kind, ref=ref, sha=head, disposition=state)
            if state == 'equivalent':
                item['accepted_ancestor'] = proofs[head]['accepted_ancestor']
            if state == 'uncovered':
                uncovered.append(item)
            if ref == 'refs/heads/main':
                main_heads[label] = head
            refs.append(item)
            counts.setdefault(kind, collections.Counter())[state] += 1

    result = dict(
        schema='quds-independent-ref-intake/v1',
        status='PASS' if not uncovered else 'FAIL',
        reviewed_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        repository='CrispStrobe/quds_office_suite', target_commit=target,
        target_tree=git('rev-parse', target + '^{tree}').decode().strip(),
        captured_main=main_heads, captures=captures,
        counts={key: dict(value) for key, value in counts.items()}, refs=refs,
        uncovered=uncovered, historical_equivalence_source=PROOF_PATH,
        historical_equivalence_source_sha256=sha(prior_bytes),
        recomputed_equivalence_proofs=list(proofs.values()),
        github_actions='NOT QUERIED OR AWAITED',
        scope='Git ancestry and exact historical content equivalence; no claim of new runtime qualification.',
    )
    report = out / (args.report_prefix + '.json')
    report.write_text(json.dumps(result, indent=2) + '\n')
    totals = {key: sum(value.values()) for key, value in counts.items()}
    full = sum(row['full_tree_equal'] for row in proofs.values())
    (out / (args.report_prefix + '.md')).write_text(
        '# Incoming Quds Office reference audit\n\n'
        f"Status: **{result['status']}** at `{target}`.\n\n"
        f"The captured fork main is `{main_heads.get('fork')}`. "
        f"The audit covers {totals.get('fork_branches', 0)} fork branch heads, "
        f"{totals.get('fork_pull_requests', 0)} fork PR heads, "
        f"{totals.get('upstream_branches', 0)} upstream branch heads and "
        f"{totals.get('upstream_pull_requests', 0)} upstream PR heads. "
        f"There are {len(uncovered)} uncovered references.\n\n"
        f"Every historical substitute was recalculated from immutable Git objects: {full} "
        'complete-tree identities and one exact 37-path ODT continuation. Modes, '
        'types and object IDs agree for each changed path, and each accepted substitute '
        'is an ancestor of the reviewed target. Historical branches need no replay.\n\n'
        '## Recent work\n\n'
        'The baseline `0201b549d0dc3f601c50e36255d557034cb01699` contains completed '
        'cached-Mail checkpoint `c7e721b7703766491fd4459b69de30bf68d9010d` and '
        'Word paragraph-spacing PR #263, including its latest source-preservation '
        'correction. The captured main already contained the earlier spacing '
        'implementation checkpoint `5ad4461a93c835479bf67acab63623944b3900a3`. '
        'PR #262 is merged; its body retained stale draft qualification text, while '
        'its committed final acceptance seal reports PASS. PR #263 was open and draft '
        'at intake and explicitly withheld final acceptance. The new continuation '
        'must qualify that incoming Word code as well as its own changes.\n\n'
        '## Reproduce\n\n'
        'From the repository root, replay the committed captures without network:\n\n'
        '```sh\npython docs/validation/word-vba-paragraph-controls-20261120/verify_intake.py '
        '--repo . --target ' + target + '\n```\n\n'
        'To collect a new inventory, add `--capture` and choose the intended immutable '
        'target. The script reads remote refs only; it does not fetch, push, merge, or '
        'query CI. Unknown or unincorporated references are recorded and cause exit 1. '
        'This is a source-inclusion audit; incoming test evidence is not a new test run.\n'
    )
    print(json.dumps(dict(status=result['status'], target=target, counts=totals,
                          uncovered=len(uncovered), equivalence_proofs=len(proofs),
                          report=str(report))))
    return 1 if uncovered else 0


if __name__ == '__main__':
    raise SystemExit(main())
