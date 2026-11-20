# Foreground bulk read and flag actions

This milestone extends the shared connected mailbox list in Studio. It covers
IMAP, EWS, Gmail and Microsoft 365 using the same frozen command plan and
four-outcome report. It is a bounded foreground capability on the route toward
desktop-client parity; durable command journals and repository-driven sessions
remain the next increment.

## User path

Select individual checkboxes or **Select visible**, then choose **Mark read**,
**Mark unread**, **Flag** or **Unflag**. Selection covers only currently matching,
already loaded headers in this folder, in their displayed order. It never means
all server messages. Newly loaded rows remain unchecked. Changing a filter prunes
hidden selections; changing account/folder or refreshing clears selection.
Sorting preserves selected identities. A checked message is independent of the
message currently open in the reader.

When the list owns keyboard focus, Ctrl/Cmd+A selects its visible rows, Space
toggles the cursor's checkbox, Escape clears checks, and Enter opens a message.
Typing in the search field retains normal editing shortcuts. Selection, search,
sorting and the bulk operation do not fetch message bodies or send mail.

The list clears the checked snapshot when the user invokes an action. During
execution, progress shows settled results and **Pending**, which includes the
currently in-flight request. **Stop after current message** allows that request
to finish and prevents later requests. There are no automatic retries.

The completed receipt shows four counts and a **Details** view with the frozen
subject and outcome for every selected message:

| Outcome | Meaning |
| --- | --- |
| Confirmed | The provider confirmed the requested flag state. |
| Failed | The provider explicitly certifies that no mutation occurred. Other independent selected messages may continue. |
| Uncertain | A mutation may have reached the server, or the provider supplied no reliable mutation evidence. The batch stops here. |
| Not attempted | No command was dispatched for this message. |

After an uncertain result, refresh the folder before another flag mutation. A
provider's certified stale-scope rejection also requires refresh, even when it
proves that this particular message was not changed; it remains a failed result,
not an uncertain result. The
uncertainty explanation remains available until refresh; dismissing a receipt
cannot clear the refresh requirement. A refresh obtains new observations and
does not replay the batch. Closing the view or changing the account prevents
subsequent dispatch and stale UI updates; an already confirmed remote operation
is not rolled back.

A stale-scope result also requires refresh when its original connection remains
open, even if the provider proved no mutation occurred. Its per-message outcome
remains Failed; requiring a fresh observation does not make that receipt
uncertain. A user-requested stop alone does not require refresh.

Controls, progress and outcome details are localized in English, German and
Arabic. Compact layouts keep controls scrollable and leave space for rows.
Cached-mail views have no bulk mutation controls.

## Identity, outcomes and state

Before the first asynchronous operation, the host freezes one to 1,000 unique
remote identities belonging to one account, provider and selected folder. IMAP
uses the full mailbox + UIDVALIDITY + UID tuple, never sequence numbers or
RFC Message-ID. Opaque provider IDs retain their local account/provider
namespace and the host's observed folder membership.

Both the core and host validate their scope before each dispatch. Menu choices
carry their selection generation when the popup opens, so an old open menu
cannot adopt a later selection or account. Host callbacks additionally retain
their provider/loader, session and observation revision. Account/folder refresh,
disposal and native identity changes retire the captured work.

Providers return content-free `MailProblem` values. The optional
`mutationMayHaveOccurred` evidence is deliberately independent of the problem
code: `false` certifies no mutation; `true` and an absent value are uncertain.
A pre-write identity conflict and a post-write confirmation conflict can thus
have the same code without being presented as the same outcome. Unexpected
callback exceptions are uncertain. IMAP, EWS, Gmail and Microsoft 365 annotate
their existing real mutation boundaries. Legacy providers without this metadata
retain conservative treatment. Cloud flag commands accept only explicit
request, authentication, resource or precondition rejections as no-write
evidence. Rate limits, timeouts and unfamiliar failures after dispatch remain
uncertain. This flag-command rule preserves the separate existing submission
outcome contract.

Only confirmed target flags update the live view. An unobserved unrelated flag
stays unknown. A successful in-flight acknowledgment is retained in the report
even if scope changes while awaiting it, but the host must not project it into
a new account, folder or observation. Reports are immutable and retain the
original selection order.

## Portable execution API

[`MailBulkFlagPlan`](../../../packages/quds_mail_core/lib/src/sync/bulk_flags.dart)
copies the selected identities and validates their shared scope. Its optional
`provider` argument checks the namespace inferred from those identities. Plan
IDs must be nonblank, contain no control characters and fit within 256
characters; `operationAt(index)` produces an explicit desired-state operation
with a stable `planId:index` ID.

There is one execution engine with two entry points:

- `MailBulkFlagRunner.run` accepts `MailResult<MailUnit>` callbacks, including
  `MailProvider.apply`, and delegates the evidence mapping to
  `MailBulkFlagAttempt.fromResult`.
- `MailBulkFlagCoordinator.run` accepts `MailBulkFlagAttempt` callbacks from
  adapters that already certify outcomes. The coordinator is single-use,
  including when its first run fails a predispatch scope check. Its separate
  cancellation token requests a stop after the current reply without cancelling
  the provider lease. The stateless runner performs no automatic retry or replay.

Both expose `shouldStop` and immutable progress reports. A coordinator's
`MailBulkFlagAttempt.failed` explicitly certifies no effect; a contradictory
`mutationMayHaveOccurred: true` problem still becomes uncertain. Certified
`cancelled` or `staleOperation` failures stop further dispatch. An uncertain
reply takes precedence over concurrent cancellation or scope change.

`MailBulkFlagReport.items` and `results` are the same immutable ordered list.
Each entry retains its frozen operation, identity, outcome and original problem.
For attempted entries, the operation is the exact object passed to the callback.
`stopReason` identifies why dispatch ended, while
`stopProblem` retains the associated problem. A host may keep a confirmed
in-flight receipt after its scope retires, but that receipt cannot authorize
publication into a different view. These APIs reconcile the earlier
[bulk-actions entry](bulk-actions.md) without introducing another runner or a
different persistence contract.

## Foreground and cache boundary

The report and command plan are in memory. There is no durable command journal,
offline queue, restart recovery, automatic replay or undo promise. Bulk changes
are reflected in the live view; reconnect and cached-mail views require a fresh
folder observation to retain the latest confirmed flags. This milestone does
not claim synchronized persistent-cache updates after every foreground change.

No dependency versions, authentication flow or database schema change is
required. Move, delete, archive, rules and scheduled operations are separate
capabilities with their own acceptance requirements.

## Validation and continuation

The [integration and local validation record](../../validation/mail-bulk-flags-20261120/README.md)
binds accepted tests to source hashes, records concurrent-source reconciliation,
and preserves raw logs and localized probes. Fake providers and protocol
fixtures qualify the implementation contracts; live provider accounts and
installed platform releases remain outside this increment.

1. Durable repository-driven sessions and a remote-command journal: persist
   intent before dispatch, retain uncertainty across restart, and qualify
   offline/reconnect, cancellation, UIDVALIDITY, conflicts and explicit recovery.
2. Account-wide/unified search, saved live views and conversations over a durable
   index with explicit cache completeness and source-message identity.
3. Consistent archive/move/delete, broader bulk commands, rules and quick actions
   built on the same durable intent and recovery contracts.
4. Rich authoring, signatures/templates and Office attachment workflows.
   Scheduling/Sent reconciliation, Calendar/People, shared mailboxes and security
   capabilities retain their provider-specific acceptance gates.
