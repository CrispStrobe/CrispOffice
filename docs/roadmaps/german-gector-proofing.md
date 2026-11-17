# German grammar proofing: scoped implementation roadmap

Status: optional de-DE manual provider, native F32/mixed Q4_K qualification, bounded complete-check AOT measurement and synthetic combined-quality evaluation implemented; broader quality, device and distribution gates remain open.
Date: 2026-11-17.
Coordinated branch: `feat/german-gector-proofing`.
Integrated continuation: `codex/german-morphology-20261117`, PR #114 after the externally merged PR #105.

## Outcome and scope

Add an optional, offline German GECToR provider to Quds using its existing
OfficeProofingProvider/session/review/correction APIs. Keep the correction
pipeline in Dart and make inference replaceable. First determine whether
onnx_runtime_dart is fast and memory-efficient enough, including bounded
optimizations justified by measurements. If it is not, use CrispEmbed/ggml or
native ONNX through the Rust stack. Prefer Q4_K when the selected backend
actually supports it. Floating-point inference is a correctness reference,
not an approved shipping precision.

This increment covers reproducible runtime/quantization qualification and the
first optional provider. It does not authorize a release, main-branch merge,
model publication, default background checking, or changes to unrelated models.
Large model and raw-logit artifacts stay outside Git; commit small manifests,
source pins, reports and reproducible commands.

## Source baseline

| Repository | Base commit | Responsibility |
| --- | --- | --- |
| quds_office_suite | b0d6c58b45a7e2cf4d161270b0e8223f05e0d470 | Canonical roadmap, frozen model/oracle, optional provider, editor integration |
| onnx_runtime_dart | 7bdf47d815a6516da69d29c671240d10e68723ff | Pretokenized alignment, exact-input runtime benchmark, measured runtime improvements |
| CrispEmbed | b34a132c6c204b71f5c58ba8bc1705b8769edb9b | Conditional GGUF conversion and dual-head Q4_K backend |
| fastembed-rs | d1500cdf248fc5447fb723f38e7cf3ee21b30487 | Conditional prepared-input native ONNX backend; base is probe/ort-rc12 |

Model baseline: proofbird/gector-bert-de v2.1.0, revision
`8e3b50beef7d775cedb7b876009e88bcf2e8d6af`.
Reuse tools/proofing/german_model/artifacts.json unchanged.
The original model is 452,972,247 bytes with SHA-256
`6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464`.
Preserve the Apache-2.0 LICENSE/NOTICE and original vendored quickstart.

The existing evaluation records 9/18 exact expected error corrections and
1/12 changed clean controls, including the de-CH heisse -> heiße regression.
That is a small synthetic baseline with upstream guards omitted, not application
quality qualification. Evaluate a newer model release as a separate experiment.

## Quantization policy

- Q4_K means the ggml/GGUF K-quant format, not generic ONNX INT4.
- onnx_runtime_dart currently consumes ONNX MatMulNBits packed 4-bit tensors;
  it does not load GGUF. This branch replaces full-matrix reconstruction with
  bounded 32-column Float32List tiles and optional direct GEMM, but still
  reconstructs weights on every call. Measure execution and peak RAM rather
  than treating a smaller artifact as a speed improvement.
- Start the ONNX candidate with a declared weight-only MatMulNBits recipe and
  record block size, symmetry, operator inventory, excluded tensors, converter
  version, source/model SHA and resulting artifact SHA. Preserve both heads.
- The selected ggml lane first preserves F32 tensors and both output heads for
  conversion/runtime parity. Its proposed mixed candidate uses Q4_K encoder
  matrices, Q8_0 token embeddings and F16 positions/heads. Qualify that precision
  reduction separately; record the complete tensor manifest and retain higher
  precision wherever decoded quality requires it.
- Keep F32 and, where relevant, F16 controls. A Q4 candidate must preserve
  useful corrections and avoid additional false edits on clean controls.
  Logit cosine or file-size savings alone do not qualify it.
- Do not label ONNX MatMulNBits as Q4_K, silently ship F32, or overwrite frozen
  reference outputs with candidate outputs.

## Current implemented state

