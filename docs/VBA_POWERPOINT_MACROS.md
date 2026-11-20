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
`Shape`, `TextFrame`, `TextRange`, `Font`, `ParagraphFormat`, and
`SlideShowTransition` variables support `Set` and explicit `ByVal` helper
parameters. Nested `With` blocks also accept their supported intermediate
objects. These are selector bindings; assigning an alias does not read a live
property value. Source arrays, loops, reusable functions, String intrinsics, and
Variant conversions follow [the shared language contract](VBA_MACROS.md).

## Selectors and collection boundaries

Both `Slides(i)` and `Slides.Item(i)` select a one-based slide. Both
`Shapes(i)` and `Shapes.Item(i)` select a one-based shape; either accepts a
nonempty exact shape name instead. Numeric selectors must be actual integral
numbers in `1..2147483647`. Strings containing numbers are names, not indices.
Name lookup is case-sensitive, preserves whitespace, and refuses duplicate
matching names. This exact-name restriction is part of this dialect's contract.

The compiler lowers indices to native zero-based selectors and adds
`topLevel: true` to every operation that targets a shape. This guard verifies
that the target slide's native shape tree and modeled objects agree in identity
and order. Slide visibility and transition properties use only a slide selector. Slides containing groups, including empty groups, or unrepresented
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

Each assignment emits one ordered native call. The following shape operations
share selector arguments `slide`, exactly one of `shape` or `shapeName`, and
`topLevel: true`. Slide visibility and transition writes are listed separately
below.

| PowerPoint property | Native call | Additional field |
| --- | --- | --- |
| `shape.TextFrame.TextRange.Text` | `pptx.shapeText` | `text` |
| `shape.TextFrame.VerticalAnchor` | `pptx.shapeTextFrame` | `anchor`: `top`, `center`, or `bottom` |
| `shape.TextFrame.MarginLeft`, `.MarginTop`, `.MarginRight`, `.MarginBottom` | `pptx.shapeTextFrame` | `marginLeft`, `marginTop`, `marginRight`, `marginBottom`, in points |
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

## Text-frame vertical alignment

`TextFrame.VerticalAnchor` accepts the exact Office values below. It changes
vertical placement inside the text frame, independently of paragraph alignment,
shape position, text direction, insets, and autofit.

| Office constant | Numeric value | Native anchor | DrawingML `bodyPr@anchor` |
| --- | ---: | --- | --- |
| `msoAnchorTop` | 1 | `top` | `t` |
| `msoAnchorMiddle` | 3 | `center` | `ctr` |
| `msoAnchorBottom` | 4 | `bottom` | `b` |

`msoAnchorTopBaseline = 2`, `msoAnchorBottomBaseline = 5`, and
`msoVerticalAnchorMixed = -2` are recognized constants but unsupported writes.
Their values are not approximated as top or bottom. An explicit assignment of
Top still takes effect when the imported model's fallback was already top but
the native XML used an unsupported anchor. Anchoring an empty supported shape
creates an empty text body; it does not add visible text.

## Text-frame margins

The four `TextFrame.MarginLeft`, `MarginTop`, `MarginRight`, and `MarginBottom`
writes use points and work through typed `TextFrame` aliases, `With`, and helper
parameters. Each write changes one side and leaves the other sides, vertical
anchor, rich text, fields, hyperlinks, writing direction and autofit untouched.
Zero removes that side's inset. Explicit same-value assignments still write a
direct native override; an omitted side remains omitted in the saved XML.

Values must be actual finite nonnegative numbers whose point value converts
exactly to an integer in `0..2147483647` EMUs at 12,700 EMUs per point. This is a
bounded dialect precision rule; values are refused rather than rounded. For
example, `0.1`, `12.5`, and `1 / 12700` are accepted, while `0.00001`, negative
values, numeric Strings and Booleans are refused. The same validation applies
to the native macro operation, which validates every supplied margin before
changing the model.

The model projects direct DrawingML `a:bodyPr` inset attributes and uses their
standard defaults when absent (left/right 7.2 points; top/bottom 3.6 points).
PDF placement and editor painting/hit-testing use this inset rectangle, including
unequal top/bottom margins for middle and bottom anchors. Native overflow and
zero-height autofit text remain visible. Layout/master **margin inheritance is
not resolved by this live projection**: omitted native sides remain preserved
for Office to inherit, but their inherited values are not claimed as rendered
by this increment. Assign all four sides to make their values explicit.

