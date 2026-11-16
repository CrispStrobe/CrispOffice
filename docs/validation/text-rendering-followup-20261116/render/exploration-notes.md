# Native font-subset rendering diagnostics

The final test asserts that a font reopened from a generated Word PDF renders
identically to a directly generated subset with the same Unicode mappings.
It also independently compares retained outline bytes and advance widths with
the bundled Liberation Sans source and checks the exact extracted Unicode text.
The supplementary fixture assigns Latin B/C outlines to U+1F600/U+20000. This is
a Unicode transport fixture, not emoji or CJK glyph coverage.

## Stronger assumptions investigated and rejected

Earlier probes assumed that equal outlines and advance widths implied identical
native bitmaps after changing a font's cmap. Those assumptions did not hold in
this Flutter test renderer:

- `test-events.jsonl`: full original font versus PDF subsets differed in native
  raster pixels for both ABZ and the supplementary-alias ABCZ fixture.
- `probe-events.jsonl`: repeated that original experiment after a scratch probe
  edit failed to find its file; it did not introduce a different source variant.
- `probe-2-events.jsonl`: isolated single glyphs as well as strings. All measured
  advances matched exactly (A/B 42.6875 px; Z 39.09375 px; ABZ 124.46875 px;
  ABCZ 170.6875 px). Single-glyph rasters still differed.
- `subset-events.jsonl`: equal-glyph-set Latin and supplementary PDF subsets
  passed the BMP embedded-versus-direct-subset control, but the Latin-to-alias
  bitmap expectation failed (2834 versus 2919 nontransparent pixels).
- `latin-events.jsonl`: using U+1DF00/U+1DF01, both verified as Latin script in
  the installed Unicode data, still differed (2834 versus 2833 ink pixels).

These observations establish that bitmap parity is not justified by the
outline/advance checks alone. They do not establish the native cause. In
particular, no proof of a specific hinting, font-table, fallback, or script
mechanism was obtained. No pixel tolerance was added, and no code points were
selected simply to make the stronger bitmap assertion pass.

The final test keeps exact pixel equality for the meaningful PDF round-trip
comparison with the identical Unicode subset. Its optional diagnostic reports
the measured difference from the Latin reference separately. That difference
is not hidden or represented as original-font or cross-cmap bitmap parity.
