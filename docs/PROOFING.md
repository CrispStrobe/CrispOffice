# Spelling, hyphenation and grammar

Roadmap accepted: 16 November 2026. Baseline: `bad2d9d30fd94db8de92a4f4bf83a55b0692b884`.

This document retains the accepted P1–P8 plan and records the delivered
Rechtschreibprüfung, Silbentrennung and Grammatikprüfung scope in the CrispStrobe
fork. The initial roadmap commit precedes implementation. German spelling,
German hyphenation, selected writing rules and the Word review surface are now
implemented. English Harper and mobile system spelling remain optional
providers. The experimental German model remains evaluation-only.

Recovery resumed from saved checkpoint `066e07979d9e710c314158fe9909c9210769cb3b`,
which includes `main` at `e5e1e9af6beb0972a010d8208c1690a642809113`.
The [resumption audit](validation/proofing-20261116/resume-audit.json) checked
43 branches and 58 PRs: all other branch and PR heads were already included in
main, and no open PR needed integration at that snapshot. A later
[fixed-cutoff audit](validation/proofing-20261116/final/remote-freshness.json)
captured 48 branch heads and 59 PRs, with no open PRs. The continuation integrates
main's PR #59 ODS hyperlink preservation, concurrent Zotero identity/backoff and
dialog changes, and the useful changes and regression cases from the sibling
proofing-resume branch. The [reconciliation record](validation/proofing-20261116/final/reconciliation.json)
identifies the exact incoming heads and merge decisions. Work is checkpointed
on `codex/proofing-20261116`. Verification below distinguishes retained records
from new local runs; counts in the interrupted chat are not substituted for
source-bound evidence.

## Using proofreading in Word

1. Press **F7** or choose **Spelling** in the example workspace to open
   **Spelling and writing**. The dialog checks all modeled stories and shows
   each finding's story, language, explanation and source context.
2. Set **Default document language** to German for Germany, Austria or
   Switzerland, or to the offered US/UK English variant. Imported paragraph
   and run language overrides still take precedence. Interface direction and
   translation do not choose the document language. Untagged documents use
   `de-DE` for proofing until an explicit default is saved.
3. Use **Automatic German hyphenation** to change layout. The setting is saved
   in DOCX. Enabling it on an untagged document saves the displayed language
   together with the toggle in one undoable change. Only supported German
   languages receive automatic candidates; authored soft hyphens work
   independently of this toggle.
4. Review the squiggles and offered replacements in the dialog or a correction
   context menu. Each applied suggestion is one undoable command. **Ignore
   once**, **Ignore word**, **Add to personal words**, and **Ignore this rule**
   keep the choice explicit. Findings are never applied automatically.
5. Expand **Checking status** when a check is incomplete. Unavailable providers,
   unsupported languages, failures/timeouts and successful checks are separate
   outcomes. A successful empty result means no findings in the checked text;
   it is not a claim of comprehensive German grammar coverage.

**Enable proofreading** controls the current session. Document-language and
hyphenation changes are disabled when the host/document forbids mutation;
read-only text can still be reviewed. Corrections additionally respect content
controls, generated fields, pending tracked changes and active IME composition.
With track changes enabled, a replacement retains the original as a deletion
and the offered replacement as an insertion for normal acceptance/rejection.

The default reusable `WordEditorController` supplies German spelling and writing
rules. The example workspace also configures Harper, but English checking
reports unavailable until its native library or hosted worker assets are
installed. The mobile system provider is not enabled automatically.

## Scope and license policy

- Keep `quds_office_engine` pure Dart and document surfaces custom RenderBox.
- Ship offline German spelling, automatic German hyphenation, and independently
  authored German typography/style and narrowly scoped grammar rules.
- Add an optional Harper backend for English grammar and an optional mobile
  platform spelling backend. Provider absence must be visible to the host.
- Evaluate the experimental German ONNX model separately; do not enable it by
  default or claim broad German grammar coverage from a limited rule set.