The [margin example](../packages/quds_office_engine/example/macros/powerpoint_text_margins.bas)
uses all four sides and a middle anchor on the existing `Title` shape of slide 1.
This does not add `WordWrap`, `AutoSize`, text-direction edits or live margin reads.

## Slide visibility and transitions

Select a slide explicitly and use its `SlideShowTransition` binding:

```vb
Dim movement As SlideShowTransition
Set movement = ActivePresentation.Slides(1).SlideShowTransition
With movement
    .Hidden = msoFalse
    .AdvanceOnClick = msoTrue
    .Duration = 1.25
    .EntryEffect = ppEffectFadeSmoothly
End With
```

These operations take `slide` and the one requested property. They do not select
a shape and do not require an ungrouped shape collection.

| PowerPoint property | Native call | Additional fields |
| --- | --- | --- |
| `SlideShowTransition.Hidden` | `pptx.slideHidden` | `hidden` |
| `SlideShowTransition.AdvanceOnClick` | `pptx.slideTransition` | `advanceOnClick` |
| `SlideShowTransition.Duration` | `pptx.slideTransition` | `durationMs` |
| `SlideShowTransition.EntryEffect` | `pptx.slideTransition` | `kind`, and `direction` for directional effects |

`Hidden` changes whether the slide participates in the slideshow; it preserves
slide identity and order. `Hidden` and `AdvanceOnClick` accept actual Booleans or
exact `msoTrue = -1` / `msoFalse = 0`, including explicit false and same-value
writes. Other tri-state values are unsupported.

`Duration` is the transition animation's duration in seconds. It accepts an
actual finite number with an exact positive millisecond representation in
`1..2147483647` milliseconds (`0.001..2147483.647` seconds). Values such as
`0`, `0.0005`, numeric Strings, and values outside that range are refused.
This precision and range are bounded dialect serialization rules, not a claim
about PowerPoint's full numeric range. Duration does not set how long a slide
remains on screen. Existing automatic-advance timing is retained; the
`AdvanceOnTime` and `AdvanceTime` properties are outside this slice.

The supported entry effects have these exact Office numeric identities:

| Office constant | Numeric value | Native kind | Native direction |
| --- | ---: | --- | --- |
| `ppEffectNone` | 0 | `none` | unchanged |
| `ppEffectCut` | 257 | `cut` | unchanged |
| `ppEffectFadeSmoothly` | 3849 | `fade` | unchanged |
| `ppEffectPushDown` | 3852 | `push` | `down` |
| `ppEffectPushLeft` | 3853 | `push` | `left` |
| `ppEffectPushRight` | 3854 | `push` | `right` |
| `ppEffectPushUp` | 3855 | `push` | `up` |
| `ppEffectWipeLeft` | 2817 | `wipe` | `left` |
| `ppEffectWipeUp` | 2818 | `wipe` | `up` |
| `ppEffectWipeRight` | 2819 | `wipe` | `right` |
| `ppEffectWipeDown` | 2820 | `wipe` | `down` |

Other effect values are refused. In particular, the legacy fade value is not
treated as an alias for `ppEffectFadeSmoothly`.

### Native transition preservation

Partial writes preserve omitted transition fields, existing automatic-advance
timing, sounds, and extension metadata on a direct native `p:transition`.
Duration and click writes retain an unknown direct effect's original XML.
An explicit `EntryEffect` assignment owns the effect and replaces its native
effect node while retaining sound and extension-list children. A slide with
no effect can still retain explicit duration, click, and automatic-advance
metadata; it is not rewritten with a fabricated fade effect.

XML attribute ownership uses namespace URI and local name. An unrelated
extension's `x:dur`, `x:advClick`, `x:spd`, or `x:anchor` is retained when the
corresponding native property is changed. Native duration uses the PowerPoint
2010 namespace, choosing an unoccupied prefix when the imported file already
uses `p14` for another namespace. Imported transition element prefixes,
including a default namespace, remain valid when replacing an effect.

