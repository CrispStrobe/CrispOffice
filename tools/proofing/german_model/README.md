# German grammar model qualification

For the current **in-process native** QA run, see
[the context qualification](../../../docs/validation/german-context-20261117/README.md).
`native_ort_probe.c` links the official ONNX Runtime 1.23.2 C API;
`evaluate_native_quality.dart` loads it directly in the Quds worker and verifies
model, shim and runtime hashes. It registers no application backend. The older
process-based evaluators below remain historical research tools only.

For a local F32 diagnostic run through the actual Quds worker, tokenizer,
decoder, guards and deterministic-first report merge, create an isolated Python
environment with `requirements.txt` and supply the complete pinned, verified
Proofbird v2.1.0 bundle (model and all metadata):

```sh
dart --packages=.dart_tool/package_config.json \
  tools/proofing/german_model/evaluate_guarded_onnx.dart \
  /path/to/verified-bundle /path/to/venv/bin/python \
  tools/proofing/german_model/cases.json /path/to/new-results.json
```

Run from the Quds workspace after resolving its packages. The helper starts a
bounded two-thread CPU ONNX process and verifies its model identity. It returns
real F32 logits to Quds and records model-only and shared combined-policy
results. It is an evaluation transport, not a registered application provider,
CrispEmbed FFI test, shipping-precision qualification or deployment dependency.
Model weights and the Python environment must stay outside Git. See the
[17 November comparison](../../../docs/validation/german-options-20261117/README.md)
for measured results and limits.

The feature work for an optional provider is scoped in the
[German GECToR roadmap](../../../docs/roadmaps/german-gector-proofing.md).
For exact-input runtime and quantization comparisons, see
[REFERENCE_FIXTURES.md](REFERENCE_FIXTURES.md). The additional exporter records
both classifier heads and the unchanged reference decoder's actual passes;
its output is backend evidence, not an enabled application provider.

The [hosted qualification workflow](../../../.github/workflows/german-gector-qualification.yml)
executes the original and declared INT4 models on native ORT and the pinned Dart
runtime. It is scoped to the feature branch and relevant source changes, with
bounded execution and retained failure evidence. Its JSON summary compares
runtime parity separately from quantization-induced correction changes.

This directory evaluates `proofbird/gector-bert-de` v2.1.0 at immutable revision
`8e3b50beef7d775cedb7b876009e88bcf2e8d6af`. It does not register a provider or
enable model inference in Quds Office. Document text is never uploaded by this
runner: it downloads public, pinned artifacts only when `--download` is given,
then checks the synthetic sentences in `cases.json` locally.

The original Apache-2.0 [LICENSE](vendor/LICENSE), [NOTICE](vendor/NOTICE) and
unmodified [reference runner](vendor/quickstart.py) are preserved. Every model,
tokenizer, rules, vocabulary, metadata and runner artifact has a SHA-256 digest
in [artifacts.json](artifacts.json). The 452,972,247-byte model itself is not
committed. The source model's NOTICE credits the MIT German BERT encoder and
the Apache GECToR tagging scheme. Its model card describes synthetic training
sentences derived from German Wikipedia and Tatoeba; that training-data
provenance is distinct from the publisher's Apache license for model artifacts.

## Current guarded native provider

The [optional Quds provider](../../../packages/quds_proofing_gector/README.md)
is implemented separately from the original unguarded evaluator described
below. It supports explicit manual de-DE checks through the verified native
mixed Q4_K lane. Its [local build/run/comparison guide](LOCAL_PROVIDER.md)
records complete-check execution and guarded nonregression; the
[development pack guide](NATIVE_PACK.md) assembles the exact model, sidecars,
library and notices without downloading or activating them.

The [retained native evidence](../../../docs/validation/german-gector/2026-11-17-native/README.md)
and [guarded JIT/AOT evidence](../../../docs/validation/german-gector/2026-11-17-native-dart/README.md)
keep numerical equivalence, final corrections, operational coverage and
performance observations separate. Continue local checks without waiting for
GitHub Actions; the earlier workflow remains reproducible historical evidence.

## Original unguarded evaluation reproduction

Use a separate virtual environment. These Python dependencies belong only to
the evaluation tool; they are not shipped in the Office application.

```sh
python3 -m venv .model-eval-venv
.model-eval-venv/bin/pip install -r tools/proofing/german_model/requirements.txt
.model-eval-venv/bin/python tools/proofing/german_model/evaluate.py \
  --model-dir /path/to/pinned-model --download \
  --output /path/to/german-model-evaluation.json
```

Omit `--download` to verify and reuse local artifacts. A missing or mismatched
artifact stops the run. The runner always receives that verified local path,
so its upstream default of fetching an unpinned current model is not used.

## Observed probe

The restored implementation's recorded run used ONNX Runtime 1.23.2 with the
CPU provider, tokenizers 0.22.1, and the exact upstream reference runner. It
matched the expected correction in **9 of 18** error cases, leaving the other
nine unchanged. It changed **1 of 12** valid controls: Swiss `ich heisse`
became `ich heiße`. The simple Swiss `Strasse`/`gross` control stayed unchanged.

Cold model setup took 1.331 seconds, with median sentence latency 0.075 seconds
and maximum 0.277 seconds on this host. These are one-run local measurements,
not product latency guarantees. Complete input, output, timing, package versions
and hashes are in
[the evaluation record](../../../docs/validation/proofing-20261116/german-model-evaluation.json).

This small hand-written probe is not a population accuracy estimate. In
particular it gives no basis for broad claims about German case inflection,
word order, regional spelling or free-form text. The supplied `quickstart.py`
explicitly omits the app's `gector-guards.json` logic and its OS spelling
guards. The model card's published app scores therefore do not describe this
runner. The guard data is pinned for inspection, but it is not silently
reimplemented or credited to these results.

Deterministic, reviewable German rules remain the application default. The
subsequent optional provider supplies its own conservative guards and retained
Unicode/offset/operational evidence. Broader quality, regional policies and
long-document support remain separate from the historical unguarded probe.

## Primary sources

- [Immutable model tree](https://huggingface.co/proofbird/gector-bert-de/tree/8e3b50beef7d775cedb7b876009e88bcf2e8d6af)
- [Exact model card](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/README.md)
- [Exact model LICENSE](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/LICENSE)
- [Exact model NOTICE](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/NOTICE)
- [Exact reference runner](https://huggingface.co/proofbird/gector-bert-de/blob/8e3b50beef7d775cedb7b876009e88bcf2e8d6af/quickstart.py)
