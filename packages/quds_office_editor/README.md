# quds_office_editor

**Embeddable Flutter surfaces for Word, spreadsheets, presentations, PDF and
band reports.** Every document surface is a custom `RenderBox` — not a
`TextField`, `ListView` or `InteractiveViewer`.

This is the interaction half of Quds Office Suite. The document models,
layout, formulas, PDF engine and report generator live in pure Dart
[`quds_office_engine`](https://pub.dev/packages/quds_office_engine). You own the
ribbon, menus and window chrome; this package paints the document.

<p>
  <a href="https://pub.dev/packages/quds_office_editor"><img alt="pub package" src="https://img.shields.io/pub/v/quds_office_editor.svg"/></a>
  <a href="https://pub.dev/packages/quds_office_editor/score"><img alt="pub points" src="https://img.shields.io/pub/points/quds_office_editor"/></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-0B1F3A"/></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-RenderBox-02569B?logo=flutter&logoColor=white"/>
</p>

<table>
  <tr>
    <td width="50%"><img src="example/screenshots/word.png" alt="Word editor"/><br/><b>Writer</b>: paginated canvas, BiDi caret, review</td>
    <td width="50%"><img src="example/screenshots/excel.png" alt="Sheet editor"/><br/><b>Spreadsheet</b>: virtualized grid, formulas, charts</td>
  </tr>
  <tr>
    <td><img src="example/screenshots/powerpoint.png" alt="Presentation editor"/><br/><b>Presentation</b>: stage, animations, slideshow</td>
    <td><img src="example/screenshots/pdf.png" alt="PDF editor"/><br/><b>PDF</b>: viewer, selection, annotations</td>
  </tr>
</table>

## Surfaces

| Widget | Controller | What it paints |
| --- | --- | --- |
| `QudsWordEditor` | `WordEditorController` | Paginated pages, caret, tables, comments, headers, notes, OMML, pictures |
| `QudsSheetEditor` | `SheetEditorController` | Virtualized grid, formula bar, freeze panes, fill handle, charts |
| `QudsSlideEditor` | `SlideEditorController` | Slide stage, resize/rotate handles, snap guides, transitions, slideshow |
| `QudsPdfViewer` | `PdfViewerController` | Read-only PDF pages, zoom, find, links, thumbnails |
| `QudsPdfEditor` | `PdfEditorController` | Same canvas plus annotation, forms, page operations and save |
| `QudsReportDesigner` | `ReportDesignerController` | Band-report canvas, inspector, data explorer, preview and export |

## Install

```yaml
dependencies:
  quds_office_editor: ^1.6.0
```

```bash
flutter pub add quds_office_editor
```

Requires Flutter **3.44+** and Dart **3.12+**. The engine is pulled in as
`quds_office_engine: ^1.5.0`.

```dart
import 'package:quds_office_editor/quds_office_editor.dart';
```

Register the bundled fonts once before the first frame:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OfficeHostFonts.ensureRegistered();
  runApp(const MyApp());
}
```

## Word

```dart
final controller = WordEditorController.fromBytes(docxBytes);

QudsWordEditor(
  controller: controller,
  toolbarBuilder: (context, c) => const SizedBox.shrink(), // your ribbon
);

final Uint8List saved = controller.saveBytes();
```

The Word canvas provides:

- logical caret and IME without `EditableText`;
- bold, italic, underline, colour, highlight and baseline controls;
- alignment, lists, indents, spacing and per-section LTR/RTL;
- mixed portrait/landscape sections and interactive rulers;
- tables, pictures, charts, comments, footnotes and headers/footers;
- page/section breaks, TOC, OMML equations, find/replace and print;
- undo, redo, copy, cut, paste and review overlays.

## Spreadsheet

```dart
final controller = SheetEditorController.fromBytes(xlsxBytes);

QudsSheetEditor(
  controller: controller,
  frozenRows: 1,
  frozenCols: 1,
);

final Uint8List saved = controller.saveBytes();
```

The grid is virtualized, so large sheets keep a bounded paint cost. It supports
A1 selection, fill handle, row/column insertion, the formula bar, freeze panes,
RTL sheets, number formats, charts and recalculation through the engine's
formula dependency graph.

## Presentation

```dart
final controller = SlideEditorController.fromBytes(pptxBytes);

