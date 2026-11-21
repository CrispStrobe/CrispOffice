# quds_office_engine

**Pure-Dart Office, PDF and report engine.** Build or open DOCX, XLSX and PPTX;
read bounded legacy and OpenDocument files; calculate spreadsheet formulas;
paint PDF 1.7; and generate band reports without Microsoft Office, LibreOffice
or a conversion service.

No Flutter. No `dart:ui`. `Uint8List` in, `Uint8List` out.

<p>
  <a href="https://pub.dev/packages/quds_office_engine"><img alt="pub package" src="https://img.shields.io/pub/v/quds_office_engine.svg"/></a>
  <a href="https://pub.dev/packages/quds_office_engine/score"><img alt="pub points" src="https://img.shields.io/pub/points/quds_office_engine"/></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-0B1F3A"/></a>
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.12%2B-0175C2?logo=dart&logoColor=white"/>
</p>

> **Fork status.** This is the CrispStrobe/CrispCloud fork. It adds bounded
> legacy and OpenDocument support on top of the upstream OOXML engine. ODT and
> ODP are formatted read-only views with new-document export subsets; ODS has
> typed import and a new-document writer. In-place ODF preservation, legacy
> writers, VBA/ActiveX execution and pixel-identical vendor rendering are not
> claimed.

## What it does

| Area | Capability |
| --- | --- |
| **Word** | DOCX/DOCM/DOTX models, pagination, styles, tables, comments, tracked changes, fields, notes, TOC, OMML, mail merge, BiDi |
| **Spreadsheets** | XLSX/XLSM models, shared formulas, dependency graph, charts, freeze panes, RTL, named ranges, sparklines |
| **Presentations** | PPTX models, layouts/masters, placeholders, theme colours, transitions and Morph |
| **Office → PDF** | Native PDF 1.7 with laid-out Word pages, sheet grids, slides/notes, links, outlines and subsetted fonts |
| **PDF files** | Open, paint, extract, annotate, fill forms, merge/split/rotate/stamp, incremental save |
| **Band reports** | `.qrep` packages with bands, groups, expressions, charts, barcodes and shape maps → PDF, XLSX or DOCX |
| **Document tools** | Text extraction/search/replace, statistics, properties, find in PDF, isolate open/save |
| **Bounded readers** | Word 97–2007, BIFF8 XLS, current-slide PPT, ODT/ODP views and ODS workbooks |

