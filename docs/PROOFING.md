# Spelling, hyphenation and grammar

Roadmap accepted and implementation resumed: 16 November 2026. Original
baseline: `bad2d9d30fd94db8de92a4f4bf83a55b0692b884`.

The CrispStrobe fork implements offline German spelling, automatic German and
US/UK English hyphenation, eight German writing-rule categories, and a
document-wide Word proofing session with reviewable corrections. Local Harper
English spelling and grammar remain optional and require packaged native or
web assets. Mobile system spelling has an adapter with protocol tests; the
experimental German model remains a separate evaluation.

## Current English/German continuation — 17 November 2026

The [current continuation report](validation/proofing-en-de-20261117/README.md)
records the integrated incoming histories, incremental remote checkpoints,
local runtime receipts and qualification boundaries. The qualified source is
`b9ac68fbbb33c7731a3241e4065f6dfb71e36a57`: all 135 distinct heads across the
initial and later inventories are ancestors. The later documentation-only main
`f57d8f5` is also retained, with unchanged qualified source inputs.

This continuation adds:

- Shared protected URL/email/backtick ranges for English and German proofing
  and hyphenation, including decomposed email domains, URI apostrophes,
  original UTF-16 coordinates and bounded delimiter pairing.
- German hyphenation guards for identifiers, contractions and join controls,
  plus canonical `de`/`de-DE`/`de-1996` language equivalence across styled runs.
- Bounded combined spelling suggestions such as `uebermaessig → übermäßig`,
  declared personal terms in explicit hyphen compounds, sentence-initial
  suggestion casing and lossless restoration of vocabulary language aliases.
- Agreement checks for 25 finite German verb families, narrow `seit`/`seid`
  contexts, nominal-word safeguards and source-preserving soft-hyphen projection.
- English Harper findings that leave protected text untouched while continuing
  to check surrounding prose, with real native and Wasm source-range acceptance.
- Review-dialog correction/undo and rule-ignore regressions for the new German
  behavior, and local compiled-JavaScript coverage alongside Dart VM tests.

All dictionary/pattern inputs, Cargo/Pub dependency constraints and existing
license notices remain unchanged; incoming standalone original English notices
are retained and verified. The fresh local gate passed strict analysis, 258
hyphenation/layout/export tests, 23 compiled-JavaScript hyphenation tests, 95
German proofing tests on each of VM and Node, 376 incoming engine regressions,
304 selected editor tests, a separate IME regression, and a release web build
with verified Harper assets/notices. The same-turn real Linux native and
Node/Wasm qualification remains bound to matching source/artifact hashes.
All 2,083 recorded inputs and runtime hashes stayed unchanged. Groups overlap;
this is not a repository-wide test count. Real Chromium startup was blocked by
the workspace before loading a page; no browser/CSP or mobile-device acceptance
is claimed. No GitHub Actions queue is used or waited on. The
[16 November handoff](validation/proofing-en-de-20261116/README.md) retains its
original source/reference-only qualification limits.

The earlier locally qualified proofing source is
**`8b93e866b4661d19f4bbad4e1069c0a609441ebb`**. Its
[completed continuation report](validation/proofing-20261116/continuation-hardening/README.md)
retains those historical results and source-bound handoff evidence.

This document retains the accepted roadmap and license rationale, and records
the delivered behavior and its validation limits. Recovery reconciled the
concurrent original branch through `976d05a` into the continuation at
`d3b37a99ff039730472ff33ba31db2ed4606a1ae`, with the original checkpoint as a
second parent. The subsequent reconciliation includes `main` through
`7edb096d3328263c75dc0229ff43bb77183e1ad3` (the four incoming ODS PRs), the
independent Zotero improvements from
`b6a6b4c42ad03eb8d0f8567e7800bb9e4e038fdb`, and the useful original-branch
proofing fixes through `93c13aa1315298c0f85a5a8b757042eb9ac435e1`. The earlier
integrated source was **`ca294cf8668706b45f40031ed9a2db52e5737cd2`**, whose
parents retain those three incoming histories and the continuation checkpoint.
The remote inventory covered **53 branches and 62 pull requests** at the
**2026-11-16 13:40:49 UTC** cutoff. The earlier
[remote audit](validation/proofing-20261116/resume-remote-audit.json) and
[final integration evidence](validation/proofing-20261116/integration-resume/README.md)
distinguish preserved evidence from freshly executed checks. No GitHub Actions
queue was required.

## Earlier qualified continuation after the 9d90518 handoff

The latest integration retains **all 64 observed branch heads and all 68 PR
heads** from the **16 November 2026, 15:39:54 UTC / 16:39:54 CET** inventory.
It includes the complete `9d90518` handoff, shaped text rendering through
`c9fc24c`, main through `91f82b8`, and the conditional/validation ODS writer
through `ec94795`. The integration is saved at `e9bb38e`, followed by proofing
improvements at `731d370` and two incoming test-only analysis fixes at `8b93e86`.
All 228 files in the handoff's proofing validation directory remain unchanged.

