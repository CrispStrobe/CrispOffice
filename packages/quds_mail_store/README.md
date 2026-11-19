# Quds Mail store

Profile-scoped Drift/SQLite persistence for the shared Mail contracts. Original
source is MIT. Schema v3 flags and the bounded native IMAP integration passed
combined local qualification at `71edec2d`, including **199 core/store test
executions** and five transport/coordinator tests using actual SQLite.
The account-aware UI and SMTP remain subsequent work. Exact dependencies and
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
- Versioned transactional schema, v1/v2-to-v3 migration, and explicit bounded
  reindexing of older content. Unknown schema versions are not reset.

Content errors are typed and redacted. No SQL exception text is returned to the
host. Logical per-account quotas include identities, cursor/journal metadata
and blob references; actual SQLite/browser storage errors remain authoritative
for physical capacity. The database is **not encrypted**. App-container access
and vault storage do not constitute database encryption or secure erasure.

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

Before reading a stored payload, the repository checks blob length metadata and
aggregate size before transferring BLOB bytes. It then checks content hashes.
Reopening under tighter limits can return `quotaExceeded` while retaining the
stored content. Local indexing decodes metadata without loading original or
attachment bytes, and it does not interpret HTML or fetch remote content.

The current schema is version 3. The retained v1 and v2 definitions support
reproducible upgrade fixtures. Version upgrades preserve existing rows and
advance schema state transactionally. Existing messages acquire unknown flags,
never an invented read/unread state. The nullable constrained bitset stores only
the five durable standard flags. Version 1 content enters the FTS index only
through bounded explicit `reindex` calls; the existing v2 index remains intact.
A failed migration rolls back, and an unknown future version returns
`unsupported` instead of resetting the database.

## Qualification boundary

### Integrated schema v3 and transport qualification — PASS

The final gates bind published source
`71edec2de364805113d18e0f1d7edbb1f00467e5`, tree
`8b7443bd15be09276764f62934b9d8ce32a6be68`, and unchanged runtime inputs:

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
Discovered-UID pagination beyond the initial high-UID ceiling, OAuth hosts,
authorized live-account interoperability, SMTP and the mailbox UI remain open.

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
included in the final integrated totals. The continuation also retains the
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
