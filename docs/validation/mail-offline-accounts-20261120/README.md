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

## Saved development checkpoints

| Remote commit | Scope |
| --- | --- |
| `9c4fbb2b2783af4f15b96a4e1b4043a1f673f6a7` | Reconciled initial branch/PR intake and historical equivalence audit. |
| `63ff7f238c6c2871082cc4dc557552a04aecde68` | Durable directory, additive migration and four-provider host entry. |
| `eb6e96b1e9dec60b591c2b88efa9560168d17898` | Monotonic removal revisions, visible independent storage warnings, connection-to-offline tests and user guide. |
| `831f240fc2072ad0580d19cf036776c68112293a` | Reconciled concurrent Word ListFormat head `57456c602856a8ec56095352e9c1b9b17476ea69`. |

At the third checkpoint the focused store/migration cohort passed 33 cases and
the focused native/chooser/host/cloud cohort passed 48 cases, without skips or
failures. Strict analysis of all changed Mail Dart source/tests passed. These
focused cases overlap the complete qualification and will not be counted twice.

The final local qualification uses `tools/mail/check_store.py` and the adjacent
`run_host_checks.py`, with source hashes before and after each complete run.
Results are pending; this checkpoint does not claim final acceptance.
