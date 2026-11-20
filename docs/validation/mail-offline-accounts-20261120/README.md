# Offline account drafts — 20 November 2026

## Scope and intake

Continue the ordered Mail parity roadmap with durable, verified account metadata
for offline access to local drafts. This increment is being implemented and has
not yet been qualified. GitHub Actions are not queried or awaited.

Initial main was `5c48058bedc42dd8cbf3fb9d6f1fb492b2ac1eb8`. The work branch
fast-forwards through both remaining recent heads at `79e11935`; this preserves
PR #254 and the matching Word continuation. The only difference from main is
the clarification of inherited Zotero test names, preserving their assertions.
The incoming Outbox implementation is already in main; its old in-progress
report is not evidence of final acceptance.

`intake.json` captures all 20 live fork branch heads and the 20 most recently
updated PRs. `reconciliation.json` rechecks eight exact-tree equivalents and
one historical changed-path equivalent against ancestors of this branch, and
verifies all four fetched upstream heads are ancestors. Historical work is
retained without replaying superseded source.

Incremental remote branch: `work/mail-offline-accounts-20261120`.
