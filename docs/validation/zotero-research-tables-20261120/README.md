# Zotero research tables — 2026-11-20

## Delivered scope

This increment preserves bounded rectangular Zotero research-note and annotation tables as native Word blocks. Add Note and Add Annotation retain active citation fields, rich cell text, lists, pictures, supported widths and cell fills. Citations keep source order: rows, then cells within each row, then paragraphs within each cell. They participate in refresh and bibliography generation, including citations owned by an authored footnote or endnote.

Insertion accepts a main-flow caret or a selection within one paragraph of the body or an authored note. Surrounding prose remains outside the new table. A leading table in an authored note leaves its automatic marker and separator before the table; a trailing table receives a main-flow paragraph for the resulting caret. The Notes pane preserves the cells while exposing the surrounding prose for text editing. The complete result remains detached until completion and applies as one undoable transaction, with the existing cancellation, composition, selection and stale-document guards.

The parser uses one context and canonical marker stream for the entire note. Its ordered blocks and flattened paragraph view refer to the same paragraph objects, so field conversion and insertion operate on the cell content that is actually published. Paragraph, link, image and payload limits are shared across all cells.

| Table property | Supported envelope |
| --- | --- |
| Structure | `table`, optional `tbody`, `tr`, `td` and `th`; rectangular, unmerged cells |
| Cell content | Empty or rich paragraphs, soft breaks, headings, supported inline formatting and links, independent lists, supported images and active citations |
| Header text | Bold by default; explicit inline emphasis changes are retained |
| Size | Up to 64 tables per note, 256 rows per table, 32 columns and 4,096 cells across the note |
| Column widths | Supplied integral `data-colwidth` values from 1 to 4,000 CSS pixels, consistent across rows; 96 pixels map to 72 points; unspecified columns default to 120 points; total native width at most 4,000 points |
| Cell backgrounds | Three- or six-digit hexadecimal colors, integer RGB colors and transparent |
| Shared limits | Existing 8 MiB payload, 10,000 paragraphs, 10,000 links and bounded image budgets for the complete note |

Nested or merged tables, ragged rows, tables inside list items, separate header/footer row groups, captions, custom structural classes and unsupported table/row/cell styles are refused. A table payload cannot be applied inside an existing table cell. Malformed content, unsupported images or missing, repeated or unconverted citation placeholders refuse the entire result.

