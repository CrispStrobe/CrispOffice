# UID, Hunspell and Arabic integration qualification

The exact integrated source **`29dd23a6edd0a0fbb916b3d9f73861a8aa4f435e`**,
tree `c0a6041f33c485c83c2cb926d0b97464a3761e1c`, passed **784 executions /
600 distinct scenarios / 37 distinct suites**. This is a completed checkpoint.
It combines our earlier saved evidence with captured main
`b655b8a37fddc874bd42a453c371eed6253e82d8`. Later main changes are recorded
separately in the [integration report](../README.md).

## Actual results

| Gate | Distinct suites | Passed executions | Distinct scenarios contributed |
| --- | ---: | ---: | ---: |
| Complete fresh core/store, VM and Node | 14 | 250 | 162 |
| Native Mail transport and discovered-UID pages | 4 | 110 | 110 |
| Actual TLS and transport ownership | 3 | 26 | 26 |
| Node unsupported transport boundary | 1 | 3 | 3 |
| Strict UID SEARCH parser and wire behavior | 2 | 68 | 68 |
| IMAP dispatch, FETCH/SEARCH and connection lifecycle | 5 | 109 | 109 |
| Mail UI consumers | 4 | 30 | 30 |
| Hunspell provider contracts, VM | 1 | 10 | 10 |
| Instrumented real native Hunspell lifecycle | 1 | 6 | 6 |
| Arabic writing rules, VM | 1 | 74 | 74 |
| Arabic editor integration | 1 | 2 | 2 |
| Mail configuration, Hunspell and Arabic repeated on Node | 3 repeated | 96 | 0 |
| **Combined** | **37 distinct** | **784** | **600** |

There are 47 suite/platform executions. The 184 repetitions comprise 88 within
core/store and 96 in the separate Node plan. The main plan contributes 438
cases. Historical qualifications, development reproductions and publisher
controls are not added to these application counts.

Strict analysis with fatal infos/warnings and formatting passed for all
**34 selected Dart paths**. The complete core/store gate also passed **42
runner controls**, enforced offline dependency resolution and both browser
entry/worker compilations. All **17 separate publisher controls** passed after
reconciling stale adapter-status wording. No live dictionary publication was
performed; the existing immutable AyaSpell revision and catalog hashes remain
unchanged. The new card text affects future generated bundles only.

## Reconciliation and repairs

Incoming main added strict discovered-UID pagination, typed atomic range
reconciliation, the optional Hunspell package and a macOS runner scaffold.
Sparse numeric UID gaps no longer consume page slots. Removal is authorized
only by a complete valid discovery result in the same mailbox, UIDVALIDITY and
closed range, under the existing account lease and cursor comparison. Pending
local edits and retained cache evidence survive reconciliation.

The Hunspell review reproduced a native dictionary-handle leak: the original
transport killed its isolate without closing the dictionary. The repair adds
serialized close/acknowledgement, immediate caller settlement, bounded disposal,
idempotent shutdown and a native ownership finalizer. Forced termination lets
the current native event return so ownership can be attached. Six identical
regressions produced one pass/five failures before the fix and six passes after
it against the counter/delay-instrumented real Hunspell adapter. They cover
normal/repeated disposal, reopening, startup, stalled checks, stalled opening
and provider timeout. The final integrated run repeats all six successfully.

The native build uses the verified committed Hunspell sources and GCC 14.2 on
Linux. Lifecycle cases use a one-word synthetic dictionary; the separate ABI
probe used a small synthetic dictionary. Neither establishes AyaSpell accuracy,
installer/download behavior or linguistic acceptance. Native library and build
receipt hashes are bound in [native-runtime-inputs.json](native-runtime-inputs.json)
and the runtime receipt before and after both focused gates. The declared
launch environment is recorded separately; the runner does not independently
serialize its child process environment.

The Notes fixes and Arabic semantic-mark repair are preserved. Flutter's
workspace resolution adds only `build/**` to Mail UI's analyzer exclusions;
checked library and test paths remain included. Original third-party license
notice bytes, including their upstream whitespace, are retained exactly.
Whitespace checks for local edits pass relative to captured main `b655b8a3`.

## Independent audit and retained evidence

