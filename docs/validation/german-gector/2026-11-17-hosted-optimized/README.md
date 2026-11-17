# Hosted optimized German GECToR evidence — 2026-11-17

**The optimized qualification job passed its numerical correctness, tokenizer,
experiment-integrity and frozen-case nonregression checks. The application is
still unqualified.** Pure Dart INT4 took **463.426 ms median / 545.531 ms p95**
for a single forward pass on short inputs, with a process peak of **465.11 MiB**.
The p95 already exceeds the provisional 500 ms complete-checker target, before
tokenization, iterative correction, guards or editor integration.

The bounded pure-Dart tuning effort stops at this evidence. The next qualification
lane is **CrispEmbed/ggml with a mixed Q4_K pack**, initially retaining both GECToR
output heads at higher precision: F32 for the control and proposed F16 for the
mixed candidate, subject to parity and decoded-quality gates. **Rust/native ONNX
Runtime remains conditional on its separate license and packaging gate.** Those
are future qualification choices: this run executed neither integration,
produced no GGUF/Q4_K pack and selected no shipping implementation.

This record preserves the optimized run separately from the
[hosted baseline](../2026-11-17-hosted-baseline/README.md) and
[local optimization measurements](../2026-11-17-local-optimization/README.md).
[evidence.json](evidence.json) contains exact source/artifact identities, aggregate
measurements, validation thresholds and audit results.
[cases.json](cases.json) preserves all 30 case outcomes, 40 saved pass decisions
per model and every recorded timing sample. No weights or raw tensor buffers are
included in this directory.

## Frozen run and experiment flags

