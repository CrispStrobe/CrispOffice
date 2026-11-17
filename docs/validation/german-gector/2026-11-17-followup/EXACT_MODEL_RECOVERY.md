# Exact German GECToR model recovery

This recovery restores the previously measured model only when its complete bytes match the retained identity. It does not qualify a different native library, run inference, repeat the full reference evaluation, or generate performance claims. Source and model pins remain unchanged.

## Recovered inputs and expected outputs

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Pinned Proofbird source ONNX | 452,972,247 | `6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464` |
| Intermediate F32 GGUF | 453,355,328 | `497657528f3a660b85b807a7da0db663abb5964ada81f819e26ed48b6e96b6c1` |
| Mixed Q4_K GGUF | 82,756,896 | `549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b` |
| Previously measured quantizer | 915,904 | `8d38bcb36ed82e6ebae6c320ea07ff3a97343feafbc0f7c024b6c1d4c5373a46` |
| Previously measured native library | 2,064,104 | `9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604` |

The 13-file source bundle occupies 454,286,403 bytes. Keeping that bundle, the F32 intermediate and the mixed model requires 990,398,627 bytes (944.52 MiB), excluding Python dependencies, native build products and logs. Reusing an existing bundle avoids another 454 MB copy or download.

The immutable source bundle revision is `proofbird/gector-bert-de@8e3b50beef7d775cedb7b876009e88bcf2e8d6af`. Its exact filenames, sizes, hashes and URLs are in [artifacts.json](../../../../tools/proofing/german_model/artifacts.json). The recovery driver authenticates that manifest with Git blob `7e2750199183bcad22645ca1b59ee65b37a91db0`, and the converter with Git blob `1da106839d8a54eee03c724283d12ea7ba8ee3de`.

## Conversion dependencies

Use Python 3.12; the measured interpreter was 3.12.14. The conversion package versions are:

- `numpy==2.5.5`
- `onnx==1.19.1`
- `gguf==0.19.0`

The actual measured evidence recorded NumPy 2.5.5 and GGUF 0.19.0; the native reproduction README recorded ONNX 1.19.1. Older oracle requirements contain different package versions and should not silently replace these. Install into an isolated target with pip's cache disabled. The converter does not need ONNX Runtime, PyTorch, tokenizers, huggingface-hub, or the remote quickstart code.

Historical versions of the transitive protobuf, ml_dtypes, typing_extensions, PyYAML, tqdm and packaging dependencies were not all archived. The driver records the installed versions and package requirement declarations; it does not invent their historical pins. The complete F32 and final-model SHA-256 gates remain authoritative.

## Driver and stages

The versioned driver is [recover_exact_native_model.py](../../../../tools/proofing/german_model/recover_exact_native_model.py). Its independently uploaded Git blob is `b3a7385766bf14bf9182f0936082ade0ef8e579a`; readback matched the submitted 21,817 bytes. This note documents the implementation and source audit. Execution results must come from the generated receipts; no successful recovery is asserted here.

The root recovery session has already downloaded the source bundle to `/workspace/model-recovery/proofbird-bundle` and installed conversion packages at `/workspace/runtime/model-python`. The following commands illustrate that environment; use its selected Python 3.12 interpreter and the repository's actual absolute driver path.

```bash
PYTHONPATH=/workspace/runtime/model-python python3 \
  tools/proofing/german_model/recover_exact_native_model.py \
  --output /workspace/model-recovery/exact-model-v2 \
  --bundle /workspace/model-recovery/proofbird-bundle \
  --prepare-only
```

The output directory must be new. `--bundle` authenticates all 13 existing files in place; it neither copies nor downloads them. Without `--bundle`, the driver downloads them into its fresh output directory from the fixed immutable URLs. It fetches only the small pinned artifact manifest and converter when an external bundle is supplied.

The prepare stage verifies source identities, exports F32, verifies all converter manifest bindings and requires the exact F32 hash and length. The converter independently validates every stored tensor's type, shape and hash by reading the GGUF back. Package version details in the conversion manifest may differ from its original JSON identity without changing model bytes; the original manifest hash is recorded for comparison, not substituted for the model hash check.

After the native quantizer is available:

```bash
PYTHONPATH=/workspace/runtime/model-python python3 \
  tools/proofing/german_model/recover_exact_native_model.py \
  --output /workspace/model-recovery/exact-model-v2 \
  --resume \
  --quantizer /absolute/path/to/crispembed-gector-quantize
```

The original external bundle directory is retained in the first receipt. Resume validates the existing inputs and intermediate again; it does not fabricate a starting ledger or overwrite failed outputs.

