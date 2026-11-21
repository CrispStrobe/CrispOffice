# Spelling, hyphenation and grammar

Quds Office proofing runs locally in the Word editor. It combines a built-in
German checker, configurable writing and terminology rules, Arabic rule
providers, optional native models and a document-wide review workspace.

The detailed provider, licensing and acceptance record is preserved in
[Proofing details](proofing-details.md).

## What is available

| Language | Default offline support | Optional |
| --- | --- | --- |
| German | Spelling, hyphenation, writing rules, terminology, thesaurus | GECToR grammar model (manual, separately installed) |
| English (US/UK) | Hyphenation; thesaurus | Harper spelling/grammar with packaged assets |
| Arabic | Writing rules and clean-room grammar checks | AyaSpell Hunspell dictionary, Camel Morph, spaCy model |

No model or dictionary is downloaded automatically. Missing providers are
reported as incomplete coverage, never as a clean check.

## Use proofing

Open **Review → Spelling** or press **F7** to show the Writing pane. The document
stays editable beside the pane.

- Red underline: spelling.
- Blue underline: grammar.
- Amber underline: writing style.
- Right-click a marked passage for suggestions and the normal edit menu.
- Use the pane to filter findings, navigate, replace, ignore an occurrence,
  word or rule, or add a personal spelling.
- Corrections are undoable. Stale results cannot modify a newer document.

The status bar reports checking progress and pending tracked changes. Open
**Review → Review changes** for the Changes pane.

## Languages and exclusions

The globe button in the editor status bar opens **Language and checking**:

- With a selection, changes apply to **Selected text**.
- With a collapsed caret, changes apply to the **Current paragraph**.
- **Use inherited language** removes a local override and falls back to the
  paragraph/style/document language.
- **Check this text** can exclude quotations, identifiers or code samples.
- The separate **Document language** control changes the default for the whole
  document.

Each actual language or checking change is one undo step. Settings survive DOCX
save and reload. Excluded text remains visible as excluded coverage.

## Supported proofing scopes

Proofing covers body text, editable table and frame text, rendered
headers/footers, active comments and authored Notes text. Protected, generated
or hidden text is not treated as ordinary prose. Comments, headers and notes do
not accidentally inherit a body selection.

Check-as-you-type runs after a typing pause. It uses an adaptive scheduler so
active typing is not blocked by provider work. The active paragraph is checked
first; later paragraphs appear progressively. Opening a document, changing
language or editing a paragraph invalidates only the affected results.

## Thesaurus

Open the thesaurus from **Review**, Shift+F7 or the word context menu. English
uses the OEWN 2025 pack; German uses OpenThesaurus. Lookup is offline and does
not mutate the document. Choosing a replacement is an explicit, undoable edit.

## Optional native providers

Native providers keep large models outside the UI isolate:

- **Harper** for English spelling and grammar;
- **Hunspell** for Arabic, using AyaSpell data;
- **spaCy** for evaluated Arabic syntax;
- **GECToR** for a manual-only German de-DE model.

Hosts install or package these explicitly. Provider registration includes
licence and availability information. The default engine does not ship a full
language corpus.

## Host API

Use an `OfficeProofingService` with one or more providers:

```dart
final service = OfficeProofingService(
  providers: [
    GermanWritingRulesProvider(),
    GermanSpellingProvider(),
    ArabicWritingRulesProvider(morphology: morphology),
  ],
);
```

The service is wrapped by `WordProofingSession`, which schedules checks, tracks
revisions and owns the review state. Hosts own provider installation,
lifecycle and error display. See the
[details](proofing-details.md) for the exact contracts, provider
options and platform packaging.

## Licensing and data

- Built-in Quds rules are MIT.
- Harper and spaCy integration code is permissively licensed; their models and
  data keep their own terms.
- AyaSpell/Hunspell data is downloaded separately and pinned by hash.
- Thesaurus data is attributed separately: OEWN/WordNet English and
  OpenThesaurus German.
- No proofing request sends document text to a new cloud service.

## Limits

- Unsupported languages and unavailable providers produce no findings, with an
  incomplete-coverage state.
- Optional grammar models are not started by ordinary typing; use **Check
  document** or F7.
- Mobile system spelling uses the platform adapter and differs by OS.
- The engine does not include a complete dictionary, morphology or universal
  grammar checker.
- Installed-desktop and browser acceptance remain separate from unit tests.
