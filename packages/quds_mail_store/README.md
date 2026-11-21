# Quds Mail store

## Durable archive and search

`SqliteMailArchive` adds an independent original-message archive alongside the
live account cache described below. Use `openNativeMailArchive` from
`quds_mail_archive_native.dart` with an application-support directory and a
stable host/profile identity. Its separate `quds_mail_archive` database survives
live-account removal and cache deletion; it has an independent schema from the live cache. Persistent archive UI is currently native-only.

Each import commits exact MIME bytes, SHA-256 identity, envelope, FTS5 index,
and source/folder provenance in one transaction. Duplicate bytes share one
original; equal Message-ID headers never merge different originals. Searches
support phrases, field scopes, Boolean/negative clauses, bounded prefix
wildcards, date/size/source/folder/attachment filters and saved searches.
Attachment filenames are indexed; bounded text attachment content is opt-in.

`MailArchiveRunner` collects an explicitly selected connected mailbox using only
provider header/message reads. It validates scope, identities, leases and cursor
progression, deduplicates repeat runs, bounds failures and reports committed
counts on cancellation. It does not schedule jobs or delete source mail.

Verification checks originals, projections, provenance and FTS posting integrity.
Rebuilding can refresh projections with a supplied MIME codec. The first
maintenance page performs guarded whole-index FTS work; subsequent original and
projection checks are paged. Corrupt oversized values fail within configured
read bounds. Structured diagnostics contain fixed phases, timings, counts and
typed error codes, with optional verbose progress and no mail text or secrets.

See the [archive guide and MailStore parity matrix](../../docs/roadmaps/mail/archive-search.md)
for syntax, defaults, host examples and remaining gaps. The
[archive/search validation report](../../docs/validation/mail-archive-search-20261119/README.md)
records the original durable-archive milestone. The
[portability validation report](../../docs/validation/mail-archive-portability-20261119/README.md)
records that increment's scope and qualification. The
[restoration validation report](../../docs/validation/mail-archive-restore-20261119/README.md)
covers provenance-aware export restoration. The
[durable resume validation report](../../docs/validation/mail-archive-resume-20261119/README.md)
covers persisted restore receipts and their management; historical cache qualifications
remain separate below.

### Bulk export and directory import

`SqliteMailArchive.planExport` freezes all matching search/filter results in one
transaction, ignoring page limit/offset. The immutable `MailArchiveExportPlan`
contains ordered original IDs, byte sizes and provenance; later imports cannot
shift the selection. It contains neither message bodies nor the search query.

Import `quds_mail_archive_native.dart` for `NativeMailArchiveExporter`.
`exportPlan` creates a unique destination with exact `<SHA-256>.eml` originals
and a versioned `manifest.json`; `resume` explicitly continues that manifest's
selection from the same archive profile. Each run verifies original lengths
and hashes, reports `planned`, `written`, verified `existing` and `failed`
counts, and never overwrites conflicting originals. The manifest's digest is
unsigned. Ownership and staging files support cooperating-process exclusion
and interrupted-export recovery; this is not a database backup or mailbox
restore. Default export limits are 10,000 messages, 1 GiB of raw originals,
32 MiB per message, 16 MiB of manifest data and 20,000 provenance records.

`enumerateMailArchiveDirectory` streams EML/MBOX entries without loading their
contents, with optional recursive traversal and cancellation. It rejects links,
checks ancestors and reports skipped/error/limited outcomes. Defaults allow
10,000 files, 100,000 inspected entries, 32 nested levels and 4 GiB of accepted
source-file sizes, with a 32 MiB EML limit. Export `.pending-*` directories are
skipped only when their immediate parent has a regular, non-link
`manifest.json` marker. The importing host must still revalidate each file and
bound its reads; enumeration does not reserve a filesystem snapshot.