German proofing now keeps protected URL/email subjects out of agreement
corrections, recognizes uppercase HTTP(S)/WWW prefixes, and distinguishes
surrounding prose punctuation from balanced URL parentheses and IPv6 brackets.
Swiss `STRAẞE` and `GRÜẞE` offer `STRASSE` and `GRÜSSE`; standard German keeps
accepting the capital sharp-s forms. These are refinements to the existing
word-list checker and seven writing rules.

Invisible zero-width break opportunities and no-break controls now survive
all wrapping paths while preserving source offsets. In the review dialog,
space replacements have visible labels such as **Insert space** and
**Use space**. The **Ignored checks** section restores words in their original
language, rules, and ignored occurrences without changing document text,
personal words, other language preferences or undo history.

The final source passed full engine/editor/host strict analysis, **347 selected
editor tests**, the separate IME regression, **295 layout/export/shaping tests**,
**503 incoming ODS/Zotero/comment regressions**, and a release web build.
German component checks passed **54 Dart tests**, the existing **10 compiled-JS
checks**, and **20 targeted compiled-JS checks** for the new behavior.
Harper contracts passed **8 provider tests and 3 native guards**, with the real
native-library test explicitly skipped. All recorded inputs remained unchanged
during the final runs. Groups overlap and are not a repository-wide total.

The [current verification report](validation/proofing-20261116/continuation-hardening/README.md)
retains commands, full logs, failed attempts, runtime/dependency receipts,
compressed manifests and reproduction instructions. Dictionary/pattern data,
Harper source, model evaluation inputs and package manifests match the handoff.
No GitHub Actions endpoints were queried or waited for.

## Earlier continuation reconciliation after both handoffs

The completed continuation integrates the original branch through `c040389`,
Zotero capabilities through `2480f09`, main through `90024d5`,
and dialog input/ruler work through `2e92a49`. The
[reconciliation record](validation/proofing-20261116/continuation-next/README.md)
accounts for **58 observed branches and 66 PRs** at the
**2026-11-16 14:27:44 UTC** cutoff. All 58 observed heads are ancestors of
`bfb24bf`, confirmed by individual GitHub comparisons; the final source
descends from that integration.

Both prior validation histories are retained, including the complete original
`c040389` logs and compressed manifests. Their
[evidence-integrity check](validation/proofing-20261116/integration-followup/evidence-integrity.json)
found all original files unchanged.

The fresh editor/host run passed at **`3bd4657b1c1cccfad8adbcf5928e30b90e4a1aaa`**:
strict engine, editor and example analysis; **294 selected editor tests**;
the separate IME regression; and a successful release web build. All
**2,032 source inputs**, runtime hashes, workspace lock and package
configuration remained unchanged. The earlier fresh engine component run at
`6f87a4e` passed **49 German tests**, **10 compiled-JavaScript checks**,
**231 hyphenation/layout/export tests**, **496 incoming ODS/Zotero/comment
regressions**, and exact dictionary/pattern regeneration. The
[source comparison](validation/proofing-20261116/integration-followup/source-scope-comparison.json)
confirms unchanged engine and Harper inputs between those tested revisions.

This continuation improves standalone mark/soft-hyphen handling, internal
apostrophes, conservative German agreement checks, grapheme-safe findings,
hyphen caret/hit ownership, empty-document and header/footer navigation, and
input ownership across route/controller changes. Body finding navigation
clears object-editing targets before selecting source text. Non-mutating
selecting mode retains keyboard navigation.

The [earlier verification report](validation/proofing-20261116/integration-followup/README.md)
links the complete receipts, commands, logs, compressed manifests, reproducible
runtime setup and retained failed attempts. Test groups overlap and are not a
repository-wide total. The fresh Harper results cover provider/lifecycle and
packaging/license tests; no new real-library/Wasm execution is claimed.
The experimental German model remains disabled and was not rerun.

## Scope and license policy

- Keep `quds_office_engine` pure Dart and document surfaces custom RenderBox.
- Ship offline German spelling, automatic German and US/UK English hyphenation,
  and independently authored German typography/style and narrowly scoped grammar
  rules. The English pattern licenses are reviewed individually below.
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

