# Mail implementation status — 18 November 2026

Development continues on `codex/mail-reader-20261118` in the canonical Quds
repository. Fetch that branch when resuming before it is merged into main.
The source of product scope remains [README.md](README.md) and the ordered work
remains [implementation-plan.md](implementation-plan.md).

## Delivered code

| Area | Current implementation | Acceptance limits |
| --- | --- | --- |
| M00 baseline | The reader foundation reconciled its captured Office heads; the M05 continuation captures and reconciles incoming main, branch and PR history separately before implementation | Capture-specific dispositions and subsequent changes belong to the dated reconciliation receipts; historical test reports are not new results |
| M01 fork | Pinned enough_mail 3.0.0 source, retained MPL/provenance, supported public `mime_core.dart`, content-redacted diagnostics, strict charset admission, RFC2231 and date corrections, selected dependency/source inventory | Actual browser execution and per-product shipped dependency/notice clearance remain open |
| M02 core | Pure-Dart immutable DTOs, exact-byte ownership, profile/account/IMAP identity, budgets/capabilities, typed host/provider/store ports, cancellation leases, cursor compare-and-set and tested outbox state machine | The store implements the persistence port in M05; live providers and SMTP remain subsequent work |
| M03 codec | Bounded byte-range scanning, public upstream header parsing, strict transfer/charset decoding, exact raw export and attachment snapshots, deterministic multipart alternatives/CID metadata | Synchronous bounded work; no streaming claim or low-memory-device qualification |
| M04 reader | Account-free full/compact reader, custom RenderBox selection, decoded search/copy, static HTML projection, local bounded CID PNG/JPEG, immutable source/attachment callbacks, policy-approved links, actual MIME example | Browser runtime no-fetch gate remains unqualified; host parity is a separate task |
| M05 store | Drift/SQLite transactional repository, immutable drafts/outbox blobs, memberships/tombstones/cursor CAS, bounded FTS5, pending-operation and vault-cleanup journals, account/profile retirement, cache/editor pins and schema migrations | Native behavior and Linux process-crash recovery are exercised; final qualification is BLOCKED; browser storage and power-loss durability are unqualified; the database is unencrypted |

The remaining M04W/M06–M13 features have **not** been implemented by this
checkpoint: mailbox workspace, native IMAP/SMTP accounts, composition/sending,
Office attachment editing, standalone full Office host, CrispCloud migration,
additional providers, Calendar/People and Apple distribution. M14 evidence
continues for the reader and store increments; it does not qualify the later
products.

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

Schema v1-to-v2 upgrade is transactional and preserves existing data; FTS backfill
is explicit and bounded. Unknown future schemas are rejected without reset.
Native file-backed tests verify migration rollback/retry and stricter read limits.
Five Linux SIGKILL scenarios exercise actual process termination at transaction
boundaries. These results establish the tested process-crash behavior, not disk
failure, operating-system power loss, mobile suspension or Apple packaging.

Browser setup has a separate public entry, explicit same-origin SQLite Wasm and
worker assets, and a required Web Locks owner lease. Unsafe concurrent IndexedDB
and in-memory fallback are rejected. The browser entry and worker compile, and
portable policy/error-mapping tests run in Node. **Actual browser persistence,
quota, reload, cross-tab ownership and recovery remain NOT RUN/unqualified.**

The database is **not encrypted**. App-container access and a separate credential
vault do not establish database encryption or secure erasure. The host must
execute and acknowledge credential cleanup and supply platform assets/services.

## Local verification

### Current store increment — final qualification BLOCKED

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
`7848eca0eec8e291cd88ed6e353151508b77784e`, but remain **NOT RUN**.
The native-platform formatting repair and a complete qualification rerun remain
open. Passing test events do not turn the overall result into a PASS or qualify
those later edits.

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
Retain the raw evidence and run the corrected qualification flow on the final
source before replacing this BLOCKED state with a source-bound pass.

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
python tools/mail/check_store.py --flutter-sdk /path/to/flutter
```

The store runner records source hashes before/after execution, raw test events,
substantive cases, compilation and exact exit results. Its default output is
`build/mail-store-qualification`. It replaces any earlier PASS receipt with the
current run state before starting, and reports actual browser storage as NOT RUN.
The stricter event parser and its 18 new regression tests saved during recovery
still require execution. Run those tests and resolve the remaining format gate
before using a fresh full run as acceptance evidence. Its native transaction-
crash cases require an environment that can start and terminate child processes.

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

1. Recover local raw evidence after freeing space, apply the pending test format,
   run the 18 qualification-parser regressions and rerun the complete corrected
   store qualifier into a fresh output directory. Finish the interrupted incoming
   Office checks, refresh remote heads and verify the final tree before claiming
   final M05 qualification.
2. Implement M06 native accounts and bounded IMAP synchronization against the
   durable repository: explicit host-owned credentials, validated TLS setup,
   UIDVALIDITY/cursor recovery, cancellation and foreground/resume behavior.
   Generic browser socket transport remains explicitly unsupported.
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