Studio's native directory-import action supplies those bounded readers,
explicit `mboxrd`/`mboxo` selection, relative-folder provenance and source IDs
combining full relative path hashes with record ordinals. It limits processed
message outcomes to 100,000 by default and reports partial, limited and
cancelled work separately. Source files are unchanged. Generic reimport of an
exported EML directory does not restore manifest provenance, archive profiles
or saved searches.

### Restore an exported archive

`NativeMailArchiveRestorer` accepts an existing destination archive and an
injected `MailCodec`. `inspect` reads a bounded export manifest without writing
anything. Show its message/byte/origin counts, source profile, creation time and
directory to the user before calling `restore`. The manifest is unsigned, so
its source labels require the user's trust. Inspection does not read the EMLs;
their exact sizes and hashes are verified during restoration.

```dart
final restorer = NativeMailArchiveRestorer(
  archive: destinationArchive,
  codec: messageCodec,
);
final inspected = await restorer.inspect(exportDirectory);
if (inspected case MailSuccess(value: final plan)) {
  // Present the plan and obtain the user's deliberate restore action first.
  final report = await restorer.restore(
    plan,
    // Set true only after the user chooses to resume recorded destination work.
    // false keeps full verification of all source EML files.
    resume: false,
    indexAttachmentText: false,
    cancellation: cancellation,
    onProgress: onProgress,
  );
  // Report saved, duplicates, failed, originsAdded and indexing warnings.
  // Show resumed/resumedBytes/resumedIndexWarnings separately from this run.
}
```

The source profile can differ from the destination. Each original, searchable
projection, all recorded origins and a durable restore receipt commit together. Identical originals are
verified and deduplicated; missing origins are added atomically. The existing
`archiveMessage` single-origin API remains compatible, and the new
`archiveMessageWithOrigins` API exposes this atomic operation directly.

By default, rerunning checks the source again and merges missing originals/provenance.
Confirmed earlier work remains counted after cancellation or a later error;
`bytes` includes verified successful duplicates. Changed manifests, observed
links/ancestors and conflicting files are reported. Source exports are read
only. Limits reuse `MailArchiveExportLimits` and destination archive quotas.
This is message/provenance restoration: archive dates for new records are set
locally, existing projections remain intact, and archive settings, saved
searches, credentials and provider mailboxes are outside the export format.
The archive guide documents filesystem race boundaries and failure semantics.

Pass `resume: true` to confirm previously committed destination messages before
reading unfinished source items. Each receipt verifies the retained original,
metadata, search projection and every expected provenance row. Missing provenance
is repaired through normal verified import; corrupt destination data is reported.
Already confirmed source EML files are not read again in this mode. The manifest
and unfinished source files must still exist. `plan.checkpoint` is advisory preview
data; receipts are looked up again during restoration.

Progress survives archive reopening and process termination, is isolated by
destination, and follows the decoded UTF-8 manifest digest (a UTF-8 BOM is ignored).
Moving the export directory preserves its progress. A changed manifest creates
a separate selection and invalidates an earlier preview. Counts include sparse
successful receipts, so a failed middle item can be retried without parsing
successful later items again.

Use `restoreCheckpoint(plan)` and `listRestoreCheckpoints()` to inspect saved
progress. `forgetRestoreCheckpoint(manifestSha256)` removes only that export's
progress; originals, provenance, dates and indexes remain intact. New imports
are bounded by `maxRestoreJobs` (64 by default), `maxRestoreReceipts` (100,000)
and the logical archive-byte quota. Jobs cost 192 logical bytes and receipts
256 each, without claiming actual disk usage. Records are never silently evicted.
Management reads and explicit cleanup remain available under lower write quotas,
within absolute supported read bounds. Archive schema v2 adds these tables and
counters to v1 without replacing existing mail. The archive schema evolves
independently of the live-cache schema.

## Live account cache

