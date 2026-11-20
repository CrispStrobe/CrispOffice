# Word line boxes and wrapping — 2026-11-20

The source-bound Mac capture now passes **52/52 pages** in **44 synthetic DOCX documents** against Microsoft Word 16.111.1. The same corpus at `43db439e` passed **27/52**. Every page must exceed 95% foreground-ink F1 at 144 DPI with a fixed 1-pixel (0.5-point) tolerance, preserve page dimensions/counts, and preserve visible words on each row. The lowest current page score is 97.956%. This is bounded evidence, not a claim about arbitrary Word documents.

The original 24-page corpus now passes 24/24, including its four remaining exact-spacing failures. Six added paragraph cases cover wrapping, justification, a large first line followed by smaller text, adjacent paragraph spacing and left/center/right tab fields. Twenty controls probe exact spacing across fonts, run sizes, defaults and independent line heights, plus minimum spacing. Two identical Calibri paragraphs with `w:kern=1` versus `w:kern=28` isolate the native kerning threshold. All 52 pass the unchanged raster threshold.

Changes:

- Exact line boxes use the fixed baseline observed in native exports (80% of line height, within the PDF's quarter-point rounding). Font/size/default controls and independent heights 10–120 points validate this separately from the original 18-point cases.
- Line height and shared baseline derive from the fonts actually present on each line; the paragraph mark participates on the final line. A large opening run no longer expands every following line.
- Adjacent body paragraph gaps take the greater before/after spacing and retain the original source properties. Explicit breaks and non-paragraph blocks interrupt adjacency.
- Word paragraphs choose the longest fitting legal line, with host shaping remeasured at candidate boundaries. Balanced breaking remains the default for other LineBreaker consumers. Unicode/source ownership and discretionary hyphen tests remain enabled.
- Left-to-right tabs use explicit left/center/right/decimal stops and the default half-inch grid. Clear stops cancel inherited positions; bar tabs do not move text. Leaders, right-to-left tab layout and locale-specific decimal separators are not qualified by this work.
- Effective native kerning thresholds survive style resolution, copying and sparse export, and affect measurement, painting and paint-run boundaries. New documents explicitly serialize their enabled threshold; styleless imports retain Word-compatible built-in fallback behavior. With declared styles but no inherited `w:kern`, kerning is off.

Calibri font versions differ between this installation's native PDF output (6.24) and its local Word DFonts (6.20). Independent horizontal-advance checks found identical widths for the problem line. The controlled native kerning exports, rather than a font-version assumption, demonstrate the cause of its differing word wrap. No font download or font substitution hack was added.

The comparator canonicalizes whitespace and groups Poppler's separate tab fields on the same visual row (within 0.25pt), using source x positions. It still rejects changed row breaks and missing words, and does not relax the ink metric. Ten comparator controls pass.

Validation artifacts include before/after reports, 299 engine tests, 56 Mac editor tests, static analysis, native export logs and renderer logs. `source-sha256.json` identifies changed production source. Ordinary tests neither invoke Word nor regenerate native references. The invalid first mixed-size producer was discarded; the retained `wl2-mixed-size-valid` input places every line break inside a run, and both baseline/candidate use that identical valid source.

The 44 DOCX inputs and 52 Word page PNGs are synthetic. No proprietary font bytes, font-bearing PDFs or extracted subsets are committed. The local font paths and hashes in the manifest describe diagnostic prerequisites; product font licensing/distribution has not changed. Arial and Times New Roman use bundled Liberation aliases in Flutter; local Calibri/Aptos are registered only for this test capture. Mac Flutter tests run the x64 tester under Rosetta; the release app uses ARM64.

Reproduce the canvas capture with Flutter 3.47.8:

```sh
cd packages/quds_office_editor
flutter test --no-pub tool/render_word_native_corpus.dart \
  --dart-define=QUDS_WORD_LAYOUT_CORPUS=/absolute/copy/of/reference
```

Then run `word_native_layout.py compare` on that directory. Missing inputs, missing pages, changed source hashes or empty output fail qualification. Re-exporting native references is a separate explicit operation requiring installed Word and local reference fonts.

Remaining work toward broad >95% Word fidelity includes representative tables, lists, floating objects, headers/footers, pagination controls, complex scripts, compatibility settings, and physical-device/font qualification. These passing Latin-text controls do not qualify those features. Incoming main through `88905c56` and the host’s Office pin `9c544ecc` were reconciled, retaining mobile native proofing and slide gradients/picture shadows/transparency. The Linux selection refresh passed all 56 editor tests and ran natively in the SMS-created `quds-word-layout-20261120` screen on the Ubuntu VPS with a separate Flutter 3.47.8 SDK. No Docker work is used for validation. No GitHub Actions jobs or CI status endpoints were queried or awaited.

A save guard also preserves the styleless kerning fallback when adding a language creates a styles part. Only the kerning default is materialized, without adding font or size defaults. The regression first failed before the serializer fix.
