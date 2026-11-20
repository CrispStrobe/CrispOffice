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

These histories overlap; six heads do not mean six independent feature sets. The bounded assessment did not establish whole-head equivalence or acceptance. Main `b42eca1db058f0def247b86c2f15dea90c11b4e8` subsequently incorporated the captured VBA, Downloads, Mail host, reply/forward and validation histories. The remaining Mail accounts continuation `cb7f8325` was later incorporated through PR #251. **All six captured heads are included in the final adopted main ancestry.** The earlier pending entries remain historical snapshots, not the final disposition. The final accounts implementation includes its generation-aware credential-instance cache rule, system-storage factory seam, credential-settings opener seam and backend-switch tests while preserving this branch's credential revision and transaction fences.

The `231bd040` reconciliation used Git's recursive merge handling for both common ancestors, `9b581e8a` and `03de5b6a`. It preserved the Zotero table behavior, credential revision fences, layout-cache ownership checks and idle chrome scheduling fix alongside main's VBA, paragraph serialization, slide-margin rendering, Mail forwarding and license-loader changes. The later `70e69c88` checkpoint incorporated Outbox main `13be5046`. Final consolidation adopts the complete production, test and configuration tree of main `243b99a5ee56e591991f381533b2363586bd5dd0`, including the completed accounts, multiple-drafts, VBA and Zotero/Mail reconciliation work. Only documentation and evidence are added on top of that tree; the exact-source reviews below qualify that decision.

