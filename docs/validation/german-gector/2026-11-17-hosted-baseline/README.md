# German GECToR: hosted baseline qualification

**The hosted job passed executor parity and frozen-probe nonregression for both
models across all 30 cases. The baseline still does not qualify a shipping
grammar checker.** F32 Dart inference used too much memory; INT4 reduced memory
and file size but its first-forward p95 exceeded the provisional complete-checker
latency budget. The known Swiss false edit remains.

This record covers the original implementation before the tile/kernel
optimization experiments. [evidence.json](evidence.json) preserves source,
dependency and artifact identities, aggregate measurements, audit checks and
limits. [cases.json](cases.json) preserves every case's outcome, observed input
and tag IDs, per-case timing samples and parity results. No weights, raw tensor
buffers or private filesystem paths are committed here.

## Run and inputs

| Item | Identity |
| --- | --- |
| Hosted run | [44053903485](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44053903485), attempt 1, completed successfully |
| Job | [133938202847](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44053903485/job/133938202847) |
| Quds source | `6bd03365ba3b146586148658b0e03998b36bdc9d` |
| Dart implementation | `0b49ca47fa056e6fc122ffe0192a9abb05627622` |
| Model | `proofbird/gector-bert-de` v2.1.0 |
| Model revision | `8e3b50beef7d775cedb7b876009e88bcf2e8d6af` |
| Original F32 SHA-256 | `6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464` |
| Derived INT4 SHA-256 | `6c92deb88469e2fce2ddded5159014200d8681a7853722714224539a48285d70` |

GitHub reported `completed / success`, last updated at **2026-11-17 09:48:49
UTC**, when independently checked at 09:56:27 UTC. All nine required stage
reports passed. The hosted lightweight controls ran **14 tests in 0.849
seconds**, including the actual tiny ONNX conversion control.

Both model arms covered the complete frozen panel: **18 error cases, 12 clean
controls, 30 first inputs and 40 saved iterative passes**. Each case had one
warmup and three measured iterations, giving **90 first-forward samples per
runtime/model arm**. First-pass lengths were only **5–12 wordpieces**, including
special tokens. Longer inputs and the eventual complete Dart checker were not
measured.

## Host and timing protocol

The Ubuntu hosted VM reported an **AMD EPYC 9V74 80-Core Processor**, with **4
logical CPUs exposed as 2 cores with 2 threads per core**. It reported
16,367,528 KiB total memory and Microsoft virtualization. ORT used two intra-op
threads, one inter-op thread and sequential execution. Dart AOT used two GEMM
workers plus its caller; `MatMulNBits` remained on the caller in this baseline.
These are declared runtime settings, not identical thread scheduling. This
workflow did not apply the separate local diagnostic's CPU-affinity controls.

Versions were Dart **3.14.0**, Python **3.12.16**, ONNX Runtime **1.23.2**, ONNX
**1.19.1**, tokenizers **0.22.1**, huggingface-hub **0.36.0** and NumPy **2.3.5**.
The archived Dart dependency lock and AOT executable hashes are retained in the
JSON. All figures below come from this hosted run; local timings are not mixed
into these results.

## Forward and complete-reference latency

These are pooled statistics over 90 samples from the 30 short cases. They
combine sentence lengths and are not a fixed-length benchmark. Every per-case
sample is available in `cases.json`; a per-case p95 is just the largest of its
three measurements.

| Runtime and model | First-forward median, ms | First-forward p95, ms | Maximum, ms |
| --- | ---: | ---: | ---: |
| Native ORT, F32 | 13.730 | 16.431 | 18.262 |
| Native ORT, INT4 | 16.209 | 20.035 | 20.651 |
| Dart AOT, F32 | 225.419 | 286.384 | 310.756 |
| Dart AOT, INT4 | 767.256 | 835.173 | 862.381 |

First-forward timings exclude loading, tokenization, edit decoding and
reference-output reads. Each Dart model was compared with its **own exact-model
ORT reference**. F32 logits were not used as the INT4 runtime oracle.

The native runner additionally measured complete iterative correction, with
the export observers removed:

| Native reference | Complete-correction median, ms | Complete-correction p95, ms | Maximum, ms |
| --- | ---: | ---: | ---: |
| F32 | 15.107 | 31.448 | 50.279 |
| INT4 | 18.257 | 36.536 | 40.894 |

These complete native calls include tokenization and edit decoding but still
omit application guards and spelling checks. No corresponding independent
complete Dart correction loop was measured. Native INT4 was slower than native
F32 in the pooled median and p95, despite its smaller artifact.

## Size, startup and memory