Profile-scoped Drift/SQLite persistence for the shared Mail contracts. Original
source is MIT. Schema v3 flags and the bounded native IMAP integration passed
the [current reconciliation qualification](../../docs/validation/office-current-reconciliation-20261119/README.md)
at `c268ce3b`, including **199 core/store test executions** within **801
application executions**, plus **42 separate launcher controls**. The earlier
`71edec2d` Mail-branch qualification is retained as historical evidence below.
Subsequent reconciliation and TLS-rejection cleanup have a separate
[captured synchronization record](../../docs/validation/office-main-sync-20261119/README.md),
whose incoming history is preserved by the current reconciliation.
Studio now provides foreground native account readers and submission adapters;
the durable outbox remains a separate host integration. Exact dependencies and
retained notices are in
[DEPENDENCIES.json](DEPENDENCIES.json) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Opening a store

The portable `quds_mail_store.dart` entry accepts a `QueryExecutor` owned
exclusively by its host. Use `quds_mail_store_native.dart` for a database below
an explicitly supplied application container, or `quds_mail_store_web.dart`
for separately configured same-origin SQLite WASM and worker assets. Both
platform openers enforce a single live profile owner. Browser storage fails
explicitly if durable safe storage or Web Locks are unavailable; it never
silently falls back to memory or unsafe concurrent IndexedDB.

| Public entry | Host responsibility | Qualification boundary |
| --- | --- | --- |
| `quds_mail_store.dart` | Inject an exclusively owned Drift `QueryExecutor`, `MailProfileId` and optional limits/clock | Common repository behavior is exercised using real SQLite; the host owns executor lifetime and exclusivity |
| `quds_mail_store_native.dart` | Call `openNativeMailStore` with the host's absolute application-support `Directory` | Linux x64 file storage, exclusive ownership, restart and process-crash cases are exercised; Apple packaging is separate |
| `quds_mail_store_web.dart` | Call `openBrowserMailStore` with a namespace and explicitly supplied same-origin SQLite Wasm/worker URIs | Entry and worker compile; actual browser persistence, quotas, Web Locks and reloads remain unqualified |

Use distinct host/profile identities for independently owned application data.
The native opener derives a path-safe namespace beneath the supplied container;
it does not choose a global storage location. The browser opener requires Web
Locks and refuses a conflicting existing database location. Hosts must verify
the pinned SQLite Wasm hash recorded in the dependency inventory and serve that
artifact with the compiled `tool/mail_store_worker.dart` from their origin.
No Wasm artifact or CDN fallback is bundled by this package.

Close the repository when its owning host session ends. A second live owner
through a platform opener returns a conflict. An injected executor must provide
the same exclusivity as the platform openers; bypassing that contract invalidates
startup-recovery assumptions.

## Implemented behavior

- Atomic sync page, membership, tombstone and cursor transactions. A page must
  present the cursor it read, and its account lease is checked before commit.
  A stale page returns `conflict`; domain streams publish successful commits.
- Authoritative IMAP ranges reconcile only existing memberships absent from the
  page's upserts in the same mailbox and UIDVALIDITY. Missing numeric UIDs never
  create tombstones. Actual removals retain pending edits for reconciliation and
  commit atomically with surviving headers and the cursor.
- Durable standard flags on header snapshots. An omitted snapshot preserves
  previously observed flags for that exact remote identity; an observed empty
  snapshot clears them. Header streams and local search return the stored flags.
- Compare-and-set draft revisions with immutable attachment blobs; frozen
  outbox wire bytes/envelope, validated state transitions and attempt history.
- Reopening captures interrupted attempts. Recovery makes them `uncertain`,
  never automatically retryable, and cannot relabel attempts begun by the
  current live owner.
- Bounded FTS5 metadata/plain-text search, without a provider or network port.
  HTML is retained but not interpreted by the indexer. Header updates read
  metadata only; they do not load cached attachments to rebuild the index.
- Separate mailbox memberships, durable pending intents and explicit
  reconciliation after resets, tombstones or interrupted application.
- Blob references for drafts, outbox, cache and editor pins. Cache eviction
  preserves outgoing and pinned data. Pins survive restart until explicitly
  released by the owning host.
