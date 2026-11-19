# CrispOffice durable mail archive and search — 19 November 2026

## Incoming integration checkpoint

Before feature edits, fetched every advertised fork branch and pull-request
head, plus all four upstream branches. The bounded inventory in
`initial-reconciliation.json` accounts for 220 references: 197 are ancestors
of the combined parents, and 23 have exact historical equivalents already in
those histories. All 14 historical equivalence proofs were recomputed from
Git objects. There are no unaccounted captured references.

The combined parents are current main `e00ca149` (including Gmail, Microsoft
365, Exchange EWS, and paragraph language identification) and the remaining
Office recovery head `62305711`. The recovery evidence is preserved unchanged
as historical evidence, not claimed as fresh test execution.

Four overlapping mail files were reconciled. The current provider presets,
cloud connections, static cross-instance credential queue, validation and
generation guards remain. Incoming keychain errors now have separate feedback
so late credential failures cannot replace an SMTP acceptance receipt. Incoming
platform credential tests and lifecycle regressions are retained. Forget stays
available even for unreadable records and pending saves; two incoming widget
expectations were reconciled with that intentional behavior.

This first checkpoint preserves the integration before new archive work. Local
runtime qualification follows; this checkpoint alone makes no passing test
claim. GitHub Actions are neither queried nor awaited. All publication commits
use `[skip ci]`, non-forced expected-head updates, and remote tree readback.