| Measurement | F32 | INT4 |
| --- | ---: | ---: |
| Model bytes | 452,972,247 | 158,365,857 |
| Model size, MiB | 431.99 | 151.03 |
| Native runner setup, seconds | 0.669 | 0.272 |
| Dart graph load, seconds | 0.838 | 0.308 |
| Dart pool setup, seconds | 0.355 | 0.020 |
| Dart first forward after setup, seconds | 0.208 | 0.765 |
| Native reference process peak before optional census, MiB | 625.55 | 342.14 |
| Dart inference-phase peak RSS, MiB | 1633.99 | 476.79 |

INT4 reduced model bytes by about **65.04%**. Its pack is below the preferred
160 MiB limit, and its measured isolated process is below the provisional
768 MiB budget. F32 is above both. RSS includes runtime overhead and
allocations, not just weights, and this process does not include an editor.
Hash verification warms file caches before loading, so startup is not cold
disk I/O.

**The native F32 stage has two different memory scopes.** The reference JSON
records **655,937,536 bytes** before the optional architecture census. The stage
wrapper records **1,496,141,824 bytes** for the whole child process, including
the later ONNX graph/protobuf census. The latter must not be presented as the
reference inference-phase memory requirement. The INT4 reference did not run
that optional census. Both values and their scopes are preserved in the JSON.

F32's forward p95 is below 500 ms on this short panel, but its memory exceeds
the provisional budget and complete Dart latency remains unmeasured. INT4's
**835 ms first-forward p95 already exceeds the 500 ms complete-checker budget**.
The successful CI result therefore does not pass the product resource gates.
A separate diagnostic profile attributes 0.740 seconds to the 72
`MatMulNBits` calls, motivating the bounded runtime optimization experiment.

## Parity and model behavior

Both Dart arms matched token IDs and word alignment and passed both output-head
checks for **all 40 saved passes**. Each recorded **zero raw and zero
thresholded tag mismatches** against its own ORT reference. Maximum absolute
head error was about `4.01e-5` for F32 and `2.86e-5` for INT4; exact tag checks
and probability-error limits accompanied the numerical checks.

Separately, the F32 and INT4 models had identical saved inputs, selected tag IDs,
final corrected text and UTF-16 suggestion spans across the full frozen panel.
They each produced **9 of 18 exact expected corrections**, and each changed
**1 of 12 clean controls**. No baseline fix was lost and no new or changed false
edit appeared in the INT4 candidate.

The retained clean-control failure is `clean-swiss-name`, locale `de-CH`:

> Input: Grüezi, ich heisse André.
>
> Both models: Grüezi, ich heiße André.

The candidate preserves this Swiss spelling error along with the useful
corrections. The panel is synthetic and small: these counts are not population
accuracy estimates, and numerical parity does not make an incorrect suggestion
appropriate for the application.

## Candidate recipe, integrity and licensing

The converter changed **72 encoder MatMul weights** to ONNX `MatMulNBits`,
**4 bits, block size 128, symmetric, accuracy level 0**, using ORT's default
weight-only round-to-nearest conversion. Both output projection operations and
their FP32 weights were verified unchanged: `[768,5000]` for labels and
`[768,2]` for detection. Embeddings, bias and norms retain their original
precision. The exact head names and tensor hashes are recorded.

The documentation audit checked **160 raw reference tensor files totaling
12,324,928 bytes** against their hashes, lengths and shapes. It also checked the
candidate-manifest links, both fixture/model identities, complete coverage,
source hashes against the pinned git objects, the archived dependency lock and
all aggregate medians/p95 recomputed from samples. This audit did not perform
new inference or load the model.

The [Quds code](https://github.com/CrispStrobe/quds_office_suite/blob/6bd03365ba3b146586148658b0e03998b36bdc9d/LICENSE)
and [Dart runtime](https://github.com/CrispStrobe/onnx_runtime_dart/blob/0b49ca47fa056e6fc122ffe0192a9abb05627622/LICENSE)
use MIT. The frozen model/reference bundle supplies an
[Apache-2.0 LICENSE](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/LICENSE)
and [NOTICE](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/NOTICE).
**ONNX INT4 is not ggml/GGUF Q4_K.** No Rust backend, CrispEmbed/ggml backend,
Q4_K model, mobile application or browser runtime was measured by this job.

## Durable record and follow-up

The source evidence is [artifact 14316019589](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44053903485/artifacts/14316019589).
Its downloaded ZIP SHA-256 is
`78804130ca5af6dac93c194f415f98e634d750fdd8601701676052a08ad473b8`.
The candidate bytes and notices are separately retained as
[artifact 14317990056](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44053903485/artifacts/14317990056).
The workflow requests 30-day artifact retention; this compact committed record
preserves the identities and measurements beyond that period.

Keep this baseline and the earlier local baseline unchanged. Store optimized
kernel results separately with their own source and executable identities,
identical-input parity and host controls. Longer inputs, full Dart corrections,
regional guards, original-text mapping and editor integration remain distinct
qualification work.
