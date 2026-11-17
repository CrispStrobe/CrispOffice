# Proposed native spaCy architecture

Status: implementation proposal, 17 November 2026. This document does not add a
native model, provider or enabled application feature. It was written against
Quds `main` at `162288351af0ad43bb4d869fd2d814eaaa30a930`. Read the
[handoff](README.md), [source audit](source-audit.md),
[validation plan](validation.md) and
[licensing and distribution review](licensing-and-distribution.md) together.

## Intended result

Implement the inference subset of the pinned German `de_core_news_sm` 3.8.0
pipeline in a small C++ component using CrispEmbed's GGML dependency. Expose it
to an optional Dart package through a C ABI. The installed application must
perform analysis locally, with **no Python runtime, no SynanDaemon and no
automatic HTTP fallback**. Python may be used in isolated developer tooling
to convert a verified model and generate reference outputs; that tooling is
outside the installed runtime.

The first native capability is contextual tokenization, POS tags, morphology,
lemmas, sentence boundaries and dependency relations for German. A separate,
conservative Dart planner may turn selected annotations into reviewable
grammar findings. Analysis, correctness of a grammar rule, and generation of
a replacement form are separate responsibilities.

The current default branch excludes the earlier AOT work. The AOT branch at
historical head `e37ccdb` is reference material, not a prerequisite to restore
or a package available on this base. In particular, a spaCy backend must not
pretend to return AOT morphological paradigms, all possible readings, phrase
groups or alternative parses. The proposed result represents the contextual
analysis that the selected spaCy pipeline actually computes.

## Existing integration points

These are existing source files, not proposed additions:

| Existing source | Contract to preserve |
| --- | --- |
| [`office_proofing.dart`](../../../packages/quds_office_engine/lib/src/proofing/office_proofing.dart) | `OfficeProofingRequest` is an immutable document/block/revision/text snapshot. A request may cover a segment with a nonzero UTF-16 `startOffset`. `OfficeProofingProvider.check` returns explicit success, unavailable, unsupported or failed status. |
| [`OfficeProofingFinding.forRequest`](../../../packages/quds_office_engine/lib/src/proofing/office_proofing.dart) | Takes offsets relative to `request.text` and adds `startOffset` exactly once. Findings retain the original source text and contain proposals, not automatic document edits. |
| [`mergeOfficeProofingReports`](../../../packages/quds_office_engine/lib/src/proofing/office_proofing.dart) | Validated findings from the primary service keep precedence; overlapping secondary proposals are suppressed without concealing provider status. Reports must refer to the identical request. |
| [`WordProofingSession`](../../../packages/quds_office_editor/lib/src/proofing/word_proofing.dart) | `configureManual` owns already-loaded manual providers. `checkNow` includes them for explicit checks; typing debounce calls it with `includeManualProviders: false`. Cache and result validity include document, revision, locale, provider configuration and paragraph snapshot. |
| [`WordEditorController`](../../../packages/quds_office_editor/lib/src/embed/office_controller.dart) | `checkDocumentProofing()` delegates to the existing session. Correction checks source identity, grapheme boundaries, protected ranges and content controls, then uses the command/undo path. |
| [`GectorProofingProvider`](../../../packages/quds_proofing_gector/lib/src/provider.dart) | An existing example of an optional, preloaded, manual provider with explicit locale and operational failure handling. It is not a spaCy implementation. |
| [`GECToR worker`](../../../packages/quds_proofing_gector/lib/src/worker_native.dart) | Demonstrates isolate ownership, bounded pending work, request coalescing, stale-call completion and shutdown. Preserve the distinction between completing an old caller and releasing its still-running native slot. |
| [`GECToR native backend`](../../../packages/quds_proofing_gector/lib/src/native_backend.dart) | Demonstrates artifact verification, native resource ownership and immutable mapped model files. Its desktop dynamic-library installation policy is not automatically the appropriate iOS loading mechanism. |
| [`GermanNounMorphology`](../../../packages/quds_office_engine/lib/src/proofing/german_morphology.dart) and [`German writing rules`](../../../packages/quds_office_engine/lib/src/proofing/german_writing_rules.dart) | Existing noun alternatives and reviewed finite-verb facts can corroborate a bounded agreement rule. Do not discard alternative noun readings because the model chose one analysis. |

