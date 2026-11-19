# Mail implementation status — 19 November 2026

Development continues on `codex/mail-reader-20261118` in the canonical Quds
repository. Fetch that branch when resuming before it is merged into main.
The source of product scope remains [README.md](README.md) and the ordered work
remains [implementation-plan.md](implementation-plan.md).

## Delivered code

| Area | Current implementation | Acceptance limits |
| --- | --- | --- |
| M00 baseline | The reader foundation reconciled its captured Office heads; the M05 continuation captures and reconciles incoming main, branch and PR history separately before implementation | Capture-specific dispositions and subsequent changes belong to the dated reconciliation receipts; historical test reports are not new results |
| M01 fork | Pinned enough_mail 3.0.0 source, retained MPL/provenance, supported public `mime_core.dart`, content-redacted diagnostics, strict charset admission, RFC2231 and date corrections, selected dependency/source inventory | Actual browser execution and per-product shipped dependency/notice clearance remain open |
| M02 core | Pure-Dart immutable DTOs, exact-byte ownership, profile/account/IMAP identity, nullable standard flag snapshots, budgets/capabilities, typed host/provider/store ports, cancellation leases, cursor compare-and-set and tested outbox state machine | Core/store and initial M06 integration passed local qualification at `71edec2d`; SMTP remains subsequent work |
| M03 codec | Bounded byte-range scanning, public upstream header parsing, strict transfer/charset decoding, exact raw export and attachment snapshots, deterministic multipart alternatives/CID metadata | Synchronous bounded work; no streaming claim or low-memory-device qualification |
| M04 reader | Account-free full/compact reader, custom RenderBox selection, decoded search/copy, static HTML projection, local bounded CID PNG/JPEG, immutable source/attachment callbacks, policy-approved links, actual MIME example | Browser runtime no-fetch gate remains unqualified; host parity is a separate task |
| M05 store | Drift/SQLite transactional repository, immutable drafts/outbox blobs, memberships/tombstones/cursor CAS, bounded FTS5, pending-operation and vault-cleanup journals, account/profile retirement, cache/editor pins and schema v3 with nullable durable flags | Schema v3 and transport/coordinator/store integration passed at `71edec2d`; browser storage and power-loss durability are unqualified; the database is unencrypted |
| M06 native foundation | Manual IMAP configuration, scoped host-vault lookup, selectable folders, finite UID-window synchronization, exact on-demand message literals, guarded UID flag/move commands and a conditional unsupported browser entry | Local parser, SQLite, Node and real Linux loopback TLS controls passed at `71edec2d`; OAuth hosts, live-account interoperability, large/sparse mailbox pagination, SMTP and the account-aware UI remain open |

M06 is partially implemented, not complete. M04W and M07–M13 still require the
mailbox workspace, composition/SMTP sending, Office attachment editing,
standalone full Office host, CrispCloud migration, additional providers,
Calendar/People and Apple distribution work. M14 evidence continues for each
increment; it does not qualify those later products.

## M05 storage and recovery

The new [store package](../../../packages/quds_mail_store/README.md) uses
Drift 2.35.4 and sqlite3 3.9.1. Native setup requires an explicitly supplied
application container and holds an exclusive owner lease across the database
lifetime. Profiles include their host identity, and removed account IDs remain
retired so stale callbacks cannot recreate deleted accounts.

Message changes, mailbox memberships, tombstones and the next cursor commit
together. The transaction compares the cursor read before provider work and
checks its account lease before commit. Conflicting concurrent pages fail
without overwriting a newer mailbox state. Repository streams publish after a
successful commit. Local pending operations survive resets and tombstones in an
explicit reconciliation state.

Drafts use revision comparison. Outbox entries retain their frozen wire bytes,
envelope and draft revision, with validated state transitions and durable attempt
history. Reopening records interrupted submission candidates; recovery persists
them as `uncertain` and never makes them automatically retryable. Work started by
the current live owner is not mistaken for interrupted work. This implements
storage semantics; it does not submit mail or claim exactly-once delivery.

The FTS5 index covers bounded metadata and decoded plain text. Search has no
provider or network port, and header updates/reindexing read metadata without
loading attachment or original-message BLOBs. Logical quotas include identity,
cursor, journal and reference metadata. Payload reads validate stored lengths
before transferring BLOBs and then verify their integrity hashes. Cache eviction
preserves outgoing and pinned content. Logout retains work and journals host-vault
cleanup; explicit account/profile removal deletes local content and retains the
markers needed to finish cleanup after restart.

