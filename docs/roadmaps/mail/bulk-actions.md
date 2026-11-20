# Foreground bulk read and flag actions

The two concurrent bulk-action branches are consolidated into one connected
mailbox implementation. The [user workflow and outcome contract](bulk-flags.md)
covers IMAP, EWS, Gmail and Microsoft 365, with visible selection, keyboard
controls, progress, stopping after the current message, and per-message receipts.
Cached hosts remain read-only. This is a foreground operation; durable command
journals, offline replay and persistent cache synchronization remain separate.

## Shared execution contract

`MailBulkFlagPlan` freezes 1–1,000 unique remote identities from one account,
provider and mailbox. Its operation ID is nonblank, contains no control
characters and is bounded to 256 characters. IMAP also requires a single
UIDVALIDITY. An explicit provider, when supplied, must match every identity;
otherwise the provider is derived from the frozen identities.

Both public entry points use the same sequential execution loop:

- `MailBulkFlagCoordinator` retains its single-use contract and typed
  confirmed/failed/uncertain attempt receipts.
- `MailBulkFlagRunner` adapts ordinary provider `MailResult` values to a new
  coordinator for each explicit invocation. Only
  `mutationMayHaveOccurred == false` certifies a definite failed write. True,
  absent evidence and unexpected exceptions remain uncertain.
- `MailBulkFlagAttempt.fromResult` exposes the same provider-result conversion
  for direct coordinator callers. Contradictory possible-mutation evidence
  cannot be hidden by a failed-attempt certificate.

Reports preserve every original identity in order, including unattempted
messages. Immutable progress snapshots expose pending entries while work is
running. An uncertain result, explicit provider cancellation/stale-operation
failure, retired scope or a stop request prevents the next dispatch. Stopping
does not cancel the in-flight provider lease or erase an acknowledgment.
Caller guards are followed by a lease recheck, so a reentrant scope change
cannot dispatch another command. Retired, invalid or failed scope checks
require a fresh observation even when no command was sent.

A certified quota rejection stops the tail without automatic retry. Its
provider retry delay remains in the per-message and stop receipts. A quota
rejection alone does not require an uncertainty refresh. Cloud mutations use
an explicit rejection-status allowlist; unfamiliar 4xx responses, timeouts
and server failures remain uncertain after possible delivery.

## Host and compatibility boundaries

The list consumes its checked selection when an action is accepted. A later
action requires a new selection. Selection changes, filtering, refresh,
account/folder changes and disposal invalidate captured popup callbacks.
Space and Ctrl/Cmd+A operate only when the list owns focus; Escape clears
checks and Enter opens the cursor's message. Search editing retains its keys.

Native adapters with the explicit bulk capability retain provider mutation
evidence. The earlier combination of immutable observed records and message
actions remains usable through a conservative adapter. Typed loader failures
preserve optional mutation-boundary evidence; only explicit false certifies
non-mutation. Older failures without evidence remain uncertain.
Reader-only adapters and adapters without immutable remote identity records
receive no bulk controls.

All hosts retain their original provider/loader, account session, observation
revision and selected identities. They check scope before each dispatch and
before view publication. A late acknowledgment remains a receipt about its
frozen identity and cannot update another account/folder. Only confirmed target
flags change; unknown unrelated flags remain unknown. The localized outcome
panel and existing notices remain accessible while ordinary list work is busy.

The list accepts both `selectionRevision`/`bulkEnabled` and
`selectionScopeId`/`bulkActionsEnabled`, with the newer argument taking
precedence when both are supplied. `selectVisible` remains a label alias for
`selectShown`. A reusable `onCancelBulk` toolbar action remains available while
normal operations are busy; outcome counts expose live-region semantics.

The [earlier reconciliation qualification](../../validation/mail-bulk-reconciliation-20261120/README.md)
and [incoming PR #273 qualification](../../validation/mail-bulk-actions-20261120/README.md)
retain their exact historical source bindings. The final API union requires
its own source-bound acceptance; prior receipts are not relabeled current.
Deterministic tests do not claim real-account access or installed-platform
qualification.
