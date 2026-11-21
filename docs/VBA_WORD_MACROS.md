# Word VBA macros: the `vba-word` dialect

`OfficeVbaWordMacroLanguage` compiles an explicitly selected `.bas` module into
an immutable native Word operation plan. `OfficeMacroLanguages` installs the
adapter by default. Select language **`vba-word`** and format **`docx`**; the
separate `vba-excel` adapter and its spreadsheet contract remain available.

Compilation evaluates the supplied source without opening or reading a
document. The supported Word objects describe explicit paragraph and section
selectors. The ordinary native runtime resolves those selectors against a detached Word
document, applies the ordered operations, and publishes saved bytes only after
the complete plan succeeds. The same mutation permissions, tool allowlists,
step limits, cancellation, document admission, and save guards apply to native
JSON and compiled source plans.

This is a bounded Word source dialect. It does not execute embedded VBA projects,
launch Microsoft Word, or claim the complete Word object model.

## A first Word module

This module prefixes the first existing body paragraph and formats its current
text. If the paragraph is empty, insertion supplies text before font formatting.

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
        .Italic = False
        .Color = RGB(31, 78, 121)
    End With
    With target.ParagraphFormat
        .Alignment = wdAlignParagraphLeft
        .SpaceBefore = 0
        .SpaceAfter = 6
    End With
End Sub
```

`Document`, `Section`, `PageSetup`, `Paragraph`, `Range`, `Font`,
`ParagraphFormat`, `TabStops`, and `ListFormat` declarations support explicit
`Set` bindings and `ByVal` helper parameters. `With` may target these supported
objects or the range's `Font` and `ParagraphFormat`. All bindings remain
document-independent selectors; they never expose text or formatting reads.

`Document.Sections(i)` and `.Sections.Item(i)` select an existing section.
Its `PageSetup` supports the eight explicit geometry writes and the orientation
and section-start controls documented below.
Section geometry is independent of body paragraph selection; a section's
headers, footers and range are not exposed as source objects.

`Paragraph.Format` returns the same formatting selector as
`Paragraph.Range.ParagraphFormat`. A typed alias retains its selected paragraph
when the caller or a helper rebinds another variable. Rebinding a `ByVal`
parameter changes only that helper's local selector. Unbound objects, incompatible
object types, `New Font`, `New ParagraphFormat`, `Duplicate`, whole-object format
assignment, and property reads remain unsupported.

`ActiveDocument` and `Application.ActiveDocument` both bind the document
explicitly supplied to the macro session, as does `ThisDocument`. They do not
consult a focused native application, discover another document, or open a
file. `Paragraphs.Item(i)` is equivalent to `Paragraphs(i)`. `With Application`
and `With doc.Paragraphs` allow those same bindings; the collection has no
readable `Count` and cannot be enumerated.

The shared [argument contract](VBA_ARGUMENTS.md) supports named calls and
optional scalar ByVal parameters on declared module helpers. Required Word
object parameters may be passed by name; optional object parameters remain
unsupported. `TabStops.Add` and the supported `ListFormat` methods also accept
named optional arguments as described below. The measurement conversion
functions accept their one required argument by position or by its official
name; other Word members retain their positional-only contract.

The common source language includes the existing local procedures and scalar
functions, bounded control flow, typed arrays, string intrinsics, and explicit
Variant states and conversions described in [the shared language
contract](VBA_MACROS.md). Excel object members are unavailable in `vba-word`.
Word object members are unavailable in `vba-excel`.

## Exact native mapping

In the following paragraph table, `i` is a one-based paragraph index and `p`
is `i - 1`. These operations use the native default `body` story. The compiler
does not emit a header, footer, note, or comment story selector. Section page
geometry has its separate mapping below.

| Word source operation | Native operation | Arguments in addition to `paragraph: p` |
| --- | --- | --- |
| `range.InsertBefore text` | `docx.replaceText` | `start: 0`, `end: 0`, `text` |
| `range.Font.Bold = value` | `docx.runFormat` | `bold: value` |
| `range.Font.Italic = value` | `docx.runFormat` | `italic: value` |
| `range.Font.Size = value` | `docx.runFormat` | `size: value` in points |
| `range.Font.Name = value` | `docx.runFormat` | `font: value` |
| `range.Font.Color = value` | `docx.runFormat` | `color` as six uppercase RGB hexadecimal digits |
| `range.Font.Underline = value` | `docx.runFormat` | `underline`, one of the 18 documented `WdUnderline` styles |
| `range.Font.StrikeThrough = value` | `docx.runFormat` | `strike: value` |
| `range.Font.SmallCaps = value` | `docx.runFormat` | `smallCaps: value`; `True` also writes an explicit native AllCaps-off override |
| `range.Font.Superscript = value` | `docx.runFormat` | `superscript: value` |
| `range.Font.Subscript = value` | `docx.runFormat` | `subscript: value` |
| `range.HighlightColorIndex = value` | `docx.runFormat` | `highlight`: the fixed palette RGB color, or `null` for `wdNoHighlight` |
| `range.ParagraphFormat.Alignment = value` | `docx.paragraphFormat` | `alignment: left`, `center`, `right`, or `justify` |
| `range.ParagraphFormat.SpaceBefore = value` | `docx.paragraphFormat` | `before: value` in points |
| `range.ParagraphFormat.SpaceAfter = value` | `docx.paragraphFormat` | `after: value` in points |
| `range.ParagraphFormat.LeftIndent = value` | `docx.paragraphFormat` | `left: value` in points |
| `range.ParagraphFormat.RightIndent = value` | `docx.paragraphFormat` | `right: value` in points |
| `range.ParagraphFormat.FirstLineIndent = value` | `docx.paragraphFormat` | nonnegative `firstLine`/`hanging` in points, always clearing the opposite value |
| `range.ParagraphFormat.KeepTogether = value` | `docx.paragraphFormat` | `keepTogether: value` |
| `range.ParagraphFormat.PageBreakBefore = value` | `docx.paragraphFormat` | `pageBreakBefore: value` |
| `range.ParagraphFormat.ReadingOrder = value` | `docx.paragraphFormat` | `rtl: true` for RTL, `false` for LTR |
| `range.ParagraphFormat.LineSpacingRule = value` | `docx.paragraphFormat` | `lineSpacingRule: auto`, `lineSpacing: 1`, `1.5`, or `2` |
| Custom `LineSpacingRule` followed by `LineSpacing = points` | `docx.lineSpacing` | One paired edit with `rule: atLeast`, `exact`, or `multiple`, and `points` |
| `range.ParagraphFormat.Space1`, `.Space15`, `.Space2` | `docx.paragraphFormat` | The corresponding single, 1.5-line, or double-line preset |
| `paragraph.OpenUp` or `paragraph.Format.OpenUp` | `docx.paragraphSpaceBefore` | `action: open`; set before spacing to 12 points |
| `paragraph.CloseUp` or `paragraph.Format.CloseUp` | `docx.paragraphSpaceBefore` | `action: close`; set before spacing to zero |
| `paragraph.OpenOrCloseUp` or `paragraph.Format.OpenOrCloseUp` | `docx.paragraphSpaceBefore` | `action: toggle`; resolve current before spacing during native execution |
| `paragraph.TabStops.Add position, alignment, leader` | `docx.tabStop` | `position` in points, `alignment`, and `leader` |
| `paragraph.TabStops.ClearAll` | `docx.clearTabStops` | No additional arguments |
| `range.ListFormat.ApplyBulletDefault` | `docx.listDefault` | `numbered: false` |
| `range.ListFormat.ApplyNumberDefault` | `docx.listDefault` | `numbered: true` |
| `range.ListFormat.RemoveNumbers` | `docx.removeNumbers` | `numberType: all` or `paragraph` |
| `range.ListFormat.ApplyOutlineNumberDefault` | `docx.listOutlineDefault` | No additional arguments |
| `range.ListFormat.ListLevelNumber = n` | `docx.listLevel` | `level: n - 1`, for source levels `1..9` |
| `range.ListFormat.ListIndent` | `docx.listLevel` | `delta: 1` |
| `range.ListFormat.ListOutdent` | `docx.listLevel` | `delta: -1` |

For example, `ThisDocument.Paragraphs(2).Range.InsertBefore "Ready: "` emits:

```json
{
  "tool": "docx.replaceText",
  "arguments": {
    "paragraph": 1,
    "start": 0,
    "end": 0,
    "text": "Ready: "
  }
}
```

Each source write emits one native operation, in evaluation order, except the
explicit custom line-spacing pair described below, which emits one complete
rule/amount operation. Repeated
`InsertBefore` calls act on the paragraph as it exists at each step: inserting
`"A"` and then `"B"` before `"tail"` produces `"BAtail"`. A later font operation
formats the paragraph's current text, including text inserted by earlier steps.

### Section page setup

`ThisDocument.Sections(i).PageSetup`,
`ActiveDocument.Sections.Item(i).PageSetup`, and the corresponding
`Application.ActiveDocument` form select page geometry for one explicit
section. `Section` and `PageSetup` support typed aliases, required `ByVal`
parameters, named helper arguments, and nested `With` blocks. `With` also
supports the intermediate `Sections` collection. Rebinding a section variable
does not retarget a previously bound `PageSetup`; rebinding a helper parameter
affects only that helper's local selector. Both type names may also be used as
local variable names.

The index is an actual numeric value that is an exact integer in
`1..9007199254740991`, following the shared bounded source integer contract.
Compilation converts it to a zero-based native section index. Native execution
checks that the section exists in the supplied document; there is no fallback
to the first section. Section order follows the Quds document model, and the
operation refuses markup-compatibility alternatives that could change section
identity or geometry. Compilation does not inspect the document or its section
count. `Sections(i)` and `.Item(i)` accept one positional index; named arguments
remain available on declared helpers rather than on these selectors.

Each assignment emits one `docx.pageSetup` operation with required `section`,
`property`, and `points` arguments. It updates the following native attribute:

| Word property | Native `property` | Native XML attribute |
| --- | --- | --- |
| `PageWidth` | `width` | `w:pgSz/@w:w` |
| `PageHeight` | `height` | `w:pgSz/@w:h` |
| `TopMargin` | `top` | `w:pgMar/@w:top` |
| `BottomMargin` | `bottom` | `w:pgMar/@w:bottom` |
| `LeftMargin` | `left` | `w:pgMar/@w:left` |
| `RightMargin` | `right` | `w:pgMar/@w:right` |
| `HeaderDistance` | `header` | `w:pgMar/@w:header` |
| `FooterDistance` | `footer` | `w:pgMar/@w:footer` |

All eight values are in points. They require actual finite numbers in exact
`0.05`-point increments, with at most `2147483647` native twips
(`107374182.35` points). Page dimensions must be at least one point; margins
and header/footer distances must be nonnegative. These are the dialect's
explicit numeric bounds. The implementation retains bounded Double arithmetic
and does not emulate VBA `Single` rounding, printer-dependent limits, or
implicit String/Boolean conversions. The existing physical measurement
functions can supply values when their results satisfy this exact native grid.

This example addresses the first existing section and uses a typed helper:

```vb
Sub SetReportMargins(ByVal page As PageSetup)
    With page
        .TopMargin = InchesToPoints(1)
        .BottomMargin = InchesToPoints(0.75)
        .LeftMargin = PicasToPoints(4.5)
        .RightMargin = PicasToPoints(4.5)
        .HeaderDistance = MillimetersToPoints(12.7)
        .FooterDistance = CentimetersToPoints(1.27)
    End With
