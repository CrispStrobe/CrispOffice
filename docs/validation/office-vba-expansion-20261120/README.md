# Word and PowerPoint VBA expansion: scoped local qualification

The reviewed 80-file selection has **2,522 accepted passing cases, zero failed and zero skipped cases**, with explicit source provenance. **42 unaffected files / 1,808 cases retain complete passing evidence from baseline `c9cbeb1248d6b5f088d1084a8c113a743aa7a77f` (C9). The other 38 files / 714 cases passed in 13 complete serial groups on final source `192ea2aedbf0b1494627953c79a7042037a63301` (D), tree `1b8e807cd76f2bbc599780170d2a2e993ea4da62`.** Final static checks and all six actual-example VM/JavaScript executions also passed on D.

This is a scoped qualification combining reviewed baseline evidence with final-source reruns. It is **not an 80-file execution on one frozen source tree**. The initial C9 attempt stopped at a real regression in group 28. Its entire failed group, all superseded baseline passes, and every earlier attempt remain preserved and are excluded from the accepted total. This record qualifies the saved source checkpoint; it does not claim that the final merge to remote `main` has occurred.

## What changed

### Word typed formatting, reading order and line presets

The Word adapter accepts typed `Font` and `ParagraphFormat` selectors and required `ByVal` helper parameters, including named helper calls. `Paragraph.Format` selects the same paragraph target as the existing range path. `ReadingOrder` accepts exactly `wdReadingOrderRtl = 0` and `wdReadingOrderLtr = 1`, changes base direction independently of alignment, and writes an explicit override against inherited direction. `LineSpacingRule` accepts the single, one-and-a-half and double presets (`0`, `1`, `2`), persisted as native automatic multipliers `1`, `1.5`, `2` and DOCX line values `240`, `360`, `480`.

Sparse paragraph writes retain unrelated native XML and spacing metadata. A line-only write does not materialize inherited before/after spacing, and same-value assignments remain direct overrides. Namespace-qualified reads and writes keep foreign same-name attributes and elements opaque. Paragraph formatting can target empty paragraphs; font edits require existing nonempty text and exclude paragraph marks. This increment does not add live formatting reads, point-based `LineSpacing`, arbitrary multiples, or `Space1`/`Space15`/`Space2` methods. See the [Word compatibility guide](../../VBA_WORD_MACROS.md).

### PowerPoint text-frame margins and original-value preservation

`TextFrame.MarginLeft`, `MarginTop`, `MarginRight` and `MarginBottom` work through typed aliases, `With`, and helper targets. Values are finite nonnegative numbers in points whose conversion at 12,700 EMUs per point is exactly integral within `0..2147483647`; invalid precision, negative/out-of-range values, numeric Strings and Booleans are refused. A side write preserves the other sides, anchor, rich text, fields, hyperlinks, direction and autofit. Explicit zero and same-value native assignments write direct values; omitted sides remain absent.

The model and PDF path use the direct DrawingML inset rectangle, including unequal top/bottom margins and bounded overflow. Imported original inset values now form an immutable source baseline: untouched nondefault margins do not turn a direct plain-text replacement into an explicit rich-paragraph edit. Genuine direct model inset changes remain detectable, including a change back to the constructor default, and a same-value explicit native write retains its override intent. Three additional final-source cases cover these distinctions.

Tests retain unsaved rich-run formatting, zero-height autofit text, extension data, namespace ownership, layout bindings, and untouched malformed or unsupported native sides across repeated saves. Editor paint/hit-test code was updated and its tracked source is included in the static manifest, but Flutter execution was outside this gate. Layout/master inherited margins remain preserved in the package; their inherited values are **not resolved by the live margin projection**. This increment does not add `WordWrap`, `AutoSize`, text-direction edits, or margin getters. See the [PowerPoint guide](../../VBA_POWERPOINT_MACROS.md).

### Shared named and optional helper arguments

