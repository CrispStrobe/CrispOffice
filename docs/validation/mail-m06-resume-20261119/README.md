# Mail M06 continuation — 19 November 2026

**Historical Mail-branch qualification.** The complete 631 application
executions / 508 distinct scenarios and 66 Python controls below qualify
`71edec2d`, with evidence published at `700e5a35`. The [Office completion report](../office-main-completion-20261119/README.md)
records the later 836 application executions and 78 Python controls at
`5569c055`. Its Socket-compatible TLS implementation supersedes the manual
socket restriction described in this historical report.

The [current reconciliation](../office-current-reconciliation-20261119/README.md)
records fresh 801 application executions and 42 launcher controls at `c268ce3b`,
including the direct TLS rejection cleanup. The concurrent
[Office synchronization record](../office-main-sync-20261119/README.md) is also
preserved with its captured source and scope. Counts from different checkpoints
remain separate; no historical result is presented as a new execution.

## Historical Mail-branch qualification: PASS on `71edec2d`

The durable flags and bounded native IMAP foundation passed the complete local
qualification on published source
`71edec2de364805113d18e0f1d7edbb1f00467e5`, tree
`8b7443bd15be09276764f62934b9d8ce32a6be68`. The evidence and status documentation
are committed afterward; they do not change the qualified implementation.
M06 remains a partial milestone, with the remaining boundaries listed below.

All three gates ran sequentially on that clean source:

| Cohort | Runtime | Passing executions |
| --- | --- | ---: |
| Core contracts | Dart VM | 31 |
| Core contracts | Node | 31 |
| Durable store, migration and recovery | Dart VM | 95 |
| Portable store policy and codec | Node | 42 |
| Transport, configuration, SQLite integration and socket controls | Dart VM | 70 |
| Inherited IMAP/SMTP/POP and shared protocol regressions | Dart VM | 244 |
| MIME | Dart VM | 32 |
| Saved-message reader | Flutter VM | 30 |
| Transport configuration and unsupported browser boundary | Node | 15 |
| MIME | Node | 32 |
| Fork portable MIME boundary | Node | 9 |
| **Total** | **VM and Node** | **631** |

There are **zero failures and zero skips**. The 631 executions cover **508
distinct repository-suite/test-name scenarios across 48 distinct test files**.
Of those scenarios, 123 run on both VM and Node; there are no repeated cases on
the same platform. These are execution and named-scenario counts, not claims
that every possible behavior or platform has been tested.

The separate **66 Python tooling controls** also pass: 42 Mail launcher/event
controls, 20 shared qualification-runner controls, and four runtime-restoration
controls. They are not included in the Dart totals. Strict core/store analysis,
analysis of all 23 changed transport/fork Dart inputs, formatting, enforced
offline dependency resolution, browser entry/worker compilation, and whitespace
checks pass. The dependency lock is unchanged.

The [execution receipt](final/execution.json) records the commands and source.
The [Mail receipt](final/mail-final-receipt.json),
[native receipt](final/native-final-verification.json), and
[Node receipt](final/node-final-verification.json) retain complete gate results.
The native and Node gates each bind 5,027 materialized source inputs; their
11,164 and 11,163 runtime inputs respectively remain unchanged. The Mail gate
independently binds its core/store sources and direct launcher/native assets.
The checkout, commit and tree remain unchanged during the runs.

The [independent evidence audit](final/evidence-audit.json) reparses raw events
using source-bound parsers, checks complete requested-suite coverage, compares
case/error lists and log hashes, verifies committed Git blobs and runtime
identities, and reconciles the totals. This audits retained evidence; it is not
a second independent execution of the tests.

## Implemented increment

### Durable standard flags

`MailMessageFlags` represents read, flagged, answered, draft and deleted state.
An absent observation remains unknown; an explicit empty snapshot is different
and clears known flags. Upserts preserve known flags only for the same remote
identity. SQLite schema v3 adds a nullable constrained bitset and transactionally
upgrades v1/v2 without replacing existing messages, memberships or FTS data.
Listings, watch streams and search expose the stored snapshot. The passing
store cohort includes the new flag, migration, rollback/retry and reopen cases,
alongside existing file-backed and Linux SIGKILL recovery controls.

