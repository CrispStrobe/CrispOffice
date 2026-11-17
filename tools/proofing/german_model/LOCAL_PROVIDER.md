# Compile and compare the guarded provider locally

The optional provider has a separate complete-check protocol from the original
unguarded reference and native-forward comparisons. It runs the persistent Dart
worker, both native heads, iterative decoding, German dictionary guards,
original UTF-16 edits and `OfficeProofingService` validation. The commands below
use explicit local inputs and do not depend on GitHub Actions.

## Prepare the exact inputs

Resolve the repository workspace with the recorded Dart/Flutter SDK, then build
and verify the [local development pack](NATIVE_PACK.md). The pack preserves the
qualified mixed GGUF, twelve frozen sidecars, separately pinned native library
and notices. Keep its paths immutable while any provider context is alive.

The complete-check runner also needs the original F32 `reference.json` from
[reference export](REFERENCE_FIXTURES.md). It authenticates the frozen corpus,
original model identity and reference case inputs before starting the worker.
The reference is development evidence; it is not an application dependency.

## Build an executable with a source receipt

From the repository root, with fresh output and receipt paths outside both the
repository and SDK:

```sh
python3 tools/proofing/german_model/build_gector_aot.py \
  --dart /path/to/dart-sdk/bin/dart \
  --source-root . \
  --output /path/to/results/guarded-provider.aot \
  --receipt /path/to/results/guarded-provider-build.json
```

The helper seals the same selected source files as the runner and separately
records resolved package dependencies, package configuration and compiler/SDK
inputs. It compiles once, checks for input changes and binds the resulting AOT
bytes to the actual runtime. Existing outputs are refused. Failure diagnostics
and a negative receipt are retained; they do not count as a successful build.
Use a writable `TMPDIR` if the environment has no system temporary directory.

## Run the complete checker through the pack

Use the model directory and library path returned by the pack verifier:

```sh
CRISPEMBED_GECTOR=1 /path/to/dart-sdk/bin/dartaotruntime \
  /path/to/results/guarded-provider.aot \
  --source-root /path/to/quds_office_suite \
  --bundle-dir /path/to/pack/model/549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b \
  --model /path/to/pack/model/549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b/gector-de-mixed-q4_k.gguf \
  --model-sha256 549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b \
  --library /path/to/pack/native/9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604/libcrispembed-gector.so \
  --library-sha256 9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604 \
  --reference /path/to/reference-f32/reference.json \
  --output /path/to/results/guarded-provider.json
```

The report keeps one warmup and three timing samples per input, actual native
thread count, setup time, peak whole-process RSS and runtime/entrypoint hashes.
It includes all 30 frozen cases, eight operational controls and three longer
structural probes. Invalid or oversized input must report failure or unsupported
coverage explicitly; an empty result is not proof that text was checked.

Operational success confirms execution and coverage. Check linguistic
nonregression separately:

```sh
python3 tools/proofing/german_model/compare_guarded_provider.py \
  --candidate /path/to/results/guarded-provider.json \
  --output /path/to/results/guarded-comparison.json
```

This comparison authenticates the original AOT v1 receipt and frozen corpus,
preserves its five accepted exact fixes and ten supported clean controls,
reports added fixes and every changed finding/span, and rejects missing or
inconsistent evidence. It does not replace the baseline with candidate outputs.
Performance budget observations remain separate from correction quality.

Before accepting a run, compare the build receipt's selected source map and
runtime/entrypoint hashes with the complete-check receipt. They must agree.
Retain the original build, provider and comparison reports together, including
failures and all timing samples.

## Compare opt-in segmented paragraphs

Run the same compiled program again with a fresh output path and the additional
argument `--segment-target-tokens 64`. Keep the first single-sequence report;
the runner never overwrites it. The receipt records the complete decoding
configuration, including the default 32-segment / 4,096-initial-token limits
and the 20,480-token bound across actual native forwards.

Both modes retain the original 30 cases, eight controls and three structural
probes. Segmented mode also measures two complete paragraphs beyond 512 logical
tokens and checks late corrections, UTF-16 offsets, protected code and whole
request rejection at each admission bound. It records the exact source
partition and separates logical original-source tokens from actual segment
input totals; per-segment terminal normalization and CLS/SEP tokens differ.

The original `operational_passed` field covers the historical cohort. Require
`segmentation_operational_passed` and `all_requested_checks_passed` as well for
an opted-in run; its process exit code requires both cohorts. The strict
comparator still authenticates the unchanged frozen panel and original v1
baseline. It does not evaluate the added long-paragraph controls, so retain
their full provider receipt alongside the comparison.

Planning, all segment forwards, guards and provider validation remain inside
each timed complete check. Timing does not measure only one native forward.
These repeated-sentence probes establish bounded execution and source coverage,
not representative long-paragraph German quality or an interactive-device SLA.

## Interpretation

The 30-case panel is synthetic and small. A successful comparison establishes
nonregression on that panel, not broad German precision/recall or intended-device
qualification. The <=64-token provisional p95 budget does not apply to the
longer structural probes. The application remains an explicit manual de-DE
provider. Segmentation is a separate host opt-in; representative long-paragraph
quality, other locales and platform/distribution acceptance remain open.