The preserved remote branch is `codex/zotero-research-tables-20261120`. The implementation review, [PR #249](https://github.com/CrispStrobe/quds_office_suite/pull/249), is already recorded as merged through the incoming ancestry. A separate follow-up PR consolidates the remaining documentation and evidence on current main; its publication details are linked from PR #249. Successive remote checkpoints retain intake, implementation, corrections, formatting, later reconciliation and validation receipts. The raw evidence identifies each tested source separately; the completed combined-source replays and final current-main adoption are recorded below. No GitHub Actions runs, check statuses or workflow queues were queried or awaited.

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

For the selected incoming host replay, run from `packages/quds_office_editor/example` after normal locked dependency resolution:

```sh
dart tool/incoming_reconciliation_acceptance.dart
```

Set `FLUTTER_BIN` when Flutter is not on `PATH`. The current helper, blob `55dc70ad3bd15b3cfb910c6a07e49f5c3dbb6534`, executes nine sequential groups with 23 original files: the original 16, two cloud-provider/forwarding files and five Outbox files. Each original file retains normal Flutter tester isolation. A group must exit zero and emit exactly one terminal JSON event with `success: true`; incomplete output is not accepted. This is a selected incoming host replay, not a claim of complete Mail coverage. The earlier 372-case receipt remains attributed to its original seven-group source and is not relabelled as this later replay.

The additional compose/autosave/draft lifecycle replay is also run from the example directory:

```sh
flutter test --no-pub --reporter=json --concurrency=1 \
  test/studio_mail_compose_test.dart \
  test/studio_mail_draft_autosave_test.dart \
  test/studio_mail_draft_store_test.dart
```

The current Mail and VBA work records linked below retain their own larger replay commands and source qualification.

The engine control script `run-engine-controls.py` targets `test/word_incremental_layout_test.dart` with `--name 'removing a wrapping frame|foreign engine reuse'`. Its red setup restores the exact original layout blobs `6f13777` and `dc268e88`; its green setup restores the accepted source. The chrome control script `run-chrome-controls-4044.py` compares the original workspace blob `4595d8f638a1f9213ea229cf8f2aeaae0e2e7a5a` with the corrected implementation. Replay destructive source swaps only in a disposable checkout and verify restoration as the recorded scripts do.

## Diagnostic failures and fixture corrections

Early attempts are retained as failed or diagnostic evidence, separate from the accepted gates. The original environment exhausted shared disk and later disconnected; work continued through remote checkpoints. The recovered runtime initially encountered compiler memory/resource failures. A 104-case parser/Add Note diagnostic and a 92-case controller diagnostic do not replace the accepted cohorts; the latter returned a compiler-process error despite its visible assertions. Loading events and partial runs are not counted as successful tests. The source-mode engine run and normal Flutter run above subsequently completed.

Execution corrected a missing required property in a new marker fixture, stale image-selection guards and the first chrome fixture's assumptions about fake time and unrelated animation. The final chrome control observes the frame scheduler without pumping a frame that would mask the defect. Its home-subtree tickers are muted only for that isolation; modal routes still animate normally. The original workspace fails at the intended observation, and the restored implementation passes.

The native host fixtures also required two host distinctions. Flutter's target-platform override does not change `dart:io Platform.isMacOS`; a Linux host correctly refuses custom-keychain selection before native initialization. The locked `flutter_secure_storage` implementation likewise chooses wire options from the actual host, so macOS-only options cannot be expected on Linux. The corrected fixtures retain admission, backend refusal, readback, cleanup and no-fallback assertions, and add a direct custom-keychain denial case. See [runtime-host-fixture-review.json](runtime-host-fixture-review.json). These are fixture corrections, not evidence that Linux tests exercise real macOS credential services.

The external-store reload diagnostic was also a fixture issue: a registered MethodChannel callback called Flutter's guarded `expect` while `pumpAndSettle` was active. The framework raised a guarded-function conflict before the callback recorded its read, and the production catalog correctly reported the resulting platform exception as unavailable. The callback now uses `expectSync`, retaining the same exact method, ordered read-key, cleared-form and preserved-old-store assertions. No production credential behavior changed for this correction. [runtime-race-fixture-review.json](runtime-race-fixture-review.json) preserves the diagnosis and states that its first raw temporary trace was lost when the runtime shell terminated; that review remains a reported trace summary. The later native bundle independently recreates and retains the expected original failure and corrected pass on the recovered genuine runtime.

## Completed combined-source qualification

The combined-source replay used immutable commit `231bd0403a3d2855dc23bf8dacefaedba01f2aab`, tree `fe67b5ddf50480db3815e1bf7bae75bfaab69f7c`. Its parents preserve the feature/evidence history and main `b42eca1d`. The [merge manifest](final-main-reconciliation.json), [independent review](final-main-source-review.json) and [preservation audit](final-main-preservation.json) retain the exact decisions at that boundary, including both recursive merge bases. Their then-pending accounts disposition is superseded by the final adoption below.

Across the 92 paths changed by that main, 74 reviewed entries were adopted, 12 were already identical and six retained this branch's corrected sources or harnesses. No path was deleted. Native Mail differed from the prior qualified source by exactly two `sourceStatus` arguments. The two incoming table-fixture cleanups changed only equivalent string expressions; their assertions and registrations were unchanged.

All six accepted processes below exited zero, emitted exactly one successful terminal event and retained identical hashes for all **2,226 tracked Dart files** before and after execution:

| Accepted process at `231bd040` | Passed | Skipped |
| --- | ---: | ---: |
| Zotero and layout engine cohort | 399 | 0 |
| Incoming VBA and differential-layout originals | 329 | 0 |
| Flutter editor/controller cohort | 332 | 8 |
| Native, cloud-provider and forwarding Mail originals | 148 | 0 |
| EWS/reply originals | 104 | 0 |
| Downloads/theme originals | 46 | 0 |
| **Combined accepted executions** | **1,358** | **8** |

There were zero accepted failures or errors. The source-manifest SHA-256 before and after was `17248fcc60854b7e947bfc9e45b52a05d9789f351c8ac253bcc8dec06a311d70`. The raw events, process receipts, exact per-file results, discovered fixtures and before/after manifests are in [checkpoint-231bd-replay-evidence.tar.xz](checkpoint-231bd-replay-evidence.tar.xz), with [archive metadata](checkpoint-231bd-replay-evidence.json) and a [readable summary](checkpoint-231bd-replay-summary.json). Engine/VBA receipts are also preserved in [checkpoint-reconciled-engine-evidence.tar.xz](checkpoint-reconciled-engine-evidence.tar.xz), its [metadata](checkpoint-reconciled-engine-evidence.json) and [summary](checkpoint-reconciled-engine-summary.json). These overlapping receipts are not separate test totals.

The full committed DOCX corpus contained 42 discovered fixtures. Thirty-four were exercised; eight authored floating-image fixtures were explicitly skipped by the unchanged `no paragraphs to edit` guard. All original 313 editor cases passed again, and 19 additional fixtures were exercised. The layout-equivalence subgroup therefore has 42 passes (34 fixture cases and eight synthetic cases) plus eight skips. The editor process completed through the normal genuine Flutter CLI in 302.64 seconds. **This clears the earlier Flutter/controller execution blocker; it does not qualify the eight skipped fixture paths.**

The first incoming VBA run used the test runner's default 30-second limit and ended with 326 passes plus three CLI timeout errors, exit 1. That failed attempt is retained and excluded. Each affected CLI case launches two sequential genuine Dart children; observed children took roughly 15–19 seconds apiece. After all old children had exited, the same source and assertions were replayed with the standard `--timeout=2m` option. The complete 329-case process then passed in 329.70 seconds. No assertion or production behavior was weakened.

An independent [literal-LF event audit](checkpoint-231bd-lf-audit.json), using the committed [audit script](audit_completed_replays.py), re-read all six unchanged raw streams. It confirmed the same 1,358 passes and eight skips, each visible test ID starting/completing exactly once, one start event and one successful terminal event per process, and no malformed, error, incomplete or protocol events. The original Python summaries used `splitlines()`; the audit avoids its treatment of legal Unicode separators. None of these particular case names contained such a separator. This was an audit of existing results, not an additional SDK test execution.

### Formatting and analysis

On `231bd040`, formatting checked **94 relevant Dart files**, required zero changes and left their bytes unchanged. The genuine Dart Analysis Server completed explicit `analysis.getErrors` responses for **94 of 94 files**: **zero errors, zero warnings and 15 informational findings**. No server/plugin errors occurred, and no analyzer plugins were configured. The remaining informational findings are in reader/credential sources and fixtures; this is not described as a wholly diagnostic-free run.

[Analysis evidence](checkpoint-analysis-evidence.tar.xz), [metadata](checkpoint-analysis-evidence.json) and the [summary](checkpoint-analysis-summary.json) retain the per-file diagnostics and actual nearest package options. In particular, the example's nearer configuration does not inherit the root `prefer_final_locals` option. Differences from earlier diagnostic counts are not claimed as source cleanup. The [format map](format-map.json) and earlier receipts retain their original source attribution.

### Outbox integration follow-up

Checkpoint `70e69c8854ab30f83d8711d3f4bf270385ed27b4` incorporated main `13be5046`, preserving the qualified Word sources and the incoming Outbox behavior. The [reconciliation](latest-main-outbox-reconciliation.json) and [preservation proof](latest-main-outbox-preservation.json) record that source boundary.

Six focused genuine processes completed on the exact `70e69c88` source:

| Follow-up process | Passed |
| --- | ---: |
| Two added wrapped-cache differential cases | 2 |
| Word workspace/chrome smoke | 1 |
| Outbox cloud/submission | 22 |
| Outbox dialog/host/store | 33 |
| Existing native/EWS interactions | 142 |
| Compose/autosave/draft lifecycle | 50 |
| **Successful follow-up executions** | **250** |

Every process exited zero with one successful terminal event and zero failures, errors or skips. All **2,237 tracked Dart source hashes** remained unchanged and matched the committed inputs. The source-manifest SHA-256 was `327c8c16424c05630484a1ec094d99371888cb1265606353695bb273fe0bf5fb`. See [raw follow-up evidence](checkpoint-outbox-followup-evidence.tar.xz), [archive metadata](checkpoint-outbox-followup-evidence.json) and [readable summary](checkpoint-outbox-followup-summary.json). The archive is 216,996 bytes with SHA-256 `9efd133341eab082fbfb36a03d75d9b0c9b3434748056711fdfa4157178a929c`. These executions include repeated cases from earlier checkpoints and must not be added to 1,358 as a distinct-test total.

The focused format check covered **23 changed Dart files**, with zero changes. The genuine Analysis Server completed 23 of 23 files, exited zero and reported **zero diagnostics at any severity**. [Raw analysis evidence](checkpoint-outbox-analysis-evidence.tar.xz) and [metadata](checkpoint-outbox-analysis-evidence.json) preserve that gate. It supplements rather than replaces the earlier 94-file analysis with 15 informational findings.

The unchanged Python accounting/tooling suite also completed 48 tests. Those tests are excluded from product totals. Its first import-only attempt failed because the sparse checkout lacked tracked `tools/mail/check_reader.py`; materializing that exact committed file allowed the unchanged suite to pass. Both attempts remain in the evidence.

## Final adoption of qualified current main

The final consolidation uses main **`243b99a5ee56e591991f381533b2363586bd5dd0`**, tree **`d4d86f3b5dd0ddeb94af281222f4269d62873fbe`**, as its complete base. This main already preserves `70e69c88` and `a2b87ee3`, and includes the accounts continuation through PR #251, multiple drafts through PR #253, the completed VBA work and the final Zotero/Mail reconciliation through PR #255. The consolidation adds only this branch's remaining documentation and evidence, including the complete follow-up bundle and LF audit. Both the existing feature history and current main are parents of the final checkpoint.

The [Mail/credential adoption review](final-main-adoption.json), [Word/Zotero/PPT adoption review](final-main-engine-adoption.json) and [root source-continuity proof](final-main-root-continuity.json) record the exact comparisons. The review confirms that native serialized selection, revision fences, captured backend identities, actual-host admission, bounded canonical catalog/readback, stale-save guards and external-dialog clear/reload behavior remain intact. The later generation-aware credential cache and test seams are retained. The critical native save, persist, listener and reload blocks remain byte-identical to the qualified `70e69c88` implementation.

The final engine package is **identical as a Git tree** to qualified commit `192ea2aedbf0b1494627953c79a7042037a63301`; the root dependency manifest, lockfile and analysis options also match. Relative to our `70e69c88` checkpoint, the Zotero parser/citing, Word serializers, controller, core editor and workspace chrome sources are unchanged. Incoming layout retains our owner/cache protections. Its additional line/frame prefix-count convergence guard is a real conservative behavior change, not a formatting-only edit: it can reduce convergence opportunities while preserving correctness. The incoming PPT repair also genuinely fixes the imported text-margin baseline and adds three inset regressions. Both are adopted with their existing exact-source acceptance; no product edits are layered on top.

### Incoming acceptance retained with its original attribution

The [VBA/engine acceptance](../office-vba-expansion-20261120/runtime/acceptance.json) records **714 actual final-source passes** at `192ea2ae`, across 38 affected files in 13 groups, with zero failures or skips. Relevant groups include differential layout (12), layout (9), prefix propagation (2), inset preservation (12), PPT margin integration (16), text fidelity (6) and explicit rich style (1). Its larger **2,522-case acceptance is composed of those 714 reruns plus 1,808 retained baseline cases**. It is not a fresh single-source 2,522-case run, and is not added to this branch's execution totals.

The [multiple-drafts acceptance](../mail-multiple-drafts-20261120/acceptance.json) identifies tested source `2a775500aa31b5e8426df54c3f68f4ceadec0790`. Its complete comparison to adopted main has 30 changed paths: documentation/evidence and the already qualified incoming replay helper only. There are **zero intervening production, test, dependency or configuration changes**. That record reports intake core/MIME/transport plus three engine files (579), full native store (596), Node portability (46), shared Mail UI (96), and **964 composed Studio acceptance cases**. The Studio result combines the broad run's 962 passes/two failures with complete corrected-file replays: EWS (61) and saved Mail (14). The EWS correction preserves read-only Send/queue restrictions while allowing local editing; the saved-Mail fixture now waits for the real 450 ms reverse transition instead of the previous 350 ms assumption. Original failures and corrected runs are retained. Nineteen changed Dart files passed strict analysis/format checks. These overlapping and cross-platform counts are not summed into a unique-test total.

The separate Outbox acceptance at `ce9ff1c8b155c03a0e2707d6fc8b41b52e611a93` remains historical evidence for its 172 core/store and 72 SMTP cases. Its committed archive was downloaded and SHA-256 verified, and its original streams were independently LF-audited. Later multiple-drafts work changes store sources, so the older 172 cases are not presented as exact-current-store acceptance; the later 596-case record supplies that attribution. The selected runtime inventory is not a claim to hash every transitive dependency.

No additional product replay was needed for this final documentation/evidence-only consolidation. Before merge, the non-`docs` root entries are compared with the adopted main tree. The final feature checkpoint, remote merge commit and exact merge-tree comparison are recorded in the follow-up PR metadata and linked from PR #249 after publication, avoiding a self-referential commit identifier in this file. No GitHub Actions runs, check statuses or workflow queues were queried or awaited.

## Acceptance boundary and next steps

No live Zotero, Word, LibreOffice or Apache OpenOffice round trip was performed for this increment. Actual picker behavior, cross-application field persistence and refresh, release-host rendering and active ODT transfer remain unqualified here. Zotero's current [requirements](https://www.zotero.org/support/system_requirements) name Word and LibreOffice, and its [troubleshooting guidance](https://www.zotero.org/support/word_processor_plugin_troubleshooting) explicitly excludes Apache OpenOffice. Any historical OpenOffice plugin remains a separately versioned legacy target.

The next work is broader structural text selections; merged/nested tables, header/footer groups, custom table styles and deliberate Notes-pane cell editing; JPEG orientation and grayscale/CMYK fidelity; active ODT/transfer handshakes; and release-host acceptance with exact Zotero, Word and LibreOffice versions and saved artifacts. The [roadmap](../../roadmaps/zotero/word-processor-parity.md#next-implementation-and-acceptance-steps) orders those increments and retains the bounded intake, remote checkpoint and local-validation workflow.
