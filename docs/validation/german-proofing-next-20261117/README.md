# German proofing continuation — 17 November 2026

This continuation adds a shared production report-merging policy and a real native evaluation of the optional model's **incremental benefit over the default German checker**. It also repairs three observed spelling false positives: a capital at the start of directly quoted speech, the courtyard noun `Hof`, and the Swiss greeting `Grüezi`. The initial measurements, the repairs they informed, and subsequent regression measurements remain separately identifiable.

This continuation is tracked in [follow-up PR #114](https://github.com/CrispStrobe/quds_office_suite/pull/114). The starting checkpoint was `f986fd031e4f984200c392e844ad83ae1ef5eb24`; during this work, [PR #105](https://github.com/CrispStrobe/quds_office_suite/pull/105) was merged externally with head `6f1abf273bd10d7ebe5641661dd307c492f897c2` at **16:44:28 CET (15:44:28 UTC)**. Its historical description and evidence remain associated with that completed PR. [Recorded PR observation](later-pr-observation.json)

The accepted product source is **`6971819edfb53ed40e97fc2b4cd436e89a39a648`** on `codex/german-morphology-20261117`. The captured integration checkpoint is `121f3be504a89e56bde40bda8f93f4e81d8c2503`; the accepted source also includes the subsequently observed main commit `7cf48a2f` for paragraph shading and borders and the reconciled empty-document test. All **244 refs** in the refreshed remote snapshot are ancestors of this checkpoint. Work was saved through incremental remote commits. No GitHub Actions workflow was dispatched or awaited, and CI status was not a validation gate. [Ancestry audit](refresh-integration.json)

## Measure the behavior the editor actually displays

The editor's deterministic-first overlap policy is now the pure-Dart [`mergeOfficeProofingReports`](../../../packages/quds_office_engine/lib/src/proofing/office_proofing.dart) helper. The editor and the new [live quality runner](../../../tools/proofing/german_model/run_incremental_quality.dart) use that same implementation. It preserves provider statuses and original offsets, rejects mixed request snapshots and duplicate provider ownership, and gives existing findings precedence over overlapping model suggestions, including insertions at either range boundary. It neither applies edits nor changes when checking runs.

The runner performs actual inference with the verified model, native library, persistent worker, dictionary guards and proofing service. It records four views of each request:

| View | What is measured |
| --- | --- |
| Writing only | The writing-rule result from the same deterministic request |
| Full deterministic | Default German spelling followed by German writing rules |
| Model only | The guarded native GECToR result |
| Combined | Both reports merged with the editor's production policy |

Receipts retain every status, displayed finding, replacement alternative, and accepted or suppressed model proposal. Requests use a nonzero original offset of **37**. A diagnostic corrected string follows a declared, single-pass policy: choose the first replacement, retain stable provider/result order, and record overlapping or replacement-free findings separately. No replacement is selected because it matches the expected answer. This is a reproducible scoring convention; it does not automatically edit a document or represent every possible user choice.

Exact expected corrections, clean text changed, and clean text flagged are separate measures. Failed or incomplete checks cannot count as successful corrections or clean checks. Unsupported model locales have their own cohorts and do not enlarge the supported-language denominator. Operational success also requires complete observations or explicitly expected unsupported results; empty reports cannot silently pass. [Measurement contract and commands](../../../tools/proofing/german_model/INCREMENTAL_QUALITY.md)

## Frozen inputs and initial versus repaired results

The original model panel remains **30 rows**: 18 de-DE errors, ten de-DE clean controls and two Swiss availability controls. The new panel contains **76 rows**: 32 de-DE errors paired with their corrected clean counterparts, eight additional de-DE clean controls, and four separate de-AT/de-CH controls. It was authored, independently reviewed and saved remotely at `60c550b4d02e4433d15c3f4fc2e67e744ed95dda` before any provider outputs for it were inspected. Its SHA-256 is `2fcdfd6aba46c854960588dc09cc2fd74af1fba08ffe86c4dc8d3a86a5eb4d42`. [Freeze receipt](prospective-freeze.json) · [Panel design and target policy](../../../tools/proofing/german_model/PROSPECTIVE_CASES.md)

The first execution at `7808a8711c91d721e8bb2b7034349008be80895b` is prospective with respect to those newly authored inputs. The panel is deliberately selected and synthetic, however; it is neither representative user writing nor evidence of exclusion from model training data. Once its outputs informed the spelling repairs, reruns became **development regression results**. Corpus bytes and expected answers were not changed to fit observed output.

The table below compares that initial execution with the repaired source at **`c9bf20a6f35e6c4607b9377716968f84c3bc67bb`**. Fresh default-decoder execution after the segmentation integration at `121f3be5` independently reproduces all **106 case rows and 424 substantive lane outcomes** from the repaired run. Only timing observations differ. The selected quality inputs remain unchanged in accepted source `6971819e`; the conservative resolved-library graph also contains the separately tested Office writer changes. [Integrated summary](integrated-quality/summary.json) · [Complete integration comparison](quality-comparison.json)

| de-DE panel and view | Initial exact errors | Repaired exact errors | Initial clean flags | Repaired clean flags |
| --- | ---: | ---: | ---: | ---: |
| Original: writing only | 7/18 | 7/18 | 0/10 | 0/10 |
| Original: deterministic | 7/18 | 7/18 | 1/10 | 0/10 |
| Original: model only | 6/18 | 6/18 | 0/10 | 0/10 |
| Original: combined | 9/18 | 9/18 | 1/10 | 0/10 |
| New panel: writing only | 14/32 | 14/32 | 0/40 | 0/40 |
| New panel: deterministic | 14/32 | 14/32 | 1/40 | 0/40 |
| New panel: model only | 12/32 | 12/32 | 0/40 | 0/40 |
| New panel: combined | 19/32 | **20/32** | 1/40 | **0/40** |

Clean-change counts equal clean-flag counts in these particular runs; both remain independently recorded. All supported de-DE observations completed, and both runs passed their operational and source-stability checks. The original panel's Swiss spelling false flag also fell from one of two controls to zero; the model correctly remained unsupported for both. The four new regional controls had no deterministic flags and explicitly unsupported model results. [Initial summary](baseline/summary.json) · [Repaired summary](after-spelling/summary.json) · [Complete spelling comparison](spelling-quality-comparison.json)

At the repaired checkpoint, the combined configuration adds **two exact corrections** over deterministic checking on the original panel and **six** on the new panel, losing none of the deterministic exact corrections. The added cases concern second-person plural verb forms and conjunction/relative-pronoun distinctions: for example, `Ihr hat` → `Ihr habt`, `Ihr liest` → `Ihr lest`, and `Das Buch, dass ich lese` → `Das Buch, das ich lese`. Model-only checking changes no supported clean controls in either panel. These are bounded observations, not a population precision estimate.

The new panel's combined increase from 19 to 20 does not reflect a newly learned model correction. The model already repaired the relative pronoun in `Das Fahrrad, dass im Hof steht, gehört mir.` An unrelated spelling suggestion changed valid `Hof` to `Hofe`, preventing an exact combined result. Removing that unnecessary suggestion allows the existing model repair to stand. The receipts distinguish eight accepted and ten overlap-suppressed model findings across the two repaired de-DE panels.

## Bounded spelling repairs

| Observed valid input | Earlier diagnostic suggestion | Repair |
| --- | --- | --- |
| `Er sagte: „Das stimmt.“` | `Das` → `das` | Recognize the first token after colon plus an opening quotation mark |
| `Das Fahrrad, das im Hof steht, gehört mir.` | `Hof` → `Hofe` | Include the noun and its reviewed finite forms in the existing supplement |
| `Grüezi, ich heisse André.` | `Grüezi` → `Grütze` | Include the greeting's reviewed case forms |

`Hofe` is a valid dative alternative; the defect was flagging an already valid word unnecessarily. The quotation rule recognizes a narrow direct-speech prefix with horizontal whitespace and German, Swiss or ASCII opening quotation marks. It does not exempt later words in the quotation or arbitrary internal capitals. Existing sentence-boundary behavior, lowercase noun detection, spelling checks and contextual cache separation remain exercised.

The exact quotation regression was recorded failing before the source change. Final focused coverage contains **18 quotation tests and six lexical-gap tests**, including original offsets, soft hyphens, decomposed accents, known inflections, neighboring misspellings and Swiss sharp-s policy. An earlier test review removed assertions that would have treated potentially valid unsupported direct-speech prefixes as errors; those superseded logs do not define the final expected behavior. [Quotation regressions](../../../packages/quds_office_engine/test/proofing/german_spelling_quotes_test.dart) · [Lexical regressions](../../../packages/quds_office_engine/test/proofing/german_lexical_gap_test.dart)

The lexical generator was rerun against the same pinned MIT word list, SHA-256 `55b457fac8e322146853f45bbda59046a55496a3e3deb32d3a88feb908eca243`. Its check mode passed before and after regeneration. Decoding both generated supplements confirms exactly three added forms—`Hof`, `Grüezi`, and `grüezi`—and no removals. Standard forms increase from 444,130 to 444,133; the 9,451 Swiss additions and every upstream shard are unchanged. [Generator audit](lexicon-generation.json)

## Incoming histories and Office preservation

The first inventory captured 235 refs, all integrated at `17f1483a02c1d9819ff4a1b3dcf2dbc512cdfb57`. A later snapshot at **16:47:52 CET (15:47:52 UTC)** captured 244 refs, including newer main, Office fidelity/continuation, provider, metadata, ODP hyperlink and page-field histories. Their feature, vendor and PR ancestry is preserved at `121f3be5`. This is a statement about the captured snapshot, not future remote changes. [First inventory](incoming-refs.json) · [Refresh inventory](refresh-refs.json)

Source comparison at `121f3be5` confirms that the combined ODT writer equals captured main `9941c80d` plus the incoming empty-document guard. That guard preserves default master/page styles without adding a synthetic body paragraph when the authored document has zero sections. Authored empty sections retain their boundary handling. The ODP writer, both writer test files, ODF decoder, extractor and text-box regressions exactly match main; the initially integrated continuation regression file exactly matches `a499549e`. The final bounded main update adds six writer lines for paragraph shading/borders and its writer regression; no proofing or model source changes in that update.

Consequently the merge retains metadata, hyperlinks/bookmarks, page-number fields, section/page parity, list-story counters, physical RTL indents, comments/notes and the newer frame extraction implementation. The provider branch's older frame decoder did not replace the namespace-aware implementation that emits anchored text-box paragraphs once and respects output limits. Exact comparisons are retained with the [evidence inventory](evidence-index.json).

The first integrated Office run exposed one contradictory inherited test expectation: **378 passed and one failed on VM; 305 passed and one failed on Node**. The continuation test expected a synthetic `SB0` paragraph for an explicitly zero-section document; the preserved writer and two other tests require an empty body with default styles. The accepted source changes only that stale assertion, retaining all default master/layout geometry and model-immutability checks. Authored empty sections still require their actual boundary anchors. The fresh accepted runs pass **380 VM tests and 307 Node tests**, including the arriving shading regression. Both failed attempts remain in the evidence.

## Real native segmentation qualification

Incoming provider history adds bounded, opt-in segmentation and decoder/guard changes. A fresh compiled provider at accepted source `6971819e`, using `--segment-target-tokens 64`, passes all eight original operational controls and six additional segmented controls. The latter verify a late correction at original UTF-16 span **2543–2547**, request offset **137** and an initial emoji; protected code; and whole-request rejection at native-sequence, total-token, segment-count and source-length limits. Capacity failures publish no partial suggestions. Five compiled CLI controls reject invalid, out-of-range, duplicate or unknown options before model loading.

The frozen guarded result remains **6/18 exact corrections, 0/10 supported clean controls changed and two Swiss cases explicitly unsupported**. Its strict historical comparison preserves all five earlier fixes and adds the already integrated `verb-wir` alias correction. This is separate from the combined editor evaluation above.

The run used two native threads, one warmup and three measured repetitions per input. Other local test, analysis and hashing jobs had completed before timing. The 87-sample pooled short cohort and peak memory meet the provisional host budgets:

| Measurement | Fresh accepted run |
| --- | ---: |
| Model verification, dictionary and worker startup | 3.223 s |
| Pooled warm median through 64 logical WordPieces | 22.886 ms |
| Pooled warm p95 through 64 logical WordPieces | 62.875 ms |
| Peak whole-process RSS | 359.6875 MiB |
| Pinned mixed Q4_K model | 82,756,896 bytes |

| Structural probe: logical tokens | Segments | Actual initial model tokens | Warm p95 |
| ---: | ---: | ---: | ---: |
| 61 | 1 | 61 | 167.485 ms |
| 126 | 3 | 128 | 395.586 ms |
| 256 | 5 | 260 | 840.740 ms |
| 636 | 11 | 646 | 1,705.884 ms |
| 1,276 | 22 | 1,297 | 3,732.003 ms |

The complete original source is partitioned and covered in every long probe. Actual model-token totals include each segment's terminal handling and CLS/SEP tokens, so they differ from logical original-text counts. The 636- and 1,276-token probes establish bounded operation beyond a single native sequence; they do not establish a speedup. The 256-token and larger probes still exceed 500 ms. Repeated grammatical sentences are structural controls, not representative long-document language evaluation or target-device qualification.

The independent audit reconstructs 84 retained results, 15 edits, 94 source segments and 105 timing samples. The producer records output stability over all repeats; only the warmup and first measured output are retained per measured input, so the independent audit does not claim access to omitted repeat outputs. Source, dependency, SDK, model, native library, executable and reference identities are stable before and after execution. The first AOT attempt's absent temporary directory and subsequent successful builds are retained separately. [Complete native report](provider-segmented.json.gz) · [Independent audit](provider-audit.json) · [Build](provider-build.json.gz) · [Run closure](provider-run.json.gz)

## Local validation and source qualification

| Check | Qualified result | Tested source |
| --- | ---: | --- |
| Engine proofing, Dart VM | **602 passed** | `c9bf20a6` |
| Engine proofing, JavaScript/Node | **602 passed** | `c9bf20a6` |
| Focused Flutter proofing, correction and hyphenation | **176 passed** | `c9bf20a6` |
| GECToR package, real native fixture included | **194 passed, zero skipped** | `121f3be5` |
| Office export, extraction and preservation, VM | **380 passed** | `6971819e` |
| Portable Office cohort plus shading regression, Node | **307 passed** | `6971819e` |
| Python qualification controls | **107 passed, one explicit skip** | `6971819e` |
| Full engine, editor, GECToR, runner and affected Office strict analysis | **No issues** | Recorded source-specific receipts |
| Native segmented provider AOT build and execution | **Passed** | `6971819e` |

These counts retain their original execution sources. The accepted Office seal binds **755 source inputs and 5,020 runtime inputs** with no mismatch. Explicit continuity audits find **222 unchanged proofing/editor core paths**, **98 unchanged model-related inputs**, and **70 unchanged named quality inputs**. Four incoming Office implementation paths differ in the broad earlier engine maps; the final Office checks above cover those changes. The wider GECToR map differs only in the ODT writer. Historical executions are not relabeled as fresh runs at the accepted commit. The Python skip requires absent optional development-only converter dependencies. [Core continuity](proofing-continuity.json) · [Model/quality continuity](model-continuity.json)

The shared merge helper has 20 new contract tests; scoring/schema/projection has 19 tests; AOT target selection has 13 Python controls. Groups overlap and must not be added together. The runner records atomic per-case checkpoints, refuses output overwrite, and preserves failure receipts. Build receipts bind selected source, dependency and SDK inputs to the compiled artifact; runtime receipts additionally bind the declared corpus and compare source hashes before and after execution. [Verification](verification.json) · [Source binding](source-binding.json)

The existing deterministic morphology harness was rerun on `c9bf` using Dart VM and Node, with all five variants of the unchanged core and review corpora. **All 1,700 outcome records per runtime are byte-identical to retained `f986fd03` results**: 70/81 core errors corrected, 0/175 core controls flagged, 24/24 review errors corrected and 0/60 review controls flagged. Operational, protection, ignored-rule and recheck failures remain zero. This harness exercises the writing provider; the spelling and live combined checks above establish the separate lexical effects.

## Reproduction, retained evidence and remaining limits

Use the [compiled quality commands](../../../tools/proofing/german_model/INCREMENTAL_QUALITY.md#reproduce-a-compiled-comparison), selecting `build_gector_aot.py --target incremental-quality`, then running both declared corpus paths with fresh output names. The [native pack guide](../../../tools/proofing/german_model/NATIVE_PACK.md) specifies asset verification; this runner downloads nothing. It executes one check per case. Its recorded elapsed times and memory observations are not a new latency budget or target-device qualification.

For the unchanged morphology panels, run the existing [qualification harness](../../../tools/proofing/run_morphology_qualification.py) from the repository root:

```sh
python3 tools/proofing/run_morphology_qualification.py \
  --target /path/to/quds_office_suite --dart /path/to/dart-sdk/bin/dart \
  --output /path/to/fresh-results/core
python3 tools/proofing/run_morphology_qualification.py \
  --target /path/to/quds_office_suite --dart /path/to/dart-sdk/bin/dart \
  --corpus tools/proofing/german_morphology_review_cases.json \
  --output /path/to/fresh-results/review
```

The [evidence archive](evidence.tar.xz), [member hashes](evidence-index.json), build/run receipts and comparison files preserve exact command output, failed validation attempts and runtime identities. Member payloads are byte-exact, including original infrastructure paths; adjust command paths when reproducing elsewhere. SDKs, caches, model/native binaries and AOT executables are excluded, with their identities retained in the receipts. The archive verifies every member without extraction. The [previous continuation report](../german-proofing-continuation-20261117/README.md) and its original model/performance results remain historical evidence for their recorded inputs.

Contextual quality remains unfinished. On `c9bf`, first spelling suggestions include `gelest` → `genest`, `geschreibt` → `beschreibt` and `gefindet` → `befindet`; the noun-phrase case `Sie hat ein roten Mantel` still receives an unsuitable adjective-first change. The two new word-order errors remain unchanged. These examples warrant contextual analysis and fresh, independently selected evaluation, not changing this panel's expected answers.

The optional model remains explicitly installed and manually enabled for **de-DE**. This work does not enable default/background model checking or promote de-AT/de-CH model support. Broader corpus selection and annotation, clean-text error rates in realistic writing, longer-document behavior, intended-device performance, packaging, and the strict native-distribution license boundary remain separate qualification work.
