# Explicit offline downloads for synchronized mail

This increment builds on [durable folder synchronization](durable-sync.md).
Synchronized headers now have a direct path to retained message content, so a
user can prepare mail for offline reading without first finding every message
in the separate foreground browser. Native IMAP, Exchange EWS, Gmail and
Microsoft 365 share the same download runner and owned local cache.

## User workflow

1. Connect to an account, select a folder and open **Synchronized mail**.
2. Start or continue header synchronization as needed. Opening the dialog and
   selecting messages still read local state only.
3. Choose **Download this page** to retain content for its current page of up
   to 100 headers. This includes rows hidden by loaded-page filters; the scope
   text states that explicitly. Alternatively, open a header without a saved
   body and choose **Download for offline reading** for that message alone.
4. Read the request's downloaded, already-saved and remaining counts. **Stop**
   cancels cooperatively. Completed transactions remain saved. Close cancels and
   drains active work before releasing the repository owner.
5. Start the download again to continue. Exact identities already in the cache
   are skipped, including after disconnect/restart. **Cached mail →
   Synchronized mail** can then read the saved bodies and attachments without
   credentials or a provider.

The selected reader refreshes from the local cache after a download. Download
controls are absent in the credential-free offline route. English, German and
Arabic labels explain header-only messages, limits, progress and recovery.
Neither reading cached mail nor downloading content marks messages as read,
submits messages, replays journaled commands or advances a sync cursor.

## Bounded and recoverable behavior

`MailBodyDownloadRunner` is a reusable pure-Dart core API. Its immutable input
contains at most 100 distinct local/remote message identities in one mailbox.
The run freezes this list, rejects cross-account/mixed-provider/mixed-IMAP-
generation inputs, and uses one session lease throughout. A provider result
must match the exact requested remote identity before it is rebound to the
canonical saved-header ID. The existing `studio-mail-cache-v1` encoding stays
unchanged.

Every message goes through the provider's existing MIME read budget: by
default 32 MiB raw, 32 MiB decoded payload, 8 MiB selected body text, 16 MiB per
attachment and 128 attachments, with the existing parser nesting/header/node
limits. The runner also verifies actual returned payload sizes. A Studio run
retains at most **64 MiB** of original raw bytes plus selected UTF-8 body/HTML
text and decoded attachment content. Metadata and database overhead remain
subject to the separate repository quota. This is a retained-content limit,
not a claim about exact network transfer or peak memory usage.

When the remaining run allowance cannot fit the next complete message, the
run pauses without saving a partial body. A subsequent explicit request skips
the saved prefix. A single message that exceeds the entire allowance reports
a quota failure; another message can be selected independently. Provider,
authentication, identity and storage failures stop further requests and retain
previous successes. There is no automatic retry. Reports retain acknowledged
commits even if cancellation arrives immediately afterward.

`StudioMailBodyDownloadCache` adapts the existing exclusively owned repository.
Its successful save atomically retains raw/body/attachment payloads, checks the
lease inside the transaction, and leaves drafts, Outbox records and synchronization
checkpoints intact. No schema migration or second repository owner is required.
Cache hits require a complete, exact-identity snapshot. Missing bodies remain
explicit; header counts never claim complete offline content coverage.

Account retirement, a replaced synchronized membership, dialog disposal or Stop
invalidates outstanding work. Paging and synchronization cannot race an active
download in the dialog. IMAP fetches retain their UIDVALIDITY checks and
`BODY.PEEK[]` behavior. EWS/Gmail/Graph keep their provider-owned identities and
complete-MIME checks; partial parsing is never presented as a retained success.

## Native Quit and draft preservation

The same intake included a native-menu change that directly popped Mail and
its dialogs. Native Quit now requests each route's guarded closure and waits
for an accepted transition to dispose before advancing. The composer therefore
saves the latest edit before its account owner closes, including an edit made
before the autosave timer fires. A pending or failed save keeps the composer
open and refuses native window closure. Once the save completes, Quit can be
requested again; a failed save remains retryable. No force-pop bypasses its
save guard.

## Qualification and next increments

The [local work record](../../validation/mail-offline-retention-20261121/README.md)
records the exact source checkpoints, captured branch intake and executed
tests. Live-provider credentials and installed-device acceptance remain separate
qualification work; deterministic provider seams do not establish them.

This delivers explicit foreground retention, not background synchronization or
full Outlook/Thunderbird/eM Client parity. Continue in this order:

1. Consolidate the separate foreground/synchronized paths into the reusable
   `QudsMailWorkspace`, retaining current account/folder authority, selection,
   error states and reader/composer ownership.
2. Add durable retention policy and restart scheduling with rate limits/backoff,
   per-folder coverage and explicit network/storage budgets.
3. Add account/folder-wide indexed queries with coverage and deduplication,
   then a unified inbox and conversations.
4. Extend the existing command journal to move/archive/delete with
   provider-specific destinations and uncertain-outcome recovery.
5. Continue server Drafts conflicts, signatures/templates, rich composition,
   undo/delayed sending, rules/categories and Office attachment workflows.

Offline retained content is a deliberate prerequisite: Thunderbird distinguishes
header synchronization from downloaded content needed for offline reading and
body search; Outlook documents scoped offline storage and offline workflows.
eM Client's mail capability list informs the later organization/composition work.
Official comparison sources checked 21 November 2026:

- [Thunderbird IMAP synchronization](https://support.mozilla.org/en-US/kb/imap-synchronization)
- [Outlook offline workflows](https://support.microsoft.com/en-gb/outlook/getstarted/how-to-work-offline-in-outlook-for-windows)
- [eM Client email features](https://www.emclient.com/features-email)

The dependency order is a Quds engineering choice. Provider/edition differences
remain explicit; no comparator defines a universal identical feature set.
