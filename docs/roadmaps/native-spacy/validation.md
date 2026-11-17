# Native spaCy validation and evidence plan

Status: handoff and proposed acceptance gates, 17 November 2026. No new native
spaCy implementation was built or executed while preparing these documents.
There is actual prior **Python evaluation evidence**, summarized below. It
does not validate C++/GGML inference, a Dart native binding, mobile memory,
App Store packaging or unrestricted grammar quality.

Read the [architecture](architecture.md), [source audit](source-audit.md) and
[implementation plan](implementation-plan.md) before implementing these gates.
All new commands, APIs and test paths below are proposals unless explicitly
identified as existing. Do not report a proposed test as a passing test.

## Existing evidence to preserve and reuse

The authoritative recorded experiment is
[`docs/validation/german-syntax-20261117/README.md`](../../validation/german-syntax-20261117/README.md).
The corresponding
[`evidence-index.json`](../../validation/german-syntax-20261117/evidence-index.json)
binds the archive and each member to SHA-256. Its archive hash is
`4588f810d12ebd30dff19beb08ad596a636b437836a670cf6de892d143bf97ca`.
The archive contains outputs, logs, manifests and notices, not model weights
or an installed Python environment.

The experiment used spaCy **3.8.18** and the official
`de_core_news_sm-3.8.0-py3-none-any.whl`, **14,639,490 bytes**, SHA-256
`fec69fec52b1780f2d269d5af7582a5e28028738bd3190532459aeb473bfa3e7`.
These pins are already stored in
[`syntax-model.json`](../../../tools/proofing/german_model/syntax-model.json),
with evaluation dependencies in
[`requirements-syntax.txt`](../../../tools/proofing/german_model/requirements-syntax.txt).
The wheel, a publisher source archive and a future converted GGUF are
different artifacts; never reuse one artifact's hash for another.

The existing
[`evaluate_syntax.py`](../../../tools/proofing/german_model/evaluate_syntax.py)
uses statistical annotations with a separately authored noun/finite-verb
agreement planner and Quds's 57 reviewed finite-verb paradigms. The
[`Dart noun-evidence exporter`](../../../tools/proofing/german_model/export_syntax_noun_evidence.dart)
corroborates parser noun number using actual Quds morphology.

| Recorded Python experiment | Exact fixes | Valid controls changed | Interpretation |
| --- | ---: | ---: | --- |
| Initial syntax prototype, 56 sentences | 15/20 | 1/36 | Misread singular `Leiter` as plural and changed valid text. |
| Same panel after lexical noun-number guard | 15/20 | 0/36 | The guard was designed after seeing that false positive; this panel is development evidence for that change. |
| Separate 76-case panel with the guarded planner | 0/32 | 0/44 | Exposes the planner's narrow scope; it does not establish broad grammar correction. |
| Original 30-case panel with the guarded planner | 2/18 | No controls changed | Regional unsupported cases are recorded separately; absence of a change does not establish supported coverage. |

Preserve the initial failing result alongside the guarded result. The actual
archive members include `syntax-sealed-syntax.json`,
`syntax-sealed-syntax-guarded.json`, `syntax-sealed-heldout-guarded.json`,
`syntax-sealed-original-guarded.json` and their noun-evidence files. Their
exact hashes are in the index. The 56-case panel was frozen at
`b13e0c72f850ed40dee94670fb63d00f82e89595` before the original syntax experiment,
but it is no longer an unseen evaluation set for future changes.

The same report also records results for the ordinary Dart rules and
Proofbird/GECToR references. Those are different systems. Do not attribute
their scores or the recorded Dart/Flutter test counts to a native spaCy port.
The historical small GECToR C++ target is an implementation precedent, not a
spaCy inference test.

### Existing fixture inputs

Reuse the unchanged sentences, IDs, locales and expected outputs in:

- [`syntax_cases_20261117.json`](../../../tools/proofing/german_model/syntax_cases_20261117.json): 20 errors and 36 valid controls.
- [`prospective_cases_20261117.json`](../../../tools/proofing/german_model/prospective_cases_20261117.json): the separate 32-error/44-control panel.
- [`cases.json`](../../../tools/proofing/german_model/cases.json): the original 18-error/12-control panel.

The syntax evaluation uses `kind = clean` for controls. An earlier adapter to
the ordinary rule harness used the wrong category name; the existing report
retains that run but excludes it from qualified counts. When adapting these
files, assert that every source case appears once, classifications and locale
counts are preserved, and the harness actually scores every control. Keep
unsupported cases distinct from successful clean checks.

