# Changelog

## Unreleased

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