The current schema is v3, with transactional upgrades from v1 and v2. Existing
rows receive unknown flags; an omitted provider observation preserves known
flags for the same remote identity, while an observed empty set clears them.
Read, flagged, answered, draft and deleted are durable; IMAP Recent is not.
Header listings, streams and search expose the stored snapshot. Existing v2
FTS data is preserved, and v1 backfill remains explicit and bounded. Unknown
future schemas are rejected without reset. The v3 migration/reopen and flag
transaction tests passed in the integrated qualification described below.

The passing baseline includes native file-backed migration/recovery and five
Linux SIGKILL scenarios at transaction boundaries. These results establish the
tested process-crash behavior, not disk failure, operating-system power loss,
mobile suspension or Apple packaging.

Browser setup has a separate public entry, explicit same-origin SQLite Wasm and
worker assets, and a required Web Locks owner lease. Unsafe concurrent IndexedDB
and in-memory fallback are rejected. The browser entry and worker compile, and
portable policy/error-mapping tests run in Node. **Actual browser persistence,
quota, reload, cross-tab ownership and recovery remain NOT RUN/unqualified.**

The database is **not encrypted**. App-container access and a separate credential
vault do not establish database encryption or secure erasure. The host must
execute and acknowledge credential cleanup and supply platform assets/services.

## M06 native IMAP foundation

The new [transport package](../../../packages/quds_mail_transport/README.md)
provides `createMailImapProvider` through a conditional public entry. Manual
configuration contains an explicit DNS/IP host, port, TLS mode, login identity,
authentication mechanism and account-scoped vault reference. Each operation
loads current host credentials and opens a fresh connection. Password,
XOAUTH2 and OAUTHBEARER protocol paths are present; token acquisition, refresh,
system-browser PKCE and platform vault integration remain host work. Required
STARTTLS and implicit TLS expose no certificate bypass or cleartext fallback.
Real Linux loopback tests now qualify both TLS modes, default-trust rejection,
hostname mismatch rejection and peer-observed closure after stalled-handshake
cancellation or deadlines. Injected test clients trust only the local fixture
certificate; the production trust policy is unchanged. Deterministic partial-write
controls verify ordering and abort behavior, but do not qualify Windows socket
semantics or operating-system backpressure.

Synchronization fetches bounded header projections and flags by numeric UID
window. Scoped cursors include UIDVALIDITY and a fixed sweep ceiling; records,
absent-UID tombstones and the next cursor commit atomically through the existing
coordinator/store. Completed sweeps restart to observe old flag changes and
expunges without claiming IDLE, CONDSTORE or QRESYNC. The default `maxUidScan`
is **10,000**, configurable up to **100,000**. It limits the highest UID, not
message count. A mailbox whose `UIDNEXT - 1` exceeds it returns `unsupported`
before fetching or committing a page, including sparse mailboxes with few
messages and high UIDs. Discovered-UID pagination remains open. Direct retrieval
of a specified high UID is supported and retains the exact full-message literal
before bounded MIME parsing; partial projections fail explicitly.

Flag mutations use UID STORE and verify the resulting observation. Delete
sets `\Deleted` only; it does not expunge mail or issue mailbox-wide CLOSE.
MOVE requires the advertised capability and confirms source absence; destination
identity mapping and synchronization remain separate. Operations have finite
timeouts and account-lease cancellation, with no automatic retry. Ambiguous
mutation outcomes return `conflict` for host reconciliation. The browser entry
returns typed `unsupported` without accessing the vault or codec.

The integrated transport/flags source passed its controlled-parser, SQLite,
Linux loopback TLS and Node qualification at `71edec2d`. Actual disposable-account
interoperability, OAuth redirects/refresh, SMTP, the mailbox UI and browser
persistence remain separate gates.

## Local verification

### Integrated schema v3 and M06 foundation — PASS

The final gates ran on published source
`71edec2de364805113d18e0f1d7edbb1f00467e5`, tree
`8b7443bd15be09276764f62934b9d8ce32a6be68`. Source and runtime inputs remained
unchanged during qualification. All three receipts report success, with
**631 passing Dart/Flutter test executions, zero failures and zero skips**:

| Gate | Passing executions | Cohorts |
| --- | ---: | --- |
| [Core/store](../../validation/mail-m06-resume-20261119/final/mail-final-receipt.json) | 199 | 31 core VM, 31 core Node, 95 store VM, 42 portable store Node |
| [Native integration](../../validation/mail-m06-resume-20261119/final/native-final-verification.json) | 376 | 70 transport, 244 fork, 32 MIME, 30 reader |
| [Additional Node](../../validation/mail-m06-resume-20261119/final/node-final-verification.json) | 56 | 15 transport, 32 MIME, 9 fork |

The 70 native transport executions comprise 12 configuration, 39 protocol,
five actual SQLite/coordinator integration and 14 socket controls. The socket
cohort includes real loopback TLS as well as explicitly separate deterministic
partial-write fixtures. Strict analysis, formatting, offline lock enforcement,
browser entry/worker compilation and whitespace checks passed. Separately,
**66 Python controls passed**: 42 Mail launcher, 20 plan-runner and four runtime
restorer controls.

The [independent evidence audit](../../validation/mail-m06-resume-20261119/final/evidence-audit.json)
reparsed raw test events, checked saved case lists and hashes, and verified the
common source/runtime bindings. It distinguishes **508 distinct suite/test
scenarios across 48 suites** from the 631 runtime executions; 123 scenarios
ran on both VM and Node, with no repeated execution of the same scenario on the
same platform. Earlier baseline and failed-attempt totals are not included.

Two earlier integrated Mail attempts remain failed historical evidence in the
[continuation record](../../validation/mail-m06-resume-20261119/README.md).
Source `da78c0bb` failed on a duplicate-constant set warning and the test-only
Drift/test `isNull` import ambiguity. Source `e734e3bd` failed a Python
process-cleanup control when its process-state read raced with child exit.
Those repairs preceded the new frozen source and complete rerun; neither
failed attempt is relabeled as passing.

### Earlier baseline qualification — PASS on `479e1e03`

The [19 November continuation](../../validation/mail-m06-resume-20261119/README.md)
binds the earlier baseline results to source
`479e1e038af0467b7f07b35d80bac9e4cc60a198`, before the schema v3 and transport
additions. Its [Mail receipt](../../validation/mail-m06-resume-20261119/baseline/mail-receipt.json)
records **186 passing test executions**, with zero failures and zero skips:

| Cohort | Passing cases |
| --- | ---: |
| Core VM | 30 |
| Core Node | 30 |
| Native store VM | 87 |
| Portable store policy/codec Node | 39 |

The **42 Python launcher regressions**, enforced offline lock resolution,
strict analysis, formatting, browser entry/worker compilation and whitespace
checks also passed. VM and Node repetitions are separate executions, not
distinct scenarios. The [72-suite Office/reader run](../../validation/mail-m06-resume-20261119/baseline/office-verification.json)
passed on the same frozen source with **1,230 cases**, zero failures and zero
skips: 233 engine, 887 editor, 99 Studio and 11 Mail-reader cases. Raw evidence,
case lists, archive indexes and source/runtime identity checks are retained in
that dated record. These results predate schema v3 and the native adapter and
remain separate from the final integrated qualification above.

### Historical store attempt — failed before recovery

The combined local attempt exercised source
`8a6105a7ec217b48105d171703c8d0294c7d2dc6`. Its observed test cohorts were:

| Cohort | Observed result |
| --- | --- |
| Core VM | 30 passed |
| Core Node | 30 passed |
| Store VM | 87 passed |
| Portable store Node | 39 passed |

These are separate runtime cohorts, not a count of distinct cases summed across
platforms. The 87 store VM cases include 32 codec, 16 repository, 16 adversarial,
seven native-platform, four configuration, seven migration and five transaction-
crash cases. The 39 Node cases cover 32 codec, four configuration and three
browser-error-policy cases; they do not execute browser persistence.

**The overall run failed.** Store analysis reported two test lint infos
(an unnecessary sqlite3 import and missing braces); the format check found a
mismatch in `native_platform_test.dart`. Disk exhaustion then prevented a new
executor process from starting. The lint repairs and stricter qualification-event
parser, with 18 new parser regressions, were saved remotely in recovery checkpoint
`7848eca0eec8e291cd88ed6e353151508b77784e`, but had not run at that checkpoint.
The native-platform formatting repair and complete qualification rerun were
also open then. The fresh baseline record above validates the subsequent
repairs; it does not rewrite this historical attempt as a PASS.