The [optional provider](../../packages/quds_proofing_gector/README.md) now owns
verified bundle admission, tokenizer/alignment, iterative decoding, conservative
German guards, UTF-16 source edits, a persistent bounded worker and explicit
failure reporting. The native adapter uses the separately qualified default-off
CrispEmbed prepared-input target. Manual/F7 registration is available through
`configureManual`; typing checks continue to use the ordinary service.

The [native qualification](../validation/german-gector/2026-11-17-native/README.md)
retains exact F32 and mixed Q4_K agreement for all 30 cases / 40 saved passes,
including the 64/128/256-token probes. The candidate GGUF is 82,756,896 bytes.
The [guarded provider evidence](../validation/german-gector/2026-11-17-native-dart/README.md)
retains both development-mode and compiled measurements. The compiled v1 run
passes the local <=64-token latency and process-memory budgets at 62.017 ms p95
and 309,854,208 bytes peak RSS. The JIT memory-budget failure is retained.

The guarded v1 policy preserved five expected fixes. The
[compiled continuation](../validation/german-gector/2026-11-17-continuation/README.md)
recovers `Wir ist` through authenticated same-number verb-person aliases,
raising the result to six expected fixes with no lost fixes or changed supported
clean controls. The other three of the nine unguarded fixes remain held. Both
Swiss controls are explicitly unsupported. This small synthetic panel does not
establish general German accuracy. de-AT/de-CH, representative held-out quality,
representative benefit beyond deterministic rules, intended-device responsiveness and the
exact distribution/license closure remain open. Inputs beyond the model's
512-token context fail explicitly in the original single-sequence mode.
The [long-input continuation](../validation/german-gector/2026-11-17-long-input/README.md)
adds opt-in bounded sentence segmentation for the manual provider, preserving
whole-request failure reporting and original UTF-16 offsets. Its conservative
boundary policy, native measurements and remaining quality limits are recorded
separately from the frozen single-sequence results.

The continuation also supplies a source/dependency/SDK-bound AOT builder and an
[offline local development pack](../../tools/proofing/german_model/NATIVE_PACK.md).
The verified pack has 23 files totaling 86,356,331 bytes, including its manifest.
The final v3 compiled run through it binds the integrated source at `a15d173`
and passes all 30 operational cases, eight controls and guarded nonregression,
at 66.072 ms short-input p95 and 360,497,152 bytes peak process RSS. Its case
outputs match v2 exactly; v1 and v2 measurements remain retained. These are
separate local observations and do not establish a speed change or
intended-device qualification. The 256-token structural probe takes 816.225 ms
at p95; the 500 ms budget applies to the short-input cohort.

That integration retains all 128 Quds branch tips captured at
2026-11-17 14:54:15 UTC. It includes explicit genitive corrections, bounded
worker request coalescing, locale-aware manual coverage and the newer ODT
section/nested-list/bookmark work. The continuation evidence records 103
GECToR, 268 deterministic German grammar, 97 editor proofing, 148 ODT and 45
tooling checks. Later incoming branch activity is listed separately from this
fixed validation snapshot.

The later [bounded-input and prospective-quality continuation](../validation/german-gector/2026-11-17-long-input/README.md)
binds implementation `d092d50a` and preserves all 130 branch tips captured at
15:32:37 UTC plus all 108 fetched PR heads. It includes the newer section/list
work, merged ODP hyperlinks and a regression repair for frame text extraction.
The final local evidence covers 924 distinct tests and three strict analysis
suites, with the real native fixture enabled and no skipped tests.

The opt-in target64 segmented provider retains all six model fixes and ten
supported clean controls. It covers complete 636/1,276-token probes with p95
2,179.809/3,804.643 ms and peak RSS 294.55 MiB. Its 256-token p95 is 724.617 ms
versus 607.917 ms single-sequence in the paired run; coverage has expanded, but
these results do not show a speedup or 500 ms long-text compliance.

A separate, prospectively frozen 76-row synthetic challenge uses the production
merge policy. On its 32 de-DE errors, writing/deterministic/model/combined exact
fixes are 14/14/12/19; the model adds five combined exact fixes without losing a
deterministic fix or adding changed/flagged cases among 40 clean de-DE rows.
One pre-existing spelling suggestion remains on a clean row. The original panel
records 7/18 deterministic and 9/18 combined, versus 6/18 model-only. The
first-replacement projection and corpus limitations are explicit; representative
incremental benefit and long-paragraph quality remain unqualified. First outputs
are preserved before follow-up changes to any rules or corpus.

