# Mail compose tools — incremental implementation

## Intake and scope

Baseline: `115f1c20131bf0157d047dfe2e9d704ddffb22a2` on remote `main`.
All 31 observed branch tips, all 101 PRs created since 20 November 2026
(#221–#321), and upstream main `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`
are already ancestors of that baseline. No open PR remained at intake.
The machine-readable branch and PR checks are retained beside this file.

Development branch: `work/mail-compose-tools-20261121`. Checkpoints are pushed
incrementally; publication will use a normal merge after current-main
reconciliation. GitHub Actions are not an acceptance dependency.

## Planned user-visible increment

- Account-scoped persistent plain-text signatures with independent defaults for
  new messages and replies/forwards.
- Named reusable Quick Text, inserted through the existing undoable Word editor.
- The same composition tools in native IMAP/SMTP, EWS, Gmail, Microsoft 365 and
  offline draft entry, with draft/outbox content retained as immutable snapshots.
- Additive SQLite migration, bounded validated metadata, revision conflicts and
  account/lifecycle guards; English, German and Arabic host controls.

This extends the authoring boundary in M07. It does not complete mail-client
parity, alias/SMTP-identity routing, rich HTML authoring, provider Drafts,
background delivery, rules or end-to-end encryption.

## Qualification

Implementation and local runtime checks are in progress. This initial
checkpoint claims only the intake checks above; later commits will record the
commands actually executed and their results.
