# Tasks implementation progress

Started 2026-11-25 from remote main
`c9362e533cc62d5616fee207e196bc3c15d4c8d5`.

## Checkpoint 0 — plan

- Added the approved multi-provider [roadmap](README.md),
  [engineering plan](implementation-plan.md), and
  [provider qualification record](provider-qualification.md).
- Included Microsoft To Do, Nextcloud, ownCloud, mailbox.org/OX CalDAV,
  lightweight DAV servers, on-premises EWS, native OX, Vikunja and Planner.
- Documented account isolation, offline recovery, uncertain writes, field
  preservation, credential persistence, and the difference between fixtures and
  live qualification.
- Reviewed repository contribution rules and current public mail auth boundary.

Implementation starts with portable reconciliation, a Graph provider, a CalDAV
codec/profile foundation, and opt-in Microsoft task consent. Desktop Tasks UI,
durable task synchronization and live account qualification remain outstanding.

No user task service has been connected or modified for this planning checkpoint.

Remote plan commit: `77be5cf8c37b2fbc83bf5cc2a3fed716b1109eff`.

## Checkpoint 1 — explicit Microsoft task consent

- Added `MailOAuthConfiguration.includeTasks`, defaulting to false. Opted-in
  Microsoft authorization and refresh request `Tasks.ReadWrite`; Gmail rejects
  the option. Existing mail-only scopes are unchanged.
- Verified that an explicit token grant missing task permission is rejected and
  a downgraded refresh clears the unusable credentials.
- Updated the mail provider setup notes and package changelog. The current Mail
  dialog does not enable this flag automatically; Tasks UI integration remains
  a later milestone.
- Validation: formatter clean; targeted analyzer clean; **37 OAuth and real
  loopback fixture tests passed**. No real Microsoft login or task was used.
- Runtime and commands are recorded in
  [the validation record](../../validation/tasks-20261125/README.md).

Remote consent commit: `12dacab624cc655ac7b8734be9dfb0c83797fde2`.

## Checkpoint 2 — portable task core

- Added `quds_tasks_core`: scoped identities, typed fields/dates, explicit
  unchanged/set/clear patches, retained provider payloads, change pages,
  capabilities and failures.
- Implemented pure three-way reconciliation with sparse pending changes,
  independent-field merging, explicit field/deletion conflicts, account/list
  isolation and local-revision fencing.
- Local deletion conflicts when the remote version or retained unknown content
  changed. Missing evidence never silently authorizes deleting newer work.
- Coupled-field conflicts prevent a reopen/completion merge or independent
  start/due edits from producing an invalid pending write. Date comparisons do
  not invent conversions between different date kinds or timezone identifiers.
- Validation: **25 tests passed**, strict analysis clean, formatter clean,
  portable JavaScript compilation and Node reconciliation smoke passed.
- This is a complete portable planning library. It performs no network or
  database IO; durable transactions/outbox and host integration remain T4/T5.

Remote core commit: `47c075883aef5a4a81004d262e5c0a77a73ac945`.

## Checkpoint 3 — Microsoft Graph To Do adapter

- Added `quds_tasks_graph` with injectable account-bound tokens/HTTP and an
  optional native HTTPS transport. It implements list discovery, list/task delta
  pages, exact task reads, create, sparse update, delete, and read-only recovery
  of uncertain creates using a stable operation marker.
- Bound cursors to the account, operation and exact collection. Empty pages,
  repeated identities and tombstones retain their intended change semantics.
- Enforced transport deadlines, byte/item limits and no redirects. Mutations
  never automatically retry; ambiguous outcomes remain explicit.
- Preserved remote date/timezone pairs and unknown JSON fields. Completion
  changes inspect recurrence first; unsupported recurrence behavior is refused.
- Validation: **35 tests passed**, strict analysis and formatting clean,
  JavaScript import compilation and Node execution passed.
- Conditional writes are not advertised. A read/write race remains until live
  qualification establishes an atomic server contract. Host code must enforce
  discovery's protected-list metadata, persist pages/outbox atomically, fence
  disconnected accounts and retain tokens securely before enabling sync.
- No Microsoft account was connected. Personal/work account behavior, extension
  recovery and date-only display parity still require live acceptance tests.

## Validation and remote checkpoints

Each following entry records the completed scope, actual checks, remaining
limits and remote commit. A checkpoint is not a claim that the entire roadmap
is finished.