End Sub

Sub Main()
    Dim section As Section
    Dim page As PageSetup
    Set section = ActiveDocument.Sections.Item(1)
    Set page = section.PageSetup
    SetReportMargins page:=page
    page.PageWidth = InchesToPoints(9)
    page.PageHeight = InchesToPoints(12)
End Sub
```

The complete [page-setup example](../packages/quds_office_engine/example/macros/word_page_setup.bas)
also selects a second existing section and demonstrates a `Section` helper.
Run it through the existing `compile-word-vba`, `validate-word-vba`, or
`run-word-vba` commands with a template containing the required sections.
For example, the first section's left-margin assignment above compiles to:

```json
{
  "tool": "docx.pageSetup",
  "arguments": { "section": 0, "property": "left", "points": 54 }
}
```

Native execution validates the geometry after **each** assignment, using the
current detached section after earlier plan operations. Margins must leave a
positive page body, and the existing uniform columns and gaps must leave
positive text width. Reduce margins before shrinking a page when the old
margins would make an intermediate step invalid. A failure leaves the entire
run unpublished, including earlier successful paragraph or page edits.
The ordinary policy allowlist, recording, source work/operation limits,
detached validation and atomic publication rules apply. A pending custom
paragraph `LineSpacingRule`/`LineSpacing` pair must be completed before a page
geometry write.

The operation owns only the selected native measurement. Unedited sparse
attributes, namespace aliases, extension metadata, unrelated section settings,
document content and opaque DOCM project parts are retained. Missing native
geometry groups are created from the current modeled values. A width or height
assignment also clears native `w:pgSz/@w:code`, including for a same-value
assignment, matching Word's custom-paper side effect; a foreign attribute
named `code` is preserved. The existing source orientation remains unchanged.
If an earlier general native `docx.sectionFormat` dimension edit is pending,
its normal orientation behavior is retained before the sparse measurement
write is applied. The separate orientation setter is described below.

The guarded source subset refuses negative, malformed or universal-unit
native measurements, nonzero gutters, duplicate native geometry/column
elements or attributes, custom/unequal columns, alternate section
properties, and `mc:ProcessContent` section/settings markup. Enabled
mirrored-margin, top-gutter or book-fold settings are also
refused, including those inside retained markup-compatibility branches;
explicit native `0`, `false`, and `off` settings are allowed. Existing source
can still be preserved as input without qualifying it for these edits.

This slice does not provide `Document.PageSetup`, `Sections.PageSetup`,
`Range.PageSetup`, `Selection`, property reads, `Sections.Count`, collection
iteration, `First`/`Last`, section creation, `Section.Range`, header/footer
objects, `PaperSize`, `Gutter`, columns, or header/footer mode
setters in VBA. Geometry changes do not edit header/footer content. Unused
helpers and inactive branches are checked for unsupported members and types.

The [local qualification record](validation/word-vba-paragraph-pagination-20261121/README.md)
records the exact source and executed checks. No installed Microsoft Word or
Flutter editor validation is claimed by this source/native geometry slice.

### Section orientation and start controls

The same explicit `Section.PageSetup` selectors now accept `Orientation`,
`SectionStart`, and the zero-argument `TogglePortrait` method. Typed `PageSetup`
aliases, required `ByVal` helper parameters, named helper arguments, and nested
`With` keep their existing selector identity. These properties remain
write-only in source; the native runtime resolves a toggle against the selected
detached section after earlier operations in the same run.

| VBA member/value | Native operation | Required arguments besides zero-based `section` |
| --- | --- | --- |
| `.Orientation = wdOrientPortrait` (`0`) | `docx.pageOrientation` | `orientation: portrait` |
| `.Orientation = wdOrientLandscape` (`1`) | `docx.pageOrientation` | `orientation: landscape` |
| `.TogglePortrait` | `docx.pageOrientation` | `orientation: toggle` |
| `.SectionStart = wdSectionContinuous` (`0`) | `docx.sectionStart` | `kind: continuous` |
| `.SectionStart = wdSectionNewPage` (`2`) | `docx.sectionStart` | `kind: nextPage` |
| `.SectionStart = wdSectionEvenPage` (`3`) | `docx.sectionStart` | `kind: evenPage` |
| `.SectionStart = wdSectionOddPage` (`4`) | `docx.sectionStart` | `kind: oddPage` |

The constants retain Microsoft's numeric values. `wdSectionNewColumn` (`1`)
is recognized but refused because the native section model does not implement
that start mode. Enum assignments require actual exact integers; Strings,
Booleans, Empty, Null, fractions and other enum values are refused. The method
accepts the bare, empty-parentheses, `Call`, and `Call ...()` statement forms,
with no arguments or return value. A new-column value in an evaluated setter
produces a source diagnostic and no partial plan. Unsupported member access,
wrong receivers and argument shapes are also checked in inactive branches and
unused helpers.

```vb
Sub Main()
    With ActiveDocument.Sections(2).PageSetup
        .Orientation = wdOrientLandscape
        .SectionStart = wdSectionOddPage
        Call .TogglePortrait()
    End With
End Sub
```

This writes landscape, selects an odd-page start for the second section, then
returns that section to portrait. Each statement emits one operation, including
repeated same-value assignments and toggles. Recording stores the toggle action,
so replay resolves the orientation of its supplied document. The complete
[word_sections.bas example](../packages/quds_office_engine/example/macros/word_sections.bas)
configures two existing sections through typed aliases and a named helper.

**Orientation contract.** Existing dimensions are resolved at the ordinary
serializer's integer-twip (0.05-point) precision, including authored defaults
and custom model values. Changing orientation swaps that width and height
once. Assigning the current orientation retains those dimensions. Named
top/bottom/left/right margins, header/footer distances and uniform column
settings retain their values; the resulting page body and column text width
must still be positive. The native printer paper code is preserved. This is
distinct from explicit `PageWidth` / `PageHeight` writes, which select custom
paper. An explicit portrait or landscape attribute is stored even for square
pages and same-value assignments, and is retained through subsequent edits,
serialization and reopening.

For imported source, `w:pgSz/@w:orient` determines the current orientation,
with absent orientation meaning portrait. Unrecognized orientation values or
non-square dimensions inconsistent with that state are refused. Authored
sections without source use their canonical dimensions to establish the initial
state. A preceding general native `docx.sectionFormat` dimension change retains
the established serializer behavior before the new orientation operation;
near-square pending geometry is refused when the general serializer's
orientation tolerance would disagree with the canonical dimensions.
Existing page-geometry, unsupported gutter/column/settings, namespace and
section-identity guards continue to apply. All checks complete before changing
the live model, and failure discards the complete detached macro run.

The dimension-swap and unchanged-margin rules above are the explicit Quds
contract. The Microsoft VBA references establish the members and enum values;
this increment has no installed Microsoft Word differential observations and
does not claim printer-dependent layout parity.

**Section-start contract.** The start belongs to the beginning of the selected
section. Continuous starts reuse the current page when the existing layout
allows it; next-page, even-page and odd-page starts use the native pagination
rules. The operation updates only `w:type/@w:val` and its modeled break kind.
Same-value writes still own that attribute, including when imported unsupported
source previously fell back to a modeled kind. Other section properties,
geometry, namespace extensions and recorded `sectPrChange` history survive.
Duplicate native type/value entries and ambiguous section identity are refused.
No unrelated page-geometry restriction is imposed by a section-start write.

Both operations require an explicit valid section index, use normal mutation
permissions/allowlists and resource limits, and preserve opaque DOCM VBA parts.
They do not create sections, broadcast over a collection, expose property
reads, open another document, or execute embedded VBA projects. A pending
custom paragraph line-spacing pair must complete before either operation.

The [local section-controls qualification](validation/word-vba-sections-20261121/README.md)
records the source snapshots, native/source/integration checks and VM/JavaScript
example results, separately from the unexecuted Office and Flutter hosts.

### Opening, closing and toggling paragraph spacing

`Paragraph` and `ParagraphFormat` support the zero-argument `OpenUp`, `CloseUp`
and `OpenOrCloseUp` methods. `Paragraph.Format` and
`Paragraph.Range.ParagraphFormat` address the same selected paragraph. Bare
statements, parenthesized statements, `Call target.OpenUp` and
`Call target.OpenUp()` are supported, along with typed aliases, required `ByVal`
helpers, named helper arguments and nested `With` blocks. The receiver is
evaluated once. Collection-wide calls, direct `Range.OpenUp`, assigned return
values, arguments and method reads are rejected, including in unused helpers
and dead branches. The existing source work and operation limits still apply.

```vb
Sub Main()
    Dim first As Paragraph
    Dim format As ParagraphFormat
    Set first = ActiveDocument.Paragraphs(1)
    Set format = first.Format

    first.CloseUp
    With format
        .OpenOrCloseUp
        Call .OpenOrCloseUp()
        .OpenUp
    End With