For the example host, inspect the current Review command in
[`suite_workspace.dart`](../../../packages/quds_office_editor/example/lib/suite_workspace.dart)
and the existing proofing dialog. A new analysis view is an addition to this
current host, not an assumption that an old AOT dialog is present.

## Native engine boundary

The audited CrispEmbed main revision is
[`b34a132c6c204b71f5c58ba8bc1705b8769edb9b`](https://github.com/CrispStrobe/CrispEmbed/tree/b34a132c6c204b71f5c58ba8bc1705b8769edb9b).
Its GGML submodule is `CrispStrobe/ggml` at
`3a27b6c665b191cb230be367db5c52d81dd3e2ac`. Recheck these identities when work
resumes; they describe the audited sources, not a floating dependency policy.

Reuse the existing
[`core/gguf_loader.h`](https://github.com/CrispStrobe/CrispEmbed/blob/b34a132c6c204b71f5c58ba8bc1705b8769edb9b/src/core/gguf_loader.h)
for metadata, tensor loading, backend ownership and optional mapping, and the
GGML execution primitives for tensor computation. A GGUF file is a container;
the engine still needs a graph builder and native algorithms for its declared
architecture. Current CrispEmbed's
[`build_encoder_graph`](https://github.com/CrispStrobe/CrispEmbed/blob/b34a132c6c204b71f5c58ba8bc1705b8769edb9b/src/crispembed.cpp)
implements transformer encoders, not the small spaCy CNN.

Use the historical Quds GECToR target as the dependency-boundary precedent:
[`tools/gector/CMakeLists.txt`](https://github.com/CrispStrobe/CrispEmbed/blob/853a1ce6089e5d5486e37307f37051ad6a928745/tools/gector/CMakeLists.txt)
at `853a1ce6089e5d5486e37307f37051ad6a928745` compiles the dedicated model source,
shared GGUF loader and pinned GGML CPU dependency without configuring the
parent OCR/document stack. Its
[`graph and C ABI`](https://github.com/CrispStrobe/CrispEmbed/blob/853a1ce6089e5d5486e37307f37051ad6a928745/src/gector.cpp)
are specific to Proofbird BERT and its two classifiers. These GECToR files are
absent from the audited current-main source directory; they must not be
described as current-main spaCy support.

Start with an analogous small CPU target and F32 weights. A separate graph
builder is preferable to disguising spaCy as BERT metadata or routing it into
the generic transformer initializer. Reuse build machinery and well-defined
helpers rather than linking every optional engine. The exact compiled source
set, linked runtimes and notices must accompany each distributed build.

### Proposed files and ownership

**Every path in the following table is proposed and does not yet implement
this feature.** Names are a concrete starting layout for the next agent.

| Proposed location | Responsibility |
| --- | --- |
| CrispEmbed `src/spacy_pipeline.h` and `src/spacy_pipeline.cpp` | Versioned C ABI, verified model admission, context/result ownership and pipeline execution. Split internal tokenizer, graph and decoder sources as they grow. |
| CrispEmbed `tools/spacy/CMakeLists.txt` | Small standalone native build with an explicit dependency set; CPU first. |
| CrispEmbed `models/convert-spacy-to-gguf.py` | Developer-only export of the pinned inference graph, tensors, lexical assets, labels, parser moves and edit trees with a manifest. |
| Quds `packages/quds_proofing_spacy/lib/src/analysis.dart` | Provider-neutral linguistic request/result types, source spans and capabilities; no AOT-shaped compatibility objects. |
| Quds `packages/quds_proofing_spacy/lib/src/bundle.dart` and `backend.dart` | Artifact/schema identity, declared capabilities and an injectable backend contract. |
| Quds `packages/quds_proofing_spacy/lib/src/native_backend.dart` | Platform-specific native binding, result validation and byte-to-UTF-16 mapping. Keep FFI imports outside the portable public library. |
| Quds `packages/quds_proofing_spacy/lib/src/worker_native.dart` | Isolate-owned native context, bounded queue, cancellation/staleness protocol and explicit disposal. |
| Quds `packages/quds_proofing_spacy/lib/src/provider.dart` and `german_agreement.dart` | Manual `OfficeProofingProvider` adapter and separately testable guarded agreement planner. |
| Quds `tools/proofing/spacy/` | Developer reference export, comparison and receipt tooling; never an application dependency. |
| Quds `packages/quds_office_editor/example/lib/studio_linguistic_analysis.dart` | Proposed optional selected-text/document analysis view using the neutral result types. |

Keep the initial analysis types in the optional package. Move them to a shared
engine module only when an actual second consumer requires that boundary.
Provide an unsupported native-platform stub rather than importing `dart:ffi`
into the web build. A later Wasm backend would be a separately qualified target.

## Exact first-model scope

The official `de_core_news_sm` 3.8.0 configuration was inspected in the publisher
archive. Its identity, license and retrieval sources are in the
[source audit](source-audit.md). The existing Quds Python experiment pins the
wheel in [`syntax-model.json`](../../../tools/proofing/german_model/syntax-model.json).
Export from that verified distribution rather than assuming a moving model
card's configuration is identical.

| Component | Pinned configuration / required implementation |
| --- | --- |
| Tokenizer | German language defaults, exceptions and prefix/suffix/infix/token-match behavior, plus source-preserving whitespace handling. |
| Shared embedding | `spacy.Tok2Vec.v2` with `spacy.MultiHashEmbed.v2`; width 96; attributes `NORM`, `PREFIX`, `SUFFIX`, `SHAPE`, `SPACY`, `IS_SPACE`; table rows `[5000, 1000, 2500, 2500, 50, 50]`; no static vectors. |
| Shared contextual encoder | `spacy.MaxoutWindowEncoder.v2`; width 96, depth 4, window size 1, three maxout pieces. |
| Tagger | `spacy.Tagger.v2`, `normalize = false`, shared `Tok2VecListener.v1`. Export exact tag labels. |
| Morphologizer | The same classifier architecture and listener; export the trained classes and exact POS/morphology mapping. |
| Dependency parser | `spacy.TransitionBasedParser.v2`, parser state, `extra_state_tokens = false`, hidden width 64, two maxout pieces, `use_upper = true`, shared listener. |
| Lemmatizer | `factory = trainable_lemmatizer`, classifier/listener architecture, `backoff = orth`, `top_k = 1`, `overwrite = false`; exported edit trees. `min_tree_freq = 3` is part of the source configuration, not a reason to rebuild trees in the app. |
| Attribute ruler | Preserve the exported matching/assignment rules and their pipeline order. Do not silently omit it even if an initial sample appears unaffected. |
| Sentence recognizer | `senter` is disabled in this pipeline. The parser supplies sentence boundaries for the initial scope. |
| NER | Excluded from the proposed first capability set. It has separate model work and is unnecessary for the agreement experiment. |

Preserve the enabled source order: shared tok2vec, tagger, morphologizer,
parser, lemmatizer, attribute ruler. Compare against the same reference
component selection. Disabling NER does not imply permission to remove model
attribution or source notices.

### Tokenization and lexical features

Current CrispEmbed
[`tokenizer.h`](https://github.com/CrispStrobe/CrispEmbed/blob/b34a132c6c204b71f5c58ba8bc1705b8769edb9b/src/tokenizer.h)
supports WordPiece, BPE and SentencePiece. None implements the small German
spaCy tokenizer. Existing Unicode/regex helpers are candidates for reuse only
after comparison with the pinned spaCy semantics.

Port the tokenization algorithm and serialize its language-specific data.
Freeze attribute definitions, string hashing, integer widths, hash seeds and
embedding-row selection. Preserve exact handling of accents, combining marks,
case, punctuation, abbreviations, URLs, whitespace and unknown words. A
reasonable-looking replacement tokenizer changes both source boundaries and
learned features and therefore is not an inference port.

### Tensor graph

Implement hash embedding lookup/combination, concatenation and the trained
projection, then the window expansion, affine transforms, maxout,
normalization and residual structure defined by the pinned spaCy/Thinc model.
Export dimension order, bias layout, normalization epsilon and window padding
explicitly. Do not reconstruct these details from layer names alone.

GGML provides the necessary building blocks for this small network; maxout can
be composed from supported operations or implemented as a bounded native
kernel. Confirm operation support on the pinned backend. Training dropout and
gradient/update logic are outside runtime scope. The shared tok2vec output
should be computed once per analysis unit and consumed by its listeners.

First match F32 CPU outputs. Quantization and GPU offload are later recipes,
each requiring its own evidence. A 96-wide CNN and small sequential parser
scorer do not by themselves establish that GPU dispatch is beneficial.

### Dependency and lemma decoding

The parser requires the native transition system around its neural scorer:
state features, legal-action masks, source action ordering and tie behavior,
state updates, sentence-break handling and dependency reconstruction,
including the source's nonprojective reconstruction behavior where used. A
per-token argmax of head indices is not the same algorithm. Export the exact
move inventory and trained labels; German dependency labels must not be
silently rewritten as Universal Dependencies labels.

The lemmatizer predicts an edit-tree class and applies that tree to the source
token according to applicability and fallback rules. Export the tree data and
implement its application; an argmax label or a lowercased token is not the
resulting lemma. The attribute ruler must then run at its declared position.
See the primary
[parser](https://spacy.io/api/dependencyparser),
[edit-tree lemmatizer](https://spacy.io/api/edittreelemmatizer) and
[architecture](https://spacy.io/api/architectures) documentation, with the
versioned source pins in the source audit.

## Native and Dart contracts

The following names are **proposed API concepts, not callable functions**:

- `crispembed_spacy_abi_version`, `crispembed_spacy_create`,
  `crispembed_spacy_analyze`, `crispembed_spacy_result_free` and
  `crispembed_spacy_free` form a narrow C ABI using opaque handles and explicit
  lengths/statuses. Never expose C++ containers across FFI.
- `SpacyBackendFactory.open(SpacyVerifiedBundle)` returns a backend with an
  immutable artifact identity and declared pipeline capabilities.
- `LinguisticAnalysisRequest` carries the original text, document/block
  identity, revision, locale, segment origin and request generation.
- `LinguisticAnalysisResult` carries that identity, status/coverage, model and
  runtime identity, tokens, sentence spans and dependency relations. Each
  token contains a source span, surface, lemma, POS, detailed tag, morphology,
  head token index and dependency label, where supported.

Use caller-owned or explicitly released result storage with documented
lifetimes. Invalid schema, shapes, counts, indices or non-finite numbers must
fail without publishing partial successful output. Serialize calls on a
context; do not free it while a native call or result view is in use. Check
allocation arithmetic and size limits before allocating output buffers.

Return a contextual selected analysis. If diagnostic classifier scores are
exposed, label them as scores; do not present them as calibrated probabilities,
complete morphological alternatives or a correctness guarantee. Missing
capabilities must be explicit, not empty fields that imitate success.

### Exact source coordinates

Use an explicit UTF-8 byte length at the native input boundary, so embedded
NUL does not truncate a source snapshot. Reject ill-formed UTF-16 before Dart
conversion and invalid UTF-8 at the C boundary. Native token spans are
half-open byte offsets into that unchanged UTF-8 input. Keep source text and
lexical normalization separate.

The Dart binding builds a byte-boundary-to-UTF-16 map from the original
snapshot. Validate every returned span at scalar boundaries, require its
surface to equal the original slice, and map it exactly once. Public analysis
tokens use offsets relative to the request text. Grammar findings pass these
relative offsets to `OfficeProofingFinding.forRequest`; that constructor adds
the segment's `startOffset`.

Token boundaries suitable for analysis are not automatically safe correction
boundaries. The planner and existing editor must also enforce grapheme
boundaries, source equality, protected spans and editing constraints. Never
recover failed alignment by substring search, nearest-offset clamping or
normalizing the document text in place.

Whole-document analysis should preserve separate logical block snapshots and
their story identities. Do not concatenate unrelated stories and then guess
offsets. If limits require per-block analysis, expose that scope and validate
it against a reference run with the same units. Arbitrarily cutting a long
sentence changes parser context; reject an over-limit unit explicitly until
a qualified segmentation policy exists.

## Manual grammar and analysis UI

Add the optional `SpacyProofingProvider` to `configureManual` only after its
bundle and native runtime are loaded. Preserve the ordinary deterministic
provider as the primary report, with the existing merger controlling overlap.
Use distinct provider/rule IDs, stable ignore/restore labels and configuration
identity covering model, runtime, rules, locale and vocabulary revisions.
The existing F7/document-check and correction/undo flows remain authoritative.
The typing timer must not start neural analysis.

The proposed analysis view should offer an explicit selected-text or document
action, show the original tokens and available annotations, allow navigation
back to current source spans, and make cancellation and stale-result state
visible. Selecting a token must not require exposing unsupported AOT
paradigms. Body-only coverage, omitted stories, unsupported locales or units
rejected by limits must remain visible.

Start grammar scope with the bounded noun-subject/finite-verb agreement
experiment already documented in
[the syntax report](../../validation/german-syntax-20261117/README.md).
Corroborate noun number with the existing morphology, retain all competing
readings and abstain on unresolved/unknown readings. The valid singular
`Die Leiter steht ...` is a required regression case. Preserve coordination,
fronted-object, relative-clause, quotation and unsupported-context controls.

Use reviewed finite-verb forms to propose replacements. The evaluation script
extracts its 57 paradigms from Dart source; production code must instead use a
reviewed shared data/API boundary, not parse source files at runtime. A small
behavior-preserving extraction may be necessary. Do not claim an unrestricted
inflection generator. Broader case/adjective rules require their own analysis,
form-generation and false-positive evidence.

Initial grammar qualification is `de-DE`. Preserve `de-AT`, `de-CH`, historical
orthography and unknown locales as unsupported for this provider until
separately qualified; another existing provider may still support them.
Analysis-only regional coverage, if offered, needs its own explicit capability
and must not silently enable grammar suggestions.

## Cancellation, limits and platform behavior

Run inference in a worker isolate; retain one owned native context and bound
queued snapshots and output sizes. Coalesce obsolete requests by document,
block and segment key. Changing the document, language, provider, model,
vocabulary or ignored rules invalidates earlier results before display or
correction. Disposal/replacement must invalidate pending calls immediately.

A synchronous FFI call does not become interruptible because a cancellation
message was sent to its busy isolate. First guarantee immediate rejection of
stale results and bounded queued work. If prompt compute interruption is
required, design a safe native cancellation token reachable while inference
runs, checked between substantial stages and parser transitions. Document
the worst observed cancellation latency. Do not destroy resources beneath a
running graph or assume isolate termination has safely interrupted C++.

Declare limits for UTF-16 input, native bytes, tokens, parser actions, queued
requests, tensor/output allocation and initialization/check deadlines.
Derive accepted defaults from measurements on intended devices. No numeric
mobile memory, latency, battery or quality budget is validated by this
document. Input overflow, queue saturation and cancellation must have explicit
outcomes; they must not become an empty successful grammar report.

Use `OfficeProofingStatus.unsupported` for an unsupported locale/capability,
`unavailable` for an absent or unusable runtime/bundle, and `failed` for an
attempted check that cannot complete. The neutral analysis API may carry more
specific cancellation/capacity reasons. Map them deliberately rather than
adding nonexistent values to the current proofing enum. A clean result means
the applicable configured checks actually completed.

Desktop hash-pinned dynamic libraries are one deployment mechanism. iOS needs
an application-bundled, signed/static native arrangement using the appropriate
FFI lookup path; Android needs qualified ABI-specific native libraries.
Existing CrispEmbed build scripts are starting points, not proof that this
new pipeline is mobile-ready. Preserve model pages immutably while mapped.
Publish measured minimal artifacts and their notices, not an unpinned native
library downloaded during a check.

## Alternative model and implementation choices

The BERT-based `de_dep_news_trf` is a separate possible route. Current
CrispEmbed exposes
[`crispembed_encode_tokens_raw`](https://github.com/CrispStrobe/CrispEmbed/blob/b34a132c6c204b71f5c58ba8bc1705b8769edb9b/src/crispembed.h),
so its raw transformer states are a useful foundation. That route still
requires exact spaCy lexical-token/WordPiece alignment, overlapping-window
processing, pooling, trained task heads, parser and edit-tree decoding. The
normalized embedding or ColBERT API is not a substitute. The larger model's
memory/performance tradeoffs need device evidence; it is not the default plan.

A Rust implementation can expose the same C ABI, and a pure Dart inference
port is possible in principle. C++/GGML reuses CrispEmbed's deployment and
backend infrastructure; the Rust ports already supply substantial inference
code but introduce a different implementation boundary. Relative effort has
not been measured. None of the audited Rust ports yet covers all components of
this German pipeline; see the source audit. Choose C++/GGML for the first bounded port,
without claiming that the original Python package is automatically portable
or that a weight conversion/ONNX export supplies the surrounding algorithms.

Proceed through the evidence gates in [validation.md](validation.md). Neither
model licensing, a successful compile nor Python experiment scores qualify a
new native app backend on their own.
