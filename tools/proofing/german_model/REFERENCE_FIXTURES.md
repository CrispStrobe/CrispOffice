# Exact-input backend qualification

`export_reference.py` observes the existing pinned `vendor/quickstart.py` runner.
It does not change its tokenization, decoding, evaluation cases, or expected
corrections. The runner still omits application guards. Matching its output is
a backend parity result, not evidence that the model is good enough to enable
in the editor.

## Produce a reference

Use the existing pinned `requirements.txt`, then run:

```sh
python tools/proofing/german_model/export_reference.py \
  --model-dir /tmp/proofbird-v2.1.0 \
  --download \
  --output-dir /tmp/gector-reference \
  --warmups 2 --repeats 10 --threads 2
```

The default is all 30 existing cases and every actual correction pass (at most
five per case). `--case-id verb-plural --case-id clean-simple` selects a short
initial probe without changing the source cases. `--eval-dir` supports running
the exporter from a separate checkout. `--source-revision` records the exact
evaluation repository revision supplied by CI. Output must be a new or empty
directory.

The exporter reuses `evaluate.py`'s `REVISION` and `digest()` helper. That script
does not expose a downloader, so the exporter downloads only missing files from
the same manifest after verifying every URL is pinned to that revision. It
checks both size and SHA-256 before publishing a downloaded file. Existing
incorrect files cause an error; the tool does not replace them. The vendored
runner must match its manifest hash.

Save `reference.json` and the accompanying binary tensors together as CI
artifacts. Model weights and generated fixtures do not belong in the repository.

## Fixture schema, version 1

All JSON keys are snake case. The top-level fields include:

| Field | Meaning |
| --- | --- |
| `schema_version`, `kind` | `1`, `quds-gector-reference` |
| `model`, `revision` | Pinned model repository and immutable revision |
| `inference_model` | Actual inference model's `file`, `variant`, `sha256`, `size_bytes`, `source_model_sha256` |
| `input_sha256` | SHA-256 of every model bundle file, keyed by filename |
| `manifest_sha256`, `cases_sha256` | Exact source inputs to this export |
| `exporter_sha256`, `evaluator_sha256`, `source_revision` | Evaluation source provenance |
| `decoder` | `keep_label_id`, `incorrect_label_id`, `keep_confidence`, `min_error_prob` |
| `runtime` | Python/package versions, platform, CPU count and ORT session settings |
| `setup_seconds` | Runner construction, including config/tokenizer/session load |
| `setup_peak_process_rss_bytes`, `peak_process_rss_bytes` | Whole-process peak resident memory, or null on unsupported hosts |
| `warmups`, `repeats` | Timing controls, also recorded in the consuming benchmark |
| `cases` | Selected source cases, results and observed per-pass tensors |

Each case retains its source `id`, `input`, `kind`, `expected` and other source
fields. It adds `corrected`, the original `suggestions_codepoints`, and separately
converted `suggestions_utf16`. Each UTF-16 suggestion has `start`, exclusive
`end`, `original`, and `replacement`. Tokenizer offsets are relative to individual
pretokenized words; they are not document positions.

Every case contains a `passes` array. Each pass contains:

| Field | Meaning |
| --- | --- |
| `words` | Pretokenized words submitted to the tokenizer, without `$START` |
| `tokens`, `word_ids`, `tokenizer_offsets` | The unchanged upstream tokenizer's output |
| `first_subword_indices` | Token indices used for word-level labels; includes token 0 for `[CLS]` / `$START`, excludes `[SEP]` and subsequent subwords |
| `input_ids`, `attention_mask` | Nested int64 arrays shaped `[1, T]`; the reference mask is all ones |
| `outputs.logits_labels`, `outputs.logits_d` | Binary tensor descriptors described below |
| `selected.label_ids` | Per-first-subword argmax after the keep bonus, before probability thresholds |
| `selected.thresholded_label_ids` | Label IDs after per-label and sentence detection thresholds |
| `selected.labels` | Tags after per-label and sentence detection thresholds; checked against the unchanged runner's tags |
| `selected.label_probabilities`, `selected.incorrect_probabilities` | Full-precision Python floats converted from float32 probabilities |
| `selected.sentence_incorrect_probability` | Maximum selected detection probability |
| `reference_decoding` | The upstream runner's pass trace, including words/tags/applied edits/result |
| `reference_inference_seconds` | Observed `session.run()` time for that real pass, excluding serialization |

