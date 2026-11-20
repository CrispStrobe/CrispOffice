# Foreground mailbox navigation

This continuation establishes the shared browsing foundation for M04W in the
native Studio Mail hosts: IMAP/SMTP, Exchange EWS, Gmail and Microsoft 365.
The reusable `MailMessageList` lives in `quds_mail_ui`; hosts retain account,
folder, transport, reader, composer and action ownership. The reader remains
the existing custom-rendered Mail surface.

## User path

1. Connect the intended account and select a folder. The initial request loads
   up to 50 headers. Message bodies are fetched only through an explicit open.
2. Enter text in **Search loaded messages** to match the loaded subjects and
   senders. Combine **Unread** and **Flagged** as needed. The count distinguishes
   matching rows from all loaded rows; this is not an account-wide search.
3. Click a row, or focus the list and use Up/Down or Home/End followed by
   Enter/Space. Moving focus alone does not fetch or open a message.
4. Choose **Load more** to request the next page. It remains available when the
   current filters show no matches. No request is triggered by typing a query,
   changing a filter, scrolling or moving keyboard focus.
5. On a compact window, **Back** returns from the reader to the same loaded
   list, query, filters and selection. Resizing keeps that list session.
6. Use the selected message's read/unread or flag/unflag control. The displayed
   state changes after provider confirmation; actions do not infer missing
   observations for a different flag. Refresh retrieves a new folder view.

English, German and Arabic labels cover the shared list, loaded-scope notice,
no-match state, pagination, confirmation and refresh requirement. Existing
folder navigation and compose/reply controls remain provider-host services.

## Shared list contract

`MailMessageListItem` requires a unique, nonempty stable ID, subject and sender;
date labels and read/flag observations are optional. The component snapshots
its input rows. Query matching is case-insensitive over subject and sender.
Unread means an observed `isRead == false`; Flagged means an observed
`isFlagged == true`. Unknown values satisfy neither filter. Both active filters
must match. A zero-match state is distinct from an empty loaded folder.

Opened-message selection and keyboard focus are separate. Appending or
replacing rows uses stable IDs rather than list positions. Filtering a selected
row out does not silently open another message or close the reader. A changed
account/folder `scopeId` clears the list's query, filters, focus and scroll
position. A same-folder refresh can retain local search intent. During a
pending provider operation, row activation and Load more are disabled while
local filtering remains available. Hidden compact lists cannot receive focus.

The list is virtualized and accepts host-localized strings. It performs no
provider operations itself. Hosts supply explicit open/load callbacks, validate
pages, choose quotas and surface errors. The shared package does not instantiate
Studio or CrispCloud globals, keep credentials or own a repository connection.

## Pagination and failure boundaries

All current native Studio hosts request at most 50 headers per page and stop
at 1,000 loaded messages. The final request is reduced to the remaining capacity.
The limit notice makes the finite loaded scope explicit; it does not claim that
older messages have been searched or that the whole folder is present.

EWS/Gmail/Microsoft 365 pages must remain under the requested limit and retain
the expected account, provider and folder scope. Duplicate identities within a
page, conflicting local identities, malformed cursors and repeated or cyclic
continuations are rejected before adoption. Valid replacements retain stable
selection. Failed pagination preserves the previously loaded rows. A transient
read failure offers an explicit retry; a conflicting snapshot requires Refresh.
There are no automatic retries.

The native IMAP adapter exposes `StudioMailMailboxBrowser` and
`StudioMailMessageActions` beside its existing reader/archive ports. Tests and
embedders with an older reader-only adapter retain the original first-page
behavior; the production native adapter uses the new bounded browser.
The browser verifies account, folder, UIDVALIDITY, UID order, page size and
continuation before projecting header metadata into the host's envelope type.
The full identity remains attached to each projected message. Later object
mutation cannot retarget a read or action to another UID or mailbox session.

## IMAP newest-first browsing

`MailImapHeaderBrowser.fetchNewestHeaders` is an optional core provider port.
Its descending browse cursor is separate from the ascending synchronization
cursor and includes the account/mailbox scope, UIDVALIDITY, initial ceiling
and next ceiling. A new view fixes its first UID ceiling. Arrivals above that
ceiling appear after Refresh; later pages do not silently expand the snapshot.
Newest means greatest UID, not a re-sort by the sender-authored Date header.

Each browse request performs at most one bounded UID SEARCH and one header FETCH.
Its discovery width respects the existing maximum discovered-UID count,
protocol-line length and aggregate response-byte quota. The response allocation
leaves headroom for control responses and headers; the original connection-wide
quota remains authoritative. No global quota is raised to accommodate a large
folder.

A positive SELECT count within the effective bound permits a whole-range
SEARCH, making small sparse folders efficient even with very large UIDs.
Large, unknown or invalid counts instead use a bounded numeric tail window.
When discovered candidates remain, the next ceiling is below the lowest chosen
UID; otherwise it is below the searched window. Empty or expunged windows keep
an older-range continuation where appropriate. Such a page may add no rows:
the user can explicitly load the next window. There is no hidden loop through
unbounded gaps, truncation of old candidates or sequence-number fallback.
Misleading server count hints still encounter the strict parser quotas.

Changing UIDVALIDITY invalidates the view, including an empty result. A cursor
from another account, folder, generation or synchronization operation fails
closed. The existing ascending fetch and durable synchronization contracts are
unchanged.

## Confirmed actions and nullable observations

Native IMAP now exposes both read/unread and flag/unflag actions. The transport
outcome must confirm the selected account/folder/generation/message identity
before the host changes the displayed observation. Callback completion after
disconnect, reconnect or changed selection cannot overwrite the current view.
An uncertain IMAP mutation requires Refresh before further mutations or paging;
it never automatically retries the write.

Read and flagged values are independently nullable in every host. A successful
flag action on a message whose read state was unknown leaves the read state
unknown; a successful read action cannot manufacture an unflagged observation.
Provider observations and explicit confirmations determine filter membership.
These foreground confirmations are not a durable offline command queue.

## Acceptance and remaining work

The [local report](../../validation/mail-workspace-20261120/README.md) records
the frozen-source commands, exact cases, runtime and incoming-work checks.
Development regressions include an actual 10,001-message inbox, 8,000 high
32-bit UIDs, sparse/empty windows, cursor isolation, compact reader/Back state,
keyboard-only activation, unknown flags, stale callbacks and the 1,000-row cap.
This fixture evidence does not qualify live providers or installed platforms.

The later [cached mailbox increment](cached-mailboxes.md) persists ordered
views of visited folders and explicitly opened bodies for credential-free local
reading. Multiple/offline local drafts and a visible durable Outbox have also
landed in their separate increments. M04W and full Outlook/Thunderbird/eM Client
parity remain open. Next, connect foreground rows to repository streams, add
durable synchronization and a unified inbox, and route supported actions through
durable commands with explicit reconciliation. Consistent move/delete and bulk
workflows, account-wide search, conversations, provider Drafts, undo-send and
scheduling retain their separate acceptance boundaries.
