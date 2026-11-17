# German proofing recovery and completed qualification — 17 November 2026

This continuation recovered the interrupted publication, integrated the captured incoming work, repaired Office export integration defects, and completed fresh local proofing and export qualification. Work was saved incrementally to `codex/german-morphology-20261117` and is tracked in [PR #114](https://github.com/CrispStrobe/quds_office_suite/pull/114). No GitHub Actions workflow was dispatched or awaited.

**Accepted final product source:** `898c4c07f421d86a8cea460b13fd3e136088b553`.
**Earlier closing-main Office source:** `7002d750e20e44392c6c9ba1a92d910fd87fe593`.
**Fresh proofing/native-quality source:** `8d6403021f797a05e9c9fc49052c3d19d3766844`.
The intervening implementation changes are confined to the ODT and ODP writers; proofing, GECToR, AOT library and editor implementation paths remain unchanged. Earlier test executions retain their original source attribution. [Delivery source continuity](delivery-main/source-continuity.json) · [Delivery field verification](delivery-main/verification.json) · [Earlier continuity](source-continuity.json) · [Earlier qualification](verification.json)

## What was recovered and integrated

The previous agent successfully saved its final report and full archive at `e67c8090e0bc93eac6b4eb0195461d52e27b7d8e`; updating the draft PR description was the interrupted publication step. Independent inspection verifies the original archive SHA-256, all **343 members**, **33,934,014 uncompressed bytes**, and every member hash. Its test counts, projected UTF-16 corrections, model comparisons and timing statistics match the original report. Those historical results remain separately available in the [original completion report](../german-proofing-next-20261117/README.md) and [recovery audit](recovered-evidence-audit.json).

The actual-server inventory captured **266 branch and PR refs at 18:54:24 CET (17:54:24 UTC)**. Seven maximal incoming tips covered all commits outside the recovered checkpoint. All captured refs are ancestors of the integrated source. The continuation retained the source and evidence from Office consolidation/qualification, German noun agreement, irregular-participle suggestions, optional AOT analysis/local transport, and the feature/vendor/main column histories. Different table/tab tests with the same incoming filename are retained under distinct filenames, and the frame-aware text extraction compatibility alias is preserved. [Captured refs](incoming-refs.json) · [Integration decisions](integration-decisions.json)

A closing main observation found `914d74f13d1ae75d9b45ea0e51873c31ff63ec62`, containing #121 chart-data fallback export and #122 paragraph column breaks/keep-together. This main update was incorporated at `0e73c748`, retaining both the existing hyperlink assertion and the new chart-data assertions. Its two identified integration defects were repaired at `7002d750`. The inventory statements apply to the recorded snapshots, not later concurrent remote work. [Closing-main observation](closing-main-observation.json)

A final PR readback identified main `13e7172977d671190ba8c3cf964deec4d7473090`, which landed prior Office qualification/continuation and new #124 inline field conversion. The histories were reconciled at `024ff173`, retaining the already-qualified Office and grammar implementations. The only new production delta was ODT field handling; its bounded cached-text repair is saved at `898c4c07`. The final amendment has its own source-bound qualification and archive, while the original 167-file evidence archive remains unchanged. [Delivery-main amendment](delivery-main/README.md)

## Fresh German quality results

The compiled runner uses the application's deterministic-first report-merging policy, actual pinned native GECToR inference, persistent worker, dictionary guards, and original UTF-16 spans. It records writing-only, full deterministic, model-only and combined outcomes. Scoring uses the first displayed replacement in a declared single-pass projection; it does not select an alternative because that alternative matches the expected answer.

Both corpora and their expected answers are byte-for-byte unchanged. The existing synthetic challenge panel is a **development regression panel**, not a new prospective or representative language evaluation. Unsupported de-AT/de-CH model observations remain outside the supported clean denominator.

| Panel and view | Previously qualified exact corrections | Fresh exact corrections | Fresh supported clean flags / changes |
| --- | ---: | ---: | ---: |
| Original, writing-only | 7/18 | 8/18 | 0/10 |
| Original, deterministic | 7/18 | **9/18** | **0/10** |
| Original, model-only | 6/18 | 6/18 | 0/10 |
| Original, combined | 9/18 | **11/18** | **0/10** |
| Synthetic challenge, writing-only | 14/32 | 14/32 | 0/40 |
| Synthetic challenge, deterministic | 14/32 | **16/32** | **0/40** |
| Synthetic challenge, model-only | 12/32 | 12/32 | 0/40 |
| Synthetic challenge, combined | 20/32 | **22/32** | **0/40** |

Exactly four case rows improve:

| Input | Fresh first-choice correction |
| --- | --- |
| `Die Kinder spielt im Garten.` | `Die Kinder spielen im Garten.` |
| `Er hat das Buch gelest.` | `Er hat das Buch gelesen.` |
| `Sie hat den Brief geschreibt.` | `Sie hat den Brief geschrieben.` |
| `Wir haben den Fehler gefindet.` | `Wir haben den Fehler gefunden.` |

These gains come from the incoming deterministic noun-agreement rule and reviewed irregular-participle priority. All **106 model-only outcomes remain unchanged**. No prior exact fix is lost, and all **50 supported clean controls** remain unflagged and unchanged. The model continues to add two exact corrections beyond deterministic checking on the original panel and six on the challenge panel; eight model findings are accepted and ten are suppressed by the editor's overlap policy.

Two audits reconstruct all **424 lane outcomes** from raw findings and UTF-16 edit positions. Source/build/run receipts agree on 66 selected Git inputs and two explicit workspace inputs. The broader build dependency closure was independently verified against the tested revision: 110 package libraries covering 4,766 Dart files, 10 SDK pins, the actual compiled artifact, native library, model and all 13 bundle files. The peer audit preserves one evidence qualification: compiler stdout is path-sanitized for display, while its raw stdout digest was computed before substitution. [Quality comparison](evidence/incremental-quality-comparison.json) · [Peer audit](evidence/quality-peer-audit.json)

The native executions ran concurrently with other qualification tasks. Their timing fields establish no new performance result. The previously qualified isolated measurement remains historical: 62.875 ms pooled short-check p95 and 359.6875 MiB peak process RSS at `6971819e`; its longer structural probes exceeded 500 ms. This continuation makes no speedup or target-device claim.

## Frozen morphology continuity

The existing core and review corpora were executed again on Dart VM and compiled JavaScript/Node. All 1,700 outcome records per runtime were compared, and VM/Node outcomes agree exactly.

| Measure | Previous qualified result | Fresh result |
| --- | ---: | ---: |
| Core exact errors | 70/81 | **71/81** |
| Original targeted subset | 68/73 | 68/73 |
| Broader challenge subset | 2/8 | **3/8** |
| Core clean controls flagged | 0/175 | **0/175** |
| Review exact errors | 24/24 | **24/24** |
| Review clean controls flagged | 0/60 | **0/60** |

Only three records change: `Die Studenten arbeitet heute.` improves to `Die Studenten arbeiten heute.` in its base, soft-hyphen and locale-alias variants. Its emoji-prefixed variant remains missed by the bounded sentence-start rule; its protected-code variant stays untouched. Operational, protected-text, ignore and correction-recheck failure counts remain zero. [Morphology comparison](evidence/morphology-comparison.json)

## Office integration repairs

### Column sections

Incoming #119 placed column attributes directly on `style:section-properties`. ODF 1.3 sections 17.11–17.12 place them on the nested `style:columns` element. The writer now emits that hierarchy, keeps an authored empty section's page anchor inside its column wrapper, uses the model's resolved column count, normalizes zero, and omits negative/nonfinite/unrepresentable gaps without changing the input model. Style caching uses the emitted normalized gap.

The final 14 semantic XML tests were run unchanged on the imported writer: 11 assertions failed and three controls passed. All 14 pass with the repair. The preserved tab-equivalence test now compares rounded positions with the same leader; distinct hyphen and underscore leader characters retain distinct output/styles. The accepted focused column/tab run passes 22 tests. Earlier environment and test-authoring attempts are retained and excluded from the accepted negative proof. [Regression comparison](evidence/office-regression-comparison.json) · [ODF 1.3 schema specification](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.pdf)

### Paragraph break styles and chart-data rotation

The closing main update emitted `columnBreakBefore` and `keepTogether` without including them in paragraph-style cache identity. Both now participate in that identity, preventing neighboring paragraphs from inheriting or losing settings. Explicit page breaks and section page breaks keep priority over column breaks.

Chart data introduced by the same update was converted into a table after the rotated-table decision. The writer now resolves an explicit or chart-derived table before that decision and passes it into the existing rotated-cell-frame exporter. Images and explicitly modeled tables retain precedence; the shape, table, chart points and transforms remain unchanged. This is a data-table/text-frame fallback, not native editable chart export.

The two new test files are identical before and after the repair: eight assertions fail and nine controls pass on `0e73c748`; all 17 pass after only the two writers are changed. The affected cohort at `7002d750` passed 174 tests on VM and 131 portable tests on Node, including all 31 new Office regressions (14 columns, eight paragraph styles and nine chart fallbacks). [Late regression comparison](evidence/late-office-regression-comparison.json) · [Final Office qualification](evidence/late-office-final-summary.json)

### Inline field caches and story isolation

The last main update recognized individual instruction fragments and used shared field suppression state. That could erase cached display text or later text after malformed fields. Conversion now requires a complete, balanced, unnested packet inside one paragraph, a supported `PAGE` or `NUMPAGES` instruction (optionally `MERGEFORMAT`), unlocked metadata, and one ordinary cached run. Instruction fragments are assembled before recognition. The cached text appears exactly once inside the native field while its style, hyperlink and attached-comment serialization remain in the existing path.

Unsupported instructions and formatting switches, locked or nested fields, malformed metadata, missing separators, atomic/multiple results and mixed inline content retain ordinary cached serialization. Metadata parsing handles malformed syntax and numeric entities safely. A cross-paragraph depth guard prevents nested conversion but never suppresses text; independent stories reset and restore it. DATE/TIME/TITLE field conversion remains outside this bounded support.

The final identical 22-case regression file gives 20 assertion failures, one missing-element exception and one passing control on the imported writer; the repaired writer passes all 22 plus all 16 existing writer tests. The earlier test-helper mistake around ODF space elements and its correction remain archived separately from this accepted pair. [Final field qualification and limitations](delivery-main/README.md) · [Field regression summary](evidence/delivery-field-summary.json)

## Optional AOT scope and portability repair

Captured AOT source adds a local-process client default, an explicit HTTP factory, bounded morphology caching/coalescing, host-selected worker/resources, CLI input handling and a decoder contract for exact source metadata. Documentation now reflects those behaviors. Studio remains explicitly endpoint-gated HTTP and creates/disposes clients per operation.

The captured native worker still returns the pinned upstream serializer without the source metadata consumed by the new decoder. Fixture tests establish the Dart consumer contract; they do not establish live normalized-token mapping or completion of the separate daemon-free native work. No AOT worker or dictionaries are bundled or installed by this continuation.

The first portable AOT run found one fixture problem: it used `0.0` as a supposedly nonintegral source offset, but JavaScript cannot preserve that distinction from `0`. The fixture now uses genuinely fractional `0.5`; product/decoder code is unchanged. The full VM suite passed 153 tests, the affected mapping VM suite passed 15 after the fixture repair, and the full portable Node cohort passed 129. The original 128-pass/one-failure Node attempt is preserved. [AOT reconciliation](evidence/aot-portability-reconciliation.json) · [Package documentation](../../../packages/quds_proofing_aot/README.md)

## Local validation

| Cohort | Accepted result | Source attribution |
| --- | ---: | --- |
| Full engine proofing, VM | **699 passed** | `8d640302` |
| Full engine proofing, Node | **699 passed** | `8d640302`, accepted quiet rerun |
| GECToR package including real native fixture | **194 passed, zero skipped** | `8d640302` |
| Flutter proofing/correction/hyphenation/platform/German integration | **178 passed** | `8d640302`, 13-file union in two runs |
| Studio AOT dialog | **12 passed** | `8d640302` |
| AOT package, VM | **153 passed** | `8d640302` |
| AOT mapping, VM after test-only repair | **15 passed** | Same product plus documented fixture correction |
| AOT portable package, Node | **129 passed** | Same product plus documented fixture correction |
| Broad Office VM / portable Node | **438 / 357 passed** | `8d640302` |
| Closing-main affected Office VM / Node | **174 / 131 passed** | `7002d750` |
| Delivery-main affected ODT VM / Node | **113 / 88 passed** | `898c4c07` |
| Delivery-main changed ODT writer/test analysis | **No issues** | `898c4c07` |
| Python qualification/admission controls | **116 passed, one skipped** | Source inputs remain unchanged |
| Full engine, AOT package/CLI, and changed Office strict analysis | **No issues** | Source-specific receipts |
| Native quality AOT build and both functional panels | **Passed** | `8d640302` |
| Morphology core/review, VM and Node | **Passed, identical outcomes** | `8d640302` |

Cohorts overlap and are not a count of unique tests. The Python skip is the development-only tiny converter control requiring optional ONNX/ONNX Runtime dependencies, both absent from the qualification interpreter.

The initial concurrent proofing Node run had 698 passes and one incomplete-report assertion in the first quotation test. Its recorded 10,125 ms interval is consistent with the service's 10,000 ms deadline, but the original assertion did not print the provider status, so deadline exhaustion under concurrent load remains an inference. With unchanged source, the quotation file passed all 18 tests alone, then the full Node suite passed all 699 at the original concurrency after other workloads finished. Both attempts and their identical input maps are preserved. [Failure resolution](evidence/proofing-node-failure-resolution.json)

## Evidence and reproducibility

[Verification](verification.json) records accepted gates and their exact receipt paths. [Source continuity](source-continuity.json) separates fresh execution from later unchanged-input attribution. The original [archive index](evidence-index.json) pins every member of the unchanged [evidence.tar.xz](evidence.tar.xz), including all command receipts, compressed stdout/stderr, source maps, failed attempts, raw model/corpus outputs, build receipts, audit scripts and summaries. Selected readable summaries are mirrored in `evidence/`; the complete archive restores all files under that prefix.

The bounded delivery-main field amendment is sealed separately in its [archive and member index](delivery-main/evidence-index.json). Its [verification](delivery-main/verification.json) and [source continuity](delivery-main/source-continuity.json) retain the earlier proofing source attribution and bind only the new focused checks to the final product revision.

The [logged runner](run_logged.py), preserved [workspace lock](resolved-pubspec.lock), per-run commands, model/native pins and build receipts document reproduction. The runner accepts `QUDS_RECOVERY_REPO` and `QUDS_RECOVERY_RUNTIME_ROOT` for a corresponding checkout and installed runtime. Native artifacts must be supplied separately at their recorded identities; no model weights or external native binaries are included. The [original-evidence audit](audit_recovered_evidence.py) independently checks the recovered historical archive.

Broader German accuracy, representative document distributions, intended-device latency, and completion of the separate native AOT mapping/Studio lifecycle work remain unqualified. GECToR remains an experimental manual de-DE option; deterministic regional support remains separate from the model's unsupported de-AT/de-CH availability results.
