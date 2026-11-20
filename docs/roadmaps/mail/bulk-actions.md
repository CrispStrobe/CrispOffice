# Foreground bulk read and flag actions

This increment adds explicit multi-message triage to the connected IMAP, EWS,
Gmail and Microsoft 365 hosts. It advances M04W without completing durable
remote commands, offline mutations, unified mail or desktop-client parity.

## User path

Check messages in the shared list, or choose **Select shown** to check the
currently visible loaded rows. Choose **Actions for selected messages**, then
**Mark read**, **Mark unread**, **Flag** or **Remove flag**. The open message and
the checked selection are independent; checking a row never opens its body or
changes its flags. The controls and outcome summary are localized in English,
German and Arabic, including right-to-left menus and enlarged text.

With focus in the message list, Space checks or unchecks the keyboard cursor,
Ctrl+A or Command+A selects shown rows, Escape clears the selection, and Enter
opens the cursor's message. The search field retains its own editing shortcuts.
Reader-only and cached hosts retain their previous opening behavior and expose
no bulk mutation controls.

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

This is a foreground session operation. Reports are not a durable command
journal and do not survive closing the view or restarting the application.
Cached mail stays read-only. Bulk actions do not fabricate a complete cached
flag snapshot from one confirmed field; cached views retain their last fetched
provider observations until the ordinary folder refresh saves a new view.

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

1. Repository-driven foreground sessions and a durable remote-command journal:
   persist intent before dispatch, retain uncertain outcomes across restart,
   qualify cancellation, UIDVALIDITY changes, conflicts and explicit recovery.
2. Account-wide/unified search, saved live views and conversations over the
   durable index, with explicit cache completeness and source identity.
3. Consistent archive/move/delete and broader bulk commands, rules and quick
   actions, using the same durable intent and recovery contracts.
4. Rich authoring, signatures/templates and Office attachment workflows;
   scheduling/Sent reconciliation, Calendar/People, shared mailboxes and
   security capabilities retain their provider-specific acceptance gates.
