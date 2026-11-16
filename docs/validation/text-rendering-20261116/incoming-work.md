# Text rendering: incoming work and baseline

Observed UTC: **2026-11-16T14:36:34.113245+00:00**.

The text-rendering work starts at
`bfb24bf57d5efd52f00ab7079b4ac8968259a478`, tree
`4d36cb2c5d0fcf76a64183195669d279b97d86aa`. This is the latest observed
`codex/proofing-20261116-resume` consolidation, preserved as the starting
point of remote branch `codex/text-rendering-20261116`.

**All 132 observed incoming branch and PR heads are ancestors of this
baseline.** No incoming head needs a further merge at this cutoff.

## Complete ref accounting

| Repository | Branch heads | PR heads | Ancestors | Nonancestors |
| --- | ---: | ---: | ---: | ---: |
| `CrispStrobe/quds_office_suite` | 58 | 66 | 124 | 0 |
| `MohammedAsaadAsaad/quds_office_suite` | 4 | 4 | 8 | 0 |
| **Total** | **62** | **70** | **132** | **0** |

The [machine-readable inventory](incoming-refs.json) records each local and
remote ref, exact SHA, repository, ref kind and independently checked
`git merge-base --is-ancestor` result. It also retains the complete raw ref
snapshot, exclusions and selected ref-update observations. The snapshot's
SHA-256 is
`9f341ca6c9c6137ce8aaf512923146767dddb5beebc76cc257d92dff111ef22d`.

Both remotes' branch heads and PR heads were fetched before this snapshot.
The observation time and exact ref values define its cutoff; the report does
not claim that remote branches stopped changing. A reflog timestamp records
the update of that ref, not the completion of every later unchanged fetch.

Excluded from incoming counts: symbolic `origin/HEAD`, the new
`codex/text-rendering-20261116` work branch, tags, local branches and synthetic
PR merge refs. PR-head ancestry establishes source inclusion, not review
approval or PR status.

## Significant included checkpoints

| Incoming work | Exact observed SHA | Result |
| --- | --- | --- |
| Origin main, ODS comparison operators and documentation through PRs #65–66 | `90024d5d76a784dd96974988a5f54effcaac911d` | Ancestor |
| Zotero capabilities, PR #63 | `2480f0988167068d9aeddf6573b9c2c6871a8481` | Ancestor |
| Primary proofing and its completed evidence publication | `c0403890fc00f38c0ee6e1d533f6fef549c6fc03` | Ancestor |
| Word dialog input ownership and metric rulers | `2e92a49c2cf39128a79d2c037c3e07bbace1d1ae` | Ancestor |
| German token, quote and grapheme-boundary corrections | `db6cea46cb0146c68df1ce204091b3ce47abd218` | Ancestor |
| Latest proofing/Zotero/ODS consolidation | `bfb24bf57d5efd52f00ab7079b4ac8968259a478` | Selected baseline |
| Original upstream main | `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` | Ancestor |

The baseline also retains the feature, vendor and documentation histories
whose changes had been squash-merged to main. Their inclusion is now verified
by ancestry; no claim of whole-tree equality with today's main is needed.

## Architectural decision and qualification

The adopted consolidation retains the standalone proofing session in
`lib/src/proofing/word_proofing.dart`. The earlier Zotero continuation retained
a different session in `lib/src/embed/word_proofing.dart`. These were competing
implementations, not equivalent patches. The later consolidation selected the
standalone session and reconciled primary rendering/caret work, Zotero guards,
dialog ownership, metric rulers and newer German-provider corrections.

The rationale and earlier reconciliation remain in
[the proofing continuation record](../proofing-20261116/continuation-next/README.md).
Earlier [Zotero proofing dispositions](../zotero-capabilities-20261116/late-proofing-disposition.md)
retain their historical source pins and correctly describe the state before
this later consolidation.

**At this initial audit checkpoint, fresh Dart/Flutter qualification of the
adopted combined baseline is pending.** Ancestry does not establish runtime
correctness. The prior combined run was interrupted during environment setup;
test totals from earlier commits are not attributed to this baseline or to new
rendering changes. Subsequent local validation must identify its actual source
and test selection separately.

The rendering task saves incremental source/documentation checkpoints to the
remote work branch. It does not wait for hosted CI: no GitHub Actions jobs,
workflow runs, commit statuses or check runs were polled, awaited or rerun for
this audit.

## Reproduction

From a checkout containing the fetched objects:

```python
import json
import subprocess

with open("docs/validation/text-rendering-20261116/incoming-refs.json") as f:
    audit = json.load(f)
for ref in audit["refs"]:
    subprocess.run(
        ["git", "merge-base", "--is-ancestor", ref["sha"], audit["baseline"]["sha"]],
        check=True,
    )
assert len(audit["refs"]) == 132
```

Use the recorded SHAs when reproducing this audit. A fresh fetch or later work
branch commit does not change this frozen observation.
