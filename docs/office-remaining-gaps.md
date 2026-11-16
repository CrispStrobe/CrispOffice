# Office format remaining work

Status: 15 November 2026.

This file tracks engine/editor work that is not complete. The host-level backlog
is maintained in the CrispCloud repository
(`docs/office-remaining-gaps-20261115.md`).

## Current baseline

- Sheet/ODS cohort: 514 tests.
- Last clean full engine run: 2,205 tests. Two unrelated CLI
  bookmark/content-control tests currently fail on main.
- Live ODS → XLSX fidelity against LibreOffice: 0.9981 on the measured BOM
  workbook; only drawing/media part names and the absent theme part differ.
- Golden checks use exact per-host references; the last completed Linux
  `office-fidelity` and editor runs passed.

## Open engine/editor work

### Proofing and automatic German hyphenation

The accepted [PROOFING.md](PROOFING.md) roadmap covers a real spelling provider,
language and provider availability, German lexicon and suggestions, German
pattern hyphenation, original grammar/style rules, diagnostic UI and undoable
corrections, and optional English/mobile backends. The initial implementation
status is planned. The experimental German model remains an evaluation.

### 1. `.xlsb`

No BIFF12 reader or writer. `.xlsb` is preview-only in the host. Do not route
BIFF12 through the BIFF8 reader; the record formats are unrelated.

### 2. ODS conditional-format breadth

Supported: numeric comparisons, between/not-between, contains-text,
begins/ends-with, duplicate, top/bottom ranks, top/bottom percentages and
above/below average, with generated dxf fill/font.

Not supported: expression rules, color scales, data bars, icon sets, date/time
conditions, and arbitrary text predicates. These need new
model kinds or native ODS rule preservation.

### 3. ODS validations

Supported: literal/range-source lists, whole/decimal/date/text-length and
custom-formula rules; comparison operators, Excel date serials,
`allow-empty-cell`, contiguous cell runs, input prompts, error
title/message/style and correct Excel list quoting. Range sources resolve after
all sheets exist.

Not supported: ODF condition grammar outside the shared model (for example time
or arbitrary multi-condition expressions) and dynamic source-range links; these
decline rather than being approximated.

### 4. ODS metadata and layout

Imported: print areas/titles, global and sheet-local named ranges and named
expressions, tab colors, cell hyperlinks, row/column outline groups and database-range filter predicates with
equality, comparison and empty checks.

Not yet imported/modeled: exotic filter grammar and several page-style
properties.

### 5. ODS package parity

Quds writes `sheet1_drawing.xml`/`sheet1_image1.png`; LibreOffice writes
`drawing1.xml`/`image1.png`. ODS has no theme part. This is cosmetic for Excel
and for the semantic fidelity report, but exact package comparisons still report
it.

### 6. ODT pictures

The host keeps supported raster pictures in a bounded image registry (8 MiB per
image, 24 MiB total) and references them from markup by synthetic keys; larger
or unsupported images remain markers. Position/crop/caption/linked/vector media
are not modeled.

### 7. ODF serialization

ODT and ODP are intentionally read-only in the host. Ordinary ODS Save writes a
new XLSX copy; the host also exposes an explicit **Export as ODS** action.
`OdsSheetWriter` exports the modeled workbook subset (values, formulas, styles,
number formats, merges, geometry, hidden state, comments, links, names, print
areas/titles, autofilter ranges and predicates, pictures, conditional formats,
validations, row outline groups, authored page setup and header/footer
sections). An ODT/ODP writer remains a separate project.

### 8. ODP slide fidelity

Frames, custom shapes, text styles/colors, fills, images, backgrounds and notes
are supported. Transitions/animations, charts, embedded objects, true table
shapes, master/placeholder inheritance and some grouped geometry are not.

### 9. BIFF8 residuals

NAME-token formula names, additional shared-formula edge cases and native-font
column-width precision remain. No BIFF writer is planned.

## Verification

```bash
cd packages/quds_office_engine
dart test test/sheet_*_test.dart test/legacy_sheet_reader_test.dart \
  test/ods_sheet_reader_test.dart test/sml_styles_date_test.dart \
  test/sheet_macro_preservation_test.dart

cd packages/quds_office_editor
flutter test test/sheet_grid_history_test.dart test/sheet_hidden_sheet_test.dart
```

The private Excel steering harness carries the broader audit and corpus
measurements; no private workbook is committed here.