Some Office files put transitions in a root `mc:AlternateContent` wrapper.
That wrapper, its choice/fallback content, and namespace bindings are preserved
on unrelated saves, shape edits, and `Hidden` changes. This dialect does not
choose or project a fallback effect and refuses explicit `Duration`,
`AdvanceOnClick`, and `EntryEffect` writes to such containers. Refusal occurs
before publication, including same-value assignments. Direct native transition
mutation has the same guard.

Inherited `mc:Ignorable` context is retained by namespace meaning and merged
without duplicate expanded-name attributes. More complex inherited markup
compatibility directives, such as `mc:ProcessContent`, are outside this bounded
transition serializer; a save that would rewrite such a transition refuses
instead of discarding or reinterpreting that context. Validation and execution
leave the original bytes and revision unchanged on these failures.

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
Explicit text formatting or anchoring of an empty supported shape creates an
empty text body without adding visible text. Vertical-anchor writes own only
the unqualified DrawingML anchor attribute and preserve text-body insets,
vertical writing mode, autofit, rich runs, fields, and hyperlinks. Model copies,
live anchor state, serialization, and reopening use the same requested anchor.
Requested fonts remain subject to the host's font availability and fallback
behavior.

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
`Main`. The report example requires first-slide shapes named `Title` and `Body`
and uses synthetic source values.

The additional [slideshow example](../packages/quds_office_engine/example/macros/powerpoint_slideshow.bas)
exercises typed text-frame, font, paragraph, and transition helpers. It requires
two existing slides, an ungrouped text shape named `Title` on slide 1, and an
editable direct transition (or none) on slide 1. It centers and styles the title,
configures a 1.25-second fade with click advance, and hides slide 2 as an appendix
without reordering it. Use its path in the same CLI commands above.

Input and output must have the same extension;
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

The earlier adapter's executed checks cover compiler refusals and complete
plans, VM/JavaScript conformance, native save/reopen, XML attributes, policy
enforcement, atomic rollback, real CLI subprocesses, MCP, and opaque PPTM project
preservation. See [that source and execution record](validation/office-vba-word-powerpoint-20261120/README.md).

The text-frame/slideshow continuation adds
[compiler contracts](../packages/quds_office_engine/test/office_vba_powerpoint_layout_test.dart)
and [native integration regressions](../packages/quds_office_engine/test/office_vba_powerpoint_layout_integration_test.dart)
for exact mappings, partial writes, source namespaces, empty/same-value intent,
opaque containers, rollback, policy, and recording. These checks pass in the
final combined local gate. The actual slideshow example also passes native
transactions and repeated save/reopen on VM and compiled JavaScript with identical
semantic results. See the
[continuation execution record](validation/office-vba-continuation-20261120/README.md)
for source hashes, raw results and qualification boundaries.
Specification-derived expectations are separate from observed Office-host
fixtures; no installed Microsoft PowerPoint results are claimed.

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

- [TextFrame.VerticalAnchor](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.textframe.verticalanchor) and [MsoVerticalAnchor](https://learn.microsoft.com/en-us/office/vba/api/office.msoverticalanchor): anchor property and exact enum values.
- [TextFrame.MarginLeft](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.textframe.marginleft) and [TextFrame.MarginBottom](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.textframe.marginbottom): margin units. [DrawingML LeftInset](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.bodyproperties.leftinset) describes the native attribute and its default.
- [SlideShowTransition](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slideshowtransition), [Hidden](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slideshowtransition.hidden), and [AdvanceOnClick](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slideshowtransition.advanceonclick): slide visibility and click-advance properties.
- [SlideShowTransition.Duration](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slideshowtransition.duration): duration measured in seconds.
- [PpEntryEffect](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.ppentryeffect): exact effect constants.
- [MS-PPTX slide transition extensions](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/22ebe6b5-2ade-43d9-977a-98fa194725c2) and [Microsoft's transition example](https://learn.microsoft.com/en-us/office/open-xml/presentation/how-to-add-transitions-between-slides-in-a-presentation): native transition and markup-compatibility container structure.
- [ECMA-376 Part 3](https://ecma-international.org/publications-and-standards/standards/ecma-376/): markup compatibility and extensibility rules.