See the [usage guide](../../zotero-support.md#tables-in-notes-and-annotations) for the complete content contract and the [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) for the next increments. Native model and DOCX checks below qualify implementation behavior; live application acceptance remains separate.

## Incoming work and remote preservation

The initial intake captured 18 fork heads, the 100 most recently updated pull request records and four upstream heads. [incoming-intake.json](incoming-intake.json) retains that snapshot and historical-equivalence references. The five divergent initial heads were reconciled with their ancestry:

| Incoming lane | Captured head |
| --- | --- |
| Downloads | `84d02025` |
| Mail accounts | `a059c024` |
| Selected credential stores | `95bf6340` |
| Parallel Downloads work | `4f5c1537` |
| Incremental Word layout | `d661e024` |

Later main `7e740a53` and performance head `e6f70bff` were incorporated at `ab8d42ec`, preserving the Mail reply/forward and VBA ancestry already present in that main. The later documentation-only performance head `9b581e8a` was also incorporated. Its local chrome A/B figures remain their author's measurements, not this branch's benchmark results.

The reconciliation and source-tree evidence are in [incoming-followup-review.json](incoming-followup-review.json), [incoming-final-review.json](incoming-final-review.json) and [integration-integrity.json](integration-integrity.json). Those records identify their own immutable checkpoints; later formatting and execution evidence do not retroactively change them.

The [late-head assessment](late-head-assessment.json) reviewed seven subsequently captured heads against `630951d2`. After incorporating the documentation-only performance head, these six were recorded as pending incoming work at that boundary:

| Later lane | Captured head |
| --- | --- |
| VBA continuation | `89910ff6` |
| Downloads/font-license follow-up | `e6737bc6` |
| Mail accounts continuation | `cb7f8325` |
| Mail provider host tests | `feffbfa4` |
| Mail reply/forward continuation | `4df7a148` |
| Mail validation/source continuation | `d6de5ef4` |

These histories overlap; six heads do not mean six independent feature sets. The bounded assessment did not establish whole-head equivalence or acceptance. A later pre-merge check found that remote main had advanced to `b42eca1db058f0def247b86c2f15dea90c11b4e8`. That main includes the captured VBA, Downloads, Mail host, reply/forward and validation heads above. They were subsequently incorporated through main's preserved ancestry. The captured Mail accounts continuation `cb7f8325` remains outside that ancestry and is still pending incoming work. It contains an additional generation-aware credential-instance cache rule, a system-storage factory seam, a credential-settings opener seam and backend-switch tests. Related revision fences in this branch do not establish whole-head equivalence, so no ancestry-only merge is used to claim incorporation.

The final main reconciliation uses Git's recursive merge handling for both common ancestors, `9b581e8a` and `03de5b6a`. It preserves the final Zotero table behavior, credential revision fences, layout-cache ownership checks and idle chrome scheduling fix. It also retains main's later VBA, paragraph serialization, slide-margin rendering, Mail forwarding and license-loader changes. The final integration record and affected replays below qualify that combined source.

The preserved remote branch is `codex/zotero-research-tables-20261120`; review is [PR #249](https://github.com/CrispStrobe/quds_office_suite/pull/249). Successive remote checkpoints retain intake, implementation, corrections, formatting, later reconciliation and validation receipts. The raw evidence identifies each tested source separately; the final combined source and its later documentation-only continuation are recorded below. No GitHub Actions runs, check statuses or workflow queues were queried or awaited.

## Integration corrections

Review and execution also resolved concrete issues in the incoming work:

- Credential operations retain the canonical bounded account catalog and all-backend write/readback verification. Queued save and Forget operations are fenced by the selected-store revision, and a started transaction uses one captured backend. Open Mail dialogs clear and reload when the selected store changes.
- Incremental layout retains the incoming line/frame prefix-count propagation fix. Dirty, empty and wrapping-frame paths invalidate paragraph break caches so removing a wrapping frame cannot resurrect older text. Layout state is tied to the engine that produced it; foreign font/measurement state restarts from the first section.
- The trailing Word chrome timer requests a frame when it expires while the editor is idle. Merely queuing a post-frame callback did not guarantee that the 400 ms refresh would run.

The independent source reviews are linked above and in [independent-source-review.json](independent-source-review.json). Source inspection is not counted as execution. The engine and chrome controls below exercise the relevant original defects.

## Accepted gates before final main reconciliation

The accepted runs use the genuine Dart 3.13.7 and Flutter 3.47.8 distributions, with SDK/dependency receipts, locked package sources, ordinary Flutter assets and native hooks. The aggregation entrypoints register the original suites and preserve their assertions and hooks. They reduce repeated compilation; the original test files remain individually runnable.

| Gate | Accepted result | Source and qualification |
| --- | --- | --- |
| Engine regression cohort | 399 passed; zero failures, errors or skips; JSON completion and exit 0 | `e618dbe2d01a71e68a757aec8688b1c7a5540bdf`; source compiler; 1,494 tracked source hashes unchanged during execution. The complete engine package remained unchanged through `2d617a31`; the later main reconciliation adds independently qualified changes and is replayed separately below. |
| Flutter editor/controller cohort | 313 passed; zero failures, errors or skips; JSON completion and exit 0 | Executed editor, workspace and original test inputs match `995ca494b687f844931b2f1fd92b4ca1ba7344d3`; 1,634 tracked source hashes unchanged during execution; normal Flutter CLI. |
| Incoming layout equivalence within the editor cohort | 23 cases using the 15 DOCX fixtures available to the run | The exact discovered fixture manifest is retained. This does not claim the complete optional corpus. |
| Engine negative controls | Three expected failures on original layout sources; three passes after restoration | Wrapped-cache transitions and foreign-engine reuse; exact restored source hashes retained. |
| Idle chrome negative control | Original workspace fails the 400 ms scheduled-frame observation; corrected workspace passes | Unrelated home-subtree tickers are muted, while modal routes retain normal animation. A narrow corrected replay also passes the six image guards, for seven cases total. |

The editor run was not an exact clean checkout of the named commit: the unimported host fixture `packages/quds_office_editor/example/test/studio_credential_selection_test.dart` was in genuine formatter-only state at blob `60c3357085dbbe9ec76b88e362f866b8a3ef657d`. It is not imported by the editor aggregate. Its formatting/import-order continuation was subsequently published at `0e84c635`. [checkpoint-editor-evidence.json](checkpoint-editor-evidence.json) records this qualification explicitly.

The accepted engine cohort includes the table parser and native-table insertion/round-trip regressions, prior research targets, lists, images, citation/bibliography and preference handling, and incoming layout regressions. The editor cohort covers table/native-dialog behavior, research targets, image guards, citations, bibliography, proofing, chrome scheduling and incremental-layout equivalence. Controlled Zotero protocol fixtures and engine DOCX serialization/reopening are included; installed Zotero or office applications were not exercised.

### Committed raw evidence

The raw bundles are committed to the branch rather than depending on the runtime workspace:

| Bundle | Bytes | Members | Receipt |
| --- | ---: | ---: | --- |
| [checkpoint-engine-evidence.tar.xz](checkpoint-engine-evidence.tar.xz) | 396,632 | 72 | [Engine metadata and SHA-256](checkpoint-engine-evidence.json) |
| [checkpoint-editor-evidence.tar.xz](checkpoint-editor-evidence.tar.xz) | 249,468 | 49 | [Editor metadata and SHA-256](checkpoint-editor-evidence.json) |
| [checkpoint-native-evidence.tar.xz](checkpoint-native-evidence.tar.xz) | 429,452 | 95 | [Native metadata and SHA-256](checkpoint-native-evidence.json) |

The engine bundle contains `accepted-e618-source/engine.jsonl`, `engine.stderr`, `engine-receipt.json` and `source-before.json`; `engine-controls-e618/` contains the red/green JSON streams and receipts. The editor bundle contains `accepted-995c-flutter/flutter.jsonl`, `flutter.stderr`, `receipt.json`, `source-before.json`, `source-qualification.json`, `group-counts.json` and `memory-monitor.json`. Its `chrome-controls-4044/` directory holds the isolated scheduler control. `available-equivalence-fixtures.json` records the 15 available fixtures. The accompanying scripts retain the executed commands and environment preparation.

The native baseline at `2d617a31bce48a7312f31586f70f7472e3420406` completed **372 visible cases across 16 original files**. All seven standard Flutter CLI groups exited zero with exactly one successful terminal JSON event; all 2,214 captured source hashes stayed unchanged. The [per-file summary](checkpoint-native-run-summary.json) separates the 124 credential selection/catalog/store cases, 73 native Mail cases, 99 EWS/reply cases, 43 Downloads/theme cases and 33 reader cases. Loading and setup entries, negative controls and synthetic replay-helper controls are excluded from product totals. The raw bundle also contains a fresh expected-failure/pass replay of the guarded-callback fixture correction and the recovered genuine SDK/dependency receipts.

### Replay

Use the recorded genuine SDK and dependency versions and the package configurations from the evidence. From `packages/quds_office_engine`, the accepted command was:

```sh
dart --packages="$RUNTIME/engine_package_config.json" \
  "$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart" \
  --reporter=json --concurrency=1 --compiler=source \
  tool/zotero/research_target_acceptance.dart
```

Here `RUNTIME` identifies the recovered runtime artifacts and `PUB_CACHE` the authenticated package cache recorded by `run-engine-e618-source.py`; neither is a substitute implementation. On a normal resolved workspace, use its genuine package configuration and the same source-compiler test runner.

From `packages/quds_office_editor`, the accepted normal Flutter command was:

```sh
flutter test --no-pub --reporter=json --concurrency=1 \
  tool/zotero/research_target_acceptance.dart
```

The editor run used no custom frontend launcher or precompiled-runner adapter. `run-flutter-995c.py` retains its exact environment and source qualification.

For the current complete incoming host replay, run from `packages/quds_office_editor/example` after normal locked dependency resolution:

```sh
dart tool/incoming_reconciliation_acceptance.dart
```

Set `FLUTTER_BIN` when Flutter is not on `PATH`. The helper executes eight sequential groups with 18 original files, including the later cloud-provider and forwarding tests. Each original file retains normal Flutter tester isolation. A group must exit zero and emit exactly one terminal JSON event with `success: true`; incomplete output is not accepted. The earlier 372-case receipt remains attributed to its original seven-group source and is not relabelled as this later replay.

The engine control script `run-engine-controls.py` targets `test/word_incremental_layout_test.dart` with `--name 'removing a wrapping frame|foreign engine reuse'`. Its red setup restores the exact original layout blobs `6f13777` and `dc268e88`; its green setup restores the accepted source. The chrome control script `run-chrome-controls-4044.py` compares the original workspace blob `4595d8f638a1f9213ea229cf8f2aeaae0e2e7a5a` with the corrected implementation. Replay destructive source swaps only in a disposable checkout and verify restoration as the recorded scripts do.

## Diagnostic failures and fixture corrections

Early attempts are retained as failed or diagnostic evidence, separate from the accepted gates. The original environment exhausted shared disk and later disconnected; work continued through remote checkpoints. The recovered runtime initially encountered compiler memory/resource failures. A 104-case parser/Add Note diagnostic and a 92-case controller diagnostic do not replace the accepted cohorts; the latter returned a compiler-process error despite its visible assertions. Loading events and partial runs are not counted as successful tests. The source-mode engine run and normal Flutter run above subsequently completed.

Execution corrected a missing required property in a new marker fixture, stale image-selection guards and the first chrome fixture's assumptions about fake time and unrelated animation. The final chrome control observes the frame scheduler without pumping a frame that would mask the defect. Its home-subtree tickers are muted only for that isolation; modal routes still animate normally. The original workspace fails at the intended observation, and the restored implementation passes.

The native host fixtures also required two host distinctions. Flutter's target-platform override does not change `dart:io Platform.isMacOS`; a Linux host correctly refuses custom-keychain selection before native initialization. The locked `flutter_secure_storage` implementation likewise chooses wire options from the actual host, so macOS-only options cannot be expected on Linux. The corrected fixtures retain admission, backend refusal, readback, cleanup and no-fallback assertions, and add a direct custom-keychain denial case. See [runtime-host-fixture-review.json](runtime-host-fixture-review.json). These are fixture corrections, not evidence that Linux tests exercise real macOS credential services.

The external-store reload diagnostic was also a fixture issue: a registered MethodChannel callback called Flutter's guarded `expect` while `pumpAndSettle` was active. The framework raised a guarded-function conflict before the callback recorded its read, and the production catalog correctly reported the resulting platform exception as unavailable. The callback now uses `expectSync`, retaining the same exact method, ordered read-key, cleared-form and preserved-old-store assertions. No production credential behavior changed for this correction. [runtime-race-fixture-review.json](runtime-race-fixture-review.json) preserves the diagnosis and states that its first raw temporary trace was lost when the runtime shell terminated; that review remains a reported trace summary. The later native bundle independently recreates and retains the expected original failure and corrected pass on the recovered genuine runtime.

## Final combined-source qualification — replay in progress

The final main reconciliation is published at `231bd0403a3d2855dc23bf8dacefaedba01f2aab`, tree `fe67b5ddf50480db3815e1bf7bae75bfaab69f7c`. Its parents preserve both the feature/evidence history and main `b42eca1d`. The [exact merge manifest](final-main-reconciliation.json), [independent source review](final-main-source-review.json) and [root preservation audit](final-main-preservation.json) record the decisions, including both recursive merge bases and the concrete pending accounts differences.

Across the 92 paths changed by the new main, 74 reviewed entries were adopted, 12 were already identical and six deliberately retain the feature's corrected sources or harnesses. No path was deleted. The new native Mail source differs from the previously qualified source by exactly two `sourceStatus` arguments. The two incoming table-fixture cleanups change only equivalent string expressions; their assertions and test registrations are unchanged.

Formatting on exact `231bd040` checked **94 relevant Dart files**, required zero changes and left all checked bytes unchanged. The genuine Dart Analysis Server completed explicit per-file `analysis.getErrors` requests for **94 of 94 files** with **zero errors, zero warnings and 15 informational style findings**. There were no server/plugin errors and no configured analyzer plugins. The informational findings remain in reader/credential sources and fixtures; they are recorded rather than presented as a wholly diagnostic-free analysis.

Affected runtime replays are in progress on the combined source: the established engine cohort; 11 incoming VBA/layout test originals; the unchanged editor aggregate with all 42 committed DOCX fixtures now available; and the changed native Mail, EWS/reply, cloud-provider/forwarding and Downloads/theme originals. Their final counts and raw receipts are not yet claimed here. Earlier red source-swap controls are not repeated.

The earlier 124 credential-only cases and 33 reader cases retain their `2d617a31` attribution. The preservation audit records unchanged credential sources/test files and an identical complete reader package. It explicitly does not equate selected-file identity with identity of every transitive dependency; the affected integration replays address the newly combined behavior.

The [format map](format-map.json) and intermediate analysis receipts retain their original source attribution. The final merge-tree comparison will be recorded in PR metadata after the documentation and evidence are finalized.

## Acceptance boundary and next steps

No live Zotero, Word, LibreOffice or Apache OpenOffice round trip was performed for this increment. Actual picker behavior, cross-application field persistence and refresh, release-host rendering and active ODT transfer remain unqualified here. Zotero's current [requirements](https://www.zotero.org/support/system_requirements) name Word and LibreOffice, and its [troubleshooting guidance](https://www.zotero.org/support/word_processor_plugin_troubleshooting) explicitly excludes Apache OpenOffice. Any historical OpenOffice plugin remains a separately versioned legacy target.

The next work is broader structural text selections; merged/nested tables, header/footer groups, custom table styles and deliberate Notes-pane cell editing; JPEG orientation and grayscale/CMYK fidelity; active ODT/transfer handshakes; and release-host acceptance with exact Zotero, Word and LibreOffice versions and saved artifacts. The [roadmap](../../roadmaps/zotero/word-processor-parity.md#next-implementation-and-acceptance-steps) orders those increments and retains the bounded intake, remote checkpoint and local-validation workflow.
