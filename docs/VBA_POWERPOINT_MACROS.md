# PowerPoint VBA macros: the `vba-powerpoint` dialect

`OfficeVbaPowerPointMacroLanguage` compiles explicitly supplied `.bas` source
into an immutable native presentation plan. It is installed by default in
`OfficeMacroLanguages` alongside `vba-excel`, `vba-word`, and native JSON.
Use language **`vba-powerpoint`** with document family **`pptx`**.

The three VBA adapters share one parser, checker, evaluator, diagnostic model,
and set of resource limits. Source logic runs during compilation, without
opening a document. Explicit selectors are resolved during detached validation
or execution. A successful run publishes one complete saved document; a later
failure leaves the original bytes and revision unchanged.

This is a bounded source dialect. It does not launch PowerPoint or execute the
embedded `vbaProject.bin`. It does not claim full VBA or PowerPoint parity.

## Example

The input presentation must contain a first slide with an ordinary ungrouped
text shape named exactly `Title`.

```vb
Option Explicit

Sub StyleTitle(ByVal target As Shape, ByVal heading As String)
    With target.TextFrame.TextRange
        .Text = heading
        .Font.Name = "Arial"
        .Font.Size = 28.5
        .Font.Bold = msoTrue
        .Font.Italic = msoFalse
        .Font.Underline = False
        .Font.Color.RGB = RGB(31, 78, 121)
        .ParagraphFormat.Alignment = ppAlignCenter
    End With
    target.Left = 24
    target.Top = 36
    target.Width = 640
    target.Height = 72
End Sub

Sub Main()
    Dim title As Shape
    Set title = ActivePresentation.Slides(1).Shapes("Title")
    Call StyleTitle(title, "Quarterly report")
End Sub
```

`ActivePresentation` means the presentation explicitly supplied to this macro
session. `Application.ActivePresentation` is the same binding; it does not
discover a running application or switch documents. `Presentation`, `Slide`,
`Shape`, and `TextRange` variables support `Set` and explicit `ByVal` helper
parameters. Nested `With` blocks also accept their supported intermediate
objects. Source arrays, loops, reusable functions, String intrinsics, and
Variant conversions follow [the shared language contract](VBA_MACROS.md).

## Selectors and collection boundaries

Both `Slides(i)` and `Slides.Item(i)` select a one-based slide. Both
`Shapes(i)` and `Shapes.Item(i)` select a one-based shape; either accepts a
nonempty exact shape name instead. Numeric selectors must be actual integral
numbers in `1..2147483647`. Strings containing numbers are names, not indices.
Name lookup is case-sensitive, preserves whitespace, and refuses duplicate
matching names. This exact-name restriction is part of this dialect's contract.

The compiler lowers indices to native zero-based selectors and adds
`topLevel: true` to every PowerPoint operation. This guard verifies that the
target slide's native shape tree and modeled objects agree in identity and
order. Slides containing groups, including empty groups, or unrepresented
native objects are refused. The engine's general native shape list may contain
flattened group children; VBA must never silently interpret those as Office's
top-level `Shapes` collection. `GroupItems`, nested selection, live collection
iteration, collection counts, and shape creation/deletion are outside this slice.

Missing slides or shapes and ambiguous names fail during validation or run.
Compilation has no access to the input file and cannot confirm those targets.
Explicit text edits reject pictures and tables. The existing native operations
remain available with their documented model-index semantics when the strict
VBA selector flag is absent.

## Supported writes

Each assignment emits one ordered native call. The common selector arguments
are `slide`, exactly one of `shape` or `shapeName`, and `topLevel: true`.

| PowerPoint property | Native call | Additional field |
| --- | --- | --- |
| `shape.TextFrame.TextRange.Text` | `pptx.shapeText` | `text` |
| `text.Font.Name` | `pptx.shapeFormat` | `font` |
| `text.Font.Size` | `pptx.shapeFormat` | `size`, in points |
| `text.Font.Bold`, `.Italic`, `.Underline` | `pptx.shapeFormat` | `bold`, `italic`, `underline` |
| `text.Font.Color.RGB` | `pptx.shapeFormat` | `color`, six uppercase RGB digits |
| `text.ParagraphFormat.Alignment` | `pptx.shapeFormat` | `alignment` |
| `shape.Left`, `.Top` | `pptx.shapeGeometry` | `x`, `y`, in points |
| `shape.Width`, `.Height` | `pptx.shapeGeometry` | `width`, `height`, in points |
| `shape.Rotation` | `pptx.shapeGeometry` | `rotation`, in degrees |

PowerPoint `Font.Color` is an object, so color assignment requires `.RGB`.
The packed integer uses VBA's red/green/blue ordering; `RGB(r, g, b)` shares
the existing compiler implementation.

