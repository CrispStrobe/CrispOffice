# VBA compatibility roadmap

The long-term target is Microsoft Office VBA compatibility across Word, Excel,
and PowerPoint. Compatibility is measured separately for the language, each
application's object model, document/package fidelity, and the host experience.
Passing one layer does not establish parity in the others.

## Current baseline

As of 20 November 2026, native JSON macros and the shared operation catalog
cover all three document families. The `vba-excel` source compiler supports a
bounded, document-independent subset: scalar expressions, typed locals,
explicit worksheet/range bindings, reusable `ByVal` procedures and scalar
functions, conditions, loops, fixed and dynamic one-dimensional arrays, `ReDim`/`Preserve`,
`Erase`, module `Option Base`, `For Each`, and the bounded String intrinsics
`Len`, `Left$`, `Right$`, and `Mid$`. Scalar Variants now support explicit
`Empty`/`Null`, state predicates and bounded `CVar`/`CBool`/`CDbl`/`CLng`/`CStr`
conversions, including default array/function behavior and native Empty clears.
It generates an immutable native plan; runtime policy, detached validation,
and atomic publication apply after compilation. Embedded VBA projects are
preserved as opaque package parts and are never executed on document open.

The `vba-word` adapter shares that language implementation and adds explicit
`ThisDocument`/paragraph/range bindings, paragraph-prefix insertion, supported
font properties, all 18 underline styles, strikethrough, paragraph
alignment/spacing, signed indentation and pagination. It emits native Word
operations and keeps paragraph marks structural. This is an initial write-only
Word object-model slice; stories, tables, arbitrary text ranges and live reads
remain separate work. The `vba-powerpoint` adapter adds explicit presentation,
slide, shape and text-range bindings, one-based/index-or-name selection,
whole-shape text, font/alignment writes and geometry. Native collection guards
refuse grouped or incompletely modeled slide collections. Rich text formatting
retains source XML, fields and hyperlinks; explicit false and same-value
assignments still take effect.
There is no live document-value evaluation, VBA project loader, editor-host
macro UI, or general VBA runtime. See the exact [Excel](VBA_MACROS.md) and
[Word](VBA_WORD_MACROS.md) and [PowerPoint](VBA_POWERPOINT_MACROS.md) contracts
and [the native macro contract](MACROS.md).

## Ordered milestones and acceptance

| Stage | Concrete deliverable | Acceptance required before claiming support |
| --- | --- | --- |
| 1. Source-data array lifecycle | Local dynamic arrays, `ReDim`, `Preserve`, `Erase`, `Option Base`; reuse fixed-array indexing and iteration | Typed defaults, preserve/shrink/regrow semantics, unallocated diagnostics, enumeration locks, shared resource budgets, CLI/MCP transaction tests, VM/JavaScript agreement |
| 2. Shared language semantics | String/numeric intrinsics, explicit Variant states and coercion rules, optional/named arguments, multidimensional arrays and array parameters | A versioned feature matrix tied to Microsoft language documentation; positive and refusal cases; differential fixtures from a real Office host for behavior claimed as compatible |
| 3. Document-aware execution | Separate a checked program from execution; resolve reads/writes against one detached transaction | Read-after-write and data-dependent branches, cancellation, instruction/resource limits, stale-document checks, whole-run rollback; no partial publication on error |
| 4. Application adapters | Excel workbook/sheet/range reads and collections; Word documents/stories/ranges/paragraphs/tables; PowerPoint presentations/slides/shapes/text ranges | One-based selectors, default members, collection order, object identity, explicit active-document context, precise range offsets/units, correct native serialization, format-specific conformance fixtures |
| 5. Procedures and projects | `ByRef`, modules/classes, properties, scoped globals, error handling, events and project references | Binding and aliasing tests, recursion/call budgets, error propagation, lifecycle tests, multi-module compatibility corpus; controlled host entry points |
| 6. Project interchange and authoring | Read/write project streams, explicit import/export, source editor, diagnostics, debugging and macro recording | Round-trip preservation, module/source provenance, source maps, breakpoints, consistent undo/history integration; successful Office open/edit/save checks |
| 7. Host integration and qualification | Common Office workflows and explicit platform integrations | Real Word/Excel/PowerPoint differential runs, version/platform matrix, supported workflow corpus and documented residual gaps; external automation stays subject to host capability grants |