The owner requested incremental remote checkpoints and local validation because
GitHub Actions capacity is starved. No new hosted job or Actions completion is
a prerequisite for this continuation. Preserve all receipts and source pins.

### Combined deterministic and model evaluation

The [next continuation](../validation/german-proofing-next-20261117/README.md)
extracts the editor's existing deterministic-first conflict policy into the
shared `mergeOfficeProofingReports` helper and measures actual native inference
through that same policy. A newly authored 76-row synthetic panel was saved
remotely before inference, separately from the unchanged original 30-row panel.
The runner retains writing-only, deterministic, model-only and combined reports,
all provider statuses, original UTF-16 offsets and accepted/suppressed findings.

On the repaired development panels, the combined configuration gives **9/18**
exact de-DE corrections versus **7/18** deterministic, and **20/32** versus
**14/32** on the new panel. It loses no deterministic exact corrections and
changes/flags none of the **10 + 40** supported clean controls. Fresh native
execution after the segmentation integration reproduces all 424 lane outcomes.
The model alone gives 6/18 and 12/32; unsupported regional cases remain separate.

Initial observations informed bounded spelling repairs for quotation capitals,
`Hof` and `Grüezi`. Only three finite forms were added to the existing supplement;
all upstream dictionary shards remain unchanged. Therefore subsequent runs are
development regressions, not new prospective evidence. Exact first-replacement
projection is a measurement convention, not automatic application. Contextual
participle and accusative misses remain visible in the raw reports. Broader
language quality, intended devices and exact native distribution still need
qualification. Earlier performance and quality receipts retain their own source
and runtime identities.

The accepted compiled provider at `6971819e` also qualifies opt-in segmentation
with a 64-token target: eight original and six additional operational controls
pass, including original UTF-16 offsets and whole-request capacity failure.
Repeated-sentence probes of 636 and 1,276 logical tokens complete in 11 and 22
segments. Their p95 times are 1.706 and 3.732 seconds; this establishes bounded
long-input operation, not a speedup or representative long-text quality.
The separate 87-sample short pool reaches 62.875 ms p95 with 359.6875 MiB peak
process memory on this Linux host. Host installation and segmentation remain
explicit options; the distribution and intended-device gates stay open.

## Milestones

### M0: recoverable scope

- [x] Record repository/model baselines, ownership, quantization distinction,
  decision gates and implementation order in feature-branch roadmaps.
- [x] Read back the pushed roadmaps before starting implementation commits.

### M1: exact-input qualification, first implementation

- [x] Add a bounded Python exporter alongside the existing Quds evaluation.
  Verify the existing manifest, execute the unmodified reference decoding loop,
  and capture exact input IDs/masks, word alignment, both output tensors,
  chosen tags/confidences and final corrected text with source hashes.
- [x] Add a Dart AOT benchmark consuming the captured inputs and both named
  outputs. Fail on missing outputs, unsupported operators, incorrect shape,
  non-finite values or unacceptable numerical/decision differences.
- [x] Add a reusable pretokenized WordPiece API with source-word alignment and
  tests for cased German, punctuation, special tokens and truncation.
- [x] Execute the same-host native ORT control and Dart candidate, with declared
  thread budgets, graph/session load (filesystem caches may already be warm),
  cold first inference, warm median/p95, iteration counts, sequence-length
  coverage and peak RSS. Separate inference time from complete correction
  latency and from model download/verification.
- [x] Preserve exact workflow/job/source/SDK/model/converter identities and all
  failures. CI timings qualify only that host, not mobile/browser hardware.

### M2: bounded optimization and backend decision

- [x] Compare the original ONNX model with the declared ONNX INT4 candidate.
  Report exact artifact size, quantized operator inventory and unsupported paths.
- [x] Profile the limiting work before changing runtime code. Candidate changes
  include initializer lifetime, last-use intermediate reclamation, packed-weight
  execution or bounded reuse, and worker/thread allocation. Change one cause
  at a time, retain a reproducible baseline, and measure decoded parity.
- [x] Limit the initial Dart optimization round to two measured hypotheses.
  If resource or latency targets remain unsuitable, open the native lane rather
  than growing an unbounded runtime project.
- [x] Select the next backend implementation/qualification lane from recorded
  evidence. A shipping backend still requires the downstream gates below.