### Native IMAP provider

The new [transport package](../../../packages/quds_mail_transport/README.md)
implements the portable `MailProvider` boundary with validated manual endpoints,
current account-scoped host-vault credentials, required TLS, selectable folders,
bounded header/flag synchronization and exact on-demand full-message literals.
Scoped UIDVALIDITY cursors, records and absent-UID tombstones commit atomically
through the coordinator and durable store. Malformed, partial, duplicate or
out-of-range raw FETCH data fails the operation instead of creating a successful
prefix or false tombstones.

Flag writes verify the UID and re-read its resulting flags. MOVE requires the
server capability and confirms source absence. Delete marks `\Deleted` only;
it does not issue mailbox-wide EXPUNGE or CLOSE. An ambiguous attempted mutation
returns `conflict` for reconciliation, with no automatic retry. The public
browser entry returns typed `unsupported` without accessing the vault or codec.

The 70-case transport cohort comprises 12 configuration, 39 controlled protocol,
five real coordinator/SQLite integration and 14 socket/lifecycle cases.
The [native plan](native-test-plan.json) also runs 21 inherited fork suites,
all six MIME suites and all four saved-message reader suites. The
[Node plan](node-test-plan.json) checks the conditional portable boundary.

### TLS ownership and cancellation repair

The [exact-SDK review](review/tls-sdk-review.md) found that `SecureSocket.secure`
transfers ownership before its handshake future completes. Destroying the old
`Socket` cannot close a handshake stalled after that transfer. The repair retains
the actual TCP `RawSocket` throughout negotiation and the established secure
connection, races the handshake against abort, and rejects late completions.
It also preserves queued-write ordering, final write readiness, flush and close.

Ten of the new controls exercise real Linux loopback TLS in both modes:
stalled-handshake cancellation/deadlines, successful authenticated exchanges,
default-trust rejection and hostname mismatch rejection. The negative controls
require actual client certificate-validation errors, while successful exchanges
require a secure LOGIN. Two controls cover manual sockets. Two use a
deterministic RawSocket fixture for partial-write/close/abort contracts; they do
not establish operating-system backpressure or actual Windows execution.

The fork's manual `connect(Socket)` path retains ordinary and already-secure
I/O. Its default TLS upgrade now rejects explicitly because an externally
supplied socket has no retained TCP owner. Native upgrades use `connectToServer`,
as the provider does. Production certificate and hostname validation remain
enabled, with no bypass exposed by the supported provider API.

The [reviewed-source binding](final/transport-review-binding.json) matches the
37 effective transport-review paths plus the separately reviewed launcher-test
repair to the published source. Original findings, resolutions and development
evidence remain distinct from final acceptance.

## Failed attempts and repairs

The first integrated attempt at `da78c0bb` failed strict flag-test lint and
migration-test compilation: the equality test used two canonical constants in
a set, and Drift/test imports both exposed `isNull`. The repair constructs a
nonidentical equivalent value, explicitly checks equality/hash/set behavior, and
hides Drift's unused conflicting helper. See the
[first failed receipt](final/first-attempt-mail-receipt.json).

The next attempt at `e734e3bd` stopped in tooling preflight when a successfully
reaped child disappeared during `/proc` state reading. The test now accepts
missing-process errors while retaining zombie handling and failure for a live
child after the deadline. Process termination and Mail product code did not
change. See the [second failed receipt](final/second-attempt-mail-receipt.json).

Both attempts remain FAIL. Their extended native/Node plans did not start, and
partial observations are not included in the 631 final passes. Development
fixture/style failures and later controls are preserved separately; repeated
development runs are not added to acceptance totals.

## Preserved evidence

The [final evidence directory](final/) contains eight indexed archives:

