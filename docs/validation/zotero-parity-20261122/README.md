# Zotero parity continuation — 22 November 2026

## Baseline and preservation

Work starts from remote `main` at
`c522851d165b395a7f60422a1be969dffc39c9ff`, including PR #353.
The initial [ref inventory](intake.json) records all fetched fork branches,
353 fork pull-request heads, upstream branches and upstream pull-request heads.
Every current fork/upstream branch is already an ancestor of this baseline.
There were no open fork PRs at intake. Fourteen historical PR heads have
previous replacement history; their equivalence is being rechecked before any
integration decision. Obsolete changes will not be replayed over newer code.

All implementation checkpoints will be retained on
`codex/zotero-parity-20261122`. Publication will preserve current main ancestry,
without force pushes or branch deletion. GitHub Actions are not queried or
awaited; validation runs locally on the repository-pinned toolchain.

## Work sequence

1. Reconcile incoming refs and identify remaining native Zotero workflow gaps.
2. Implement the selected behavior with engine and host regression coverage.
3. Validate affected source, document persistence and surrounding Zotero flows.
4. Update the parity roadmap with actual results and remaining host acceptance.
5. Refresh remote refs, preserve any concurrent work, and merge into remote main.

This record is updated at the implementation and validation checkpoints.
No test or complete Word/LibreOffice parity claim is made by this initial
inventory commit. Legacy Apache OpenOffice requires separately identified
application/plugin versions.