- Logout preserves work and retires credentials through a durable host-vault
  cleanup journal. Account removal is destructive and local only. Removed
  account IDs cannot be reused. Retired profiles can reopen to finish vault
  cleanup but cannot create accounts or content.
- Versioned transactional schema, additive v1–v5-to-v6 migration, and explicit bounded
  reindexing of older content. Unknown schema versions are not reset.

Content errors are typed and redacted. No SQL exception text is returned to the
host. Logical per-account quotas include identities, cursor/journal metadata
and blob references; actual SQLite/browser storage errors remain authoritative
for physical capacity. The database is **not encrypted**. App-container access
and vault storage do not constitute database encryption or secure erasure.

## Durable foreground flag receipts

The schema-v6 flag journal is separate from the older `pending_operations` API.
It retains evidence for one explicitly selected foreground batch and exposes no
method to replay a saved batch. The host binds a `MailBulkFlagJournal` adapter to
the following repository operations:

| Operation | Durable boundary |
| --- | --- |
| `createFlagBatch(plan, subjects:, lease:)` | Atomically retain all frozen identities, desired flags and subjects; return an opaque `MailFlagBatchHandle` |
| `beginFlagAttempt(handle, index, lease:)` | Commit one applying marker before the host calls its provider |
| `recordFlagResult(handle, index, result)` | Retain typed provider evidence and any exact-identity cache flag patch in one transaction |
| `finishFlagBatch(handle, report)` | Retain the final ordered receipt, stop reason, persistence problem and untouched tail |
| `listFlagBatches` / `loadFlagBatch` | Inspect bounded account-scoped history without provider calls or message body reads |
| `clearCompletedFlagBatches` | Remove finished receipts with no applying or unresolved uncertain items |

The handle belongs to the repository instance that created it. Every mutation
compares a monotonic revision, and dispatch also requires a live account lease.
Recording a reply intentionally does not require the old view lease: an
in-flight acknowledgement can survive folder navigation. The original account
must still be active. Logout retires unfinished handles even if the account is
later resumed; account/profile removal deletes their local receipts and rejects
late callbacks. The host must let pending receipt writes settle before closing
the owning repository.

On exclusive reopen, a committed applying marker becomes **uncertain**, already
recorded confirmations/failures remain intact, and undispatched items remain
**not attempted**. The batch is closed as interrupted. There is no automatic
retry, offline replay, automatic provider reconciliation, or claim that a lost reply was
a server rejection. A transient result-write failure may still be finalized
once by its original owner; if storage cannot retain the known result, the
committed applying marker preserves uncertainty across restart.

A confirmed flag patches only that bit on an existing exact remote identity
whose full flag snapshot was already known. Other bits, message payloads and
folder completeness remain unchanged. Wholly unknown flags stay null. Affected
cached views receive a new revision while keeping their original capture time,
even when the desired bit already matches or the snapshot is unknown. An older
cache writer cannot pass its previous compare-and-set check and restore an
observation made before the confirmed command.

Each batch has at most 1,000 items (also bounded by `maxPageSize`), a subject
limit of 4,096 UTF-16 code units per item, and a combined identity/subject budget
of at most 2 Mi code units or the lower configured metadata limit. Each account
has a 200-batch ceiling. Creating or finishing a batch prunes clean completed
history to at most 100 receipts, preserving the receipt just finalized. Recovery
can turn additional undispatched batches into clean completed receipts; those
remain within the 200-batch ceiling until the next pruning write or explicit
cleanup. Running or unresolved uncertain batches are never pruned or cleared. Once 100
unresolved/running batches exist, new batches fail with `quotaExceeded` before
provider dispatch. The explicit read-only reconciliation below releases this
admission block only after every uncertain item has a definitive observation.

Listing uses explicit bounded pages and continuation offsets. Logical account
quotas include stored identity/subject bytes and reserve 256 bytes per batch
and per item for bounded typed outcome metadata at creation. This reservation
avoids new logical-byte admission for a reply; physical disk quota or I/O errors
can still prevent a later commit. It is not an estimate of SQLite file size.