The Word, PowerPoint and Excel adapters share case-insensitive `name:=expression` helper arguments, positional arguments before named arguments, optional-position holes, and omitted optional scalar `ByVal` parameters. Supplied expressions execute once in written source order before binding to callee parameter order. Defaults are checked declaration-time constant expressions in module scope. Duplicate or unknown names, required omissions, invalid ordering and unsupported types are rejected even in unused helpers and unreachable branches.

Optional `Long`, `Double`, `String`, `Boolean` and scalar `Variant` parameters have the documented defaults. An omitted defaultless Variant has a distinct Missing state; `IsMissing` accepts the current helper's direct optional Variant formal. Explicit `Empty` and `Null` remain distinct, assignment clears Missing, and an ordinary unhandled Missing read is refused. This is bounded Missing behavior, not general Variant Error propagation. ByRef, array/ParamArray and optional object parameters, `Nothing` defaults, and named application-member/intrinsic arguments remain unsupported. Shared work/copy/call budgets and native transaction boundaries remain in force. See [the argument contract](../../VBA_ARGUMENTS.md) and [shared macro guide](../../VBA_MACROS.md).

## Accepted evidence and final reruns

| Check | Result and source |
| --- | --- |
| Accepted combined selection | 2,522 cases across 80 distinct files; 0 failed; 0 skipped; split provenance below |
| Retained complete baseline evidence | 42 files / 1,808 cases on C9; reviewed unchanged and outside the changed native paths |
| Final affected, guard and previously unrun files | 38 files / 714 cases on D in 13 complete groups |
| Newly selected files | 16 files / 332 accepted cases, already included in the combined total; the other 64 files retain the prior selection |
| Final engine analysis | `dart analyze --fatal-infos`: exit 0 on D |
| Final formatting | 33 relevant Dart files; `--output=none --set-exit-if-changed`: exit 0 on D |
| Actual examples | All six committed BAS files executed on Dart VM and compiled JavaScript on D |
| Cross-runtime semantics | Exact canonical JSON equality; no numeric tolerance |
| Raw VM/JavaScript JSON bytes | different; recorded separately from semantic equality |
| Final Word incremental/full geometry | 12 passing cases / 308 comparisons on D, derived from verified fixed source loops |
| Qualified source union | 1,164 paths; exactly 8 approved C9-to-D input changes, 1,156 exactly unchanged inputs |

The [acceptance receipt](runtime/acceptance.json), [complete per-file case provenance](runtime/per-file.json), [reviewed scoped plan](runtime/scoped-plan.json), [final group plan](runtime/scoped-shards.json), [source manifests](runtime/source-manifests.json), and [exact source delta](runtime/source-delta.json) make the split reviewable. Every retained file refers to its original complete passing C9 group, raw JSONL checksum, case-name multiset and source hash. Every rerun file refers to its final D group. An original group can contain both retained and superseded files; only its explicitly retained files contribute C9 cases.

The collector independently re-derives all visible case counts, requires one complete successful runner ending, complete selected-suite coverage, matching declared root test counts, and a completion for every started test. Hidden loading/setup events are checked for success and excluded from totals. Cases are identified by `(file, full test name, occurrence ordinal per name)`: the pre-existing duplicate full name in the slide-format suite represents two legitimate tests, both retained in the counts. The partition is disjoint and full-name multiplicities are preserved. The final rerun process durations sum to 1123.514 seconds; this is not total session wall time or baseline execution time.

The reviewed impact decision reruns all selected PML consumers, the affected Word-layout consumers, native VBA integration, shared runtime/CLI/MCP and PDF guards, and the files from the failed or unrun tail. The two changed test files each add exactly three cases. Retained files keep their original C9 provenance; source review is a qualification decision, not a new execution. The complete reasons are in the scoped plan.

Test, static and portable capture domains intentionally differ. The test gate includes editor fonts and manifests; static capture includes the entire engine package plus the touched editor renderer; portable capture includes compiler/runtime sources. Hashes agree on all overlaps within each commit, all completed baseline groups share one baseline manifest, and all final groups share one final manifest. Each manifest is independently checked against its commit's Git blobs. The complete final union is also checked against disk and HEAD. The exact eight approved changes include the PML baseline repair, its three cases, Word layout owner/fallback and empty-cache guards, its three cases, the research acceptance registration, and the changelog. The C9 prefix-slice checkpoint guards remain present. No change to the shared VBA language implementation is hidden by this qualification split.