- Accept MIT, BSD, Apache and MPL components with their actual obligations.
  Do not add GPL/AGPL or LGPL-only components, dictionaries or rules under this
  plan. An explicitly selectable MPL alternative is acceptable.
- Review engine code, dictionary/affix data, hyphenation patterns, rules, model
  weights, wrappers and transitive dependencies separately. Pin upstream inputs,
  preserve notices, and retain a reproducible data-generation path.
- Do not import igerman98/de_DE_frami or the GPL German `dictionary-de` assets,
  LibreOffice's LGPL-converted German hyphenation data, LanguageTool/nlprule
  language resources, or unverified package example word lists.

## Baseline findings retained from the accepted plan

At the accepted baseline, `OfficeSpell` was a host callback or supplied-word-set
lookup. With neither it returned an empty list. The example's F7/Spelling action passed no checker and
reported "No issues (host dictionary)". The controller checked only the active
paragraph; there was no diagnostic decoration or correction menu. That callback
API remains available for legacy callers; the new Word UI uses the explicit
proofing service instead.

The baseline `LineBreaker` recognized explicit hyphens and U+00AD break positions
but had no linguistic break generator or complete discretionary-hyphen handling.
Word source XML could preserve proofing/hyphenation properties without exposing
them as live model settings, and no grammar provider was implemented.

## Delivery sequence and current status

Every row started as **Planned** in the accepted roadmap. The acceptance column
is retained; status records the implementation and the remaining platform gates.

| ID | Work | Current status | Acceptance |
| --- | --- | --- | --- |
| P1 | Shared asynchronous proofing contract, language selection and availability | Implemented; validated shared contract | Unavailable/unsupported/error and successful empty results remain distinct; findings carry stable block identity, revision, UTF-16 ranges, category, rule ID, explanation and replacements. |
| P2 | Automatic German and explicit discretionary hyphenation | Implemented; engine/editor/PDF local regressions passed | Licensed patterns produce measured break candidates in shared editor/PDF layout; unchanged source text, correct soft-hyphen behavior, grapheme and bidi integrity, Word setting round-trips. |
| P3 | Offline German spelling and user vocabulary | Implemented; finite German vocabulary with explicit limits | Approved MIT word data with pinned provenance; case/locale-aware membership; bounded useful suggestions; personal words/ignore controls; meaningful positive and negative tests. |
| P4 | German style and limited grammar rules | Implemented; seven advisory checks and configurable terminology | Independently authored rules with documented coverage/exclusions; valid repeated German words and regional spelling remain accepted; no silent rewrites. |
| P5 | Word proofing UI and lifecycle | Implemented; full-story session and review UI | Real configured provider, full document traversal, background/stale-result handling, squiggles, F7 results and undoable suggestions; disabled or unsupported providers never imply a clean check. |
| P6 | Optional English Harper and mobile spelling adapters | Implemented; Linux/Node/Wasm and mock mobile checks; browser/device gates remain | Working provider protocol and supported-platform wiring; backend-specific offsets mapped to UTF-16; adapter and integration tests; licenses and operational setup documented. |
| P7 | German model evaluation | Evaluated separately; retained probe, disabled in application | Inspect exact artifacts and notices; reproducible evaluation entry point, representative correctness checks and measured runtime where executable; record unavailable gates honestly; no default model activation. |
| P8 | Integration and documentation | Local integration and evidence recorded; platform limits below | Analyze/test affected packages, editor/layout/export and serialization regressions, dependency/data license manifest, complete release notes and source-bound verification record. |

## Chosen components and data

### Hyphenation

The delivered engine uses an independently authored pure-Dart Liang trie with
36,709 original MIT `hyph-de-1996.tex` patterns, version `2024-02-28`, pinned to
tex-hyphen commit `5684c0f51c0b81133db2efbe60a408b4155a3ff5`. The external Dart
`hyphenation` package was an initial candidate; it is not a runtime dependency.
The [provenance and regeneration instructions](../packages/quds_office_engine/third_party/hyphenation/README.md)
retain the exact upstream source, license and digest.

