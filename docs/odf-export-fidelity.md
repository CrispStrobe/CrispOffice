# ODF export: tables, paragraphs, and header/footer stories

`OdtDocumentWriter` and `OdpPresentationWriter` create new packages from the
shared Word and slide models. They do not preserve arbitrary imported ODF XML.
The [17 November continuation report](validation/office-fidelity-continuation-20261117/README.md)
records the incoming histories, local qualification, independent schema checks,
and actual LibreOffice consumer evidence for the behavior below.
The [resumed qualification](validation/office-fidelity-resume-20261117/README.md)
adds the later comment integration, comment-story repairs, and centered slide
rotation checks against a fresh saved source checkpoint.
The [list and section continuation](validation/office-fidelity-lists-sections-20261117/README.md)
adds the later incoming branches and hardens section activation, page parity,
list nesting, markers, and numbering against fresh local consumer checks.

## Word paragraphs

Line spacing follows the model's units:

| Model rule | Model value | ODF property |
| --- | --- | --- |
| `auto` | Multiplier, e.g. `1.125` | `fo:line-height="112.50%"` |
| `exact` | Points, e.g. `18` | `fo:line-height="18.00pt"` |
| `atLeast` | Minimum points, e.g. `24` | `style:line-height-at-least="24.00pt"` |

The line-spacing rule is part of the automatic-style identity. Headings retain
their paragraph alignment, before/after spacing, line spacing, and explicit
direction. Explicit zero margins override the generated default style.
`left` and `right` retain physical alignment independently of RTL/LTR direction;
explicit writing direction is not automatically recalculated by the consumer.
Hanging indentation retains precedence over first-line indentation.

Nonfinite values and exponent-form values that cannot be serialized as ODF
decimal lengths/percentages are omitted. Values are serialized to two decimal
places. This is a bounded mapping of resolved model properties, not a complete
reconstruction of Word style inheritance or pagination.

## Word tables

The writer emits a column declaration for every logical column, preserving
known grid widths and declaring remaining inferred columns compactly. Table
width uses `style:rel-width="100%"`. Empty tables receive one blank row; empty
and ragged rows receive enough ordinary blank cells to fill the declared grid.
These output-only fallbacks do not add cells to the source model.

A vertical continuation belongs to an anchor only when it is in the next
physical row and has the same logical starting column and horizontal span.
Matching chains produce `table:number-rows-spanned` on the anchor and
`table:covered-table-cell` at covered positions. Horizontal spans combine with
vertical spans to form rectangular merges. A fresh restart, an ordinary cell,
an empty row, or invalid row metadata interrupts a chain. Orphaned or mismatched
continuations remain ordinary visible cells, preserving their content.

For structural table exports, covered-cell stories and formatting remain in the XML. They are hidden by
ordinary ODF consumers and excluded by generic text extraction and bounded
search, including nested stories and the legacy namespace-less fallback.
Recognition uses the ODF table namespace, not a particular prefix or a bare
local name.

Logical positions use `BigInt`; iteration and storage are proportional to
physical source rows/cells. Repetition attributes represent large horizontal
spans, omissions, and padding without allocating or looping over a logical
grid. A consumer may impose its own table-size limits.

## Word sections

Each section retains its modeled page size, page margins, and normal header
and footer through an ODF master page. A section starts on its first exported
paragraph or list item, or directly on its first table. Empty content controls
and unsupported blocks do not consume that boundary. Pictures and frames can
carry the section on a paragraph anchor; frame positions remain relative to
the page. Empty sections use a small empty anchor without modifying the source.
First paragraphs inherit from a common body/heading style and retain their
resolved spacing, indentation, alignment, and direction directly.

An odd/even start selects a temporary right/left page master whose next style
is the normal section master. This constrains only the first page of the
section. Consumers may insert a blank page to satisfy parity; PDF conversion
must retain automatically inserted empty pages to measure physical page order.

Continuous sections reuse the active master when the emitted page geometry
and modeled normal stories are equivalent. Picture comparison uses the exact
image bytes, and comment comparison uses authored reference positions rather
than global annotation-emission state. An empty equivalent continuous section
adds no output paragraph. A changed page size, margin, or normal story uses a
new master and therefore starts a new page: this is an explicit fallback for
page-style changes that cannot apply midway through an ODF page.

First-page/alternating header selection, inherited `linkToPrevious` resolution,
columns, line numbering, and unmodeled native section settings remain outside
this export. The writer exports the normal stories already present in each
section; it does not reconstruct missing stories from native relationships.

## Header and footer stories

Each section's normal header/footer paragraphs use the same inline writer as
body text. This retains explicit line breaks, whitespace, run formatting,
hyperlinks, inline pictures/fallback text, and visible cached field results.
Hidden field instructions remain omitted.