See the [M05 report](../../validation/mail-store-20261118/README.md) and
[recovered qualification summary](../../validation/mail-store-20261118/checks/receipt.json).
That summary was reconstructed from observed tool results after the filesystem
became inaccessible; **it is not the original raw qualification receipt**.
The original aggregate raw logs and source manifest remain local and were not
uploaded. Additional review/late Office raw evidence was also not recoverable
through the remaining tools. Remote source checkpoints are preserved, but the
final remote tree was not verified against the local working tree after the
filesystem failure.

The [runtime record](../../validation/mail-store-20261118/runtime/README.md)
retains the earlier verified Flutter 3.47.8/Dart 3.13.7 setup, SQLite 3.54.1 Linux
x64 binary, dependency-resolution comparison and platform checks. Incoming
Office work has [separate reconciliation and regression evidence](../../validation/mail-store-20261118/incoming/).
Retain this failed-attempt evidence and its recovery limitations separately from
the later baseline and final integrated source-bound passes.

### Earlier reader checkpoint

Exact commands, raw results, source hashes and environment limits are retained
under [the reader evidence directory](../../validation/mail-reader-20261118/).
The results below belong to that earlier reader checkpoint and are not new
qualification results for the M05 tree.
The fork's own [verification receipt](../../../third_party/enough_mail/verification/receipt.json)
and [dependency inventory](../../../third_party/enough_mail/DEPENDENCIES.json)
are separate from original Quds tests.

- Core: clean fatal-infos analysis; 28 tests on the native VM and the same 28 in
  Node/JavaScript; public-entry JavaScript and native executable compilation.
- Fork: 170 native tests across 14 files, clean native library analysis, public
  portable JavaScript compilation and equal native/Node fixture projections.
- MIME: 32 tests on the native VM and the same 32 in Node cover original octets,
  raw/decode/body/attachment/
  part/header/depth limits, malformed encodings, alternatives, CID metadata,
  cancellation and review regressions. Both runtimes produce identical public
  fixture projections and hashes.
- Reader: 30 native Flutter tests cover actual MIME integration, search,
  graphemes, immutable callbacks, resource denial with a positive control,
  host-approval invalidation, full/preview budgets and enlarged RTL layouts.
  Two additional visual fixtures were captured and inspected. The release web
  target and browser guard compile; neither is an actual browser runtime pass.
- Initial incoming integration: 190 targeted engine/editor/Studio regressions
  and scoped analysis passed on the initial review/thesaurus merge. The later
  captured head passed a separate 344-test cohort: 74 engine, 148 editor,
  71 Studio and 51 spaCy tests. Its `checks/late-*` receipts retain source
  hashes, initial failures, narrow repairs and final passing results. The
  Studio coverage includes an explicit Linux modal/desktop resize with real
  Material scrollbars. Earlier test totals are not presented as a new run on
  the later source.

See the [reader verification receipt](../../validation/mail-reader-20261118/verification.json)
for that source identity and links to each completed cohort. The imported
draft-proofing flow received numeric limit feedback and responsive chrome;
the navigation sheet keeps its state current and uses separate PDF thumbnail
controllers across resize. A stale test label and two proofing lints were
corrected without changing the established comment-label or priority contract.

No GitHub Actions status was queried, awaited or rerun. Source checkpoints use
`[skip ci]` and are written incrementally to the remote implementation branch.

### Browser and memory qualification

JavaScript compilation and execution in Node do not close browser runtime gates.
The reader checkpoint could not start local Chromium, and the cloud browser
could not access its loopback harness;
[the exact limitation is recorded](../../validation/mail-reader-20261118/browser-limitations.md).
A new Chromium launch during M05 also failed before rendering because the
executor denied its process-singleton socket; the
[launch receipt](../../validation/mail-store-20261118/runtime/chromium-smoke.json)
records the failure. Reader rendering/no-fetch and browser-store acceptance both
remain open. Run those tests on a supported browser environment before enabling
host migration or claiming the corresponding browser capability.

A synthetic 16 MiB attachment (22,369,758 input bytes) was parsed by a native
executable in 493,958 microseconds on this Linux x64 host. Whole-process peak RSS,
including fixture construction, was 112,095,232 bytes. This measurement belongs
to the initial codec checkpoint `9ee120bd` and is a desktop baseline, not a
mobile/low-memory claim. Raw data is in `checks/mime-memory.json`.

