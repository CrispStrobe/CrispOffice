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

`Document`, `Paragraph`, and `Range` declarations support explicit `Set`
bindings and `ByVal` helper parameters. `With` may target these supported
objects or the range's `Font` and `ParagraphFormat`. All bindings remain
document-independent selectors; they never expose text or formatting reads.

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
| `range.ParagraphFormat.Alignment = value` | `docx.paragraphFormat` | `alignment: left`, `center`, `right`, or `justify` |
| `range.ParagraphFormat.SpaceBefore = value` | `docx.paragraphFormat` | `before: value` in points |
| `range.ParagraphFormat.SpaceAfter = value` | `docx.paragraphFormat` | `after: value` in points |

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

### Paragraph selectors

`ThisDocument.Paragraphs(i)` requires an actual numeric value that is an exact
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
| `Font.Bold`, `Font.Italic` | Actual `Boolean`; numeric `-1`/`0` and Strings require explicit conversion |
| `Font.Size` | Actual finite number from `0.5` through `1638`, in exact half-point increments |
| `Font.Name` | Nonempty XML-safe String; control whitespace in font names is unsupported |
| `Font.Color` | Exact integer from `0` through `16777215`, using VBA's packed RGB representation; `RGB(r, g, b)` is supported |
| `ParagraphFormat.Alignment` | Exact integer `0`, `1`, `2`, or `3`, including the named constants below |
| `SpaceBefore`, `SpaceAfter` | Nonnegative finite number in exact `0.05`-point increments; the resulting twentieth-point integer must not exceed `2147483647` |

The named alignment constants are `wdAlignParagraphLeft = 0`,
`wdAlignParagraphCenter = 1`, `wdAlignParagraphRight = 2`, and
`wdAlignParagraphJustify = 3`. Other Word alignment modes are unsupported.

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

Unsupported scope includes document-content reads, `ActiveDocument`,
`Selection`, `Paragraphs.Count`, live collection iteration, editable character
subranges, paragraph creation, whole-document ranges, tables as Word objects,
headers and footers as Word objects, event entry points, COM, external files,
and execution or editing of an embedded VBA project.

## Primary reference boundaries

The following Microsoft references inform the supported source vocabulary and
the explicit restrictions above. They do not certify this implementation:

- [Paragraphs object](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs): indexed paragraph access and main-story collection scope.
- [Range.InsertBefore](https://learn.microsoft.com/en-us/office/vba/api/word.range.insertbefore): insertion before a range and range expansion; full Word also supports structural characters excluded here.
- [Range.InsertAfter](https://learn.microsoft.com/en-us/office/vba/api/word.range.insertafter): the ending paragraph mark and insertion boundary.
- [Font.Size](https://learn.microsoft.com/en-us/office/vba/api/word.font.size) and [Font.Name](https://learn.microsoft.com/en-us/office/vba/api/word.font.name): point units and the named font property.
- [WdParagraphAlignment](https://learn.microsoft.com/en-us/office/vba/api/word.wdparagraphalignment): numeric alignment constants.
- [ParagraphFormat.SpaceBefore](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.spacebefore) and [SpaceAfter](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.spaceafter): paragraph spacing in points.
