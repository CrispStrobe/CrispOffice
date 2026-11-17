# Native spaCy source audit

Audit date: **17 November 2026**. This is a source and model-architecture audit,
with a separate account of the Python experiment already retained in Quds.
It does not report a completed native German port, device benchmark or shipping
dependency approval. See the [roadmap overview](README.md),
[architecture](architecture.md), [implementation plan](implementation-plan.md),
[validation plan](validation.md) and
[licensing and distribution review](licensing-and-distribution.md).

The documentation branch starts from Quds main
`162288351af0ad43bb4d869fd2d814eaaa30a930`. That main excludes AOT through the scope
of [PR #125](https://github.com/CrispStrobe/quds_office_suite/pull/125). The earlier
SynanDaemon/AOT work is historical; do not assume that its package or example
integration exists in the current tree. The ordinary Dart proofing rules and
the retained German syntax experiment are the current starting points.

## Conclusions for the next implementer

- **A Python-free application is feasible.** All three projects below contain
  native inference implementations. They are not Python launchers or bindings
  to an embedded CPython interpreter.
- **None of the audited revisions provides a complete German spaCy pipeline.**
  The German morphologizer and trainable edit-tree lemmatizer are decisive
  missing components. English morphology obtained through an attribute ruler
  does not establish German morphology support.
- **Among Rust alternatives, SpaRs is the first candidate to evaluate, not an approved dependency.** Its
  explicit model validation, provenance, compatibility inventory and native
  conversion tooling make it a useful starting point. Its supported language
  remains English. Reproduce its baseline before selecting a fork. The preferred
  implementation in this handoff is C++/ggml; evaluating a Rust fork is an
  alternative or reference exercise, not a required detour before that work.
- **The small German model is a hash-embedding/CNN/transition-parser pipeline.**
  It is not a BERT model and cannot become executable in an existing BERT/GGML
  loader merely by changing its weight container. GGML integration requires an
  architecture implementation and host-side linguistic logic.
- **Analysis is not correction.** A compatible parser/morphologizer supplies
  evidence to Quds grammar rules. It does not itself provide a calibrated
  grammar checker, a complete inflection generator or safe automatic edits.

These are engineering conclusions from the source and evidence below. No
native build, performance comparison or mobile qualification was performed in
this audit. No GitHub Actions jobs or status endpoints were queried or awaited.

## Audited project identities

Pin the full revisions below when reproducing this comparison. A moving
`latest` crate page or a README version label is insufficient.

| Project | Audited repository revision | Version information | Project license |
| --- | --- | --- | --- |
| [`spars-nlp` / SpaRs](https://github.com/tareksanger/SpaRs) | `604365ed01bca1ffd3ff7c73395b2691c43913f6` | Audited source manifest says `0.4.2`; indexed published docs are `0.4.0` dated 16 October 2026. The current registry's latest version was not independently resolved. Rust import name is `spars`. | MIT |
| [`spacy-rs`](https://github.com/DaniilPak/spacy-rs) | `424c0121db00b9c2a06dfa149d33b0ce6165b7cf` | Crate `0.1.0`, published 10 November 2026. Rust import name is `spacy`. | MIT |
| [`gospacy`](https://github.com/bioshock/gospacy) | `e2766da9ab71ffc55a5967a76a474046a96402bc` | Go module `github.com/bioshock/gospacy/v3`; alpha port. README and later feature inventory contain different port-version labels, so use the revision above. | MIT |

License files:
[SpaRs](https://github.com/tareksanger/SpaRs/blob/604365ed01bca1ffd3ff7c73395b2691c43913f6/LICENSE),
[spacy-rs](https://github.com/DaniilPak/spacy-rs/blob/424c0121db00b9c2a06dfa149d33b0ce6165b7cf/LICENSE),
[gospacy](https://github.com/bioshock/gospacy/blob/e2766da9ab71ffc55a5967a76a474046a96402bc/LICENSE).
These project licenses do not substitute for the dependency and model-resource
review in [licensing and distribution](licensing-and-distribution.md).

### Capability comparison at those revisions

| Surface | SpaRs / `spars-nlp` | `spacy-rs` | `gospacy` |
| --- | --- | --- | --- |
| Runtime | Rust CPU; `matrixmultiply` | Rust CPU; `matrixmultiply` | Go CPU; Gonum |
| Python required in the app | No | No | No |
| Model input | Own JSON manifest plus F32 SafeTensors | Unpacked spaCy assets, config and MessagePack weights | Unpacked spaCy assets, config and Thinc MessagePack weights |
| English neural pipeline | Declared support for `en_core_web_sm/md/lg` 3.8.0 | English small-model architecture; static vectors unsupported | English `sm/md/lg` architecture, including static vectors |
| German tokenization | Other languages explicitly unimplemented | German tokenizer data present | Non-English model load explicitly rejected |
| German morphologizer | Unimplemented | Unsupported factory | No implementation in supported pipeline |
| German edit-tree lemmatizer | Unimplemented | Unsupported; rule/lookup lemmatizers only | Unsupported; rule/lookup lemmatizers only |
| Transformer inference | Unsupported | Unsupported | Unsupported |
| Training | Unsupported | Unsupported | Unsupported |
| GGML or ONNX inference dependency | None in inference manifest | None in inference manifest | None in Go module/backend path |
| Qualified Quds German or mobile deployment | None | None | None |

### SpaRs: strongest candidate for a bounded evaluation

The actual [inference Cargo manifest](https://github.com/tareksanger/SpaRs/blob/604365ed01bca1ffd3ff7c73395b2691c43913f6/crates/spars/Cargo.toml)
lists `serde`, `serde_json`, `thiserror`, `fancy-regex`, `sha2`, `safetensors`
and `matrixmultiply`. There is no CPython, PyO3, ONNX or GGML dependency there.
The [neural implementation](https://github.com/tareksanger/SpaRs/blob/604365ed01bca1ffd3ff7c73395b2691c43913f6/crates/spars/src/neural.rs)
implements affine operations, normalized maxout, token feature hashing,
optional static-vector projection, residual window encoding and transition
scoring in Rust. This is an independent implementation of the numerical and
linguistic runtime, not a wrapper around Python.

Its [model format](https://github.com/tareksanger/SpaRs/blob/604365ed01bca1ffd3ff7c73395b2691c43913f6/docs/MODEL_FORMAT.md)
is a JSON manifest with `weights.safetensors`, containing F32 row-major
parameters. The manifest also carries tokenizer exceptions/patterns,
Unicode and lexical tables, hash features/seeds, layer definitions,
labels/actions, attribute rules, lemma tables and vector mappings. Format v2
declares language and architecture capabilities; unknown or missing
capabilities fail loading. SafeTensors is only the tensor container.

The separate Rust installer can convert its **catalog-selected official
English 3.8.0 wheels without Python**. The actual
[converter](https://github.com/tareksanger/SpaRs/blob/604365ed01bca1ffd3ff7c73395b2691c43913f6/crates/spars-model/src/convert.rs)
decodes Thinc/NumPy parameters, verifies dimensions and an exact reference
weight digest, writes the manifest and SafeTensors, and copies model notices.
Its [dependencies](https://github.com/tareksanger/SpaRs/blob/604365ed01bca1ffd3ff7c73395b2691c43913f6/crates/spars-model/Cargo.toml)
and [installation contract](https://github.com/tareksanger/SpaRs/blob/604365ed01bca1ffd3ff7c73395b2691c43913f6/docs/MODEL_INSTALLATION.md)
keep acquisition outside the inference crate. Python remains useful for
development exports, reference generation and adding support for a new model;
it need not ship in the application. The converter is not a general importer
for arbitrary spaCy architectures or German pipelines.

The [compatibility inventory](https://github.com/tareksanger/SpaRs/blob/604365ed01bca1ffd3ff7c73395b2691c43913f6/docs/COMPATIBILITY.md)
explicitly marks other languages, morphologizer, edit-tree lemmatizer,
transformers and training as unimplemented. English NER, parser and matcher
support is substantial but deliberately partial. The declared English
reference suite contains 190 documents / 7,029 tokens and requires exact
discrete outputs; those are upstream results, not tests rerun for Quds.
The [loader validation](https://github.com/tareksanger/SpaRs/blob/604365ed01bca1ffd3ff7c73395b2691c43913f6/crates/spars/src/validation.rs)
and model format check shapes, types, finite values, compatible dimensions and
capabilities. This explicit contract is a reason to evaluate it first; it does
not establish mobile memory/latency, German correctness or production maturity.

### spacy-rs: direct model loading, narrower and newer

The [Cargo manifest](https://github.com/DaniilPak/spacy-rs/blob/424c0121db00b9c2a06dfa149d33b0ce6165b7cf/Cargo.toml)
and [native neural source](https://github.com/DaniilPak/spacy-rs/blob/424c0121db00b9c2a06dfa149d33b0ce6165b7cf/src/models/nn.rs)
confirm a Rust implementation with its own hashing, matrices/maxout,
normalization, window expansion and parser affine operations. The
[loader](https://github.com/DaniilPak/spacy-rs/blob/424c0121db00b9c2a06dfa149d33b0ce6165b7cf/src/models/mod.rs)
reads ordinary spaCy model assets and recognizes `tok2vec`, `tagger`, `parser`,
`ner`, `attribute_ruler`, rule/lookup `lemmatizer`, `sentencizer` and
`entity_ruler` factories. It does not recognize German `morphologizer` or
`trainable_lemmatizer`. German tokenizer resources therefore do not make the
default German pipeline loadable.

The [model acquisition script](https://github.com/DaniilPak/spacy-rs/blob/424c0121db00b9c2a06dfa149d33b0ce6165b7cf/tools/fetch_model.sh)
downloads and unpacks a wheel using archive tools; no Python interpreter is
needed for runtime inference. Developer-side Python utilities produce reference
fixtures and language resources. Static vectors, transformer architectures and
training are outside the inspected implementation.

Read the [parity test](https://github.com/DaniilPak/spacy-rs/blob/424c0121db00b9c2a06dfa149d33b0ce6165b7cf/tests/model_parity.rs)
before treating a green test invocation as evidence: it returns successfully
when model assets or generated fixtures are missing, and the comparisons admit
small mismatch tolerances. The published package excludes those assets. Quds
must make missing fixtures a failure in its own acceptance run and state the
actual tested token/document counts. The numerical source also relies on valid
model shapes for indexing and matrix operations; review model validation before
exposing a model-loading FFI boundary.

### gospacy: useful independent implementation, additional runtime choice

The [Go module](https://github.com/bioshock/gospacy/blob/e2766da9ab71ffc55a5967a76a474046a96402bc/go.mod)
and [bundle loader](https://github.com/bioshock/gospacy/blob/e2766da9ab71ffc55a5967a76a474046a96402bc/bundle/bundle.go)
confirm a Go/Gonum pipeline reading spaCy configuration and Thinc weights. It
does not call Python. `bundle.FromDisk` rejects `nlp.lang != "en"`; the wired
pipeline is tokenizer/tok2vec, tagger, parser, English attribute ruler,
rule/lookup lemmatizer and NER. NER has a separate encoder. It contains no
German morphologizer/edit-tree implementation that can be enabled by merely
changing the language check.

The [feature inventory](https://github.com/bioshock/gospacy/blob/e2766da9ab71ffc55a5967a76a474046a96402bc/NOT_YET_PORTED.md)
documents CPU/English scope, unimplemented transformer and training features,
and a BLIS/cgo backend scaffold rather than a qualified alternative backend.
It records that only Linux/amd64 execution was tested. The
[README](https://github.com/bioshock/gospacy/blob/e2766da9ab71ffc55a5967a76a474046a96402bc/README.md)
reports exact tag/POS/morphology/lemma/head/dependency parity on eight fixture
sentences, 68 tokens; the inventory says the larger parser differential is not
part of that acceptance contract. These are narrow upstream claims, not a
German or mobile evaluation. No advertised speedup was measured here.

The loader also documents that a `Bundle` cannot be used concurrently for
inference without separate instances/clones. A Flutter integration would need
its own ABI, lifetime/concurrency contract and platform packaging, including the
Go runtime. It is a useful comparison/reference implementation, but adopting it
would add a language/runtime choice beyond the requested Rust/C++/Dart paths.

The inspected loader can also mark unsupported architectures, missing model
files, or deserialization failures as `Skipped` and continue with partial
annotations. A Quds implementation must require the declared analysis
capabilities and fail explicitly when a required component is unavailable.

## Exact German model target

Use the official **`de_core_news_sm` 3.8.0** release as the initial port target.
Do not silently replace it with an unversioned Hugging Face `main` snapshot:
the inspected `main` configuration elsewhere in this research was not a
reliable substitute for the exact 3.8.0 archive.

### Three different artifact identities

| Object | Identity | Meaning |
| --- | --- | --- |
| Official `de_core_news_sm-3.8.0` wheel | SHA-256 `fec69fec52b1780f2d269d5af7582a5e28028738bd3190532459aeb473bfa3e7`; **14,639,490 bytes** | Model package used by the existing Quds Python experiment |
| Official `de_core_news_sm-3.8.0.tar.gz` | SHA-256 `06960052d5346291f94fb1c928bccd4898e46ea0f5953758f30348653ad66045`; **14,641,307 bytes** | Release archive inspected during this research for the exact model configuration; a different container from the wheel |
| Quds `evidence.tar.gz` | SHA-256 `4588f810d12ebd30dff19beb08ad596a636b437836a670cf6de892d143bf97ca` in the retained index | Experiment evidence, notices and receipts; **not model weights or a Python environment** |

Sources: [official release](https://github.com/explosion/spacy-models/releases/tag/de_core_news_sm-3.8.0),
[official tar.gz asset](https://github.com/explosion/spacy-models/releases/download/de_core_news_sm-3.8.0/de_core_news_sm-3.8.0.tar.gz),
[versioned model metadata](https://github.com/explosion/spacy-models/blob/master/meta/de_core_news_sm-3.8.0.json),
and the Quds [experiment](../../validation/german-syntax-20261117/README.md)
and [evidence index](../../validation/german-syntax-20261117/evidence-index.json).
Preserve these distinct identities when adding a converted native artifact.
The archive-derived configuration below was inspected during the research;
this documentation change adds no downloaded model/code assets.

### Configuration that the native implementation must reproduce

The archive's configured order is:

```text
tok2vec, tagger, morphologizer, parser, lemmatizer,
senter, attribute_ruler, ner
```

`senter` is disabled in the default pipeline. A complete claim about the active
pipeline must account for the other seven components; a smaller intentionally
selected pipeline must declare its exact component set.

| Component | Exact inspected 3.8.0 configuration relevant to inference |
| --- | --- |
| Shared `tok2vec` | `spacy.Tok2Vec.v2`; width **96** |
| Embedding | `spacy.MultiHashEmbed.v2`; attributes `NORM`, `PREFIX`, `SUFFIX`, `SHAPE`, `SPACY`, `IS_SPACE`; table rows `[5000, 1000, 2500, 2500, 50, 50]`; **no static vectors** |
| Encoder | `spacy.MaxoutWindowEncoder.v2`; depth **4**, window size **1**, maxout pieces **3** |
| Tagger | `spacy.Tagger.v2`, `normalize = false`, shared `spacy.Tok2VecListener.v1` |
| Morphologizer | `spacy.Tagger.v2`, `normalize = false`, shared listener; labels must be interpreted as morphological analyses/POS according to the component semantics |
| Parser | `spacy.TransitionBasedParser.v2`; `state_type = parser`, `extra_state_tokens = false`, hidden width **64**, maxout pieces **2**, `use_upper = true`; shared listener |
| Lemmatizer | Factory `trainable_lemmatizer`; `spacy.Tagger.v2` with shared listener; `backoff = orth`, `min_tree_freq = 3`, `overwrite = false`, `top_k = 1` |
| Sentence recognizer | Present in configuration but disabled by default |
| Attribute ruler / NER | Active components; preserve model-defined rules and NER decoding if claiming the full active pipeline |

Shared neural layers make part of this port reusable. The remaining work is
not just matrix multiplication: morphological label assignment, edit-tree
application and fallback, German tokenization/lexical behavior, parser action
legality/deprojection and exact source offsets have their own semantics.
Do not substitute English rule lemmatization for the trained German edit trees
and call it parity.

The source anchors for those semantics are the upstream
[morphologizer](https://github.com/explosion/spaCy/blob/v3.8.18/spacy/pipeline/morphologizer.pyx),
[trainable lemmatizer](https://github.com/explosion/spaCy/blob/v3.8.18/spacy/pipeline/edit_tree_lemmatizer.py),
and [edit-tree implementation](https://github.com/explosion/spaCy/blob/v3.8.18/spacy/pipeline/_edit_tree_internals/edit_trees.pyx).
The existing Quds Python evaluation used **spaCy 3.8.18**. SpaRs's English
reference uses spaCy 3.8.14 / Thinc 8.3.13, so record and resolve reference-version
differences when constructing native acceptance fixtures instead of assuming
that all 3.8 runtimes are identical.

### Other official German 3.8.0 choices

The sizes below are **publisher-rounded metadata values**, not measured resident
memory, converted bundle size or app download impact. Each model has its own
artifact identity and resources; MIT metadata does not eliminate its source
notices.

| Model | Publisher size | Published model license | Architectural consequence |
| --- | ---: | --- | --- |
| [`de_core_news_sm`](https://github.com/explosion/spacy-models/blob/master/meta/de_core_news_sm-3.8.0.json) | 13 MB | MIT | Small CNN pipeline, no static vectors; initial target |
| [`de_core_news_md`](https://github.com/explosion/spacy-models/blob/master/meta/de_core_news_md-3.8.0.json) | 42 MB | MIT | CPU pipeline plus static-vector resources; separate export/parity/memory work |
| [`de_core_news_lg`](https://github.com/explosion/spacy-models/blob/master/meta/de_core_news_lg-3.8.0.json) | 541 MB | MIT | Much larger static-vector resources; not an automatic mobile improvement |
| [`de_dep_news_trf`](https://github.com/explosion/spacy-models/blob/master/meta/de_dep_news_trf-3.8.0.json) | 391 MB | MIT | German BERT-based dependency pipeline; separate transformer, token alignment and task-head integration |

The transformer metadata describes German cased BERT, width **768**, WordPiece
vocabulary **30,000**, window **176** and stride **136**. Even where a GGML engine
already supports a related BERT encoder, the spaCy token alignment, overlapping
window aggregation and downstream linguistic heads remain integration work.
It is a separate option, not a substitute artifact for the small CNN target.
Current CrispEmbed source/pins and the engine boundary belong in
[architecture](architecture.md).

## Existing Quds experiment: useful, limited and not native validation

The retained [German syntax report](../../validation/german-syntax-20261117/README.md)
and [reproduction instructions](../../../tools/proofing/german_model/SYNTAX_EVALUATION.md)
already contain a real Python spaCy 3.8.18 run of the pinned German wheel. Its
statistical annotations feed a separately authored agreement planner using
Quds's finite verb facts. This evidence must not be relabeled as SpaRs,
`spacy-rs`, Go, GGML, mobile, quantized or shipping-app validation.

- On the 56-sentence syntax panel, the initial prototype produced **15/20
  target fixes**, but changed **1/36 valid controls**, misreading singular
  `Leiter` as plural.
- Corroborating noun number with the actual Dart morphology preserved **15/20
  fixes** and reduced changed controls to **0/36**. That guard was authored
  after observing the failure; this is not independent validation on that panel.
- On the separate 76-case panel it produced **0/32 fixes, 0/44 controls changed**;
  on the original 30-case panel, **2/18 fixes** and no changed controls. These
  results show a narrow noun-agreement prototype, not general grammar quality.
- Regional support is recorded separately. Absence of a finding is not proof
  that a locale or sentence was fully supported.

The [evidence index](../../validation/german-syntax-20261117/evidence-index.json)
binds the retained outputs, dependency metadata, wheel receipt and original
notices. It identifies the frozen corpus and tested runtime commits. The model
license is MIT; its source notices separately identify TIGER, Tiger2Dep and
WikiNER. The Python dependency review applies to that evaluation environment,
not the eventual native app's linked dependency closure. No training corpus is
redistributed by this documentation.

## Handoff decisions and remaining uncertainty

**Audited:** the three revisions above, their source-level runtime/model
boundaries, explicit German gaps, the exact small German model configuration,
and the already retained Quds Python evidence.

**Proposed:** implement the bounded C++/ggml pipeline described in the
architecture and implementation plan, using the audited ports as optional
implementation references. Preserve an independent Python reference only in
development, implement the German semantics, expose a bounded native API to
Dart, and qualify the resulting artifact. SpaRs is the preferred Rust option
to evaluate if reconsidering that implementation boundary, not a prerequisite
for the C++ route. This documentation does not vendor or enable a dependency
or model in an application.

**Still to establish:** an actual reproducible native build; full German
numerical/discrete parity (and the existing English baseline if adopting a
Rust fork); tokenizer and Unicode-offset
behavior; malformed-model handling; FFI ownership/cancellation/concurrency;
iOS/Android/macOS/other target builds; peak memory and latency on representative
devices; grammar quality on prospective error/control panels; and the precise
license/notice closure of the final distributed binary and assets. Follow
[implementation-plan.md](implementation-plan.md) and [validation.md](validation.md)
for acceptance work. Do not use an upstream README benchmark, a skipped asset
test or the Python experiment as a substitute for that evidence.
