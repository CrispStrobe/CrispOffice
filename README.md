# Quds Office Suite

**A pure-Dart Office engine with Flutter editors for Word, spreadsheets,
presentations, PDF and band reports.**

This is the CrispStrobe fork used by **CrispOffice Studio** and
[CrispCloud](https://github.com/CrispStrobe/CrispCloud). The engine has no
Flutter dependency; the editor surfaces are custom `RenderBox` canvases rather
than wrapped text fields.

<p align="center">
  <a href="https://pub.dev/packages/quds_office_engine"><img alt="engine" src="https://img.shields.io/pub/v/quds_office_engine.svg?label=quds_office_engine&color=2B579A"/></a>
  <a href="https://pub.dev/packages/quds_office_editor"><img alt="editor" src="https://img.shields.io/pub/v/quds_office_editor.svg?label=quds_office_editor&color=217346"/></a>
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-0B1F3A"/></a>
</p>

## What it does

| Area | Capabilities |
| --- | --- |
| **Word** | DOCX/DOCM/DOTX editing, paginated layout, BiDi/RTL, comments, tracked changes, review workspace, styles, tables, fields, headers/footers, Zotero citations, proofing, autocorrect and configurable Word/Writer shortcuts |
| **Spreadsheets** | XLSX/XLSM editing, formula engine, charts, conditional formats, validation, frozen panes, undo/redo, XLS import and ODS import/export |
| **Presentations** | PPTX editing, slide/shape layout, rich text, animations and Morph |
| **PDF** | Viewer/editor, annotations, forms, page organisation and export |
| **Reports** | `.qrep` band reports rendered by the engine to PDF, XLSX and DOCX |
| **Mail** | IMAP, Exchange EWS, Gmail and Microsoft 365; durable drafts, Outbox, cached mail, search and flag journal in the native Studio |
| **Automation** | Native macros/MCP bridge and bounded Excel/Word/PowerPoint VBA subsets |

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="packages/quds_office_editor/example/screenshots/word.png" alt="Word editor"/><br/><b>Writer</b></td>
    <td width="50%"><img src="packages/quds_office_editor/example/screenshots/excel.png" alt="Sheet editor"/><br/><b>Spreadsheet</b></td>
  </tr>
  <tr>
    <td><img src="packages/quds_office_editor/example/screenshots/powerpoint.png" alt="Presentation editor"/><br/><b>Presentation</b></td>
    <td><img src="packages/quds_office_editor/example/screenshots/pdf.png" alt="PDF editor"/><br/><b>PDF</b></td>
  </tr>
</table>

## Packages

| Package | Runtime | Purpose |
| --- | --- | --- |
| [`quds_office_engine`](packages/quds_office_engine) | Pure Dart | OOXML, OPC/ZIP, OLE, formulas, layout, BiDi, PDF, reports |
| [`quds_office_editor`](packages/quds_office_editor) | Flutter | Word, sheet, slide, PDF and report-design surfaces |
| [`quds_reports`](packages/quds_reports) | Pure Dart | `.qrep` templates and PDF/XLSX/DOCX export |
| [`quds_report_studio`](apps/quds_report_studio) | Flutter desktop | Standalone report designer |
| [`quds_mail_*`](packages) | Dart/Flutter | Mail core, MIME, store, transport and reader UI |

## Quick start

```bash
git clone https://github.com/CrispStrobe/quds_office_suite.git
cd quds_office_suite
dart pub get

# CrispOffice Studio
cd packages/quds_office_editor/example
flutter run -d macos        # or linux / windows

# Engine gallery: DOCX, XLSX, PPTX and PDF output
cd ../../quds_office_engine
dart run example/rich_export_gallery.dart
```

Engine-only consumers need `quds_office_engine`. Editor consumers should depend
on `quds_office_editor`, which brings the engine and report packages with it.
Publishing instructions are in [docs/PUBLISHING.md](docs/PUBLISHING.md).

## Architecture

```text
Host app / ribbon / dialogs
          │
   quds_office_editor      Flutter RenderBox, IME, hit-testing
          │
   quds_office_engine      models, OOXML, layout, formulas, PDF
          │
   OPC / ZIP / OLE / XML   portable package and file IO
```

Rules:

- The engine never imports Flutter or `dart:ui`.
- Document surfaces use custom `RenderBox`/`LeafRenderObjectWidget` canvases,
  not `TextField`, `ListView` or `InteractiveViewer`.
- Host chrome may use Material.

## Notable capabilities

- **CrispOffice Studio** is the reference desktop host: ribbons, window chrome,
  Mail workspace, downloads/font packs and Office editors.
- **Proofing** supports German, English and Arabic paths, with Hunspell, Harper,
  spaCy and deterministic rule engines. Adaptive scheduling keeps provider work
  out of active typing.
- **Zotero** supports local/online libraries, native desktop hand-off, citation
  fields, bibliographies and undoable edits.
- **Legacy and ODF** paths include structured DOC conversion, XLS import and
  bounded ODS/ODT reading and export. Original files are not silently rewritten.
- **Fonts** can come from the host, installed Office fonts or reviewed open-font
  packs. Missing faces use explicit fallbacks rather than invented metrics.
- **Macros** are inert and preserved unless explicitly executed through the
  documented native/MCP or VBA pathways.

## Verification

Use the repository checks after shared-source changes:

```bash
dart pub get
cd packages/quds_office_engine && dart test
cd ../quds_office_editor && flutter test
cd ../../packages/quds_office_editor/example && flutter test
cd ../.. && flutter analyze
```

The typing benchmark lives in
`packages/quds_office_editor/example/test/studio_typing_proofing_benchmark_test.dart`
and runs with `QUDS_TYPING_BENCHMARK=1`.

Detailed records:

- [Office capability record](docs/office-capabilities-20261114.md)
- [Remaining format gaps](docs/office-remaining-gaps.md)
- [Document review](docs/document-review.md)
- [Proofing roadmap](docs/PROOFING.md)
- [Zotero support](docs/zotero-support.md)
- [Mail roadmap](docs/roadmaps/mail/README.md)
- [VBA parity](docs/VBA_PARITY_ROADMAP.md)
- [Typing/autocorrect performance roadmap](docs/roadmaps/typing-autocorrect-performance.md)

## Known limits

- Rendering is high-fidelity but not pixel-identical to Microsoft Office or
  LibreOffice for every document.
- Unsupported OOXML/ODF constructs are preserved where the package model allows,
  or rejected explicitly; they are not silently rewritten.
- Macro execution is bounded to the documented subsets. Signed packages are
  refused rather than modified.
- Live provider interoperability, native mounts and some mobile/browser paths
  remain platform-specific or unqualified.

## Contributing and licence

See [CONTRIBUTING.md](CONTRIBUTING.md). Keep engine and editor changes
separable, add tests beside changed behaviour, and update package changelogs for
public behaviour changes.

[MIT](LICENSE) © Mohammed Asaad Asaad. Fork changes © CrispStrobe, same licence.
