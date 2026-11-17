# German GECToR: local INT4 optimization observations

Date: 2026-11-17. **All four local observations passed the same tokenizer,
dual-head and selected-tag parity checks. The complete checker remains
unqualified.** The final opt-in run measured median forward times of **1.357061 s
and 1.408750 s** on the two short inputs. Its faster unconditional prototype and
its slower repeat are both retained here.

[evidence.json](evidence.json) preserves the original report/status hashes,
complete timing samples, every reported RSS field, per-pass parity metrics,
operator profiles, source identities and executable hashes. It includes no
weights, raw tensor buffers or private filesystem paths. The original
[local baseline](https://github.com/CrispStrobe/quds_office_suite/tree/28cbbe4e780460736bdacccb798be9005aae3d14/docs/validation/german-gector/2026-11-17-local-smoke) is frozen at Quds commit
`28cbbe4e780460736bdacccb798be9005aae3d14` and is not revised by this record.

## Scope and fixed inputs

All observations use the identical 158,365,857-byte INT4 candidate, tokenizer and
native reference fixture:

| Artifact | SHA-256 |
| --- | --- |
| INT4 model | `6c92deb88469e2fce2ddded5159014200d8681a7853722714224539a48285d70` |
| Original F32 model | `6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464` |
| Tokenizer | `45253db94c657c7b89880de2c8872e10cd0561577e9393e1f5f4df27b0165087` |
| Saved INT4 reference fixture | `6d7c2e29bdc44dceaf1c75a76d7dc105c566945aacdbcdaff569c46e19f52db5` |

The model is [Proofbird v2.1.0 at the frozen revision](https://huggingface.co/proofbird/gector-bert-de/tree/8e3b50beef7d775cedb7b876009e88bcf2e8d6af)
`8e3b50beef7d775cedb7b876009e88bcf2e8d6af`. The
[evaluation source](https://github.com/CrispStrobe/quds_office_suite/tree/6bd03365ba3b146586148658b0e03998b36bdc9d/tools/proofing/german_model) is Quds commit
`6bd03365ba3b146586148658b0e03998b36bdc9d`. The candidate uses ONNX `MatMulNBits`, 4 bits,
block size 128, symmetric quantization and accuracy level 0. Its 72 encoder
matrices were quantized; the label and detection heads retain their original
FP32 weights. This is **ONNX INT4**, not GGUF/ggml Q4_K.

The two cases are `verb-du` and `clean-swiss-name`, selected from the frozen
30-case set. Their first passes contain **7 and 10 wordpieces including special
tokens**. Validation replays all four saved passes; the final Swiss pass has
9 pieces after the model's edit. The oracle is native ORT 1.23.2 CPU output for
the **same candidate file**. Original F32 logits are not the INT4 parity oracle.

## Two hypotheses, four retained observations

| Observation | Runtime source | Configuration |
| --- | --- | --- |
| Original | [`0b49ca47fa05`](https://github.com/CrispStrobe/onnx_runtime_dart/commit/0b49ca47fa056e6fc122ffe0192a9abb05627622) | Full FP32 dequantization matrix, standard GEMM |
| First tile hypothesis | [`6988d46f3978`](https://github.com/CrispStrobe/onnx_runtime_dart/commit/6988d46f3978643076f27a340deb5ccc737458d7) | Reuse at most 32 dequantized columns, standard GEMM packing |
| Second hypothesis prototype | Uncommitted one-file patch from `6988d46f3978` | Same tiles, hardcoded `narrowDirect: true` |
| Final opt-in integration | [`b10258682d45`](https://github.com/CrispStrobe/onnx_runtime_dart/commit/b10258682d459847b63e012eaaba58a528e93956) | Existing `narrowDirectGemm` experiment, explicitly enabled |

The first hypothesis reduces full `K × N` reconstruction scratch to `K × 32`
and reuses the small tile buffers. It also fixes packed zero-point row alignment
for an odd number of blocks. The symmetric model used here does not exercise
explicit packed zero points, so these model observations do not validate that
specific correctness case.

The second hypothesis reuses an existing kernel that can read eligible narrow,
contiguous tiles directly; its existing shape and alignment guards preserve the
fallback path. The prototype enabled the hint inside `MatMulNBits`. The final
integration routes the existing **disabled-by-default** model experiment to that
operator and adds a strict `--narrow-direct true|false` benchmark option. The
measured final command uses `--narrow-direct true`; the runtime default remains
off. This integration is part of the same second hypothesis, not a third tuning
change.

The prototype has **no commit identity**. Its exact small patch, the base and
resulting source hashes, and its own executable hash are retained below and in
the JSON. The other source-file hashes were checked against the pinned git
objects.

## Every warm timing sample

Values below are seconds, in the recorded execution order. Each case used one
warmup and three measured replays of its first saved input.

| Observation | Case / pieces | All measured samples, seconds | Median | Recorded p95 |
| --- | --- | --- | ---: | ---: |
| Original | `verb-du` / 7 | 2.066489, 1.896172, 1.857285 | 1.896172 | 2.066489 |
| Original | `clean-swiss-name` / 10 | 2.435666, 2.146931, 1.962191 | 2.146931 | 2.435666 |
| 32-column tiles | `verb-du` / 7 | 1.841738, 2.680373, 1.514148 | 1.841738 | 2.680373 |
| 32-column tiles | `clean-swiss-name` / 10 | 2.267543, 1.396697, 1.891854 | 1.891854 | 2.267543 |
| Unconditional prototype | `verb-du` / 7 | 0.974301, 1.170080, 1.058874 | 1.058874 | 1.170080 |
| Unconditional prototype | `clean-swiss-name` / 10 | 1.373020, 1.252059, 1.246554 | 1.252059 | 1.373020 |
| Final opt-in | `verb-du` / 7 | 1.746766, 1.013142, 1.357061 | 1.357061 | 1.746766 |
| Final opt-in | `clean-swiss-name` / 10 | 1.408750, 1.364842, 1.433395 | 1.408750 | 1.433395 |

The narrow-direct observations have lower medians than the original local run.
The final opt-in observation is slower than the unconditional prototype, so the
prototype's best result is not substituted for the committed configuration's
measurement. Three samples on this shared, noisy host do not establish a stable
speedup. The recorded nearest-rank p95 is simply the largest of three samples.

These timings cover **one forward only**. They exclude tokenizer work, hashes,
reference-buffer reads and decoding. All timed cases and the separate profile
completed before raw reference arrays were loaded for validation. The complete
iterative correction, application guards and editor work were not executed in
Dart. Even the smallest median in this table exceeds the provisional **500 ms
complete-check** budget; this record cannot qualify that budget.

## Startup, memory and resource controls

The machine was Linux x86-64, reporting 9 logical CPUs; its CPU model was not
recorded. All four commands used CPU affinity **0 and 1**, niceness **+10**, a
**90-second CPU limit**, **180-second wall limit** and **3 GiB RSS stop threshold**.
All exited successfully. Dart 3.14.0 AOT used two GEMM workers. That setting is
not the total process thread count: `MatMulNBits` remains on the caller isolate,
and its scheduling is not equivalent to ORT's intra-op thread setting.

| Observation | Graph load, s | Pool setup, s | First forward, s | Inference peak RSS, bytes | Post-validation peak RSS, bytes | Wrapper sampled peak RSS, bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Original | 1.920356 | 0.096215 | 2.287918 | 488,251,392 | 488,251,392 | 474,324,992 |
| 32-column tiles | 2.566236 | 0.152249 | 2.266107 | 476,790,784 | 476,790,784 | 475,869,184 |
| Unconditional prototype | 2.930210 | 0.043634 | 1.145363 | 467,263,488 | 478,588,928 | 478,846,976 |
| Final opt-in | 3.620643 | 0.040753 | 1.682866 | 463,605,760 | 481,816,576 | 477,925,376 |

The report's inference peak is a whole-process high-water mark through the
inference phase, including earlier startup, hashing and loading. It is not
weights-only allocation. Post-validation peaks include later validation work.
The wrapper samples RSS over the process lifetime and can miss brief peaks; its
maximum is a separate metric. The JSON retains all before/after-load,
after-pool, checkpoint and lifetime measurements. Hash verification can warm
the filesystem cache, so loading and the first forward are not a cold-disk test.
These processes also omit the running editor.

## Separate operator profiles and parity

Each arm profiled one extra `verb-du` first pass outside the warm sample loop.

| Observation | Profile wall, s | Operator total, s | 72 `MatMulNBits` calls, s |
| --- | ---: | ---: | ---: |
| Original | 2.029402 | 2.024952 | 1.964629 |
| 32-column tiles | 1.757374 | 1.735963 | 1.627959 |
| Unconditional prototype | 1.052419 | 1.038673 | 0.982869 |
| Final opt-in | 1.181183 | 1.177089 | 1.083830 |

The JSON retains every operator's count and duration. `MatMulNBits` remains the
largest measured contributor after both hypotheses.

Each arm completed **2 timed cases and 4 validated passes**. Token IDs and word
alignment, both `logits_labels` and `logits_d`, raw selected tags and thresholded
tags all passed the unchanged numerical and exact-decision gates. Every raw and
thresholded tag mismatch count is zero. Across these reports, the minimum head
cosine is approximately `0.9999999999997654`, and the maximum absolute head error
is `2.288818359375e-5`. All four reports retain identical logged error metrics;
this statement does not claim that unretained actual output buffers were
compared byte for byte across arms.

The fixed reference pair contains the intended `geht` → `gehst` correction and
the existing `de-CH` false edit `heisse` → `heiße`. Runtime parity preserves that
model error. This is neither a clean-control pass nor a German accuracy estimate.

## Executable and prototype provenance

| Observation | AOT executable SHA-256 |
| --- | --- |
| Original | `85860b03fcf0d4b3067653a357343b6300342b2bc7bf20576a2dfbb0b58be452` |
| 32-column tiles | `be96cdc3ae64465563218dd1a8988a85479a46085fd81a6d358613e4654a1b0d` |
| Unconditional prototype | `8b2bf4f1948f11d4aa74635d6316fcc37da24941befbcdb19084d06e5d257523` |
| Final opt-in | `648c7928f5a4b19bd09d0d7fd17b3d7c2963da363e0f0aa0bbb5b0d8c447cf9c` |

The prototype's `lib/src/onnx_qlinear_ops.dart` changes from SHA-256
`1d9f7c2637626ec4011e713a4b5cefb30f648c32bc5f90354e204e331c0710df` to
`04aa3c1ec131e3c623cab91d819253913dcd5217bc5a22815c442fa0a264875f`. The following UTF-8/LF
unified diff has SHA-256 `8492e41951ba11fb9ff69e5b55aafa10dc9a210ba9a11e06f098efb9a67d2f5f`:

```diff
--- a/lib/src/onnx_qlinear_ops.dart
+++ b/lib/src/onnx_qlinear_ops.dart
@@ -182,7 +182,12 @@
     // The scalar/web kernel accumulates into its output. Reset the reused
     // buffer even though the native SIMD path overwrites every element.
     if (firstColumn != 0) tileOut.fillRange(0, m * width, 0);
-    gemm.matmulKernel(af, 0, bt, 0, tileOut, 0, m, k, width);
+    // A reconstructed tile is already narrow and contiguous. The native
+    // kernel can read aligned tiles directly; its existing guards retain the
+    // packed/remainder path for unsupported shapes or alignment. Web ignores
+    // this hint and keeps the scalar accumulation path.
+    gemm.matmulKernel(af, 0, bt, 0, tileOut, 0, m, k, width,
+        narrowDirect: true);
     if (!identical(tileOut, out)) {
       for (int row = 0; row < m; row++) {
         out.setRange(row * n + firstColumn, row * n + firstColumn + width,
```

The final benchmark invocation has the following normalized form; its exact
relative argument list and original status-file hash are in the JSON:

```sh
build/gector_benchmark_tiled_optin \
  --model candidate/model.int4.onnx \
  --tokenizer model/tokenizer.json \
  --fixtures reference-int4/reference.json \
  --report dart-int4-tiled-optin.json \
  --warmup 1 --iterations 3 --workers 2 --narrow-direct true
```

## Remaining qualification

The updated full hosted run, pinned to `b10258682d459847b63e012eaaba58a528e93956` with the
experiment explicitly enabled, is **pending review in this record**. No updated
run ID or successful result is inferred. Local and hosted samples come from
different machines and must remain separate; cross-host ratios would not isolate
the kernel change.

Broader sentence lengths, the full frozen case set, an independently implemented
Dart correction and guard loop, Unicode/editor behavior and target-device
performance remain qualification gates. No Rust/FFI backend, CrispEmbed/ggml
execution, Q4_K model or shipping Quds provider is qualified by these four local
observations.