QudsSlideEditor(controller: controller);
```

Edit mode supports move, resize, rotate, snap guides, shape text, tables,
pictures, charts, z-order, entrance/emphasis/exit/motion paths and transitions.

```dart
controller.startShow(from: 0);
controller.showNext();
controller.showPrevious(); // reverses that animation or transition
controller.endShow();
```

## PDF

`QudsPdfViewer` is display-only: zoom, find, copy, outline jumps, internal and
external links. `QudsPdfEditor` adds highlights, notes, AcroForm values, page
insert/delete/rotate and incremental save.

```dart
final viewer = PdfViewerController.fromBytes(pdfBytes);
QudsPdfViewer(
  controller: viewer,
  options: const PdfViewerOptions(
    fitPolicy: PdfFitPolicy.width,
    minZoom: 0.25,
    maxZoom: 4,
  ),
);

final editor = PdfEditorController.fromBytes(pdfBytes);
editor.highlightSelection();
editor.rotateCurrentPage(90);
final Uint8List saved = editor.saveBytes();
```

Rotation is a clockwise quarter-turn of the PDF `/Rotate` value; it does not
reflow the page. Page assembly (merge, split, stamp, crop) belongs to
`PdfToolbox` in the engine.

## Report designer

`QudsReportDesigner` embeds the full `.qrep` editor:

- data explorer with typed columns, calculated fields and CSV/JSON import;
- inspector for properties, variables, images and fonts;
- expression autocomplete that knows the current data schema;
- named elements that a host can fill from code;
- live, paginated preview and PDF/XLSX/DOCX export;
- Arabic and English templates with images and fonts stored in the `.qrep`.

![Report designer](example/screenshots/report_designer.png)

See the [standalone Report Studio app](../../apps/quds_report_studio) for a
desktop host without writing any Flutter code.

## Fonts and direction

Host fonts are resolved through `OfficeFontSet`. Register bundled faces with
`OfficeHostFonts.ensureRegistered()` or supply your own. The package does not
download fonts automatically.

The surfaces support LTR, RTL and mixed BiDi text, including Arabic shaping and
direction-aware selection and caret movement. Missing glyphs keep their layout
advance and paint a visible fallback; they are reported only when actually
painted.

## Modes and theming

```dart
const OfficeSurfaceConfig(
  mode: OfficeInteractionMode.editing, // editing | selecting | viewing
  theme: OfficeTheme.light,
  textDirection: TextDirection.ltr,
  strings: OfficeStrings.english,
  showRulers: true,
  showFormulaBar: true,
  showGridlines: true,
);
```

`OfficeTheme.light`, `OfficeTheme.dark` and `OfficeTheme.highContrast` are
starting palettes. Host chrome stays yours; only the document surface is
painted by this package. `OfficeStrings.english` and `OfficeStrings.arabic`
ship as complete typed tables.

## Load and save

```dart
await controller.loadBytesAsync(
  bytes,
  password: password,
  onProgress: (p) => setState(() => label = p.stage),
);

final Uint8List out = controller.saveBytes(password: optionalPassword);
```

Large documents open through `OfficeIsolateOpen`; saves can use a worker
isolate. Password-protected OOXML packages open when a password is supplied.
Export any Office controller to PDF with
`OfficePdfExport.fromBytes(controller.saveBytes())`.

## Rules

The document surface must remain a custom paint surface:

- no `TextField`, `TextFormField`, `EditableText` or `SelectableRegion`;
- no `ListView`, `SingleChildScrollView` or `InteractiveViewer` on the document;
- no per-frame model rebuilds or layout recomputation during typing.

Those widgets are fine in your toolbar, find bar and dialogs. This separation is
what keeps BiDi caret logic, pagination, selection and rendering consistent.

## Studio example

`example/` is the full CrispOffice Studio host: ribbons, settings, Mail
workspace, file handling, shortcuts and dialogs. Run it with:

```bash
cd packages/quds_office_editor/example
flutter run -d macos   # or windows / linux
```

## Documentation

- [Repository overview](../../README.md)
- [Engine package](../quds_office_engine/README.md)
- [Document review](../../docs/document-review.md)
- [Proofing](../../docs/PROOFING.md)
- [Zotero](../../docs/zotero-support.md)
- [Typing/autocorrect performance](../../docs/roadmaps/typing-autocorrect-performance.md)

## Licence

MIT. See [LICENSE](LICENSE).
