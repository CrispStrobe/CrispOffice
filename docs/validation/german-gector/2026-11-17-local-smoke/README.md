# German GECToR: local baseline before runtime optimization

Date: 2026-11-17. **Exact-input Dart parity passed on two selected cases, but
baseline Dart inference was too slow for the provisional interactive budget.**
The INT4 candidate reduced artifact size and process memory substantially; it
did not establish a useful speed improvement. Neither the application provider
nor a shipping backend is qualified by this diagnostic.

The accompanying [baseline.json](baseline.json) contains the exact source/model
identities, original evidence-file hashes, timing samples, parity metrics,
resource controls, conversion recipe and limitations. It contains no weights,
raw tensor binaries or private filesystem paths.

## Scope and source identity

This run selected **2 of the frozen 30 cases**: `verb-du` and
`clean-swiss-name`. Their first inputs contain 7 and 10 wordpieces, including
special tokens. Each native correction used two passes. Dart validated both
heads and selected decisions on all four saved passes per model; it timed the
first pass of each case. It did not implement or time an independent complete
Dart correction and guard loop.

| Component | Exact identity |
| --- | --- |
| Quds evaluation source | `6bd03365ba3b146586148658b0e03998b36bdc9d` |
| Dart runtime and benchmark | `0b49ca47fa056e6fc122ffe0192a9abb05627622` |
| Model | `proofbird/gector-bert-de`, v2.1.0 |
| Immutable model revision | `8e3b50beef7d775cedb7b876009e88bcf2e8d6af` |
| F32 model SHA-256 | `6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464` |
| INT4 model SHA-256 | `6c92deb88469e2fce2ddded5159014200d8681a7853722714224539a48285d70` |

The model/fixture/candidate links and selected source-file bytes were checked
against the recorded JSON and pinned git objects when preparing this record.
The JSON also retains the benchmark executable and dependency-lock hashes.

The complete lightweight Python discovery was separately rerun in the pinned
qualification environment: **all 14 tests passed in 2.006 seconds**, including
the actual tiny ONNX conversion control. The command was
`python -m unittest discover -s tools/proofing/german_model -p 'test_*.py'`.
Those tests do not execute the frozen German checkpoint or establish its quality.

The host was Linux x86-64 and reported 9 logical CPUs; its CPU model was not
recorded. Every diagnostic stage used affinity to CPUs **0 and 1**, a niceness
increment of **+10**, a 90-second CPU limit, a 180-second wall limit, and a 3 GiB
RSS stop threshold. All five stages completed successfully. Native ORT used two
intra-op threads, one inter-op thread and sequential execution. Dart AOT used
two GEMM workers; that worker setting is not the process's total thread count.

Each timing used **one warmup and three measured iterations**. The recorded
nearest-rank p95 is therefore the maximum of three observations, not a reliable
latency-distribution estimate. The machine was shared and samples were noisy.

## Forward latency

Values are **median / p95 in milliseconds**, on the same saved first-pass inputs.

| Case | Native ORT F32 | Native ORT INT4 | Dart F32 | Dart INT4 |
| --- | ---: | ---: | ---: | ---: |
| `verb-du`, 7 pieces | 26.48 / 28.47 | 44.81 / 45.72 | 1782.98 / 2748.77 | 1896.17 / 2066.49 |
| `clean-swiss-name`, 10 pieces | 30.29 / 30.84 | 45.52 / 46.82 | 2388.29 / 3333.68 | 2146.93 / 2435.67 |

These figures exclude model loading, tokenization, reference-file reads and edit
decoding. Native INT4 was slower than native F32 on both inputs. Dart's results
do not support a consistent INT4 speedup. Even one Dart forward already exceeds
the roadmap's provisional 500 ms p95 budget for the eventual complete checker.

The original unguarded native runner's **complete iterative correction** was
also measured separately, with export observers removed:

| Case | Native ORT F32, median / p95 ms | Native ORT INT4, median / p95 ms |
| --- | ---: | ---: |
| `verb-du` | 54.66 / 56.98 | 84.67 / 85.27 |
| `clean-swiss-name` | 58.71 / 58.78 | 97.81 / 124.88 |

Those complete native timings include tokenization and edit decoding. They
still omit the application guards and editor integration. The F32 reference
stage's roughly 160-second total also includes downloading and verification;
it is not a correction-latency measurement.

