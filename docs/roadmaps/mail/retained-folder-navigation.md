# Unified retained-folder navigation

## User workflow

Open **Cached mail** for a saved account. The folder selector now includes both
saved browsing windows and folders whose headers were retained by explicit
synchronization. Each account/folder identity appears once, even if both sources
exist. The most recently saved folder comes first, with stable folder-ID ordering
for equal timestamps.

For a folder with both sources, choose **Saved browsing view** or
**Synchronized headers**. Synchronized headers are selected by default when
first opening that folder. A source switch is explicit and resets the displayed
list's filter/selection scope. The reader never combines the two header sets or
uses one source as a silent substitute when the other disappears.

Synchronized headers use pages of 100. **Previous page** and **Next page** read
only the local repository. The page label reports displayed positions and the
number of retained headers. Search, sorting, conversation folding and unread
counts apply to the displayed page; they do not imply a full-mailbox search.
The saved-search workflow remains available for broader local discovery.

Opening a message reads its retained body. A header without retained content
shows the existing missing-body explanation. **Refresh local mail** reloads the
local catalogs and selected source/page. It does not log in, contact providers,
download messages or start synchronization.

## Coverage is explicit

| Source | What the view represents | What continuation means |
| --- | --- | --- |
| Saved browsing view | Headers captured while visiting a connected folder | More server messages may exist beyond that saved window |
| Synchronized headers | Locally retained membership at the last committed synchronization checkpoint | Local page buttons browse retained headers; the separate scan status says whether provider synchronization had more work |

A finished scan is dated evidence, not a claim that later server changes are
already present. A saved empty folder is distinct from a missing source and from
a storage failure. If a read fails, the last valid data remains visible with an
error. Refresh can recover a one-shot or completed subscription. If the selected
source disappears while another source remains, the other is offered as an
explicit choice.

The dialog continues to support hosts that expose only saved browse windows.
No database migration, dependency change or provider API change is required.

## Repository and ownership contract

`studioMailRetainedFolders` merges the two bounded catalogs by exact
`MailMailboxId`, including its account/profile. Duplicate entries within one
source, foreign accounts, inconsistent folder/label semantics and malformed
metadata fail explicitly. The merged catalog has at most 1,000 folders. It keeps
both source observations so one source's count or timestamp never describes the
other. Synchronization catalog metadata supplies a renamed folder's label.

`StudioMailMailboxSession.selectSynchronized` observes a bounded local page and
validates its requested offset, count, continuation, provider/account identity,
unique message IDs and positive monotonic revision. IMAP rows must share their
selected mailbox and UIDVALIDITY. Synchronized snapshots remain genuine
`MailMailboxSyncSnapshot` values; no synthetic browsing window is written.

Every folder/source/page selection revokes earlier callbacks before waiting for
the old subscription. If retained membership shrinks past the displayed page,
the session selects the last valid page, or page zero for an empty folder, and
carries the revision fence into that repair.

The selected reader survives updates only while its local and remote identities
remain on the same displayed source/page. Membership removal, source changes,
page changes and cleanup invalidate pending body results. Catalog notifications
never load bodies implicitly or grant authority to mutate provider mail.

Closing drains catalog subscriptions, selected-view subscriptions and pending
local reads before releasing the shared repository owner. A cancellation error
does not discard its ownership handle or allow another observer to overwrite it.
Cleanup revokes the selected observer before waiting for catalog shutdown, so
old notifications cannot restore removed displayed content.

**Clear cached mail** retains the existing bounded cleanup policy. Drafts,
Outbox, pending operations, protected content and authoritative synchronized
memberships are not provider deletion targets. A synchronized folder can remain
listed after expendable body/cache data is removed.

## Parity sequence

This increment closes the split between two local folder readers. The next
ordered steps are:

1. [Durable foreground Move/Delete](durable-mutations.md) now continues this
   task with exact intent, dispatch markers, restart receipts and no automatic
   replay. Its separate provider-specific membership reconciliation remains open.
2. Provider-specific membership reconciliation: IMAP deleted flags and MOVE,
   Gmail label/trash behavior, EWS changed IDs and Graph immutable IDs.
3. Connected and multi-account navigation over the same repository contracts,
   retaining source coverage, account isolation and mutation capabilities.
4. Account-wide conversation discovery, indexed body search and rules, built on
   reliable membership and operation state.
5. Live-provider and installed-platform acceptance, plus separate background
   sending/sync, encryption and advanced interoperability work.

The benchmark is workflow-specific. Thunderbird documents the separation of
downloaded headers, offline bodies and search in its
[IMAP synchronization guide](https://support.mozilla.org/en-US/kb/imap-synchronization).
[eM Client's feature FAQ](https://www.emclient.com/faq-em-client-features)
documents offline account/folder downloads. Microsoft's
[new/classic Outlook comparison](https://support.microsoft.com/en-us/outlook/getstarted/feature-comparison-between-new-outlook-and-classic-outlook)
tracks version-dependent feature coverage. These references guide acceptance
targets; they do not establish full parity for this implementation.

Fresh local evidence is recorded in
[the qualification record](../../validation/mail-retained-navigation-20261122/README.md).