The same modern patterns serve `de-DE`, `de-AT` and `de-CH` with two-letter
minimum fragments. Automatic candidates respect language boundaries and
paragraph suppression. Selected breaks include the visible hyphen's measured
width. Unselected U+00AD remains invisible; a selected automatic hyphen owns
zero source units, while selected U+00AD owns its original UTF-16 unit.
Editor paint runs, caret/selection geometry and shared PDF layout preserve
that ownership. Automatic hyphenation does not insert permanent hyphens into
source text or copied PDF text. DOCX retains document settings, paragraph/run
language, `noProof`, suppression, and independent native language metadata.

### Spelling

The shipped vocabulary contains **444,123 standard word forms** and **9,451
Swiss additions**. It combines the pinned 1 May 2016 MIT DANTE/Werners Wortliste
mirror at `4330a0b1254e88615cb4c83e4b3dc2f0810c76d9` with a small independently
authored MIT supplement. The generator selects modern orthography explicitly;
importing every source entry would incorrectly admit historical forms such as
`daß`. Exact inputs, counts and generated hashes are in the
[data manifest](../packages/quds_office_engine/third_party/proofing/manifest.json).

This is finite word-form membership, with bounded suggestions and explicit
hyphen-compound support. It does not implement complete morphology,
unrestricted closed-compound decomposition, or a contemporary comprehensive
German dictionary. `de-DE` and `de-AT` share the source vocabulary; it is not an
exhaustive Austrian regional lexicon. `de-CH` applies the documented modern
Swiss variants and rejects sharp-s forms. New terms, proper names and unlisted
inflections may need personal words or an ignore choice.

Lookup normalizes common decomposed accents and soft hyphens without changing
source text or finding offsets. German noun case remains significant;
sentence-initial and all-capital forms use the corresponding accepted lookup.
URLs and email addresses are excluded. Data decoding and token batches yield
cooperatively, including when compiled to JavaScript. See
[German spelling scope and reproduction](../packages/quds_office_engine/third_party/proofing/README.md).

Hunspell remains a possible later adapter if an acceptable complete dictionary
is available. It is not shipped by this implementation.

### German writing rules and terminology

`GermanWritingRulesProvider` provides seven independently authored checks:

| Rule | Actual boundary |
| --- | --- |
| `de.spacing.repeated` | Repeated interior spaces, with numeric spacing exceptions |
| `de.spacing.before-punctuation` | Spaces before selected punctuation |
| `de.spacing.after-punctuation` | Missing spaces after comma/semicolon before a letter |
| `de.repetition.conjunction` | Immediate repetition of `und`, `oder` or `aber` |
| `de.grammar.pronoun-verb` | Selected adjacent `ich`/`du`/`wir`/`ihr` and `sein` mismatches |
| `de.delimiter.balance` | Paragraph-local bracket balance; review only |
| `de.quote.balance` | Paragraph-local typographic quote balance; review only |

These rules skip their supported URL, email and inline-code forms. They do not
perform general syntax, agreement, word-order or comma analysis. Natural
repetitions such as “Ist das das Haus?” remain accepted. A quotation spanning
paragraphs can legitimately produce a balance advisory; such findings have no
automatic rewrite. Spelling, grammar and style are distinct finding categories.

Hosts can additionally supply `OfficeTerminologyProvider` with literal
`OfficeTerminologyRule` entries: rule ID, term, explanation, replacements,
language filters, case sensitivity and whole-word matching. No organization
terminology list is assumed or installed by default.

### Optional English and mobile providers

[quds_proofing_harper](../packages/quds_proofing_harper/README.md) pins real
Harper 3.2.0 and upstream revision
`ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3`. The native wrapper runs in a
persistent Dart isolate; the web wrapper runs in a module Web Worker with
Wasm. Document text remains local. English scalar offsets are converted to
Quds UTF-16 offsets, including after emoji and within a segmented paragraph.