End Sub
```

This example finishes with 12 points of spacing before the first existing
paragraph. `OpenUp` always sets 12 points; `CloseUp` sets zero. `OpenOrCloseUp`
sets 12 points when the current spacing is zero, and zero when it is positive.
The compiler emits the action rather than a guessed resulting value. Native
execution resolves the current effective paragraph properties, including
supported style inheritance and earlier operations in the same detached
transaction. Two consecutive toggles both execute. Recording retains the
toggle action, so replay resolves the spacing of the replay target. This does
not expose document values to VBA expressions or add live property reads.

Each method emits one `docx.paragraphSpaceBefore` operation with a zero-based
`paragraph` and an exact `action` of `open`, `close` or `toggle`. A pending
custom `LineSpacingRule` / `LineSpacing` pair must be completed before these
methods, just as before any other document write. Body paragraph traversal,
policy/allowlist checks, step limits, detached validation and all-or-nothing
publication are unchanged. Empty paragraphs are supported without inserting
text or changing paragraph structure.

The edit owns only the native before-spacing group. Same-value writes become
direct formatting; unedited after-spacing and line-spacing values continue to
inherit and respond to later style edits. Unrelated direct properties, native
style definitions, foreign attributes/children and opaque DOCM project/signature
parts are preserved. An existing disabled `beforeAutospacing` attribute in the
edited direct group can be removed; unedited groups retain their source data.
Native style identities and `basedOn` links are resolved by namespace rather
than prefix spelling, and default paragraph styles accept native `1`, `true`
and `on` flags. An omitted native style type means `paragraph`; foreign type
attributes do not override that default. Foreign style/attribute lookalikes
remain source data.

The supported input is nonnegative point spacing represented by exact integer
twips in `0..2147483647`. The controls refuse native `beforeLines`, enabled or
unknown `beforeAutospacing`, malformed/negative/noninteger/oversized native
`before`, duplicate spacing or paragraph-property packets, spacing-bearing
markup-compatibility alternatives, and unbalanced modeled field boundaries.
They also refuse before-spacing declarations in numbering levels or unmodeled
conditional table-style regions, and ambiguous style identities, duplicate
defaults, unknown style types, missing `basedOn` targets, cyclic inheritance,
cross-type `basedOn` links or numbering-style `basedOn` links. Paragraph/table
style selectors must resolve to native styles of the expected type; missing,
foreign, nested, duplicate or ambiguously attributed selectors are refused.
These checks
scan stored Word XML parts conservatively, so a conflicting declaration in an
unrelated style or story can cause refusal. They do not guess automatic spacing,
silently round native values, or choose an ambiguous style.

Supported table-style inheritance remains Quds's existing `wholeTable`, enabled
horizontal bands and `firstRow` projection. The controls do not introduce
complete conditional table-style parity. They follow the existing body selector
contract and do not add arbitrary ranges, collections, `Selection`, COM or
embedded VBA execution.

The actual [word_paragraph_controls.bas](../packages/quds_office_engine/example/macros/word_paragraph_controls.bas)
example requires three existing body paragraphs. Its ten operations finish at
12, zero and 12 points and can run again on its own saved output. The
[qualification record](validation/word-vba-paragraph-controls-20261120/README.md)
also covers the incoming custom line-spacing continuation.

### Custom paragraph tab stops

`Paragraph.TabStops`, `Paragraph.Format.TabStops`, and
`Paragraph.Range.ParagraphFormat.TabStops` select one paragraph's custom stops.
They support `Dim stops As TabStops`, `Set`, nested `With`, and required `ByVal`
helper parameters. Aliases retain their selected paragraph when another alias
or a helper parameter is rebound. Empty paragraphs are valid targets.

```vb
Sub Main()
    Dim stops As TabStops
    Set stops = ActiveDocument.Paragraphs(1).TabStops
    With stops
        .ClearAll
        .Add Position:=72
        .Add Leader:=wdTabLeaderDots, Position:=432, Alignment:=wdAlignTabRight
        .Add 216, , wdTabLeaderDashes
    End With
End Sub
```

`Add(Position, Alignment, Leader)` requires `Position`; its optional arguments
default to `wdAlignTabLeft` and `wdTabLeaderSpaces`. Bare statements,
parenthesized statements and `Call stops.Add(...)` are accepted. Argument names
are case-insensitive. Positional arguments and comma holes must precede named
arguments. A hole skips only an optional position; it cannot replace the
required `Position`. Unknown names, duplicate bindings, and extra arguments
are rejected before evaluation, including in unused helpers and dead branches.
The receiver is resolved first; supplied expressions then execute exactly once
in their written order, even if named arguments use a different parameter order.

| Argument | Supported values |
| --- | --- |
| `Position` | Actual finite numeric points from `-1584` through `1584`, in exact `0.05`-point increments; zero and negative positions are allowed |
| `Alignment` | `wdAlignTabLeft = 0`, `wdAlignTabCenter = 1`, `wdAlignTabRight = 2`, `wdAlignTabDecimal = 3` |
| `Leader` | `wdTabLeaderSpaces = 0`, `wdTabLeaderDots = 1`, `wdTabLeaderDashes = 2`, `wdTabLeaderLines = 3`; native `none`, `dot`, `hyphen`, `underscore` |

Positions are relative to the left margin. This exact-twip contract avoids
silent rounding and stays within Word's documented signed 31,680-twip native
position bound. It does not emulate VBA `Single` coercion. Strings, Booleans,
Empty, Null, and an unhandled omitted Variant are not numeric arguments. Bar
and list alignment and heavy/middle-dot leaders are recognized enum constants
but refused as new writes because their rendering is outside this slice.

`Add` changes the stop at one position, preserving other direct and inherited
stops. An explicit same-value write still becomes direct formatting. Unedited
inherited stops continue to follow later style edits. Existing source records
for bar/start/end/numbering tabs and unmodeled leaders remain native source;
preserving them does not add their missing live rendering behavior.

`ClearAll`, `ClearAll()`, `Call stops.ClearAll`, and `Call stops.ClearAll()`
accept no arguments. They clear the currently effective **explicit native
custom-tab definitions** resolved by Quds, including those inherited from
document defaults, supported table-style layers and paragraph styles. Position-specific native `clear`
records keep those stops suppressed after style refresh and repeated save/reopen.
Document default-tab interval settings and paragraph indentation are preserved;
implicit hanging-indent behavior is not redefined. New custom positions added
to a style after the operation are not preemptively suppressed.

Table-style inheritance follows the existing Quds resolver: `wholeTable`,
enabled horizontal bands (`band1Horz` / `band2Horz`), and enabled `firstRow`.
It does not evaluate first/last-column, last-row, corner or vertical-band
conditional regions. Native tab definitions in those unmodeled regions remain
preserved; `ClearAll` does not promise to suppress them. This increment does
not add complete conditional table-style parity.

Both operations retain unrelated native properties, extension attributes and
children, foreign namespace lookalikes, and opaque macro-project parts through
the ordinary detached transaction. Ambiguous source is refused before mutation:
duplicate native tab containers or positions in one layer, missing/noninteger
or out-of-signed-32-bit source positions, unknown native alignment values, and
misbound native property namespaces. Tab-bearing markup-compatibility alternatives
anywhere in the stored Word XML parts cause a conservative document-level
refusal, including alternatives wrapped around an entire style or paragraph
property block. The adapter does not infer which hidden tab branch Word would edit.
The existing native `paragraphFormat.tabs` operation retains replacement of the
whole effective collection resolved by Quds, including inherited stops, under
the corrected position-wise style cascade and the same table-layer limits.

This slice supports statements whose `Add` return value is discarded. It does
not introduce `TabStop` objects, indexing, `Count`, enumeration, collection-copy
assignment, default-tab setters, `Selection` or live document reads. Supported
measurement conversions are documented separately below. The actual [word_tabstops.bas](../packages/quds_office_engine/example/macros/word_tabstops.bas)
example requires three existing body paragraphs and is exercised on the Dart VM
and compiled JavaScript by the portable regression driver. See the
[qualification record](validation/word-vba-tabstops-20261120/README.md) for executed
results and remaining host boundaries.

Primary contracts: Microsoft's [TabStops.Add](https://learn.microsoft.com/en-us/office/vba/api/word.tabstops.add),
[TabStops.ClearAll](https://learn.microsoft.com/en-us/office/vba/api/word.tabstops.clearall),
[WdTabAlignment](https://learn.microsoft.com/en-us/office/vba/api/word.wdtabalignment),
[WdTabLeader](https://learn.microsoft.com/en-us/office/vba/api/word.wdtableader), and
[native tab-position bounds](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/bca28b4c-9ef6-4eb4-b749-f5ea55b22dc4).

### Paragraph list formatting

`Paragraph.Range.ListFormat` selects one existing body paragraph's list
formatting. It supports `Dim format As ListFormat`, `Set` aliases, nested `With`,
and required `ByVal` helper parameters. Rebinding an alias or a helper parameter
does not rebind other aliases. Empty paragraphs are valid targets.

```vb
Sub MakeNumbered(ByVal target As ListFormat)
    target.RemoveNumbers NumberType:=wdNumberParagraph
    target.ApplyNumberDefault DefaultListBehavior:=wdWord8ListBehavior
