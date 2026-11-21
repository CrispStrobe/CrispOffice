# Frozen Mail continuation intake

This audit captures the incoming work before the unified cached-mail milestone.
The machine-readable source inventory and freshly recomputed Git-object checks
are in [`intake.json`](intake.json). This is a history/source audit, not a claim
of executed application tests.

## Result

| Captured scope | Disposition |
| --- | --- |
| 24 starting fork branch heads | 23 already ancestors of captured main; one new Word continuation integrated |
| All 300 fork PR heads, pages 1–3 | 286 actual ancestors; 14 exact historical equivalents |
| Open fork PRs | Zero |
| Four upstream branches | All actual ancestors of captured main |
| Four upstream PR heads | All actual ancestors of captured main |
| Captured heads left uncovered after integration | Zero |

Captured main is `f50c4f23392ccb0ac9f486541ffae6a65a691b99`, the merge of
[PR #300](https://github.com/CrispStrobe/quds_office_suite/pull/300).
The Zotero draft [#299](https://github.com/CrispStrobe/quds_office_suite/pull/299)
was incorporated through that Mail work. The current CLI fix `41c363f4` and
typing benchmark `8716057f` are already actual ancestors. No additional replay
of those branches is needed.

Upstream `MohammedAsaadAsaad/quds_office_suite` main is
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`; its GitHub comparison with captured
fork main has zero upstream-only commits. Local ancestry checks independently
confirm all four upstream branch heads and all four upstream PR heads.

## New incoming Word continuation

The only new captured fork head is
`codex/word-vba-text-intrinsics-20261121` at
`2714483aafe059065b00dac23032023f9ddf7aac`.
Its feature commit `801ad67b` adds bounded binary VBA text search, replacement,
and trimming. Its following commit adds the Word example, versioned fixtures,
conformance/integration tests and qualification documentation. The compiler
and fixture hashes recorded by that incoming qualification match their actual
Git blobs.

Root integrated it with both histories retained at
`db00cf411b21cb8c26878adaa535ffaa5e7e62db`, tree
`73ff301692eacea20ac7ee0f4ab6509fe11a9678`.
All 24 starting fork branch heads are now actual ancestors of that commit.
The auditor independently checked this graph and these conflict resolutions:

- Keep main's completed Boolean search help, error text, RTL example handling
  and localization source. The incoming Word branch had an earlier alternate
  Mail UI integration.
- Keep main's bounded per-file CLI compiler helper. The incoming difference
  there is only a comment; both use the same package-config file-path fix.
- Keep main's 430-line Boolean regression suite. Preserve the incoming
  complementary 225-line suite byte-for-byte as
  `header_search_boolean_truth_table_test.dart`.
- Retain the exact incoming Word compiler and versioned conformance fixture.

The incoming README reports standalone Dart qualification and VM/JavaScript
agreement. Those are historical results from that branch. This intake audit
does not recast them as fresh runs and does not claim full Flutter validation.

## Historical equivalence

The nonancestor PR heads are #134, #135, #136, #137, #138, #140, #141, #142,
#145, #146, #147, #149, #151 and #152. Their recorded replacement commits are
all ancestors of captured main. Thirteen have identical complete Git trees.
For #140, all 37 paths changed by its two source-only commits have exactly the
same mode/type/blob entries at the replacement. The declared path list was
checked against the complete source-only delta; no path is omitted.

The audit also rechecks an older three-path replay from `ec70b942` to
`698209aa`, although that old branch is no longer among the 24 live starting
branches. This yields 15 independently re-executed historical proofs overall:
13 whole-tree proofs and two complete changed-path proofs. Their full SHAs,
trees, path sets and entry comparisons are retained in the JSON. Replaying
those historical heads over current source would replace later work.

## Reproduce the frozen Git checks

Run from a checkout with the captured commits available. The script only reads
Git objects and the frozen JSON; it does not modify refs or the working tree.

```sh
python3 - <<'PY'
import json
import subprocess
from pathlib import Path

d = json.loads(Path(
    'docs/validation/mail-unified-cache-20261121/intake.json'
).read_text())
base, target = d['captured_main'], d['integrated_commit']

def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()

def ancestor(source, destination):
    result = subprocess.run(
        ['git', 'merge-base', '--is-ancestor', source, destination],
        capture_output=True,
    )
    assert result.returncode in (0, 1), result.stderr
    return result.returncode == 0

assert git('rev-parse', target + '^{tree}') == d['integrated_tree']
for branch in d['fork_branches']:
    assert ancestor(branch['head'], base) == branch['ancestor_of_captured_main']
    assert ancestor(branch['head'], target)
proofs = {p['source']: p for p in d['historical_equivalence_proofs']}
for pr in d['pull_requests']:
    if pr['disposition'] == 'ancestor':
        assert ancestor(pr['head'], base)
    else:
        assert not ancestor(pr['head'], base)
        assert proofs[pr['head']]['replacement'] == pr['equivalent_commit']
for proof in proofs.values():
    source, replacement = proof['source'], proof['replacement']
    assert ancestor(replacement, base)
    if proof['kind'] == 'full_tree':
        assert git('rev-parse', source + '^{tree}') == git(
            'rev-parse', replacement + '^{tree}')
    else:
        commits = git('rev-list', base + '..' + source).splitlines()
        paths = set()
        for commit in commits:
            paths.update(git('diff-tree', '--no-commit-id', '--name-only',
                             '-r', commit).splitlines())
        assert paths == set(proof['changed_paths'])
        for path in paths:
            assert git('ls-tree', source, '--', path) == git(
                'ls-tree', replacement, '--', path)
for group in ('branches', 'pull_requests'):
    for item in d['upstream'][group]:
        assert ancestor(item['head'], base)
print('All frozen fork, PR, upstream and historical-equivalence checks passed.')
PY
```

## Scope and final-publication caveat

The inventory is immutable. The newly created working branch is outside its
24-branch starting population. Other branches and remote main can advance
after capture; refresh their current heads before final publication and record
any later reconciliation separately. GitHub Actions, workflow runs, checks and
status queues were neither queried nor awaited. The auditor made no remote
changes and did not modify the Git index.