The saved Python token spans are **Unicode code-point offsets**, not Dart
UTF-16 offsets. They are useful reference observations, not ready-to-apply
editor findings. The new parity exporter must add independently calculated
UTF-8 byte and UTF-16 boundaries without changing the source text.

## Gate 1: reproducible identity and model admission

Before native execution, record and verify:

1. Original model artifact URL, byte count and hash; exact model configuration,
   component selection and source notices.
2. Reference spaCy/Thinc versions and dependency lock, reference exporter
   source revision/hash, Python version and platform.
3. Converter source revision/hash, schema version, complete tensor/metadata
   inventory, dimensions, dtypes, layouts and hashes of every converted asset.
4. Exact native source and GGML revisions, build flags/toolchain/target,
   compiled source list, linked dependencies and native artifact hash.
5. Fixture IDs and input hashes, locale policy, rule/planner revision, noun
   evidence identity and intended execution scope.

Reject unsupported architecture/schema, missing or extra required assets,
wrong source-model identity, wrong precision, wrong tensor dimensions,
duplicate names, invalid parser labels/edit-tree references and truncated
payloads before publishing a usable backend. Bound tensor counts and checked
allocation arithmetic. Check both lexical metadata and numeric weights;
matching a filename is not model authentication.

Exercise changed bytes with an unchanged file size, missing notices,
path-escape names, malformed counts, corrupt labels and model replacement
while a context is live. Models retained through memory mapping must remain
immutable for that lifetime. An unavailable or rejected bundle must not start
another process, execute publisher Python, send text to an endpoint or return
an empty successful result.

Model-free admission tests can use synthetic malformed fixtures. They do not
prove inference works. Model-dependent acceptance stages must require
explicit verified assets and fail with an actionable missing-asset result;
they must not silently skip and produce a green qualification receipt.

## Gate 2: lexical and numerical model parity

Create a new reference exporter for the exact enabled pipeline described in
[architecture.md](architecture.md). The existing agreement experiment omits
NER; use the same component selection for comparable outputs. Preserve the
source pipeline order and the disabled sentence recognizer. First export
small readable cases, then the frozen panels and boundary cases.

The proposed reference fixture format should bind each layer's input/output
to the same token IDs and original source. Keep raw F32 arrays in a specified
endianness and shape order with per-file hashes; keep summaries and mismatch
locations in JSON. These new intermediate fixtures do not already exist in
the repository's Python evidence archive.

| Stage | Required comparison |
| --- | --- |
| Tokenization | Exact surface tokens, whitespace treatment and byte/code-point/UTF-16 spans. No skipped token, normalization drift or guessed alignment. |
| Lexical features | Exact normalized attribute values, string/hash integers, embedding bucket IDs and seeds for all six feature columns. |
| Embedding | Exported tensor layouts and the combined/projected token vectors. |
| Four CNN layers | Window padding, intermediate affine/maxout/normalization/residual outputs and final shared tok2vec vectors. |
| Tagger and morphologizer | Raw class logits, label ordering, selected classes and final POS/morphological assignments. |
| Lemmatizer | Raw class logits, chosen tree, applicability/fallback result and final lemma. |
| Parser scorer | State feature indices, lower/upper scorer values, raw action scores and the legal-action mask. |
| Parser decoder | Chosen action at each step, tie handling, state changes, sentence boundaries and final dependency heads/labels after reconstruction. |
| Attribute ruler and full pipeline | Matched assignments and final complete token annotations in the source order. |

Use bit-exact comparison for discrete features, tokens, mappings and required
decisions. For F32 numeric arrays, record maximum/mean error and the tolerance
policy, justified by reference repeatability and numerical operations. Define
that policy before using it to excuse a port failure. Numerical proximity is
not sufficient if an action, lemma, tag or final dependency changes on a
required parity fixture. Report mismatches; do not silently overwrite a
golden fixture with native output.

When a discrepancy appears, find the earliest divergent stage. An upstream
token/hash error can make every later neural value wrong; changing decoder
thresholds cannot repair that. Test maxout axis/layout, normalization epsilon,
embedding sum order, padded contexts and parser validity masks specifically.
Re-running only final sentence strings is insufficient to localize a port.

Cover at least these input families: empty text; punctuation-only and repeated
whitespace; umlauts and `ß`/`ẞ`; NFC and decomposed accents; soft hyphens;
nonbreaking spaces and mixed newlines; abbreviations; apostrophes/dashes;
URLs/email; supplementary-plane characters, emoji and ZWJ sequences; multiple
scripts; unknown words; very long tokens; repeated identical substrings; and
input exactly at and beyond each declared limit. Exercise the explicit NUL
and malformed-text policy; never silently truncate. Over-limit behavior must
be deterministic and visible.