### Explicit checks of uncertain flags

Schema v7 adds `beginFlagReconciliation(account, id, index, expectedRevision:,
lease:, isCurrent:)` and `recordFlagObservation(handle, observation, lease:,
isCurrent:)`. The first returns an opaque `MailFlagReconciliationHandle` for one
completed, unresolved uncertain item. The host then uses a `MailFlagObserver`
to read that handle's exact `message` identity and records the result using the
same lease. Both calls check optional host/provider scope callbacks. A check
never executes the historical command, resends mail, moves a message or deletes
provider content.

The later `MailStoredFlagResolution` has an item `index`, a `checkedAt` timestamp
and one of `matches`, `differs`, `missing` or `identityChanged`. Only the
requested read/flagged bit determines matches/differs. An IMAP generation change
refers to the original historical mailbox/UIDVALIDITY/UID, not a replacement
message. Missing/generation-changed observations leave the cache intact.
Present observations can patch the requested bit of an already-known exact
cache identity and advance its cached-view revision. Unknown flags stay unknown.

The original batch report, uncertain outcomes and problems remain historical
evidence. `batch.resolutions` holds separate immutable records;
`summary.reconciledCount` counts them and `summary.unresolvedCount` subtracts
them from the original uncertainty. Each item can be resolved once. Completed
batches whose uncertainties are all resolved are eligible for the same bounded
cleanup as other clean receipts. New observation metadata is subject to account
quota; failed storage leaves the original uncertainty and cache unchanged.

The handle captures the batch revision, repository owner, original lease and a
persisted profile observation epoch. SQLite triggers advance that epoch when
account routes, account state, messages, cached mailbox views, pending commands
or flag-journal evidence change. Any such intervening write conservatively
rejects a late observation, including unrelated writes within the profile; the
user can initiate another explicit check. Reopening, logout/resume, cancelled
leases and retired host/provider callbacks cannot revive an older handle.
Receipt, optional cache projection, view fencing and epoch changes commit or
roll back together.

The native opener uses SQLite WAL, `synchronous=FULL` and an exclusive profile
owner. Durability is the completed SQLite transaction boundary, subject to the
filesystem and device honoring flushes. This is local application storage, not
a backup, synchronized multi-device history, encrypted database or a guarantee
against device loss. Browser persistence requires its separately qualified
safe-storage setup; portable core/Node tests do not qualify a browser database.

## Repository use and lifecycle

Register an account explicitly with `createAccount`; ordinary account metadata
contains an opaque host-vault reference, never a password or token. Mailbox
memberships remain separate from messages and their provider identities. IMAP
keys retain mailbox, UIDVALIDITY and UID. `listHeaders` supports bounded pages;
`watchHeaders` supplies a bounded first-page stream.

When saving a draft, supply its expected prior revision. A new row uses
`expectedRevision: null`; an existing row advances its revision by one. Queue
prepared immutable wire bytes and an explicit submission envelope separately
from the editable draft. Persist the `submitting` attempt before invoking a
future transport adapter. Outbox saves compare prior state/attempt identity,
reject replacement payloads and illegal transitions, and prevent historical
attempt-ID reuse.

Call `recoverOutbox` after reopening and before coordinating new submissions.
An interrupted `submitting` entry becomes durably `uncertain`; this cannot prove
server rejection and does not authorize automatic resend. The repository does
not contact an SMTP server, mark recipients delivered or reconcile a real Sent
folder. Those behaviors belong to the later provider/submission milestones.

`enqueueOperation` records local provider intent before execution. A reset,
tombstone or interrupted applying operation leaves an explicit reconciliation
state. Acknowledgement/cancellation is separate from issuing a fresh intent.
Cache deletion cannot remove blobs referenced by drafts, outbox payloads or
editor pins. Release pins explicitly when the owning editor no longer needs
the snapshot.

