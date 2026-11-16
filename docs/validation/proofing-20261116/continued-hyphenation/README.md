# Continued hyphenation and rendering validation

Local checks used Flutter 3.47.8 and Dart 3.13.7. GitHub Actions were not used
or waited for. Receipts include the checked source hashes and log hashes;
`base_commit` identifies the checkout before the recorded refinements.

| Check | Result | Record |
| --- | --- | --- |
| Editor rendering, caret, small caps, note labels and existing editor regressions | 85 passed | `editor-tests.log`, `editor-validation.json` |
| Focused editor static analysis | No issues | `editor-analysis.log` |
| Engine hyphenation, bidi, Word layout, notes, tables, DOCX and PDF regressions | 231 passed | `engine/hyphenation-tests.log`, `engine/hyphenation-validation.json` |
| Engine static analysis and exact pattern regeneration | Passed | `engine/hyphenation-analysis.log`, `engine/hyphenation-generator.log` |

The original proofing branch's rendering regressions were retained in
`word_hyphenation_source_presentation_test.dart`. The continuation's tests add
RTL source ownership, mixed manual/automatic breaks, surrogate pairs, combining
marks and selection at a generated break. Header/footer tests check exact
offsets for repeated tab-separated text and exclude generated page labels.

The existing column-break test identified body lines through a null
`sourceText`. Layout now captures source text for all paragraphs, so that test
was updated to use the actual `sourceParagraph` identity. Its column position
and height assertions remain unchanged.