### Charset and license decisions

The portable parser imports only the reviewed non-CJK enough_convert source
closure. GBK, Big5 and GB18030 aliases were removed from the registry because
the legacy mapping provenance was not established. Those charsets now report
unsupported and retain original source for a host fallback. UTF-8, ASCII,
Latin-1, supported ISO/Windows and KOI8 mappings remain available; malformed and
undefined character mappings are not silently displayed as exact text.

Original Quds files remain MIT. Modified enough_mail files retain MPL. The
selected enough_convert closure is MPL, with its matching notice/source record.
The complete enough_mail runtime dependency inventory is pinned and retained,
including component-specific notices. The store's
[dependency inventory](../../../packages/quds_mail_store/DEPENDENCIES.json) and
[retained notices](../../../packages/quds_mail_store/THIRD_PARTY_NOTICES.md)
record its independently resolved package closure and default SQLite artifacts.
Flutter, other host dependencies and
shipped assets still require the product-level LIC-02 review. This is
source-level evidence, not approval of an
Apple binary or the full existing CrispCloud host. That host's AGPL boundary
and LIC/CC release gates remain as documented in the original scope.

## Reproduce without hosted CI

Use the pinned Flutter 3.47.8 SDK, Node on PATH and the committed root lockfile.
Resolve the SDK's own flutter_tools dependencies normally if this is a fresh
SDK extraction. From the repository root, qualify the store and updated core:

```bash
python3 tools/mail/test_check_store.py
python3 tools/mail/check_store.py --flutter-sdk /path/to/flutter \
  --offline --direct-tests --command-timeout 300 --output /path/to/fresh-store-checks
```

The store runner records source hashes before/after execution, raw test events,
substantive cases, compilation and exact exit results. Its default output is
`build/mail-store-qualification`. It replaces any earlier PASS receipt with the
current run state before starting, and reports actual browser storage as NOT RUN.
The corrected launcher and its 42 regressions passed on the final frozen source;
rerun them when qualifying subsequent changes. Native
transaction-crash cases require an environment that can start and terminate child
processes. Transport/flags qualification has its own combined source-bound
record under [the M06 continuation](../../validation/mail-m06-resume-20261119/README.md).

For the earlier reader qualification workflow:

```bash
python tools/mail/check_reader.py --flutter-sdk /path/to/flutter --web-build
```

On a machine where Chrome can run, include actual browser execution:

```bash
python tools/mail/check_reader.py --flutter-sdk /path/to/flutter \
  --web-build --chrome /path/to/chrome
```

The runner records command exits, raw output, before/after source hashes and
native/JavaScript projection equality. It reports browser execution as NOT RUN
unless requested. Its output defaults to `build/mail-qualification`, outside
the committed evidence; retain a new dated receipt when qualifying a release.

The web preview harness lives under `packages/quds_mail_ui/example`. A host can
embed `MailMessageView` using `MailReaderController.fromBytes` and
`const QudsMimeCodec()` without accounts or network setup. It is a reader
harness, not the standalone Office application.

## Next implementation order

1. Extend M06 with discovered-UID pagination for large/sparse mailboxes,
   archive/destination workflows and individual body-part retrieval. Preserve
   transactional cursor advancement and the current explicit high-UID limit
   until its replacement is implemented and qualified.
2. Implement host OAuth/PKCE, refresh, platform vaults and lifecycle scheduling;
   qualify authorized disposable-account interoperability and the required
   platform socket behavior beyond Linux loopback. Generic browser
   socket transport remains explicitly unsupported; no automatic retry is added
   without its own bounded policy and reconciliation checks.
3. Continue M07 composition/submission and M04W's repository-driven mailbox
   workspace. Preserve immutable queued revisions, explicit SMTP outcomes,
   uncertain-send reconciliation and the all-or-abort recipient policy.
4. Independently close reader/browser no-fetch and browser-store runtime gates,
   including quotas, reloads, tab contention and recovery. Qualify memory and
   rendering on the intended low-memory devices. Keep CrispCloud EML routing
   unchanged until CC parity tests pass in that repository.
5. Continue the Office attachment bridge, standalone full Office host and
   independent CrispCloud integration with the original dependency order and
   per-product release gates.