The [raw-event audit](latest_final_review.json) reconstructed all case identities,
exact suite coverage, full starts/completions and successful terminal events.
It found zero failures, skips, reporter errors, unfinished cases, duplicate
identities, layout overflows or missed-tap diagnostics. The known Drift debug
warning episode remains visible as two print messages in the separate-host
container test; strict analysis has no diagnostics.

Both focused source inventories contain **5,103 identical records**, all matched
to frozen Git modes/blobs and live bytes. The fresh store gate binds 55 source
inputs and seven direct launcher/native records. Main runtime boundaries contain
**11,168 records** and Node boundaries **11,164 records**; each is unchanged.
Readback verifies all **11,142 retained runtime files** and provenance records
for 176 verified hosted archives. The store runner has its own narrower direct
input boundary; full-runtime readback does not retroactively widen it.

- [Main verification](verification.json), [Node verification](node-verification.json),
  [store receipt](store-receipt.json), [case inventory](latest_final_review-cases.json).
- [Independent audit script](audit_latest_qualification.py) and
  [supplemental controls](supplemental-controls.json).
- [Qualification archive](qualification-evidence.tar.xz): 926,092 bytes, 100 members,
  SHA-256 `93dd04ec51be469d0ad75514eaf49c23d9e71a93aff680c7ed6ca331288b11a7`.
  The [index](qualification-evidence.index.json) records every member hash and six
  reproducible generated JavaScript outputs preserved as hashes.
- [Native repair archive](hunspell-disposal-evidence.tar.xz): 245,588 bytes,
  117 members, SHA-256
  `395e07b1e33dbdb11158b0986e931c23f904486a6adf02ecc76509bbcb3d5fb8`.
  Its [index](hunspell-disposal-evidence.index.json) preserves exact RED/GREEN
  sources, raw logs, native build/instrumentation inputs and offline replay.

## Replay

Restore the pinned runtime following the retained
[runtime instructions](../../document-review-notes-20261118/runtime/README.md).
Use a detached checkout of the exact source above and separate empty output
directories. Rebuild the instrumented native library from the repair archive,
place it at the path declared in the native binding, and include both it and
its build receipt in `runtime.json` additional inputs with verified hashes.

```bash
source /absolute/path/to/runtime/env.sh
python3 -B tools/mail/check_store.py \
  --flutter-sdk /absolute/path/to/runtime/flutter --offline --direct-tests \
  --output /absolute/path/to/new-store-output --command-timeout 600
QUDS_HUNSPELL_LIFECYCLE_LIBRARY=/absolute/path/to/instrumented-library.so \
python3 -B docs/validation/document-review-notes-20261118/run_checks.py \
  --head 29dd23a6edd0a0fbb916b3d9f73861a8aa4f435e \
  --base b655b8a37fddc874bd42a453c371eed6253e82d8 \
  --plan docs/validation/office-main-integration-20261119/latest-final/plan.json \
  --runtime /absolute/path/to/runtime --output /absolute/path/to/new-main-output \
  --command-timeout 600
python3 -B docs/validation/document-review-notes-20261118/run_checks.py \
  --head 29dd23a6edd0a0fbb916b3d9f73861a8aa4f435e \
  --base b655b8a37fddc874bd42a453c371eed6253e82d8 \
  --plan docs/validation/office-main-integration-20261119/latest-final/node-plan.json \
  --runtime /absolute/path/to/runtime --output /absolute/path/to/new-node-output \
  --command-timeout 600
```

The recorded invocations used the exact bound paths in the receipts. A replay
at different paths requires fresh truthful runtime receipts and bindings;
original evidence must not be overwritten. Complete locked resolution before
starting the focused runners, and avoid simultaneous Git preflight operations.

## Scope boundaries

This checkpoint does not execute an installed macOS/Studio app, real OS/IME,
a live Zotero session, external Word/LibreOffice or actual browser lifecycle,
CSP, storage/offline/performance acceptance. macOS scaffold review is static.
The six real-AyaSpell/installer cases and live-download case were not selected
here; no actual dictionary was available. Incoming macOS/Wasm/mobile/corpus
claims retain their original source attribution and were not independently
repeated by this Linux run. Independent English/German linguistic judgments
remain incomplete. The earlier 2,018-case, native 208-case and release-web
fixtures retain their original `39843ed4` source and are not current execution
or build results. No GitHub Actions were queried, dispatched or awaited.
