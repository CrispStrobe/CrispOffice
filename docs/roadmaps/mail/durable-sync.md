# Resumable foreground folder synchronization

This increment connects the existing provider synchronization protocols to the
owned native mailbox repository and a visible **Synchronized mail** workflow.
It follows [repository-observed sessions](repository-sessions.md) and advances
M04W/M06 without claiming the complete shared workspace or background sync.

## User workflow

In a connected native IMAP, Exchange EWS, Gmail or Microsoft 365 account, select
a folder and open **Synchronized mail** (the sync icon). Opening the dialog reads
local state only. **Start sync**, **Continue sync** or **Check for changes**
explicitly starts one bounded run. Each run processes at most ten provider pages
of up to 100 records; lower provider limits still apply. Empty continuation pages
count toward that budget. A partial run can be continued from its last durable
checkpoint, including after closing the app and reconnecting to the same account.

**Stop** cancels the active run cooperatively. Completed transactions stay saved;
an uncommitted page cannot advance the cursor. Closing the dialog cancels and
drains its run, local reads and repository subscriptions before returning the
shared repository to its owner. Switching or retiring the account invalidates
old work even when a later connection has the same stable account identifier.

The dialog distinguishes no known checkpoint, a saved partial scan, and a
finished provider scan. It displays the observation time and the number of local
synchronized memberships. A finished scan does not claim that later server
changes are already present. Failure, authentication, unsupported capability,
conflict, cancellation and quota states preserve earlier saved progress.

The local view reads 100 headers per page, with deterministic repository order
and existing loaded-page search, filters and sorting. It can show folders larger
than the separate 1,000-header foreground browsing window by paging through
their synchronized memberships. **Cached mail → Synchronized mail** opens the
same retained folders without credentials or a provider. Only previously opened
and saved message bodies are readable there; a missing body is identified and
is never downloaded implicitly. Controls and scope text are available in English,
German and Arabic, including compact reader/back navigation.

## Data and lifecycle contract

`MailSyncRunner` reuses `MailSyncCoordinator` for each page. One run-wide account
lease spans the sequence. Its immutable report distinguishes completed, paused,
cancelled and failed runs, retains acknowledged commits after cancellation, and
rejects repeated continuation cursors before persistence. Raw storage/provider
exceptions become content-redacted typed failures. Progress callbacks cannot
turn an acknowledged transaction into a failure or authorize another account.
There is no automatic retry, provider mutation or mail submission in this path.

Schema v8 adds `mailbox_sync_state`. Each successful `commitSyncPage` writes the
headers, memberships, tombstones, provider cursor, monotonically advancing
checkpoint revision, observation time and continuation flag in one transaction.
Cursor compare-and-swap, operation leases, quota checks and injected failure
gates all cover that transaction. Legacy cursors from schemas 1–7 survive
migration; their completion remains unknown until a new page is committed.

`loadSyncMailbox` and `listSyncMailboxes` expose bounded snapshots and summaries.
`watchSyncMailbox` and `watchSyncMailboxes` observe successful domain commits.
Reads validate account/profile ownership, stored types, identity, metadata size
and configured limits before transferring payloads. They do not fetch bodies.
Headers use local-message-ID ascending pagination; the UI's search and alternate
sort choices apply only to its loaded page. Concurrent membership changes may
shift an offset page; this is a live local view, not a frozen export cursor.

Studio providers now use the same non-secret endpoint/login/sender fingerprint
as the durable draft/cache owner. A new connection still receives a fresh lease
and credentials. Provider cursors therefore retain their account scope across
reconnects, including cloud cursors that bind the local scope.
Sync headers map into the unchanged `studio-mail-cache-v1` local-ID encoding,
so previously saved bodies are reused without identity collisions. Independent
browse windows retain their original capture semantics and are not silently
treated as synchronized memberships.

Existing IMAP UIDVALIDITY reset and authoritative UID-range reconciliation,
EWS reset, Gmail history/reset and Graph delta handling remain provider-owned.
The host does not reinterpret opaque cursors or infer deletion from a missing
page. Reset/deletion retains drafts and flag-command receipts, and the existing
pending-operation reconciliation remains in force. Sync never replays a queued
message action or resubmits an Outbox entry.

## Qualification and limits

The [local work record](../../validation/mail-sync-foundation-20261121/README.md)
binds the changed source to executed local tests and remote checkpoints. It
includes repository intake, migration/restart/rollback tests, provider fixtures,
host/dialog tests and the precise portability scope. GitHub Actions queue time
is not an acceptance dependency.

This slice synchronizes headers for one explicitly selected folder at a time.
It does not fetch all bodies/attachments, schedule background work, replay
offline mutations, create a unified inbox, synchronize server Drafts, or add
account-wide search. Provider limits, authentication prerequisites and the
existing foreground browse limits remain. Deterministic tests do not establish
live-account interoperability, installed desktop/mobile acceptance, Apple
packaging or a complete Outlook/Thunderbird/eM Client parity claim.

## Next ordered increments

1. Move the synchronized folder/query/session path into a reusable
   `QudsMailWorkspace`, preserving selection and provider authority while
   replacing the remaining separate foreground browsing path. Add scoped body
   retention controls and restart/resume scheduling with explicit rate limits.
2. Add stable queries across selected accounts and folders, with coverage
   indicators and deduplication, then unified inbox, account-wide search and
   conversations. Extend beyond offset pagination where a stable snapshot is
   required.
3. Extend the durable command/recovery model to move, archive and delete,
   accounting for provider-specific destination identities and uncertain writes.
4. Continue provider Drafts conflict handling, signatures/templates and rich
   composition, delayed/undo sending, rules/categories and Office attachments.
   Qualify supported providers and installed platforms at each workflow boundary.

These priorities use the capability distinctions in
[Thunderbird IMAP synchronization](https://support.mozilla.org/en-US/kb/imap-synchronization),
[Microsoft's Outlook edition matrix](https://support.microsoft.com/en-us/outlook/getstarted/feature-comparison-between-new-outlook-and-classic-outlook),
and [eM Client mail workflows](https://www.emclient.com/features-email), checked
21 November 2026. The dependency order is a Quds engineering decision; no single
comparator edition defines every capability or supported provider.