Install/package the optional backend using that package's build instructions:
Rust 1.100.0, the pinned `wasm-bindgen` tooling, and
`python3 packages/quds_proofing_harper/tool/build.py --native --web`.
Native hosts provide a library path or `QUDS_HARPER_LIBRARY` Dart define.
Web hosts serve the worker, generated JavaScript and Wasm together at the
configured `proofing/` path and permit them in their CSP. No CDN or remote
grammar-service fallback is used. Missing/incompatible assets are unavailable,
other languages are unsupported, and timeout/request-limit failures are
explicit. Limits are 32,768 Unicode scalars and 2,000 findings per request.

Harper is Apache-2.0 and the wrapper is MIT. The build's
[license manifest](../packages/quds_proofing_harper/licenses/manifest.json)
and original notice/MPL source archive must ship with the backend. The actual
transitive graph also records reviewed ancillary Unicode-3.0, Zlib, CC0-1.0 and
target-specific ISC terms; these are not relabeled as MIT/BSD/Apache/MPL.
Unknown license expressions, missing notices and GPL/AGPL/LGPL-only dependencies
stop packaging. Target-specific builds require the same audit for their graph.

`OfficePlatformSpellingProvider` is an optional Flutter Android/iOS adapter.
The host declares dictionaries actually installed on the device. It serializes
system-channel calls, clears locale-insensitive cache entries between requests,
and treats a null platform result as failure rather than successful empty
output. Its local tests use a mock service; no device acceptance is claimed.

### Experimental German model: retained evaluation only

The separate [evaluation harness](../tools/proofing/german_model/README.md) pins
`proofbird/gector-bert-de` v2.1.0 at
`8e3b50beef7d775cedb7b876009e88bcf2e8d6af`, its exact Apache-2.0 LICENSE and
NOTICE, the unmodified reference runner, and every model/tokenizer artifact.
The model and Python inference environment are not part of the application.
The recorded evaluation dependency inventory is separate from the audited
application shipping manifest; it is not approval to distribute that entire
Python environment under the application's license policy.

The retained recovered-checkpoint probe matched **9 of 18** expected error
corrections and changed **1 of 12** valid controls: Swiss `ich heisse` became
`ich heiße`. This continuation did not rerun that model evaluation. The
[record](validation/proofing-20261116/german-model-evaluation.json) includes all
synthetic inputs/outputs, artifact hashes and runtime measurements. The small
probe is not a population accuracy estimate. The reference runner omits the
publisher's app guards and OS spelling guards, so published app scores do not
apply to it. Deterministic German providers remain the application default.
Commercial services, accounts, purchases and document uploads remain outside
this scope.

## Integration contracts and host responsibilities

The engine remains pure Dart; the editor remains a custom RenderBox surface.
`OfficeProofingService` validates document/block/revision identity, UTF-16 and
grapheme boundaries, original text and provider identity before publishing
findings. A document session splits only where language, `noProof`, generated
fields or other exclusions require it, preserving paragraph source offsets
across ordinary formatting runs.

### Document stories and navigation

The session traverses body paragraphs, nested tables, frames, footnotes,
endnotes, all modeled default/first/even header/footer variants, and comments.
Paragraph identity distinguishes contained stories even when their display
indexes overlap. Modeled generated fields, TOC content, `noProof` spans and
pending deleted revisions are excluded. Opaque blocks/inlines and preserved
unmodeled stories are counted as unsupported; they prevent a complete clean
claim. The dialog displays paragraph/segment and exclusion counts.

**Go to text** navigates current body paragraphs (including supported table and
frame paragraphs), comments, and standard headers/footers that are actually
present on a rendered page. Header/footer navigation matches the source
paragraph and section; it does not substitute a first/even variant. Notes and
first/even header/footer variants remain reviewable and correctable through
their actual source paragraph in the dialog, without canvas navigation.
Visible modeled note/header/footer text
can carry squiggles; a source-owned mapping prevents a note number, generated
page label or trimmed header fragment from borrowing another range.

### Results, editing and lifecycle

Background checks use a 350 ms default debounce, unchanged-paragraph caching,
and an index of findings for painting. Completed requests are discarded when
the document, paragraph source/signature, language, configuration, vocabulary or
revision changes. Expensive German work yields in batches; Harper uses its
isolate/worker. A host that mutates model objects directly calls
`controller.proofing.invalidate()` after the mutation.