F32 CPU is the first qualification target. A quantized or accelerated recipe
gets a separate conversion/native identity and a repeat of the affected
parity and quality gates. Keep quantization effects separate from algorithm
port defects. No model size, GPU support or speed claim follows merely from
using GGML operations.

## Gate 3: bounded grammar behavior

The publication refresh includes PR #129's
[independent context qualification](../../validation/german-context-20261117/README.md).
Its ordinary Dart checker is the baseline for new comparisons. Reuse the
context, holdout and completion cases already in `tools/proofing/german_model/`
with their recorded provenance; they are existing development/evaluation cases,
not newly unseen holdouts. Preserve current deterministic corrections and
protection behavior. Report incremental model benefit explicitly rather than
comparing against a superseded default. Analysis parity alone does not justify
enabling model grammar with no demonstrated gain or new false positives.

Run the native annotations through the same independently testable guarded
Dart planner. Retain analysis-only comparison so a rule guard cannot hide
parser divergence. Match the chosen reference behavior on the frozen
development panels, including abstentions and unsupported outcomes. Any
intentional rule change needs a separate before/after record.

Mandatory controls include singular/plural `Leiter`, legitimate noun
ambiguity, expletive `es`, fronted objects, coordination, relative clauses,
quotation/metalinguistic use, names and unknown nouns, competing verb readings,
imperatives, personal vocabulary, ignored rules and regional spelling. The
model's chosen noun number must not override a compatible alternative from
the lexical evidence. Unknown or unresolved facts require abstention.

Use only reviewed replacement forms. Verify source casing and punctuation
preservation, exact replaced span, idempotent recheck, and that no suggestion
appears when a compatible interpretation makes the original valid. Scope
expansion beyond noun/finite-verb agreement requires its own cases and
replacement-form evidence; it cannot inherit this planner's finite scores.

Freeze a new independent panel before tuning additional rules or thresholds.
Record who/what authored it, when expectations were committed and which
outputs were already known. Once used for debugging, classify it as
development evidence. Report separate counts for exact target corrections,
missed targets, flagged/changed valid controls, unsupported inputs,
operational failures, suppressed proposals and abstentions. Small panel
counts are diagnostics, not population-level precision/recall claims.

## Gate 4: FFI, worker and editor safety

The application tests must exercise the real binding as well as model-free
tests of the protocol. Keep mock-backend results explicitly labeled. Verify:

- Allocation/result ownership, error-buffer bounds, version negotiation,
  invalid pointers/count combinations supported by the API contract, invalid
  returned head indices/spans and non-finite native scores.
- Byte-to-UTF-16 mapping on the original snapshot, nonzero request origins,
  grapheme-safe correction spans, well-formed replacement text and exact
  `originalText`. Include repeated substrings to detect accidental searching
  instead of coordinate mapping.
- Selection/body/story mapping, table paragraphs, mixed-language segments,
  protected fields/content controls, tracked revisions and locked ranges.
- Bounded queue saturation, same-key coalescing, timeout, cancellation during
  inference, disposal/replacement, startup failure, worker crash and late
  replies. Completing a cancelled caller must not free an in-flight slot or
  native context prematurely.
- Model/configuration, document, revision, locale, vocabulary and ignored-rule
  changes while a call is running. A result for an obsolete snapshot must not
  become a visible current finding or an applicable correction.
- Manual F7/document checks invoking the optional provider, typing debounce
  excluding it, provider status remaining visible and deterministic findings
  retaining precedence when secondary proposals overlap.
- Correction, recheck, undo/redo, ignore/restore, navigation and analysis-view
  stale/cancelled states through the existing controller paths.

Existing tests to extend or use as integration patterns include
[`word_manual_proofing_test.dart`](../../../packages/quds_office_editor/test/word_manual_proofing_test.dart),
[`word_proofing_session_test.dart`](../../../packages/quds_office_editor/test/word_proofing_session_test.dart),
[`word_proofing_correction_test.dart`](../../../packages/quds_office_editor/test/word_proofing_correction_test.dart),
[`proofing_report_merge_test.dart`](../../../packages/quds_office_engine/test/proofing/proofing_report_merge_test.dart),
and the GECToR package's worker/native/backend tests. Their current passing
history is not a result for code that has not been added.

