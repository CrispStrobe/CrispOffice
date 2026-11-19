# Dark slide correction: independent follow-up

All **6 dark-slide test cases passed, with zero failures or skips**, after the
narrow table-cell text-color parser fix. The original export assertion remains
intact. The renderer, theme, corrected test, and parser hashes were unchanged
during this focused run.

`focused-after-parser.json` records the exact Flutter command, environment,
duration, raw log hashes, test totals, and before/after source hashes.
`focused-after-parser.stdout` preserves the complete Dart JSON events;
`independent-review.json` records the source review.

| Input | SHA-256 |
| --- | --- |
| Corrected `office_dark_slide_test.dart` | `8a4bfdcf1a4fb913a2533ed523c05b6250427a49596a2051dc022dad5e262109` |
| Corrected `drawingml.dart` | `7d77b680b43bf2a02bd3ea24642c8f9faf3f19f814c3dba61398c1d01ca34c12` |

The production change routes an active table cell's pending text color to that
cell instead of the enclosing shape. It preserves the existing representative
first cell color, cell-fill precedence, stroke/fill routing, and ordinary shape
text behavior. The new engine regressions independently cover raw XML with
themed/RGB/automatic colors and later runs, neighboring shape isolation, and three
save/reopen cycles. This review found no additional issue in that narrow diff.

The GUI correction measures black glyph coverage on white instead of counting
only fully opaque black pixels. It retains every other original color threshold
and export assertion, compares the white cell exactly with adaptation disabled,
and rejects incorrect light ink and blank-cell controls. The full raster proof,
histograms, PNGs/crops, original reproduced failure, and focused export failure
remain frozen in
[the earlier diagnostic report](../latest-frontier/DARK_SLIDE_DIAGNOSIS.md).

These six passing cases are focused correction evidence. They are not added to
the later full accepted GUI run, whose receipt belongs under
`incoming-layout-theme-accepted/`.