Logout invalidates the supplied account session, preserves local work and queues
credential cleanup. The host deletes the referenced credential in its own vault
and acknowledges that exact cleanup item. `resumeAccount` requires fresh host
authorization and a usable credential reference. Explicit account/profile
removal deletes local data without contacting a provider; retired identifiers
cannot be used to recreate content. Cleanup acknowledgements remain available
after profile retirement.

## Resource bounds and schema behavior

`MailStoreLimits` supplies configurable work and logical-capacity bounds. Defaults
include 32 MiB per blob, 64 MiB per transaction's blobs, 2,097,152 UTF-16 code
units of metadata input, 256 MiB of logical data per account, 100,000 messages per
account, 1,000 rows per page, 65,536 indexed code units per message, 256 query code
units/16 query terms and at most 200 search results. JSON escaping is accounted
for separately from input metadata, and physical SQLite/index overhead is subject
to actual platform quota errors. These limits are not a measured mobile memory
budget.

An authoritative `MailSyncPage.imapRange` can remove more existing memberships
than the page's incoming row count. The repository scans at most the configured
`maxMessagesPerAccount` stored memberships (plus one overflow sentinel), using
their decoded scoped identities. A range does not enumerate its numeric UID
space, so a sparse range can extend through UID 4,294,967,295. Reopening with a
lower message limit rejects an oversized mailbox scan before mutation. Incoming
upserts and explicit tombstones still obey `maxPageSize` and metadata limits;
the final account quota remains authoritative for the resulting journal/data.
The `resetRequired` flag retains its separate full-mailbox reset semantics.
No schema migration is needed for range reconciliation.

Before reading a stored payload, the repository checks blob length metadata and
aggregate size before transferring BLOB bytes. It then checks content hashes.
Reopening under tighter limits can return `quotaExceeded` while retaining the
stored content. Local indexing decodes metadata without loading original or
attachment bytes, and it does not interpret HTML or fetch remote content.

The current schema is version 7. The retained v1 through v6 definitions support
reproducible upgrade fixtures. Version upgrades preserve existing rows and
advance schema state transactionally. Existing messages acquire unknown flags,
never an invented read/unread state. The nullable constrained bitset stores only
the five durable standard flags. Version 1 content enters the FTS index only
through bounded explicit `reindex` calls; the existing v2 index remains intact.
Version 4 adds a separate bounded `local_accounts` directory without changing
message, draft, Outbox, blob or search rows. `MailLocalAccountDirectory` records
non-secret verified routes for hosts that already established a connection.
It admits at most 100 records, prevents identity replacement and compares the
connection revision on shortcut removal. It does not store credentials or
invoke providers. Removing a shortcut cannot cascade to account content. See
the [offline-account guide](../../docs/roadmaps/mail/offline-accounts.md).
Version 5 adds ordered, partial foreground mailbox views with capture times and
revision checks; it does not replace synchronization cursors. Version 6 adds
the foreground flag journal described above, preserving all prior tables.
Version 7 adds per-item observation records and a persisted freshness epoch;
it never rewrites prior uncertain outcomes into confirmations.
A failed migration rolls back, and an unknown future version returns
`unsupported` instead of resetting the database.

## Qualification boundary

### UID discovery and cursor freshness

The [UID discovery report](../../docs/validation/mail-uid-pagination-20261119/README.md)
records bounded stored-range reconciliation, the v3 monotonic cursor repair and
source-bound combined qualification. The first 1,000-execution checkpoint at `960fb72f` predates that repair; it is
retained separately. The updated provider must reject stale completed-sweep
pages through the store comparison without restoring expunged data. Historical
counts below remain attached to their original sources.

### Historical reconciled source — PASS at `c268ce3b`

