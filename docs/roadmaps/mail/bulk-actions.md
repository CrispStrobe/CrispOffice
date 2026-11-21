# Foreground bulk actions — compatibility entry

The executable contract for connected IMAP, EWS, Gmail and Microsoft 365 bulk
read/unread/flag/unflag actions is [bulk-flags.md](bulk-flags.md). It defines the
user path, loaded-visible selection, stop-after-current behavior, all four
outcomes, scope guards, nullable flags and the foreground/cache boundary.

This path is retained from the concurrent `work/mail-bulk-actions-20261120`
implementation. The integration consolidates that work with
`work/mail-bulk-flags-20261120`; it does not maintain two dispatch algorithms or
two sets of acceptance rules. The peer's `MailBulkFlagCoordinator`, certified
attempts, provider validation, `operationAt` and receipt accessors remain
available alongside `MailBulkFlagRunner`, using one private execution engine.
`MailBulkFlagAttempt.fromResult` provides their shared provider-result mapping.
See the [portable API](bulk-flags.md#portable-execution-api) and the
[technical reconciliation record](../../validation/mail-bulk-flags-20261120/reconciliation.md)
for exact compatibility choices and preserved tests.

The original statement that every invoked provider failure must be uncertain
is superseded by explicit `MailProblem.mutationMayHaveOccurred` evidence.
For provider replies, `false` certifies no effect; `true` or absent evidence
remain uncertain. A coordinator's explicit failed attempt is also a certificate,
but contradictory possible-mutation evidence remains uncertain. Error codes
alone never establish non-mutation.

The [combined acceptance record](../../validation/mail-bulk-flags-20261120/README.md)
owns source-bound qualification and publication results. Earlier
[peer intake records](../../validation/mail-bulk-actions-20261120/intake-local.md)
remain historical evidence of their captured source, not qualification of the
combined runtime.

Selection covers the current loaded window, whose connected-host ceiling is
1,000 messages. Select shown respects the current query and quick filters. A
filter removes hidden rows from the selection; an invalid query clears it.
Sorting retains checked identities, and commands use their displayed order.
An action clears the checked set as it hands its immutable snapshot to the host.
Menu choices carry their original selection and generation even if Flutter
rebuilds the button while its popup remains open.
Loading another page does not check new rows automatically. No selection or
bulk action loads a body, requests another page, or sends mail.

## Execution and outcomes

Each action assigns an explicit Boolean value. It never toggles an unknown
flag. The host freezes the selected identities before starting and dispatches
one request at a time. Only confirmed target flags change in the current view;
an unobserved independent flag remains unobserved.

| Outcome | Meaning |
| --- | --- |
| Confirmed | The adapter positively confirmed the requested assignment |
| Failed | The adapter proved the mutation did not occur |
| Uncertain | An invoked request might have changed the server, but confirmation is unavailable |
| Not attempted | The batch stopped before this identity's adapter was invoked |

Every frozen identity has one outcome in the portable report, in original
selection order. The host displays all four outcome counts and a **Details**
view with each captured subject and its outcome. Subjects are frozen with the
selection, so later refreshes cannot relabel an earlier result. While a batch
runs, unsettled items are labeled **Pending**, including the in-flight request. Uncertainty stops
the batch immediately; later messages are not attempted. Another mutation
requires an explicit folder refresh, and there is no automatic retry.

Provider failures carry an optional `mutationMayHaveOccurred` receipt. Only an
explicit `false` certifies that no remote mutation happened and becomes
**failed**. `true`, missing evidence, and unexpected exceptions become
**uncertain**. The native loader preserves this receipt rather than discarding
it while translating provider errors. A certified cancellation or stale-scope
failure still stops later requests; a certified ordinary rejection can allow
the next selected message. A certified quota/rate-limit rejection stops the
remaining batch without an automatic retry or a forced refresh. Its provider
retry delay remains available in the receipt. Timeouts, unfamiliar responses
and server failures retain uncertainty until a refresh reconciles observations.

While a batch runs, the ordinary busy guards prevent new message operations,
folder/account switches and another batch. **Stop after current message**
prevents the next dispatch. It awaits the current bounded transport attempt
and retains its actual confirmation or uncertainty; stopping cannot retract a
request already sent. No detached future or background replay is introduced.

## Identity, refresh and publication

`MailBulkFlagPlan` copies and validates 1–1,000 unique remote identities in one
account/provider/mailbox. IMAP additionally requires a single UIDVALIDITY and
uses exact UIDs, never sequence numbers. Opaque provider IDs retain account and
provider namespaces. The coordinator is single-use. Optional immutable progress
snapshots preserve the full original order; observer failures do not rewrite provider outcomes. A consumed menu
callback cannot dispatch the same selection again after completion.

The hosts retain the original account session, provider/loader, folder
generation and selected membership. Native checks also reject changed mutable
UID, mailbox path or UIDVALIDITY projections. Guards run before every dispatch
and before final view publication. A confirmed in-flight result remains a
confirmation about its frozen identity even if the originating scope becomes
stale; it never updates a different account/folder or a disposed widget.

An account/folder transition resets discovery and selection state. Refreshing
the same folder preserves the query and sorting while clearing checked rows
and invalidating old checkbox, opening and action callbacks. A new selection is
required after refresh. A later return to a previously visited account/folder
does not revive an older callback.

## Persistence and provider boundaries

The original milestone was a foreground session operation. The later
[command journal](command-journal.md) persists native single/bulk flag intent
and receipts across restart and exposes read-only activity history from
connected or cached accounts. Cached mail stays read-only. Confirmed journaled
results atomically patch only an existing exact-identity cached target flag;
an unknown full flag snapshot remains unknown.

Native IMAP reuses the existing bounded action adapter, including server
UIDVALIDITY/existence checks and confirmation. EWS/cloud reuse their existing
provider assignments and confirmation paths. Requests are sequential and use
the existing transport timeouts and provider limits. This increment makes no
live-account, installed-platform, throughput or background-sync claim.

## Implementation and acceptance

- `quds_mail_core`: frozen plans, typed attempt receipts, four outcomes,
  cancellation and sequential foreground coordinator; portable VM/JavaScript.
- `quds_mail_ui`: optional selection controls, immutable callback snapshots,
  keyboard selection, refresh invalidation, compact and accessible controls.
- Studio native and EWS/cloud hosts: exact identity adapters, nullable flag
  publication, outcome/refresh notices and original-scope guards.

The [validation record](../../validation/mail-bulk-actions-20261120/README.md)
binds local checks, source intake, incremental remote checkpoints and the final
merge. Deterministic provider/widget tests do not qualify real account access
or real sends.

## Next increments toward full parity

1. Repository-driven foreground sessions, building on durable flag receipts and
   completed [explicit observation recovery](flag-recovery.md), with visible
   completeness, synchronization ownership and reconnect behavior.
2. Account-wide/unified search, saved live views and conversations over the
   durable index, with explicit cache completeness and source identity.
3. Consistent archive/move/delete and broader bulk commands, rules and quick
   actions, using the same durable intent and recovery contracts.
4. Rich authoring, signatures/templates and Office attachment workflows;
   scheduling/Sent reconciliation, Calendar/People, shared mailboxes and
   security capabilities retain their provider-specific acceptance gates.
