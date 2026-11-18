# Quds Mail store

Profile-scoped Drift/SQLite persistence for the shared Mail contracts. Original
source is MIT. Exact dependencies and retained notices are in
`DEPENDENCIES.json` and `THIRD_PARTY_NOTICES.md`.

The portable `quds_mail_store.dart` entry accepts a `QueryExecutor` owned
exclusively by its host. Use `quds_mail_store_native.dart` for a database below
an explicitly supplied application container, or `quds_mail_store_web.dart`
for separately configured same-origin SQLite WASM and worker assets. Both
platform openers enforce a single live profile owner. Browser storage fails
explicitly if durable safe storage or Web Locks are unavailable; it never
silently falls back to memory or unsafe concurrent IndexedDB.

## Implemented behavior

- Atomic sync page, membership, tombstone and cursor transactions. A page must
  present the cursor it read, and its account lease is checked before commit.
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
- Versioned transactional schema, v1-to-v2 migration, and explicit bounded
  reindexing of older content. Unknown schema versions are not reset.

Content errors are typed and redacted. No SQL exception text is returned to the
host. Logical per-account quotas include identities, cursor/journal metadata
and blob references; actual SQLite/browser storage errors remain authoritative
for physical capacity. The database is **not encrypted**. App-container access
and vault storage do not constitute database encryption or secure erasure.

## Qualification boundary

The implementation is being qualified locally as the M05 increment. Evidence is
retained under `docs/validation/mail-store-20261118` in the repository. Native
tests and JavaScript compilation do not establish browser persistence or actual
browser quota behavior. Live accounts, providers, composition, the mailbox UI,
and product-specific Apple packaging remain later milestones.

The host must finish acknowledged vault cleanup, supply its own application
container and browser assets, and obtain new provider authorization before
resuming a logged-out account. No credentials, provider endpoints, real mail or
external services are required by the test fixtures.
