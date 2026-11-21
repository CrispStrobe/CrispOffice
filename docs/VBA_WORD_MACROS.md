# Word VBA macros — `vba-word`

`OfficeVbaWordMacroLanguage` compiles an explicitly selected `.bas` module into
an immutable native Word operation plan. Select language **`vba-word`** and
format **`docx`**.

This page is the practical index. The complete object-member and formatting
reference is preserved in
[Word VBA details](vba-word-macros-details.md).

## How it runs

1. Compile the source without opening a document. Unsupported members fail with
  a source diagnostic.
2. Validate the resulting plan against a detached document.
3. Execute the ordered operations.
4. Publish saved bytes only after the complete plan succeeds.

The dialect does not execute embedded VBA projects, start Microsoft Word or
expose the full Word object model.

## Minimal module

```vb
Option Explicit

Sub Main()
    Dim doc As Document
    Dim p As Paragraph
    Dim target As Range

    Set doc = ThisDocument
    Set p = doc.Paragraphs(1)
    Set target = p.Range

    target.InsertBefore "Report: "
    With target.Font
        .Name = "Arial"
        .Size = 14
        .Bold = True
        .Color = RGB(31, 78, 121)
    End With
    With target.ParagraphFormat
        .Alignment = wdAlignParagraphLeft
        .SpaceBefore = 0
        .SpaceAfter = 6
    End With
End Sub
```

`ThisDocument`, `ActiveDocument` and `Application.ActiveDocument` all bind the
document supplied to the macro session. They never search for another file.

## Supported selectors

| Selector | What it addresses |
| --- | --- |
| `Document.Paragraphs(i)` | Existing body paragraphs |
| `Document.Tables(i)` / `Table.Cell(row, column)` | Existing main-story table cells |
| `Document.Sections(i)` | Existing sections |
| `Section.PageSetup` | Page geometry, orientation and section start |
| `Section.TextColumns` | Uniform text columns |
| `Section.Headers` / `.Footers` | Existing header/footer paragraphs |
| `Range.Font` / `ParagraphFormat` | Formatting of the selected text |
| `ListFormat` / `TabStops` | Supported paragraph list and tab settings |

Selectors are document-independent until native validation. Indexes are
one-based exact integers; an out-of-range selector fails instead of creating
content.

## Formatting coverage

The native plan can apply the documented subset of:

- paragraph styles and direct character formatting;
- paragraph shading, spacing, line spacing and keep controls;
- tab stops and list formatting;
- section page size, margins, orientation and start controls;
- uniform section columns;
- existing header/footer paragraph edits;
- table-cell text;
- proofing language, kerning and complex-script font controls.

Unsupported whole-object assignment, `Duplicate`, runtime type discovery and
property reads are refused. A `ByVal` object helper retains the selector passed
to it; rebinding the helper parameter does not retarget the caller.

## Filling a table template

```vb
Sub Main()
    Dim report As Table
    Set report = ActiveDocument.Tables(1)
    report.Cell(2, 1).Range.Text = "Total: 42"
    report.Cell(2, 2).Range.Text = "Ready"
End Sub
```

Each text assignment becomes one explicit native table-cell operation. Source
indexes are checked during validation/execution, not by opening the document
while compiling.

## Shared language

`vba-word` uses the same local procedures, scalar functions, loops, arrays and
conversion rules as the other dialects. See the
[shared VBA overview](VBA_MACROS.md) and
[argument contract](VBA_ARGUMENTS.md).

## Run

```bash
dart run tool/macros/office_macro.dart compile-vba \
  example/macros/report.bas report.qudsmacro.json

dart run tool/macros/office_macro.dart run-vba \
  input.docx example/macros/report.bas output.docx
```

A compile or execution failure leaves an existing output untouched. Source is
UTF-8 and limited to 1 MiB. The optional final argument selects a
parameterless `Sub`; the default is `Main`.

## Safety and limits

- Embedded VBA is preserved as opaque bytes and never loaded.
- No document discovery, external file opening or application automation.
- The same permissions, tool allowlists, step limits, cancellation and save
  guards as native JSON macros apply.
- Forms, events, COM, macro recording and the complete Word object model are
  out of scope.
- Indexes and formatting values are validated against a real detached document.
- Source-bound local tests do not establish compatibility with every Microsoft
  Word macro.

## Reference

- [Complete Word VBA reference](vba-word-macros-details.md)
- [Shared VBA overview](VBA_MACROS.md)
- [Arguments](VBA_ARGUMENTS.md)
- [Conformance](VBA_CONFORMANCE.md)
- [PowerPoint VBA](VBA_POWERPOINT_MACROS.md)