## Actual BAS inputs and native persistence

| Committed example | Native operations |
| --- | ---: |
| [word_typography.bas](../../../packages/quds_office_engine/example/macros/word_typography.bas) | 12 |
| [powerpoint_slideshow.bas](../../../packages/quds_office_engine/example/macros/powerpoint_slideshow.bas) | 12 |
| [word_optional_helpers.bas](../../../packages/quds_office_engine/example/macros/word_optional_helpers.bas) | 7 |
| [powerpoint_optional_helpers.bas](../../../packages/quds_office_engine/example/macros/powerpoint_optional_helpers.bas) | 5 |
| [word_paragraph_layout.bas](../../../packages/quds_office_engine/example/macros/word_paragraph_layout.bas) | 10 |
| [powerpoint_text_margins.bas](../../../packages/quds_office_engine/example/macros/powerpoint_text_margins.bas) | 5 |

The driver receives the exact source bytes via six base64 compiler defines; the collector independently checks both VM and JavaScript compiler arguments against the committed files and their SHA-256 hashes. Detached validation leaves the caller input and revision unchanged. Execution publishes one native transaction, verifies intended and untouched content, and checks additional native save/reopen cycles. The combined driver also exercises exact one-EMU and signed-Long-maximum positive-EMU margin boundaries (`1` and `2147483647`) through actual PPTX serialization. Helper coverage includes source-order effects, Missing/refusal behavior and late native failure rollback.

The prior typography/slideshow pair checks one additional save/reopen; the helper and new paragraph/margin examples each check two additional native save/reopens. The examples use generated fixture documents with existing body paragraphs or named Title shapes; they do not create those application targets implicitly.

Cross-runtime comparison parses each complete JSON output, recursively converts only integral floating-point numbers to integers, then serializes with sorted keys, UTF-8 strings and compact separators. Boolean and String types remain distinct; non-finite values are forbidden; fractional numeric values receive no tolerance. Python Boolean-versus-integer equality is not used as the comparison. The [canonical bytes](runtime/portable-canonical.json) and SHA-256 hashes of both raw outputs are retained. Integral floating-point spelling can differ between the raw runtime outputs; canonical semantic equality is the accepted claim. ZIP container bytes are not compared across runtimes.

## Real regressions, repairs and preserved historical evidence

The pre-cache-fix integrated source `89910ff6` produced a real differential failure at seed 7, structures enabled, edit 44. A paragraph edited while frame wrapping was active retained stale unwrapped line breaks; later flow changes could make the old cache readable again. The repair invalidates old breaks at paragraph entry when the block is not proven clean, including early-return and cache-bypass paths. The old-source negative control records **two failed focused cases**, followed by **two passing focused cases** on the recorded repaired source. These [supplemental controls](runtime/cache-reproduction.json) retain their actual old/fixed production hashes and are **not added** to the accepted total or relabeled as D execution.

The final D differential rerun preserves the original 302 fresh-engine comparisons: 10 convergence comparisons, six deterministic 48-edit sequences (288), two note fallbacks and two discarded-state/section-list comparisons. Two text/font frame-edit cases add three comparisons each, producing 12 cases and 308 comparisons. The [source-derived proof](runtime/differential.json) binds fixed loop bounds to the final passing test-file hash; 308 is not a runtime counter emitted by package:test. Geometry uses pure Dart null-font fallback metrics, without installed Word or Flutter font-metric comparison. Final incoming layout work additionally binds incremental state to its owning engine, falls back for cross-engine state, and retires empty-paragraph caches; affected selected layout files were rerun on D.

