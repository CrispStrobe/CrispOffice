# VBA compatibility roadmap

The long-term target is Microsoft Office VBA compatibility across Word, Excel,
and PowerPoint. Compatibility is measured separately for the language, each
application's object model, document/package fidelity, and the host experience.
Passing one layer does not establish parity in the others.

## Current baseline

As of 22 November 2026, native JSON macros and the shared operation catalog
cover all three document families. The `vba-excel` source compiler supports a
bounded, document-independent subset: scalar expressions, typed locals,
explicit worksheet/range bindings, reusable `ByVal` procedures and scalar
functions, conditions, loops, fixed and dynamic one-dimensional arrays, `ReDim`/`Preserve`,
`Erase`, module `Option Base`, `For Each`, and the bounded String intrinsics
`Len`, `Left`/`Left$`, `Right`/`Right$`, `Mid`/`Mid$`, and `Join` over allocated local String arrays.
The unsuffixed substring forms additionally preserve Null and treat Empty as
an empty String, under the existing strict index and work limits.
Standalone `Mid` / `Mid$` assignment also replaces a span of a mutable local
String or String-valued Variant, including allocated array elements, without
changing its length.
Direct `Split` assignment now fills or replaces a local dynamic String array
from source text, with zero-based binary results and the existing array budgets.
Scalar Variants now support explicit
`Empty`/`Null`, state predicates and bounded `CVar`/`CBool`/`CDbl`/`CLng`/`CStr`
conversions, including default array/function behavior and native Empty clears.
It generates an immutable native plan; runtime policy, detached validation,
and atomic publication apply after compilation. Embedded VBA projects are
preserved as opaque package parts and are never executed on document open.

The `vba-word` adapter shares that language implementation and adds explicit
`ThisDocument`/paragraph/range bindings, paragraph-prefix insertion, supported
font properties, all 18 underline styles, strikethrough, paragraph
alignment/spacing, signed indentation and pagination. Explicit `Section` and
`PageSetup` selectors additionally set page width/height, four margins and
header/footer distances on one existing section, plus portrait/landscape
orientation, toggling and four section-start modes. It emits native Word
operations and keeps paragraph marks structural. This is a bounded write-only
Word object-model slice. Explicit independent header/footer paragraphs now reuse
its insertion and formatting operations; linked stories, arbitrary text
ranges and live reads remain separate work. Existing plain, single-paragraph
table cells support `Range.Text`, `Range.Font` and `Range.ParagraphFormat`,
including paragraph spacing and tabs, through guarded main-story selectors.
Typed `Rows`, `Row`, `Columns`, `Column` and row/column `Cells` navigation
now selects those same cells, with required named indexes and `Table.Cell`
coordinates, retained aliases and typed helpers. Their current text also accepts direct highlighting, proofing exclusion and
mapped normal-slot language setters through the same cell-aware native guards.
Explicit `Cell.Range.Paragraphs(1)` / `.Paragraphs.Item(1)` selectors now apply
existing paragraph styles and solid background shading, including on empty
ordinary paragraphs, with retained cell identity. Cell prefix insertion now
retains original text/runs through a separate guarded operation. Direct cell
`InsertAfter` now appends through its own guarded operation, retaining current
range identity and end formatting. Standard
portable String constants support source cleanup before publication.
The `vba-powerpoint` adapter adds explicit presentation,
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

The current source-text continuation adds `StrReverse` across all three
adapters. It reverses source-known UTF-16 units with strict String/Variant
payload handling, Empty/Null semantics, once-only evaluation and preallocation
work charging. Word can use it with the existing table, paragraph and story
operations; the native mutation and document-admission envelope is unchanged.