Stage 1 was delivered in the prior array-lifecycle increment. Its source, CLI/MCP transaction and
VM/JavaScript checks are recorded in the
[local validation record](validation/office-vba-dynamic-arrays-20261119/README.md).
This establishes the documented bounded dialect, not differential qualification
against an installed Microsoft Office host. Stage 2 now has two bounded
slices: a [versioned conformance format](VBA_CONFORMANCE.md) and these four
String intrinsics, with explicit type restrictions, UTF-16 units, copy-work
accounting, transactional integration, and VM/JavaScript agreement; followed
by explicit Variant states and conversions with independently authored
conformance expectations, shared budgets, and the same transaction boundary.
Locale-sensitive coercions, numeric subtype identity, `Nothing`, and remaining
Stage 2 semantics and Stage 3 remain planned work. Stage 4 now has the initial
source-only Word paragraph adapter above; its remaining application models and
Stages 5–7 remain planned work.
Small tested adapter slices may run alongside shared language work when their
prerequisites exist.

The current Word/PowerPoint increment adds the Stage 4 write-only slices above
without introducing Stage 3 document reads. Its exact branch integration,
VM/JavaScript, native transaction and CLI/MCP evidence is retained in the
[20 November qualification record](validation/office-vba-word-powerpoint-20261120/README.md).
Groups, arbitrary text subranges, Word stories/tables, and live collection
behavior remain separate increments with their own identity and range tests.

### Qualified Word and PowerPoint continuation

The `codex/word-powerpoint-vba-continuation-20261120` branch extends the Word
slice with active-document aliases, `Paragraphs.Item`, small caps,
superscript/subscript and fixed-palette highlighting. PowerPoint gains typed
text-frame/font/paragraph-format/transition bindings, top/middle/bottom anchors,
slide visibility, click advancing, duration and eleven entry-effect constants.
These remain source-to-plan writes; no document-content reads are introduced.

The intake reconciles the captured fork/PR snapshots and upstream ancestry.
The final local gate passes 2,190 cases across 64 files, strict engine
analysis, and the actual examples on VM and compiled JavaScript with matching
results. Source hashes remain unchanged through qualification. Earlier disk
failures are retained separately. This qualifies the bounded headless engine;
Flutter UI and installed Office hosts remain unexecuted. See the
[continuation record](validation/office-vba-continuation-20261120/README.md).
Full AllCaps rendering, paint provenance for Fill/Line writes, baseline text
anchors and broader slideshow behavior remain separate work.

### Named helpers and further Word/PowerPoint formatting

The expansion adds case-insensitive named arguments and optional scalar
`ByVal` parameters for declared module helpers. Supplied arguments evaluate in
source order; defaults are checked in module scope, including unused helpers.
An omitted optional Variant is distinct from Empty and Null and can be tested
with bounded `IsMissing`. Named/omitted arguments on intrinsic or application
members, optional objects, ByRef, and general Variant Error propagation remain
unsupported. See the exact [argument contract](VBA_ARGUMENTS.md).

Word adds typed Font/ParagraphFormat aliases and helpers, Paragraph.Format,
explicit reading order, and single/1.5/double line-spacing presets. Granular
spacing ownership preserves unedited native attributes and inheritance;
foreign or nested layout properties remain opaque during projection.
PowerPoint adds four precise text-frame margins, independent native ownership,
and inset placement in PDF and the live model. Direct bodyPr values are
projected; layout/master margin inheritance remains outside this rendering
slice. The [expansion record](validation/office-vba-expansion-20261120/README.md)
documents executed qualification separately from inherited or unexecuted work.

### Custom Word tab stops

