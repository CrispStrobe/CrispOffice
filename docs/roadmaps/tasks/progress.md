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
  isolation and stale-snapshot revision checks. The host must recheck the local
  revision in its committing transaction.
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
  Unknown status/importance enums fail closed rather than importing defaults.
- Validation: **35 tests passed**, strict analysis and formatting clean,
  JavaScript import compilation and Node execution passed.
- Conditional writes are not advertised. A read/write race remains until live
  qualification establishes an atomic server contract. Host code must enforce
  discovery's protected-list metadata, persist pages/outbox atomically, fence
  disconnected accounts and retain tokens securely before enabling sync.
- No Microsoft account was connected. Personal/work account behavior, extension
  recovery and date-only display parity still require live acceptance tests.

Remote Graph commit: `c090f3072164297bb40c85ced7d1a1111d08d03a`.

## Checkpoint 4 — CalDAV codec and provider profiles

- Added `quds_tasks_caldav`: a bounded single-VTODO parser, common field
  projection, explicit patches, and retained original iCalendar data. No-op
  serialization is exact; unrelated properties, parameters, alarms, timezone
  definitions and UID survive supported edits.
- Kept civil dates, floating times, UTC and zoned wall times distinct. Zoned
  writes require a retained matching timezone definition; directly comparable
  DUE must follow DTSTART. Unsupported recurrence, delegation, relationship and
  duration changes fail explicitly instead of flattening advanced task data.
- Added credential-free generic, Nextcloud, ownCloud, Open-Xchange and mailbox.org
  profiles. The mailbox preset uses `https://dav.mailbox.org/` discovery, a
  dedicated DAV credential, and an opaque task-list URL supplied/discovered for
  that account. Its OX capabilities remain conservative until live testing.
- Fixed resource/line/depth budgets and content-line validation bound untrusted
  parsing and reject property-name injection.
- Validation: **35 tests passed**, strict analysis and formatting clean,
  JavaScript compilation and a real VTODO round-trip smoke in Node passed.
- **T3 is partial:** the codec/profile foundation performs no HTTP requests.
  DAV authentication, discovery, sync REPORTs, ETag conditional writes, token
  recovery and live server qualification remain required.

Remote CalDAV commit: `2195bd379747e5afc1e4e4a6e9263c34fae3dad8`.

## Checkpoint 5 — continuous checks and handoff

- Added `.github/workflows/tasks.yml`: all three task packages get formatting,
  strict analysis, Dart VM tests and portable JavaScript/Node checks with the
  repository's pinned Flutter SDK. YAML validation passed locally. Hosted CI
  completion is not established by the local checks.
- The integrated workspace resolves with `dart pub get --offline
  --enforce-lockfile`; `pubspec.lock` is unchanged.
- Total focused checks completed: **132 tests** (37 mail OAuth/loopback, 25 core,
  35 Graph, 35 CalDAV), strict/targeted analysis, formatting and all three
  portable smoke programs. See the linked validation record for limitations.
- All implementation increments are intended as independently reviewable remote
  checkpoints. The final checkpoint's SHA is available in GitHub history rather
  than embedded recursively in its own contents.

## Checkpoint 6 — CalDAV network provider

- Added Basic authentication, principal and calendar-home discovery, an exact
  collection path and per-operation privileges. Credentialed requests stay on the
  configured origin. VTODO filtering supports mixed collections.
- Added strong-ETag conditional update and delete, deterministic create with
  `If-None-Match: *`, read-only recovery after uncertain creates and canonical
  resource reads after successful writes.
- Added bounded multistatus parsing, sync-token continuation and reset, plus
  VTODO ETag/multiget fallback. Mock DAV and native loopback fixtures exercise
  these paths. The provider is implemented in `c9e05dca9`.

## Checkpoint 7 — durable inbound synchronization

- Added `quds_tasks_store`. Task snapshots and continuation state commit in one
  SQLite transaction. The worker resumes after restart and handles expired cursors
  while retaining prior rows until a full baseline completes.
- Account generations and database/list identity checks fence late results.
  Tested persistence, rollback, competing commits, disconnect during a request
  and CalDAV ETag reuse through the store.
- The store currently persists remote snapshots. Local editing, durable outbox
  intents, write acknowledgment and host scheduling remain T4/T5.
- Validation on Dart 3.13.7 passed for **119 VM tests** across Tasks Core,
  Graph, CalDAV and the SQLite store. Strict analysis and formatting passed
  for both changed packages, the CalDAV portability probe ran in Node, and
  the workspace resolved offline with the existing lockfile. Hosted CI and
  live provider accounts still need verification.

## Checkpoint 8 — durable outbound sync and Studio Tasks

- Added the SQLite outbox, offline edits, three-way merge and conflict resolution,
  revision-aware acknowledgments and persisted retry deadlines. Recovery uses
  reads and retains unresolved operations for later checks.
- Added the native Tasks pane with a device-local list, task editing and
  completion, search, and CalDAV and Microsoft To Do connection setup. Studio
  stores app passwords and refresh grants in the selected credential backend
  and keeps the active task list syncing during the desktop session.
- Microsoft sign-in requests Tasks access and offline access. Microsoft edits
  require an explicit opt-in while the atomic write contract is unqualified.
- Validation passed for **170 focused Dart VM tests**, three Studio Tasks widget
  tests, 65 related Studio Mail and shortcut regressions, and both adapter
  JavaScript/Node probes. The Tasks widget tests exercise offline persistence,
  completion, search, deletion, pane close, and secure connect and disconnect.

## Checkpoint 9 — live mailbox.org qualification

- Authenticated against mailbox.org and exercised create, UID-based recovery,
  update, live HTTP 412 on a stale If-Match, incremental sync and deletion
  tombstones in a disposable VTODO collection. Both task and collection
  deletion were verified.
- The deployed Open-Xchange server assigned opaque resource URLs, returned
  bare multistatus ETags and rejected a client-specified sync page size.
  Added profile-specific handling and fixture regressions.
- Reproduce with the [live mailbox runner](../../../packages/quds_tasks_caldav/README.md).
  Microsoft and Nextcloud live credentials are still required for their
  qualification. Extended fields, account revocation, shared lists and
  long-running cross-provider workflows remain outside this live check.

## Next execution sequence

1. Qualify Microsoft To Do and Nextcloud against designated accounts and lists,
   including normalization, conflict recovery, permission changes and revocation.
2. Extend the Studio workflow to multiple simultaneously connected accounts.
3. Continue T7-T9 with extended fields, additional providers and optional bridging.

## Validation and remote checkpoints

The entries above record completed scope, actual checks, remaining limits and
remote commits. A checkpoint is not a claim that the entire roadmap is finished.
Remote updates use the observed branch head and never force-push. A concurrent
Word proofing improvement (`d2cb6a99`) was fast-forwarded and preserved before
the final CI/documentation checkpoint.
