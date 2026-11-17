# Native spaCy implementation — 17 November 2026

## Source reconciliation (W0)

This implementation starts from current CrispEmbed `b34a132c6c204b71f5c58ba8bc1705b8769edb9b`
and Quds `081af8a5` (the full commit/tree/ref inventory is in
[source-snapshot.json](source-snapshot.json)). Both repositories use isolated
worktrees. Origin branch and PR-head refs were refreshed; Quds upstream branch
and PR-head refs were refreshed too. Upstream main has no commits missing from
Quds main at this cutoff. No Actions, checks, or status endpoints were queried.

Quds includes the handoff PR #131 and subsequent ODF story/header/bookmark fixes
in PR #132. The current deterministic German context rules stay the grammar
baseline; historical AOT remains excluded. CrispEmbed main has no changes since
the handoff's inspected base. Its newer unmerged GECToR branch at `957ffa3b` is
a standalone-build/reference precedent, not a dependency to merge; the unrelated
worksheet perspective work at `0eca8e35` remains separately owned. Other fetched
feature/PR heads are inventoried, not represented as integrated.

## Owned lane and constraints

- Native source: [CrispEmbed feat/native-spacy-20261117](https://github.com/CrispStrobe/CrispEmbed/tree/feat/native-spacy-20261117).
- Developer oracle: [Quds feat/native-spacy-reference-20261117](https://github.com/CrispStrobe/quds_office_suite/tree/feat/native-spacy-reference-20261117).
- Decision: German `de_core_news_sm` 3.8.0, CPU/F32 first, no app Python, daemon,
  automatic model download, or implicit grammar activation.
- The user explicitly requires local validation and no CI waiting. This
  supersedes the generic hosted-CI guidance for this bounded implementation.
- Save meaningful commits remotely with `[skip ci]`, verifying each remote head.

## W1 inputs

The official wheel was acquired and matched **14,639,490 bytes**, SHA-256
`fec69fec52b1780f2d269d5af7582a5e28028738bd3190532459aeb473bfa3e7`.
It remains a developer input outside ordinary Git. Converter outputs must be
reproducible from that authenticated input; model notices must remain intact.

The handoff's spaCy source links used a nonexistent `v3.8.18` tag. The correct
tag is `release-v3.8.18`, commit
`43311999028032fd81bef77a75fdb4fa96803c98`; this corrects source identity without
changing the reference version. Thinc `v8.3.14` is
`e617de4ea2530c7091ea2110e011807c33c366f0`.

The W0 checkpoint scheduled deterministic model conversion, an explicit
tensor/lexical contract, a hash-bound reference environment, and nonempty
full-analysis fixtures before numerical porting. The following sections record
those later checkpoints. Missing fixtures must fail qualification. The W0
source inspection alone establishes no runtime or distribution readiness.

## W1 reference checkpoint

The complete reference tooling and frozen development fixtures are under
[tools/proofing/spacy](../../../tools/proofing/spacy/README.md). Two independent
exports match byte-for-byte across 36 files and 7,122,950 bytes: 16 cases,
113 tokens, 1,201 numerical stages, 244 parser transitions. The observer leaves
ordinary spaCy C greedy annotations unchanged; shared encoder vectors are exact.

Reference manifest SHA-256:
`9a3bb6bae6114adcf579840834ddcb64dea4e0aaa8361718dc7a551d663c8f7c`.
The hash-locked CPython3.12.14/spaCy3.8.18/Thinc8.3.14/NumPy2.4.6 environment
was independently reproduced in CrispEmbed's paired checkpoint. Seventeen
model-free fixture admission tests pass. These are reference and integrity
results, not native inference or grammar qualification. Eight acceptance
inputs are frozen and remain unexecuted during numerical development.

## Saved native numerical checkpoint (W3)

The paired implementation is saved at CrispEmbed
[`7f387f094528b01ba153d7cc5858344db16dd077`](https://github.com/CrispStrobe/CrispEmbed/commit/7f387f094528b01ba153d7cc5858344db16dd077),
on `feat/native-spacy-20261117`, with [draft PR #236](https://github.com/CrispStrobe/CrispEmbed/pull/236).
It consumes the unchanged Quds reference checkpoint
[`dcf2ec9b4d6fba05fa5eec2634c6654266332cc9`](https://github.com/CrispStrobe/quds_office_suite/commit/dcf2ec9b4d6fba05fa5eec2634c6654266332cc9).
This section restores the cross-repository handoff that was still pending when
the earlier implementation session ended. It summarizes retained results at
those exact revisions; it does not count them as new continuation test runs.

The native library implements six-feature hash embeddings, the shared CNN,
tagger/morphologizer/lemma-class scores, and parser scoring for supplied states.
Arithmetic is scalar C++ F32 with unfused operations; ggml provides GGUF loading
and CPU weight ownership. Its C ABI accepts prepared lexical features and parser
indices. It advertises those numerical capabilities while raw-text tokenization
and complete linguistic decoding remain open.

| Retained evidence | Result and scope |
| --- | --- |
| [Installed-library parity](https://github.com/CrispStrobe/CrispEmbed/blob/7f387f094528b01ba153d7cc5858344db16dd077/docs/validation/native-spacy-20261117/native-parity-final.json) | 16 development cases, 113 tokens, 1,201 stages and 1,406,553 F32 comparisons pass the frozen budget. |
| Classifier decisions | All 339 argmax choices match exactly. |
| Parser scorer replay | All 244 legal action choices match on reference-supplied states and masks. Native parser transitions are a separate W4 requirement. |
| Numerical error | Maximum absolute error is `3.814697265625e-5`, within `2e-4 + 2e-5 * abs(reference)`. No tolerance or golden output was changed. |
| [Native build and controls](https://github.com/CrispStrobe/CrispEmbed/blob/7f387f094528b01ba153d7cc5858344db16dd077/docs/validation/native-spacy-20261117/native-validation.json) | Two native control executables and the numeric ASan/UBSan control pass. Missing reference assets fail explicitly. |
| Build/install scope | Linux x86-64 with the repository AVX2 baseline; ten installed library, header and notice files are inventoried. The inspected ELF depends on C/C++/math/system libraries without a Python library dependency. |
| [Conversion evidence](https://github.com/CrispStrobe/CrispEmbed/blob/7f387f094528b01ba153d7cc5858344db16dd077/docs/validation/native-spacy-20261117/converter-validation.json) | 33 model-free controls pass; two real conversions are byte-identical across five files; all 39 trained F32 tensors round-trip unchanged. |

The [native summary](https://github.com/CrispStrobe/CrispEmbed/blob/7f387f094528b01ba153d7cc5858344db16dd077/docs/validation/native-spacy-20261117/native-summary.json)
independently recomputes the final numerical denominators. Initial and final
parity runs use the same development cases and must not be added as separate
unique evidence. The [full receipt](https://github.com/CrispStrobe/CrispEmbed/blob/7f387f094528b01ba153d7cc5858344db16dd077/docs/validation/native-spacy-20261117/README.md)
also preserves the initial unwritable temporary-directory test setup and the
stale install recipe, together with their successful corrections.

The converted GGUF has 7,383,104 bytes and SHA-256
`fae2e6ab8d6c611d7a9dddd4b3259a871a1d2f95cacc8259f49c1e4ff31ff6cd`.
Its bundle manifest SHA-256 is
`d599768375de3dc56abcca5cf1d49da0015857f9d3a10640aebb5317ef5d427e`.
The [build/API instructions](https://github.com/CrispStrobe/CrispEmbed/blob/7f387f094528b01ba153d7cc5858344db16dd077/tools/spacy/README.md)
reproduce the admitted model and standalone library. Model weights stay outside
ordinary Git; the authenticated source wheel and pinned converter reproduce
them. Native/model release artifacts have not been published.

## Continuation source refresh

The continuation starts from saved Quds `dcf2ec9b4d6fba05fa5eec2634c6654266332cc9`
and the native checkpoint above. Origin and the known upstream repository's
branch/PR-head refs were refreshed without Actions, checks or status queries.
[continuation-source-snapshot.json](continuation-source-snapshot.json) records
the 320 fetched refs and the source comparison before integration.

At that cutoff, Quds origin main was
`d6010059644b34accd6f188e0e2a4863ab63e318`, and upstream main was
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`. No upstream-main commit is absent
from origin main. Since the original `081af8a5` base, origin main has 13
additional commits affecting 68 paths, with no path overlap with the saved
reference lane. The continuation incorporates that exact origin-main revision
through a normal merge, preserving both parents' work. The incoming work covers
ODT first/even headers, bounded fields,
bookmarks, columns, tabs and contents; retained Office regressions and render
evidence; sheet color scales; dynamic ODS list validation; and the first-party
proofing adapter reuse map. The snapshot intentionally retains the source state
captured before that integration.

The incoming reuse map preserves first-party UI, lifecycle, source-mapping and
review behavior while excluding AOT/RML libraries, resources and transports.
The spaCy lane owns its new ABI and analysis types. Existing deterministic
German context rules continue to define the grammar comparison baseline.
Frozen fixture bytes and the eight acceptance inputs remain unchanged.

## Next implementation boundary

1. **W2 lexical processing:** implement German tokenization, normalization,
   exact string/feature IDs and original UTF-8/scalar/UTF-16 spans from the
   exported resources. Require exact parity on the frozen development cases,
   explicit malformed/over-limit behavior, and a remote checkpoint before
   downstream decoding relies on those features.
2. **W4 linguistic decoding:** implement parser state, legal-action masks,
   transitions, sentence boundaries, dependency reconstruction/deprojection,
   edit-tree application/top-k/fallback, morphology/POS decoding and final
   attribute rules. Compare complete annotations and step-level decisions.
3. **W5 onward:** connect the optional Dart worker and analysis UI after
   complete raw-text analysis parity. Grammar activation requires incremental
   benefit over current deterministic rules. Packaging, device evidence and
   final qualification remain separately reported gates.

Keep the eight frozen acceptance inputs unused while tuning. The numerical
checkpoint leaves `CRISPEMBED_SPACY` default off and changes no Quds provider,
app pin, model alias or release default. Local validation and incremental
remote checkpoints remain required; no GitHub Actions query or wait is a gate.