End Sub

Sub Main()
    Dim format As ListFormat
    Set format = ActiveDocument.Paragraphs(1).Range.ListFormat
    MakeNumbered target:=format
    With ActiveDocument.Paragraphs(2).Range.ListFormat
        .RemoveNumbers wdNumberParagraph
        .ApplyBulletDefault
    End With
End Sub
```

The three methods accept bare statements, parenthesized statements, and `Call`
forms, including zero-argument `Call format.ApplyBulletDefault`. Each has at most
one optional numeric argument. Argument names are case-insensitive; unknown
names and excess/duplicate bindings are refused during checking, including in
dead branches and unused helpers. The receiver is evaluated before its supplied
argument, and each expression executes exactly once. Numeric strings, Booleans,
Empty, Null, fractions, and unhandled missing Variants are not enum values.

| Method | Optional argument | Accepted values |
| --- | --- | --- |
| `ApplyBulletDefault` | `DefaultListBehavior` | Omitted or `wdWord8ListBehavior = 0` |
| `ApplyNumberDefault` | `DefaultListBehavior` | Omitted or `wdWord8ListBehavior = 0` |
| `RemoveNumbers` | `NumberType` | Omitted / `wdNumberAllNumbers = 3`, or `wdNumberParagraph = 1` |

The apply methods are **toggles**. At native execution time, a paragraph already
using the requested bullet/number kind loses its paragraph numbering. Otherwise,
the operation applies a deterministic Quds single-level default at level zero.
Each step sees earlier operations in the same plan. The compiler never guesses
the input document's list state. Explicitly removing paragraph numbering before
applying a default, as above, makes the result independent of its previous kind.

New defaults use a native bullet or decimal scheme with a left indent of 18
points, a hanging indent of 9 points and no first-line indent. They preserve the
right indent and unrelated paragraph/run content. Imported numbering definitions
are retained, new IDs avoid collisions, and only a validated Quds default scheme
is reused. ID allocation reserves references in all live stories and stored Word
XML, including unused/opaque source parts. A matching Quds marker with additional
native semantics is refused instead of reusing a different scheme. A matching
toggle or `RemoveNumbers` writes an explicit native
numbering suppression, which survives style refresh and save/reopen, while
retaining paragraph indentation. These defaults are Quds's defined host behavior;
the adapter does not reproduce a user's customized Word list gallery or Word's
complete indentation-reset behavior. `wdWord9ListBehavior = 1` and
`wdWord10ListBehavior = 2` are recognized but refused because their distinct
layout algorithms are not implemented.

Classification uses native numbering IDs, abstract definitions, and the selected
level/override, rather than visible labels or an assumption that ID 1 is a bullet.
Supported numeric formats are `decimal`, `decimalZero`, `upperRoman`, `lowerRoman`,
`upperLetter`, `lowerLetter`, `ordinal`, `cardinalText`, `ordinalText`, `hex`, and
`chicago`, with exactly one `%1` through `%9` placeholder in the selected level's
label. Native `bullet` selects the bullet kind regardless of its glyph. Missing
or ambiguous native identities and unsupported linked/picture/outline numbering
are refused by the apply methods. A selected level override must supply a complete
supported level; partial-override fallback is not introduced here. Duplicate
numbering properties, partial `numPr` without an explicit ID, foreign/misbound numbering
lookalikes, tracked numbering, and numbering-bearing markup-compatibility alternatives are refused
before mutation. Some source guards conservatively apply across the document,
including its styles and alternative XML branches. `RemoveNumbers` does not
classify the list kind and can suppress existing outline numbering. Inheritance
follows the existing Quds paragraph/default and
supported table-style layers; this does not add other conditional table regions.

`RemoveNumbers NumberType:=wdNumberParagraph` removes paragraph numbering while
preserving supported field instructions/results. All list operations refuse
before mutation if the live document contains field boundaries that the serializer
would discard as unbalanced, including in another story or where an opaque block
hides a field's opening or closing boundary. This guard prevents a list edit from
silently losing unrelated field markers during serialization; it does not repair
the field source. The omitted or explicit `wdNumberAllNumbers`
form additionally checks for `LISTNUM` fields and refuses if it cannot fulfill
the requested removal without editing such fields. This includes split complex
field instructions and fields spanning the selected paragraph. It never silently
leaves a selected `LISTNUM` field behind while reporting an all-numbers removal.
All-number removal also conservatively refuses any field-bearing alternative
XML branch anywhere in stored Word parts, field-bearing opaque body blocks or
inlines even outside the selected paragraph. Opaque content can hide a field
boundary that overlaps the target paragraph. Paragraph-only removal can preserve
fully opaque field packets when no modeled boundaries would be discarded; it
does not infer or modify their instructions.
`wdNumberListNum = 2` is recognized but refused at compilation. The source adapter
does not expose live list reads, list templates/galleries or a document-wide list
collection. Outline application and list-level writes are described below.

The executable [word_lists.bas](../packages/quds_office_engine/example/macros/word_lists.bas)
uses aliases, helpers, `With`, named arguments and `Call`. The
[validation record](validation/word-vba-lists-20261120/README.md) identifies the
executed source and tests. Native `docx.listDefault` and `docx.removeNumbers`
retain ordinary mutation permissions, admission, resource limits and detached
transaction publication; opaque VBA project bytes remain inert and preserved.

Primary contracts: Microsoft's [ListFormat](https://learn.microsoft.com/en-us/office/vba/api/word.listformat),
[ApplyBulletDefault](https://learn.microsoft.com/en-us/office/vba/api/word.listformat.applybulletdefault),
[ApplyNumberDefault](https://learn.microsoft.com/en-us/office/vba/api/word.listformat.applynumberdefault),
[RemoveNumbers](https://learn.microsoft.com/en-us/office/vba/api/word.listformat.removenumbers),
[WdDefaultListBehavior](https://learn.microsoft.com/en-us/office/vba/api/word.wddefaultlistbehavior),
and [WdNumberType](https://learn.microsoft.com/en-us/office/vba/api/word.wdnumbertype).

### Outline numbering and list levels

The same paragraph `ListFormat` selector supports `ApplyOutlineNumberDefault`,
write-only `ListLevelNumber`, and the zero-argument `ListIndent` and `ListOutdent`
methods. Typed aliases, required `ByVal` helpers and nested `With` retain their
existing selector semantics. This allows macros to build a hierarchy without
reading the live document:

```vb
Sub Main()
    Dim target As ListFormat
    Set target = ActiveDocument.Paragraphs(1).Range.ListFormat
    With target
        .RemoveNumbers NumberType:=wdNumberParagraph
        .ApplyOutlineNumberDefault DefaultListBehavior:=wdWord8ListBehavior
        .ListLevelNumber = 2
        .ListIndent
        Call .ListOutdent()
    End With
