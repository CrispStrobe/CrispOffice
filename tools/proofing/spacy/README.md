# Native spaCy reference tooling

This directory implements the **development oracle and fixture contract** for
the [native spaCy handoff](../../../docs/roadmaps/native-spacy/README.md).
Python runs only in this developer workflow. These files are not application
dependencies and are not a native inference backend.

The selected model is the official `de_core_news_sm` **3.8.0** wheel,
14,639,490 bytes, SHA-256
`fec69fec52b1780f2d269d5af7582a5e28028738bd3190532459aeb473bfa3e7`.
Obtain that exact artifact from the [publisher release](https://github.com/explosion/spacy-models/releases/tag/de_core_news_sm-3.8.0)
outside the exporter. It never downloads anything. It verifies the complete
wheel before extracting model data, and loads the data directory without
importing the model wheel's Python package.

## Scope and frozen cases

`fixtures/cases.json` was authored before native implementation. It separates
16 development inputs from 8 untouched acceptance inputs. The development
reference contains **113 tokens, 244 parser transitions and 1,201 numerical
stages**. Empty text is one explicit case; it has zero tokens and no executed
CNN/parser stages. A run consisting only of empty input cannot qualify.

The inputs cover German ambiguity, repeated source substrings, abbreviations,
URLs, emails, punctuation, CRLF, nonbreaking whitespace, umlauts, sharp S,
soft hyphens, NFC/NFD, supplementary scalars, emoji/ZWJ, mixed scripts, unknown
words, a long token and embedded NUL. Malformed scalar strings are rejected by
separate model-free controls. These cases test implementation parity, not
grammar correctness, general language accuracy or mobile performance.

Do not run acceptance inputs while tuning the native implementation. If their
results are inspected to fix a port, report that use and classify those results
as development evidence. Existing Quds grammar panels remain separate and are
not relabeled as unseen data.

## Reproduce the reference

Use **CPython 3.12.14** and the hash-pinned
`tools/spacy/requirements-reference.txt` from the paired CrispEmbed branch.
It freezes spaCy **3.8.18**, Thinc **8.3.14**, NumPy **2.4.6**, the converter's
GGUF package and their dependencies. The exporter checks every installed
transitive runtime dependency against the supplied lock. Extra build tools
are excluded from the runtime identity. The exact lock bytes are retained in
the capture, so it can be reproduced after branches move.

Install the lock in a separate developer environment with hash checking:

```sh
uv venv --python 3.12.14 /path/to/oracle
uv pip sync --python /path/to/oracle/bin/python --require-hashes \
  /path/to/CrispEmbed/tools/spacy/requirements-reference.txt

/path/to/oracle/bin/python tools/proofing/spacy/export_reference.py \
  --wheel /path/to/de_core_news_sm-3.8.0-py3-none-any.whl \
  --environment-lock /path/to/CrispEmbed/tools/spacy/requirements-reference.txt \
  --cases tools/proofing/spacy/fixtures/cases.json \
  --split development --output /path/to/new-reference
```

The exporter fixes CPU execution and one numerical thread. It refuses to
overwrite existing output. A successful manifest is published only after every
case, every required stage, ordinary-pipeline comparison and notice copy succeeds.
The reference preserves the source order:
`tok2vec → tagger → morphologizer → parser → lemmatizer → attribute_ruler`.
NER is explicitly excluded; `senter` stays disabled.

The actual upstream source tag is
[`release-v3.8.18`](https://github.com/explosion/spaCy/tree/43311999028032fd81bef77a75fdb4fa96803c98),
not `v3.8.18`. The Thinc source is
[`v8.3.14`](https://github.com/explosion/thinc/tree/e617de4ea2530c7091ea2110e011807c33c366f0).
Their exact revisions and installed runtime versions are recorded in the
manifest. The older handoff's spaCy source links use the wrong tag spelling;
the model/runtime selection is unchanged.

## What is captured

Each case retains original text, exact half-open UTF-8 byte, Unicode scalar
and UTF-16 token spans, whitespace, lexical values, selected POS/tag/morphology,
lemma, dependency head/label and sentence boundaries. Source reconstruction
must be exact. All uint64 string/label IDs are decimal strings, including
parser arc labels; nothing passes through a floating-point integer conversion.

Six lexical feature columns are in the trained order `NORM`, `PREFIX`,
`SUFFIX`, `SHAPE`, `SPACY`, `IS_SPACE`. Seeds are 8 through 13. Each feature has
four embedding buckets, with row counts `[5000,1000,2500,2500,50,50]`.

Each `case.json` maps named stages to slices in its sibling `traces.f32`:

| Stages | Shape for N tokens |
| --- | --- |
| `tok2vec.embed.concat` | `[N,576]` |
| `tok2vec.embed.affine` | `[N,96,3]` |
| `tok2vec.embed.maxout`, `.norm` | `[N,96]` |
| `tok2vec.encoder.input` | `[N+8,96]` |
| `tok2vec.encoder.layer.{0..3}.window` | `[N+8,288]` |
| Each layer's `.affine` | `[N+8,96,3]` |
| Each layer's `.maxout`, `.norm`, `.residual` | `[N+8,96]` |
| `tok2vec.output` | `[N,96]` |
| `tagger.scores`, `morphologizer.scores`, `lemmatizer.scores` | `[N,55]`, `[N,671]`, `[N,1311]` |
| `parser.reduce`, `parser.lower_cache` | `[N,64]`, `[N+1,8,64,2]` |
| `parser.step.{i}.sum`, `.hidden`, `.scores` | `[1,64,2]`, `[1,64]`, `[1,137]` |

The four padding rows on each side evolve through all four residual layers;
they must not be reset between layers. Every slice declares shape, byte offset,
byte length, SHA-256, little-endian F32 and C/row-major order. Full arrays are
retained, not rounded summaries. The complete stage data occupies about 5.6 MB.

Parser steps include feature indices, legal-action masks, chosen class/name,
stack, queue and existing arcs. Reconstructed pre-maxout sums must equal the
source hidden vectors after maxout exactly. Lemma decisions retain predicted
class/tree, applicability, fallback and applied lemma. The attribute ruler's
matched rules, pre-ruler annotations and final annotations are separate.

Instrumentation uses the actual source operators and parser APIs. Its complete
annotations must equal ordinary spaCy C greedy execution exactly on every case;
its final shared vectors must be bit-exact. This verifies the reference observer,
not a native implementation.

## Verify and compare without Python model dependencies

The integrity checker and tests use only the Python standard library:

```sh
python3 tools/proofing/spacy/verify_reference.py \
  --reference tools/proofing/spacy/fixtures/development \
  --cases tools/proofing/spacy/fixtures/cases.json

python3 -m unittest discover -s tools/proofing/spacy/tests -v

python3 tools/proofing/spacy/compare_reference.py \
  --first /path/to/first-reference --second /path/to/second-reference \
  --cases tools/proofing/spacy/fixtures/cases.json \
  --report /path/to/new-repeatability-receipt.json
```

Missing fixtures, missing/extra stages, bad shapes, invalid spans, changed bytes,
truncation, nonfinite floats, invalid action masks, duplicate JSON keys, path
escapes, symlinks, omitted notices and zero denominators are failures. No test
skips because the model or fixture is absent. Model-free controls verify data
admission; they do not run inference.

Independent oracle exports are compared byte-for-byte across the complete
inventory. Native numerical qualification uses the predeclared elementwise
budget `abs(candidate-reference) <= 2e-4 + 2e-5*abs(reference)`, with finite
values and exact discrete decisions required. Report maximum and mean error
at every stage and find the earliest divergence; do not widen the budget or
edit goldens after observing a native failure. The native differential driver
lives with the CrispEmbed standalone implementation. Tokenization, decoding,
native linguistic output and editor integration require their own qualification.

## Notices

The captured `LICENSE` and `LICENSES_SOURCES` are copied byte-for-byte from the
verified model. They retain the model's MIT grant and source disclosures,
including TIGER, Tiger2Dep and WikiNER. This is not permission to redistribute
the original training corpora. Source code/model distribution and mobile
packaging remain separate from these reference results.
