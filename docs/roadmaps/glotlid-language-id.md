# GlotLID as an optional second language identifier — feasibility (20 November 2026)

**Decision: not implemented now.** Licence is not the blocker; the runtime
and download size are. CLD3 stays the only identifier. Nothing in this
document changes the app.

## Licence (checked 20 November 2026)

| Part | Source | Licence | App Store as downloaded data |
| --- | --- | --- | --- |
| GlotLID V3/V4 model weights | `cis-lmu/glotlid` (Hugging Face) | "Apache License 2.0 plus notices" (`LICENSE`, 13,050 bytes): the full Apache-2.0 text, plus informational notices. The notices say the training data may include copyrighted material and that its licensing status is not warranted. They also offer a good-faith exclusion contact. | Yes. Apache-2.0 allows redistribution and binary/data use. Ship `LICENSE` and the notices on the licence page. The training-data notice is a risk statement, not an extra restriction. |
| GGUF conversion | `cstr/glotlid-GGUF` (revision `846630153a3ec7aa25cf76c2b9bfbc3b539e170f`) | `apache-2.0` | Yes, on the same terms. |
| Runtime | CrispASR `crisp_lid/src/lid_fasttext.cpp` (688 lines, commit `369d7b44`) | MIT | Yes (MIT, like the CLD3 runtime we already ship). |
| Original fastText | `facebookresearch/fastText` | MIT | Yes. |

Not to be confused with Facebook **LID-176**, which is **CC-BY-SA-3.0**.
CrispASR also packages it (`cstr/fasttext-lid176-GGUF`). Its ShareAlike would
pass on to the redistributed data, so it is not a candidate.

## Runtime and size: the blockers

- A native runtime already exists. CrispASR's `lid_fasttext` reads GlotLID
  GGUF files and implements flat softmax, `</s>` row injection and fastText
  subword hashing, with recorded parity against `model.predict()`. It is the
  same source family as our CLD3 path (`quds_language_id` compiles
  `lid_cld3.cpp` with a small GGUF shim and no ggml).
- But `lid_fasttext.cpp` dequantizes rows through ggml
  (`ggml_get_type_traits()->to_float`) and uses the ggml CPU backend helpers.
  `quds_language_id` would have to compile and ship ggml-base, plus its quant
  kernels for K-quants, on every platform including Wasm. Today it ships about
  0.1 MB of C++.
- Published GGUF sizes are F16 848 MB, Q8_0 455 MB, Q5_K 298 MB and Q4_K
  246 MB. Q4_K, the smallest, falls below the converter's own 0.999 cosine
  floor on intermediate stages (top-1 is stable on its 8-sentence smoke set).
  Even Q4_K is about 560× the bundled 440 KB CLD3 model. That is too much for an
  optional mobile/web download, and for the browser it exceeds a practical
  Wasm heap.
- The compact upstream `model_v4_small.ftz` (35 MB, product-quantized fastText)
  would be acceptable, but no MIT runtime here reads `.ftz` product
  quantization. CrispASR converts only the dense `.bin`.

## What would unblock it

1. Choose a model that fits a download budget (at most about 40 MB). Options:
   convert `model_v4_small.bin` (131 MB dense, 2102 labels) to Q4_K, which
   gives about 40 MB, and record cosine/top-1 parity. Or add product-quantizer
   (`.ftz`) inference to `lid_fasttext`, which is small: per-subquantizer
   centroid lookup.
2. Add a ggml-free dequant for the chosen type to the `quds_language_id` shim
   (Q4_K/Q8_0 row decode is about 100 lines). This keeps the library free of
   ggml and Wasm-friendly, as with CLD3.
3. Package it like CLD3 (pinned GGUF digest, build receipt, notices). Make it
   an in-app download, not a bundled asset. Map GlotLID labels
   (`deu_Latn` …) to the BCP-47 tags the proofing router uses.
4. Settings: an "Identifier" choice (CLD3 default, GlotLID when installed).
   Then run the requested A/B on short mixed-language paragraphs and record
   accuracy for both before offering it.

The A/B on short mixed-language paragraphs was **not run**, because no
shippable GlotLID build exists to compare.