End Sub
```

This example finishes at source level 2. `ListLevelNumber` accepts an actual
numeric exact integer from 1 through 9; it does not round or coerce strings,
Booleans, Empty, Null, or omitted Variants. It maps to native DOCX levels 0
through 8. A numeric Variant is accepted when its value meets the same bounds.
The property is write-only in this source adapter; expressions such as
`depth = target.ListLevelNumber` remain unsupported. Parenthesized property
invocation, `Set` assignment and default-object coercions are also refused.

`ListIndent`, `ListIndent()`, `Call target.ListIndent` and
`Call target.ListIndent()` all increase the selected paragraph's list level by
one; the equivalent `ListOutdent` forms decrease it by one. No positional,
named or omitted arguments are accepted. Invalid call shapes are checked even
in unused helpers and dead branches. The native operation resolves the current
level at execution time, so earlier list operations in the plan are visible.
It refuses a paragraph without numbering, a missing target level, indent above
level 9, or outdent below level 1. It does not clamp or invent another list.
An unresolved pending native list restart is also refused.

`ApplyOutlineNumberDefault` accepts the same statement/`Call` forms and optional
`DefaultListBehavior` argument as the other default-list methods: omitted or
`wdWord8ListBehavior = 0` only. It toggles a supported existing outline off;
otherwise it applies a separately named, nine-level Quds decimal outline at
source level 1. As with the single-level methods, explicit paragraph-number
removal before applying makes the outcome independent of the previous list
kind. Toggling off writes persistent numbering suppression and retains the
paragraph's indentation and style, including heading styles.

For the outline toggle, imported templates must explicitly declare native
`multilevel` or `hybridMultilevel` and contain at least two complete supported
numeric levels. All defined levels and overrides must pass validation. Mixed
bullet/numeric templates, ambiguous metadata and multilevel templates without
the type declaration are refused. A `singleLevel` declaration is classified as
non-outline for this bounded toggle. This metadata does not restrict explicit
level changes: `ListLevelNumber` can still select any actually defined,
supported level even when the template's UI metadata says `singleLevel`.

The Quds outline uses a left indent of `18 * level` points and a 9-point hanging
indent. Its first label template is `%1.`; deeper levels combine their ancestor
counters, such as `%1.%2.` and `%1.%2.%3.`. Definitions are allocated without
colliding with imported numbering or references in stored Word parts. Reuse
requires the entire expected native scheme, not just a matching marker name.
Existing single-level bullet and number defaults retain their own definitions
and behavior; attempting to indent one into an undefined level is refused.

Level changes preserve the current numbering instance, imported definitions
and unrelated numbering metadata. They do not rewrite the numbering part.
The ordinary serializer can still normalize XML or add its existing fallback
definitions; complete input-part byte identity is not a general guarantee.
They resolve the actual target definition and complete level overrides, then
apply its supported indentation while retaining the paragraph's right indent,
style, other formatting and foreign metadata. They do not infer list kind from
visible labels or special numbering IDs. The new level operations support
native bullets and the six numeric formats rendered by the current label
resolver: `decimal`, `decimalZero`, `upperRoman`, `lowerRoman`, `upperLetter`, and
`lowerLetter`. This does not expand the separate legacy simple-default
classification contract above.

The new geometry writes retain right-indent inheritance when that value was
not directly edited; a later style update can still change it. A deliberate
earlier native right-indent write keeps its direct ownership, including a
same-value write. Effective indentation now resolves native attributes using
their namespace rather than their prefix spelling. This also corrects plain
import and save/reopen of alternate-prefix indentation. Original paragraph and
style XML retains extension metadata, and foreign `ind` lookalikes stay opaque.

Each selected numeric level requires its own counter placeholder and may
reference each existing ancestor counter once. Forward, repeated or unresolved
references are refused. Levels must provide `start`, `numFmt` and `lvlText`,
use left label alignment, and omit linked paragraph styles, legal-numbering,
explicit level restart rules (`lvlRestart`), legacy or picture-bullet
instructions. A complete level override and a valid positive `startOverride`
can be preserved; partial level
replacement is not inferred. Level changes invalidate the native model's
derived label cache; normal save/reopen recomputes labels from the unchanged
numbering definitions and story counters.

Imported level geometry must be unambiguous native twip-based indentation with
an explicit `left` value and optional `hanging` or `firstLine`. Logical or
character-based indentation, unsupported native level paragraph formatting,
linked or picture numbering, and incomplete or ambiguous definitions are
refused before mutation. The existing list guards for source namespaces,
tracked numbering, alternatives and serializer-sensitive field boundaries
also apply. Unsupported sources can be preserved as input without implying
that every possible edit to them is supported.

Because Word can give inherited character-based or logical indentation
precedence over a new point value, new outline application and level geometry
writes conservatively refuse those attributes anywhere in stored native
styles, document defaults or table-style regions. Positive target first-line
indentation also refuses a native hanging attribute on that level, even when
zero, or hanging indentation in stored styles. These guards avoid publishing
geometry that only the Quds model would interpret as requested. A supported
positive first-line target is written without a hanging attribute.

Method receivers are captured before their optional argument expressions.
`ListLevelNumber` retains the adapter's existing scalar-property assignment
order: evaluate the right-hand value, then the target selector, each exactly
once, before emitting the write. A previously bound alias or `With` selector
remains stable. This is an explicit source-adapter contract, not a claim that
every host or COM evaluation detail is reproduced.

The executable [word_list_levels.bas](../packages/quds_office_engine/example/macros/word_list_levels.bas)
demonstrates outline creation, explicit levels, relative level changes,
aliases, helpers and `Call`. Native `docx.listOutlineDefault` and `docx.listLevel`
use ordinary mutation permissions, tool allowlists, step limits and detached
publication. Validation does not publish; a later failure rolls back the whole
plan and its recording. Opaque VBA projects remain inert. The
[qualification record](validation/word-vba-list-levels-20261120/README.md)
records the exact executed source and local checks.

Primary contracts: Microsoft's
[ApplyOutlineNumberDefault](https://learn.microsoft.com/en-us/office/vba/api/word.listformat.applyoutlinenumberdefault),
[ListLevelNumber](https://learn.microsoft.com/en-us/office/vba/api/word.listformat.listlevelnumber),
[ListIndent](https://learn.microsoft.com/en-us/office/vba/api/word.listformat.listindent),
[ListOutdent](https://learn.microsoft.com/en-us/office/vba/api/word.listformat.listoutdent),
and [ListLevel](https://learn.microsoft.com/en-us/office/vba/api/word.listlevel).

### Paragraph selectors

`ThisDocument.Paragraphs(i)` and `.Paragraphs.Item(i)` require an actual numeric value that is an exact
integer from `1` through `9007199254740991`. Numeric strings and Booleans are
not implicitly converted. Whether that paragraph exists is checked when the
native plan runs; compilation does not inspect the document.

Indexes follow **Quds's native body paragraph order**, also used by document
inspection. The engine visits sections in order and traverses their body
blocks depth first. It includes paragraphs inside content-control containers,
frames, and nested tables; table rows and cells are visited in stored order.
A modeled table of contents contributes its title and result paragraphs.
Headers, footers, footnotes, endnotes, and comments are excluded. This explicit
native traversal is not a claim that every complex document has the same
paragraph numbering in Microsoft Word.

This slice does not add, delete, split, or merge paragraphs. The required
paragraphs must already exist in the input template. Because the supported
operations do not alter body structure, their selectors remain stable through
the plan.

### Text and paragraph-mark boundaries

`InsertBefore` accepts one actual String, including an empty String. Bare and
parenthesized forms and `Call range.InsertBefore("text")` are supported. Text
must contain well-formed UTF-16 and XML 1.0 characters. Tabs are allowed;
carriage returns and line feeds are refused because structural paragraph and
line-break insertion is outside this slice. Other XML-invalid controls,
unpaired surrogates, and BMP `U+FFFE`/`U+FFFF` are refused before a native plan
is returned. Valid supplementary characters remain intact.

Microsoft's paragraph range includes its ending paragraph mark. Its
[InsertAfter documentation](https://learn.microsoft.com/en-us/office/vba/api/word.range.insertafter)
explains how that affects insertion into the next paragraph. Quds's native
`replaceText` addresses paragraph **content**, so this dialect deliberately
exposes only insertion at the beginning. `Range.Text`, `InsertAfter`, range
endpoints, and structural characters are unsupported instead of being lowered
to a different paragraph-mark behavior.

Font operations likewise affect the paragraph's current **text**, without
formatting its paragraph mark. Native `runFormat` rejects an empty text range.
Insert text before applying font properties to an empty template paragraph.
Paragraph-format operations can target an empty paragraph.

### Formatting values and serialization precision

| Property | Accepted value |
| --- | --- |
| `Font.Bold`, `Font.Italic`, `Font.StrikeThrough`, `Font.SmallCaps`, `Font.Superscript`, `Font.Subscript`, `KeepTogether`, `PageBreakBefore` | Actual `Boolean`; numeric `-1`/`0` and Strings require explicit conversion |
| `Font.Underline` | Exact numeric member of `WdUnderline`, including all 18 named constants; `True` is not an underline enum |
| `Font.Size` | Actual finite number from `0.5` through `1638`, in exact half-point increments |
| `Font.Name` | Nonempty XML-safe String; control whitespace in font names is unsupported |
| `Font.Color` | Exact integer from `0` through `16777215`, using VBA's packed RGB representation; `RGB(r, g, b)` is supported |
| `ParagraphFormat.Alignment` | Exact integer `0`, `1`, `2`, or `3`, including the named constants below |
| `Range.HighlightColorIndex` | Exact integer `0..16`, including the named `WdColorIndex` constants; `0` removes highlighting |
| `SpaceBefore`, `SpaceAfter` | Nonnegative finite number in exact `0.05`-point increments; the resulting twentieth-point integer must not exceed `2147483647` |
| `LeftIndent`, `RightIndent`, `FirstLineIndent` | Signed finite number in exact `0.05`-point increments; absolute twentieth-point value must not exceed `2147483647` |
| `ParagraphFormat.ReadingOrder` | Exact integer `0` (RTL) or `1` (LTR), including the named `WdReadingOrder` constants |
| `ParagraphFormat.LineSpacingRule` | Exact integer `0`, `1`, or `2`, including the single, 1.5-line, and double-line constants below |
| Custom `ParagraphFormat.LineSpacingRule` | Exact integer `3`, `4`, or `5`, followed by a matching `LineSpacing` write under the paired contract below |
| `ParagraphFormat.LineSpacing` | Positive finite number in exact `0.05`-point increments, at most `107374182.35` points (`2147483647` native twips) |
| `PageSetup.PageWidth`, `PageSetup.PageHeight` | Actual finite number from `1` through `107374182.35` points, in exact `0.05`-point increments; native execution also checks page-body and column geometry |
| `PageSetup.TopMargin`, `BottomMargin`, `LeftMargin`, `RightMargin`, `HeaderDistance`, `FooterDistance` | Actual finite number from `0` through `107374182.35` points, in exact `0.05`-point increments; native execution also checks current geometry |
| `PageSetup.Orientation` | Exact numeric `0` (portrait) or `1` (landscape); native execution checks orientation consistency and resulting geometry |
| `PageSetup.SectionStart` | Exact numeric `0`, `2`, `3`, or `4` (continuous, new-page, even-page or odd-page); new-column `1` is unsupported |

The named alignment constants are `wdAlignParagraphLeft = 0`,
`wdAlignParagraphCenter = 1`, `wdAlignParagraphRight = 2`, and
`wdAlignParagraphJustify = 3`. Other Word alignment modes are unsupported.

The underline constants retain Microsoft's exact enum values, including
`wdUnderlineNone`, `wdUnderlineSingle`, `wdUnderlineWords`, double, dotted,
dash, dot-dash, dot-dot-dash, long-dash, wavy and their heavy/double variants.
They map to native Word underline styles without reducing them to a Boolean.
For example, `wdUnderlineDotDashHeavy = 25` writes `w:u w:val="dashDotHeavy"`.
`wdUnderlineNone` and `StrikeThrough = False` explicitly clear prior formatting.
`wdToggle`, mixed-state values and automatic conversions remain unsupported.

`FirstLineIndent = -12.5` sets a 12.5-point hanging indent and clears an existing
first-line indent. A later positive or zero value clears the hanging indent.
The left and right indent values remain independent. `KeepTogether` controls
the paragraph's keep-lines property; it does not imply keep-with-next.

### Paragraph reading order and line spacing

`ReadingOrder` changes the paragraph's base reading direction without changing
its alignment. `wdReadingOrderRtl = 0` writes native RTL; `wdReadingOrderLtr = 1`
writes an explicit LTR override, including against a right-to-left paragraph
style. These enum values are not Boolean values. Numeric Strings, Booleans,
fractions, and other enum values are refused. Reading-order writes preserve
unrelated attributes on the native `w:bidi` element and other paragraph properties.

The supported `LineSpacingRule` presets set both native line attributes in one
operation:

| Word constant | Value | Native line multiplier | DOCX `w:spacing` attributes |
| --- | ---: | ---: | --- |
| `wdLineSpaceSingle` | 0 | 1 | `w:line="240" w:lineRule="auto"` |
| `wdLineSpace1pt5` | 1 | 1.5 | `w:line="360" w:lineRule="auto"` |
| `wdLineSpaceDouble` | 2 | 2 | `w:line="480" w:lineRule="auto"` |

These preset writes replace an existing exact, minimum, or automatic line rule.
They own only `w:line` and `w:lineRule`: existing before/after spacing, their
automatic or line-unit metadata, and foreign attributes survive. When before/after
spacing is inherited, a line-spacing write does not copy those effective values
into direct formatting. An explicit same-value preset still becomes direct
formatting, so changing the paragraph style later cannot undo it.
The native engine displays the selected line multiplier; matching an installed
Word host's precise line-box metrics is outside this headless qualification.

`ParagraphFormat.Space1`, `Space15`, and `Space2` apply the same three presets.
They accept bare statements, empty parentheses, and both `Call` forms, including
inside `With`. They take no arguments and return no value in this dialect.
They operate on a `ParagraphFormat` selector; direct `Paragraph.Space1` and
collection-wide methods remain unsupported.

Paragraph formatting accepts empty paragraphs. `Font` aliases retain the
existing nonempty paragraph-text requirement and never include paragraph marks.
[`word_paragraph_layout.bas`](../packages/quds_office_engine/example/macros/word_paragraph_layout.bas)
demonstrates typed font and paragraph helpers, the direct `Paragraph.Format`
binding, RTL and LTR reading order, and all three line-spacing presets. It needs
three existing paragraphs, with nonempty text in the first paragraph.

### Exact, minimum and multiple line spacing

The custom rules use a point value explicitly supplied by the macro:

| Word rule | Value | Native interpretation of `LineSpacing` |
| --- | ---: | --- |
| `wdLineSpaceAtLeast` | 3 | Minimum line height in points; taller text may increase the line box |
| `wdLineSpaceExactly` | 4 | Fixed line height in points |
| `wdLineSpaceMultiple` | 5 | Points divided by 12 become the native line multiplier |

```vb
Sub Main()
    With ActiveDocument.Paragraphs(1).Format
        .LineSpacingRule = wdLineSpaceExactly
        .LineSpacing = 14.25
    End With
    With ActiveDocument.Paragraphs(2).Range.ParagraphFormat
        .LineSpacingRule = wdLineSpaceAtLeast
        .LineSpacing = 18
    End With
    With ActiveDocument.Paragraphs(3).Format
        .LineSpacingRule = wdLineSpaceMultiple
        .LineSpacing = LinesToPoints(1.75)
    End With