The [current reconciliation report](../../docs/validation/office-current-reconciliation-20261119/README.md)
binds 801 application executions (731 distinct cases) and 42 launcher controls
to `c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e`. The native gate passed 602 cases;
the core/store gate passed 199 VM/Node executions. The direct TLS-rejection
cleanup and strengthened assertions are included. Application, configuration,
and test inputs are unchanged by later documentation/publication reconciliation;
this README is the one explicitly reviewed documentation-input update.

### Inherited main qualification — PASS

The [Office completion report](../../docs/validation/office-main-completion-20261119/README.md)
binds **836 application executions** and **78 separate Python controls** to
source `5569c055a021c893e941fc54d40499ad9d96a5db`. Its fresh core/store gate
passed 199 executions; native transport, MIME, UI and shared protocols passed
602, and the additional Node boundary/MIME gate passed 35. Strict analysis,
formatting and browser entry/worker compilation also passed. These results
remain tied to that inherited source; compilation does not qualify actual
browser persistence.

The subsequent TLS-rejection cleanup restores disconnected and unauthenticated
state for a failed direct upgrade while preserving a newer connection generation.
Its fresh focused gate and incoming-ref reconciliation are recorded separately
in the [Office synchronization report](../../docs/validation/office-main-sync-20261119/README.md).
Neither the 836-execution main receipt nor the earlier 631-execution receipt is
counted as a new run of that continuation.

### Historical Mail-branch qualification — PASS on `71edec2d`

The following gates qualify the earlier published source
`71edec2de364805113d18e0f1d7edbb1f00467e5`, tree
`8b7443bd15be09276764f62934b9d8ce32a6be68`, and its unchanged runtime inputs.
They are retained independently of the later main and continuation results:

| Gate | Passing executions | Cohorts |
| --- | ---: | --- |
| [Core/store](../../docs/validation/mail-m06-resume-20261119/final/mail-final-receipt.json) | 199 | 31 core VM, 31 core Node, 95 native store VM, 42 portable store Node |
| [Native integration](../../docs/validation/mail-m06-resume-20261119/final/native-final-verification.json) | 376 | 70 transport, 244 fork, 32 MIME, 30 reader |
| [Additional Node](../../docs/validation/mail-m06-resume-20261119/final/node-final-verification.json) | 56 | 15 transport, 32 MIME, 9 fork |

All **631 executions passed with zero failures and zero skips**. The native
transport cohort contains 12 configuration, 39 protocol, five actual
SQLite/coordinator and 14 socket controls. The store results include v1/v2-to-v3
migration, reopen, rollback, unknown-versus-observed flags and scoped identity
preservation. Strict analysis, formatting, offline lock enforcement, browser
entry/worker compilation and whitespace checks passed. Separately, **66 Python
controls passed**: 42 Mail launcher, 20 plan-runner and four runtime-restorer.
The [independent evidence audit](../../docs/validation/mail-m06-resume-20261119/final/evidence-audit.json)
checks raw events, case lists, hashes and the common source/runtime identity;
runtime repetitions are not distinct scenarios.

The [transport package](../quds_mail_transport/README.md) remains an initial,
partially implemented M06 foundation with these local gates complete. Real Linux
loopback implicit TLS/STARTTLS, default-trust and
hostname rejection, and stalled-handshake cancellation/deadline cleanup passed.
Deterministic partial-write fixtures verify ordering and abort behavior; they
do not qualify Windows socket semantics or operating-system backpressure.
Those historical gates predate discovered-UID pagination beyond the initial
high-UID ceiling. The current authoritative-range increment and cursor-freshness
repair are recorded in the [UID pagination report](../../docs/validation/mail-uid-pagination-20261119/README.md).
OAuth hosts, authorized live-account interoperability, SMTP and the mailbox UI
remain separate work.

### Earlier baseline pass and retained failed attempts

