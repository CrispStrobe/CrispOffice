# Durable Studio drafts and interrupted-send recovery

This continuation advances M07 in the existing [implementation plan](implementation-plan.md).
The goal is one recoverable local composer per account across native IMAP/SMTP,
Exchange EWS, Gmail and Microsoft 365. It builds on the existing transactional
Mail store and the shared Word editing surface.

## Acceptance contract

- Preserve unfinished To/Cc/Bcc fields, subject, plain text, reply headers and
  immutable attachment snapshots, including drafts whose recipients are not yet
  valid for sending.
- Autosave while editing; expose pending, saved and failed states. Flush before
  closing or sending, and keep the editor open when a requested save fails.
- Scope recovery to a stable provider, endpoint, login and sender identity.
  Account switches must not expose another account's draft or accept stale
  callbacks. Credentials and OAuth tokens never enter the draft store.
- Compare revisions and serialize writes so delayed autosaves cannot overwrite
  newer edits, discard or a recorded submission result.
- Persist the possible-submission boundary before invoking a provider. Restarting
  after an interrupted send must retain the uncertainty warning and require the
  existing explicit delivery-check acknowledgement before another send.
- Clear a successfully accepted or explicitly discarded draft durably. A local
  cleanup failure after acceptance must never appear as an ordinary retryable
  send failure.
- Preserve bounded attachment bytes and original reply metadata through reopen.
  An external file changing or disappearing cannot change the saved draft.

## Implementation order

1. Capture current fork/upstream branches and PRs, reconcile completed work, and
   keep active unrelated work visible for a final refresh.
2. Extend typed persistence only where the existing draft contract cannot retain
   incomplete editor input or submission recovery state.
3. Add account-scoped native draft storage and host injection seams.
4. Connect debounced composer saves, explicit close, send and discard to the
   storage seam in both native mailbox hosts.
5. Exercise restart, storage errors, delayed saves, account isolation and
   interrupted/accepted submissions with local unit and widget tests.
6. Record actual local results, push incremental source checkpoints, refresh
   remote main, and merge the validated result without waiting for Actions.

## Remaining parity work

This milestone does not close M07. A repository-driven mailbox, draft list,
multiple simultaneous drafts, an inspectable queued outbox, undo-send/scheduled
sending, rich HTML composition, signatures/templates, unified inbox,
conversation views, full mailbox search, filters/rules, Calendar/People and
provider/installed-platform qualification remain separate increments. The
ordered work stays in [implementation-plan.md](implementation-plan.md), with
current completion boundaries in [status.md](status.md).

Drafts reside in the native application data directory. This does not establish
encrypted storage or server-side draft synchronization. Live-provider delivery
and installed-platform acceptance require their own evidence.

## Validation record

This planning checkpoint does not claim an implemented or qualified recovery
workflow. The implementation will need a continuation report under
`docs/validation/mail-draft-recovery-20261120/` with its actual local results.
Historical test totals in other reports retain their original source scope.