End Sub
```

This bounded source adapter requires **one explicit rule/amount pair for every
custom spacing edit**. After a custom `LineSpacingRule` assignment, the next
executed document mutation must be a `LineSpacing` assignment selecting the
same paragraph. Scalar calculations, local variable or selector rebinding,
conditions, and helper calls can occur between them if they emit no document
write. The pair can cross a `ByVal ParagraphFormat` helper boundary; aliases
selecting the same paragraph are equivalent. The selected rule remains pending
only during compilation, never in a live document or saved plan.

An intervening font, text, list, tab or paragraph mutation, another rule
assignment, a different paragraph, or an unfinished pair at macro exit causes
a positioned compilation error and returns no plan. `LineSpacing` on its own,
after a preset, or repeated without a fresh custom rule is unsupported. This
explicit restriction avoids inferring the current rule or the point height of
an existing automatic line from a document the compiler does not read. It is
not full independent-property behavior of Microsoft Word.

A completed pair emits one `docx.lineSpacing` operation, for example:

```json
{
  "tool": "docx.lineSpacing",
  "arguments": {"paragraph": 2, "rule": "multiple", "points": 21}
}
```

Consequently a pair consumes one native step; its two source assignments still
consume ordinary compiler work. The operation carries both values and changes
them together. Methods and presets continue to emit one operation each.

`LineSpacing` requires an actual numeric value or numeric Variant. Values must
be positive exact twentieth-points and fit the documented dialect twip bound.
Strings, Booleans, Empty, Null, omitted Variants, zero, negative values and
inexact native units are refused. A one-twip value (`0.05` points) is supported
for all three rules, including a multiple of `1/240` line. This is a storage
and model contract, not a claim about Word's user-interface limits.

`LinesToPoints(value)` multiplies by 12 and `PointsToLines(value)` divides by 12.
Both accept one actual finite numeric argument, including signed values and
zero, supplied positionally or as `Lines:=` / `Points:=`. They also work as `Application.LinesToPoints(...)`,
`Application.PointsToLines(...)`, or leading-dot calls inside `With Application`.
They are Word-only source functions; declarations cannot shadow their names.
Omitted arguments, object arguments and implicit scalar coercions are
unsupported. Conversion results must remain finite and within the shared
numeric magnitude bound `9007199254740991`; later property writes apply their
own precision/range checks. Inputs that exactly round-trip on the native
twentieth-point / 1/240-line grid use integer-unit arithmetic. Thus common
values such as `LinesToPoints(1.15)` yield the canonical `13.8`-point value
without widening the precision accepted for adjacent off-grid inputs.
Off-grid conversion inputs retain ordinary numeric arithmetic; the resulting
value, rather than the input's grid membership, is checked by a later write.
The adapter uses its existing numeric representation
and does not emulate VBA `Single` rounding or read font metrics.

Native edits own only `w:spacing/@w:line` and `@w:lineRule`, preserving unrelated
before/after attributes, automatic/line-unit metadata, extension attributes and
children, and foreign namespace lookalikes. Untouched inherited before/after
values still follow later style edits. An explicit same-value line-spacing
assignment becomes direct formatting. Native spacing attributes now resolve
by namespace identity in the style cascade, including alternate and rebound
prefixes; original paragraph/style XML stays intact.

Custom edits refuse ambiguous duplicate native paragraph/spacing containers or
line/rule attributes, and spacing-bearing markup-compatibility alternatives
anywhere in the stored Word XML, including foreign spacing lookalikes inside
alternatives. Alternatives within or wrapping native paragraph properties are
also refused when they carry other metadata: choosing a branch would discard
an unedited property packet. Unbalanced modeled field boundaries are refused before a custom
edit can trigger lossy serialization. These conservative source guards are
applied to `docx.lineSpacing` and to generic `docx.paragraphFormat` calls that
write `lineSpacing` or `lineSpacingRule`, including presets and `Space1` /
`Space15` / `Space2`. Before/after-only writes retain their existing behavior.
Valid supported field packets and opaque DOCM VBA parts remain inert and preserved.
Unrelated body drawing alternatives remain within the ordinary serializer's
existing behavior. This increment does not promise whole-package byte identity
or preservation of every unmodeled alternative outside paragraph properties.

The existing native layout uses fixed, minimum and multiple line heights;
installed Word pagination, font metrics and clipping parity are not claimed.
Automatic before/after setters, live spacing reads, arbitrary ranges and
collection-wide formatting remain outside this increment. The actual
[word_line_spacing.bas](../packages/quds_office_engine/example/macros/word_line_spacing.bas)
example combines helpers, aliases, presets and custom rules on three existing
body paragraphs. See the
[qualification record](validation/word-vba-paragraph-spacing-20261120/README.md)
for the executed local gates and source identities.

Primary contracts: Microsoft's
[LineSpacingRule](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.linespacingrule),
[LineSpacing](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.linespacing),
[LinesToPoints](https://learn.microsoft.com/en-us/office/vba/api/word.application.linestopoints),
[PointsToLines](https://learn.microsoft.com/en-us/office/vba/api/word.application.pointstolines),
[Space1](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.space1),
[Space15](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.space15)
and [Space2](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.space2).

### Physical measurement conversions

Word layout macros can convert inches, centimeters, millimeters and picas to
points and back, alongside the existing line/point conversions. These are
document-independent functions: compilation neither reads a document nor
queries screen resolution, fonts, locale or a running Word application.

| Function | Required argument name | Conversion |
| --- | --- | --- |
| `InchesToPoints` | `Inches` | inches × 72 |
| `CentimetersToPoints` | `Centimeters` | centimeters × 3600 / 127 |
| `MillimetersToPoints` | `Millimeters` | millimeters × 360 / 127 |
| `PicasToPoints` | `Picas` | picas × 12 |
| `LinesToPoints` | `Lines` | lines × 12 |
| `PointsToInches` | `Points` | points / 72 |
| `PointsToCentimeters` | `Points` | points × 127 / 3600 |
| `PointsToMillimeters` | `Points` | points × 127 / 360 |
| `PointsToPicas` | `Points` | points / 12 |
| `PointsToLines` | `Points` | points / 12 |

Every function accepts exactly one actual number or numeric Variant. The
argument can be positional or use the official name above, case-insensitively.
Global calls, `Application.Function(...)` and leading-dot calls inside
`With Application` all work. A supplied expression is evaluated once, in its
ordinary source order, with the existing compiler work limits. Helpers,
optional scalar defaults, arrays and arithmetic can supply measurements.
Missing values, comma holes, duplicates, wrong names, object values and
implicit conversion from String/Boolean/Empty/Null/omitted Variant are refused.
Call shapes and statically known argument types are checked even in unreachable
branches and unused helpers. A Variant's contents are checked when its value is
evaluated. Functions remain unavailable in Const/default expressions, which
already disallow function calls. The names are reserved only in `vba-word`;
they do not add builtins or new reservations to Excel or PowerPoint.

```vb
Sub Main()
    Dim inset As Double
    With Application
        inset = .CentimetersToPoints(Centimeters:=1.27)
        With .ActiveDocument.Paragraphs(1).Format
            .LeftIndent = inset
            .FirstLineIndent = -InchesToPoints(Inches:=0.25)
            .SpaceBefore = PicasToPoints(0.5)
            .TabStops.Add Position:=MillimetersToPoints(25.4)
            .LineSpacingRule = wdLineSpaceExactly
            .LineSpacing = InchesToPoints(0.25)
        End With
    End With