Provisional desktop engineering targets for the eventual complete checker:
warm p95 <=500 ms for sentences up to 64 wordpieces, peak process RSS <=768 MiB,
and preferred downloadable model pack <=160 MiB. Report pass/fail against these
budgets without treating a hosted-runner pass as target-device qualification.
Longer 128/256-token inputs are measured separately and must not be silently
truncated. Record full iterative correction latency; per-forward timing alone
cannot satisfy the complete-check target. Refine target-device budgets openly
before mobile/browser rollout, not after viewing results to make a run pass.

### M3: optional Quds provider

- [x] Add packages/quds_proofing_gector with a backend-neutral decoder, verified
  model-bundle loading and a persistent worker. Reuse Harper transport patterns.
- [x] Port word preparation, first-subword mapping, label/verb transformations,
  bounded iterative edits and original-text UTF-16 mapping. Implement the
  documented conservative Quds guard policy; do not claim parity with
  unpublished Proofbird built-ins.
- [x] Expose tested de-DE support first. Explicitly return unsupported for
  de-AT/de-CH; their locale policy and quality qualification remain future work.
- [ ] Qualify de-AT/de-CH policies before advertising those locales.
- [x] Construct results around the original request object; forRequest receives
  request-relative offsets and adds startOffset exactly once.
- [x] Reuse protected ranges, personal-vocabulary and duplicate/conflict
  handling. Expose the existing German spelling vocabulary through a read-only
  query required by the guards.
- [x] Load outside the service request deadline; bound the queue, cancel obsolete
  work between passes, invalidate caches on configuration changes and report
  missing/failed/partial work honestly.
- [x] Introduce the model through optional manual/F7 checking. Existing service
  Future.wait and end-of-scan publication require a separate scheduling change
  before responsive background model checks.
- [x] Add opt-in bounded sentence grouping with preflight capacity limits,
  original UTF-16 offsets, whole-request failure and cancellation checks.
- [x] Measure model additions through the production deterministic/manual merge
  on a separately frozen synthetic challenge; preserve full first outputs.
- [x] Apply suggestions through the existing guarded editor command, including
  rich text, undo, tracked changes, protection and stale-result controls.
- [x] Measure added model corrections under the actual deterministic-first
  editor policy on fixed synthetic panels, retaining clean-text and coverage
  controls. Representative incremental precision/recall remains open.

### M4: selected native lane and fallback

- [x] Implement and authenticate the exact fine-tuned converter and both heads.
- [x] Qualify the small prepared-ID native target against saved F32 references.
- [x] Qualify the declared mixed Q4_K recipe on frozen decoded outputs and
  required longer inputs; retain strict numeric failures separately.
- [x] Measure the complete guarded Dart worker/provider/service in JIT and AOT.
- [x] Execute bounded opt-in segmentation through the real compiled native
  worker, including complete long-input coverage and atomic capacity failures.
- [ ] Qualify intended desktop devices and broader held-out German quality.
- [ ] Complete exact platform/distribution and model-pack acceptance.

CrispEmbed/ggml is implemented as a small CPU target with controlled
BERT/GGUF/ggml dependencies. It converts the exact fine-tuned encoder and both
GECToR heads and exposes a default-off prepared-ID interface for one unpadded
sequence with an all-ones mask. Both heads use ggml matrix operations. The
retained F32 control and mixed Q4_K candidate preserve frozen-panel decoded
decisions; numerical limits and failed diagnostics remain recorded separately.
Follow CrispEmbed PLAN ownership and its feature-specific local CPU permission.
See [native qualification](../validation/german-gector/2026-11-17-native/README.md)
for exact source, artifact, build, performance and license identities.

Rust/native ONNX: use a dedicated prepared-input grammar/session abstraction
with preserved word alignment, bounded thread counts and exact output selection.
The pooled embed() API is unsuitable; raw transform outputs are available but
the current public string path discards alignment. Use the original ONNX model
or a separately qualified ONNX quantized artifact; this is not a Q4_K backend.