The Word tab-stop increment adds typed `TabStops` selectors and required
`ByVal` helpers, statement `Add` with named/optional arguments, and `ClearAll`.
Native edits preserve untouched direct/inherited stops and opaque XML, and
clear inherited custom stops with position-specific overrides. This remains a
source-to-plan slice: no collection reads, `TabStop` return objects, arbitrary
Word ranges or live execution were added. See the
[exact contract](VBA_WORD_MACROS.md#custom-paragraph-tab-stops) and
[source-bound local qualification](validation/word-vba-tabstops-20261120/README.md).

### Custom Word line spacing

The Word spacing continuation adds exact, minimum and custom multiple spacing
through explicit `LineSpacingRule` / `LineSpacing` pairs, standard `Space1`,
`Space15`, `Space2` methods and document-independent line/point conversions.
Each complete pair lowers to one guarded native edit; unpaired setters and
intervening document writes are refused. This deliberately bounded contract
does not introduce live spacing reads or infer existing font metrics. See the
[exact contract](VBA_WORD_MACROS.md#exact-minimum-and-multiple-line-spacing)
and [local qualification](validation/word-vba-paragraph-spacing-20261120/README.md).

### Paragraph spacing controls

The paragraph-controls continuation adds `OpenUp`, `CloseUp` and
`OpenOrCloseUp` on `Paragraph` and `ParagraphFormat`. The native operation
resolves each toggle against the detached document after earlier plan edits;
no document value is exposed to source expressions. Sparse before ownership
preserves after/line inheritance, and conservative source guards refuse
unmodeled automatic/line-based spacing and ambiguous styles. Default paragraph
styles now recognize native Boolean flags and native namespace identities.
This continuation also qualifies the incoming custom spacing work described
below. See the [exact contract](VBA_WORD_MACROS.md#opening-closing-and-toggling-paragraph-spacing)
and [local evidence](validation/word-vba-paragraph-controls-20261120/README.md).

### Next shared-language increments

Keep multidimensional arrays and array parameter passing as separate increments
with their own shape, ownership, aliasing and resource tests. Broader implicit
coercions, locale handling and numeric subtype reporting also need explicit
contracts; this increment's invariant conversions do not establish those.
Continue distinguishing specification-derived expectations, dialect restrictions
and actual Office-host observations in the versioned corpus. Stage 3 remains
the architectural prerequisite for macros that branch on existing workbook
data; additional source-only syntax does not supply that capability.

## Architecture decisions

- Keep a single shared language parser, binder, diagnostics model and resource
  accounting. Host object models supply typed members and native operations;
  avoid three independent language implementations.
- Preserve the existing source-to-plan API for static macros. Document-aware
  programs need a distinct execution representation: extending the static
  compiler with live reads would erase its current no-document-access contract.
- Model VBA behavior explicitly. Refuse an unsupported construct with its
  source position rather than silently borrowing Dart behavior. Numeric
  subtypes, `Empty`/`Null`/`Nothing`, locale rules and Unicode indexing need
  their own compatibility fixtures.
- Treat Word ranges and PowerPoint text as application-specific objects.
  A Word paragraph range includes a paragraph mark; mapping it blindly to a
  plain-text replacement can change document structure. Rich-text formatting,
  table cells, stories and slide shape collections need explicit contracts.
- Continue to use the shared native operation catalog and detached publication
  boundary for every adapter. Macro syntax cannot grant itself filesystem,
  network, shell, COM or application-event access.

## Working protocol

Begin each increment by refreshing remote main, current branches and recent
PR heads. Classify each head as contained, equivalent with recorded evidence,
or needing integration. Preserve newer independent work and real Git ancestry.
Save small remote branch checkpoints with expected-head, non-forced updates.
Run targeted local gates and record actual commands/results and the source
they cover. GitHub Actions are not a gate for this work. Refresh main again
before the final merge and rerun checks affected by any concurrent source.

Do not report a percentage of VBA parity from test counts or operation counts.
Report supported features, tested hosts and explicit missing behavior instead.

## Primary references

- [Microsoft VBA language specification (MS-VBAL)](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/)
- [ReDim statement](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/redim-statement)
- [Erase statement](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/erase-statement)
- [Option Base statement](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/option-base-statement)
