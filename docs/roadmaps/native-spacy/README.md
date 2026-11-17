# Native spaCy analysis and proofing: implementation handoff

Date: 17 November 2026. Status: **researched and scoped; native spaCy backend
not implemented or qualified**. This directory is the durable handoff for a
fresh implementation agent. It records decisions, inspected source, existing
experiments, work packages, and acceptance criteria without requiring access to
the preceding conversation.

**Implementation continuation, 17 November 2026:** the original status above
describes the research handoff. The later native CPU/F32 implementation is saved
at [CrispEmbed `51c2ac328`](https://github.com/CrispStrobe/CrispEmbed/commit/51c2ac328ef40b00f18eb9b03130fb67c3f11313).
Its installed Linux raw-text path passes the complete 16-case development
comparison, with native tokenization and linguistic decoding. The eight-case
acceptance freeze/run and W5 application integration remain pending at this
continuation checkpoint. Read the [current implementation receipt](../../validation/native-spacy-20261117/README.md)
before choosing the next work package. Historical evidence below remains
source-bound.

## Start here

Build an optional, offline German linguistic-analysis backend for Quds using
the trained `de_core_news_sm` **3.8.0** pipeline. The recommended implementation
is a small **C++/ggml target in CrispEmbed**, connected to a new optional Dart
package through a C ABI. Reuse the trained weights and implement the matching
tokenization, neural graph, parser, and edit-tree lemmatizer. Grammar diagnostics
and replacement generation are a separate, guarded Quds layer.

The application must contain **no Python runtime and require no SynanDaemon,
listening service, or remote inference**. Python is acceptable in isolated
developer conversion/reference tooling; that is an implementation assumption
consistent with the user's prohibition on Python *in the app*. Exported data
and compiled native code are the runtime deliverables.

Read these documents in order:

1. [Source audit](source-audit.md): exact repositories, revisions, model assets,
   formats, German support gaps, and what has actually been verified.
2. [Architecture](architecture.md): model semantics, native/Dart boundaries,
   proposed files and APIs, ownership, offsets, cancellation, and capabilities.
3. [Implementation plan](implementation-plan.md): ordered work packages,
   ownership boundaries, concrete outputs, and per-stage completion criteria.
4. [Validation](validation.md): reference parity, existing corpus reuse, grammar
   quality, adverse inputs, packaging, and device evidence.
5. [Licensing and distribution](licensing-and-distribution.md): the AOT/LGPL
   findings, the clarified user policy, selected spaCy assets, and App Store
   commercial-distribution considerations.

The supplementary [historical AOT build receipt](aot-license-build-evidence.md)
preserves the exact link/dependency/notices observations behind the licensing
record. It is evidence about the earlier Linux prototype, not new runtime or
mobile qualification.

## Instructions and constraints carried forward

- Save small, meaningful commits to a **remote GitHub branch incrementally**.
  Local-only work is not a completed checkpoint. Verify the remote ref after
  each push. Preserve the previous checkpoint if a later stage fails.
- Before implementation, refresh fork and upstream branches and PR heads,
  inspect incoming changes, and reconcile the relevant current source. Record
  exactly what was incorporated or deferred and why. Do not silently replace
  newer Office/proofing changes with an old research checkout.
- **Do not query, poll, wait for, rerun, or use GitHub Actions/CI status as a
  gate.** The user's free-tier queue is starved. Use local validation and
  explicit receipts; `[skip ci]` can be used in checkpoint commit messages.
- No Python interpreter, Python packages, Python subprocesses, or Python
  embedding in the shipped app. No automatic network fallback or model
  download during analysis.
- The app must remain suitable for commercial distribution, including possible
  tips or in-app purchases. The user explicitly clarified that LGPL is not
  categorically forbidden if provenance and distribution obligations are met.
  The recommended spaCy route nevertheless starts from clearly licensed MIT
  code/model assets. See the licensing document for the precise boundaries.
- Preserve existing spelling, writing rules, proofing sessions, ignore rules,
  protected text, review-before-correction, undo/redo, and locale behavior.
- The first new grammar provider is **manual, optional, and de-DE only**.
  Additional German regions or languages require their own declared support
  and evidence. Source data for German is not proof of regional grammar quality.
- Do not describe source inspection, a passing empty test run, existing Python
  experiments, or English-port tests as a working German native implementation.

## Repository state at handoff

The documentation branch is `docs/native-spacy-handoff-20261117`. Its initial
base was Quds `main` at **`162288351af0ad43bb4d869fd2d814eaaa30a930`**; publication
then reconciled newer main **`aa9591d496d66a549d4e0c67aee73eada0d9d46f`**, including
[PR #129](https://github.com/CrispStrobe/quds_office_suite/pull/129) and
[PR #130](https://github.com/CrispStrobe/quds_office_suite/pull/130). The two
documentation conflicts retained both incoming content and the handoff links.
Fork/upstream branch and PR-head refs were refreshed before writing. These are
read-only research/documentation changes; this handoff does not claim to merge
every unmerged branch or to requalify application code.

Current main includes [PR #125](https://github.com/CrispStrobe/quds_office_suite/pull/125),
whose Office integration excludes AOT. At this baseline, `quds_proofing_aot`
is not a tracked workspace package and `studio_aot.dart` is not current code.
An old checkout can retain ignored build directories with these names: use
`git ls-tree` or `git ls-files`, not directory existence, to determine source
availability.

The daemon-free AOT work remains a **historical reference** at
[`e37ccdb47c047f6a0250585cf5cb20efc17573b4`](https://github.com/CrispStrobe/quds_office_suite/tree/e37ccdb47c047f6a0250585cf5cb20efc17573b4),
branch `codex/aot-daemon-free-20261117`,
[PR #120](https://github.com/CrispStrobe/quds_office_suite/pull/120).
It provides useful lifecycle/UI/offset experience. Reintroducing its libraries
or dictionaries is not part of the recommended spaCy implementation.

| Existing work | Where to start | What it proves |
| --- | --- | --- |
| Pure Dart spelling, morphology, and grammar | [Proofing roadmap](../../PROOFING.md), `packages/quds_office_engine/lib/src/proofing/` | Existing application behavior and reusable licensed linguistic resources |
| Newer independent German context rules | [Context qualification](../../validation/german-context-20261117/README.md), `german_context_grammar.dart` and `german_literal_ranges.dart` under the engine's proofing directory | The current deterministic baseline is broader than the earlier spaCy experiment; preserve it and measure any incremental model benefit |
| Native GECToR adapter | [Package README](../../../packages/quds_proofing_gector/README.md) | Existing native-worker/FFI and manual-provider integration patterns |
| spaCy syntax experiment | [Retained report](../../validation/german-syntax-20261117/README.md) | Actual Python-side German inference and bounded correction experiments; not native runtime qualification |
| Reproduction tools and model pin | [Syntax evaluation](../../../tools/proofing/german_model/SYNTAX_EVALUATION.md), [model manifest](../../../tools/proofing/german_model/syntax-model.json) | Existing reproducible reference inputs and exact wheel identity |
| CrispEmbed current source inspected | [`b34a132c6c204b71f5c58ba8bc1705b8769edb9b`](https://github.com/CrispStrobe/CrispEmbed/tree/b34a132c6c204b71f5c58ba8bc1705b8769edb9b) | Native GGUF/ggml infrastructure and raw-token encoder API; no spaCy pipeline |
| CrispEmbed standalone GECToR precedent | [`853a1ce6089e5d5486e37307f37051ad6a928745`](https://github.com/CrispStrobe/CrispEmbed/tree/853a1ce6089e5d5486e37307f37051ad6a928745) | Small CPU target and strict model admission; historical feature pin, not current-main spaCy support |

## First session for a fresh agent

For a new clone in an empty working directory, the saved handoff is available
without recovering any previous agent workspace:

```sh
git clone https://github.com/CrispStrobe/quds_office_suite.git quds_office_suite
cd quds_office_suite
git switch --track origin/docs/native-spacy-handoff-20261117
git remote add upstream https://github.com/MohammedAsaadAsaad/quds_office_suite.git
```

For an existing checkout, inspect its status and fetch the documentation branch
before switching; preserve uncommitted work. Keep these handoff commits when
creating the implementation branch and reconcile newer main into that branch.

1. Read this directory and any applicable `AGENTS.md` in each repository.
   Confirm a clean or safely isolated checkout; never reset another person's
   work. The source pins above are research baselines, not permission to
   overwrite newer commits.
2. Fetch current refs without CI endpoints, record current heads, and make an
   implementation branch from the reconciled current Quds source. Read the
   corresponding CrispEmbed checkout's instructions before editing it.
3. Start **W0 and W1** in the implementation plan: preserve the input snapshot,
   inspect the existing model manifest and reference harness, freeze a full
   native-reference fixture contract, and specify the converted model bundle.
4. Push that first concrete model/reference/contract checkpoint before porting
   the numerical graph. Continue with W2-W8 in dependency order.

For an existing Quds clone, these are ordinary read-only startup checks:

```sh
git status --short --branch
git fetch origin --prune
git fetch upstream --prune
git fetch origin '+refs/pull/*/head:refs/remotes/origin/pr/*'
git fetch upstream '+refs/pull/*/head:refs/remotes/upstream/pr/*'
git show origin/main:pubspec.yaml
git log -8 --oneline origin/main
git show HEAD:tools/proofing/german_model/syntax-model.json
```

`upstream` here is the existing MohammedAsaadAsaad repository remote. A fresh
clone must add that known remote if absent. Fetching PR heads reads source refs;
it does not query checks or Actions. Use a fresh branch name if another agent
already owns the implementation branch. The named new spaCy packages, commands,
and native targets in the companion documents are **proposals to create**, not
commands claimed to work before their implementation stage.

## Scope and completion boundary

The first useful native analysis result includes original-text token spans,
fine/coarse part of speech, contextual morphology, lemmas, dependency heads and
relations, and sentence boundaries. Omit NER initially; it is not required for
the targeted grammar rules. Explicitly identify unavailable capabilities.

After analysis parity, add independently tested conservative grammar rules,
starting with noun/subject-verb agreement corroborated by existing Quds
morphology. Follow with fixed-preposition and noun-phrase agreement only when
replacement generation and ambiguity guards are qualified. Do not fabricate
AOT-style full paradigms or alternative parse forests from one spaCy prediction.

The incoming context-rule work is the current grammar baseline. Compare against
it and reuse its licensed facts and guards; do not recreate already implemented
rules or replace them simply to exercise a neural backend. Native analysis is a
useful independent deliverable. A model-based grammar provider needs evidence
of incremental benefit and acceptable false positives before activation.

The first implementation is complete only when the selected native model runs
without Python or a daemon, produces qualified analysis, integrates safely with
manual review, and has published local test evidence and reproducible build
instructions. Mobile distribution, accelerated backends, quantization, other
locales, and broader correction claims require separately reported evidence.
Do not call Linux-only validation mobile readiness.

## Decisions to keep explicit

- **Preferred:** C++/ggml inside CrispEmbed, compact CNN German model, CPU F32
  first, separate optional Dart package, frozen reference fixtures.
- **Viable alternative:** extend the MIT SpaRs Rust implementation and expose a
  C ABI if that materially reduces implementation effort. Document the choice;
  all audited ports still need German components and qualification.
- **Later model option:** the BERT-based `de_dep_news_trf` can reuse more encoder
  machinery, but still needs spaCy alignment, task heads, parsing, and lemmas.
  Convert its exact trained weights; a generic German BERT checkpoint is not a
  substitute.
- **Not an implementation shortcut:** changing MessagePack or SafeTensors to
  GGUF without implementing the model architecture and linguistic algorithms.
- **Evidence rule:** runtime parity, linguistic accuracy, correction quality,
  device performance, and distribution compliance are distinct claims. Report
  each with its actual scope and do not transfer evidence between them.
