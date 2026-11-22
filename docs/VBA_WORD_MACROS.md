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
| `Table.Rows(i).Cells(j)` / `Table.Columns(j).Cells(i)` | The same cells through typed row/column collections |
| `Cell.Range.InsertAfter` | Append to current cell text with retained run formatting |
| `Cell.Range.InsertBefore` / `.Paragraphs(1).Range.InsertBefore` | Prefix current cell text with retained run formatting |
| `Cell.Range.Font` / `.ParagraphFormat` | Current cell text and its one ordinary paragraph |
| `Cell.Range.Paragraphs(1)` / `.Paragraphs.Item(1)` | The existing cell paragraph, including its Style and background Shading |
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

`Paragraphs`, `Sections`, `Headers`, `Footers` and their `Item` calls accept
required named `Index:=` as well as positional indexes. `Paragraphs` and
`Sections` can be retained in typed variables and passed to required `ByVal`
helpers. See the [exact selector contract](vba-word-macros-details.md#named-document-and-story-selectors).

## Formatting coverage

The native plan can apply the documented subset of:

- paragraph styles and direct character formatting, including the fixed font-color palette and native automatic foreground;
- paragraph shading, spacing, line spacing and keep controls;
- tab stops and list formatting;
- section page size, margins, orientation and start controls;
- uniform section columns;
- existing header/footer paragraph edits;
- table-cell text, font formatting, paragraph spacing/alignment, custom tabs, highlighting and proofing metadata;
- styles and background shading on explicitly selected cell paragraphs, including empty paragraphs;
- proofing language, kerning and complex-script font controls.

Unsupported whole-object assignment, `Duplicate`, runtime type discovery and
property reads are refused. A `ByVal` object helper retains the selector passed
to it; rebinding the helper parameter does not retarget the caller.

## Extracting reference labels

Ordinary `Left`, `Right` and expression `Mid` now work alongside their `$`
forms. They extract source-known UTF-16 text and return scalar Variants;
Empty input gives `""`, and Null text stays Null until explicitly handled.

```vb
Sub Main()
    Dim lines As Paragraphs, reference As Variant
    reference = "INV-0042-DE"
    Set lines = ActiveDocument.Sections.Item(Index:=2).Headers(Index:=wdHeaderFooterPrimary).Range.Paragraphs
    lines.Item(Index:=1).Range.InsertBefore Text:=Left(reference, 3) & " " & Mid(reference, 5, 4) & ": "
End Sub
```

The selected existing header receives `INV 0042: ` before its current text.
The [complete reference-label example](../packages/quds_office_engine/example/macros/word_text_selectors.bas)
also uses a typed collection helper, body and footer targets, and a missing
reference handled with `IsNull`. Numeric text coercion and named intrinsic
arguments remain outside the bounded [String contract](vba-macros-details.md#string-intrinsics).

## Filling a table from delimited records

Use `Split` to populate a local dynamic String array from source-known text:

```vb
Sub Main()
    Dim fields() As String, column As Long
    fields = Split("Item|Status", "|")
    For column = LBound(fields) To UBound(fields)
        ActiveDocument.Tables(1).Cell(1, column + 1).Range.Text = fields(column)
    Next column
End Sub
```

`Split` always produces zero-based elements, independently of `Option Base`.
It accepts an optional delimiter, result limit and binary comparison mode.
Empty fields are retained; an empty input produces no elements. The
[complete 2×2 report](../packages/quds_office_engine/example/macros/word_split_report.bas)
splits both records and fields, fills the cells, emphasizes the headings and
colors the status cell in seven native operations.

The target must be a local dynamic String array. General array values,
locale comparison and live document reads remain unsupported. All writes use
the existing table-cell admission, detached validation and publication rules.
See the [exact Split contract](vba-macros-details.md#splitting-source-string-arrays)
and [local qualification](validation/word-vba-split-20261122/README.md).

## Editing fixed-width template labels

`Mid(label, start[, length]) = text` and `Mid$(...) = text` replace part of a
local String without changing its length. They also edit allocated
String/Variant array elements and helper-local String values. The indexes count
UTF-16 units; the start must address an existing unit, and replacement text is
truncated to the requested and available span.

```vb
Sub Main()
    Dim label As String
    label = "INV-0000 | OPEN"
    Mid$(label, 5, 4) = "0042"
    Mid(label, 12) = "DONE"
    ActiveDocument.Tables(1).Cell(1, 1).Range.Text = label
End Sub
```

The cell receives `INV-0042 | DONE`. All text comes from source-local values;
this statement does not read or edit a document Range directly. The
[complete 2×2 label example](../packages/quds_office_engine/example/macros/word_fixed_width_labels.bas)
combines array elements, a reusable function and calculated table selectors.
See the [exact String-editing contract](vba-macros-details.md#replacing-part-of-a-source-string)
for types, bounds, evaluation order, Unicode and budgets, and the
[local qualification](validation/word-vba-mid-assignment-20261122/README.md)
for the executed scope.

## Grouping labels into a table

The shared source operators `\` and `Mod` calculate row groups, column
positions and repeating formatting choices. For a zero-based source ordinal,
`ordinal \ 2 + 1` chooses a two-column row and `ordinal Mod 2 + 1` chooses its
column. The [complete grouped report](../packages/quds_office_engine/example/macros/word_grouped_report.bas)
combines arrays, Const/default expressions, named helpers, retained Range
aliases and direct cell suffixes in twelve native operations.

Run it with `compile-word-vba`, `validate-word-vba` or `run-word-vba` against an
existing supported 2×2 table. It uses source data; it does not enumerate or
read existing table text. See the [arithmetic contract](vba-macros-details.md#integer-division-and-remainder)
for rounding, signed remainder, overflow and explicit compatibility limits.

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
`ListFormat`, arbitrary subranges and document reads remain unsupported. Select
`Range.Paragraphs(1)` to style or shade the existing cell paragraph.
See the [exact cell-formatting contract](vba-word-macros-details.md#formatting-existing-table-cells)
and [local qualification](validation/word-vba-cell-formatting-20261122/README.md).

## Navigating table rows and columns

```vb
Sub Main()
    Dim report As Table, heading As Row, statusColumn As Column
    Dim selectedCells As Cells, status As Range
    Set report = ActiveDocument.Tables(Index:=1)
    Set heading = report.Rows.Item(Index:=1)
    heading.Cells(1).Range.Text = "Item"

    Set statusColumn = report.Columns(Index:=2)
    Set selectedCells = statusColumn.Cells
    Set status = selectedCells.Item(Index:=2).Range
    status.Text = "Ready"
    status.InsertAfter Text:=vbTab & "Reviewed"
    status.Font.ColorIndex = wdGreen

    report.Cell(Column:=1, Row:=2).Range.Text = "Quarterly report"
End Sub
```

`Rows`, `Row`, `Columns`, `Column` and `Cells` support typed aliases, nested
`With` and required `ByVal` helpers. A row's cell index chooses a column; a
column's cell index chooses a row. Captured selectors retain their original
table and coordinates when another variable is rebound.

`Tables`, `Rows`, `Columns` and their `Item` calls, plus row/column `Cells` and
`Cells.Item`, accept the required case-insensitive `Index:=` argument.
`Table.Cell` accepts required `Row:=` and `Column:=` in either named order.
Expressions evaluate once in their written order; positional arguments must
precede named arguments. Use `.Item(i)` when indexing a collection alias.

All writes reuse the existing guarded cell operations. The table must have a
supported unmerged grid, and the selected cell must contain one ordinary
paragraph. Collection counts, `First`/`Last`, enumeration, whole-row/column
ranges and document reads remain outside this increment. See the
[complete 10-operation BAS](../packages/quds_office_engine/example/macros/word_table_navigation.bas),
[exact selector contract](vba-word-macros-details.md#table-row-and-column-navigation)
and [local qualification](validation/word-vba-table-navigation-20261122/README.md).

## Appending to existing table text

```vb
Sub AppendStatus(ByVal target As Range, ByVal label As String)
    target.InsertAfter Text:=vbTab & label
End Sub

Sub Main()
    Dim target As Range
    Set target = ActiveDocument.Tables(1).Cell(1, 1).Range
    AppendStatus label:="Ready", target:=target
    Call target.InsertAfter(Text:=vbTab & "Reviewed")
    target.Font.Bold = True
End Sub
```

Direct `Cell.Range.InsertAfter` appends to the selected cell's current text.
The retained range includes the appended labels, so later Font writes include
them. Original text, distinct run formatting, table geometry and neighboring
cells remain intact. Empty cells can be filled this way, and repeated runs
append again. Bare, parenthesized, `Call`, case-insensitive `Text:=`, typed
aliases, nested `With` and named `ByVal` helpers are supported.

Appended text inherits the last existing text character's formatting. In an
empty cell it uses the last retained empty run, or retained paragraph-mark
formatting when there are no runs. Zero-width metadata remains preserved.
These are explicit native formatting rules; installed Word differential
qualification remains separate.

Use a direct cell Range for this operation. A projected
`Cell.Range.Paragraphs(1).Range`, body paragraph or header/footer paragraph has
a structural paragraph-mark boundary, and its `InsertAfter` remains refused.
The supported cell must still have one ordinary paragraph in an unmerged
main-story table. Tabs and valid Unicode are accepted; structural line breaks,
paragraph marks and invalid XML text are refused.

See the [complete BAS](../packages/quds_office_engine/example/macros/word_table_suffix.bas),
[exact append contract](vba-word-macros-details.md#appending-existing-cell-text),
[independent conformance cases](../packages/quds_office_engine/test/fixtures/vba_conformance/word_cell_suffix_v1.json)
and [local qualification](validation/word-vba-cell-suffix-20261122/README.md).

## Prefixing existing table text

```vb
Sub Main()
    Dim target As Range
    Set target = ActiveDocument.Tables(1).Cell(1, 1).Range
    target.InsertBefore Text:="Status" & vbTab
    target.Paragraphs(1).Range.InsertBefore Text:="Review" & vbTab
    target.Font.Bold = True
End Sub
```

Both prefixes become part of the retained cell range, so its later Font write
also includes the inserted labels. Existing text and distinct run formatting
survive the prefix operation; the inserted run inherits the supported formatting
at the beginning. The cell must still contain one ordinary paragraph in a
supported unmerged main-story table. An empty cell can be prefixed before
formatting its text. Repeating the macro prefixes the current text again.

`InsertBefore` accepts its required String by position or case-insensitive
`Text:=`, including parenthesized and `Call` forms. The named argument also
works on existing body and independent header/footer paragraph ranges. Typed
aliases, nested `With`, and named `ByVal` helpers preserve selected cell identity.

The shared source language includes the eight fixed VBA text constants,
including `vbTab` and `vbCrLf`. A macro can normalize source lines with
`Replace(label, vbCrLf, vbTab)` before inserting them. Tabs are supported in
native Word text; structural line/paragraph controls remain outside the
single-paragraph mutation contract.

See the [complete BAS](../packages/quds_office_engine/example/macros/word_table_prefix.bas),
[exact prefix contract](vba-word-macros-details.md#prefixing-existing-cell-text),
[portable constants](vba-macros-details.md#portable-text-constants), and
[local qualification](validation/word-vba-cell-prefix-20261122/README.md).

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

## Styling a table's paragraphs

```vb
Sub Main()
    Dim label As Paragraph
    Set label = ActiveDocument.Tables(1).Cell(1, 1).Range.Paragraphs(1)
    label.Style = "Report Label"
    With label.Shading
        .BackgroundPatternColor = RGB(31, 78, 121)
    End With
    label.Range.Font.ColorIndex = wdWhite
End Sub
```

The template must already contain the named paragraph style. The selected
paragraph also accepts supported built-in style constants, palette backgrounds
and explicit automatic shading. `Paragraph`, `Range` and `Shading` aliases,
nested `With`, and named `ByVal` helpers retain the selected cell. Style and
shading can target an empty ordinary paragraph; text formatting still requires
nonempty current text.

These operations change paragraph properties. They do not set cell fill or
table styles. Only the first and sole ordinary paragraph is supported;
multi-paragraph, merged and nested cells retain the existing admission guards.
Prefix insertion is supported through the selected paragraph Range; list
operations and live document reads remain unsupported through this selector. See the [exact contract](vba-word-macros-details.md#formatting-a-cell-paragraph),
[complete BAS example](../packages/quds_office_engine/example/macros/word_table_paragraphs.bas)
and [local qualification](validation/word-vba-cell-paragraphs-20261122/README.md).

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