The analysis type may represent contextual token boundaries inside an unusual
grapheme. A grammar edit still must satisfy the editor's stricter grapheme
checks. Do not force both contracts to pass by rounding offsets.

## Gate 5: real device and distribution evidence

Qualify the exact minimal native binary on each claimed target. Start with an
actual supported desktop CPU build, then intended iOS and Android devices.
Simulator or cross-compilation success alone does not qualify device behavior.
Web support remains unavailable until a separate Wasm backend is implemented
and measured.

Record cold load, warm request latency, tokenization/inference/decoding and
end-to-end time, peak/resident memory, model/native artifact size, queue size,
thread count, input lengths and cancellation/shutdown latency. Exercise long
paragraphs, repeated checks, model reloads, background/foreground transitions
and memory pressure. Set product limits from these measurements and report
their operating conditions. This handoff assigns no invented milliseconds,
megabytes, battery savings or supported token budget.

Inspect the final linked/packaged artifact: native source/dependency closure,
notices, signing/ABI support, model manifest and no Python runtime. Execute
with networking unavailable after the verified assets are installed; the
analysis must complete locally or report its actual local failure. Missing
assets must not trigger an endpoint request or SynanDaemon launch. Retain
App Store-specific distribution review separately as described in
[licensing-and-distribution.md](licensing-and-distribution.md).

## Commands: existing reproduction versus proposed stages

The existing Python experiment's real commands and dependency prerequisites
are in
[`SYNTAX_EVALUATION.md`](../../../tools/proofing/german_model/SYNTAX_EVALUATION.md).
Use an isolated developer environment and the pinned verified wheel. Those
commands run a Python reference experiment, not the proposed native backend.
No model should be installed or executed merely to create documentation.

**The following command interfaces are proposed and are not executable yet.**
Create the tools and their argument contracts before using them. Paths in
variables refer to explicit local verified artifacts; do not add automatic
downloads or CI-status polling to make a stage appear complete.

```sh
# Proposed developer-only oracle; this script does not yet exist.
python tools/proofing/spacy/export_reference.py \
  --model-directory "$QUDS_SPACY_SOURCE_MODEL" \
  --cases tools/proofing/german_model/syntax_cases_20261117.json \
  --output "$QUDS_SPACY_REFERENCE_DIR"

# Proposed standalone CrispEmbed target; this target does not yet exist.
cmake -S "$CRISPEMBED_CHECKOUT/tools/spacy" -B "$QUDS_SPACY_BUILD" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$QUDS_SPACY_BUILD" --parallel 2

# Proposed acceptance driver; must fail if model/native/oracle assets are absent.
python tools/proofing/spacy/qualify_native.py \
  --manifest "$QUDS_SPACY_MANIFEST" \
  --native-library "$QUDS_SPACY_NATIVE_LIBRARY" \
  --reference "$QUDS_SPACY_REFERENCE_DIR" \
  --output "$QUDS_SPACY_RECEIPT_DIR"
```

New package model-free tests may follow existing Dart package conventions.
The planned real-model acceptance command must remain a separate, explicit
gate, not a conditional skip buried in those tests. Run the affected existing
engine/editor tests when their integration changes; broaden verification to
resolve concrete remaining risks. **Do not wait on GitHub Actions**: use local
checks and clearly record any platform that cannot be exercised.

## Completion receipt and promotion criteria

Store new evidence under a dated validation directory and bind every retained
member to a manifest. Keep the original experiment archive unchanged. A
receipt must list source/model/native/fixture identities, actual commands,
environment, pass/fail/not-run status, numerical mismatch summaries, final
annotation differences, grammar outcome counts, device measurements and
remaining limitations. Distinguish repeated executions from unique cases.

Use the following promotion boundaries:

1. **Model admitted:** assets and native ABI satisfy the declared schema; no
   linguistic correctness claim yet.
2. **Native analysis qualified:** lexical, numeric, action and final-result
   parity passes for the declared reference fixtures and target runtime.
3. **Manual grammar qualified:** the guarded planner and actual editor path
   pass their finite controls with explicit coverage and operational outcomes.
4. **Platform qualified:** the exact packaged native/model artifacts pass on
   the named device/OS/architecture with measured limits and notices.

Do not register a default provider, claim a whole language is supported, or
replace an admitted artifact just because an earlier boundary passed. Missing
native assets or device access are recorded as uncompleted evidence, not
converted into success. Resume from the earliest unfulfilled boundary with
the immutable inputs and diagnostics retained.