Font Boolean properties accept actual `True`/`False` or exact
`msoTrue = -1` / `msoFalse = 0`. `msoCTrue`, mixed, toggle, and other numbers
are refused. Toggle and mixed-state behavior would require live document reads.
Alignment accepts `ppAlignLeft = 1`, `ppAlignCenter = 2`,
`ppAlignRight = 3`, and `ppAlignJustify = 4`; other alignment modes are refused.

Font size is limited to `1..4000` points in exact hundredths. Geometry uses
points and degrees, converted by the native serializer to 12,700 EMUs per point
or 60,000 units per degree. The scaled value must fit a signed 32-bit integer;
width and height must be at least `0.01` points. These are explicit dialect
serialization bounds, not a claim about every value accepted by PowerPoint.

## Text, formatting and preservation

`TextRange.Text` replaces the selected shape's complete text. This increment
accepts XML-safe, well-formed UTF-16 single-paragraph Strings, including tabs
and emoji. Carriage returns, line feeds, other forbidden XML controls, and
unpaired surrogates are refused before a plan is returned. Font and shape names
must be nonempty and cannot contain tabs or line breaks. Font names additionally
require non-whitespace content, at most 255 UTF-16 units, and no DEL control.
Characters/subranges,
paragraph insertion, and PowerPoint's full CR/soft-line-break model remain
unsupported.

Formatting operations retain the source text body, paragraph structure, runs,
fields, hyperlinks and unrelated properties. Explicit `False` removes an
existing bold, italic or underline effect. Assigning an existing representative
size, color or alignment still applies it across all mixed runs/paragraphs.
The model's resolved rich text and saved DrawingML use the same overrides.
Explicit text formatting of an empty supported shape creates an empty text
body without adding visible text. Requested fonts remain subject to the host's
font availability and fallback behavior.

Formatting after a text replacement applies to the replacement text. Earlier
source content is not read into VBA variables. `Fill.ForeColor` is excluded:
changing a gradient's foreground color is not the same operation as replacing
its fill with a solid color, so the compiler does not approximate it with the
native solid-fill field.

## CLI, Dart and MCP

From `packages/quds_office_engine`:

```sh
dart run tool/macros/office_macro.dart compile-powerpoint-vba \
  example/macros/powerpoint_report.bas presentation.qudsmacro.json
dart run tool/macros/office_macro.dart validate-powerpoint-vba \
  template.pptx example/macros/powerpoint_report.bas
dart run tool/macros/office_macro.dart run-powerpoint-vba \
  template.pptx example/macros/powerpoint_report.bas report.pptx
```

The optional final argument selects a parameterless `Sub`, defaulting to
`Main`. The example requires first-slide shapes named `Title` and `Body` and
uses synthetic source values. Input and output must have the same extension;
`.pptm`, `.potx`, `.potm`, `.ppsx`, and `.ppsm` route to the presentation family
and retain their package types. A compile or execution failure leaves an
existing output untouched.

```dart
final plan = OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-powerpoint',
    format: OfficeMacroFormat.pptx,
    moduleName: 'DeckReport',
    source: sourceText,
  ),
);
final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.pptx);
await session.validate(plan);
await session.run(plan);
final updatedBytes = session.bytes;
```

The MCP `office_macro_compile` tool accepts the same source envelope with
`language: "vba-powerpoint"` and `format: "pptx"`. Pass its returned `macro`
to `office_macro_validate` or `office_macro_run`. Compilation remains read-only;
execution still requires host permission for each generated operation.

## Qualification and remaining scope

The local checks cover compiler refusals and complete plans, VM/JavaScript
conformance, native save/reopen, XML attributes, policy enforcement, atomic
rollback, real CLI subprocesses, MCP, and opaque PPTM project preservation.
See [the exact source and execution record](validation/office-vba-word-powerpoint-20261120/README.md).
Specification-derived expectations are separate from observed Office-host
fixtures; this increment contains no installed Microsoft PowerPoint results.

Live document reads, named/optional arguments, `ByRef`, events, shape creation,
slides/masters manipulation, notes, COM, filesystem/network calls, project
loading/editing, macro UI and debugger integration remain outside this adapter.
The [parity roadmap](VBA_PARITY_ROADMAP.md) tracks these independently of test
counts. Existing embedded projects remain opaque and inert.

## Primary references

- [Shapes.Item](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.shapes.item) and [Slide.Shapes](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slide.shapes): one-based/native collection access and names.
- [Shape.GroupItems](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.shape.groupitems): group children are a separate collection.
- [TextRange](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.textrange) and [Font](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.font): text and font object paths.
- [Font.Size](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.font.size): size in points.
- [MsoTriState](https://learn.microsoft.com/en-us/office/vba/api/office.msotristate): numeric Boolean-state constants.
- [PpParagraphAlignment](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.ppparagraphalignment): alignment constants.
- [Shape.Left](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.shape.left) and [Shape.Rotation](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.shape.rotation): geometry units.
