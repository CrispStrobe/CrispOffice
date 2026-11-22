# Mail membership recovery — work and local qualification

This increment continues the ordered Mail parity work after durable foreground
Move/Delete. Implementation and local acceptance are in progress; this initial
checkpoint records the reconciled source and scope, not a passed release gate.

## Intake

The checkout starts from `b13a170cdb5fd42b9a0f2c77d97c996caf5d0d7f`, including
the latest Mail #363, Word #362 and Zotero #364 integrations. All 27 fork branch
tips, four upstream branch tips and all 101 inspected recent PR heads are
ancestors of this baseline. Neither fork nor upstream has an open PR at intake.
The exact refs and results are retained in [intake.json](intake.json).

Work is preserved incrementally on `codex/mail-membership-recovery-20261122`.
Local acceptance is the gate: GitHub Actions and status endpoints are not
queried or awaited. Publication will preserve current-main ancestry and verify
the merged remote tree, using ordinary branch/PR operations without force.

## Scope

- Add an optional, read-only membership observer, separate from flag recovery.
- Observe the original IMAP UID generation and deletion marker, Gmail labels
  and Trash, Microsoft Graph immutable-ID parent folder, and EWS original-ID
  parent when available. Missing IMAP/EWS identities do not identify a moved
  destination or prove the old operation succeeded.
- Retain a bounded latest observation per uncertain membership item, with exact
  identity, check time and revision. Preserve the historical command receipt,
  uncertain outcome and cleanup protection. Never replay the command.
- Expose explicit checks and saved evidence in connected Mail activity, with
  English/German/Arabic controls and the existing account, owner, cancellation,
  revision and stale-view fences. Cached history remains a local read.
- Preserve dated cache observations until an explicit browse refresh or sync.
  This increment does not invent replacement IMAP/EWS IDs, destination rows,
  complete mailbox coverage, or causal proof from a current-state observation.

## Planned local acceptance

Provider fixtures exercise exact identity, current membership, missing data,
malformed responses, generation changes, authentication errors, cancellation
and zero provider writes. Core/store checks cover migration, quota, reopen,
revisions, ownership, cancellation and unchanged uncertain receipts. Connected
host and localized activity tests cover account rebinding, explicit dispatch,
late results, repeated checking and local-only cached presentation. The final
record will contain actual commands, results, source hashes and limitations.
