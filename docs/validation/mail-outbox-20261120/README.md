# Durable Outbox continuation

Work in progress. This record does not claim completed validation.

## Scope

Continue the Mail parity roadmap from `c3df77d01ea9df4846e18131e69160d858f174ac`.
The separate account-management lane remains with its owner. This increment
connects the existing frozen-message state machine and SQLite store to a visible
foreground Outbox for native IMAP/SMTP, EWS, Gmail and Microsoft 365.

Acceptance requires atomic draft-to-outbox transfer; immutable MIME and complete
transport recipients, including Bcc; durable pre-submission attempt markers;
restart recovery; explicit send/retry/cancel; sticky uncertainty across retries;
account/session isolation; and bounded local terminal-history removal. Sending
and recovery never run automatically on reconnect or restart.

## Intake and preservation

`intake-initial.json` records all 26 branch heads and the 50 most recently updated
PRs observed before implementation. Main matches the previous PR #248 handoff.
Branch ancestry and unincorporated deltas are reviewed separately before merging.
Incremental task commits are preserved on `work/mail-outbox-20261120`.

## Validation policy

Use the repository-pinned Flutter/Dart runtime and actual local test results.
Do not use or wait for GitHub Actions. Retain command receipts and source identity
for accepted qualification. Historical test totals do not validate this change.

## Remaining work

Implement and locally qualify the feature, refresh remote intake, then merge the
reconciled result into remote main. Background sending, scheduling, undo-send,
server-side Drafts and live-provider/installed-platform qualification remain
outside this increment.
