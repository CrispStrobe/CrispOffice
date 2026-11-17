# Local native German GECToR evidence — 2026-11-17

**The exact fine-tuned F32 GGUF control and the declared mixed Q4_K candidate
passed the bounded native numerical and frozen-case nonregression panel.**
Both reproduced the original runner's final text and UTF-16 suggestions on all
30 cases, with exact selected tags on all 40 saved passes. The application and
intended devices remain unqualified. These measurements used local execution;
no GitHub Actions job was launched or awaited.

[evidence.json](evidence.json) summarizes the corrected policy-v2 run.
[files.json](files.json) records every archived file's stored and uncompressed
SHA-256. Complete reports, all per-case timing samples, exact prepared inputs,
conversion censuses, failures and licenses are retained here. JSON files larger
than 100,000 bytes use deterministic gzip with an empty filename and `mtime=0`.
Weights and raw tensor buffers are excluded; their identities remain in the
complete reports and can be regenerated with the commands below.

## Frozen identities and precision

| Item | Identity |
| --- | --- |
| Source model | `proofbird/gector-bert-de`, revision `8e3b50beef7d775cedb7b876009e88bcf2e8d6af` |
| Original ONNX SHA-256 | `6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464` |
| F32 GGUF SHA-256 | `497657528f3a660b85b807a7da0db663abb5964ada81f819e26ed48b6e96b6c1` |
| Mixed Q4_K GGUF SHA-256 | `549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b` |
| Measured native library SHA-256 | `9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604` |
| Quds policy-v2 checkpoint | [`60836ce0bea770b57764cc03f44e1847a859ff88`](https://github.com/CrispStrobe/quds_office_suite/tree/60836ce0bea770b57764cc03f44e1847a859ff88) |
| CrispEmbed checkpoint containing the measured source | [`853a1ce6089e5d5486e37307f37051ad6a928745`](https://github.com/CrispStrobe/CrispEmbed/tree/853a1ce6089e5d5486e37307f37051ad6a928745) |
| ggml revision | `3a27b6c665b191cb230be367db5c52d81dd3e2ac` |

The converter uses all 201 parameters from the pinned ONNX graph, including
both trained heads. It resolves matrix identity through graph consumers and
transposes every matrix from source `[in,out]` to GGUF `[out,in]`, including
square attention matrices. The source embedding addition order, LayerNorm
epsilon, separate Q/K scaling, Erf GELU and post-softmax NaN handling are
recorded in the [F32 manifest](gector-de-f32.gguf.manifest.json.gz).

| Actual tensor census | F32 control | Mixed Q4_K |
| --- | ---: | ---: |
| F32 | 201 | 125: type embeddings, norms and biases |
| Q4_K | 0 | 72: encoder attention and feed-forward matrices |
| Q8_0 | 0 | 1: token embeddings |
| F16 | 0 | 3: position embeddings and both head matrices |
| Total GGUF bytes | 453,355,328 (432.35 MiB) | 82,756,896 (78.92 MiB) |

Every actual tensor type, shape and byte hash was read back. The
[mixed manifest](gector-de-mixed-q4_k.gguf.manifest.json) identifies its exact
F32 parent and the native quantizer. Its `gector.precision` metadata explicitly
states `mixed-q4_k`; no Q4_0 fallback is admitted. Conversion-time qualification
booleans are preserved as originally written. Subsequent execution qualification
is recorded separately in the complete reports.

## Numerical and correction results

The saved [original reference](reference-f32.json.gz) binds token IDs, masks,
token strings, word IDs, first-subword indices, both head payload hashes and
selected tags for all 40 passes. The native test replays these exact inputs and
then executes the unchanged upstream iterative decoder with only its inference
session replaced by the native C ABI. The mixed candidate is compared with both
the original ONNX outputs and its exact native F32 control.

| Saved-pass comparison with original ONNX | F32 labels | F32 detection | Mixed labels | Mixed detection |
| --- | ---: | ---: | ---: | ---: |
| Minimum per-token cosine | 0.999999999999943 | 0.999999999999731 | 0.998946845 | 0.993997065 |
| Maximum absolute error | 0.0000190735 | 0.0000057220 | 1.233072519 | 0.758199215 |
| Raw argmax mismatches | 0 | 0 | 0 | 0 |

The declared precision gate is minimum **per-token** cosine strictly above
0.99 for F32 and 0.94 for mixed Q4_K, separately for both heads. The stricter
absolute-error diagnostic remains fixed at 0.002. F32 passes that diagnostic;
mixed Q4_K fails it. The full numerical errors are retained and the tolerance
was not relaxed to turn that diagnostic into a pass. Mixed-versus-native-F32
metrics and all 13 intermediate embedding/layer comparisons are in the full
[mixed report](qualification-mixed-q4_k-policy-v2.json.gz); its lowest
intermediate per-token cosine is 0.981123539 at layer 11.

Both arms correct **9 of 18** error cases and change **1 of 12** clean controls,
exactly matching the original. There are no lost baseline fixes, new or changed
clean false edits, final-text differences, or UTF-16 suggestion differences.
The existing Swiss false edit remains: `Grüezi, ich heisse André.` becomes
`Grüezi, ich heiße André.` Nonregression does not resolve that error or establish
accuracy on real documents.

The required 64-, 128- and 256-token probes repeat prepared IDs from the first
frozen case. All required shapes and both head numerical gates pass. The mixed
candidate's worst per-token cosine across those probes is **0.998662702** for
labels and **0.993339848** for detection. Every raw head argmax also matches.
These synthetic sequences exercise shape, numerics and forward timing; they
provide no long-document linguistic-quality or iterative-correction result.

## Measured timing and memory

The local host reported Linux x86-64, nine visible logical CPUs, and AMD EPYC
9V74. The [host observation](host-observation.json) was captured after the first
run pair; its load average is not a contemporaneous measurement of either
timed pair. Both arms use two native threads, one warmup and three measurements.
The [build receipt](native-build-v2.json) records the portable compiler flags;
machine-native ISA selection is disabled.

| Corrected policy-v2 run | F32 | Mixed Q4_K |
| --- | ---: | ---: |
| Short first forward median / p95 | 26.326 / 43.383 ms | 19.477 / 35.037 ms |
| Complete unguarded correction median / p95 | 31.283 / 65.109 ms | 25.255 / 54.892 ms |
| Process peak before constructing the ONNX long-probe oracle | 515.23 MiB | 163.28 MiB |
| Later process peak including the ONNX oracle and long probes | 1,081.13 MiB | 735.12 MiB |

Each short aggregate combines 90 samples across first-pass lengths of 5–12
WordPieces. Complete correction includes upstream tokenization, iterative
inference and decoding. It excludes application guards, spelling checks and
editor work. Process RSS includes Python, validation and mapped model pages;
it is not a model-only or target-application allocation estimate.

| Prepared length | F32 forward median / p95 | Mixed forward median / p95 |
| --- | ---: | ---: |
| 64 tokens | 144.548 / 168.755 ms | 159.687 / 166.504 ms |
| 128 tokens | 232.057 / 310.383 ms | 290.053 / 338.480 ms |
| 256 tokens | 692.974 / 844.132 ms | 667.567 / 679.986 ms |

Each long p95 is the maximum of three measured samples. Shared-host variation
is visible across the retained run pairs; their samples are not pooled. The
256-token forward timings already exceed 500 ms in this rerun. The small model
and short-panel timings therefore do not qualify a 500 ms complete-checker
target, longer inputs, interactive responsiveness or intended devices.

## Policy history, failures and source sealing

The first completed reports are preserved unchanged as
[F32 policy v1](qualification-f32-policy-v1.json.gz) and
[mixed policy v1](qualification-mixed-q4_k-policy-v1.json.gz). Independent review
found three harness gaps: long numerical results did not feed the final pass;
mixed qualification did not bind its F32 baseline to the exact declared parent;
and imported policy-helper sources were not all hashed. The actual recorded
outputs already cleared the numerical thresholds.

Policy v2 freezes the required length set, gates both long head shapes and
cosines, enforces exact parent-GGUF identity, and seals the qualifier plus
`export_reference.py`, `summarize_qualification.py`, `quantize_int4.py` and
`evaluate.py`. It verifies those source hashes again before final acceptance.
The two precision arms were each rerun once with the same model bytes, native
binary and native source inventory. [Focused tests](local-tests.json) passed
38 tests and 136 subtests, including negative controls for all three gaps.
A separate read-only audit recomputed both final gates, checked coverage and
verified the exact mixed-parent/baseline/source/binary linkage.

Two earlier failures are retained: [the temporary gate-lifetime
bug](failure-f32-gate-lifetime.json) failed before a completed forward; [source
drift](failure-f32-source-drift.json) rejected a CMake packaging change after
the first build seal. The gate now stays enabled for the whole native session;
the final source inventory was resealed. The native binary hash did not change.
[Build v1](native-build-v1.json), [build v2](native-build-v2.json), and both
initial smoke reports remain available to make those events inspectable.

## Native dependency and license boundary

[native-build-and-licenses.json](native-build-and-licenses.json) records 31
compiled translation units, five resolved system libraries, installed file
hashes and 50 passing native contract checks. The standalone target contains
the GECToR implementation, existing GGUF loader, pinned ggml CPU code and
llamafile SGEMM. It excludes the parent OCR/document stack, C2PA, PDFium, other
model families, GPU/BLAS/OpenMP backends and dynamic backend loading.

The source components use MIT; the exact model/reference bundle uses
Apache-2.0 with its retained [LICENSE](proofbird-LICENSE) and
[NOTICE](proofbird-NOTICE). The native install retains
[CrispEmbed's license](CrispEmbed-LICENSE) and
[third-party notices](native-THIRD_PARTY_NOTICES). The measured GNU/Linux
binary also resolves system libstdc++/libgcc with the GCC Runtime Library
Exception and libc/libm/loader with LGPL/component notices. This is not an
all-MIT binary claim, and those system runtimes are not bundled by this target.
Other toolchains, platform closures and distributed packages need their own
qualification. ONNX Runtime remains a development oracle in these commands;
it is not installed as an application dependency by the standalone target.

## Reproduce the bounded local workflow

Use fresh output directories and the source checkpoints listed above. The
commands reproduce the inputs, precision recipe and gates. Timestamps,
timings, newly compiled binary hashes and newly sealed report hashes can differ.
Run from a work directory containing `CrispEmbed` and `quds_office_suite`
checkouts; the model and raw outputs stay outside either checkout.

```sh
python3 -m venv .venv
.venv/bin/pip install numpy==2.5.5 onnx==1.19.1 gguf==0.19.0 \
  onnxruntime==1.23.2 tokenizers==0.23.3 huggingface-hub==2.4.0 \
  cmake ninja pytest
GECTOR_QUDS="$PWD/quds_office_suite"
GECTOR_CRISP="$PWD/CrispEmbed"
GECTOR_TOOL="$GECTOR_QUDS/tools/proofing/german_model/qualify_native.py"
export PATH="$PWD/.venv/bin:$PATH"

git -C "$GECTOR_CRISP" submodule update --init ggml
cmake -S "$GECTOR_CRISP/tools/gector" -B build/gector -G Ninja \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build/gector --parallel 2
ctest --test-dir build/gector --output-on-failure

python "$GECTOR_QUDS/tools/proofing/german_model/export_reference.py" \
  --model-dir assets/proofbird --download --output-dir assets/reference-f32 \
  --threads 2 --warmups 1 --repeats 3 --onnx-census
python "$GECTOR_CRISP/models/convert-gector-onnx-to-gguf.py" \
  --bundle assets/proofbird --output assets/gector-de-f32.gguf --dtype f32
python "$GECTOR_TOOL" seal-build --source-dir "$GECTOR_CRISP" \
  --build-dir build/gector --library build/gector/libcrispembed-gector.so \
  --output assets/native-build-v2.json

python "$GECTOR_TOOL" qualify --precision f32 \
  --model assets/gector-de-f32.gguf \
  --model-manifest assets/gector-de-f32.gguf.manifest.json \
  --model-dir assets/proofbird --reference assets/reference-f32/reference.json \
  --library build/gector/libcrispembed-gector.so \
  --build-manifest assets/native-build-v2.json --source-dir "$GECTOR_CRISP" \
  --output-dir assets/native-f32-policy-v2 --threads 2 --warmups 1 --repeats 3

python "$GECTOR_TOOL" quantize --source-model assets/gector-de-f32.gguf \
  --source-manifest assets/gector-de-f32.gguf.manifest.json \
  --quantizer build/gector/crispembed-gector-quantize \
  --build-manifest assets/native-build-v2.json --source-dir "$GECTOR_CRISP" \
  --library build/gector/libcrispembed-gector.so \
  --output assets/gector-de-mixed-q4_k.gguf \
  --manifest assets/gector-de-mixed-q4_k.gguf.manifest.json
python "$GECTOR_TOOL" qualify --precision mixed-q4_k \
  --model assets/gector-de-mixed-q4_k.gguf \
  --model-manifest assets/gector-de-mixed-q4_k.gguf.manifest.json \
  --model-dir assets/proofbird --reference assets/reference-f32/reference.json \
  --library build/gector/libcrispembed-gector.so \
  --build-manifest assets/native-build-v2.json --source-dir "$GECTOR_CRISP" \
  --baseline assets/native-f32-policy-v2/qualification.json \
  --output-dir assets/native-mixed-q4_k-policy-v2 --threads 2 --warmups 1 --repeats 3

python -m pytest -q "$GECTOR_QUDS/tools/proofing/german_model/test_native_qualification.py"
python -m pytest -q "$GECTOR_CRISP/tests/test_gector_onnx_converter.py"
```

The archived reference JSON preserves all inputs and payload hashes. A fresh
export is required to regenerate the raw logits expected by the qualifier;
decompressing the JSON alone does not supply those buffers. The experimental
prepared-input native backend and this local evidence do not enable an
application default or constitute a release decision.
