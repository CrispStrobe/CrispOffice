# Zotero parity continuation — 22 November 2026

## Baseline and preservation

Work starts from remote `main` at
`c522851d165b395a7f60422a1be969dffc39c9ff`, including PR #353.
The initial [ref inventory](intake.json) records all fetched fork branches,
353 fork pull-request heads, upstream branches and upstream pull-request heads.
Every current fork/upstream branch is already an ancestor of this baseline.
There were no open fork PRs at intake. The independent
[historical equivalence audit](historical-intake-equivalence.md) accounts for
every captured ref: 366 direct ancestors, 13 identical-tree replacements and
one replacement with identical entries on all 37 original changed paths.
All 14 replacement commits are ancestors of this baseline. There is no
uncovered historical work to replay.

All implementation checkpoints will be retained on
`codex/zotero-parity-20261122`. Publication will preserve current main ancestry,
without force pushes or branch deletion. GitHub Actions are not queried or
awaited; validation runs locally on the repository-pinned toolchain.

## Work sequence

1. Reconcile incoming refs and identify remaining native Zotero workflow gaps.
2. Preserve the writing position and selection through citation refresh,
   bibliography reflow and supported note conversion, with engine and host
   regression coverage. Align the adapter's optional `canInsertField` argument
   with the already accepted HTTP protocol form.
3. Validate affected source, document persistence and surrounding Zotero flows.
4. Update the parity roadmap with actual results and remaining host acceptance.
5. Refresh remote refs, preserve any concurrent work, and merge into remote main.

This record is updated at the implementation and validation checkpoints.
No test or complete Word/LibreOffice parity claim is made by this initial
inventory commit. Legacy Apache OpenOffice requires separately identified
application/plugin versions.
