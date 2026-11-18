# Mail implementation status — 18 November 2026

Development continues on `codex/mail-reader-20261118` in the canonical Quds
repository. Fetch that branch when resuming before it is merged into main.
The source of product scope remains [README.md](README.md) and the ordered work
remains [implementation-plan.md](implementation-plan.md).

## Delivered code

| Area | Current implementation | Acceptance limits |
| --- | --- | --- |
| M00 baseline | Reconciled current main, recent document review/Zotero work, and completed offline thesaurus work; 207 branches and 169 PR heads accounted for | Historical test reports were not treated as new results |
| M01 fork | Pinned enough_mail 3.0.0 source, retained MPL/provenance, supported public `mime_core.dart`, content-redacted diagnostics, strict charset admission, RFC2231 and date corrections, selected dependency/source inventory | Actual browser execution and per-product shipped dependency/notice clearance remain open |
| M02 core | Pure-Dart immutable DTOs, exact-byte ownership, profile/account/IMAP identity, budgets/capabilities, typed host/provider/store ports, cancellation leases, atomic sync-page contract and tested outbox state machine | Ports do not constitute a database, SMTP implementation or live account support |
| M03 codec | Bounded byte-range scanning, public upstream header parsing, strict transfer/charset decoding, exact raw export and attachment snapshots, deterministic multipart alternatives/CID metadata | Synchronous bounded work; no streaming claim or low-memory-device qualification |
| M04 reader | Account-free full/compact reader, custom RenderBox selection, decoded search/copy, static HTML projection, local bounded CID PNG/JPEG, immutable source/attachment callbacks, policy-approved links, actual MIME example | Browser runtime no-fetch gate remains unqualified; host parity is a separate task |

The remaining M04W/M05–M13 features have **not** been implemented by this
checkpoint: mailbox workspace, durable SQLite store/search, native IMAP/SMTP
accounts, composition/sending, Office attachment editing, standalone full Office
host, CrispCloud migration, additional providers, Calendar/People and Apple
distribution. M14 evidence has started for this reader increment; it does not
qualify the later products.

## Local verification

Exact commands, raw results, source hashes and environment limits are retained
under [the reader evidence directory](../../validation/mail-reader-20261118/).
The fork's own [verification receipt](../../../third_party/enough_mail/verification/receipt.json)
and [dependency inventory](../../../third_party/enough_mail/DEPENDENCIES.json)
are separate from original Quds tests.

- Core: clean fatal-infos analysis; 28 tests on the native VM and the same 28 in
  Node/JavaScript; public-entry JavaScript and native executable compilation.
- MIME: native and Node tests cover original octets, raw/decode/body/attachment/
  part/header/depth limits, malformed encodings, alternatives, CID metadata,
  cancellation and review regressions. Both runtimes produce identical public
  fixture projections and hashes. See the final test log for the exact count.
- Reader: 30 native Flutter tests cover actual MIME integration, search,
  graphemes, immutable callbacks, resource denial with a positive control,
  host-approval invalidation, full/preview budgets and enlarged RTL layouts.
- Incoming integration: targeted engine/editor/Studio regressions and scoped
  analysis cover the actual review/thesaurus merge overlaps. See the integration
  receipt; unrelated historical totals are not carried forward.

No GitHub Actions status was queried, awaited or rerun. Source checkpoints use
`[skip ci]` and are written incrementally to the remote implementation branch.

### Browser and memory qualification

JavaScript compilation and execution in Node pass. The executor blocks local
Chromium startup, and the cloud browser cannot access its loopback harness;
[the exact limitation is recorded](../../validation/mail-reader-20261118/browser-limitations.md).
This does not close actual browser rendering/no-fetch acceptance. Run the
browser tests on an environment that permits Chromium before enabling host
migration or claiming R0 across every target.

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
including component-specific notices. Flutter, other host dependencies and
shipped assets still require the product-level LIC-02 review. This is
source-level evidence, not approval of an
Apple binary or the full existing CrispCloud host. That host's AGPL boundary
and LIC/CC release gates remain as documented in the original scope.

## Reproduce without hosted CI

Use the pinned Flutter 3.47.8 SDK, Node on PATH and the committed root lockfile.
Resolve the SDK's own flutter_tools dependencies normally if this is a fresh
SDK extraction. Then, from the repository root:

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

1. Close the actual browser no-fetch/runtime gate and qualify memory/rendering
   on the intended low-memory device. Keep existing CrispCloud EML routing
   unchanged until CC parity tests pass in that repository.
2. Implement M05's durable store and recovery journal against the tested core
   contracts. Prove atomic message-page/cursor commits and durable drafts/outbox
   before connecting a network provider.
3. Implement M06/M07 and M04W together: native accounts, bounded IMAP sync,
   canonical composition, explicit SMTP outcomes and repository-driven mailbox
   workspace. Retain uncertain-send reconciliation and all-or-abort recipients.
4. Continue the Office attachment bridge, standalone full Office host, and
   independent CrispCloud integration with the original dependency order and
   per-product release gates.