Corrections use ordinary command history, preserve run/source structure, and
reject protected content, generated/atomic ranges, stale results, active IME
composition and unsafe overlaps with existing tracked changes. A changed-length
correction updates the active selection; undo restores text, revision state and
selection. Findings remain ephemeral and are not serialized into documents.

`QudsWordEditor` and the review dialog acquire background checking while mounted
and release it when detached. Multiple views can share a controller. A host
using the session independently can call `start()`/`stop()`; controller disposal
disposes its owned session/service. `configureService(..., ownsService: false)`
allows an explicitly shared service to retain host-owned disposal. A raw
`WordCanvas` integration supplies `proofingFindings` from the session and
connects its review/correction actions.

### Personal vocabulary and custom providers

`OfficeProofingVocabulary` has one explicit `ownerId`, language-scoped personal
and ignored words, a revision and `toJson()`/`fromJson(...)` snapshots. Supply it
with `WordEditorController(proofingVocabulary: vocabulary)`. The session exposes
`onVocabularyChanged` for host persistence and `restoreVocabulary(snapshot)`
for a matching owner's saved snapshot. Restoring another owner's vocabulary is
rejected. The sample's `studio-local` vocabulary is in memory; the application
host must wire persistence if words should survive closing it.

The engine never writes these words into the bundled dictionary or DOCX and
never shares them across accounts. **Ignore once** and ignored rule IDs are
session choices. To add Harper, platform spelling or terminology, configure an
`OfficeProofingService` with the desired providers; retain the same vocabulary
instance in `GermanSpellingProvider` when replacing the default service.
Provider absence and unsupported languages remain visible to callers.

## Acceptance cases retained from the plan

These cases define the delivered regression scope and the remaining platform
acceptance work:

- No provider, unsupported language, provider error and clean text have distinct
  results and UI messages.
- German casing, umlauts, decomposed characters, `ß`/`ss`, Swiss conventions,
  accepted/rejected word forms, proper/user terms and suggestion bounds.
- Non-BMP characters before issues, split formatting runs, multiline ranges,
  edits during asynchronous checks, and correct undo of a replacement.
- Natural German repeated words, punctuation exceptions and rule opt-outs.
- Automatic and explicit discretionary hyphens at fitting/non-fitting widths;
  unchanged logical text, exact source consumption, bidi/grapheme boundaries,
  editor/PDF parity and DOCX settings/property preservation.
- Full document traversal including table/note/header/footer paragraphs where
  the current model exposes them; no silent active-paragraph-only claim.
- Provider native/web transport and offset conversion against actual backend
  output when executable, with unsupported cases reported rather than faked.

## Verification record

The records below identify commands, source hashes and operational limits.
Counts overlap between focused and broader suites and must not be added into a
single unique-test total. No GitHub Actions queue was waited for.

