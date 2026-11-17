# Native spaCy implementation work packages

Status: **implementation specification**, 17 November 2026. Start with the
[handoff](README.md), [source audit](source-audit.md), and
[architecture](architecture.md). This document names new files and commands
that an implementation agent must create; their presence here is not a claim
that a native spaCy backend already exists.

## Deliverable and initial decisions

Implement the inference subset of `de_core_news_sm` 3.8.0 needed for German
tokens, tags, contextual morphology, lemmas, syntax, and sentence boundaries.
Use a small CrispEmbed C++/ggml library, a versioned model bundle, and an
optional `quds_proofing_spacy` Dart package. Integrate explicit linguistic
analysis and conservative manual grammar checking with the existing editor.

Initial decisions are CPU/F32, no NER, no training implementation, no Python in
the app, no daemon, and no implicit network activity. Preserve current default
providers. Do not expand scope to a general spaCy API clone or all languages.
The first language/grammar qualification is de-DE; the model's `de` identity
does not establish de-AT/de-CH correction safety.

No new trained weights are required merely to port the inference computation.
Do not retrain to hide a serialization or parity bug. Reconsider the model only
after measuring its actual limitations with the correct native implementation.

## Work order and parallel ownership

| Package | Depends on | Principal output | Safe parallel work |
| --- | --- | --- | --- |
| W0: source reconciliation | Handoff | Exact current input snapshot and branch | Read-only license/source inventory |
| W1: reference and model contract | W0 | Frozen reference fixtures, converter, schema, licenses | Draft Dart analysis types and fixture cases |
| W2: native lexical processing | W1 | Exact tokens, offsets, features, hash inputs | W3 numeric implementation against frozen tensors |
| W3: shared CNN and classifiers | W1 | F32 graph and stage traces | W2; Dart schema-only work |
| W4: parser and edit-tree decoding | W2, W3 | Complete native analysis parity | Parser and lemma modules can have separate owners |
| W5: Dart/native integration | W1 contract, W4 runtime | Optional package, worker, analysis UI | Isolated UI work with explicitly synthetic test backends |
| W6: guarded grammar | W4, W5 | Tested reviewable de-DE corrections | Independently owned rule families sharing fixed DTOs |
| W7: native/mobile packaging | W4, W5 | Reproducible binaries, model pack, dependency inventory | Platform-specific build owners |
| W8: final qualification | W6, W7 | Evidence, supported-platform statement, remote handoff | Independent review of frozen candidate |

One owner controls the model schema, C ABI, and shared Dart DTOs. Other agents
consume those contracts and own disjoint files. The coordinating agent owns
Git integration. Do not let parallel agents commit or rewrite the same branch
without coordination. Publish a meaningful remote checkpoint at each package
boundary; split larger packages further when useful.

## W0 — Refresh and preserve the actual source

**Existing inputs:** Quds main was `162288351af0ad43bb4d869fd2d814eaaa30a930`
when these documents were written. CrispEmbed main inspected for research was
`b34a132c6c204b71f5c58ba8bc1705b8769edb9b`; its ggml submodule was
`3a27b6c665b191cb230be367db5c52d81dd3e2ac`. The standalone GECToR precedent
is a different feature pin, `853a1ce6089e5d5486e37307f37051ad6a928745`.

