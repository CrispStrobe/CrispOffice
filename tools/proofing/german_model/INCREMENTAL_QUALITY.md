# Measure the model's added value over deterministic German proofing

`run_incremental_quality.dart` checks an explicit local corpus with the actual
German spelling/writing providers and the verified native GECToR worker. It
uses the same `mergeOfficeProofingReports` policy as the editor's manual/F7
lane. It downloads nothing and does not enable a model in the application.

## Modes and interpretation

The runner records four modes for each unchanged request snapshot:

| Mode | Providers |
| --- | --- |
| Writing only | The validated `GermanWritingRulesProvider` result |
| Deterministic | `GermanSpellingProvider` followed by `GermanWritingRulesProvider`, matching the editor default |
| Model only | The actual guarded native GECToR provider |
| Combined | Deterministic results merged with model results using the shared editor policy |

All findings, alternatives and provider statuses remain in the receipt. The
model cannot replace an overlapping deterministic finding. The report also
identifies accepted and suppressed model proposals so that model-only fixes
are not automatically credited as additional editor corrections.

Findings are suggestions for individual review. For reproducible comparison,
the tool additionally projects a diagnostic corrected string with an explicit
single-pass, first-replacement policy. It never chooses a replacement because
it matches the expected answer. Overlaps and suggestions without replacements
are recorded separately. This projection is a measurement convention, not an
automatic correction mode or a simulation of every possible user choice.

Exact-target fixes, changed clean text and flagged clean text are different
measures. An exact-target miss can still be a grammatical alternative and needs
inspection. Unavailable/failed/unsupported model results must never count as a
successful clean model check. Keep the de-DE quality cohort separate from
de-AT/de-CH availability controls and retain each mode's coverage.

## Inputs

Use the [verified native development pack](NATIVE_PACK.md) and resolve the Dart
workspace with its pinned SDK and dependency lock. The model and native
library hashes must be supplied explicitly, as in [the provider guide](LOCAL_PROVIDER.md).

The original `cases.json` remains the 30-row regression panel. The separately
frozen `prospective_cases_20261117.json` contains 76 rows, described in
[PROSPECTIVE_CASES.md](PROSPECTIVE_CASES.md). It was authored, independently
reviewed and saved remotely before any provider outputs for it were inspected.
Both are synthetic development panels; neither estimates representative German
accuracy or establishes absence from model training data.

The build helper's `incremental-quality` target binds the executable to its
selected sources, resolved dependencies and SDK. The runtime receipt also
binds the declared corpus bytes and records before/after source hashes. Build
and output files must use fresh paths outside the source tree. Preserve failed
attempts and partial receipts rather than replacing them with a later run.

This is a quality comparison with one check per case. Its elapsed times are
observations, not a new latency benchmark or a target-device qualification.
The optional model remains manual de-DE-only, with native distribution,
regional model support, representative quality and long-text coverage as
separate acceptance work.

## Reproduce a compiled comparison

From the repository root, using fresh paths for the build and each run:

```sh
python3 tools/proofing/german_model/build_gector_aot.py \
  --target incremental-quality \
  --dart /path/to/dart-sdk/bin/dart \
  --source-root /path/to/quds_office_suite \
  --output /path/to/results/quality.aot \
  --receipt /path/to/results/quality-build.json

CRISPEMBED_GECTOR=1 /path/to/dart-sdk/bin/dartaotruntime \
  /path/to/results/quality.aot \
  --source-root /path/to/quds_office_suite \
  --cases /path/to/quds_office_suite/tools/proofing/german_model/cases.json \
  --bundle-dir /path/to/pack/model/549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b \
  --model /path/to/pack/model/549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b/gector-de-mixed-q4_k.gguf \
  --model-sha256 549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b \
  --library /path/to/pack/native/9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604/libcrispembed-gector.so \
  --library-sha256 9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604 \
  --output /path/to/results/frozen-quality.json
```

Repeat the last command with `prospective_cases_20261117.json` and a different
output file for the second panel. Compare the build's `source_files` with the
run's map after removing `declared-corpus`; executable and entrypoint hashes
must also match. The corpus hash and its normalized declarations are preserved
separately in each run. Status-contract and source-stability failure make the
command fail while retaining its partial receipt.

The first runs at `7808a871` and the spelling repairs informed by them are
retained in the [continuation evidence](../../../docs/validation/german-proofing-next-20261117/README.md).
Measurements after those repairs use the same immutable corpus and are
development regression results; they are not a new prospective sample.
