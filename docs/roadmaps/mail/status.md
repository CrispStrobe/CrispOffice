# Mail implementation status — 19 November 2026

The current integrated source and qualification are recorded in the
[19 November completion report](../../validation/office-main-completion-20261119/README.md).
Fetch the canonical repository's current refs before resuming.
The source of product scope remains [README.md](README.md) and the ordered work
remains [implementation-plan.md](implementation-plan.md).

## Delivered code

| Area | Current implementation | Acceptance limits |
| --- | --- | --- |
| M00 baseline | The reader foundation reconciled its captured Office heads; the M05 continuation captures and reconciles incoming main, branch and PR history separately before implementation | Capture-specific dispositions and subsequent changes belong to the dated reconciliation receipts; historical test reports are not new results |
| M01 fork | Pinned enough_mail 3.0.0 source, retained MPL/provenance, supported public `mime_core.dart`, content-redacted diagnostics, strict charset admission, RFC2231 and date corrections, selected dependency/source inventory | Actual browser execution and per-product shipped dependency/notice clearance remain open |
| M02 core | Pure-Dart immutable DTOs, exact-byte ownership, profile/account/IMAP identity, nullable standard flag snapshots, budgets/capabilities, typed host/provider/store ports, cancellation leases, cursor compare-and-set and tested outbox state machine | M05 implements persistence; the initial M06 IMAP adapter passed combined local qualification; SMTP remains subsequent work |
| M03 codec | Bounded byte-range scanning, public upstream header parsing, strict transfer/charset decoding, exact raw export and attachment snapshots, deterministic multipart alternatives/CID metadata | Synchronous bounded work; no streaming claim or low-memory-device qualification |
| M04 reader | Account-free full/compact reader, custom RenderBox selection, decoded search/copy, static HTML projection, local bounded CID PNG/JPEG, immutable source/attachment callbacks, policy-approved links, actual MIME example | Browser runtime no-fetch gate remains unqualified; host parity is a separate task |
| M05 store | Drift/SQLite transactional repository, immutable drafts/outbox blobs, memberships/tombstones/cursor CAS, bounded FTS5, pending-operation and vault-cleanup journals, account/profile retirement, cache/editor pins and schema v3 with nullable durable flags | Schema v3 and the integrated flags/transport source passed local qualification; browser storage and power-loss durability are unqualified; the database is unencrypted |
| M06 native foundation | Manual IMAP configuration, scoped host-vault lookup, selectable folders, finite UID-window synchronization, exact on-demand message literals, guarded UID flag/move commands and a conditional unsupported browser entry | Integrated qualification and real Linux TLS loopback checks passed; external-provider/other-OS interoperability, OAuth authorization hosts, large or sparse mailbox pagination, SMTP and the account-aware UI remain open |

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
future schemas are rejected without reset. The added v3 migration/reopen and
flag transaction tests passed in the qualification recorded below.

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
Separate real Linux loopback tests exercise successful TLS, stalled-handshake
cancellation/deadlines, trust and hostname refusal, credential sequencing and
write lifecycle. These do not establish external-provider or other-OS acceptance.

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

The integrated transport/flags source passed local controlled-parser,
SQLite/coordinator and Node qualification. Coverage includes unsolicited flag
notifications, EXPUNGE ambiguity, exact literal bytes, strict FETCH structure and
decimal UID validation. The default owned transport also passed real TLS and
abort-lifecycle tests. Actual disposable-account interoperability, OAuth
redirects/refresh, other operating systems, SMTP, the mailbox UI and actual browser
persistence remain separate gates.

## Local verification

### Final reconciled source — PASS

The [completion report](../../validation/office-main-completion-20261119/README.md)
binds all final execution to `5569c055a021c893e941fc54d40499ad9d96a5db`:
**836 application executions across 85 suite/platform executions and 73 distinct
files**, plus **78 separate Python controls**. The native gate passed 602 cases,
the Node gate 35, and a fresh full core/store gate 199. All 35 changed Dart files
passed strict analysis and formatting. Browser entry/worker compilation passed;
actual browser persistence remains outside this gate.

The separate audit recounts the raw events, verifies exact source/runtime
bindings and accounts for all 392 refs at the recorded cutoff. No historical or
development cases contribute to these totals. Real TLS checks use Linux
loopback; external mail services, installed Office/OS integrations and other
platforms retain their separate acceptance requirements.

### Earlier integrated flags and native IMAP qualification — PASS

The [Office integration report](../../validation/office-main-integration-20261119/README.md)
binds the final **32-suite / 389-case** focused pass to source
`7d279e084bae438d383630726ad7b0514da77d35`. It covers 80 native transport cases,
three Node unsupported-entry cases, 244 shared IMAP/POP/SMTP and byte-reader
regressions, 32 MIME cases and 30 Mail-reader cases. Strict analysis, formatting
and whitespace checks also passed, with the source and runtime inputs unchanged.

The retained core/store gate records **199 passing executions / 129 distinct
scenarios**, with source continuity checked for the integrated tree. Its VM/Node
repetitions are separate executions. The report retains raw events, receipts,
source/runtime identities, failed reproductions and independent audit records;
it does not add earlier Office, Notes or thesaurus results to this qualification.
Controlled streams, Node and Flutter tests do not close actual browser, live TLS,
installed Studio/OS IME, live Zotero or human linguistic acceptance.

### Earlier baseline qualification — PASS

The [19 November continuation](../../validation/mail-m06-resume-20261119/README.md)
binds the fresh results to source
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
that dated record. No historical totals are included in these fresh results.

The old runner/formatting blockage was resolved for that baseline. Its results
predate schema v3 and the M06 adapter; the integrated qualification above supplies
the subsequent source-bound evidence.

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
the newer source-bound baseline and integrated M06 passes.

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
The corrected launcher and its 42 regressions passed in the fresh baseline;
run them again with the final source when recording a new gate. Native
transaction-crash cases require an environment that can start and terminate child
processes. Transport/flags qualification has its own combined source-bound
record under [the Office integration report](../../validation/office-main-integration-20261119/README.md).

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

1. Preserve the completed integrated qualification and its source/runtime
   identities. Rerun affected checks for subsequent source changes and retain
   their raw logs and remote checkpoints separately from earlier evidence.
2. Continue the remaining M06 work: discovered-UID pagination for large/sparse
   mailboxes, host OAuth/refresh and lifecycle scheduling, other-OS TLS coverage
   and authorized disposable-account interoperability. Generic browser
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