The optional Harper dependency audit also records reviewed ancillary
Unicode-3.0, ISC, Zlib and CC0-1.0 terms individually. These are not relabeled as
MIT or Apache. Its generated [manifest](../packages/quds_proofing_harper/licenses/manifest.json)
and notice/source archive cover the actual 226-package resolved graph, including
three MPL source archives. Unknown license expressions, missing original
notices and GPL/AGPL/LGPL-only components stop packaging. See the
[backend license boundary](../packages/quds_proofing_harper/README.md#license-boundary)
for selection and provenance checks.

## Baseline findings

At the original baseline, `OfficeSpell` was a host callback or supplied-word-set
lookup. With neither it returned an empty list. The example's F7/Spelling action
passed no checker and reported "No issues (host dictionary)". The controller
checked only the active paragraph, without diagnostic decoration or a correction
menu. The new Word path uses `OfficeProofingService` and `WordProofingSession`;
unavailable proofing cannot produce a successful clean-check message.

The original `LineBreaker` recognized explicit hyphens and U+00AD positions but
had no linguistic break generator or complete discretionary-hyphen handling.
Word source XML preserved some proofing/hyphenation properties without exposing
them as live settings. Those gaps now have a shared layout implementation,
live model properties and Word serialization coverage.

## Delivery sequence

| ID | Work | Delivered status | Acceptance and boundary |
| --- | --- | --- | --- |
| P1 | Shared asynchronous proofing contract, language selection and availability | Implemented | Distinct unavailable, unsupported, failed and successful results; stable document/block identity, revision, UTF-16 ranges, category, rule ID, explanation and literal replacements. |
| P2 | Automatic German/US/UK English and explicit discretionary hyphenation | Implemented | Licensed patterns and measured break candidates in shared editor/PDF layout; source text unchanged, grapheme/bidi and source-hit coverage, Word setting round-trips. |
| P3 | Offline German spelling and user vocabulary | Implemented | Pinned MIT finite word forms, locale/case handling, bounded suggestions, host-owned vocabulary and ignore controls; no claim of complete German morphology. |
| P4 | German style and limited grammar rules | Implemented | Eight independently authored checks and a host terminology provider; explicit exclusions and reviewable suggestions. |
| P5 | Word proofing UI and lifecycle | Implemented | Whole-story traversal, manual/background checks, stale-result rejection, squiggles, F7 review, correction menu and guarded undoable corrections. |
| P6 | Optional English Harper and mobile spelling adapters | Implemented with runtime limits | Actual Linux native and Node/Wasm integration exercised; browser startup blocked before loading a page; mobile adapter protocol tested without Android/iOS device acceptance. |
| P7 | German model evaluation | Evaluated; not enabled | Exact artifacts and original notices retained; recorded probe matched 9/18 error cases and changed 1/12 valid controls. No application provider or automatic model download. |
| P8 | Integration and documentation | Current source locally qualified and remotely saved | Source `b9ac68f` passed strict analysis, VM/JavaScript language checks, 376 incoming regressions, 304 selected editor tests, separate IME regression and release web packaging. Matching-source real Linux native and Node/Wasm Harper evidence is verified. All 2,083 input hashes stayed unchanged; browser startup and device acceptance limits are explicit in the current report. |

## Chosen components and data

### Hyphenation

The German implementation retains its small, independently authored pure-Dart
Liang trie and the original MIT `hyph-de-1996.tex` patterns. English adds a
separate pure-Dart matcher with the upstream exception lists; `OfficeHyphenator`
dispatches both through shared layout. The initially reviewed `hyphenation`
1.0.2 package was not adopted. No runtime dependency or service is added.

The 36,709 patterns are generated from tex-hyphen commit
`5684c0f51c0b81133db2efbe60a408b4155a3ff5`, pattern version `2024-02-28`.
The unchanged source contains its full MIT notice and underlying Wortliste
revision. The generator verifies its pinned SHA-256 before conversion and
retains the notice in the generated Dart file. See the
[provenance and regeneration instructions](../packages/quds_office_engine/third_party/hyphenation/README.md).

The modern German pattern set serves `de`, `de-DE`, `de-AT` and `de-CH`, with
minimum fragments of two letters. English uses 4,938 US patterns/14 exceptions
for `en` and `en-US`, and 8,527 British patterns/eight exceptions for `en-GB`.
English breaks leave two letters before and three after. The US source's
explicit permissive grant is recorded as `LicenseRef-Kuiken-permissive`; the
British patterns use MIT. Complete notices and immutable originals are retained.
The restricted underlying OUP word list is not included. See
[English provenance and reproduction](../packages/quds_office_engine/third_party/hyphenation/ENGLISH.md).

Other languages, including other English dialects, receive no automatic
candidates. English conservatively skips unsupported accented words,
contractions, identifiers, protected URL/email/code spans and fragments adjoining
join controls. A word crossing genuinely different language tags is skipped;
equivalent `en`/`en-US` tags remain compatible. Original source U+00AD soft
hyphens stay available in every language. Automatic hyphenation is a
document/layout setting with a review-dialog toggle and normal controller undo.

A selected discretionary break includes the measured visible hyphen width and
paints it only at that break. No permanent ASCII hyphen is inserted. Explicit
soft hyphens stay in source and are invisible when not selected. Shared layout
and source-presentation mapping preserve logical text, caret and selection
ownership, bidi ranges, copying and PDF export. DOCX model settings and
paragraph/run properties round-trip with the relevant source XML.

U+200B ZERO WIDTH SPACE contributes an invisible soft-break opportunity.
U+2060 WORD JOINER and U+FEFF zero-width no-break space suppress adjoining soft
breaks, including emergency and contextually remeasured wrapping. An explicit
zero-width opportunity takes precedence when both address the same boundary.
The controls remain in source; they do not introduce visible glyphs.

### Spelling

`GermanSpellingProvider` uses the MIT DANTE/Werners Wortliste mirror at
`4330a0b1254e88615cb4c83e4b3dc2f0810c76d9`, a **1 May 2016** snapshot. It is
not presented as a current or exhaustive dictionary. Modern orthography is
selected from the appropriate source columns; the first key column is not
an allowlist. Historical `daß` and `Fluß` are not accepted merely because the
source contains their keys.

The generated standard vocabulary has **444,123 forms**: 443,925 selected
source forms plus 198 additional forms from the independently authored
1,264-form common-word supplement. There are **9,451 Swiss additions**.
`de-DE` and `de-AT` share this vocabulary; it is not an exhaustive Austrian
regional dictionary. `de-CH` also maps accepted sharp-s forms to `ss` and rejects
sharp-s tokens. Exact notices, selection rules, hashes and reproduction commands
are in the [data documentation](../packages/quds_office_engine/third_party/proofing/README.md)
and [manifest](../packages/quds_office_engine/third_party/proofing/manifest.json).

This is a finite word-form checker. Explicit hyphenated compounds can use known
components, but it has no unrestricted closed-compound decomposition or complete
German morphology. Unknown proper names, new terms and unlisted inflections can
produce findings. Messages describe absence from the word list, and the UI
offers personal vocabulary and ignore controls.

Common decomposed accents and soft hyphens are normalized for lookup only;
findings retain original UTF-16 offsets and original text. German noun casing
remains significant. Sentence-initial capitals and all-capitals are accepted
when a corresponding listed form exists. URLs, email addresses and closed code
spans with matching backtick-run delimiters are excluded. Unmatched delimiters
do not hide the remaining prose. Explicit hyphen compounds can repair one
unknown constituent while retaining the other constituents' case and authored
U+2010/U+2011 separator style. This reuses one bounded component search; it does
not infer unrestricted closed compounds or import morphology data.
Suggestions use bounded local edits and German accent/sharp-s variants, with
defaults of at most five suggestions and 6,000 candidate checks. Dictionary
decoding and token batches yield cooperatively, including in compiled JavaScript.
A bounded search of at most 32 orthographic variants combines umlaut and
sharp-s transformations; every suggestion must occur in the shipped dictionary.
Declared personal words may be components of explicit hyphenated compounds,
with exact case and locale. Session-ignored words remain exact-token exemptions.
Vocabulary restoration merges canonical language aliases instead of discarding
an earlier alias's entries.

Hunspell's MPL alternative remains a possible later engine adapter after a
compatible full dictionary is available. It is not required to ship multiple
competing spelling engines in this implementation.

### German writing rules and terminology

`GermanWritingRulesProvider` contains eight independently authored
checks. It is not a general German grammar parser.

| Rule ID | Category | Implemented boundary |
| --- | --- | --- |
| `de.spacing.repeated` | Style | Repeated internal spaces, with a numeric-spacing exception. |
| `de.spacing.before-punctuation` | Style | Spaces before `, ; : ! ?`. |
| `de.spacing.after-punctuation` | Style | A comma or semicolon immediately followed by a letter; offers a zero-length space insertion. |
| `de.repetition.conjunction` | Style | Immediate repeated `und`, `oder` or `aber`; valid repetitions such as “Ist das das Haus?” remain accepted. |
| `de.grammar.pronoun-verb` | Grammar | Immediate `ich`/`du`/`wir` with 25 enumerated present-indicative verb families; narrow `ihr`/`sein` checks, nominal-word and context guards. |
| `de.grammar.seit-seid` | Grammar | `ihr seit` before listed predicates, or `seid` between a listed finite verb and a reviewed temporal expression; never a generic `seid + time` rewrite. |
| `de.delimiter.balance` | Style | Paragraph-local bracket balancing. |
| `de.quote.balance` | Style | Paragraph-local German/English typographic quotes and guillemets, with apostrophe handling. |

The finite families are `sein`, `haben`, `werden`, `können`, `müssen`, `dürfen`,
`sollen`, `wollen`, `mögen`, `gehen`, `kommen`, `machen`, `sagen`, `arbeiten`,
`lernen`, `brauchen`, `finden`, `geben`, `nehmen`, `sehen`, `lesen`, `sprechen`,
`fahren`, `laufen` and `essen`. Agreement accepts horizontal spaces, tabs and
nonbreaking spaces, and preserves uppercase replacement style. Valid constructions such as `Ihr ist kalt`,
`Ihr bin ich dankbar`, `Du und ich sind hier` and coordinated subjects with
relative clauses remain outside this bounded rule. Unlisted verbs,
subjunctives, separated subjects/verbs and broad sentence parsing are not added.

Title-cased noun homographs and nominalized infinitives are conservatively
excluded: `Wenn du Essen brauchst` and `Weil ich Macht habe` must not receive
verb corrections. Inflected/fused determiners also preserve nominal pronouns,
such as `Mit dem Du kommen wir gut zurecht`. Unambiguous uppercase finite
errors remain checkable. The narrow `seit`/`seid` checks preserve valid temporal
past-tense and imperative constructions such as `Ihr seid gestern gekommen`
and `Seid drei Wochen geduldig`.

Discretionary soft hyphens are omitted from German checker text only. Every
finding maps back to whole graphemes in the untouched source, including
internal controls and nonzero segment origins. URLs, email addresses and
closed matching-backtick spans are protected from these rules. Quote/bracket findings are review items: a legitimate quotation spanning
paragraphs can be unbalanced within an individual paragraph. No rule rewrites
text without a user-selected correction.

`OfficeTerminologyProvider` accepts immutable host-authored literal term rules
with language scope, case/whole-word options, stable IDs, explanations and
replacements. No external terminology or grammar-rule corpus is bundled.

### Conservative source-boundary checks

Spelling tokens must begin with a letter; standalone soft hyphens and combining
marks do not become empty lookup candidates. Internal apostrophes in quoted
names or contractions (for example `‘O’Connor’` and `‘geht’s’`) do not close the
surrounding quotation.

The existing pronoun/verb rule also recognizes lowercase `ich ist` and
`du ist`, while preserving capitalized nominal uses such as `das Ich ist`.
Immediate comparison phrases beginning with `wie` or `als` are excluded, and
an all-capital verb receives an all-capital replacement.

Spelling, writing and terminology findings are emitted only at whole source
grapheme boundaries. A pattern match ending inside a combining sequence or
next to a joiner is omitted, rather than failing all findings for the paragraph
or extending a replacement over neighboring marks. Decorated unmatched
punctuation and lexical fragments adjoining joiners can therefore be omitted.
This conservative range policy is not a claim that every such fragment has
been checked.

### German model evaluation

The `proofbird/gector-bert-de` v2.1.0 ONNX model was evaluated separately at
immutable revision `8e3b50beef7d775cedb7b876009e88bcf2e8d6af`. Its original
Apache-2.0 LICENSE, NOTICE and reference runner are preserved, with pinned
digests for model, tokenizer, metadata and rule artifacts. Model weights and
evaluation-only Python dependencies are not shipped by the Office application.

The recorded local CPU probe matched the expected correction in **9 of 18**
error cases and changed **1 of 12** valid controls: Swiss `ich heisse` became
`ich heiße`. This small hand-written probe is not a population accuracy
estimate. The upstream reference runner omits the application's additional
grammar and OS spelling guards, so published guarded-app scores do not
describe this run. Original timings, outputs, versions and hashes remain in
the [evaluation record](validation/proofing-20261116/german-model-evaluation.json);
the recovery did not rerun the expensive evaluation or enable a model provider.
See the [evaluation README](../tools/proofing/german_model/README.md) for a
repeatable local entry point and the requirements for any future provider.

Commercial Duden/LanguageTool services and LGPL policy exceptions remain
outside this implementation. No account, purchase or document upload is
authorized by this roadmap.

## Using Word proofing

`WordEditorController.proofing` owns a lazy `WordProofingSession`. Its built-in
providers are German spelling and the eight German writing rules. Background
checking starts disabled. The exported `showWordProofingDialog` commits pending
edits, opens the review UI and runs an explicit check. The example's F7/Spelling
action uses this dialog; its **Check while typing** switch enables debounced
background checks. A manual check works with that switch off.

The review shows findings, explanations, offered replacements and availability
or coverage messages. It supports ignore-once, language-scoped ignored/personal
words and rule opt-outs. Squiggles use the renderer's source-to-geometry mapping
across wrapped and bidi text, including visible markers for zero-length
findings. A secondary click at a source position exposes the relevant correction
actions. Unavailable, unsupported, failed and incomplete checks remain distinct
from a complete successful check with no findings.

Invisible replacement buttons use labels such as **Insert space**, **Use
space**, **Insert nonbreaking space** or **Insert tab**, while applying the
exact offered characters. The **Ignored checks** section lists ignored words
across languages and restores each in its original language, including a run
language that differs from the document default. It also restores individual
rules and can review ignored occurrences again. These proofing preferences
remain available in read-only review and do not create document undo entries.

### Language and document coverage

Effective language inherits from **run → paragraph → document → `de-DE`**.
The dialog offers `de-DE`, `de-AT`, `de-CH`, `en-US` and `en-GB`, and preserves
other imported language tags. Changing the document default does not overwrite
explicit paragraph/run languages. Interface translation is independent of
proofing language. Imported comment paragraphs now participate in the same
document style cascade, including inherited language/`noProof` and explicit
`noProof` resets.

Logical text is joined across formatting runs. Capture respects full paragraph
grapheme boundaries, including combining marks or surrogate pairs split across
runs. A grapheme takes the language of its first source unit; excluding any
part of it excludes the complete grapheme from checking. This prevents a run
or language boundary from creating a correction inside one visible character.

Traversal covers ordinary body paragraphs, nested tables and text frames, all
six header/footer collections, footnotes, endnotes and comments exposed by the
model. Generated fields and field results, generated page-number paragraphs,
TOCs, atomic references, `noProof` spans and deleted revision text are excluded.
Complex-field state is tracked across paragraph boundaries, including empty
paragraphs within a field. Page-number and field metadata participate in the
source snapshot, so changing those flags invalidates findings and pending
results even when the text is unchanged. Excluded or opaque/preserved content
contributes an explicit coverage limitation; it cannot silently become a claim
that the entire document is clean.

**Show in document** selects a finding only when the current document view can
represent its source. Other modeled stories remain reviewable through their
source paragraphs; whole-story checking does not promise canvas navigation to
every note or header/footer variant.

### Lifecycle and corrections

Session generations, document/block identities, revisions, provider
configuration, vocabulary revisions and complete source snapshots reject stale
results. Replacing the service invalidates pending work and disposes the
previous service. Controller disposal ends the owned session and backend
resources. Normal controller commands notify the session; hosts that mutate
the model or vocabulary directly call `controller.proofing.refresh()`. Reusing
a mounted review dialog with another controller clears old notices and checks
the new document; deferred checks and failures from the old controller cannot
be presented as results for the replacement controller.

A correction must still match a current finding and one of its offered literal
replacements. The controller checks full paragraph grapheme boundaries, story
membership and source text again at application time. It refuses writes to a
read-only/protected document, generated fields, locked or data-bound controls,
and conflicting pending revisions, and refuses correction while IME composition
is active.
It also guards zero-width field/control boundaries and the actual insertion
point of a tracked replacement. Replacements cannot insert paragraph or line
separators. A permitted correction uses normal editing commands and one undo
unit; when change tracking is enabled, the original text is retained as a
deletion and the replacement is tracked as an insertion. Corrections update
the active caret, undo restores its original selection and redo restores the
corrected caret, including tracked replacements. Nonempty finding hits use
half-open ranges; zero-length findings match their exact insertion position.

### Host vocabulary and session API

Vocabulary belongs to an explicit host-selected owner. The engine changes its
in-memory vocabulary only; the host chooses storage and account boundaries.
For example:

```dart
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

WordEditorController createController({
  required WmlDocument document,
  required String ownerId,
  required void Function(Map<String, Object?>) persistVocabulary,
  Map<String, Object?>? savedVocabulary,
}) {
  final controller = WordEditorController(
    document: document,
    proofingVocabulary: OfficeProofingVocabulary(ownerId: ownerId),
  );
  controller.proofing.onVocabularyChanged = persistVocabulary;
  if (savedVocabulary != null) {
    controller.proofing.restoreVocabulary(savedVocabulary);
  }
  return controller;
}
```

`restoreVocabulary` rejects another owner's snapshot and preserves the
vocabulary instance referenced by configured providers. Snapshots use
`OfficeProofingVocabulary.toJson()`/`fromJson()` and retain language-scoped
personal and ignored words; membership is case-sensitive after canonical
accent normalization. Ignore-once is tied to the captured issue/source
snapshot. Rule ignores are session settings exposed through `ignoreRule` and
`restoreRule`. Neither the shipped lexicon nor the document is changed when a
word is added, and no shared account storage is selected automatically.

Hosts can use `checkNow()`, `enabled`, `summary`, `findingsByParagraph`,
`issuesAt(...)` and `refresh()` on the session, or replace the owned provider
service with `configure(...)`. Supply the same vocabulary instance to a custom
`GermanSpellingProvider` so personal words remain effective after configuration.
`unignoreWord(word, language: ...)` restores one language-scoped ignored word
and publishes the updated host vocabulary snapshot. `clearIgnoredOnce()`
restores ignored occurrences without changing word or rule preferences;
`restoreRule(...)` restores an ignored rule.

## Optional local backends

### English Harper installation and configuration

`quds_proofing_harper` wraps Harper 3.2.0 at source commit
`ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3`, with Cargo.lock pinning the graph.
Native requests run through a persistent Dart isolate and a Rust FFI library;
web requests use a module Web Worker and the same wrapper compiled to Wasm.
Document text stays local. Web asset fetching does not use a hosted grammar
service or a CDN fallback.

Build/package the optional assets from the matching checkout. Rust 1.100.0,
the `wasm32-unknown-unknown` target and `wasm-bindgen-cli` 0.2.130 are the
validated toolchain; setup commands are in the
[package README](../packages/quds_proofing_harper/README.md).

```sh
# Before the example host's Flutter web build:
python3 packages/quds_proofing_harper/tool/build.py --web \
  --install-web packages/quds_office_editor/example/web/proofing

# After a Linux Flutter release build has created its application bundle:
python3 packages/quds_proofing_harper/tool/build.py --native \
  --install-native /path/to/flutter/release/bundle/lib
```

The helper copies only receipt-listed runtime assets, plus the license manifest,
original notices/MPL sources and build receipt. All three web runtime files
must be served together: `harper_worker.mjs`, `quds_proofing_harper.js` and
`quds_proofing_harper_bg.wasm`. The host must allow same-origin module workers
and Wasm in its CSP. Generated binaries/assets are build outputs, not checked-in
source files. A custom `workerUrl` supports a host mounted under a path prefix.
For native hosts, use `nativeLibraryPath` or the `QUDS_HARPER_LIBRARY` Dart define
if the platform loader does not search the packaged library directory.

The base editor's default checking providers are German spelling and writing
rules. English checking remains an optional provider; automatic English
hyphenation is part of the engine. A host can opt into English checking after
adding the package dependency:

```dart
import 'package:quds_proofing_harper/quds_proofing_harper.dart';

controller.proofing.configure(
  OfficeProofingService(providers: [
    GermanSpellingProvider(vocabulary: controller.proofing.vocabulary),
    GermanWritingRulesProvider(),
    HarperProofingProvider(
      vocabulary: controller.proofing.vocabulary,
      workerUrl: Uri.base.resolve('proofing/harper_worker.mjs'),
      // For a native host, set nativeLibraryPath when required by packaging.
    ),
  ]),
);
```

The example host already registers this optional provider lazily; selecting
English requests it. Registration alone does not install the backend. Missing
or incompatible libraries and missing worker assets report **unavailable**.
Harper supports `en`, `en-US`, `en-GB`, `en-CA`, `en-AU` and `en-IN`; other tags
are **unsupported**, never silently sent to an English checker.

Discretionary U+00AD is omitted only from English checker input so it cannot
split words. Indexed scalar ranges map back to the unchanged original UTF-16
source, including controls within a finding and supplementary characters.
Both source and projected grapheme boundaries are enforced. A shared
`OfficeProofingVocabulary` suppresses only matching-dialect spelling findings;
grammar continues and vocabulary changes invalidate pending results.
Each request is limited to 32,768 original Unicode scalars and 2,000 findings; exceeding
either bound is an explicit failure, without a truncated clean result. Startup,
worker/message and timeout failures settle pending requests and retire the
failed worker. Native concurrent-request and disposal cases and the actual
Dart web transport/worker/Wasm path have local integration coverage. Runtime
acceptance on platforms other than the tested Linux native host is still
required, as is real-browser hosting/CSP acceptance.

### Mobile platform spelling

`OfficePlatformSpellingProvider` is exported by `quds_office_editor`, keeping
Flutter and `dart:ui` out of the pure-Dart engine. It wraps Flutter's
`DefaultSpellCheckService` for Android/iOS. The host declares the installed
`supportedLanguages`; Flutter does not provide reliable dictionary enumeration.
Requests are serialized, the framework's text-only cache is cleared between
languages, UTF-16 ranges are validated and suggestions are bounded. A null
platform response is a failure; an empty successful response is distinct.

The local tests exercise the provider protocol, including two uses of the real
Flutter service against a mocked platform channel. They do not demonstrate
installed dictionaries or spelling behavior on an Android/iOS device. Hosts
must perform that device acceptance before advertising mobile availability.

## Integration contracts

- Use a proofing language on each applicable text span, with document defaults
  and explicit `de-DE`, `de-AT`, `de-CH` and English choices. Interface translation
  is independent of document proofing language.
- Proofing operates on logical source text across formatting runs. Include
  ordinary body paragraphs and supported contained paragraphs; clearly expose
  any unmodeled content that cannot be checked.
- Track document/block identities and revisions. Discard completed results
  when their text, language, provider configuration or revision has changed.
- Run expensive work off the typing path. Native isolates and browser workers
  are implementation options; do not assume isolates execute on Flutter web.
- Keep findings ephemeral. Corrections use normal document editing commands
  and undo; honor protected/read-only regions and IME composition.
- Personal and ignored words have explicit ownership and a host persistence
  contract. Do not mutate the shipped dictionary or silently share vocabulary.
- Reuse range-to-geometry mapping for squiggles across line wraps and bidi text.
- Hyphenation changes layout, not proofreading text or serialized spelling.

## Acceptance cases

Check real behavior rather than mirroring implementation:

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

The latest continuation results are in the
[current verification report](validation/proofing-20261116/continuation-hardening/README.md)
and the current section above. The following tables preserve the earlier
component runs against the exact sources identified in their receipts.

### Earlier component results

Validation was run locally on Linux using Flutter 3.47.8 and Dart 3.13.7,
with Rust 1.100.0 for Harper. GitHub Actions were neither used nor waited for.
Receipts record exact commands, exit codes, source/artifact hashes and log
hashes. Component suites intentionally overlap; the counts below must not be
added together as a unique repository-wide test total.

| Area | Observed local validation | Evidence |
| --- | --- | --- |
| Shared proofing, German spelling, writing rules and terminology | 38 Dart tests; focused analysis with no issues; 10 compiled-JavaScript checks in Node; all 18 generated dictionary files reproduced byte for byte from a fresh pinned download. | [German core receipt and scope](validation/proofing-20261116/german-resume/README.md) |
| Hyphenation, bidi, Word layout, notes/tables, DOCX and PDF | 231 engine tests; focused analysis and exact pattern regeneration passed. | [Hyphenation validation](validation/proofing-20261116/continued-hyphenation/README.md) |
| Editor hyphenation, caret/source presentation, small caps, note labels and existing editor regressions | 85 tests and focused analysis passed. | [Editor validation](validation/proofing-20261116/continued-hyphenation/editor-validation.json) |
| Proofing session and review dialog | 30 session tests and 13 dialog tests passed in the final combined run, covering stale/cancelled work, whole-story coverage, vocabulary/controls, graphemes split across language runs, page-number metadata and controller swaps. | [Final integration evidence](validation/proofing-20261116/integration-resume/README.md) |
| Correction guards and undo/tracking | 33 tests passed in the final combined run, covering source/revision guards, protected/control/field boundaries, pending revisions, caret/selection restoration, undo and tracking. | [Final integration evidence](validation/proofing-20261116/integration-resume/README.md) |
| Proofing geometry and mobile adapter | 19 tests passed: 10 geometry/rendering and 9 platform-protocol tests; focused analysis had no issues. Mobile results use mock services/channels. | [Renderer/platform receipt and scope](validation/proofing-20261116/continued-renderer/README.md) |
| Incoming engine reconciliation and comment proofing styles | 212 selected engine tests passed, full-engine fatal-info analysis had no issues, and current hyphenation output regenerated exactly. Includes comment style/`noProof` inheritance, repeated DOCX saves, ODS and Zotero regressions. | [Engine reconciliation evidence](validation/proofing-20261116/continued-comments-and-merges/README.md) |
| Incoming Zotero editor integration | 9 tests passed: 5 session-backoff, 2 dialog-scaling and 2 source-identity checks. Focused fatal-info analysis had no issues; the same nine tests also passed in the final combined editor run. | [Zotero editor evidence](validation/proofing-20261116/incoming-zotero-editor/README.md) |
| Optional Harper native/web | 5 Rust tests, 10 Dart VM tests with the real Linux library and no native skips, 7 compiled-JavaScript adapter tests, 5 real shipped worker/Wasm checks, 8 compiled-Dart web-transport checks, 3 license regression tests; analysis and notice/MPL source checks passed. | [Harper receipt and scope](validation/proofing-20261116/harper-resume/README.md) |
| German model | Preserved evaluation: 9/18 expected error corrections, 1/12 valid controls changed. No recovery rerun or application activation. | [Model evaluation record](validation/proofing-20261116/german-model-evaluation.json) |

At integrated source **`ca294cf8668706b45f40031ed9a2db52e5737cd2`**, all six
local command groups passed: toolchain identification, full-engine fatal-info
analysis, editor-library and 13 selected test-file fatal-info analysis,
host-library fatal-info analysis, **189 selected editor tests**, and the host
web build. All **684 recorded source inputs** were unchanged during validation.
The [integration README](validation/proofing-20261116/integration-resume/README.md)
and [receipt](validation/proofing-20261116/integration-resume/receipt.json)
bind the engine, editor, host, Harper and related inputs plus the resolved
workspace lockfile and generated web artifact hashes.

The editor total comprises 30 session, 33 correction, 13 dialog, 10 geometry,
9 platform-protocol, 85 existing editor/rendering and 9 incoming Zotero tests.
It is the selected integrated suite, not every test in the repository. The
separate 212-test engine reconciliation suite overlaps other component checks
and is not added to them as a unique total. The successful final results
supersede earlier failed attempts only for the exact recorded source inputs;
a later checkout needs its own source comparison or validation.

The [component source comparison](validation/proofing-20261116/integration-resume/component-source-comparison.json)
found all 31 recorded Harper inputs unchanged. Of the German receipt's 36
inputs, only the auxiliary hyphenation generator's notice whitespace changed;
the German providers, dictionary, original word-list inputs, lexicon generation
code and tests are unchanged. The current hyphenation generator was separately
[verified against its exact output](validation/proofing-20261116/continued-comments-and-merges/generator-receipt.json).

The component verifiers can be repeated independently from the repository root:

```sh
python3 packages/quds_office_engine/tool/proofing/verify_german.py \
  --download-wordlist --output /path/to/german-validation

python3 packages/quds_proofing_harper/tool/build.py --native --web
python3 packages/quds_proofing_harper/tool/verify.py \
  --output /path/to/harper-validation
```

The German verifier re-fetches the immutable wordlist, checks its digest and
compares generated files. The successful recovery run verified SHA-256
`55b457fac8e322146853f45bbda59046a55496a3e3deb32d3a88feb908eca243` and
unchanged hashes for all 36 recorded inputs. The Harper verifier rejects source
or generated-artifact drift before and after testing; its separate installation
probe confirmed copied runtime bytes and exclusion of unrelated stale output.

### Remaining runtime boundaries

The browser attempt was blocked **before any page or backend loaded**:
Chromium exited with code 134 after its process-singleton socket creation failed
with `Operation not permitted`. The
[probe record](validation/proofing-20261116/harper-resume/chromium-probe.json)
and accompanying log retain that evidence. Node executed the actual compiled
Dart transport, shipped module worker and real Wasm with a substituted local
Worker/fetch bridge. Those passes do not demonstrate browser HTTP delivery,
CSP, visual interaction or end-user browser behavior. Compiling a Flutter web
host is also separate from running it in a browser.

Native Harper was built and tested on Linux. Windows/macOS loading and
packaging, real Android/iOS system dictionaries and device behavior have not
been exercised in this recovery. They require their own target-specific build,
license audit and runtime acceptance. The German model remains unsuitable for
an unqualified grammar-coverage claim on the evidence recorded here.

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
