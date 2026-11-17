# German syntax and newer-model evaluation

These tools run in isolated evaluation environments. Neither spaCy, Python nor
the candidate Proofbird weights become app dependencies or enabled providers.

`syntax_cases_20261117.json` was saved before syntax or v2.2 inference. It has
20 errors and 36 valid controls, including noun ambiguity, fronted objects,
coordination, relative clauses, Swiss spelling and metalinguistic cases. Scores
are finite diagnostic results, not general accuracy estimates.

## Syntax experiment

Install `requirements-syntax.txt` in a separate environment, then install the
official wheel pinned by `syntax-model.json` after checking its size and SHA-256.
Retain the wheel's MIT `LICENSE` and complete `LICENSES_SOURCES`. The publisher
lists TIGER as commercially licensed by Explosion, Tiger2Dep as a citation with
no packaged code, and WikiNER as CC-BY-4.0. Corpus terms and distributed model
terms are distinct. This evaluation is not a native app packaging qualification.

From the resolved Quds workspace:

```sh
python tools/proofing/german_model/evaluate_syntax.py \
  --model de_core_news_sm \
  --cases tools/proofing/german_model/syntax_cases_20261117.json \
  --output /path/to/new-parser-results.json

dart --packages=.dart_tool/package_config.json \
  tools/proofing/german_model/export_syntax_noun_evidence.dart \
  /path/to/new-parser-results.json /path/to/new-noun-evidence.json

python tools/proofing/german_model/evaluate_syntax.py \
  --model de_core_news_sm \
  --cases tools/proofing/german_model/syntax_cases_20261117.json \
  --noun-evidence /path/to/new-noun-evidence.json \
  --output /path/to/new-guarded-results.json
```

The syntax planner uses the existing first-party finite verb facts. Its noun
guard uses actual Quds Unicode morphology, requiring unambiguous nominative
number; it preserves every competing reading. The evidence is bound to the
case-file hash and model version. Results use Python code-point offsets, and
are not directly suitable as application UTF-16 findings.

## Pinned publisher comparison

`evaluate_candidate.py` downloads nothing. Supply the reviewed manifest and an
already downloaded bundle. It checks every listed size/hash, including the
publisher runner, before importing the runner. `candidate-v220-artifacts.json`
pins the separate v2.2.0 candidate; `artifacts.json` retains the current v2.1.0.
The same command can evaluate either by changing the manifest and bundle:

```sh
python tools/proofing/german_model/evaluate_candidate.py \
  --manifest tools/proofing/german_model/candidate-v220-artifacts.json \
  --model-dir /path/to/verified-v220-bundle \
  --cases tools/proofing/german_model/cases.json \
  --cases tools/proofing/german_model/syntax_cases_20261117.json \
  --cases tools/proofing/german_model/prospective_cases_20261117.json \
  --output /path/to/new-candidate-results.json
```

Use the isolated `requirements.txt` environment for ONNX comparisons. Both
reference versions execute unchanged with two CPU threads. The v2.2 reference
also contains its publisher's `schon/schön` rule. Neither reference supplies
the publisher app's full guards or Quds guards; scores must not be reported as
application-provider results. The reviewed Quds bundle admission still rejects
the unapproved v2.2 assets. No current model pin is silently relaxed.

The [continuation report](../../../docs/validation/german-syntax-20261117/README.md)
records the actual results and the separately implemented bounded Dart rule.
