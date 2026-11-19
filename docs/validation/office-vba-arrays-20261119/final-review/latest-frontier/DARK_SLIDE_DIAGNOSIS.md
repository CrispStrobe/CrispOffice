# Dark slide raster diagnosis and test correction

## Observed failure

The first expanded GUI run at `596430dcb816dd418204d62e78f4dc518afdc0e1`
failed the new `office_dark_slide_test.dart` assertion for black text in the
white table cell. The sampled rectangle is `(384, 33, 290, 25)`, exactly matching
the renderer's cell origin plus its text inset. The 13 px table text is visible
and correctly colored. The original helper counted only pixels whose channels
were within 3 of the exact requested RGB value; it found 3 such black pixels,
against an expectation greater than 15.

An exact-source diagnostic copy retained every original assertion and reproduced
that failure. It added PNG captures, histograms, and an adaptation-disabled
control. These are recorded in `dark-slide-diagnostic-source.json`,
`dark-slide-diagnostic-command.json`, `dark-slide-diagnostic.stdout`, and
`dark-slide-diagnostic.stderr`. The diagnostic adds zero qualification cases.

## Raster evidence

The sampled white cell contains 255 nonwhite pixels. Antialiased glyph edges
account for most of them: only 3 are within 3 of black, 10 are within 32, and 31
are within 64. The complete white-cell region is byte-identical with adaptation
enabled and disabled. The dark-cell region changes in 258 pixels; its adapted
ink contains 16 pixels within 3 of `F2F2F2`, while the disabled control contains
none. These observations distinguish the thin-font raster threshold from a
production color adaptation error.

`capture-0.png` is the full adapted slide. `capture-0-table.png` and
`capture-0-white-cell.png` are exact crops. `capture-1.png` and its corresponding
crops show adaptation disabled. The JSON histogram files retain measured counts,
and `dark-slide-diagnosis.json` records the summary and image hashes.

## Narrow correction

Only the white-cell assertion changes its measurement. It sums black foreground
coverage on a known white background, `(255 - brightest RGB channel) / 255` per
pixel. Fractionally covered glyph pixels now contribute their actual coverage.
The expectation remains greater than 15 coverage pixels. All other exact-color
thresholds and every existing export/color assertion remain intact.

The corrected test also requires exact white-cell raster equality with adaptation
disabled. A dark-cell negative control verifies that disabling adaptation removes
the light adapted ink. Two copied fixtures establish that the coverage gate rejects
wrong light ink and a blank cell without mutating the original slide:

| White-cell fixture | Measured black coverage | Result against > 15 |
| --- | ---: | --- |
| Correct authored black, adaptation enabled | 109.1569 | Pass |
| Correct authored black, adaptation disabled | 109.1569 | Pass; identical pixels |
| Incorrect `F2F2F2` text on white | 9.4824 | Reject |
| Blank cell | 0 | Reject |

The `color-control/` subdirectory retains a diagnostic copy of the corrected
test, its source hash, complete command/log receipt, all four measured histograms,
and full PNGs/crops. `capture-2-table.png` visibly shows the intentionally incorrect
light text; `capture-3-table.png` shows the blank control. The diagnostic copy
preserves all assertions and adds only capture/reporting code.

## Focused verification and newly exposed export issue

The corrected file's focused run passes the new raster and control assertions,
then fails an existing export assertion: reopened table text colors are empty
strings instead of the authored `000000` values. Five other tests in the file
pass. The focused events and source hash are retained in `focused-tests.stdout`
and `focused-correction-receipt.json`; this incomplete run is not acceptance.

Inspection identifies the relevant engine path in
`packages/quds_office_engine/lib/src/slide/shapes/drawingml.dart`. The writer emits
cell run colors under `rPr/solidFill/srgbClr`. The reader sets `textFillPending`
for the table cell text body, then assigns the color to the enclosing shape
before reaching its `currentCell` fallback. The separate engine owner is handling
that narrow parser issue and its regression tests. This review did not change
engine production code or relax the export assertion.

A first plain-Dart analysis invocation used the reduced workspace and could not
resolve Flutter libraries. Its output is preserved as a setup failure, not a
source diagnosis. The correct Flutter-aware command subsequently passed with
fatal infos enabled; see `focused-flutter-analysis.json` and its stdout/stderr.
The pinned formatter reported zero changes to the corrected test.

Final acceptance belongs to the later `incoming-layout-theme-accepted/` run,
after the parser fix and committed source checkpoint. None of these diagnostic
or focused development runs are added to that accepted total.
