# Word-native layout fidelity — 20 November 2026

The goal is **every qualified page strictly above 95% against Microsoft Word**.
It is **not yet achieved**. This first reproducible corpus passes **20 of 24
pages**, up from **0 of 24** on the prior renderer. Every reference page improves;
all 24 now have the correct page dimensions, page count and per-page line text.
These are 16 synthetic documents, not a claim about arbitrary Word files.

## What changed

- Use real font typographic line metrics instead of glyph-clipping extents,
  a 1.2-em minimum and an additional blanket 10% multiplier.
- Feed the actual registered font/style metrics to interactive pagination as
  well as shaping widths. Forward them into nested table and note layout.
- Align Flutter text painting to the layout baseline. Font-specific leading,
  mixed sizes and inline pictures must not be positioned from a guessed top.
- Place surplus exact/minimum line spacing above the baseline. The bounded
  references improve substantially, but exact spacing remains unqualified for
  the two font families below.
- Preserve imported paragraph-mark font/size through the style cascade and
  independent clones. Truly empty paragraphs without inline runs use that font
  for their blank-line advance. Three isolate save/reopen cycles protect this.

The old calculation adds about 63 pt of cumulative Calibri line-position drift
over 40 lines and about 98 pt for Aptos. Typographic spacing removes that extra
multiplier without fitting a replacement constant to one document.

## Measurement and results

Microsoft Word **16.111.1 for macOS** exported the references. Production
`WordEditorController`, `WordCanvas`, `PaintRunText` and Flutter's real test
renderer produced the candidate page images, with rulers/selection/caret hidden.
This measures the interactive canvas, not just a Quds PDF or an app screenshot.

Poppler rasterizes Word's PDFs at **144 DPI**. The score is foreground ink F1:
precision penalizes added ink, recall penalizes missing ink, with a fixed **one
pixel (0.5 pt)** positional tolerance and grayscale ink threshold below 200.
White page area contributes nothing. The 1.5-pt outer page outline is excluded
as UI chrome; document content is not shifted, scaled or cropped to match.
This is a tolerant content metric, **not pixel identity or a universal
perceptual-quality percentage**. Text, page counts and dimensions must also match.

| Corpus group | Pages above 95% | Minimum page ink F1 |
| --- | ---: | ---: |
| Calibri, four spacing modes | 6 / 6 | 99.97% |
| Aptos, four spacing modes | 6 / 6 | 99.99% |
| Arial, automatic/minimum modes | 4 / 4 | 99.25% |
| Times New Roman, automatic/minimum modes | 4 / 4 | 98.98% |
| Arial, exact 18-pt spacing | 0 / 2 | 88.09% |
| Times New Roman, exact 18-pt spacing | 0 / 2 | 84.51% |

See [before](qualification-before.json), [after](qualification-after.json) and
[acceptance](acceptance.json). The strict target gate returns **exit status 1**;
we retain that failure rather than hiding the four pages in an average.
Eight comparator controls protect missing/extra ink, displaced content, blank
pages, dimension mismatch, absent/empty corpora and unsafe/duplicate inventories.

Calibri and Aptos are read from the locally licensed Word installation for this
diagnostic. Arial and Times requests use the editor's bundled Liberation aliases;
the reports name those substitutions. **No proprietary font files or Word PDF
font subsets are committed or shipped.** The committed references contain only
our synthetic DOCX source and Word's page PNGs, with PDF/font SHA-256 receipts.
Matching font availability is part of qualification, not assumed on every device.

182 engine regressions, 32 editor tests and 8 comparator controls pass; changed
Dart code analyzes cleanly. No GitHub Actions jobs/status endpoints were queried.

## Reproduce

Copy `reference/` to a scratch directory, for example `/tmp/word-layout-check`.
Its manifest uses the standard local macOS/Word font locations. Missing required
fonts fail explicitly. Run from `packages/quds_office_editor`:

```sh
flutter test --no-pub tool/render_word_native_corpus.dart \
  --dart-define=QUDS_WORD_LAYOUT_CORPUS=/tmp/word-layout-check
```

Then, from the repository root with Pillow installed:

```sh
python3 packages/quds_office_engine/tool/fidelity/word_native_layout.py \
  compare /tmp/word-layout-check --report /tmp/word-layout-check/report.json
```

The current source deliberately fails the full >95% target on four pages.
Missing pages, mismatched inventories or changed reference/source hashes raise
errors. An empty or skipped run cannot qualify inference or rendering.

The Python tool also has explicit `generate`, `word` and `reference` commands
for new, separate corpora. `word` automates the locally installed Microsoft Word
and exports only the named synthetic documents; ordinary tests never invoke it.
Generating new fixtures or references is separate from comparing existing ones.
The Dart engine producer is diagnostic for the separate PDF-export path; this
record does not qualify all engine PDF output at >95%.

## Remaining work, in order

1. **Exact-spacing baselines:** fix the four failing pages using declared
   document defaults, compatibility settings and independently measured Word
   baselines. A follow-up with explicit paragraph-mark font values kept Word's
   fixed baseline unchanged, so a mark-descender-only adjustment was rejected.
   Blank-paragraph mark metrics are a separate verified improvement.
2. **Broaden the corpus:** real wrapped paragraphs, mixed fonts/sizes, German
   hyphenation, Arabic/Hebrew, justification, tabs and list indents. The initial
   hard-break corpus does not prove Word-compatible wrapping.
3. **Pagination rules:** paragraph spacing interaction, widow/orphan control,
   keep-with-next, section starts and column balancing, with exact page/text
   inventory checks alongside the ink score.
4. **Stories and complex pages:** replace header/footer character-width
   approximations and font-size clamps with rich story layout; qualify tables,
   footnote continuations, floating pictures/textboxes, fields and equations.
5. **Host/device qualification:** run the same source-bound page tests through
   CrispCloud and on the shipping macOS/iPad renderers, with actual fonts and
   explicit substitutions. Editor test rendering alone cannot certify those.

Every added corpus page must meet the same threshold individually. New
references require actual Word output and retained source/font/version evidence;
rebaselining Quds output against itself cannot close these gaps.
