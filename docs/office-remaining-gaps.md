# Office format remaining work

Status: 15 November 2026.

This file tracks engine/editor work that is not complete. The host-level backlog
is maintained in the CrispCloud repository
(`docs/office-remaining-gaps-20261115.md`).

## Current baseline

- Sheet/ODS cohort: 501 tests.
- Full engine suite: 2,205 tests.
- Live ODS → XLSX fidelity against LibreOffice: 0.9981 on the measured BOM
  workbook; only drawing/media part names and the absent theme part differ.
- Golden checks use exact per-host references; the last completed Linux
  `office-fidelity` and editor runs passed.

## Open engine/editor work

### 1. `.xlsb`

No BIFF12 reader or writer. `.xlsb` is preview-only in the host. Do not route
BIFF12 through the BIFF8 reader; the record formats are unrelated.

### 2. ODS conditional-format breadth

Supported: numeric comparisons, between/not-between, contains-text,
begins/ends-with, duplicate, generated dxf fill/font.

Not supported: expression rules, top/bottom rules, color scales, data bars,
icon sets, date/time conditions, and arbitrary text predicates. These need new
model kinds or native ODS rule preservation.

### 3. ODS validations

Supported: literal and range-source `cell-content-is-in-list` (resolved after
all sheets exist), whole/decimal/date/text-length conditions, comparison
operators, Excel date serials, `allow-empty-cell`, contiguous cell runs and
correct Excel list quoting.

Not supported: custom `is-true-formula` rules, input-prompt metadata, error
styles and unmodeled cross-sheet source cases.

### 4. ODS metadata and layout

Imported: print areas, print-title rows/columns, global and sheet-local named
ranges, and a basic database-range autofilter.

Not yet imported/modeled: unmodeled named expressions, detailed filter
conditions, tab colors, outline grouping, cell hyperlinks and several page-style
properties.

### 5. ODS package parity

Quds writes `sheet1_drawing.xml`/`sheet1_image1.png`; LibreOffice writes
`drawing1.xml`/`image1.png`. ODS has no theme part. This is cosmetic for Excel
and for the semantic fidelity report, but exact package comparisons still report
it.

### 6. ODT pictures

Raster pictures are embedded as data URIs with a 2 MiB total budget; larger or
unsupported images remain markers. Position/crop/caption/linked/vector media are
not modeled. A bounded image registry would remove the Markdown cap.

### 7. ODT/ODP serialization

ODT and ODP are intentionally read-only in the host. ODS edits save a new XLSX
copy. An in-place ODF writer is a separate serializer project and must preserve
unknown XML/styles/media.

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