| Item | Recorded identity |
| --- | --- |
| Workflow run | [44062093617](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44062093617), attempt 1, completed successfully |
| Job | [133966294406](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44062093617/job/133966294406) |
| Quds source | [`69d153c0f81596af894e48e21880f0957b963994`](https://github.com/CrispStrobe/quds_office_suite/tree/69d153c0f81596af894e48e21880f0957b963994) |
| Actual and declared Dart source | [`b10258682d459847b63e012eaaba58a528e93956`](https://github.com/CrispStrobe/onnx_runtime_dart/tree/b10258682d459847b63e012eaaba58a528e93956) |
| Model | [`proofbird/gector-bert-de`, v2.1.0](https://huggingface.co/proofbird/gector-bert-de/tree/8e3b50beef7d775cedb7b876009e88bcf2e8d6af), revision `8e3b50beef7d775cedb7b876009e88bcf2e8d6af` |
| F32 experiments, declared and reported | `[]` |
| INT4 experiments, declared and reported | `["narrowDirectGemm"]` |
| Frozen scope | 30 cases: 18 errors and 12 clean controls; 40 actual saved passes per model |
| Timing scope | First-pass lengths 5–12 WordPieces; 1 warmup and 3 measured repetitions per case |

The INT4 path combines bounded column tiles in `MatMulNBits` with the explicitly
enabled `narrowDirectGemm` experiment. The library default remains off. The hosted
summary verifies the complete reports' experiment lists against provenance; the
documentation audit independently checked the same equality. Thus the optimized
measurement is tied to the final opt-in implementation, rather than only to the
earlier local prototype.

The run was created at 10:08:53 UTC and last updated at 10:13:09 UTC. All nine
required stages passed. The hosted lightweight suite recorded **19 tests passed
in 0.897 s**, including the tiny real ONNX conversion control and negative
experiment-declaration integrity checks. These test results were read from the
artifact; the documentation audit performed no new inference or model loading.

## Measured latency and memory on this runner

The hosted VM reported **Intel Xeon 6975P-C**, four logical CPUs arranged as two
cores with two threads per core, KVM, and Linux `7.0.0-1014-aws`. The workflow used
native ONNX Runtime with two intra-op threads, one inter-op thread and sequential
execution. Dart used two GEMM workers plus its caller. `MatMulNBits` remains on
the caller, so these settings do not give identical scheduling. This hosted
workflow set no explicit CPU affinity or local `nice` control.

| Runtime and exact model | First forward median | First forward p95 | Complete reference correction median | Complete reference correction p95 | Recorded process peak |
| --- | ---: | ---: | ---: | ---: | ---: |
| Native ORT 1.23.2, F32 | 16.802 ms | 18.683 ms | 18.373 ms | 36.680 ms | 625.42 MiB before optional census |
| Native ORT 1.23.2, INT4 | 15.772 ms | 17.060 ms | 16.907 ms | 33.220 ms | 342.20 MiB |
| Pure Dart, F32, default experiments | 200.334 ms | 250.041 ms | Not measured | Not measured | 1,597.13 MiB |
| Pure Dart, INT4, `narrowDirectGemm` | 463.426 ms | 545.531 ms | Not measured | Not measured | 465.11 MiB |

Each aggregate combines **90 measured samples** from different short sentence
lengths. Per-case samples remain available in `cases.json`; a per-case p95 is the
maximum of only three measurements. These measurements provide no 64-, 128- or
256-token coverage and no target-device guarantee. In this run, native INT4 was
slightly faster than native F32 on these cases; the earlier hosted baseline had
the opposite ordering.

The native complete-correction measurements execute the frozen upstream iterative
runner, including its own tokenization and decoding, without export observers.
They omit application guards and spelling checks. Dart timings execute the exact
saved first-pass inputs; they exclude tokenization, reference buffers, hashing
and decoding. Validation additionally covers every saved follow-up pass, but
that does not constitute an independently implemented complete Dart correction
loop.

| Startup observation | Native F32 | Native INT4 | Dart F32 | Dart INT4 |
| --- | ---: | ---: | ---: | ---: |
| Native runner/session setup | 680.116 ms | 260.331 ms | — | — |
| Dart graph load | — | — | 897.933 ms | 287.533 ms |
| Dart worker-pool setup | — | — | 320.949 ms | 16.337 ms |
| Dart cold first forward | — | — | 188.748 ms | 470.511 ms |

Native setup and Dart graph load have different scopes. Hash verification occurs
before Dart loading and can warm filesystem caches; these are not cold disk-load
measurements. Process RSS includes runtime, model and temporary allocations.
The native F32 exporter writes its reference report before an optional ONNX
graph census. Its **655,798,272-byte** recorded reference-phase peak must be kept
separate from the entire stage's **1,490,079,744-byte** peak after that census.
The INT4 reference did not request a census. Dart inference peaks were captured
before the diagnostic profile and reference-output validation; the later peaks
are preserved separately and were equal in this run.

A separate diagnostic forward on `verb-du` attributed **431.173 ms** to 72
`MatMulNBits` calls out of **462.606 ms** wall time in the INT4 arm. It is an
operator-level observation, not one of the 90 timing samples and not a profile of
the application. The bounded INT4 work still dominates this short forward.

## What correctness means here

Each Dart arm was checked against native ORT using the **identical model file**,
tokenizer and saved inputs. F32 Dart is compared with F32 ORT; INT4 Dart is
compared with INT4 ORT. Both heads, `logits_labels` and `logits_d`, passed on all
40 saved passes in each arm. Raw selected label IDs and thresholded label IDs
matched exactly, with **zero mismatches**. Token IDs and first-subword alignment
also passed the full saved-pass tokenizer checks.

| Same-model numerical comparison | Maximum label-head absolute error | Maximum detection-head absolute error | Raw / thresholded tag mismatches |
| --- | ---: | ---: | ---: |
| F32 Dart versus F32 ORT | 0.0000400543 | 0.0000109673 | 0 / 0 |
| INT4 Dart versus INT4 ORT | 0.0000286102 | 0.0000133514 | 0 / 0 |

These results establish numerical agreement within the declared tolerances, not
bitwise identity. The checker requires cosine at least `0.999999`, maximum
absolute error within the larger of `0.001` and `0.00025 × maximum reference
magnitude`, selected-probability error at most `0.0001`, and exact selected IDs.
The full thresholds and observed maxima are retained in `evidence.json`.

**Quantization quality is a separate comparison.** Native F32 and native INT4
produced identical final text and UTF-16 suggestions on all 30 frozen cases.
Their saved pass inputs and both raw and thresholded label IDs also matched on
all 40 passes. Both corrected **9 of 18 error cases** and changed **1 of 12 clean
controls**. There were no lost baseline fixes or new/changed clean false edits.
The small synthetic panel does not estimate accuracy on real documents.

The existing Swiss false edit remains in both models:

```text
Locale: de-CH
Input:  Grüezi, ich heisse André.
Output: Grüezi, ich heiße André.
```

Passing nonregression does not resolve this error. Locale policy, protected
names, conservative application guards and full editor-level correction quality
remain separate work.

## Quantization and artifact integrity

The original F32 model is **452,972,247 bytes / 431.99 MiB**. The candidate is
**158,365,857 bytes / 151.03 MiB**. The converter selected 72 encoder `MatMul`
weights for ONNX `MatMulNBits`: 4 bits, block size 128, symmetric quantization,
accuracy level 0 and ORT's default round-to-nearest algorithm. Embeddings, biases
and norms retain their original precision. The output matrices remain FP32:

| Output | Preserved node | Weight shape |
| --- | --- | --- |
| `logits_labels` | `/m/labels_head/MatMul` | `[768, 5000]` |
| `logits_d` | `/m/detect_head/MatMul` | `[768, 2]` |

The converter verifies head-node/weight preservation; its exact tensor-protobuf
hashes and the declared recipe are retained in the compact record. The
documentation audit checked that metadata and excluded-node identities without
loading the model. **ONNX INT4 is not ggml/GGUF Q4_K.** A mixed Q4_K conversion
requires its own converter, mapping, parity and quality evidence.

| File identity | SHA-256 |
| --- | --- |
| F32 `model.onnx` | `6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464` |
| Candidate `model.int4.onnx` | `6c92deb88469e2fce2ddded5159014200d8681a7853722714224539a48285d70` |
| `tokenizer.json` | `45253db94c657c7b89880de2c8872e10cd0561577e9393e1f5f4df27b0165087` |
| Frozen case file | `ec3309ebf99a3b1be9bb065fc91cd2afce2e362ebaa81f2d64d39a231c6defb9` |

The independent documentation audit verified the evidence ZIP digest, all **160
raw output files totaling 12,324,928 bytes**, report-to-fixture/model/tokenizer
links, candidate-manifest linkage, complete case/pass coverage, all nine pinned
Quds provenance source hashes, the pinned Dart benchmark/pubspec, and the archived
Dart dependency lock. It recomputed every aggregate median and p95 from the
recorded samples. It did not rerun inference or treat source/report hashes as a
new independent model evaluation.

## Comparison with the earlier hosted run

| Hosted observation | CPU / hypervisor | Dart INT4 median | Dart INT4 p95 |
| --- | --- | ---: | ---: |
| [Baseline, 44053903485](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44053903485) | AMD EPYC 9V74 / Microsoft, Azure kernel | 767.256 ms | 835.173 ms |
| [Optimized, 44062093617](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44062093617) | Intel Xeon 6975P-C / KVM, AWS kernel | 463.426 ms | 545.531 ms |

The cases and candidate model hashes match, but the runner hardware, hypervisor
and runtime code differ. **The p95 observation moved from 835.173 to 545.531 ms;
this is not a randomized same-host A/B estimate of the code's speedup.** No
samples are pooled across these hosted runs or the separate local runs. The
earlier baseline remains unchanged.

The optimized INT4 model fits the provisional 160 MiB model-download preference and
768 MiB isolated-process memory budget on this runner. Its short-input forward
p95 still exceeds the complete-checker latency target. F32 has a lower forward
p95 but exceeds the memory budget. Neither result qualifies the application.
The next native lane must repeat same-model dual-head/tag checks and then measure
the complete guarded correction path, longer inputs and intended devices before
editor integration or release selection.

## Source licenses and retained evidence

The [frozen model/reference bundle](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/LICENSE)
uses Apache-2.0 and includes a pinned
[NOTICE](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/NOTICE).
[Quds evaluation code](https://github.com/CrispStrobe/quds_office_suite/blob/69d153c0f81596af894e48e21880f0957b963994/LICENSE)
and [onnx_runtime_dart](https://github.com/CrispStrobe/onnx_runtime_dart/blob/b10258682d459847b63e012eaaba58a528e93956/LICENSE)
use MIT. This record does not infer a separate future GGUF pack's license or
redistribution contents.

The measured native ORT wheel is a development/performance oracle, not an
approved application dependency. ORT 1.23.2 has an MIT top-level license, but
its pinned [third-party notices](https://github.com/microsoft/onnxruntime/blob/a83fc4d58cb48eb68890dd689f94f28288cf2278/ThirdPartyNotices.txt)
include Eigen under MPL-2.0. The user's strict permissive-license requirement
therefore leaves native ORT distribution unapproved pending qualification of
the exact binary and complete dependency closure. The Rust fork uses API-24
and needs a separate runtime-version and license audit. These measured timings
remain valid; they do not establish a shippable Rust/Dart FFI implementation.
The selected small ggml target also requires its own source, linked-library
and packaged-asset license inventory.

The environment pinned Python 3.12.16, native ORT 1.23.2, ONNX 1.19.1,
tokenizers 0.22.1, huggingface-hub 0.36.0, NumPy 2.3.5 and Dart 3.14.0. Exact
dependency/source file hashes and the AOT binary identity are in `evidence.json`.

| Hosted artifact | Identity |
| --- | --- |
| [Evidence artifact 14318039568](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44062093617/artifacts/14318039568) | ZIP SHA-256 `9244e83ded64639b1b5cc8fc095d59e3973a115db1c85ebd95eee29273b64327` |
| [Candidate artifact 14317884182](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44062093617/artifacts/14317884182) | ZIP SHA-256 `a56fa4c4e2862770ae01227fc5e4e2b8c5af0ab04563769811207faf2f035c2b` |

Hosted artifacts have a configured 30-day retention period. These small committed
records preserve the decision evidence independently of that retention. They
contain no private absolute filesystem paths, model weights or raw tensor files.