- [Mail](final/mail-final.tar.xz), [native](final/native-final.tar.xz) and
  [Node](final/node-final.tar.xz): original receipts, raw events, case/error
  lists, command logs and source/runtime snapshots.
- [Preparation](final/preparation.tar.xz): runtime binding, Python controls,
  repair checks, execution/audit support and the independent audit report.
- [Source review](final/source-review.tar.xz): exact path manifests, immutable
  remote readback, review follow-ups and Office continuity, with separately
  identified historical attempts.
- [Development](final/development.tar.xz),
  [first failed attempt](final/first-attempt.tar.xz) and
  [second failed attempt](final/second-attempt.tar.xz): historical diagnostics,
  explicitly outside final acceptance counts.

Each archive has a matching `.tar.index.json` with member sizes and SHA-256
digests. Generated browser JavaScript outputs are inventoried separately;
compilation and Node execution do not establish actual browser persistence.
The [archive audit](final/archive-audit.json) checks packaged bytes against
those indexes and original evidence.

## Recovered source, incoming reconciliation and baseline

The continuation restored `eafcd80fdfbd7ff678a7a04fb9a9a98b5330ad00` from
`codex/mail-reader-20261118`. Three subsequently captured thesaurus/Zotero
commits were integrated into published baseline
`479e1e038af0467b7f07b35d80bac9e4cc60a198`, tree
`03b895b74affd80c54fa1c35dfa87a6eb1d645c6`. The five protected Notes
source/test/changelog files were preserved exactly. See the
[initial audit](incoming/post-integration-audit.json).

A final bounded capture added Notes/thesaurus evidence heads `c320f283` and
`df62b589`; their 68 changed paths are documentation/evidence only. Published
merge `faab20b9` preserves both parents. All **389 captured external refs** are
accounted for by ancestry or 14 freshly reverified historical equivalents. See
the [final incoming audit](final-incoming/post-integration-audit.json).

At baseline `479e1e03`, the fresh [Mail gate](baseline/mail-receipt.json) passed
186 executions, and the [Office/reader gate](baseline/office-verification.json)
passed **1,230 cases across 72 suites**: 233 engine, 887 editor, 99 Studio and
11 reader cases. Both had zero failures/skips. Original archives and indexes
remain under [baseline](baseline/). These historical results are not added to
final Mail counts.

The [source continuity audit](final/source-continuity.json) confirms that all
4,632 non-Mail package/app entries remain identical to that tested baseline.
A stronger 4,673-entry selection also includes unchanged MIME/UI source; all
materialized hashes match. Final Mail gates re-exercise affected MIME and the
complete saved-message reader. The dependency lock remains byte-identical.

The official Flutter 3.47.8 / Dart 3.13.7 archive, 176 hosted archives and pinned
SQLite 3.54.1/FTS5 native asset were restored and verified. The original
[runtime receipt](runtime/runtime.json) and
[restoration archive](runtime/restore-evidence.tar.xz) preserve that provenance;
the preparation archive contains the final workspace/native/Node binding.

## Remaining qualification and implementation boundaries

`maxUidScan` bounds the **highest numeric UID**, default 10,000 and maximum
100,000; it is not a message-count limit. Larger or sparse UID spaces return
`unsupported` before page fetch/commit and require discovered-UID pagination.
Direct on-demand retrieval of a specified high UID remains available.

System-browser OAuth/PKCE, redirects, token refresh, platform vault hosts,
authorized disposable-account interoperability, background scheduling,
IDLE/CONDSTORE/QRESYNC, SMTP/composition and the account-aware mailbox workspace
remain separate work. Actual browser storage, Web Locks, reload/quota behavior,
other operating-system TLS implementations and product-specific packaging are
not qualified by these Linux VM/Flutter/Node runs. The database is not encrypted.

No GitHub Actions workflow, job or status was queried, awaited or rerun.
Remote checkpoints use `[skip ci]` and non-forced expected-head updates, with
published trees checked against local source.