## Size, startup and memory

| Measurement | F32 | INT4 |
| --- | ---: | ---: |
| Model bytes | 452,972,247 | 158,365,857 |
| Model size, MiB | 431.99 | 151.03 |
| Native runner setup, seconds | 4.111 | 2.268 |
| Dart graph load, seconds | 7.537 | 1.920 |
| Dart worker-pool setup, seconds | 3.804 | 0.096 |
| Dart first forward after setup, seconds | 1.989 | 2.288 |
| Native process peak RSS, MiB | 604.42 | 321.21 |
| Dart inference-phase peak RSS, MiB | 1453.36 | 465.63 |

INT4 saves about **65.04% of model bytes**. Its 151.03 MiB artifact is below the
roadmap's preferred 160 MiB pack size, and this isolated Dart process stayed
below 768 MiB. F32 exceeded both provisional size and memory budgets. These are
whole-process memory measurements, not weights alone; they do not include a
running editor. Model hashing warms filesystem caches before loading, so the
load figures do not measure cold disk I/O.

A separate diagnostic profile points to matrix operations: F32 `MatMul`
accounted for about 87% of recorded operator time; INT4 `MatMulNBits` accounted
for about 97%. Profiling was outside the timed samples. The next optimization
experiment should retain this baseline and measure one cause at a time.

## Parity and retained quality failure

For **each exact model file**, Dart matched its own native ORT reference on
token IDs, word alignment, both heads and selected tags. Both variants recorded
zero raw or thresholded tag mismatches over four saved passes. Maximum absolute
head error was about `4.01e-5` for F32 and `2.29e-5` for INT4. This establishes
limited executor parity; F32 logits were not used as the INT4 runtime oracle.

The separate F32-versus-INT4 task comparison produced identical text and UTF-16
suggestion spans for the two cases:

| Case | Both native models produced | Interpretation |
| --- | --- | --- |
| `Du geht heute nach Hause.` | `Du gehst heute nach Hause.` | Expected correction retained |
| `Grüezi, ich heisse André.` (`de-CH`) | `Grüezi, ich heiße André.` | Existing Swiss false edit retained |

The candidate preserved one useful correction **and one known false edit**.
There was no new difference in this selected pair. This is not an accuracy
estimate, a clean-control pass, or evidence that German regional handling is
ready. Numerical agreement faithfully preserves the model's mistake.

## Quantization and licenses

The candidate used ORT 1.23.2 and ONNX 1.19.1, with 72 encoder `MatMul`
operations converted to **ONNX `MatMulNBits`, 4 bits, block size 128, symmetric,
accuracy level 0**. The `/m/labels_head/MatMul` `[768,5000]` and
`/m/detect_head/MatMul` `[768,2]` operations and their FP32 weight protobufs were
verified unchanged. Embeddings, bias and norms retained their original
precision. The exact protected tensor names and hashes are in the JSON.

**ONNX INT4 is not ggml/GGUF Q4_K.** No Rust backend, CrispEmbed/ggml backend or
Q4_K model was executed. Python native ORT is the measured reference control,
not evidence that a Rust/Dart bridge has been implemented or qualified.

The pinned [Quds code](https://github.com/CrispStrobe/quds_office_suite/blob/6bd03365ba3b146586148658b0e03998b36bdc9d/LICENSE)
and [Dart runtime](https://github.com/CrispStrobe/onnx_runtime_dart/blob/0b49ca47fa056e6fc122ffe0192a9abb05627622/LICENSE)
use MIT. The frozen model/reference bundle has an
[Apache-2.0 LICENSE](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/LICENSE)
and [NOTICE](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/NOTICE),
whose hashes are retained in this record.

## Outstanding evidence and follow-up

The full hosted [qualification run 44053903485](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44053903485)
was **queued**, with no conclusion, when checked at **2026-11-17 09:39:12 UTC**.
Its source commit is the Quds commit above. These local results must not be
presented as that run passing or as execution of all 30 cases.

Keep this baseline unchanged. Add any tile/kernel optimization results as a
separate evidence record with new source and executable hashes, identical-input
parity, declared CPU controls and its own samples. Broader sentence lengths,
complete Dart corrections, guards, Unicode/editor behavior and target-device
performance remain separate qualification gates.