Before publication the handoff also reconciled Quds main through
`aa9591d496d66a549d4e0c67aee73eada0d9d46f` (PRs #129 and #130). Preserve its
new context rules and Office repairs. Read the
[context qualification](../../validation/german-context-20261117/README.md)
alongside the earlier syntax experiment before choosing a grammar extension.

**Actions:**

1. Read repository instructions, inspect tracked/untracked changes, and create
   an isolated implementation branch or worktree as needed. Never use a hard
   reset or clean to remove another agent's work.
2. Fetch fork/upstream heads and PR heads. Record exact refs, SHAs, capture time,
   and an integration cutoff. Inspect new commits for applicable Office,
   proofing, ABI, and dependency changes. Use source/ref/PR metadata only;
   never query checks or Actions.
3. Reconcile relevant incoming changes by source content and recorded intent.
   Main's integration deliberately excludes AOT. Historical AOT references are
   evidence, not instructions to restore that dependency. Do not use ancestry-
   only merges to claim that excluded code was integrated.
4. Refresh CrispEmbed separately. Read its `AGENTS.md`. Compare the current
   source with the research pins and record which existing functions/targets
   remain available. Select and record the implementation base.
5. Create `docs/validation/native-spacy-<date>/` for this implementation's input
   snapshot and later evidence. Keep previous reports immutable.

**Exit:** an independently reproducible source snapshot and integration note,
with a remote checkpoint in Quds and an identified CrispEmbed work branch.
Preserve the original request to bring in recent work, but state exact deferred
or intentionally excluded source instead of silently claiming full inclusion.

## W1 — Freeze the oracle and converted-model contract

**Existing files to read first:**

- [Model identity](../../../tools/proofing/german_model/syntax-model.json).
- [Reference environment](../../../tools/proofing/german_model/requirements-syntax.txt):
  the existing evaluation pins spaCy **3.8.18** and Thinc **8.3.14**.
- [Reference runner](../../../tools/proofing/german_model/evaluate_syntax.py)
  and [reproduction commands](../../../tools/proofing/german_model/SYNTAX_EVALUATION.md).
- [Actual experiment report](../../validation/german-syntax-20261117/README.md)
  and [archive inventory](../../validation/german-syntax-20261117/evidence-index.json).

The existing requirements describe a macOS evaluation environment, not a
portable native build recipe. Freeze a reproducible development oracle with
exact dependency versions/hashes for the implementation host. If a version
must change, record and compare its outputs; do not silently replace fixtures.
English-port reference environments are not automatically the German oracle.

**New outputs, proposed locations:**

- Quds `tools/proofing/spacy/`: trusted acquisition metadata, full annotation
  and intermediate-trace exporter, fixture inventory, differential runner, and
  reproduction README. Developer Python is isolated here and never an app
  dependency.
- CrispEmbed `models/convert-spacy-to-gguf.py`: a deterministic converter for
  this exact supported pipeline and selected components.
- A versioned model manifest and schema identifying the native architecture,
  source artifact SHA-256, tensor names/shapes/dtypes/layouts, lexical resource
  hashes, ordered labels/moves/edit trees, component dependencies, declared
  capabilities, sizes, limits, and required notices.

Acquire the existing pinned wheel only after verifying its exact identity:
`de_core_news_sm-3.8.0-py3-none-any.whl`, **14,639,490 bytes**, SHA-256
`fec69fec52b1780f2d269d5af7582a5e28028738bd3190532459aeb473bfa3e7`.
The separately inspected upstream `.tar.gz` and Quds evidence archive are
different artifacts with different hashes; see the source audit.

Export trained inference parameters, not optimizer state. Export native data
for tokenizer exceptions/regexes, lexical normalization and symbols, embedding
hash seeds, label order, parser moves, and edit trees. Treat 64-bit identifiers
as exact integers or decimal strings; never round them through JavaScript
Number. Preserve model `LICENSE` and `LICENSES_SOURCES` verbatim.

Extend the existing evaluator to capture full model behavior. Its current
agreement output alone is insufficient: freeze tokens, original code-point
and UTF-16 spans, lexical features, shared encoder outputs, classifier scores,
parser decisions/final structure, lemma decisions, and sentence boundaries.
Freeze development fixtures separately from an untouched acceptance set.

**Exit:** converter round-trip/shape checks pass; independent exports are
reproducible; bad versions, missing components, malformed resources, and changed
assets fail admission. The fixture set has recorded denominators and origin.
Commit/push metadata, tools, small fixtures, and notices. Large model weights
and Python environments stay outside ordinary Git, in an identified immutable
artifact location with trusted hashes.

## W2 — Implement lexical processing and source positions

**Proposed native files:** `src/spacy_pipeline.{h,cpp}` plus focused lexical,
Unicode, hashing, and resource modules as the implementation warrants. Reuse
reviewed existing helpers only after conformance checks; CrispEmbed's WordPiece,
BPE, and SentencePiece tokenizers are not substitutes for spaCy tokenization.

Implement German exception handling, prefix/suffix/infix splitting, token and
URL matches, whitespace conventions, normalization, prefix/suffix/shape, and
the exact exported attributes. Match spaCy string IDs and Thinc's embedding
hash behavior, including overflow, signedness, seeds, and table indexing.

Keep the original input and spans authoritative. Do not recover positions with
`indexOf` on repeated words or normalize text before locating it. Explicitly
handle UTF-8 bytes, Unicode scalar positions, Dart UTF-16, combining marks,
supplementary characters, soft hyphens, CRLF, and unusual whitespace. Reject or
explicitly represent unsupported malformed input; never produce plausible but
incorrect source spans.

**Exit:** exact lexical/token/offset parity on the frozen cases and Unicode
boundary cases. Failures identify the earliest differing token/feature. The
native input contract defines empty input and bounds without truncating text
silently. Push a checkpoint before downstream code relies on these features.

## W3 — Implement the CNN and task scores

Use the actual exported architecture: six-feature `MultiHashEmbed.v2`, width
96, table rows `[5000,1000,2500,2500,50,50]`, no static vectors, and four
`MaxoutWindowEncoder.v2` layers with window one and three maxout pieces.
The source audit and architecture document record the exact component graph.

Implement embedding lookup/composition, window expansion/padding, learned affine
maps, maxout, normalization with source epsilon, residual connections, and the
tagger/morphologizer/edit-tree scoring heads. Add parser scorer support with
source layouts and padding. Preserve shared encoder execution rather than
recomputing it independently for every head.

Use F32 CPU first. Add optional diagnostic traces at each stage. Confirm tensor
orientation, concatenation order, normalization axes, document boundaries, and
tie-breaking. A tensor container conversion or matching output dimensions is
not numerical parity. Do not substitute the GECToR BERT graph for this CNN.

**Exit:** declared intermediate tolerances and final classifier decisions pass
on actual model fixtures. Missing fixtures/model assets make the required
parity command fail. A model-free unit run must be labeled separately. Push the
exact graph, converter, fixture hashes, and comparison receipt together.

## W4 — Complete linguistic decoding

Implement the greedy dependency parser's state, valid-action mask, ordered
actions, transitions, sentence breaks, final dependency reconstruction, and
pseudo-projective handling used by the pinned model. A single head-index argmax
does not reproduce this parser. Compare step-level decisions when a tree differs.

Implement morphologizer label decoding and trainable edit-tree lemmatization,
including tree applicability, configured top-k, overwrite semantics, and
fallback. Reusing an English rule/lookup lemmatizer does not implement the
German trained component. Preserve model component order and attribute rules.

The disabled `senter` does not need a separate initial implementation; the
qualified parser supplies sentence boundaries. NER stays omitted and declared
unavailable. Unsupported component sets must fail explicitly rather than
silently returning a partially annotated document as complete.

**Exit:** complete token/tag/POS/morphology/lemma/dependency/sentence output
matches the frozen reference's acceptance requirements. Structural invariants
and bounded parsing pass. Report deviations explicitly; never edit goldens to
match the port. Save and push a complete standalone native analysis checkpoint.

## W5 — Add the optional Dart package and analysis UI

Create `packages/quds_proofing_spacy/` with a separate native entry point and
platform-safe Dart API. The architecture document owns the proposed exact file
map and ABI. Keep `quds_office_engine` pure Dart. Load immutable reviewed model
data through an explicit host configuration, not hidden runtime downloads.

Existing integration anchors:

- [Proofing types and merger](../../../packages/quds_office_engine/lib/src/proofing/office_proofing.dart):
  `OfficeProofingProvider`, `OfficeProofingRequest`, `OfficeProofingFinding.forRequest`,
  and `mergeOfficeProofingReports`.
- [Word proofing session](../../../packages/quds_office_editor/lib/src/proofing/word_proofing.dart):
  `configureManual`, manual checks, revision checks, and cancellation behavior.
- [Native GECToR backend](../../../packages/quds_proofing_gector/lib/src/native_backend.dart)
  and its [worker](../../../packages/quds_proofing_gector/lib/src/worker_native.dart):
  lifecycle and admission patterns; review platform assumptions before reuse.

Use neutral analysis types with truthful capabilities, original spans, model
identity, and complete/failed/unsupported states. A contextual selected reading
is not a list of every possible morphological reading. Do not reuse an AOT DTO
that would imply nonexistent paradigms or parse alternatives.

Run native work away from the UI thread. Define one-context serialization,
buffer ownership, request identity, cancellation acknowledgement, stale-result
discard, and shutdown. Never free a native context while an FFI call still
uses it. Bounded caches may retain immutable model resources; avoid retaining
document text beyond the declared request/cache policy.

Add an explicit analysis action for selected text or document-body text, with
readable token/lemma/morphology/dependency results and cancellation. Current
main has no AOT analysis screen to rename; the historical screen is a reference.
Until W6 qualifies the grammar planner, keep grammar disabled or use explicitly
synthetic test backends. The first qualified grammar implementation remains
manual-only after W6; background/default registration is outside this scope.

**Exit:** real native end-to-end analysis, exact nonzero selection offsets,
staleness/cancel/close/error paths, and unsupported-platform behavior are
verified. Web imports remain safe with an explicit unavailable native backend.
Push before proceeding to new grammar claims.

## W6 — Add conservative corrections on top of analysis

First establish the **current** deterministic baseline, including
`german_context_grammar.dart`, literal-range protection, and the incoming context
fixtures. Compare the combined provider against that baseline, not only the
older spaCy prototype or pre-extension scores. Reuse existing rule/data APIs.
Do not enable duplicate or lower-quality model suggestions merely because
native inference now works. If no bounded grammar benefit is demonstrated,
deliver qualified analysis and retain grammar as disabled/experimental with
the measured result documented.

Start with independently authored noun/subject-verb agreement. Reuse the
existing licensed German morphology and reviewed verb facts through an
appropriate pure Dart API. Preserve all competing lexical readings: the prior
spaCy experiment changed valid singular `Leiter` until Quds noun evidence
vetoed the inference. Its guarded result is a development result, not a new
blind benchmark; see the validation document.

Add fixed-preposition case and article/adjective/noun agreement only when each
replacement is supported by reviewed generation rules or licensed paradigms.
A lemma alone cannot enumerate all inflected forms. Unknown, ambiguous,
unsupported, protected, or incompletely analyzed contexts cause abstention.
Keep imperatives, coordination, expletive `es`, fronted objects, quotations,
regional spellings, and malformed text in the valid/adverse control design.

For each rule, record its exact preconditions, supported constructions, stable
ignore-rule ID, evidence used, replacement provenance, abstention cases, and
expected interaction with existing deterministic providers. Avoid duplicate or
contradictory findings by using the existing report-merging policy.

**Exit:** correction/protection/ignore/recheck/undo/redo tests pass through the
real editor. Report coverage and false positives separately, with changed valid
controls called out. General grammar quality is not inferred from a small panel.
Push the rule implementation with frozen before/after evidence.

## W7 — Package the exact native dependency set

Follow the small-library pattern in CrispEmbed's historical
[`tools/gector/CMakeLists.txt`](https://github.com/CrispStrobe/CrispEmbed/blob/853a1ce6089e5d5486e37307f37051ad6a928745/tools/gector/CMakeLists.txt).
Create `tools/spacy/CMakeLists.txt` and documented build/install targets rather
than pulling every optional document/OCR component into the new NLP library.
Record compiled sources, ggml revision, toolchain, target ABI, linked libraries,
model hashes, precision, and original notices.

Provide desktop development builds and intended mobile builds separately.
iOS integration needs its actual static/framework/FFI symbol strategy, signing
compatible packaging, and device/simulator evidence. Android needs its actual
ABI/NDK/library packaging and device evidence. Do not copy desktop process or
arbitrary-library-path assumptions into mobile. A Linux result does not qualify
Apple or Android targets.

No Python, Go runtime, Rust runtime library, AOT dictionaries, or extra inference
framework is an automatic dependency of the chosen C++ route. If a concrete
implementation introduces any new component, record its reason and exact license
instead of assuming the parent project's MIT license covers it.

**Exit:** reproducible documented builds, a minimal admitted runtime bundle,
complete distribution inventory, and per-platform smoke evidence. Track any
unavailable device/toolchain as a specific unqualified target, not a passing
test. App Store publication and payment-product setup are separate work.

## W8 — Qualify, publish, and hand off

Run the scoped [validation plan](validation.md) locally on the exact candidate.
Report source/fixture/model/build hashes, test denominators, failures/skips,
reference parity, correction quality, startup/latency/memory, and platform scope.
Do not sum repeated subsets as additional unique tests.

Quantization and accelerated backends are optional follow-on work. First record
the F32 CPU baseline. Any F16/Q8/Q4 or Metal/Vulkan recipe needs its own final
annotation and correction comparisons plus complete-operation measurements.
Small tensor error does not prove unchanged parser decisions.

Update this roadmap's status, package README, source/model manifest, notices,
and evidence index. Publish both repository branches in meaningful increments.
Pin Quds to the exact reviewed CrispEmbed commit and immutable native/model
artifacts; never depend on moving main or an unpushed developer checkout.

**Exit:** a fresh agent can retrieve every required source/artifact, reproduce
the declared local checks, run the supported application flow, and identify
remaining limits without chat history or CI access. Preserve failed exploratory
results that explain decisions, but clearly separate them from passing evidence.

## Checkpoint discipline

Use explicit paths when staging changes and review the staged diff. Example
checkpoint messages may use `feat(spacy): ... [skip ci]`. Push the current branch
after each completed unit and compare its remote head with the saved commit.
If shell credentials are unavailable, the connected GitHub API may publish the
same reviewed tree; verify tree equality and synchronize the local branch.
Do not print credentials or pause completed work merely because one transport
is unavailable. Use non-forced updates and expected-head checks.

A merge conflict, missing license grant, unsupported native platform, or model
parity failure is a concrete issue to resolve or record with exact scope. None
is a reason to query the starved GitHub Actions queue. Do not claim a feature
implemented until its corresponding work package and evidence are complete.
