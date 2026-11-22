# Changelog

## Unreleased

- Add schema v15 for authoritative move identity transitions. Retain confirmed
  replacement identities with journal receipts and atomically reconcile eligible
  retained cache memberships behind a dispatch epoch fence. Preserve original
  capture times, coverage and provider cursors; keep source message bytes and
  avoid inventing destination bodies. Stale or unavailable cache projections
  retain the acknowledgement and require explicit refresh. Earlier receipt
  schemas migrate without inventing mappings or changing uncertainty.

- Bound move projection by the complete destination browse-window metadata,
  including retained destination identities. Preserve the confirmed receipt
  without cache writes if either browse window is absent or the combined window
  would exceed quota. Advance both existing browse revisions even when a moved
  synchronized item was outside the loaded source window, rejecting stale
  browse writes while retaining the original capture times and bodies. Isolate
  optional projection in a required savepoint so cache growth that exceeds the
  account quota cannot discard an otherwise admissible confirmed receipt;
  receipt quota and unrelated storage failures still roll back atomically.

- Add schema v14 for bounded latest membership evidence on uncertain Move/Delete
  receipts. Preserve all earlier schemas transactionally; retain original
  uncertainty and cleanup protection. Fence explicit checks by exact identity,
  account, repository owner, revision, epoch, lease and view; save evidence
  atomically without changing cached memberships, content or synchronization.

- Add schema v13 with exact account-owned move destinations in the existing
  foreground command journal. Preserve earlier receipts through transactional
  migration, include destinations in quotas and reject substituted commands or
  corrupt intent. Move/delete retain dispatch/restart uncertainty and history;
  they neither invent cache membership from a unit acknowledgement nor permit
  generic flag observations to resolve membership uncertainty.

- Add schema-v12 retained folder labels without changing the published v11
  exact folder identities, discriminator, ordering or 200-folder constraint.
  Preserve the published `folderScopes` and string `folderIds` APIs alongside
  typed folder selection. Keep atomic revision-guarded updates and migrate
  pre-v11 definitions as all folders without altering earlier payloads;
  reject corrupt empty explicit scopes rather than widening them. Filter cached
  search membership before counting and paging, bind cursors to a canonical
  folder set, preserve message deduplication and selected-folder provenance,
  and report selected IDs absent from the local catalog. Add a bounded local
  folder catalog reader that distinguishes known empty folders from absence.

- Persist Outbox scheduling in validated payload v3 with canonical UTC deadlines
  and monotonic revisions; read v1/v2 entries as unscheduled without losing
  earlier uncertainty. Require explicit revision comparison for schedule edits
  and all later state changes, including after a deadline is cleared. Reject
  stale timers, cancellation and edit-as-draft decisions across rescheduling;
  preserve frozen bytes, attempt history and transaction rollback guarantees.
  No database schema migration is required.

- Add schema-v10 account-owned compose settings and ordered Quick Text with
  atomic revision-guarded saves, bounded corruption reads and strict UTF-8
  decoding. Preserve settings on logout, clear them on account/profile removal,
  include them in account quotas, and leave drafts and frozen Outbox unchanged.

- Add schema-v9 saved header-search definitions with fixed cross-profile account
  scopes, case-insensitive unique names, bounded metadata, monotonic revisions
  and atomic create/update/delete. Preserve all earlier schemas, reject stale
  or corrupt definitions, and never store cursors, results or credentials.

- Add bounded account-wide cached-header search across synchronized memberships
  and saved browse windows. Reuse the Boolean query contract, deduplicate label
  memberships, retain folder provenance and body availability without loading
  payloads, and expose explicit scan continuation and local coverage metadata.
  Bind in-memory cursors to the unchanged account, query and repository owner;
  committed changes and reopen require a fresh search. No schema migration.

- Add schema-v8 synchronization checkpoints with monotonic per-mailbox
  revisions, last committed page times and explicit provider continuation.
  Commit them atomically with headers, memberships, tombstones and cursors;
  preserve unknown completion for legacy cursors until the next page commits.
  Add bounded `loadSyncMailbox`/`listSyncMailboxes` reads and corresponding
  observers, with immutable snapshots, stable local-ID pagination, separate
  local/provider continuation, metadata preflight and account isolation.
  Preserve browse windows, pending-operation reconciliation, drafts and flag
  history through synchronization resets, migrations and failures.

- Add bounded `watchMailboxView` and `watchMailboxViews` streams for saved
  browse windows and folder catalogs. Publish complete snapshots after
  successful commits, including flag journal acknowledgements and later
  observations, while keeping absent views distinct from empty folders.
  Preserve ordering, capture times, quotas and account isolation; coalesce
  updates while paused, drain cancelled reads and complete on repository close.

- Add schema-v7 read-only reconciliation of completed uncertain flag receipts.
  Retain the original uncertain outcomes and problems while recording one
  immutable matches/differs/missing/identity-changed observation per item.
  Bind checks to the exact account, provider identity, repository owner, lease,
  batch revision and a persisted epoch fencing newer commands, cache writes
  and account transitions. Host scope checks and cancellation roll back late
  commits. Update only the observed requested bit of a known cache snapshot;
  missing or replaced identities never evict cached content. Definitively
  resolved batches release unresolved capacity and become eligible for clean
  history pruning. Preserve released schema definitions and migrate atomically.

- Add schema-v6 durable bulk flag journals with frozen selections/subjects,
  sequential dispatch markers, typed outcomes, owner-bound revision checks,
  history paging and bounded completed-history cleanup. Exclusive reopen and
  logout preserve confirmations, recover applying markers as uncertain, and
  retain untouched items as not attempted without replaying provider commands.
  Atomically patch only a confirmed known cache flag and advance affected view
  revisions, including confirmations of already-matching or unknown snapshots.
  Preserve unrelated/unknown flags, old UIDVALIDITY namespaces,
  drafts, Outbox and older schemas. Bound retained clean/unresolved receipts and
  reject oversized persisted metadata before transferring it to Dart.

- Retain bounded, ordered foreground mailbox windows with timestamps, explicit
  partial scope, transactional revision checks and lease cancellation. Keep
  browse references separate from synchronization cursors and authoritative
  memberships, preserve cached messages across synchronization pruning, and
  migrate existing databases additively to schema v5.
- Add bounded explicit local mailbox-cache cleanup that preserves outgoing work,
  sync state and editor pins while freeing quota. Retain a durable view revision
  counter across cleanup/recreate, and preflight cached JSON before transferring
  it from SQLite, with exact decoded metadata budgets on reads.
  Explicit cleanup invalidates evicted search entries without reading old
  envelopes, so lowered metadata budgets and malformed envelopes do not block
  body cleanup.
  Retained authoritative headers can be rebuilt by bounded reindex or sync.

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
