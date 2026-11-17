# German grammar proofing: scoped implementation roadmap

Status: bounded Dart runtime qualification complete; CrispEmbed mixed Q4_K selected for the next native implementation/qualification slice; application provider pending.
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

### M4: selected native lane and fallback

CrispEmbed/ggml (selected next): use a small native target with controlled
BERT/GGUF/ggml CPU dependencies; the current full library is monolithic.
Convert the exact fine-tuned encoder plus both GECToR heads;
provide a default-off prepared-ID interface with an explicit unpadded/all-ones
mask contract or fully implement masks. Use ggml matrix operations for the heads.
Prove F32/F16 equivalence first, then Q4_K/mixed-precision decoded nonregression.
Follow CrispEmbed PLAN ownership, environment-gate and hosted benchmark rules.

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

### Product quality and remaining work

Both models retain 9/18 exact expected error corrections and 1/12 changed
clean controls on the frozen synthetic panel, including the incorrect de-CH
heisse -> heiße edit. Quantization introduced no changed inputs, selected tags,
final text or suggestion spans on this panel. These counts do not estimate
general German accuracy. Broader held-out evaluation and incremental value
over existing deterministic rules remain required.

The next code slice is the exact fine-tuned ONNX-to-GGUF conversion, both
trained heads and prepared-ID native entry point, followed by F32 control
parity and actual mixed Q4_K qualification. The CrispEmbed roadmap and PLAN
record its observed architecture, required tensor transposes, Q/K rounding
order, proposed small native dependency boundary and hosted-build gates.
The Rust roadmap preserves the explicit API-24/native-runtime version check
and outstanding FFI packaging work.

No GGUF model, native GECToR backend or application provider is implemented
by this initial qualification slice. M3 and native implementation remain open.
Preserve shared Dart tokenization/decoding/guards, protected ranges, UTF-16
source mapping, bounded workers and manual/F7 integration as scoped above.
Measure longer 64/128/256-token inputs and complete checks before qualification.

### Durable evidence

- [Original local two-case baseline](../validation/german-gector/2026-11-17-local-smoke/README.md).
- [Original full hosted baseline](../validation/german-gector/2026-11-17-hosted-baseline/README.md), run 44053903485.
- [All local optimization observations](../validation/german-gector/2026-11-17-local-optimization/README.md), including the slower final opt-in repeat.
- [Final full hosted optimized result](../validation/german-gector/2026-11-17-hosted-optimized/README.md), run 44062093617.

Keep source/model/binary identities, each complete report and all failures.
The recorded correctness/nonregression passes do not mark the application
qualified. F32 remains a control; ONNX INT4 remains distinct from Q4_K.
