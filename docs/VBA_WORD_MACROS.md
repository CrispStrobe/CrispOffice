# Word VBA macros: the `vba-word` dialect

`OfficeVbaWordMacroLanguage` compiles an explicitly selected `.bas` module into
an immutable native Word operation plan. `OfficeMacroLanguages` installs the
adapter by default. Select language **`vba-word`** and format **`docx`**; the
separate `vba-excel` adapter and its spreadsheet contract remain available.

Compilation evaluates the supplied source without opening or reading a
document. The supported Word objects describe explicit paragraph selectors.
The ordinary native runtime resolves those selectors against a detached Word
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

`Document`, `Paragraph`, `Range`, `Font`, `ParagraphFormat`, `TabStops`, and `ListFormat` declarations
support explicit `Set` bindings and `ByVal` helper parameters. `With` may target
these supported objects or the range's `Font` and `ParagraphFormat`. All bindings remain
document-independent selectors; they never expose text or formatting reads.

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
named optional arguments as described below; other Word members retain their
positional-only contract.

The common source language includes the existing local procedures and scalar
functions, bounded control flow, typed arrays, string intrinsics, and explicit
Variant states and conversions described in [the shared language
contract](VBA_MACROS.md). Excel object members are unavailable in `vba-word`.
Word object members are unavailable in `vba-excel`.

## Exact native mapping

In this table, `i` is a one-based paragraph index and `p` is `i - 1`. Every
operation uses the native default `body` story. The compiler does not emit a
header, footer, note, or comment story selector.

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

Each source write emits one native operation, in evaluation order. Repeated
`InsertBefore` calls act on the paragraph as it exists at each step: inserting
`"A"` and then `"B"` before `"tail"` produces `"BAtail"`. A later font operation
formats the paragraph's current text, including text inserted by earlier steps.

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
assignment, default-tab setters, `Selection`, unit-conversion intrinsics or live
document reads. The actual [word_tabstops.bas](../packages/quds_office_engine/example/macros/word_tabstops.bas)
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

`wdLineSpaceAtLeast = 3`, `wdLineSpaceExactly = 4`, and
`wdLineSpaceMultiple = 5` are recognized constants but are refused as writes.
Their interaction with the point-based `LineSpacing` property needs a separate
compatibility contract. `LineSpacing`, arbitrary line multiples, automatic
before/after setters, and the `Space1`/`Space15`/`Space2` methods are not introduced
by this slice. Preserving existing source metadata does not add live rendering
or editing support for those unmodeled spacing modes.

Paragraph formatting accepts empty paragraphs. `Font` aliases retain the
existing nonempty paragraph-text requirement and never include paragraph marks.
[`word_paragraph_layout.bas`](../packages/quds_office_engine/example/macros/word_paragraph_layout.bas)
demonstrates typed font and paragraph helpers, the direct `Paragraph.Format`
binding, RTL and LTR reading order, and all three line-spacing presets. It needs
three existing paragraphs, with nonempty text in the first paragraph.

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
`Selection`, `Paragraphs.Count`, live collection iteration, editable character
subranges, paragraph creation, whole-document ranges, tables as Word objects,
headers and footers as Word objects, event entry points, COM, external files,
and execution or editing of an embedded VBA project.

## Primary reference boundaries

The following Microsoft references inform the supported source vocabulary and
the explicit restrictions above. They do not certify this implementation:

- [Paragraphs object](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs): indexed paragraph access and main-story collection scope.
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