Both tensor descriptors contain `dtype: float32`, `byte_order: little`,
`layout: row-major`, a `shape` array, a relative `file` name, `size_bytes`, and
`sha256`. The files contain raw IEEE-754 little-endian float32 values without a
header. Expected shapes are `[1,T,5000]` and `[1,T,2]`. Verify file size and SHA-256
before decoding. The consumer must verify the actual inference model hash against
`inference_model.sha256` before running it. `input_sha256['model.onnx']` identifies
the original pinned bundle even when the inference model is a derived candidate.

For a derived INT4 candidate, additionally pass `--inference-model` and
`--candidate-manifest`. The sidecar must have `schema_version: 1`,
`kind: quds-gector-int4-candidate`, `status: passed`, the pinned
`source_model_sha256`, and an `output` containing its exact `file`, `sha256` and
`size_bytes`. Its `recipe` is preserved in `inference_model`. The candidate
oracle runs that exact ONNX file while retaining the pinned tokenizer, labels
and original decoder. The two reference directories must remain separate.

## Timing and parity

Each case's `reference_first_pass_benchmark` runs its first-pass input directly
through the original CPU ORT session, after the requested warmups. Its
`samples_seconds`, `median_seconds`, nearest-rank `p95_seconds` and
`maximum_seconds` exclude tokenization, edit decoding and tensor serialization.
First observations of the real iterative passes are recorded separately. ORT's
thread settings are reported. The exporter defaults to two intra-op threads,
one inter-op thread, and sequential execution, injecting only session settings
while leaving the vendored runner unchanged. Peak RSS includes Python and
dependencies, not only weights.

`reference_correction_benchmark` additionally times the original complete
iterative `correct()` call after removing both export observers. It uses the
same warmup/repeat counts and records the same timing fields. Its final text and
suggestions must be stable across repeated runs. These timings include
tokenization and edit decoding but do not include model loading or fixture I/O.

The Dart consumer should time the same exact first-pass tensors, with the same
warmup/repeat counts, using an AOT build on the same host. Read reference tensor
files outside timed sections. Validate both raw heads and selected tags for
every saved pass. Report maximum/mean error and tag disagreements separately;
a similar embedding cosine score is not a grammar decoder parity check.
Retain token ID and word alignment comparisons when the Dart tokenizer is added.

For INT4, runtime parity compares Dart to the INT4 ORT reference, not to F32 raw
logits. Compare the two models' first-pass tags and final edits separately to
measure quantization effects. Later iterative passes can follow different word
sequences, so raw-logit comparisons across models are valid only for identical
input IDs and masks. Neither a first-pass benchmark nor numerical parity alone
is a complete grammar-checker qualification.

These short cases test exact runtime compatibility first. They do not measure
interactive paragraph performance, cancellation, Unicode edit mapping, regional
false-positive rates, or quantized model quality. Add those qualification gates
without changing these frozen reference inputs. Quantization can change tag
rankings even when aggregate numerical error is small.

## Optional architecture census

With `onnx` installed, pass `--onnx-census` to additionally write
`onnx-census.json`. It records config fields, graph inputs/outputs, operator
counts, initializer names/types/shapes, and node connections. It does not write
tensor weights into JSON. Use this artifact to map the exact two classifier
heads for a native backend; do not infer head names from a generic BERT model.

Q4_K is a ggml quantization format. It is not ONNX int4/`MatMulNBits`; a Q4_K
experiment needs a ggml/GGUF conversion and corresponding native kernels.
Evaluate any native or quantized export against the same exact inputs and
full edit behavior, then separately evaluate guarded quality.

## Lightweight checks

```sh
python -m unittest discover -s tools/proofing/german_model -p 'test_export_reference.py'
```

These tests use tiny synthetic arrays and temporary files. They check pinned
artifact integrity, safe download failure, unchanged logits, first-subword
alignment, threshold semantics, float32 serialization and UTF-16 conversion.
They do not download or execute the real model.
