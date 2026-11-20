# Changelog

## Unreleased

- Add a bounded non-secret local account directory with additive schema-v4
  migration, immutable route identities, monotonic connection revisions and
  compare-and-set shortcut removal. Preserve existing draft, Outbox, blob,
  cache and search state; reject corrupt metadata and storage failures.

- Atomically cancel a safely editable Outbox entry and create a distinct revision-zero draft, with full source compare-and-set, draft admission, blob ownership and quota rollback. Persist explicit uncertain closure without inventing provider acceptance.

- Add bounded, account-scoped draft metadata pages without resolving attachment
  blobs. Keep cleared revision markers out of normal pages and enforce an
  optional active-draft limit atomically with draft writes and quota checks.

- Atomically transfer a saved draft revision into a frozen outbox item and an
  empty next revision, closing the crash gap between enqueue and draft cleanup.
- Persist sticky outbox uncertainty in version-two payloads while reading
  version-one records. Enforce immutable payloads, fresh attempts and explicit
  acknowledged retry transitions through compare-and-set writes.
- Add guarded removal of reviewed terminal outbox records, releasing only
  unreferenced bytes. Preserve active and uncertain work; permit explicit local
  cleanup after confirmed later acceptance without implying recall or delivery.

- Persist optional draft editor state in a versioned payload while continuing
  to read existing version-one drafts. Account quotas include raw editor text.

- Add durable restore receipts committed atomically with originals, indexes and
  all provenance. Explicit `resume: true` verifies previously committed
  destination items and imports only unfinished items; default reruns still
  verify every source file. Report resumed counts, bytes and warnings separately.
- Upgrade archive schema v1 to v2 additively and account for bounded progress
  metadata in archive quotas. Add checkpoint inspection, listing and explicit
  removal without deleting messages, including cleanup under lowered quotas.
- Verify sparse retry, changed manifests, destination corruption, cancellation,
  cross-profile isolation and actual SIGKILL/reopen resume.

- Add `NativeMailArchiveRestorer` for read-only inspection and verified
  cross-profile restoration of exported originals with all recorded provenance.
  Repeated restores deduplicate originals, add missing origins, and retain
  confirmed progress after cancellation or partial failure.
- Add atomic `archiveMessageWithOrigins` and `MailArchiveImportResult.originsAdded`
  while retaining the single-origin `archiveMessage` API. The complete current
  message and its provenance roll back together on quota or storage failure.
- Cover changed manifests, source and codec substitution, existing corruption,
  bounded failures, and real importer SIGKILL/reopen/retry recovery.

- Add transactional `SqliteMailArchive.planExport` for an immutable selection of
  every matching original, its size and provenance, independent of paging.
- Add native bulk EML export and explicit manifest-based resume with profile
  binding, exact-byte/hash verification, ownership, staging and per-run counts.
  Preserve conflicting files and refuse plans exceeding configured budgets.
- Add `enumerateMailArchiveDirectory` for bounded, cancellable EML/MBOX walks,
  optional recursion, relative provenance paths, link rejection and explicit
  limits/errors. Skip recognized export staging without importing its manifest.
- Add a physically separate durable mail archive with exact original bytes,
  SHA-256 deduplication, transactional provenance/index writes, bounded FTS5
  query syntax, filters, saved searches and credentials-free archive profiles.
- Add native archive ownership/reopen support, explicit index verification and
  rebuilding, optional safe text-attachment extraction, typed error containment,
  cancellation/lease guards and content-free verbose diagnostics.
- Add a bounded read-only selected-mailbox runner with stable reconnect
  provenance, cursor-loop detection and truthful partial/cancelled run reports.
- Exercise native SIGKILL recovery, FTS posting corruption, metadata read limits,
  quota rollback, exact byte fidelity and independent cache/archive lifetimes.
- Persist observed read, flagged, answered, draft and deleted flags atomically
  with header/cursor updates. Omitted snapshots preserve existing observations.
- Upgrade v1/v2 databases transactionally to schema v3 with unknown flags for
  existing rows, retaining content, provider identities and the existing index.

## 0.1.0

- Add transactional scoped SQLite storage, bounded FTS5 search, durable
  draft/outbox/blob references, cursor preconditions and pending intent recovery.
- Add isolated native and explicit browser openers with exclusive profile
  ownership, typed storage failures and transactional schema migration.
- Preserve local work on logout, protect outgoing/editor blobs during cache
  eviction, and journal host credential cleanup across local removal/restart.