By default, the supplied quantizer must exactly match the previously measured 915,904-byte binary. An explicitly reviewed new build can be used solely to attempt reconstruction of identical model bytes:

```bash
PYTHONPATH=/workspace/runtime/model-python python3 \
  tools/proofing/german_model/recover_exact_native_model.py \
  --output /workspace/model-recovery/exact-model-v2 \
  --resume \
  --quantizer /absolute/path/to/new/crispembed-gector-quantize \
  --allow-candidate-quantizer \
  --candidate-quantizer-sha256 EXACT_NEW_BINARY_SHA256 \
  --candidate-build-receipt /absolute/path/to/candidate-build.json \
  --candidate-source-dir /absolute/path/to/CrispEmbed
```

That mode requires a `quds.gector.native-build.v1` receipt binding the actual candidate binary size and SHA-256; source revision `853a1ce6089e5d5486e37307f37051ad6a928745`; ggml revision `3a27b6c665b191cb230be367db5c52d81dd3e2ac`; portable build settings; and original 112-file inventory digest `923301782b6d91bc1c55eb3d124b784ac91045af715b1a92996462ddb0ccaddf`. The driver rehashes every recorded source file, rejects paths outside the supplied source root and rechecks the seal after quantization.

The original native-build-v2 receipt names earlier source revision `85287df43a2a3951b49e4e6865c88231b3c1eeeb`, while the later measured wrapper/evidence names `853a1ce6089e5d5486e37307f37051ad6a928745`. Recovery of a new build uses its actual 853a revision and requires the unchanged original source inventory. It does not relabel a different binary as the old binary.

## Exact quantization recipe

```bash
crispembed-gector-quantize gector-de-f32.gguf gector-de-mixed-q4_k.gguf q4_k \
  --standard-file-type \
  --tensor-type '*=f32' \
  --tensor-type 'enc.*.attn.*.weight=q4_k' \
  --tensor-type 'enc.*.ffn.*.weight=q4_k' \
  --tensor-type 'token_embd.weight=q8_0' \
  --tensor-type 'position_embd.weight=f16' \
  --tensor-type 'gector.*.weight=f16' \
  --metadata-string gector.precision=mixed-q4_k
```

Order matters because later tensor overrides win. The expected 201 tensors are 72 Q4_K encoder weights, one Q8_0 token embedding, three F16 weights (position embedding and two heads), and 125 F32 tensors. `--standard-file-type` sets the retained standard GGUF file-type metadata; omitting it changes the bytes. No importance matrix is used. The driver removes inherited CrispEmbed quantization/inpainting policy environment variables for this subprocess and records their names.

The authenticated converter derives tensors from graph consumers and uses stable metadata insertion order. It does not include timestamps, local paths or random data in the GGUF. The pinned quantizer uses reference row quantization for the selected Q4_K and Q8_0 paths, but compiler differences can still affect output. Determinism is therefore established by exact output identity, not by assuming equal source produces equal bytes.

## Evidence and limitations

The driver appends and flushes `events.jsonl` after each stage, retains unique command logs and failure reports, rechecks inputs and binaries, and writes a uniquely named result receipt only after the final length and whole-file hash match. Partial downloads and failed artifacts are kept for diagnosis. A failed artifact is not silently overwritten on resume.

A recovered exact model can restore the model input to the original quality replay without running the full reference pipeline first. A different native library remains a different library and requires its own qualification; generating the exact model with a candidate quantizer does not qualify that library.

The pre-reset baseline functional replay summary is retained separately in [RECOVERY.md](quality/RECOVERY.md). Its raw archive was lost before upload. This model recovery does not recreate those lost observations or establish a final replay/performance result.

## Source audit references

- [Immutable converter at CrispEmbed 853a1ce6](https://github.com/CrispStrobe/CrispEmbed/blob/853a1ce6089e5d5486e37307f37051ad6a928745/models/convert-gector-onnx-to-gguf.py)
- [Immutable quantizer at CrispEmbed 853a1ce6](https://github.com/CrispStrobe/CrispEmbed/blob/853a1ce6089e5d5486e37307f37051ad6a928745/tools/quantize.cpp)
- [Pinned mixed model manifest](../2026-11-17-native/gector-de-mixed-q4_k.gguf.manifest.json)
- [Original native build receipt](../2026-11-17-native/native-build-v2.json)
- [Measured native evidence](../2026-11-17-native/evidence.json)
- [Native reproduction instructions](../2026-11-17-native/README.md)

The converter and quantizer source blobs were identical at the later inspected grammar commit `957ffa3bcf578daf6dda546d6f1af7c12607dc4a`. Inspected GitHub release and repository inventories did not expose an original uploaded GGUF; that observation is limited to the inspected GitHub scope.