Master-page automatic styles are collected in `styles.xml`; body automatic
styles remain in `content.xml`. The two style registries are separate, while
picture names and bytes share one package registry. This permits the same
automatic-style name to have the appropriate local definition without media
name collisions. Image links include required `xlink:type="simple"`.

Header and footer lists use independent numbering scopes. Field instructions
and editable field metadata are not retained by this new-document export.

## Footnotes and endnotes

Visible body references emit a note body once. Later references to the same
definition use a resolving `text:note-ref`; note IDs remain independent of
display labels. Footnotes and endnotes use the shared read-only Word numbering
resolver, including supported native formats, starts, restarts, and custom
marks. The export adapter treats empty authored reference runs as automatic.
Default editor/native numbering callers retain their existing interpretation.

Citation `text:label` attributes freeze the resolved visible labels so a consumer
cannot silently replace them with its own numbering defaults. This preserves
the exported view; native editable numbering metadata and page-dependent
numbering are not reconstructed. Unresolved numbering retains cached reference
text. A differently authored repeat mark is retained as ordinary visible text.
An otherwise empty custom label uses U+2060 WORD JOINER only in the label
attribute, because an empty attribute causes the tested consumer to invent a
number. Citation character data and source text remain empty; ordinary custom
marks retain their authored labels.

Numbering follows the exporter's visible body paragraphs. Correctly covered
merged-cell stories do not consume numbers, while orphan continuations remain
visible and participate. Missing or ambiguous definitions retain their cached
visible reference text. Note bodies retain paragraph, inline, list, link, and
picture content. Newly authored automatic note markers honor the model's
requested separator without duplicating existing leading whitespace. The
tested consumer omits structural tables inside notes, so
note-table cells export as styled paragraphs in source order, including nested
visible cells and excluding covered stories. Table geometry and hidden cell
stories inside notes are outside this fallback; source blocks remain intact.

New note bodies are emitted only in visible body paragraphs. References in
headers, footers, frames, comments, covered cells, or note bodies appear as visible
marks.
This bounds expansion even when definitions refer to themselves or one another.
Note lookup uses an indexed definition map; source IDs, strings, native settings,
and source block lists remain unchanged.

## Comments

Comments export as point annotations after their visible anchor run. One indexed
registry resolves definitions and emits each comment once across body and master
parts. Main-body anchors take precedence over note, frame, header, and footer
anchors. Hidden covered-cell runs and references inside another comment do not
consume a later visible anchor. Missing or ambiguous definitions leave the
anchor text intact and omit the uncertain annotation.

Comment stories retain author, initials, date, paragraph/run formatting, lists,
line breaks, links, cached field results, and packaged pictures. Heading
paragraphs use styled `text:p` elements because annotations do not permit
`text:h` children. Valid XML Schema date-time strings use `dc:date`; other
authored date strings remain in the standard `meta:date-string` element. Empty
comments receive an output-only blank paragraph for predictable consumers.

Nested comment references do not recursively emit annotations. Note references
inside comments keep their visible marks without emitting or consuming the note
body. Links in comments carry their text style directly on `text:a`; the tested
LibreOffice annotation importer loses the visible text when it is nested inside
a styled span.

The serialized ODF retains pictures, tabs, and annotations in auxiliary stories,
but the tested LibreOffice conversion omits some of these. The consumer report
distinguishes retained XML from visible imported content. Comment ranges,
thread/reply relationships, resolution metadata, and imported foreign annotation
XML are outside this bounded new-document export.

## Presentation tables

The slide model describes equal-sized rows and columns inside a frame. ODP
exports fixed column widths and row heights derived from that frame, together
with required column declarations. Ragged or empty source tables receive a
compact rectangular output grid without source mutation.

Authored cell fill and text colors survive independently. Empty colors use the
slide renderer's white fill and dark (`1A1A1A`) text defaults, avoiding unrelated
consumer theme colors. Ordinary text shapes and speaker notes retain their own
style-cache entries.

All presentation rows are direct `table:table-row` children. The first-row
styling flag carries `headerRow` intent; an empty fallback table has that flag
disabled. The export does not use `table:table-header-rows`, because the tested
Impress consumer omits those wrapped rows. Existing authored cell styles carry
the visible header appearance; no new table template is invented.

To make RTL column placement consistent across consumers, the writer serializes
physical positions from left to right and sets table writing mode to `lr-tb`.
For an RTL source table it reverses the output cell sequence and places missing
logical cells on the physical left. Paragraph writing direction remains RTL.
This avoids relying on the tested Impress consumer's ignored table writing
mode and avoids double reversal in readers that do honor it. The source row
lists remain in their original logical order. This preserves appearance rather
than reconstructing editable native RTL-table metadata.