C9 group 28 then exposed a separate legacy multiline text-replacement regression. Imported nondefault text margins were incorrectly treated as a new inset edit, causing `resolvedRichText` to synthesize paragraphs for a plain-text replacement. The original receipt and raw failure are retained in the archive. The final immutable source-inset baseline repair preserves the legacy plain-text fallback while retaining genuine direct and explicit native margin edits. The legacy fidelity suite, new inset regressions and selected native/PDF consumers all contribute only final D evidence. No passing prefix from failed C9 group 28 is counted.

## Incoming work, final cutoff and saved checkpoints

The [final-cutoff reconciliation](integration/final-cutoff-reconciliation.md) and [inclusion proof](integration/final-cutoff-inclusion.json) account for the captured **16 current branch refs, 249 PR heads and 4 upstream heads**, plus **9 deleted earlier branch refs** and the recorded previous heads of advancing refs. Current PR heads resolve as 235 ancestors and 14 verified historical equivalents; all four upstream heads are ancestors. The collector recomputes the 14 historical changed-path proofs; 13 also have complete-tree identity. The four explicitly required incoming heads, including captured main `b42eca1db058f0def247b86c2f15dea90c11b4e8`, are ancestors of D. Earlier C9 inclusion and main-review receipts remain separate historical records.

The complete C9-to-D tree delta has 92 paths: 8 approved engine input changes and 84 paths outside the qualified input union. Each changed path records mode, object type, Git object identity and SHA-256. Incoming Mail/account, Outbox, desktop/editor and documentation integration is included in the history and audit; this source-object accounting does not claim new Flutter, Outbox, keychain or mail-provider runtime execution.

The [captured-main review](integration/final-cutoff-main-review.json) compares D with the prospective merge of D and the already included captured main. That prospective tree is exactly D, so all 1,164 qualified input entries are preserved. A direct snapshot comparison between D and captured main is a different comparison and retains its recorded differences. The [compact checked main proof](runtime/main-proof.json) also records the locally fetched main ref at collection and whether a newer head needs separate review. This is a pre-merge source-preservation check, not an actual final-merge receipt. Any subsequent main advance or evidence commit needs a corresponding final consistency check.

The published first-parent checkpoints are preserved below with actual remote-history identities. The collector checks their ancestry and the already fetched remote checkpoint ref without fetching or querying GitHub.

| Published checkpoint | Purpose |
| --- | --- |
| `f761cfe6d25c27fede697943a18ab89c11353d8f` | Reconcile captured Mail, Downloads and Zotero integration heads [skip ci] |
| `b6d6a26d9fcb5602ad9bd65d451aa5273881c933` | Reconcile native credential storage and Mail reader chrome [skip ci] |
| `9e0d8173fada4ae3f22ace5c5b896c21ab5191da` | Integrate captured Word relayout and reconcile alternate Downloads history [skip ci] |
| `58000866a6a36d7cc29e2a5677ef23c2f71dff51` | Record complete intake and independent incremental-layout qualification [skip ci] |
| `979cfa77c3bf7718664db7ecb4f62b656a58f187` | Extend Word and PowerPoint VBA formatting and shared helper arguments [skip ci] |
| `40572427fc7d62b0fb2423712fa79162814b53a9` | Complete reviewed Word bindings and portable Office expansion examples [skip ci] |
| `050ba58acad35f41803377b385ea22c833822845` | Reconcile refreshed main, Mail, Zotero tables and Word layout before qualification [skip ci] |
| `89910ff6363cd45ced5faf0e48b11cac46754b28` | Qualify incoming Zotero fixtures and format layout regressions [skip ci] |
| `4a2607162199deedde0587b2cdb919bbf6435251` | Invalidate stale Word breaks across frame-wrapping edits [skip ci] |
| `c9cbeb1248d6b5f088d1084a8c113a743aa7a77f` | Reconcile current main cache repair and credential packaging [skip ci] |
| `dfa8407b54c98e6f5810413b56fcde4853627002` | Preserve imported PowerPoint margin baselines during text edits [skip ci] |
| `192ea2aedbf0b1494627953c79a7042037a63301` | Reconcile final captured Zotero, layout, credential and Mail heads [skip ci] |

## Runtime, evidence and reproduction

