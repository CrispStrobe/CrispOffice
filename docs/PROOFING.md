# Spelling, hyphenation and grammar

Roadmap accepted: 16 November 2026. Baseline: `bad2d9d30fd94db8de92a4f4bf83a55b0692b884`.

This is the implementation and acceptance plan for Rechtschreibprüfung,
Silbentrennung and Grammatikprüfung in the CrispStrobe fork. The initial
roadmap commit precedes implementation. Status below describes work actually
validated, not the capabilities of a dependency in isolation.

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

## Baseline findings

`OfficeSpell` is a host callback or supplied-word-set lookup. With neither it
returns an empty list. The example's F7/Spelling action passes no checker and
reports "No issues (host dictionary)". The controller checks only the active
paragraph. There is no diagnostic decoration or correction menu.

`LineBreaker` recognizes explicit hyphens and U+00AD break positions but has
no linguistic break generator and no complete discretionary-hyphen handling.
Word source XML can preserve proofing/hyphenation properties without exposing
them as live model settings. No grammar provider is implemented.

## Delivery sequence

| ID | Work | Initial status | Acceptance |
| --- | --- | --- | --- |
| P1 | Shared asynchronous proofing contract, language selection and availability | Planned | Unavailable/unsupported/error and successful empty results remain distinct; findings carry stable block identity, revision, UTF-16 ranges, category, rule ID, explanation and replacements. |
| P2 | Automatic German and explicit discretionary hyphenation | Planned | Licensed patterns produce measured break candidates in shared editor/PDF layout; unchanged source text, correct soft-hyphen behavior, grapheme and bidi integrity, Word setting round-trips. |
| P3 | Offline German spelling and user vocabulary | Planned | Approved MIT word data with pinned provenance; case/locale-aware membership; bounded useful suggestions; personal words/ignore controls; meaningful positive and negative tests. |
| P4 | German style and limited grammar rules | Planned | Independently authored rules with documented coverage/exclusions; valid repeated German words and regional spelling remain accepted; no silent rewrites. |
| P5 | Word proofing UI and lifecycle | Planned | Real configured provider, full document traversal, background/stale-result handling, squiggles, F7 results and undoable suggestions; disabled or unsupported providers never imply a clean check. |
| P6 | Optional English Harper and mobile spelling adapters | Planned | Working provider protocol and supported-platform wiring; backend-specific offsets mapped to UTF-16; adapter and integration tests; licenses and operational setup documented. |
| P7 | German model evaluation | Planned | Inspect exact artifacts and notices; reproducible evaluation entry point, representative correctness checks and measured runtime where executable; record unavailable gates honestly; no default model activation. |
| P8 | Integration and documentation | Planned | Analyze/test affected packages, editor/layout/export and serialization regressions, dependency/data license manifest, complete release notes and source-bound verification record. |

## Chosen components and data

### Hyphenation

Evaluate and pin the pure Dart MIT `hyphenation` engine (reviewed version
1.0.2) with the original MIT `hyph-de-1996.tex` patterns (reviewed header
2024-02-28). Use break offsets, not its Flutter Text widget. Pattern conversion
or embedding must preserve the source license and record its digest.

Automatic hyphenation belongs in layout. It must not insert permanent ASCII
hyphens into document text. A selected discretionary break includes the visible
hyphen's width and paints it only at that break. Explicit soft hyphens remain
in source text and are invisible unless selected. Preserve source ownership for
caret, selection, search, copy and export.

### Spelling

Use MIT DANTE/Werners Wortliste as curated source data, selecting the intended
orthography and regional variants. The word list does not supply complete
German morphology/compound rules; document the actual checker boundary.
Implement efficient, bounded suggestions and user vocabulary. An approved
Apache/MIT implementation may be used if its Unicode/case behavior fits; its
example dictionaries are not approved automatically.

Hunspell's MPL alternative remains a possible later engine adapter after a
compatible full dictionary is available. It is not required to ship multiple
competing spelling engines in this implementation.

### Grammar

Author German spacing, punctuation, quote/delimiter, terminology and selected
grammar checks independently. Avoid simplistic false positives such as treating
"Ist das das Haus?" as an erroneous repeated word. Return reviewable suggestions
through the same issue model. Distinguish style suggestions from grammar errors.

Harper is an optional Apache-2.0 English backend. Keep native/web adapters out of
the pure Dart document model; normalize Unicode scalar offsets to Quds UTF-16
offsets and record backend availability. Audit the minimal pinned distribution.

The experimental `proofbird/gector-bert-de` ONNX model declares Apache-2.0 in its
model card. Its linked exact LICENSE/NOTICE and full artifact/dependency
provenance still need inspection. Evaluate independently and retain results and
limitations. Commercial Duden/LanguageTool services and LGPL policy exceptions
are outside this implementation; no account, purchase or document upload is
authorized by this roadmap.

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

Implementation has not started in this initial roadmap commit. Later commits
must update this section with exact commands/results and remaining limits.

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
