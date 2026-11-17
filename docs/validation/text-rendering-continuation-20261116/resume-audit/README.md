# Recovered evidence audit and independent PDF recheck

This review recovered and checked the continuation evidence saved in commit
`6bf486ee0bbcd2025c3a42cae7d7003b8c9324a4`, then compared its source hashes
with integration commit `65f943d70260ad634ffd9f0d36a2a3790061a137`.

## Receipt and source integrity

`receipt.json` records the complete audit. `audit_recovered.py` reproduces it
with `--repo /absolute/repository/path --output /new/audit.json`.

- All saved stdout/stderr hashes match the decompressed log bytes. Reparsing
  the test event logs reproduces the recorded summaries exactly.
- The baseline records **10 failures, 9 errors and 1 success** among 20 probes.
  All **508** recorded baseline production/library/manifest/font source hashes
  match Git commit `0d19b16e10c6bc8492f47880321df2d9f2561223`. Its three probe
  files match the current probes byte for byte.
- The recovered engine gate records **169 successes**, no skips or failures,
  and successful strict analysis and formatting. Its **397** recorded inputs
  were unchanged during that original run.
- Relative to the integration checkout, the recovered engine input manifest
  differs only in the incoming ODS writer and its test. The generated local
  `.dart_tool/package_config.json` did not exist at audit time. Therefore this
  audit does **not** claim the historical engine gate qualifies incoming ODS
  changes or the fresh runtime's generated package metadata.
- The restored root dependency lock exactly matches the original receipt:
  `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
- All **12** inputs bound by the recovered Poppler receipt match the current
  checkout, including the font/PDF production files, fixtures and lock. All
  recorded PDF, PNG, extracted-text and producer-receipt artifact hashes match.

The captured engine runner `../engine-attempt1/validate-used.py` matches the
engine receipt's harness hash. The current runner adds a `--flutter` launcher
option used only for the editor command; the engine command and source-hashing
logic are unchanged. The exact difference is retained in
`engine-harness-difference.patch`. The baseline and Poppler harnesses match their
recorded hashes.

## Fresh independent renderer result

`poppler-recheck/receipt.json` records a new run of the committed independent
PDF verifier against the recovered engine artifacts. No Dart tests were
rerun by this check. The input artifacts and relevant checkout source files
were unchanged during the check.

Poppler's rendered CID-encoded PDF and the identity-glyph raster control are
exactly equal at **320 by 112 pixels, 72 dpi**: **0 differing pixels**, with
**2,109 nonwhite pixels** in each. The new PNG hashes also match the recovered
PNGs. Visual inspection confirms clean, unclipped Latin outlines for four
`A` glyphs followed by `Z`.

Independent extraction from both the directly encoded PDF and the Word export
preserves the exact authored sequence `U+0041 U+1F600 U+20000 U+0041 U+005A`.
Only the extractor's trailing newlines/page-break character are removed; no
Unicode normalization or lossy conversion is applied.

These are synthetic aliases of bundled Latin outlines. The checks establish
CID-to-glyph painting and Unicode extraction for this fixture; they do not
establish actual emoji/CJK font coverage, full shaping parity, platform
conformance, or performance improvements. The identity PDF is a raster control
only, because its legacy extraction mapping deliberately collapses aliases.

The renderer used Poppler `pdftoppm` 26.05.0 and `pdftotext` 25.03.0 with Pillow
13.0.0. These are local verification tools, not new shipped dependencies.
No GitHub Actions were accessed. Historical and repeated cohorts are not
summed into a new total.