End Sub
```

This produces a 36-point left indent, an 18-point hanging indent, 6 points
before the paragraph, a tab at 72 points, and exact 18-point line spacing.
The complete [word_named_measurements.bas](../packages/quds_office_engine/example/macros/word_named_measurements.bas)
example uses all ten functions, typed format aliases, named helper arguments
and two existing paragraphs. It emits thirteen operations and is repeatable
on its own output. Its source, integration and portable-driver fixtures use
the matching `word_named_measurements` filenames.

The original [word_measurements.bas](../packages/quds_office_engine/example/macros/word_measurements.bas)
example and its independent fixtures are also retained. That example emits
eight writes, including a tab stop and custom line spacing, and requires two
existing body paragraphs. Keeping distinct filenames preserves both examples
and their native-document expectations.

The independently authored [word_unit_conversions.bas](../packages/quds_office_engine/example/macros/word_unit_conversions.bas)
example is also retained. It uses the eight physical conversion functions and
emits nine paragraph-format operations on two existing paragraphs. Both finish
with 72-point left indents, 18-point right indents, 12-point before spacing and
6-point after spacing; the first also has an 18-point hanging indent.

**Numeric contract.** The portable dialect uses bounded binary64 `Double`
arithmetic, including signed values and zero; it does not emulate the `Single`
parameters/results documented for Microsoft Word. Both inputs and results must
be finite and within magnitude `9007199254740991`. Intermediate multiplication
uses floating-point arithmetic to avoid signed-integer overflow on the Dart VM.
The physical ratios use
exactly 72 points and 25.4 millimeters per inch. Microsoft Learn's rounded
metric descriptions (including inconsistent millimeter approximations) are
not used as conversion constants. These are specification-derived expectations;
an installed Microsoft Word host has not been used to establish bit-for-bit
VBA behavior.

Exact native-grid values are canonicalized only when converting the candidate
integer twip count back reproduces the input double exactly. This keeps
`InchesToPoints(0.65) = 46.8`, `CentimetersToPoints(1.27) = 36` and
`PicasToPoints(1.15) = 13.8` usable without a tolerance that would snap adjacent
values. Off-grid inputs retain ordinary arithmetic. Inverse/forward round-trips
preserve native twip values, including one twip, within the existing signed-Long
document bound.

**Property precision remains explicit.** The result must still satisfy the
receiving property's existing range and precision rules. For example,
`CentimetersToPoints(1)` is a valid scalar value (about 28.34645669 points),
but assigning it directly to `LeftIndent` is refused because it is not an exact
twentieth-point. The adapter does not silently round that value to 28.35.
Macro authors can explicitly request native twip rounding using the existing
ties-to-even `CLng` conversion:

```vb
Sub Main()
    ActiveDocument.Paragraphs(1).Format.LeftIndent = _
        CLng(CentimetersToPoints(1) * 20) / 20
End Sub
```

This requests 28.35 points explicitly without changing the conversion's
precision contract. The independent
[word_unit_conversions.bas](../packages/quds_office_engine/example/macros/word_unit_conversions.bas)
and [word_measurements_positional.bas](../packages/quds_office_engine/example/macros/word_measurements_positional.bas)
examples and their original regression suites remain available alongside the
named-argument example. The canonical
[word_measurements.bas](../packages/quds_office_engine/example/macros/word_measurements.bas)
retains the earlier eight-helper example and its independent compiler, CLI/MCP
and portable-driver cases. All examples require their documented existing
paragraphs; no source fixture is silently replaced by a different contract.

That example writes 28.35 points. The compiler does not silently add rounding,
change a destination property's range limits, or emulate VBA `Single`
coercion. Microsoft's API documentation identifies Single arguments/results
and gives rounded metric conversion factors; the exact physical ratios above
are the explicit Quds numeric contract, not a claim of observed Word binary32
parity. They follow the exact ratios in Microsoft's
[Office coordinate specification](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/afb7e140-b259-4901-8af4-d4a514f50db9)
and [native unit definitions](https://learn.microsoft.com/en-us/windows/win32/vml/basic-vml-types).

Font sizes still require their existing half-point grid; tab stops, spacing
and indentation retain their existing constraints. Pixel conversions,
`Selection`, page-setup objects, arbitrary ranges and document property reads
remain outside this slice.

Conversions emit no native operation themselves. Resulting writes use the
same detached transaction, permissions, allowlists, operation limits,
cancellation and atomic publication as other Word macros. Native formatting
ownership also remains unchanged: indentation edits replace the native
`w:ind` property group, so foreign attributes inside that edited group are
not promised to survive. Unrelated paragraph metadata, untouched paragraphs,
style parts and opaque DOCM project/signature bytes are covered by the saved
document tests. See the [local qualification record](validation/word-vba-final-integration-20261120/README.md)
for executed VM, JavaScript, CLI and MCP checks.

Primary references: Microsoft Word's
[InchesToPoints](https://learn.microsoft.com/en-us/office/vba/api/word.application.inchestopoints),
[CentimetersToPoints](https://learn.microsoft.com/en-us/office/vba/api/word.application.centimeterstopoints),
[MillimetersToPoints](https://learn.microsoft.com/en-us/office/vba/api/word.application.millimeterstopoints),
[PicasToPoints](https://learn.microsoft.com/en-us/office/vba/api/word.application.picastopoints),
[PointsToInches](https://learn.microsoft.com/en-us/office/vba/api/word.application.pointstoinches),
[PointsToCentimeters](https://learn.microsoft.com/en-us/office/vba/api/word.application.pointstocentimeters),
[PointsToMillimeters](https://learn.microsoft.com/en-us/office/vba/api/word.application.pointstomillimeters)
and [PointsToPicas](https://learn.microsoft.com/en-us/office/vba/api/word.application.pointstopicas),
and [NIST's exact inch definition](https://www.nist.gov/pml/owm/si-units-length).

### Typography and highlighting

`SmallCaps` changes native formatting without uppercasing the authored text.
Setting it to `True` explicitly clears native `w:caps`, including a value
inherited from a style, because Word makes small capitals and all capitals
mutually exclusive. Setting it to `False` changes only small-cap formatting;
an unrelated native all-cap property is preserved. `Font.AllCaps` remains
unsupported because the current live model does not render that property.

`Superscript = True` selects native superscript and clears subscript;
`Subscript = True` does the reverse. A `False` assignment clears only the named
mode on each run: superscript-off leaves existing subscript intact, and
subscript-off leaves existing superscript intact. Runs in the cleared mode
receive an explicit `baseline` override so style inheritance cannot revive it
on save/reopen. These are whole-paragraph **text** operations, retaining the
existing paragraph-mark boundary. Mixed run formats remain distinct until a
write actually changes them. Numeric toggle and mixed-state values are refused.

Highlight constants use this exact fixed palette. The compiler emits native
RGB fields; DOCX serialization writes the corresponding named
`w:highlight` token. Clearing uses explicit `w:highlight w:val="none"`, including
when the previous color came from a style.

| Constant | Value | RGB / effect |
| --- | ---: | --- |
| `wdNoHighlight`, `wdAuto` | 0 | Remove highlighting |
| `wdBlack` | 1 | `000000` |
| `wdBlue` | 2 | `0000FF` |
| `wdTurquoise` | 3 | `00FFFF` |
| `wdBrightGreen` | 4 | `00FF00` |
| `wdPink` | 5 | `FF00FF` |
| `wdRed` | 6 | `FF0000` |
| `wdYellow` | 7 | `FFFF00` |
| `wdWhite` | 8 | `FFFFFF` |
| `wdDarkBlue` | 9 | `000080` |
| `wdTeal` | 10 | `008080` |
| `wdGreen` | 11 | `008000` |
| `wdViolet` | 12 | `800080` |
| `wdDarkRed` | 13 | `800000` |
| `wdDarkYellow` | 14 | `808000` |
| `wdGray50` | 15 | `808080` |
| `wdGray25` | 16 | `C0C0C0` |

The aliases `wdAuto` and `wdNoHighlight` have the same numeric value; on this
specific property it means removal. `wdByAuthor = -1` is declared for a precise
unsupported-value diagnostic and is not a highlight color. This does not add
`Font.ColorIndex`, theme color resolution, or automatic foreground colors.

[`word_typography.bas`](../packages/quds_office_engine/example/macros/word_typography.bas)
demonstrates the session document aliases, explicit collection `Item`, a typed
Range helper, small capitals, highlighting, and script-mode writes. It needs
three existing body paragraphs and prefixes the source text before formatting
them. Its native plan remains subject to the same permissions and transaction
boundary as other Word macros.

Size and spacing restrictions avoid silently rounding requested values when
the native serializer writes half-points and twentieth-points. The spacing
integer ceiling is a dialect serialization bound, not a claim about a maximum
accepted by Microsoft Word. `Font.Size` edits the regular native `w:sz` value.
The model projects that regular size whenever it is present in the effective
style cascade, with `w:szCs` as a compatibility fallback only when no regular
size exists. A separate complex-script `w:szCs` remains preserved as source
XML; this dialect does not expose Word's
[`Font.SizeBi`](https://learn.microsoft.com/en-us/office/vba/api/word.font.sizebi)
property. `Font.Name` sets the native ASCII font family;
independent East Asian and complex-script font selection is not implemented
by this source operation. Requested font availability and rendering fallback
remain the document host's responsibility.

Publication checks apply after expression evaluation. A String may contain
surrogate slices internally for the existing string intrinsics, but malformed
text cannot be emitted to the Word plan. Invalid selectors, values, or source
features report the ordinary positioned `OfficeVbaCompileException`; a failed
compilation returns no partial macro.

## Runnable report example

[`word_report.bas`](../packages/quds_office_engine/example/macros/word_report.bas)
builds a six-paragraph supply report from three local item names and quantities.
It uses typed object aliases, a `ByVal Range` helper, arrays, a loop, `CStr`, an
uninitialized Variant checked with `IsEmpty`, and lossless emoji extraction
with `Mid$`. Its source total is `14`. The template needs six existing, empty
body paragraphs; the example inserts text and then formats each paragraph.

The expected paragraph text is:

1. `Weekly supply report`
2. `Paper: 5`
3. `Ink: 3`
4. `Labels: 6`
5. `Total units: 14`
6. `Source values supplied by the macro. 😀`

The example is an insertion macro: running it twice inserts a second copy
before the earlier content. It does not read or replace existing paragraph
text. A native builder can create the initial template:

```dart
final builder = DocxDocumentBuilder();
for (var i = 0; i < 6; i++) {
  builder.paragraph('');
}
final templateBytes = builder.build();
```

From `packages/quds_office_engine`, the explicit CLI commands are:

```sh
dart run tool/macros/office_macro.dart compile-word-vba \
  example/macros/word_report.bas word-report.qudsmacro.json