| Evidence | Recorded scope/result | Provenance |
| --- | --- | --- |
| [Resumption audit](validation/proofing-20261116/resume-audit.json) | 43 branch heads, 58 PR heads, no outstanding integration at the audit snapshot | New read-only remote audit |
| [Final remote audit](validation/proofing-20261116/final/remote-freshness.json) and [reconciliation](validation/proofing-20261116/final/reconciliation.json) | Fixed cutoff of 48 branch heads and 59 PRs; main, Zotero and sibling proofing changes reconciled | Later read-only audit and explicit merge decisions |
| [Hyphenation engine receipt](validation/proofing-20261116/hyphenation-resume/engine/hyphenation-validation.json) | 232 engine tests; strict analysis and exact pinned-pattern regeneration passed; source unchanged during checks | New local continuation run |
| [Hyphenation/editor receipt](validation/proofing-20261116/hyphenation-resume/editor/receipt.json) | 19 painter/note/small-capital tests, including seven new cases and widget timer ownership; source unchanged during checks | New local continuation run |
| [Harper/platform receipt](validation/proofing-20261116/harper-resume/receipt.json) | Real Linux native and Wasm builds, Dart native/Node adapter checks, exact worker and compiled Dart web transport smoke checks, four mocked platform-adapter tests and three license-policy tests | New local continuation run |
| [Merged Harper receipt](validation/proofing-20261116/final/harper-merged/receipt.json) | 5 Rust, 12 native Dart, 8 Node provider, 5 Wasm worker, 8 compiled Dart web transport, 3 license and 2 packaging tests; strict analysis clean | Rebuilt and verified after sibling-branch reconciliation |
| [Merged renderer receipt](validation/proofing-20261116/final/hyphenation-merge/receipt.json) | 41 renderer/note/selection cases; all eight incoming cases retained; strict targeted analysis clean | New local merge validation |
| [German core continuation receipt](validation/proofing-20261116/german-resume/receipt.json) | 38 shared/German tests, dictionary byte-for-byte regeneration, strict analysis and ten compiled-JavaScript checks; source unchanged during checks | New local continuation run |
| [Earlier German core receipt](validation/proofing-20261116/german-core/receipt.json) | Earlier 38-test/ten-JavaScript run retained for its own source snapshot | Retained recovered-checkpoint evidence |
| [Final integration receipt](validation/proofing-20261116/final/receipt.json) | Consolidated session, UI, context-menu and affected-package checks; exact counts, source hashes and commands in the receipt | Final local continuation evidence |
| [German model probe](validation/proofing-20261116/german-model-evaluation.json) | 9/18 exact error corrections; 1/12 valid controls changed | Retained evaluation only; not rerun or enabled |

The [hyphenation validation notes](validation/proofing-20261116/hyphenation-resume/README.md)
explain the exact geometry/source fixes and reproduction commands. Session
correctness is covered in
[`word_proofing_test.dart`](../packages/quds_office_editor/test/word_proofing_test.dart),
including full-story traversal, mixed-language coverage, stale results,
content-control/field/protection guards, IME composition, tracked corrections,
shortened-correction caret behavior, vocabulary and view lifetime. Consolidated
session/UI results and subsequent style-inheritance checks are recorded with
the [final integration evidence](validation/proofing-20261116/final/README.md)
rather than attributed to the earlier receipts.

### Remaining acceptance boundaries

- Chromium startup failed because the execution environment denied `socket()`.
  The exact shipped Wasm worker and compiled Dart web transport passed through
  a Node worker/file-fetch bridge; this does not establish browser HTTP/CSP,
  browser painting, or end-user browser acceptance.
- Linux native Harper was executed. Other desktop native targets require their
  own build/runtime and distribution acceptance.
- Android/iOS system spelling was tested through a mocked adapter, not a device
  with installed dictionaries. Device behavior remains a separate gate.
- The finite German vocabulary, seven advisory rules, paragraph-local quote
  checks and navigation limits above are product boundaries, not hidden test
  passes. The experimental model is not a production German grammar backend.

## Primary sources

- [Dart hyphenation package](https://pub.dev/packages/hyphenation)
- [Engine MIT license and notices](https://github.com/arxdeus/hyphenation/tree/main/packages/hyphenation)
- [Original German patterns and embedded MIT license](https://github.com/hyphenation/tex-hyphen/blob/master/hyph-utf8/tex/generic/hyph-utf8/patterns/tex/hyph-de-1996.tex)
- [DANTE word-list licensing](https://wiki.dante.de/trennmuster/korpora)
- [Wortliste source](https://repo.or.cz/wortliste.git)
- [Hunspell alternative license grant](https://github.com/hunspell/hunspell/blob/master/license.hunspell)
- [German dictionary GPL data / MIT wrapper distinction](https://github.com/wooorm/dictionaries/blob/main/dictionaries/de/readme.md)
- [Harper](https://github.com/Automattic/harper)
- [Harper span convention](https://writewithharper.com/docs/harperjs/spans)
- [Flutter platform spelling service](https://api.flutter.dev/flutter/services/DefaultSpellCheckService-class.html)
- [German ONNX model card](https://huggingface.co/proofbird/gector-bert-de)