The [19 November continuation](../../docs/validation/mail-m06-resume-20261119/README.md)
records the earlier Mail gate **PASS** on source
`479e1e038af0467b7f07b35d80bac9e4cc60a198`: **186 passing test executions**, zero
failures and zero skips, comprising 30 core VM, 30 core Node, 87 native store VM
and 39 portable store Node cases. The 42 Python launcher regressions, offline
lock enforcement, strict analysis, formatting, browser entry/worker compilation
and whitespace checks passed. The accompanying 72-suite Office/reader gate
passed **1,230 cases** on the same frozen baseline. Original logs, case lists,
archive indexes and source/runtime identities are retained in the dated record.

These baseline results predate schema v3 and native transport and are not
included in either later integrated total. The continuation also retains the
failed attempts at `da78c0bb` (test-only constant-set/import diagnostics) and
`e734e3bd` (a process-state read race in a Python cleanup control). Their repairs
preceded the complete rerun on `71edec2d`; the failed receipts remain historical.

### Historical failed store attempt

The earlier combined attempt on source
`8a6105a7ec217b48105d171703c8d0294c7d2dc6` observed 30 passing core VM tests,
30 passing core Node tests, 87 passing store VM tests and 39 passing portable
store Node tests. These are separate runtime cohorts. The overall runner result
was **FAIL**, caused by two test lint infos and a formatting mismatch in
`native_platform_test.dart`.

Disk exhaustion then prevented command execution. The two lint repairs and a
stricter event parser with 18 new parser regressions were saved in recovery
checkpoint `7848eca0eec8e291cd88ed6e353151508b77784e`; those changes had not run
and the native-platform formatting repair remained open at that checkpoint.
The fresh baseline pass above validates the subsequent repairs. The
[qualification summary](../../docs/validation/mail-store-20261118/checks/receipt.json)
is a recovered observation record, not the original raw qualification receipt.
Original aggregate logs/source manifests and additional review/late Office raw
evidence remain local and were not uploaded. See the
[M05 report](../../docs/validation/mail-store-20261118/README.md) for recovery
steps and preserved evidence boundaries.

The historical and earlier baseline native cohorts include seven file-backed migration cases
and five Linux SIGKILL transaction scenarios. The latter cover interruption
after sync-record writes, before cursor write, after draft-blob writes, after an
outbox write and after a submitting attempt has committed. They verify
reopen/recovery of the tested process failures; they do not establish power-loss
durability or qualify later unexecuted edits.

Portable serialization, configuration and browser-error mapping can run in
Node. They do not execute a browser SQLite filesystem. Browser entry/worker
compilation also does not establish storage persistence, actual browser quota
errors, reloads or Web Locks behavior. Those runtime gates remain **NOT RUN**.
The initial native IMAP adapter is implemented separately. Its real Linux
loopback TLS controls passed; live-account interoperability, other target
platforms, OAuth host flows, SMTP/composition, the mailbox UI and product-specific
Apple packaging remain open.

The host must finish acknowledged vault cleanup, supply its own application
container and browser assets, and obtain new provider authorization before
resuming a logged-out account. No credentials, provider endpoints, real mail or
external services are required by the test fixtures.

## Local qualification

Resolve the committed workspace lockfile using the pinned Flutter/Dart
toolchain. With Node available, run the launcher regressions and use a fresh
qualification output directory from the repository root:

```bash
python3 tools/mail/test_check_store.py
python3 tools/mail/check_store.py --flutter-sdk /path/to/flutter \
  --offline --direct-tests --command-timeout 300 --output /path/to/fresh-store-checks
```

The runner performs analysis, formatting, core/store VM checks, the selected
portable Node suites and browser entry/worker compilation. It records raw test
events, substantive case counts, source hashes before/after execution and the
browser runtime gap in `build/mail-store-qualification/receipt.json`. Failed or
interrupted runs replace an earlier PASS receipt. The corrected launcher and
42 regression cases passed on the final frozen source; retain each subsequent
run's raw evidence before removing build outputs. The integrated flags/transport
acceptance record above is separate from the earlier baseline.

The native crash cases start child processes and send SIGKILL to the process
that owns SQLite; run them in an environment that permits those operations.
The runner uses no hosted CI status.
