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
| `Cell.Range.Font` / `.ParagraphFormat` | Current cell text and its one ordinary paragraph |
| `Cell.Range.HighlightColorIndex` / `.NoProofing` / `.LanguageID` / `.LanguageIDOther` | Highlight and proofing metadata on current cell text |
| `Document.Sections(i)` | Existing sections |
| `Section.PageSetup` | Page geometry, orientation and section start |
| `Section.PageSetup.TextColumns` | Uniform text columns |
| `Section.Headers` / `.Footers` | Existing header/footer paragraphs |
| `Range.Font` / `ParagraphFormat` | Formatting of the selected text |
| `ListFormat` / `TabStops` | Supported paragraph list and tab settings |

Selectors are document-independent until native validation. Indexes are
one-based exact integers; an out-of-range selector fails instead of creating
content.

## Formatting coverage

The native plan can apply the documented subset of:

- paragraph styles and direct character formatting, including the fixed font-color palette and native automatic foreground;
- paragraph shading, spacing, line spacing and keep controls;
- tab stops and list formatting;
- section page size, margins, orientation and start controls;
- uniform section columns;
- existing header/footer paragraph edits;
- table-cell text, font formatting, paragraph spacing/alignment, custom tabs, highlighting and proofing metadata;
- proofing language, kerning and complex-script font controls.

Unsupported whole-object assignment, `Duplicate`, runtime type discovery and
property reads are refused. A `ByVal` object helper retains the selector passed
to it; rebinding the helper parameter does not retarget the caller.

## Comparing labels and choosing colors

`Font.ColorIndex` accepts all 16 fixed `WdColorIndex` colors plus `wdAuto`.
`Font.Color` accepts packed RGB or `wdColorAutomatic`. Automatic remains a
native value, and explicit writes override inherited/theme colors while
preserving unrelated XML metadata. These writes use existing paragraph,
independent header/footer and supported table-cell selectors.

Source-only `StrComp` can choose a status color using binary comparisons; it
does not read document text. See the [exact foreground contract](vba-word-macros-details.md#font-palette-and-automatic-foreground),
[shared comparison contract](vba-macros-details.md#binary-string-comparison),
and [complete runnable BAS](../packages/quds_office_engine/example/macros/word_comparison_colors.bas).

## Filling and formatting a table template

```vb
Sub Main()
    Dim report As Table
    Set report = ActiveDocument.Tables(1)
    report.Cell(2, 1).Range.Text = "Total: 42"
    With report.Cell(2, 2).Range
        .Text = "Ready"
        .Font.Bold = True
        .Font.ColorIndex = wdGreen
        .ParagraphFormat.Alignment = wdAlignParagraphRight
    End With
End Sub
```

Each text assignment becomes one explicit native table-cell operation. Source
indexes are checked during validation/execution, not by opening the document
while compiling.

`Cell.Range.Font` and `.ParagraphFormat` reuse the documented font properties,
paragraph alignment/spacing, line-spacing controls and `ParagraphFormat.TabStops`.
Typed aliases, nested `With` and named `ByVal` helpers retain the selected cell.
The [complete 2×2 table example](../packages/quds_office_engine/example/macros/word_table_formatting.bas)
fills and formats cells through a reusable helper.

Each selected cell must contain one ordinary paragraph in a supported unmerged
main-story table. Font writes affect its current nonempty text and leave
paragraph/cell marks and future insertion formatting outside the contract.
Fill an empty template cell before applying its Font or text controls; paragraph
formatting can target an empty paragraph. Direct cell-range `Style`, `Shading`,
`ListFormat`, subranges and document reads remain unsupported.
See the [exact cell-formatting contract](vba-word-macros-details.md#formatting-existing-table-cells)
and [local qualification](validation/word-vba-cell-formatting-20261122/README.md).

## Preparing multilingual table reports

`Join(parts[, delimiter])` assembles source text from an allocated local array
declared `As String`. It preserves every slot and its current array order, uses
a space when the delimiter is omitted, and supports an explicit empty or
multicharacter delimiter. Fixed and dynamic arrays share the same bounded
String/work limits. See the [exact Join contract](vba-macros-details.md#joining-source-string-arrays).

```vb
Sub Main()
    Dim parts(1 To 2) As String
    parts(1) = "Prêt"
    parts(2) = "à relire"
    With ActiveDocument.Tables(1).Cell(1, 1).Range
        .Text = Join(parts)
        .LanguageIDOther = wdFrench
        .NoProofing = False
        .HighlightColorIndex = wdYellow
    End With
End Sub
```

The four direct cell controls reuse `docx.runFormat`, including the fixed
highlight palette, strict Boolean proofing flag and 30 mapped normal-slot
language IDs. Explicit false/no-highlight values override inherited settings;
complex-script and East Asian language slots remain unchanged. They affect
current nonempty ordinary runs and retain all cell structure, protection and
atomic-publication checks. They do not install dictionaries or run a proofing
provider. See the [cell text contract](vba-word-macros-details.md#cell-highlighting-and-proofing-controls),
[combined report](../packages/quds_office_engine/example/macros/word_join_report.bas),
and [local qualification](validation/word-vba-cell-text-20261122/README.md).

## Shared language

`vba-word` uses the same local procedures, scalar functions, loops, arrays and
conversion rules as the other dialects. See the
[shared VBA overview](VBA_MACROS.md) and
[argument contract](VBA_ARGUMENTS.md).

## Run

```bash
cd packages/quds_office_engine

dart run tool/macros/office_macro.dart compile-word-vba \
  example/macros/word_table_formatting.bas report.qudsmacro.json

dart run tool/macros/office_macro.dart run-word-vba \
  input.docx example/macros/word_table_formatting.bas output.docx
```

A compile or execution failure leaves an existing output untouched. Source is
UTF-8 and limited to 1 MiB. The optional final argument selects a
parameterless `Sub`; the default is `Main`.

## Safety and limits

- Embedded VBA is preserved as opaque bytes and never loaded.
- No document discovery, external file opening or application automation.
- The same permissions, tool allowlists, step limits, cancellation and save
  guards as native JSON macros apply.
- Forms, events, COM, source-level VBA recording and the complete Word object model are
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