Interactive surfaces live in
[`quds_office_editor`](https://pub.dev/packages/quds_office_editor).

## Install

```yaml
dependencies:
  quds_office_engine: ^1.5.0
```

```bash
dart pub add quds_office_engine
```

Dart **3.12+**. Works in Flutter apps, CLIs, servers, isolates and on the web.

```dart
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/pdf_widgets.dart' as pw;
```

## Quick start

### Build a Word document

```dart
final bytes = (DocxDocumentBuilder()
      ..heading('Quarterly report')
      ..paragraph('Generated without Microsoft Office.')
      ..bulletList(['Writer', 'Spreadsheet', 'Presentation'])
      ..table([
        ['KPI', 'Q1', 'Q2'],
        ['Documents', '120', '148'],
      ]))
    .build();
```

Open, inspect and serialize a typed model:

```dart
final document = WordDeserializer().readBytes(bytes);
final text = OfficeTextExtractor.extract(bytes, name: 'report.docx');
final out = WordSerializer().writeBytes(document);
```

`WordLayout` paginates the same model used by PDF export and the Flutter
canvas. Sections can mix portrait and landscape pages.

### Build a workbook and calculate

```dart
final book = XlsxWorkbookBuilder();
final sheet = book.addSheet('Budget')
  ..freezeRows = 1
  ..addRow(['Item', 'Qty', 'Price'])
  ..addRow(['Paper', 40, 1.25]);
final xlsx = book.build();

final calc = SmlWorksheet(name: 'Calc', sheetId: 1);
calc.cellA1('A1').value = 10;
calc.cellA1('A2').value = 20;
calc.cellA1('A3').formula = '=SUM(A1:A2)';
final workbook = SmlWorkbook(sheets: [calc]);
FormulaDepGraph(workbook).recalculate();
```

Formula support includes math, logic, lookup, text, statistics and date
families. It is a deliberate subset; unknown names return `#NAME?`, not a
silent guess.

### Export Office to PDF

```dart
final pdf = OfficePdfExport.fromBytes(
  docxBytes,
  fonts: OfficeFontSet(
    primary: SfntFont.parse(fontBytes),
  ),
);
```

`OfficePdfExport` accepts DOCX, XLSX and PPTX bytes. Missing fonts are reported
and replaced only at paint time; source metadata is not rewritten.

### Work with PDF files

```dart
final pdf = PdfFile.open(bytes);
final merged = PdfToolbox.merge([
  PdfPageSource(a, ranges: ['1-3']),
  PdfPageSource(b, ranges: ['2-4']),
]);
final rotated = PdfToolbox.rotate(bytes, degrees: 90, ranges: ['1-3']);
```

The PDF file API also extracts text, fills AcroForm fields, adds annotations,
grafts pages and writes incremental updates. Body-text reflow is not supported.

### Generate a band report

A `.qrep` is a ZIP containing an XML layout plus its images and TrueType fonts.
`quds_reports` turns it into paginated output:

```dart
final report = QudsReportEngine.fromPackage(qrepBytes);
final pdf = await report.exportToPdf({'invoice': invoice});
final xlsx = report.exportToExcel({'invoice': invoice});
final docx = report.exportToWord({'invoice': invoice});
```

Templates, expressions, grouping, charts and the desktop designer are described
in [`quds_reports`](https://pub.dev/packages/quds_reports) and the
[Report Studio app](../../apps/quds_report_studio).

## Format support

| Format | Read | Write | Notes |
| --- | --- | --- | --- |
| DOCX / DOCM / DOTX | Yes | Yes | Main Office editing format |
| DOC / DOT | Partial | — | Word 97–2007 main-story import; host can save a DOCX copy |
| XLSX / XLSM / XLTX | Yes | Yes | Styles, formulas, charts, RTL |
| XLS / XLT | Partial | — | BIFF8 import; host saves a new XLSX copy |
| XLSB | — | — | Host preview only |
| PPTX | Yes | Yes | Shapes, notes, layouts, transitions |
| PPT / PPS / POT | Partial | — | Bounded current-slide text import |
| ODT | Yes | New subset | Formatted read-only model; no in-place preservation |
| ODS | Yes | New subset | Typed sheets, pictures, validations, conditional formats |
| ODP | Yes | New subset | Positioned text, pictures, tables, fills, transitions |
| PDF | Yes | Yes | PDF 1.7 writer, annotations, forms, toolbox |
| `.qrep` | Yes | Yes | Band reports → PDF/XLSX/DOCX |

Password-protected OOXML packages open when a password is supplied.
Password-protected PDFs use the supported Standard Security revisions.

## Reports and PDF composition

- `quds_reports` — `.qrep` band reports with typed data, expressions, grouping,
  charts and Arabic amount-in-words.
- `pdf_widgets` — constraint layout (`Document`, `Table`, `MultiPage`), charts,
  headers, footers, watermarks and a synchronous `Document.save()`.
- `pdf_templates` — classified report layouts and LTR/RTL skins.

![Report designer output](example/screenshots/report_sales_performance.png)

## Large files and isolates

```dart
final payload = await OfficeIsolateOpen.word(bytes);
final document = payload.document;
final laidOut = payload.laidOut;
```

Office and PDF opens can run on worker isolates. Saves can use
`OfficeIsolateSave`, keeping a UI isolate responsive.

## Limits

- Rendering is high-fidelity, not pixel-identical to Microsoft Office or
  LibreOffice.
- Legacy, ODF and unknown OOXML constructs outside the documented model are
  rejected or preserved only where explicitly supported. They are never
  silently rewritten into a false claim of fidelity.
- Excel LAMBDA, Power Pivot and Power Query are out of scope.
- Multi-series Office charts are not fully drawn; one series per chart.
- PDF editing is annotation/form/page assembly, not body-text reflow.
- OCR, PDF/A certification, JBIG2 arithmetic regions and JPEG2000 are not
  implemented.
- Macro and ActiveX payloads are never executed. VBA support is a separately
  compiled, bounded dialect.

## Examples

```bash
cd packages/quds_office_engine
dart run example/engine_quickstart.dart
dart run example/rich_export_gallery.dart
dart run example/report_quickstart.dart
```

- [`example/engine_quickstart.dart`](example/engine_quickstart.dart)
- [`example/rich_export_gallery.dart`](example/rich_export_gallery.dart)
- [`example/report_quickstart.dart`](example/report_quickstart.dart)
- [`example/pdf_widgets_invoice.dart`](example/pdf_widgets_invoice.dart)

## Documentation

- [Repository overview](../../README.md)
- [Office capability record](../../docs/office-capabilities-20261114.md)
- [Remaining format gaps](../../docs/office-remaining-gaps.md)
- [VBA macro overview](../../docs/VBA_MACROS.md)
- [Report templates](https://pub.dev/packages/quds_reports)

## Licence

MIT. See [LICENSE](LICENSE).