## Presentation frame rotation

Text and picture frames rotate clockwise about their authored center, matching
the shared slide model. The writer uses an affine matrix plus translation with
explicit units and local frame coordinates. This avoids the old rotation-angle
and positioning mismatch that moved ordinary rotated content outside the slide.
Full turns retain the ordinary unrotated frame representation; wrapped and
negative angles normalize without changing the source transform.

LibreOffice ignores rotation on a native presentation table while applying its
translation. For a rotated table, the writer therefore emits a group of ordinary
cell text frames plus a background. Each cell's position and content rotate
around the table's common center. Authored/default colors, text, and physical RTL
column order remain visible; missing ragged cells use the background without
expanding a logical grid. A final transparent frame retains an authored outer
stroke. Fixed cell frames prevent consumer auto-growth. Unrotated tables retain
native table structure.

This visual fallback does not retain an editable native table or header-row
metadata for rotated tables. The source model is unchanged. Schema checks, asymmetric colored-picture
fixtures, and independently measured consumer geometry cover the documented
cases; they do not establish arbitrary imported transforms or animation parity.

## Slide transitions and automatic advance

Transition properties belong to the referenced drawing-page style. Distinct
effect/timing combinations receive distinct styles, and equivalent combinations
reuse one style. Positive automatic-advance times are preserved to millisecond
precision, including slides with no visual effect. Nonpositive advance times
are omitted. Cut transitions and nonpositive effect durations use no animation.

Push, cover/uncover, wipe, split/doors, clock, circle, and diamond effects use
bounded standard SMIL mappings. Dissolve, checkerboard, blinds, and random bars
use their standard legacy ODF tokens. Other effects use a crossfade fallback.
Mappings follow the shared renderer's movement direction; an incoming edge is
not always named after the source movement direction.

Effect speed uses ODF's three buckets: fast through 500 ms, medium below 1000 ms,
and slow from 1000 ms. Exact effect durations, shape animations, and per-slide
click suppression are outside this export. Schema checks and LibreOffice-imported
transition properties establish structural and consumer retention; they do not
establish playback or frame-by-frame rendering parity.

## Word lists

Consecutive paragraphs sharing a nonzero numbering ID form structural ODF
lists. Nesting compares authored levels, so repeated skipped levels remain
siblings and a list beginning above level zero does not invent missing items.
Malformed levels are bounded to nine levels. Mixed bullet/number markers keep
their own styles. Numbering ID zero and suppressed numbering remain ordinary
paragraphs. All list paragraphs retain their resolved paragraph/run formatting.

Simple decimal definitions retain supported native starts and per-instance
overrides; `listRestart` is authoritative. Without an unambiguous native
definition, a simple first cached decimal label seeds its numbering identity
and level. Subsequent occurrences advance exact `BigInt` counters across
ordinary paragraphs, tables, controls, and sections. Authored higher-level
items reset supported default child counters, including bullet/literal parents.
Every positive value is written explicitly as `text:start-value`.

Headers, footers, frames, comments, notes, and hidden covered-cell stories have
independent counters, so auxiliary or hidden occurrences cannot consume visible
body numbering. Orphaned merge continuations remain visible. Default bullet
glyphs, native symbol-font bullet normalization, and explicitly cached bullet
glyphs are preserved.

Roman, alphabetic, multilevel, special-restart, and otherwise unsupported native
numbering semantics are not reconstructed. Their available cached marker text
is retained literally using core ODF prefix/suffix properties; nonpositive
numeric starts also use literal text because ODF start values must be positive.
Cached labels are trimmed and use normal list-tab separation. The exporter
does not infer a new restart from an arbitrary later cached decimal label, and
does not retain native marker fonts or full editable numbering definitions.
Explicit per-item values and literal fallbacks preserve the tested appearance
without claiming a complete native numbering round trip.

## Standards and validation boundaries

The mappings follow [ODF 1.3 Part 3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html),
particularly sections 6.3 and 7.7.7 (notes and note references),
9.1.3–9.1.7 (rows, cells, covered cells, and columns), 17.25 (drawing-page properties),
19.501 (master-page selection), 19.504–19.507 (number formats and affixes),
19.680 and 19.682 (spans), 19.744 (first-row styling), 20.204 (line height),
20.254 (column width), 20.317 (minimum line height), 20.340.2 (relative table
width), 20.348 (row height), and 20.404–20.405 (writing direction).

Tests inspect generated semantics and source preservation. Independent checks
use Python ZIP/XML readers, the official OASIS RelaxNG schemas, LibreOffice,
and Poppler. Passing the retained fixtures does not establish all-document
schema conformance, complete native office round trips, or universal rendering
parity. Shared editor/headless font shaping remains separate work.