Native ORT is a performance control and a conditional engineering fallback,
not an approved shipping dependency. The measured ORT 1.23.2 distribution's
[third-party notices](https://github.com/microsoft/onnxruntime/blob/a83fc4d58cb48eb68890dd689f94f28288cf2278/ThirdPartyNotices.txt)
include Eigen under MPL-2.0 despite ORT's MIT top-level license. Under the
strict permissive-license requirement, qualify the exact runtime binary and
its dependency closure before considering distribution; do not infer approval
from the Rust wrapper's or runtime's top-level license. The fork's API-24
runtime would require a separate version-specific audit. The selected ggml
target also needs its compiled-source, linked-library and packaged-asset
license inventory. No native ORT application dependency is added here.

## Acceptance and evidence

1. Reproducible source/model/tokenizer/label/guard provenance and permissive
   licenses/notices for the complete shipped dependency and asset closure.
   GPL/LGPL/AGPL/MPL/NC components do not pass this feature's strict allowlist;
   a development oracle does not approve a runtime for shipping.
2. Exact input IDs, masks and word alignment before numerical comparisons.
3. Both heads present with correct shapes, finite values and recorded numeric
   errors; exact selected decisions and final corrections for the F32 port.
4. Quantized candidate: no loss of baseline fixes and no new changed clean
   controls on the frozen probe; larger held-out German validation remains
   necessary. Measure incremental benefit over existing deterministic rules.
5. UTF-16/grapheme/source preservation, stale-result rejection, explicit
   availability/coverage, unchanged undo and tracked-change semantics.
6. Real cold/warm/per-pass/end-to-end latency and peak-memory measurements with
   host identity, threads, SDK/compiler, precision and sequence lengths.
7. Optional features stay unavailable until their exact artifacts are verified;
   no successful empty report for inference failure or unprocessed text.

## Measured decision and current state

### Completed implementation

Roadmaps were pushed and read back before implementation in all four
repositories. The initial Quds scope commit is
`4cceff38040d423c4cfc08a0039b0379c6b35bbf`; the other initial roadmap commits
are retained in each repository's history.

Quds now has the authenticated reference exporter, explicit INT4 converter,
bounded stage runner, evidence-chain and correction nonregression checks, and
a pinned hosted workflow. The original evaluator, vendored runner, artifact
manifest, frozen cases and earlier recorded results remain intact.

The final measured Dart source is
`onnx_runtime_dart@b10258682d459847b63e012eaaba58a528e93956`. It adds aligned
pretokenized WordPiece input, the exact-input dual-head AOT benchmark, bounded
32-column INT4 reconstruction, corrected packed zero-point column alignment,
and opt-in reuse of the existing narrow direct GEMM strategy. The existing
`OnnxExperiment.narrowDirectGemm` default stays disabled. The benchmark
explicitly records its selection, and CI rejects a report/declaration mismatch.

Twenty-seven final focused Dart operator/configuration/reference checks pass,
as do analysis and AOT compilation. The original tokenizer/harness increment
passed its 22 targeted tests. Quds' final 19 lightweight Python controls pass,
including an actual tiny ONNX conversion and negative experiment-integrity
cases. The real checkpoint was additionally exercised in both completed
hosted runs described below.

### Final hosted result and backend decision

[Optimized run 44062093617](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44062093617)
used Quds source `69d153c0f81596af894e48e21880f0957b963994` and the final
Dart source above. Both model variants passed all 30 cases / 40 saved passes,
with exact token alignment, both heads, selected tags and experiment selection
checked. The INT4 candidate still has SHA-256
`6c92deb88469e2fce2ddded5159014200d8681a7853722714224539a48285d70` and
size 158,365,857 bytes (151.03 MiB).

On that run's Intel CPU, comparing the same INT4 bytes within one job:

| Measurement | Optimized Dart INT4 | Native ONNX INT4 control |
| --- | ---: | ---: |
| First-forward median | 463.426 ms | 15.772 ms |
| First-forward p95 | 545.531 ms | 17.060 ms |
| Inference/reference process peak RSS | 487,698,432 bytes | 358,817,792 bytes |
| Complete unguarded reference correction p95 | Not implemented/measured | 33.220 ms |

These pooled figures cover only 5..12 wordpieces, one warmup and three samples
per case. They are not target-device qualification or the full Quds pipeline.
The original hosted baseline used an AMD/Azure VM; the optimized job used an
Intel/AWS VM. Cross-run timing differences cannot be attributed solely to code.
The separate local record retains all noisy before/after observations and the
uncommitted prototype without substituting its best timing for the final run.

The optimized Dart forward alone still exceeds the provisional 500 ms
complete-check p95 budget on short inputs. The initial two runtime hypotheses
are complete, so stop this initial kernel tuning round. Select CrispEmbed/ggml
with the declared mixed Q4_K recipe as the next implementation/qualification
lane, retaining native ONNX through Rust as the fallback if Q4_K fails its
quality, performance or packaging gates and the native ONNX license boundary
can be satisfied. This selects the next engineering step, not an already
qualified shipping backend.

### Original reference quality

Both models retain 9/18 exact expected error corrections and 1/12 changed
clean controls on the frozen synthetic panel, including the incorrect de-CH
heisse -> heiße edit. Quantization introduced no changed inputs, selected tags,
final text or suggestion spans on this panel. These counts do not estimate
general German accuracy. Broader held-out evaluation and incremental value
over existing deterministic rules remain required.

### Earlier morphology-branch native and application continuation

This historical checkpoint precedes the v2/v3 continuation described above.
Its separate measurements and evidence remain retained.

The Quds feature checkpoint `216d9a4ba11d87d27f861d84d26bf74ca1d4f298`
adds the optional application provider after the native conversion and
qualification commits. It is integrated with the morphology and ODT fixes in
PR #105. The [provider README](../../packages/quds_proofing_gector/README.md)
defines bundle/hash admission, all-ones prepared input, both output heads,
conservative guards, source mapping, cancellation and availability contracts.
No model or native binary is shipped by the Dart package.

CrispEmbed's measured implementation is
`853a1ce6089e5d5486e37307f37051ad6a928745`, with pinned ggml
`3a27b6c665b191cb230be367db5c52d81dd3e2ac`. The mixed artifact is
82,756,896 bytes. Its frozen-panel decoded behavior matches the F32 control,
but its separate 0.002 absolute-error diagnostic does not pass. The native
dependency report also retains the GNU/Linux system/runtime license boundary;
top-level MIT/Apache notices alone do not approve distribution.

The first [complete guarded Dart run](../validation/german-gector/2026-11-17-native-dart/README.md)
fixes 5/18 error cases, preserves all ten supported clean controls and rejects
the two Swiss controls as unsupported. The guards hold four reference fixes
whose subject/person evidence is insufficient. The authenticated raw-logit
replay independently matches all 30 original cases and 40 passes. These are
different checks: unguarded replay parity is not guarded product quality.

The retained JIT run has a 93.618 ms warm p95 up to 64 WordPieces and an
819,101,696-byte process peak, exceeding the 768 MiB memory budget. The morphology continuation
compiled-provider run has a 58.877 ms pooled warm p95 through 64 WordPieces and
a 404,336,640-byte (385.61 MiB) process peak, passing those provisional budgets
on its Linux host. Its 256-token structural probe has an 803.379 ms p95. Keep
the complete sample distribution, host identity and earlier JIT observation;
these separate runs are not a controlled attribution to one code change. The current
[continuation report](../validation/german-proofing-continuation-20261117/README.md)
records the combined-source validation and follow-up fixes without overwriting
earlier evidence.

Remaining work includes broader held-out precision/recall and incremental
benefit over deterministic checks, intended-device measurements, approved
native packaging and locale policy. Web model inference, automatic background
model checking and default promotion remain unimplemented. The Rust roadmap
retains the API-24/native-runtime version check and outstanding fallback
packaging work. None of these results authorizes a release or main merge.

The later compiled GECToR continuation in the Current implemented state
section above preserves these earlier receipts and advances the guarded result
to 6/18; the two reports describe distinct, explicitly pinned source states.

### Durable evidence

- [Original local two-case baseline](../validation/german-gector/2026-11-17-local-smoke/README.md).
- [Original full hosted baseline](../validation/german-gector/2026-11-17-hosted-baseline/README.md), run 44053903485.
- [All local optimization observations](../validation/german-gector/2026-11-17-local-optimization/README.md), including the slower final opt-in repeat.
- [Final full hosted optimized result](../validation/german-gector/2026-11-17-hosted-optimized/README.md), run 44062093617.

Keep source/model/binary identities, each complete report and all failures.
The recorded correctness/nonregression passes do not mark the application
qualified. F32 remains a control; ONNX INT4 remains distinct from Q4_K.