The [complete Word import](../packages/quds_office_engine/example/macros/word_reverse_import.bas),
[26-case corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/strreverse_v1.json),
[exact contract](vba-macros-details.md#reversing-source-strings) and
[review/execution record](validation/word-vba-source-text-20261122/README.md)
define the increment. Regression tests are authored but unexecuted because
the local checkout exhausted workspace capacity. Source inspection and
JavaScript oracle checks are not Dart/compiler or installed Office acceptance.
This extends Stage 2 syntax; it does not add Stage 3 document reads, grapheme
processing or general String coercion.

The preceding continuation adds direct `Split` assignment to local dynamic
String arrays across all three adapters. It supports binary UTF-16 delimiters,
optional result limits, retained empty fields and allocated empty arrays.
Source arguments evaluate once in written order while the old array remains
readable; replacement preserves frame ownership, active enumeration locks and
shared String/slot/work budgets. General array values and live document reads
remain separate work. This advances the source-language part of Stage 2.

The [complete delimited Word report](../packages/quds_office_engine/example/macros/word_split_report.bas),
[independent corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/split_v1.json),
[exact contract](vba-macros-details.md#splitting-source-string-arrays) and
[local qualification](validation/word-vba-split-20261122/README.md) define the
increment. Existing native Word operations handle the resulting table writes;
document admission and embedded VBA behavior are unchanged. Named/omitted
intrinsic arguments, locale comparison, general array passing/returning and
installed Office differential acceptance remain separate milestones.

The preceding continuation adds ordinary Variant-returning `Left`, `Right` and
expression `Mid`, required named `Index` arguments on Word body/story/section
selectors, and typed `Sections`/`Paragraphs` collection aliases and `ByVal`
helpers. Existing UTF-16 slices, exact-index checks, source-order evaluation,
cell/story origins and native transactions remain shared. Cell-origin checks
follow alias cycles before admitting projected list operations, including
inactive source. This advances bounded Stages 2 and 4.

The [complete reference-label BAS](../packages/quds_office_engine/example/macros/word_text_selectors.bas),
[64-case independent corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/word_text_selectors_v1.json),
[String contract](vba-macros-details.md#string-intrinsics),
[selector contract](vba-word-macros-details.md#named-document-and-story-selectors)
and [local qualification](validation/word-vba-text-selectors-20261122/README.md)
define this increment. Full coercion, named intrinsic arguments, document
reads/enumeration and installed Office differential qualification remain
separate work.

The preceding continuation adds source-only `Mid` / `Mid$` assignment for fixed-width
labels and template data. Local String/Variant variables, allocated String/Variant
array elements, `ByVal` helper parameters and function results retain their
existing ownership. Target/index, start, length and replacement are evaluated
once in source order. Bounded UTF-16 replacement never grows the target, and
copy work is charged before allocation. Strict types, inactive-source checks,
array accounting and native publication guards remain shared across adapters.

The [complete BAS](../packages/quds_office_engine/example/macros/word_fixed_width_labels.bas),
[independent corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/mid_assignment_v1.json),
[exact contract](vba-macros-details.md#replacing-part-of-a-source-string) and
[local qualification](validation/word-vba-mid-assignment-20261122/README.md)
define this Stage 2 increment. Property lvalues, byte-mode edits, implicit String
coercion, live document reads and installed Office differential acceptance
remain separate work.

The preceding continuation adds typed table row/column navigation. `Rows`, `Row`,
`Columns`, `Column` and `Cells` bindings retain their selected table and axis
through aliases, nested `With` and required `ByVal` helpers. Direct collection
selection and `Item` accept required named `Index` values, including `Tables`;
`Table.Cell` accepts required named `Row` and `Column` in either written order.
Receiver and argument evaluation remains once-only and ordered. Strict index,
type, origin and resource boundaries stay shared with the existing compiler.

The resulting cells lower to the existing guarded text, prefix/suffix,
formatting and projected-paragraph operations. No native mutation or document
admission envelope is widened. Collection reads/counts, enumeration,
whole-row/column ranges, merged-cell indexing and document-aware execution
remain separate work. The [complete BAS](../packages/quds_office_engine/example/macros/word_table_navigation.bas),
[32-case corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/word_table_navigation_v1.json),
[selector contract](vba-word-macros-details.md#table-row-and-column-navigation)
and [local qualification](validation/word-vba-table-navigation-20261122/README.md)
define this bounded Stage 4 extension, separately from installed Word acceptance.

The preceding continuation adds shared integer division (`\`) and signed
remainder (`Mod`) for source-known grouping and template calculations in Word,
Excel and PowerPoint. It preserves VBA precedence, left-to-right evaluation,
strict numeric/Variant operands, Empty/Null behavior and compilation budgets.
Operands use the existing ties-to-even Long conversion boundary; zero divisors
and overflow refuse publication. The complete grouped Word BAS combines
calculated table selectors, direct suffixes, named helpers and alternating
formatting under the ordinary native transaction. This advances Stage 2.

The [exact contract](vba-macros-details.md#integer-division-and-remainder),
[54-case corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/word_integer_arithmetic_v1.json)
and [local record](validation/word-vba-integer-arithmetic-20261122/README.md)
distinguish deterministic Quds behavior from installed Office qualification.
Signed Mod deliberately follows the dividend-signed formula, while MS-VBAL's
absolute-remainder wording is recorded as an unresolved source discrepancy.
Full numeric subtype coercion, live document reads and embedded VBA execution
remain separate work.

The preceding continuation adds direct `Cell.Range.InsertAfter`, including
required named `Text:=`, typed aliases, nested `With` and named `ByVal` helpers.
The dedicated native append operation preserves original characters, run
boundaries, kerning and zero-width metadata, while keeping cell and paragraph
delimiters structural. It inherits last-character formatting; empty cells use
the last retained empty run or paragraph-mark formatting. Subsequent formatting
through the retained cell Range includes appended text. Empty suffixes still
validate, and failed runs retain atomic publication and recording boundaries.

Static direct-cell origin checks now follow complete local alias graphs,
admitting rooted cell-only cycles while refusing any noncell origin and
rootless cycles. Actual generic helper receivers remain checked during source
evaluation. Projected cell paragraph ranges and body/header/footer paragraph
`InsertAfter` remain explicitly unsupported because their paragraph-mark
semantics differ from direct cell insertion.

This advances the bounded Stage 4 adapter. The
[complete BAS](../packages/quds_office_engine/example/macros/word_table_suffix.bas),
[independent corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/word_cell_suffix_v1.json),
[append contract](vba-word-macros-details.md#appending-existing-cell-text) and
[local qualification](validation/word-vba-cell-suffix-20261122/README.md)
define the scope. Live reads, arbitrary ranges, structural insertion,
broader table structures and installed Word differential acceptance remain
separate milestones.

The preceding continuation adds `Cell.Range.InsertBefore` and selected cell
paragraph `Range.InsertBefore`, plus named `Text:=` on supported Word ranges.
A dedicated native operation preserves all original runs and sparse metadata,
including distinct kerning and zero-width properties, without changing table
admission or generic replacement offsets. Captured aliases/helpers retain their
cell; formatting after insertion includes the prefix. Empty prefixes still
validate, and late failures retain atomic publication and recording boundaries.

Shared source constants `vbTab`, `vbCr`, `vbLf`, `vbCrLf`, `vbBack`, `vbFormFeed`,
`vbVerticalTab` and `vbNullChar` add their fixed String values to all adapters,
including Const expressions and optional defaults. Native Word control-character
refusals remain unchanged. Host-dependent or external-call sentinel constants
remain separate work.

This advances Stages 2 and 4. The [complete BAS](../packages/quds_office_engine/example/macros/word_table_prefix.bas),
[independent corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/word_cell_prefix_v1.json),
[exact contract](vba-word-macros-details.md#prefixing-existing-cell-text), and
[local record](validation/word-vba-cell-prefix-20261122/README.md) define the
qualified scope. Live reads, arbitrary ranges, structural insertion, broader
cell structures and installed Office differential acceptance remain separate.

The preceding continuation adds explicit `Cell.Range.Paragraphs(1)` and
`.Paragraphs.Item(1)` selection with paragraph Style and background Shading.
It reuses existing guarded native operations rather than broadening the table
grid or content envelope. Paragraph/Range/Shading aliases and named `ByVal`
helpers retain the original cell; empty paragraphs accept style/background
writes without new text. Sparse XML ownership, direct formatting, unrelated
cells and opaque VBA parts survive save/reopen. Cell-paragraph `InsertAfter`
and list operations remain rejected in inactive source as well as executed paths.

This advances the bounded Stage 4 adapter. The independently authored corpus,
complete BAS example, native serialization and CLI/MCP transaction checks are
recorded in the [cell paragraph contract](vba-word-macros-details.md#formatting-a-cell-paragraph)
and [local qualification](validation/word-vba-cell-paragraphs-20261122/README.md).
Multiple cell paragraphs, merged/nested table support, live collection reads,
arbitrary subranges and installed Office differential qualification remain
separate work.

The preceding continuation adds direct `Cell.Range.HighlightColorIndex`,
`NoProofing`, `LanguageID` and `LanguageIDOther` writes, plus shared source-only
`Join` for allocated local String arrays. The Word writes reuse guarded native
run formatting with retained table/row/column identity, detached property
copies and whole-run rollback. They affect current nonempty ordinary text,
preserve paragraph/cell marks and other language slots, and retain existing
grid/content/protection refusals. Source-only Join preserves array order and
empty slots, supports fixed/dynamic array lifecycle and explicit separators,
and meters array visits and copied text before allocating the result.

This advances Stage 2 and the bounded Stage 4 adapter. The independent Join
corpus distinguishes primary-source expectations from explicit dialect
restrictions, and the complete multilingual table example combines both
capabilities through CLI/MCP/native transactions. See the
[Join contract](vba-macros-details.md#joining-source-string-arrays),
[cell text controls](vba-word-macros-details.md#cell-highlighting-and-proofing-controls),
[combined report](../packages/quds_office_engine/example/macros/word_join_report.bas)
and [local qualification](validation/word-vba-cell-text-20261122/README.md).
Live document reads, multidimensional/Variant-array joining, array parameters,
embedded VBA execution and installed Office differential qualification remain
separate work.

The preceding Word continuation adds `Cell.Range.Font` and
`Cell.Range.ParagraphFormat` to the existing guarded table text workflow. It
reuses the bounded font and paragraph member contracts, line-spacing pairs,
spacing-control methods and paragraph tab operations. Typed aliases and named
`ByVal` helpers retain table/row/column identity; native plans carry an explicit
`tableCell` selector and preserve the ordinary atomic transaction.

Font writes affect current nonempty ordinary text and exclude paragraph/cell
marks and future insertion formatting. Paragraph formatting can target an empty
cell paragraph. Detached run formatting prevents shared public-model properties
from affecting unrelated cells. The existing unmerged-grid, single-paragraph,
source-fidelity and protection restrictions stay in force. Direct cell-range
style/shading/list members, insertion, subranges, collection reads and embedded
execution remain outside that formatting increment. Direct proofing/language
and highlighting setters are added by the preceding continuation above.

This advances the bounded Stage 4 application adapter. See the
[cell-formatting contract](vba-word-macros-details.md#formatting-existing-table-cells),
[runnable 2×2 report](../packages/quds_office_engine/example/macros/word_table_formatting.bas)
and [local qualification](validation/word-vba-cell-formatting-20261122/README.md).
The record separates executed local checks from installed Word differential
qualification; Stage 3 document-aware execution remains separate work.

The preceding source-language continuation adds binary `StrComp` with exact
comparison results, explicit Empty/Null semantics and metered UTF-16 scans in
all three adapters. Word gains the fixed `Font.ColorIndex` palette and both
automatic foreground setters, retaining native automatic identity, explicit
style/theme overrides and sparse source metadata. This advances Stage 2 and
the bounded Stage 4 adapter together: a complete report/template example uses
source-data comparisons to choose paragraph/header/footer colors and fill
existing table cells through the current native transaction.

The [comparison contract](vba-macros-details.md#binary-string-comparison),
[foreground contract](vba-word-macros-details.md#font-palette-and-automatic-foreground)
and [local qualification](validation/word-vba-comparison-colors-20261121/README.md)
record supported cases and refusals. Locale comparison, implicit coercion,
live document reads and installed Office differential runs
remain separate milestones. No new rendering policy or embedded VBA host is
introduced.

The preceding Word object-model continuation adds explicit `Tables`, `Table`,
`Cell` and cell-range bindings with `Cell.Range.Text` assignment. Existing
plain, single-paragraph cells in supported unmerged main-story tables can be
filled using local arrays, loops and typed helpers. A separate guarded native
operation preserves structural ownership and formatting while retaining atomic
validation/publication. This advances Stage 4 without introducing document
reads, arbitrary range mutation, merged/nested-table semantics or embedded
project execution. See the [table-cell contract](vba-word-macros-details.md#filling-existing-table-cells)
and [local qualification](validation/word-vba-table-cells-20261121/README.md).

The preceding shared-language continuation adds `Abs`, `Int`, `Fix` and `Sgn`
for source-known numeric calculations in Word, Excel and PowerPoint. It advances
Stage 2 with explicit Empty/Null behavior, negative-floor versus truncation
semantics, strict coercion limits and portable numeric bounds. Word macros can
use these results in existing paragraph selectors, typography and indentation
operations. The runnable numeric report and versioned corpus exercise the
existing atomic native transaction; this does not introduce document reads,
VBA numeric subtype identity or installed-Office differential qualification.
See the [numeric contract](vba-macros-details.md#numeric-intrinsics) and
[local qualification](validation/word-vba-numeric-20261121/README.md).

The preceding bounded continuation adds Word `Font.Position` writes, native signed
half-point DOCX ownership, automatic/minimum line extents and independent
baseline rendering through editor and PDF paths. It retains the existing
typed aliases, helpers, explicit story selectors and atomic plan boundary.
See the [position contract](vba-word-macros-details.md#baseline-position-without-resizing-text)
and [local qualification](validation/word-vba-typography-20261121/README.md).

The preceding formatting continuation adds typed Word `Shading` objects for selected
paragraph backgrounds, two background-color setters and named `WdColor`
constants, with sparse native ownership and explicit automatic overrides.
The shared source language adds `Space`/`String` construction and
`ChrW`/`AscW` UTF-16 operations. These extend Stages 2 and 4 using the same
compile-to-plan boundary; document reads, live execution and embedded VBA
projects remain separate milestones. See the
[shading contract](vba-word-macros-details.md#paragraph-background-shading),
[text-construction contract](vba-macros-details.md#text-construction-and-unicode-code-units),
and [source-specific local qualification](validation/word-vba-format-controls-20261121/README.md).

| Stage | Concrete deliverable | Acceptance required before claiming support |
| --- | --- | --- |
| 1. Source-data array lifecycle | Local dynamic arrays, `ReDim`, `Preserve`, `Erase`, `Option Base`; reuse fixed-array indexing and iteration | Typed defaults, preserve/shrink/regrow semantics, unallocated diagnostics, enumeration locks, shared resource budgets, CLI/MCP transaction tests, VM/JavaScript agreement |
| 2. Shared language semantics | String/numeric intrinsics, explicit Variant states and coercion rules, optional/named arguments, multidimensional arrays and array parameters | A versioned feature matrix tied to Microsoft language documentation; positive and refusal cases; differential fixtures from a real Office host for behavior claimed as compatible |
| 3. Document-aware execution | Separate a checked program from execution; resolve reads/writes against one detached transaction | Read-after-write and data-dependent branches, cancellation, instruction/resource limits, stale-document checks, whole-run rollback; no partial publication on error |
| 4. Application adapters | Excel workbook/sheet/range reads and collections; Word documents/sections/page setup/stories/ranges/paragraphs/tables; PowerPoint presentations/slides/shapes/text ranges | One-based selectors, default members, collection order, object identity, explicit active-document context, precise range offsets/units, correct native serialization, format-specific conformance fixtures |
| 5. Procedures and projects | `ByRef`, modules/classes, properties, scoped globals, error handling, events and project references | Binding and aliasing tests, recursion/call budgets, error propagation, lifecycle tests, multi-module compatibility corpus; controlled host entry points |
| 6. Project interchange and authoring | Read/write project streams, explicit import/export, source editor, diagnostics, debugging and macro recording | Round-trip preservation, module/source provenance, source maps, breakpoints, consistent undo/history integration; successful Office open/edit/save checks |
| 7. Host integration and qualification | Common Office workflows and explicit platform integrations | Real Word/Excel/PowerPoint differential runs, version/platform matrix, supported workflow corpus and documented residual gaps; external automation stays subject to host capability grants |

Stage 1 was delivered in the prior array-lifecycle increment. Its source, CLI/MCP transaction and
VM/JavaScript checks are recorded in the
[local validation record](validation/office-vba-dynamic-arrays-20261119/README.md).
This establishes the documented bounded dialect, not differential qualification
against an installed Microsoft Office host. Stage 2 includes a
[versioned conformance format](VBA_CONFORMANCE.md) and the original four
String intrinsics, with explicit type restrictions, UTF-16 units, copy-work
accounting, transactional integration, and VM/JavaScript agreement; followed
by explicit Variant states and conversions with independently authored
conformance expectations, shared budgets, and the same transaction boundary.
The text-search, replacement and trimming continuation below extends the
shared source String layer.
Locale-sensitive coercions, numeric subtype identity, `Nothing`, and remaining
Stage 2 semantics and Stage 3 remain planned work. Stage 4 now has the initial
source-only Word paragraph and section adapters above; their remaining application models and
Stages 5–7 remain planned work.
Small tested adapter slices may run alongside shared language work when their
prerequisites exist.

The current Word/PowerPoint increment adds the Stage 4 write-only slices above
without introducing Stage 3 document reads. Its exact branch integration,
VM/JavaScript, native transaction and CLI/MCP evidence is retained in the
[20 November qualification record](validation/office-vba-word-powerpoint-20261120/README.md).
Groups, arbitrary text subranges, broader Word stories/tables, and live collection
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
Full AllCaps rendering was subsequently added in the continuation below.
Paint provenance for Fill/Line writes, baseline text anchors and broader
slideshow behavior remain separate work.

### Named helpers and further Word/PowerPoint formatting

The expansion adds case-insensitive named arguments and optional scalar
`ByVal` parameters for declared module helpers. Supplied arguments evaluate in
source order; defaults are checked in module scope, including unused helpers.
An omitted optional Variant is distinct from Empty and Null and can be tested
with bounded `IsMissing`. That increment did not add named or omitted arguments
on intrinsic or application members. Later application-specific exceptions are
documented in the [argument contract](VBA_ARGUMENTS.md). Optional objects,
ByRef and general Variant Error propagation remain unsupported.

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
[exact contract](vba-word-macros-details.md#custom-paragraph-tab-stops) and
[source-bound local qualification](validation/word-vba-tabstops-20261120/README.md).

### Custom Word line spacing

The Word spacing continuation adds exact, minimum and custom multiple spacing
through explicit `LineSpacingRule` / `LineSpacing` pairs, standard `Space1`,
`Space15`, `Space2` methods and document-independent line/point conversions.
Each complete pair lowers to one guarded native edit; unpaired setters and
intervening document writes are refused. This deliberately bounded contract
does not introduce live spacing reads or infer existing font metrics. See the
[exact contract](vba-word-macros-details.md#exact-minimum-and-multiple-line-spacing)
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
below. See the [exact contract](vba-word-macros-details.md#opening-closing-and-toggling-paragraph-spacing)
and [local evidence](validation/word-vba-paragraph-controls-20261120/README.md).

### Physical Word measurements

The Word measurement continuation adds inches, centimeters, millimeters and
picas in both directions, and official named arguments for all ten unit
conversions, including the existing line/point functions. It uses exact physical
ratios with bounded Double arithmetic and exact native-grid canonicalization;
it does not emulate VBA Single rounding or loosen property precision guards.
The complete BAS examples and source/integration checks cover document
publication, CLI/MCP paths and the portable numeric contract. The combined
source has local Dart acceptance; earlier arithmetic-model and authored
JavaScript checks retain their separate execution status. See the
[measurement contract](vba-word-macros-details.md#physical-measurement-conversions)
and [combined-source qualification](validation/zotero-merged-cells-20261120/intake.md).
The incoming Mail continuation additionally qualified the named-argument
example and original eight-, nine- and thirteen-operation examples on the
VM and JavaScript; see its [source-specific record](validation/mail-bulk-actions-20261120/intake-local-word-final.md).
Later publication evidence remains available in the [Mail/Word main record](validation/mail-bulk-actions-20261120/final-main-word-summary.md) and [Word main integration record](validation/word-main-integration-20261120/README.md).

### Explicit Word section page setup

The section continuation adds typed `Section` and `PageSetup` selectors through
`Document.Sections(i)` / `.Sections.Item(i)`, with `With`, aliases, and required
`ByVal` helpers. Eight write-only geometry properties lower to the dedicated
`docx.pageSetup` operation: page width/height, four margins, and header/footer
distances. Source numbers retain exact twentieth-point checks and bounded
Double arithmetic; VBA Single rounding, `PaperSize`, broadcast page setup and
geometry reads remain outside this slice. Orientation and section starts are
extended by the following continuation.

Native execution resolves each write against the detached section after
earlier operations, validates positive page-body/column text geometry, and
retains all-run rollback. Sparse XML ownership preserves unedited attributes,
namespace aliases and opaque DOCM parts. Width/height writes select custom
paper even when their values do not change. Unsupported source measurements,
gutters, duplicate geometry, custom columns, alternate section properties, and
mirrored/book-fold settings are refused before mutation. The
[exact contract](vba-word-macros-details.md#section-page-setup),
[complete BAS example](../packages/quds_office_engine/example/macros/word_page_setup.bas),
and [local qualification record](validation/word-vba-paragraph-pagination-20261121/README.md)
describe the supported engine behavior and executed source checks. This
increment does not establish installed Microsoft Word or Flutter validation
and does not add Stage 3 document-aware source execution.

### Word section orientation and starts

The next section slice adds `PageSetup.Orientation`, zero-argument
`TogglePortrait`, and four `SectionStart` modes through the existing explicit
section selectors. Portrait/landscape assignment and toggling use a dedicated
native action that swaps dimensions when needed while retaining named margins
and printer paper code. Square pages retain explicit orientation through
save/reopen. Continuous/new-page/even-page/odd-page starts update only the
native section-start attribute, with headless pagination coverage.

Both operations preserve the existing transaction, recording, policy and
resource boundaries. Ambiguous source identity or orientation is refused;
new-column starts, collection-wide settings and source property reads remain
unsupported. This is another Stage 4 source-to-plan slice, without Stage 3
document-dependent branching or installed Word differential qualification.
See the [exact contract](vba-word-macros-details.md#section-orientation-and-start-controls),
[BAS example](../packages/quds_office_engine/example/macros/word_sections.bas),
and [local qualification](validation/word-vba-sections-20261121/README.md).

### Existing paragraph style assignment

The Word adapter supports writable `Paragraph.Style` and a selected paragraph's
`Range.Style`, including typed aliases, `With` and required `ByVal` helpers.
Native execution resolves primary style names or 13 supported built-ins from
the active document styles part and updates a sparse paragraph style reference.
Direct formatting, character/table inheritance, previous plan edits, independent
header/footer ownership and transaction rollback are preserved. Missing or
ambiguous definitions and effective numbering changes are explicitly refused.

This is a Stage 4 source-to-plan increment. It does not add live style reads,
Style objects, collection enumeration, style creation or an embedded VBA host.
See the [contract](vba-word-macros-details.md#existing-paragraph-styles),
[BAS example](../packages/quds_office_engine/example/macros/word_styles.bas)
and [local qualification](validation/word-vba-styles-20261121/README.md).

### Uniform section text columns

The Word adapter extends explicit section page setup with typed `TextColumns`
selectors and `SetCount`, `Spacing` and `LineBetween` writes. Native execution
resolves each operation against the detached section, validates usable column
geometry and preserves unrelated sparse section XML, namespace aliases and
inert DOCM parts. Existing uniform layout and separator rendering consume the
updated model. Custom unequal columns remain guarded and unselected sections
remain untouched.

Typed aliases, required `ByVal` helpers, named `NumColumns`, nested `With` and
physical unit conversions are supported. The source contract requires exact
numeric counts/spacing and actual Booleans, without property reads, collection
iteration or a document-wide page-setup binding. This remains a Stage 4
source-to-plan increment; Stage 3 execution and installed Word differential
qualification are separate. See the
[exact contract](vba-word-macros-details.md#uniform-section-text-columns),
[two-section example](../packages/quds_office_engine/example/macros/word_text_columns.bas)
and [local qualification](validation/word-vba-text-columns-20261121/README.md).

### Independent header/footer paragraphs

The next Word adapter slice adds explicit section `Headers` / `Footers`, typed
`HeadersFooters` / `HeaderFooter` aliases and helpers, and all three
`WdHeaderFooterIndex` variants. `HeaderFooter.Range.Paragraphs(i)` selects an
existing paragraph for the supported insertion, formatting, tabs and spacing
operations. Native plans retain the complete section/story/paragraph identity,
including custom line-spacing pairing. Body-only list operations are refused
for these selectors.

Native paragraph selection requires direct independent story ownership and
refuses missing or opaque targets, ambiguous references, shared/inherited
header/footer topology and unmodeled content in rewritten paragraph stories
before mutation. Selected mutable model aliases are also refused. This is bounded source-to-plan support with the existing
atomic transaction and policy boundary. It does not implement linked-story
propagation, story creation, whole-story writes or document-aware source
execution. See the [exact contract](vba-word-macros-details.md#existing-header-and-footer-paragraphs),
[BAS example](../packages/quds_office_engine/example/macros/word_headers_footers.bas),
and [local qualification record](validation/word-vba-compatibility-20261121/README.md).

### Word proofing and kerning controls

The next source slice adds write-only `Range.NoProofing`,
`ParagraphFormat.Hyphenation`, and `Font.Kerning` through the existing paragraph
selectors. It reuses native proofing/hyphenation/kerning models, preserves
explicit false/zero inheritance overrides and foreign source metadata, and
retains detached validation and whole-run rollback. Hyphenation controls
paragraph inclusion without enabling the document setting. Run controls affect
selected current text, not paragraph-mark insertion formatting.

The source contract requires actual Booleans and exact half-point kerning
thresholds in `0..1638`. No document-dependent reads, mixed-value results,
general coercions, installed Word differential validation or new proofing
provider are implied. See the [exact contract](vba-word-macros-details.md#proofing-and-kerning-controls),
[BAS example](../packages/quds_office_engine/example/macros/word_proofing_controls.bas),
and [local record](validation/word-vba-proofing-20261121/README.md).

### Word proofing-language and complex-script font controls

The Word adapter also supports `Range.LanguageID` / `LanguageIDOther` for
30 explicitly mapped normal-slot language IDs and independent `Font.NameBi`
writes. Native language/font ownership is sparse per attribute group, including
theme removal for explicit font choices, same-value inheritance overrides and
preserved foreign metadata. Direct/style import ignores foreign or nested
lookalikes, and guarded operations refuse ambiguous source before mutation.
The existing transactional source-to-plan boundary remains unchanged.

This slice does not add complex-script/East Asian language routing, language
reads, installed dictionaries, complex-script size/bold/italic models or Stage 3
document-aware execution. See the [language/font contract](vba-word-macros-details.md#proofing-language-and-complex-script-font-controls),
[BAS example](../packages/quds_office_engine/example/macros/word_language_controls.bas)
and [local qualification](validation/word-vba-language-controls-20261121/README.md).

### Word AllCaps source and display

The Word adapter adds Boolean `Font.AllCaps` assignments, with reciprocal
SmallCaps exclusion, typed Font aliases, named helpers and independent
header/footer targets. The native model now imports, resolves, copies and
sparsely exports `w:caps`. Full-size uppercase display preserves authored text,
UTF-16 selection ranges and PDF logical text, including Unicode expansions.
Run equality, comparison and stale Zotero/proofing guards recognize the flag;
explicit CSL small capitals clear inherited all-capital formatting.

This is another bounded Stage 4 write-only capability. Property reads, numeric
toggles, locale-specific casing, new ODT/RTF capitalization interchange and
installed Word-host differential acceptance remain separate work. See the
[exact contract](vba-word-macros-details.md#all-capital-display-without-changing-source-text),
[BAS example](../packages/quds_office_engine/example/macros/word_all_caps.bas)
and [local qualification](validation/word-vba-all-caps-20261121/README.md).

### Binary source text processing

The text continuation adds `InStr`, `InStrRev`, `Replace`, and the
`Trim` / `LTrim` / `RTrim` families to all three VBA adapters. They retain
source-only evaluation, strict types and UTF-16 units, with positional optional
arguments and binary comparison. A metered linear matcher bounds scanning and
replacement expansion before allocation; source and native publication limits
are unchanged. A new independently authored versioned corpus checks complete
plans and positioned refusals on both VM and JavaScript.

The [Word report example](../packages/quds_office_engine/example/macros/word_text_report.bas)
prepares report titles and filenames before editing existing body/header
paragraphs. Its local qualification covers CLI/MCP, atomic rollback, native
record/replay, rich formatting and inert DOCM preservation. This extends Stage 2
and reuses the existing Stage 4 adapters; it does not add Stage 3 document reads,
locale comparison, general VBA coercion or installed Office qualification.
See the [exact contract](vba-macros-details.md#binary-search-replacement-and-trimming)
and [intake and local evidence](validation/word-vba-continuation-20261121/README.md).

### Independent Word baseline positioning

The Word adapter supports `Font.Position` on the existing explicit paragraph
and independent header/footer selectors, including typed aliases and named
`ByVal` helpers. Source writes use signed whole points; native JSON accepts
exact half-points. The native model imports, inherits, copies and sparsely
exports `w:position`, including an explicit zero that overrides a style.
Font size and logical text remain independent from the baseline displacement.

Headless layout, incremental translation, note copies, PDF text order, editor
paint grouping, comparison and stale-document fingerprints retain positioning.
This remains a bounded Stage 4 write-only extension, without Stage 3 reads,
embedded VBA execution, general ODT/RTF position interchange or installed Word
differential qualification. See the
[exact contract](vba-word-macros-details.md#baseline-position-without-resizing-text),
[BAS example](../packages/quds_office_engine/example/macros/word_font_position.bas)
and [local qualification](validation/word-vba-typography-20261121/README.md).

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