dart run tool/macros/office_macro.dart validate-word-vba \
  template.docx example/macros/word_report.bas
dart run tool/macros/office_macro.dart run-word-vba \
  template.docx example/macros/word_report.bas report.docx
```

The optional final argument selects an entry-point Sub; its default is `Main`.
Input and output must have the same extension. Word-family inputs are routed
to format `docx`, including `.docm`, `.dotx`, and `.dotm` packages. Opaque VBA
project bytes can be preserved during document edits; they are never executed
by this compiler or the native runtime.

The Dart API uses an explicit language and document family:

```dart
final plan = OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordReport',
    source: sourceText,
  ),
);
final session = OfficeMacroSession(
  templateBytes,
  format: OfficeMacroFormat.docx,
);
await session.validate(plan); // Executes and saves a detached copy.
await session.run(OfficeMacro.parse(plan.encode()));
final resultBytes = session.bytes;
```

The existing MCP source envelope also accepts `language: "vba-word"` and
`format: "docx"`. See [the macro MCP contract](MACROS.md#mcp-integration) for tool requests
and structured diagnostics.

## Atomic runtime and verification scope

A compiled Word plan uses the same transaction as handwritten native plans.
If a later selector is missing, a text range is empty, a native structural
guard rejects an edit, or serialization fails, earlier detached edits are not
published. Session bytes, revision, and recording remain unchanged. Successful
`validate` also leaves the session unchanged. A successful nonempty `run`
publishes one new document revision regardless of the number of operations.
An empty plan leaves the revision unchanged.

Source diagnostics and complete ordered plans are covered by the versioned
[conformance format](VBA_CONFORMANCE.md). The independent Word integration
suite runs on the Dart VM, compiles source, and executes its plan against real
native packages. It checks save/reopen behavior, selector routing, formatting
precision, transaction rollback, revision history, and opaque macro-part
preservation. The conformance runner also supports compiled JavaScript. These
checks do not claim observed Microsoft Word host results.

The typography continuation passes its compiler/native regressions within the
[final combined local gate](validation/office-vba-continuation-20261120/README.md).
The actual `word_typography.bas` example also produces identical native
transaction and repeated-save results on VM and compiled JavaScript.

Unsupported scope includes document-content reads,
`Selection`, `Paragraphs.Count`, `Sections.Count`, live collection iteration,
editable character subranges, paragraph/section creation, whole-document ranges,
document-wide page setup, tables as Word objects,
headers and footers as Word objects, event entry points, COM, external files,
and execution or editing of an embedded VBA project.

## Primary reference boundaries

The following Microsoft references inform the supported source vocabulary and
the explicit restrictions above. They do not certify this implementation:

- [Paragraphs object](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs): indexed paragraph access and main-story collection scope.
- [Document.Sections](https://learn.microsoft.com/en-us/office/vba/api/word.document.sections), [Sections.Item](https://learn.microsoft.com/en-us/office/vba/api/word.sections.item), and [Section.PageSetup](https://learn.microsoft.com/en-us/office/vba/api/word.section.pagesetup): explicit section selection and page-setup object vocabulary; the source integer limits and no-read restrictions above are deliberate dialect boundaries.
- [PageSetup.PageWidth](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.pagewidth) and [PageHeight](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.pageheight): point dimensions and the custom-paper side effect of each setter. Quds does not claim VBA Single rounding or a general paper-size object model.
- [PageSetup.Orientation](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.orientation), [WdOrientation](https://learn.microsoft.com/en-us/office/vba/api/word.wdorientation), and [PageSetup.TogglePortrait](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.toggleportrait): member vocabulary, enum values and toggling. The explicit dimension/margin behavior above is the bounded Quds contract, without an installed Word differential claim.
- [PageSetup.SectionStart](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.sectionstart) and [WdSectionStart](https://learn.microsoft.com/en-us/office/vba/api/word.wdsectionstart): break modes and their numeric identities, applied to the beginning of the selected section. New-column starts remain unsupported.
- [PageSetup.TopMargin](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.topmargin), [BottomMargin](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.bottommargin), [LeftMargin](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.leftmargin), and [RightMargin](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.rightmargin): page-to-body distances in points.
- [PageSetup.HeaderDistance](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.headerdistance) and [FooterDistance](https://learn.microsoft.com/en-us/office/vba/api/word.pagesetup.footerdistance): page-edge distances in points, separate from story content.
- [Paragraphs.Item](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs.item) and [Application.ActiveDocument](https://learn.microsoft.com/en-us/office/vba/api/word.application.activedocument): source vocabulary; the Quds session binding is explicitly scoped above.
- [Paragraph.Format](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.format), [Font](https://learn.microsoft.com/en-us/office/vba/api/word.font), and [ParagraphFormat](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat): typed formatting objects; this dialect binds explicit paragraph selectors only.
- [ParagraphFormat.ReadingOrder](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.readingorder) and [WdReadingOrder](https://learn.microsoft.com/en-us/office/vba/api/word.wdreadingorder): reading direction independently of alignment, with exact RTL/LTR numeric identities.
- [ParagraphFormat.LineSpacingRule](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.linespacingrule) and [WdLineSpacing](https://learn.microsoft.com/en-us/office/vba/api/word.wdlinespacing): line-spacing presets and the separate point-based spacing property required by the remaining rules.
- [Range.InsertBefore](https://learn.microsoft.com/en-us/office/vba/api/word.range.insertbefore): insertion before a range and range expansion; full Word also supports structural characters excluded here.
- [Range.InsertAfter](https://learn.microsoft.com/en-us/office/vba/api/word.range.insertafter): the ending paragraph mark and insertion boundary.
- [Font.Size](https://learn.microsoft.com/en-us/office/vba/api/word.font.size) and [Font.Name](https://learn.microsoft.com/en-us/office/vba/api/word.font.name): point units and the named font property.
- [WdParagraphAlignment](https://learn.microsoft.com/en-us/office/vba/api/word.wdparagraphalignment): numeric alignment constants.
- [WdUnderline](https://learn.microsoft.com/en-us/office/vba/api/word.wdunderline) and [Font.StrikeThrough](https://learn.microsoft.com/en-us/office/vba/api/word.font.strikethrough): underline enum values and strike formatting.
- [Font.SmallCaps](https://learn.microsoft.com/en-us/office/vba/api/word.font.smallcaps), [Superscript](https://learn.microsoft.com/en-us/office/vba/api/word.font.superscript), and [Subscript](https://learn.microsoft.com/en-us/office/vba/api/word.font.subscript): formatting flags and mutual exclusion; these checks contain no installed Word-host observations.
- [Range.HighlightColorIndex](https://learn.microsoft.com/en-us/office/vba/api/word.range.highlightcolorindex) and [WdColorIndex](https://learn.microsoft.com/en-us/office/vba/api/word.wdcolorindex): fixed color vocabulary and highlighting removal.
- [FirstLineIndent](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.firstlineindent): negative values mean hanging indentation.
- [KeepTogether](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.keeptogether) and [PageBreakBefore](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.pagebreakbefore): paragraph pagination properties.
- [ParagraphFormat.SpaceBefore](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.spacebefore) and [SpaceAfter](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.spaceafter): paragraph spacing in points.
