# ODF export: tables, paragraphs, and header/footer stories

`OdtDocumentWriter` and `OdpPresentationWriter` create new packages from the
shared Word and slide models. They do not preserve arbitrary imported ODF XML.
The [17 November continuation report](validation/office-fidelity-continuation-20261117/README.md)
records the incoming histories, local qualification, independent schema checks,
and actual LibreOffice consumer evidence for the behavior below.

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

Covered-cell stories and formatting remain in the XML. They are hidden by
ordinary ODF consumers and excluded by generic text extraction and bounded
search, including nested stories and the legacy namespace-less fallback.
Recognition uses the ODF table namespace, not a particular prefix or a bare
local name.

Logical positions use `BigInt`; iteration and storage are proportional to
physical source rows/cells. Repetition attributes represent large horizontal
spans, omissions, and padding without allocating or looping over a logical
grid. A consumer may impose its own table-size limits.

## Header and footer stories

The first section's header/footer paragraphs use the same inline writer as
body text. This retains explicit line breaks, whitespace, run formatting,
hyperlinks, inline pictures/fallback text, and visible cached field results.
Hidden field instructions remain omitted.

Master-page automatic styles are collected in `styles.xml`; body automatic
styles remain in `content.xml`. The two style registries are separate, while
picture names and bytes share one package registry. This permits the same
automatic-style name to have the appropriate local definition without media
name collisions. Image links include required `xlink:type="simple"`.

Per-section, alternating, and first-page-specific master-page reconstruction is
outside this writer. Field instructions and editable field metadata are not
retained by this new-document export.

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

## Incoming list support

The integrated list writers group consecutive paragraphs sharing a numbering
ID into flat bullet or decimal lists. List paragraphs continue through the
same paragraph writer, including lists inside table cells. Decimal styles use
the core `style:num-format` and `style:num-suffix` attributes; the redundant
LibreOffice extension was removed after strict schema checking and a
pixel-identical consumer comparison.

Nested levels, restart values, complex numbering formats, and header/footer or
frame list grouping remain outside this bounded list implementation.

## Standards and validation boundaries

The mappings follow [ODF 1.3 Part 3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html),
particularly sections 9.1.3–9.1.7 (rows, cells, covered cells, and columns),
19.680 and 19.682 (spans), 19.744 (first-row styling), 20.204 (line height),
20.254 (column width), 20.317 (minimum line height), 20.340.2 (relative table
width), 20.348 (row height), and 20.404–20.405 (writing direction).

Tests inspect generated semantics and source preservation. Independent checks
use Python ZIP/XML readers, the official OASIS RelaxNG schemas, LibreOffice,
and Poppler. Passing the retained fixtures does not establish all-document
schema conformance, complete native office round trips, or universal rendering
parity. Rotation and shared editor/headless font shaping remain separate work.
