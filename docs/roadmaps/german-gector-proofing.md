# German grammar proofing: scoped implementation roadmap

Status: feature work authorized; inference and quantized model qualification pending.
Date: 2026-11-17.
Coordinated branch: `feat/german-gector-proofing`.

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
  it does not load GGUF. Its current implementation expands each matrix to
  Float32List before multiplication on every call. Measure execution and peak
  RAM rather than treating a smaller artifact as a speed improvement.
- Start the ONNX candidate with a declared weight-only MatMulNBits recipe and
  record block size, symmetry, operator inventory, excluded tensors, converter
  version, source/model SHA and resulting artifact SHA. Preserve both heads.
- The conditional ggml candidate uses Q4_K encoder matrices. Keep sensitive
  tensors and the edit/detection heads in F16 or Q8_0 if decoded quality requires
  it; record the complete mixed-precision tensor manifest.
- Keep F32 and, where relevant, F16 controls. A Q4 candidate must preserve
  useful corrections and avoid additional false edits on clean controls.
  Logit cosine or file-size savings alone do not qualify it.
- Do not label ONNX MatMulNBits as Q4_K, silently ship F32, or overwrite frozen
  reference outputs with candidate outputs.

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
- [ ] Add a Dart AOT benchmark consuming the captured inputs and both named
  outputs. Fail on missing outputs, unsupported operators, incorrect shape,
  non-finite values or unacceptable numerical/decision differences.
- [ ] Add a reusable pretokenized WordPiece API with source-word alignment and
  tests for cased German, punctuation, special tokens and truncation.
- [ ] Execute the same-host native ORT control and Dart candidate, with declared
  thread budgets, cold load, first inference, warm median/p95, iteration counts,
  sequence-length coverage and peak RSS. Separate inference time from complete
  correction latency and from model download/verification.
- [ ] Preserve exact workflow/job/source/SDK/model/converter identities and all
  failures. CI timings qualify only that host, not mobile/browser hardware.

### M2: bounded optimization and backend decision

- [ ] Compare the original ONNX model with the declared ONNX INT4 candidate.
  Report exact artifact size, quantized operator inventory and unsupported paths.
- [ ] Profile the limiting work before changing runtime code. Candidate changes
  include initializer lifetime, last-use intermediate reclamation, packed-weight
  execution or bounded reuse, and worker/thread allocation. Change one cause
  at a time, retain a reproducible baseline, and measure decoded parity.
- [ ] Limit the initial Dart optimization round to two measured hypotheses.
  If resource or latency targets remain unsuitable, open the native lane rather
  than growing an unbounded runtime project.
- [ ] Select a backend from recorded evidence; no backend is selected merely
  because its API accepts the model.

Provisional desktop engineering targets for the eventual complete checker:
warm p95 <=500 ms for sentences up to64 wordpieces, peak process RSS <=768 MiB,
and preferred downloadable model pack <=160 MiB. Report pass/fail against these
budgets without treating a hosted-runner pass as target-device qualification.
Longer128/256-token inputs are measured separately and must not be silently
truncated. Record full iterative correction latency; per-forward timing alone
cannot satisfy the complete-check target. Refine target-device budgets openly
before mobile/browser rollout, not after viewing results to make a run pass.

### M3: optional Quds provider

- [ ] Add packages/quds_proofing_gector with a backend-neutral decoder, verified
  model-bundle loading and a persistent worker. Reuse Harper transport patterns.
- [ ] Port word preparation, first-subword mapping, label/verb transformations,
  bounded iterative edits and guard behavior with original-text UTF-16 mapping.
- [ ] Expose tested de-DE support first. Add explicit de-AT/de-CH policy and
  controls before advertising those locales.
- [ ] Construct results around the original request object; forRequest receives
  request-relative offsets and adds startOffset exactly once.
- [ ] Reuse protected ranges; define personal-vocabulary and duplicate/conflict
  handling. Expose a read-only existing lexicon interface only if guards need it.
- [ ] Load outside the service request deadline; bound the queue, cancel obsolete
  work between passes, invalidate caches on configuration changes and report
  missing/failed/partial work honestly.
- [ ] Introduce the model through optional manual/F7 checking. Existing service
  Future.wait and end-of-scan publication require a separate scheduling change
  before responsive background model checks.
- [ ] Apply suggestions through the existing guarded editor command, including
  rich text, undo, tracked changes, protection and stale-result controls.

### M4: conditional native backends

CrispEmbed/ggml: convert the exact fine-tuned encoder plus both GECToR heads;
provide a default-off prepared-ID interface with an explicit unpadded/all-ones
mask contract or fully implement masks. Use ggml matrix operations for the heads.
Prove F32/F16 equivalence first, then Q4_K/mixed-precision decoded nonregression.
Follow CrispEmbed PLAN ownership, environment-gate and hosted benchmark rules.

Rust/native ONNX: use a dedicated prepared-input grammar/session abstraction
with preserved word alignment, bounded thread counts and exact output selection.
The pooled embed() API is unsuitable; raw transform outputs are available but
the current public string path discards alignment. Use the original ONNX model
or a separately qualified ONNX quantized artifact; this is not a Q4_K backend.

## Acceptance and evidence

1. Reproducible source/model/tokenizer/label/guard provenance and permissive
   code/model notices; no GPL/LGPL/AGPL/NC dependency added for this feature.
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

## Current execution state

Roadmaps were published and read back before implementation:

- Quds: `4cceff38040d423c4cfc08a0039b0379c6b35bbf`.
- Dart runtime: `3ac10dd64c655657186ba89e673cb183d2250682`.
- CrispEmbed: `85e973fba7c1be3f8bf028bb43de82ce0537174f` (including PLAN ownership).
- Rust fallback: `99d21fbc830e3dbaaafff3d60a0864097b1b795b`.

The first implementation adds `export_reference.py`, its documented fixture
contract and nine lightweight integrity/alignment tests. All nine pass with
synthetic data; no real model inference is implied by those tests. The exporter
preserves the original evaluator, vendored runner, cases and recorded results.
It captures actual iterative passes and separately measures native ORT forward
and complete-correction timing for both an original and verified derived model.

Hosted model execution, Dart runtime qualification and quantized task quality
remain pending. Record exact implementation commits/runs and retain failures
as the work progresses. No application provider or target platform is qualified.
