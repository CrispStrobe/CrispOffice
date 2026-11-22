# Durable Mail move/delete — intake and local qualification

## Remote intake

The 22 November 2026 intake starts from
`a5b4eb7d329b0700768b1fc72bb63cf58a9f5cd6` on
`CrispStrobe/quds_office_suite/main`. The workspace was initially empty; a new
checkout was acquired without overwriting prior local work.

- All 24 fork branches were inspected. The other 23 tips were ancestors of
  `main`, with no commits ahead of it.
- All four branches of the upstream `MohammedAsaadAsaad/quds_office_suite`
  repository were ancestors of fork `main`.
- Neither repository had an open pull request. All 30 recently updated closed
  fork pull requests inspected were merged.
- The latest integrated work includes #359 (Word VBA cell text), #360 (Mail
  retained-folder navigation and reconciled Office work), and #361 (Zotero
  selected-field context). No additional intake merge was necessary.
- The remote checkpoint branch is `codex/mail-durable-mutations-20261122`.
  Publication uses incremental commits with `[skip ci]`; local verification
  does not wait for the starved GitHub Actions queue.

## Selected increment

The ordered continuation in
[retained-folder-navigation](../../roadmaps/mail/retained-folder-navigation.md)
is durable foreground Move/Delete. Extend the existing command execution and
journal contract: commit frozen intent, then an applying marker, before any
provider mutation; retain typed outcomes; recover interrupted dispatch as
uncertain; never replay it automatically.

Move destinations retain exact account/folder identities. Read/flag observation
recovery must not be presented as move/delete membership reconciliation.
Existing provider semantics remain distinct: IMAP marks `\\Deleted` without
expunging; EWS, Gmail and Microsoft 365 use their existing trash/deleted-items
paths. A generic acknowledgement does not establish a new destination identity
or synchronized membership. Cached sources remain dated observations until an
explicit browse or sync refresh.

## Verification status

This first checkpoint records intake and intended acceptance only. Implementation,
local test results, review findings and final remote reconciliation will be
recorded here as work completes. No live-account, installed-platform, complete
desktop-client parity or CI-success claim is made by this checkpoint.