The environment uses Dart **3.13.7**, package:test **1.31.1**, test_core **0.6.18**, and Node **v24.22.3**. The 56 shared hosted package versions match the repository lockfile. A standalone pure-Dart workspace provides unchanged engine/legacy/example manifests and a canonical package configuration. [Environment metadata](runtime/environment.json) records SDK archive, dependency lock, package configuration and precompiled runner checksums.

The unmodified package:test runner was compiled to kernel using the installed SDK's `gen_kernel_aot.dart.snapshot` under `dartaotruntime --old_gen_heap_size=512`. Its `.dill` runs under the normal Dart VM with the same old-generation bound, `--compiler source --concurrency=1 --timeout=4x --fail-fast`. The final 13 fresh processes avoid accumulated runner/compiler state; process-spawning integration files are isolated. This old-generation bound is not a process RSS cap and is not forwarded to independent CLI/MCP subprocesses or the normal JavaScript compiler. The archived bounded-compile receipt preserves the exact successful compiler command and runner checksum.

The [evidence archive](runtime/acceptance-evidence.tar.gz) contains 416 indexed raw evidence/configuration/source members plus its internal index, including every regular file under `validation-results`, the selected root development logs, exact collection/validation/intake drivers, plan, and source-specific integration records. The [archive index](runtime/archive-index.json) records classification, byte count and SHA-256 for every member. [Checksums](runtime/SHA256SUMS) cover compact outputs and the archive. SDK/pub-cache binaries, compiled JavaScript/kernel binaries, and large generated Office fixtures are omitted.

The archive retains the original cache failure, C9 group28 failure, interrupted pre-main-refresh run, startup SIGKILL attempts, failed normal kernel-wrapper compilation, setup attempts and development results. A raw successful original group may contain cases that are superseded in the final aggregate; per-file provenance determines which original cases are retained. Earlier static/portable checks are historical and are replaced by final scoped checks. Historical controls, development runs, failed groups and superseded cases never inflate the accepted total. The earlier 10-case/302-comparison receipt remains labeled as historical.

To reproduce the final cohort, restore the recorded SDK/dependencies, adapt archived scratch-root paths, and use the pinned `scoped-qualification-plan.json` with `run_scoped_expansion.py` after final scoped static and portable checks. The archived baseline raw evidence is required to reconstruct retained cases; a fresh all-80-files D run would be a separate stronger execution claim. The collector refuses incomplete groups, missing or duplicate runtime IDs, uncompleted declared cases, skipped/failing accepted cases, source mismatches, stale HEAD, unreviewed source deltas or missing historical failure evidence. Collection performs no tests, compiler, analyzer, network, CI, merge or remote mutation.

## Publication reconciliation with newer main

After the scoped run, remote main advanced to
`13be50464d1b43e9f2100fb9ccc12f8fe22eb55e` through the completed Outbox PR #250.
The normal merge into the publication tree is conflict-free. Its 22 changes
are outside the recorded input union: **all 1,164 qualified engine/input entries
retain their exact mode, object type, Git blob and SHA-256**, and the merged
working files were independently checked against the final-source manifest.
The [publication review](integration/final-publication-main-review.md) and
[machine proof](integration/final-publication-main-review.json) record the
comparison, including the combined native-host notice and the retained newer
Outbox qualification artifacts. Those incoming runtime claims remain tied to
their own source; the earlier cutoff's work-in-progress description remains a
historical observation. This source-preservation check is separate from the
subsequent final GitHub merge verification.

## Qualification limits

GitHub Actions was neither queried nor awaited. The checks cover the bounded, explicitly invoked VBA source-to-native-plan adapter, native macro/CLI/MCP behavior and engine persistence. Embedded VBA projects remain preserved and inert; full VBA execution, COM, events and a VBA editor remain outside this increment. Flutter UI/controller execution, installed Microsoft Word/PowerPoint, platform keychains, native signing and live mail providers were not executed here. Incoming application source inclusion and historical incoming runtime evidence remain separate from this scoped Office engine qualification.
