# Zotero word-processor parity

This roadmap compares Quds' native desktop integration with Zotero's Word and
LibreOffice workflows. It distinguishes implemented behavior, deliberate
content limits and interoperability acceptance. LibreOffice is the current
supported comparison target in Zotero's [plugin requirements](https://www.zotero.org/support/system_requirements).
Zotero's [troubleshooting guidance](https://www.zotero.org/support/word_processor_plugin_troubleshooting)
explicitly excludes Apache OpenOffice from supported applications. Compatibility
with a historical OpenOffice plugin remains a separate legacy target, requiring
identified application, Zotero and plugin versions. LibreOffice results do not
establish that compatibility.

The [usage guide](../../zotero-support.md) describes the current controls. The
[table-layout work record](../../validation/zotero-table-layout-20261121/README.md)
tracks delivered native margin layout and bounded editable ODT uniform padding,
including precision and remaining application-validation limits. The
[rich ODT import record](../../validation/zotero-rich-odt-20261121/README.md)
tracks the earlier bounded native-file conversion, asynchronous editor/Studio
opening, source-preserving DOCX save routing and exact qualification limits. The
[nested-table work record](../../validation/zotero-nested-tables-20261121/README.md)
tracks bounded nested research content and its qualification. The
[table-cell range work record](../../validation/zotero-table-cell-ranges-20261121/README.md)
tracks the latest cell-local editing increment. The
[document-transfer work record](../../validation/zotero-transfer-20261121/README.md)
records its source, incoming-work reconciliation, remote checkpoints,
local checks, real file-converter routes and remaining installed-plugin
acceptance. The preceding
[multi-paragraph replacement work record](../../validation/zotero-multiparagraph-20261121/README.md)
retains its source-specific evidence. The earlier
[vertical-table work record](../../validation/zotero-vertical-tables-20261120/README.md)
retains its source-specific evidence. The
[research-table work record](../../validation/zotero-research-tables-20261120/README.md)
retains the preceding table increment's evidence. The earlier
[structured-note continuation](../../validation/zotero-parity-continuation-20261120/README.md)
retains its evidence for embedded pictures and research lists. Historical
results retain their original source and platform attribution.

## Workflow coverage

| Workflow | Quds implementation | Remaining boundary |
| --- | --- | --- |
| Add/edit citation | Native Zotero picker, selected catalog sources, locators, prefixes/suffixes, multiple items, body and authored-note caret | Unsupported stories and structural ranges remain guarded |
| Document preferences | Native style, locale and inline/footnote/endnote preferences stored in the document | Conversion refuses authored notes whose extra content would be lost |
| Refresh | Complete supported document sequence sent to Zotero's processor, including note order, numeric renumbering, disambiguation, style-dependent ibid. and merging of directly touching citation packets | Merge hints require physical adjacency in the same paragraph/story/note; live acceptance must be repeated on the exact release/host |
| Native selected-field context | Temporary original-source highlights and prompt excerpts for explicit `Field.select`, including body/table/note citations, damaged metadata and multipart bibliographies; independent writing selection, lifecycle cleanup and guarded viewport restoration | Pending insertions and transfer clones have no live source range; incomplete or ambiguous structural recovery and installed-host acceptance remain separate |
| Damaged reference metadata | Native repair for structurally complete citation packets with invalid JSON/schema and owned bibliography ranges with invalid JSON; original-source retention until completion; confirmed individual conversion to ordinary text, undo and DOCX persistence | No inferred field boundaries or shared/cross-owner repairs; incomplete, nested, locked and opaque packets remain guarded; native delete and unlink callbacks retain distinct effects; installed-plugin acceptance remains open |
| Bibliography | Native add/edit, entry paragraphs, rich runs, hanging indents, spacing and tab stops | Replacement requires a complete exclusively owned bibliography range |
| Unlink citations | Explicit individual and document-wide conversion with undo, including complete damaged metadata with a disclosed count and native ownership checks | Incomplete, locked, nested, opaque or ambiguously owned fields block the whole conversion; verify final target-application files separately |
| Add Note | Rich paragraphs, headings, block quotations up to eight levels, nested lists up to nine levels, multiparagraph items, links, pictures, rectangular tables nested up to eight levels with combined row/column spans and active citations; insertion in body or authored notes and replacement across consecutive ordinary paragraphs in one section, note or table cell | Quote indentation uses a documented native mapping; quotes inside list items and tables inside quotes remain guarded. Table payloads require a main-flow destination; cross-cell/control ranges, selected protected/structural content, compact merged-row height distribution, header/footer row groups, custom table styling and custom/reversed list markers remain unsupported |
| Add Annotation | Zotero 9+ native annotation picker, text/comments and supported PNG image/ink content with active citations | Uses the same bounded image/content envelope as Add Note |
| Research-note formatting | Explicit paragraph/heading direction and alignment, exported indent levels 1–7 at 30 pt per level, opaque text/highlight colors, authored empty-paragraph direction, native RGB shading and color-consistent canvas/PDF rendering | Directional lists, RTL child paragraphs in lists, higher historical indent levels, arbitrary layout CSS and alpha/dynamic color expressions remain guarded; export padding differs from Zotero's editor-only CSS |
| Library/source discovery | Local/online catalogs, collections, saved searches, tags, source details, cited-source reuse and occurrence navigation, and validated local/group **Open in Zotero** navigation from reference details | Local and online catalog APIs have different connection/version requirements; desktop selection is unavailable for unverified personal-web or offline identities |
| Research materials | Read-only direct-child note previews and attachment metadata | No separate attachment-file download or Zotero library write workflow |
| DOCX persistence | Active fields/preferences, native notes, rich bibliography structure, tables and embedded pictures use supported save/reopen paths | Local tests are separate from actual Word/LibreOffice application round trips |
| Table margins | Native measurement, wrapping, pagination, ruler insets and nested picture fitting use each table's modeled uniform margin; explicit editable ODT preserves bounded uniform padding through style inheritance and merged/nested ownership | Asymmetric/per-cell ODT padding and visible borders remain unsupported; ODT/DOCX geometry rounds to format precision, and exhausted final scaled widths refuse |
| Footnote separators | Explicit solid/hidden rules retain independent gaps, nominal thickness, relative width, physical alignment and color; matching native pagination, continuation-page layout, editor/PDF rendering, ODT persistence and bounded native DOCX persistence | One compatible document-wide geometry; dashed/dotted active rules and richer separator stories remain unsupported; LibreOffice normalizes custom DOCX separator paragraphs, so that converter route remains a recorded limitation |
| Cross-word-processor transfer | Native export/import handshake, temporary metadata hyperlinks, DOCX import/save/reopen and ODT carrier export; complete native formatting before import publication | The qualified DOCX carrier route and native ODT conversion have separate envelopes; installed Zotero/Word/LibreOffice plugin acceptance remains open and actual converter findings are retained |
| Native ODT inspection | Read-only inventory of citation ReferenceMarks, bibliography TextSections, exact story/paragraph/cell ownership, cached text and original preferences; JSON diagnostic CLI | Inspection reports eligibility and findings without publishing an editable document |
| Native ODT import | Bounded rich paragraphs/styles, hyperlinks, authored notes, simple lists, supported merged/nested tables and embedded inline PNG/upright RGB JPEG pictures; canonical Zotero fields and preferences convert to an editable Word document; asynchronous editor/Studio opening and DOCX save/reopen | Used unsupported structure/formatting refuses atomically; content-sensitive guards limit dormant defaults; installed-plugin acceptance remains open |
| Native editable ODT output | Explicit copy export with native citation ReferenceMarks, bibliography TextSections, preferences, bounded body/cell and automatic decimal/Roman note ownership and inline pictures with links/alternative text | General Word-to-ODT formatting limits remain; unsupported active-field or picture ownership refuses; release-host/plugin acceptance is separate from local and converter fixtures |

The native controls use Zotero's own CSL processor. The separate basic/offline
citation and single-item preview/export paths retain their narrower formatting
contract; they are not evidence of complete document-wide CSL parity.

## Delivered increment: research-note paragraph layout and colors

The [formatting continuation](../../validation/zotero-note-formatting-20261122/README.md)
preserves canonical `dir`, `data-indent` and text alignment on paragraphs and
headings, plus opaque exported text/highlight colors. Indentation follows the
40 CSS px compatibility padding in Zotero's word-processor payload: 30 pt per
level, counted once and composed with native list/quote indentation. Explicit
alignment stays independent of reading direction. Missing direction remains
automatic, including right-aligned mixed-script text.

Formatted paragraphs retain their owners through merged cells and use
structured insertion to protect surrounding prose. Explicit LTR/RTL survives
empty-paragraph relayout, typing, undo/redo and DOCX reopening. Non-palette RGB
highlights persist as native Word run shading; the editor paints the authored
opaque RGB, matching PDF/export semantics. Ordinary CSL formatting keeps its
existing contract. Exact forms and deliberate limits are described in the
[support details](../../zotero-support-details.md#paragraph-layout-and-colors-in-research-notes).

Installed native Zotero dialogs and Word/LibreOffice plugin acceptance remain
open. Controlled callbacks, native file cycles and converter observations have
separate evidence and do not establish complete application parity.

## Delivered increment: quoted research notes

The [quote continuation](../../validation/zotero-workflow-parity-20261122/README.md)
accepts the literal `blockquote` structure exported by Zotero's note editor.
Up to eight levels map to an additional 18 pt of native left indentation per
level. Rich paragraphs, empty paragraphs, headings, lists inside quotes,
inline pictures, links and active citations retain their content and reading
order. Quotes in research-table cells retain their actual native owners,
including the paragraph remapping needed by vertical merged cells.

Quote indentation composes after heading and list formatting. Any note with
quotes follows the structured insertion path, preserving surrounding prose and
its paragraph properties. Body, authored-note and supported cell selections
retain detached completion, source guards, undo/redo and DOCX persistence.
An independent empty-heading regression prevents an extra blank quote paragraph.

The exported HTML does not carry Zotero's editor-only quote stylesheet; Quds'
mapping does not claim its blue border or exact spacing. Inline-only quote
content, quotes inside list items, tables inside quotes, arbitrary layout CSS
and greater depth remain guarded. Quote-only editable ODT acceptance does not
establish continued-list ODT or installed Zotero/Word/LibreOffice parity.
Canonical paragraph direction/indent attributes and opaque exported note colors
are covered by the formatting continuation above.

## Delivered increment: automatic Roman notes in editable ODT

The [numbering and unlink continuation](../../validation/zotero-parity-next-20261122/README.md)
extends the automatic-note path below to continuous sequences starting from
1 to 32,768. Footnotes/endnotes keep independent starts; decimal ordinals stay
within 65,535 and Roman ordinals within 3,999. It distinguishes literal ODF
starts from identified LibreOffice offsets and a versioned Quds export
convention, requires exact caches, and preserves numeric Zotero note indexes.
It also extends document-wide unlinking to structurally complete damaged
metadata, with confirmation, atomic refusal, undo/redo and DOCX persistence.

The preceding Roman increment preserves continuous automatic decimal and
lower/upper Roman notes starting at one, including Word's default endnotes.
The exporter verifies effective native format, ordinal, start and restart
settings for every note in a cited class, including uncited notes. It emits
explicit per-class configurations while leaving footnote/endnote sequences
independent. Import checks the cached labels against the declared sequence
and stores native numbering settings for subsequent DOCX saves.

Custom labels, format changes within one note class, restarts, malformed settings and Roman ordinals
outside 1–3,999 remain guarded. Alphabetic numbering requires a separate
producer-aware contract: current LibreOffice and the ODF prose disagree on
letter synchronization. Omitted format/default behavior and the LibreOffice
zero-offset convention are handled explicitly, without guessing from text.

The [implementation and validation record](../../validation/zotero-note-numbering-20261122/README.md)
tracks local engine/editor/Studio checks, actual converter fixtures and exact
source attribution. Installed Zotero plugin and Microsoft Word acceptance
remain separate from file conversion and controlled protocol tests.

## Delivered increments: pictures and structured research lists

The previous Add Note/Add Annotation path refused every image. This increment
uses the existing `Document.insertText` payload and existing Word inline-picture
model. Images occupy one atomic character position, preserving the surrounding
rich text and active citation offsets. The whole response remains detached
until the native operation completes and the original document target is still
valid. Text, pictures, notes, citations and preferences apply as one undo step.

The accepted raster envelope is static PNG and upright, three-component
RGB/YCbCr JPEG. Original accepted bytes, ordinary image links, title, alternative
description and supported dimensions are retained. Bounded validation checks
the actual raster, not only its filename or header. The detailed limits and
explicit exclusions are in [Embedded pictures](../../zotero-support.md#embedded-pictures-in-notes-and-annotations).

This is an incremental feature qualification, not a declaration of complete
Word/LibreOffice parity. No new live Zotero session or installed Word/LibreOffice
interoperability result is implied by controlled protocol, serializer,
controller or Flutter raster tests.

The continuation preserves mixed nested lists and multiparagraph items as native
Word paragraphs and numbering. First paragraphs receive the item marker;
continuations retain their indentation without incrementing the counter. Nested
lists have independent starts, and existing document lists are unchanged. Active
citations and embedded pictures remain in reading order, including picture-only
list paragraphs. The same detached transaction applies the entire result as one
undoable edit and refuses malformed or over-depth content before publication.

## Delivered increment: authored-note and selection insertion

Add Note and Add Annotation now accept the active authored footnote/endnote
and a deliberate selection within one paragraph. Embedded citations keep that
note's physical ownership and document order; incompatible note-style requests
are refused, so the operation never creates a nested note. The automatic note
number and its separator remain before content inserted at the visible start,
including a leading heading or list.

The selected range is replaced only when the detached operation completes and
the original document, selection and composition state are still current.
Surrounding prose, supported formatting, lists and images remain intact. One
undo restores the entire document and the original selection direction.
That increment guarded selections across paragraphs. The later range
continuation below extends this boundary; selected existing fields, atomic
content, commented text and structural/protected ranges remain guarded. Native complex
Word fields and bookmark endpoints are protected too. DOCX reopening now
resolves visible list labels independently for each authored footnote/endnote.

The [target-insertion work record](../../validation/zotero-note-targets-20261120/README.md)
records the reconciled baseline, implementation checkpoints and local checks.
This increment does not establish live application or active ODT transfer parity.

## Delivered increment: native research tables

Add Note and Add Annotation preserve bounded rectangular tables as native Word
blocks, with rich cell content, independent lists, pictures and active citation
fields. Source order is retained across rows, cells and their paragraphs.
Consistent column widths and supported cell background colors map to native
properties. Header cells retain bold text with explicit inline emphasis
changes. Empty cells and tables preserve their structure.

One parse context covers the complete note, including shared image, paragraph
and link limits. Additional bounds are 64 tables, 256 rows per table, 32 columns
and 4,096 total cells. Supplied column widths accept 1–4,000 integral CSS pixels
and must agree across rows; total native width is limited to 4,000 points.
The [usage guide](../../zotero-support.md#tables-in-notes-and-annotations) specifies
the mappings and content envelope.

A table payload requires a main-flow paragraph in the body or authored note.
Surrounding prose never becomes cell content. A leading authored-note table
leaves the automatic marker and separator before it; a trailing table receives
a main-flow paragraph for the final caret. The Notes pane edits surrounding
prose and preserves the table without presenting its cells as ordinary Notes
text. The complete operation retains the established atomic staging, target
guards, DOCX persistence and undo boundary.

That initial table increment refused merged cells. The horizontal-merge
continuation below extends its structure while retaining the remaining limits.
The
[implementation and validation record](../../validation/zotero-research-tables-20261120/README.md)
separates local source checks from live Zotero and Word/LibreOffice acceptance.
This increment does not establish active ODT transfer or complete plugin parity.

## Delivered increment: horizontal merged cells and adjacent-citation Refresh

Add Note and Add Annotation now map HTML `colspan` values from 1 to 32 to native
`gridSpan`. All rows must cover the same logical column count, up to 32, while
their authored cell counts may differ. Rich text, independent lists, pictures
and active citations remain owned by their native cells and paragraphs, with
the same body, footnote and endnote destinations and one undo/redo transaction.
DOCX saving and reopening retain the spans, cell contents and active fields.

A supplied `data-colwidth` vector has exactly one entry per covered logical
column. Each entry is an integer: 0 means unspecified, and 1–4,000 specifies CSS
pixels. Explicit widths reconcile across all rows by logical column; unresolved
columns use 120 points. A cell's width is the sum of its covered grid widths,
and total native table width remains at most 4,000 points. The existing bounds
of 64 tables, 256 rows per table and 4,096 authored cells per note remain,
alongside shared paragraph, link and image budgets. At that checkpoint, vertical merges
(`rowspan` greater than 1), nested tables, tables inside list items, unequal
logical row widths, separate header/footer row groups, captions and unsupported
custom styling refused the entire staged insertion. The subsequent vertical-table increment below extends that boundary. The
[usage guide](../../zotero-support.md#tables-in-notes-and-annotations) records the
complete content envelope.

Native Refresh advertises boolean `supportsCitationMerging` and marks a field
`adjacent` only when its native citation packet directly touches the **next
enumerated field** within the same paragraph, story and authored note. Zotero
owns the merged item order, deduplication and CSL formatting. Whitespace,
zero-width text characters, bookmarks, comments, controls, ordinary native
fields, bibliographies and paragraph/cell/note boundaries break the chain.
Staged insertion, deletion, unlinking and conversion do not create new merge
opportunities. Quds rechecks physical adjacency before applying the result;
successful refresh is one undo/redo step, and aborted or stale results stay
detached.

The [continuation validation record](../../validation/zotero-merged-cells-20261120/README.md)
qualifies source `180399f99a3898501ab1959e3b845150d7da59fd` with 495 engine
passes, 378 editor passes/eight skips and 928 incoming Word/Mail passes. The
three final processes total 1,801 passes and eight skips, with zero failures or
errors. All 257 Zotero editor cases executed and passed. The eight skips are
existing image-only layout fixtures; they are also excluded from the corrected
earlier-source tally. Repeated runs are not added together. PR #276 merged into main as
`698209aaa6e7f1350b6541df5eb192b7b233443d`. This is local source qualification; no new installed
Zotero, Word or LibreOffice run, active ODT transfer or complete parity is
claimed. Earlier records retain their original evidence and source attribution.

## Delivered increment: vertical research-table merges

Add Note and Add Annotation now accept bounded `rowspan` and combined
`rowspan`/`colspan`. A logical occupancy grid checks complete rectangular
coverage, actual-row bounds, row-group boundaries and overlaps before staging.
Native continuation cells own mandatory empty paragraphs; citation and list
indexes are remapped to the final native paragraph order, preserving active
fields and independent counters before, inside and after tables.

The complete fragment is limited to 4,096 native cells and 10,000 native
paragraphs, including generated continuations. Width vectors reconcile by
occupied logical column. Body, authored-footnote and authored-endnote targets
retain detached cancellation/stale-target behavior, one undo/redo step and
DOCX reopening.

Merged-cell shading/borders continue across physical pages. Pointer and keyboard
navigation target the originating cell while row handles retain physical row
geometry. The first physical row still carries the originating cell's full
content height; compact Word-style row-height distribution is not claimed.
See the [source-bound work record](../../validation/zotero-vertical-tables-20261120/README.md)
for current qualification and remaining installed-application acceptance.

## Delivered increment: replacement across ordinary paragraphs

Add Note and Add Annotation now replace a selection spanning up to 10,000
consecutive ordinary main-flow paragraphs in one body section or authored
footnote/endnote. The native range owns its paragraph boundaries explicitly.
Unselected prefix/suffix runs and active fields remain in reading order;
separate suffix paragraphs retain their original paragraph formatting. The
existing rich paragraphs, headings, lists, images and table payloads use the
same detached conversion and one undo/redo transaction.

The Notes pane maps both visible selection endpoints to native offsets and
preserves the automatic marker/separator. Undo restores the original selection
direction. Cancellation, moved endpoints, composition and intervening edits
leave the staged result unapplied. Exact unselected citation endpoints retain
both simple and complex native packets, including refreshes that change text
length. Quds DOCX reopening retains active citations and permits another
qualified replacement.

Selected fields, note references, pictures, comments, bookmarks and ambiguous
native markup remain guarded. Ranges cannot cross sections or structural
blocks, nor start inside a table or content control. Shared paragraph objects
are refused before mutation. This completes the earlier ordinary-paragraph
range milestone; it does not establish active ODT transfer or installed
Word/LibreOffice acceptance. The [work record](../../validation/zotero-multiparagraph-20261121/README.md)
separates fresh execution from historical evidence and records all remote saves.

## Delivered increment: active-document transfer protocol

Quds now advertises Zotero's import/export capability, invokes its native
`exportDocument` command and implements the matching document callbacks.
Transfer preparation retains the canonical marker, instructions, raw citation
and bibliography codes and serialized preferences. Import recognizes the modern
and legacy markers, reconstructs validated fields and lets Zotero reformat every
remaining imported field before the staged result can be applied.

The editor exposes **Prepare document for transfer…** and changes Refresh into
**Import transferred references…** for a pending carrier. Cancellation, malformed
metadata, incomplete formatting and stale document state leave the source
untouched. Successful import/export is one undo/redo step. The model preserves
existing paragraph, table-cell and authored-note identities, handles adjacent or
formatted link fragments, and recognizes narrowly verified Google Docs URLs.

The [transfer work record](../../validation/zotero-transfer-20261121/README.md)
records pinned upstream contracts, local tests, converter artifacts and exact
limitations. DOCX is the qualified incoming carrier format for that increment.
ODT export uses temporary metadata hyperlinks. The later native ODT import
increment below separately converts canonical `ReferenceMark`/TextSection
documents within its supported content envelope. Installed native-plugin
acceptance remains a separate gate.

## Delivered increment: replacement within one table cell

Add Note and Add Annotation can replace consecutive ordinary paragraphs in one
body table cell, including a merged region's originating cell and a cell inside
an existing nested table. The native table, row, cell and block-list owners stay
intact. Rich paragraphs, headings, lists, supported pictures, unselected text
and active citation fields retain the existing detached transaction, DOCX
persistence and one undo/redo action.

The session captures the exact owner chain when it starts. Replacing an owner
while a picker is open invalidates the result even if flattened paragraph
identities and visible text are unchanged. Cross-cell ranges, selected nested
structures, content-control/drawing ancestors, aliases and hidden vertical-merge
continuations remain guarded. A table-containing incoming note still requires a
main-flow destination. That cell-range increment did not add nested-table
payload parsing; the subsequent nested-research-table increment below does.

Raw engine sessions also support cells in authored footnotes/endnotes. The
standard Notes pane still edits main-flow note paragraphs, so this does not
claim a new Notes-pane table editor. The [work record](../../validation/zotero-table-cell-ranges-20261121/README.md)
separates local qualification from installed Word/LibreOffice plugin acceptance.

## Delivered increment: nested research tables

Add Note and Add Annotation preserve tables nested at ordinary cell block
boundaries, up to eight table levels including the outermost table. Explicit
owner frames reconstruct the actual native cell/block tree. Citations and list
metadata follow recursive document order, including generated merged-cell and
trailing cell paragraphs. Each table validates its own spans and widths while
the complete note shares table, cell, paragraph, link and image budgets.

Body and authored-note destinations retain detached publication and one undo
transaction. A table-containing payload still requires a main-flow target;
tables inside list items/inline content, custom table styles and cross-cell
replacement remain separate work. The
[work record](../../validation/zotero-nested-tables-20261121/README.md) records
local qualification separately from installed-application acceptance.

The retained converter fixture qualifies the direct Quds ODT carrier →
LibreOffice DOCX → Quds import route, including three further saves. On the
identified LibreOffice development build, the DOCX → ODT → DOCX route changes
a continued numbered list from `4., 5.` to `4., 1.`. A flat-list control reproduces
the change without nested tables. The strict verifier keeps that route failed;
no reader heuristic conflates separate numbering instances to conceal it.

## Delivered increment: native ODT Zotero inventory

`OdfZotero.inspect` reads native LibreOffice citation marks and bibliography
sections without changing the document. It preserves full names, logical codes,
unknown citation metadata, paragraph ranges, UTF-16 offsets and original
preference strings. Namespace-qualified owner chains distinguish the body,
individual notes, table cells, comments, drawings, headers/footers and revisions.
Duplicate, missing, crossed, nested, repeated, protected, linked and unsupported
structures produce explicit findings. Resource exhaustion fails the whole
inspection. A command-line diagnostic emits the typed inventory as JSON.

The [native-input contract](native-odt-input.md) documents the exact scope and
bounds; the [validation record](../../validation/zotero-odt-inventory-20261121/README.md)
records executed checks and incremental remote preservation. The source uses
the existing Zotero metadata semantics without weakening Word/HTTP callbacks.
This completed the inventory prerequisite. The inspection API remains read-only
and ordinary ODT export retains its cached-result behavior.

## Delivered increment: bounded rich native ODT import

`OdtDocumentReader.readBytes` converts supported native ODT into `WmlDocument`.
`OfficeIsolateOpen.word` dispatches by package bytes, and
`WordEditorController.loadBytesAsync` refuses stale publication after another
open, edit, document replacement or disposal. Studio Open accepts `.odt` and
proposes a new `.docx` save destination, preserving the original ODT file.

Canonical Zotero citations and reference-mark/section bibliographies become
active native fields with exact paragraph, note and cell ownership. Rich and
empty bibliography paragraphs, identical-looking/adjacent citations, per-source
options and unknown metadata survive DOCX save/reopen. Source endpoint order
and rich UTF-16 decoding preserve whitespace around authored note anchors and
refuse a field that encloses an anchor, including at its final text offset.

The content envelope includes supported named/default/automatic styles,
paragraphs and unnumbered headings, absolute external links, ordinary decimal
footnotes/endnotes, simple decimal/bullet lists and rectangular unmerged tables
nested up to eight levels. It preserves supported table widths/inheritance,
independent list starts/restarts and nested continuation paragraphs. Unsupported
used properties, protected/linked sections, drawings/images, comments, revisions,
merged/repeated table owners, conflicting list geometry and ambiguous fields
refuse before publication; the [native-input contract](native-odt-input.md)
defines the full boundary.

The explicit import boundary normalizes `ReferenceMark` preferences to `Field`
after field reconstruction, retaining style/locale/note mode and unknown
XML/JSON preferences. Ordinary Word/HTTP callbacks remain strict. Original
`meta.xml` is archived byte-for-byte in a DOCX custom XML part; supported
document properties are also mapped to the native model. Save as DOCX to retain
active citations. Ordinary ODT export remains a cached-result path.

The [rich-import record](../../validation/zotero-rich-odt-20261121/README.md)
separates synthetic parser/style tests, controlled Zotero refresh/placement
transactions, DOCX persistence and editor/Studio checks from actual host
acceptance. Its historical LibreOfficeDev 26.8 style refusal is addressed by the
next increment. These changes do not establish full Word/LibreOffice plugin
parity, an installed Zotero round trip or legacy Apache OpenOffice compatibility.

## Delivered increment: retained LibreOffice styles

The [style continuation record](../../validation/zotero-libreoffice-styles-20261121/README.md)
retains the untouched LibreOfficeDev prose fixture, its source DOCX and exact
hashes. The importer resolves its full supported style envelope, preserving
Latin 11-point and Arabic 10-point text through repeated DOCX saves. A separately
identified synthetic Zotero extension keeps the same style XML while exercising
canonical fields, multi-paragraph bibliography refresh, preferences, unknown
metadata and exact UTF-16 ownership.

Independent script settings resolve through inheritance and become ordinary
editable native runs. Later formatting edits synchronize only importer-owned
script projections. Paragraph/page defaults are accepted only when supported
or demonstrably inactive for the current content: active Asian typography,
uncertain break locales, nonstandard tabs, active grids and used custom footnote
separators remain explicit refusals. This conversion does not retain a complete
ODF style engine for later content changes. The source review and local checks
are separate from an installed Word/LibreOffice/Zotero interoperability session.

## Implemented increment: native ODT merged tables

The native reader now validates horizontal/vertical spans against explicit
ODF covered cells and maps the originating rich content into the existing Word
table model. Supported combined spans, widths, row properties and inherited
shading retain their physical cell ownership. Native vertical continuations
contain no duplicate text or Zotero fields. Nested tables have separate
coverage grids and share the complete document's resource limits.

The conversion refuses missing/orphan/overlapping coverage, out-of-range
spans, repeated rows/cells, hidden covered content and unsupported covered
styles. ODF permits stored covered-cell content; this refusal is a deliberate
supported-subset boundary. The original ODT is unchanged, and active citations
continue to save as DOCX.

The [merged-table work record](../../validation/zotero-odt-merged-tables-20261121/README.md)
records incremental remote preservation and independent source review.
The subsequent [editable-output work record](../../validation/zotero-editable-odt-20261121/README.md)
executes the pending formatting, analysis and engine/editor regressions with
the pinned SDK. Earlier results retain their original source attribution.

## Delivered increment: explicit editable ODT output

The [native-output contract](native-odt-output.md) defines a separate
`OdtDocumentWriter.writeEditableZoteroBytes` API and Studio **Export Zotero ODT**
action. Canonical ReferenceMarks, complete bibliography TextSections and
Unicode-safe preference chunks retain the active field metadata. Exact native
owners and emitted endpoints are checked before returning bytes. Unsupported
or hidden fields refuse the whole export. The ordinary cached-text exporter and
normal DOCX save workflow retain their existing behavior.

Repeated body/table/note ODT/native/DOCX cycles, native bibliography refresh and
unlink, source immutability and Studio cancellation/save routing are qualified
locally. The concrete LibreOfficeDev save/reopen fixtures preserve seven active
field records and preferences; they do not establish installed-plugin or stable
release acceptance. A repeat-cycle regression also corrected decimal ODT
endnotes reverting to Roman numbering after DOCX saves. The final local gate
passed 513 engine, 93 editor and 25 Studio cases (631 unique passes, no failures
or skips), with exact published-source binding and retained converter fixtures
in the [qualification record](../../validation/zotero-editable-odt-20261121/README.md).

## Delivered increment: inline pictures through native ODT

The [picture continuation](../../validation/zotero-odt-images-20261121/README.md)
closes a gap between existing Zotero note/annotation insertion and native ODT
reopening. Supported embedded inline PNG and upright RGB/YCbCr JPEG pictures
retain their bytes, physical size, links, accessible titles/descriptions and
supported run properties. Exact picture positions keep adjacent citation
offsets and owners stable through native reopening, controlled refresh/unlink,
undo/redo and further DOCX saves.

The exporter emits one frame per picture without duplicating its internal
placeholder as visible text. It assigns unique drawing-object names across
stories so LibreOffice does not drop pictures with duplicate names. Accessible
titles/descriptions remain independent of those assigned names. The importer
qualifies each consumed frame/image
path rather than clearing all drawing findings. It reuses the bounded raster
decoder across the whole document and refuses unsupported ownership, image
adjustments and pictures inside field caches. The [input](native-odt-input.md)
and [output](native-odt-output.md) contracts define the exact envelope.

Actual converter evidence and unresolved general LibreOffice section/table
defaults are retained separately in the work record. This increment does not
establish installed Zotero plugin acceptance or historical Apache OpenOffice
compatibility.

## Delivered increment: reopening LibreOffice-saved native references

The [native round-trip continuation](../../validation/zotero-odt-roundtrip-20261121/README.md)
starts from actual saved ODT files that previously passed inventory checks but
failed editable reopening. Native bibliography sections now admit their inert
inherited LibreOffice styles, preserving complete rich/empty entry ownership.
Strict decimal note labels qualify the identified LibreOffice zero-offset
convention. Editable table exports use physical alignment with fixed widths,
preventing LibreOffice from expanding them to the page margins. Unknown used
formatting and unrepresented protection remain explicit refusals.

Intervening DOCX saves retain complete uniform table margins, including zero,
without flattening unsupported imported margin XML. Native editable notes use
distinct 65-percent symbol/anchor styles per note class and the final regular
endnote master; reopening validates their effective formatting and compatible
page geometry. Optional soft-page hints are recomputed. Actual acceptance now
follows three fixtures and eleven fields through two external LibreOffice saves
with a native/DOCX/native cycle between them. The following increment replaces
fixed table-screen padding with modeled margins. At that checkpoint, active
footnote separators and installed release-host/plugin acceptance remained open.

The work record separates local native update/save regressions, actual converter
cycles, and installed-plugin acceptance. The later active-separator increment
below adds native model/layout/persistence support. Endnote-only and table-only
acceptance does not establish that footnote behavior or full Word/LibreOffice
parity.

## Delivered increment: uniform table margins and editable ODT padding

Native table measurement, wrapping, row height, pagination and ruler fallback
now use each table's uniform `cellMargin`, including zero. The native model's
default remains 4 pt. Nested tables keep independent values; picture fitting
accounts for all enclosing margins, including temporary tall-row layout and
tables in authored notes. Layout restores the enclosing margin budget after
nested work or a failure.

The explicit editable ODT writer emits that margin as cell-style `fo:padding`.
Native input resolves family defaults and named parents, expanding each layer's
shorthand before its explicit sides. All effective sides and all visible
originating cells in one table must share one value. Covered-cell padding, when
authored or inherited, must match its merged origin; nested tables resolve
separately. Asymmetric/per-cell padding, unsupported row/column default-cell
styles and visible borders remain refused. Explicit borderless declarations
are accepted. Ordinary cached-result ODT output keeps its previous formatting
contract.

Margins must be finite, nonnegative, within the DOCX limit of 32,767 twentieths
of a point (1,638.35 pt), and leave positive cell content width. Editable ODT
checks the emitted geometry after rounding: ODT lengths use two decimal places
in points, while DOCX margins round to twentieths of a point (0.05 pt). This
does not promise exact cross-format geometry. Native layout may scale a table
to a page or enclosing cell and refuses a final scaled width exhausted by its
margins, even when the unscaled source had positive content width.

The [table-layout work record](../../validation/zotero-table-layout-20261121/README.md)
records the implementation, focused regressions, repeated native/ODT/DOCX
lifecycles and identified LibreOffice converter evidence. Installed Zotero
workflows in Word and supported LibreOffice releases remain a separate gate;
this increment does not establish complete plugin parity.

## Delivered increment: active footnote separators

Supported footnote documents now retain one explicit separator geometry across
ordinary and continuation pages: independent before/after gaps, nominal line
thickness, relative body width, physical left/center/right alignment, RGB color
and solid/hidden line style. Native pagination reserves both gaps and thickness,
even when the rule is hidden or has zero width. Editor and PDF rendering use
the modeled rectangle; documents without an explicit model retain their legacy
appearance. Continuation-page image fitting accounts for the same reservation.

Native ODT import/export preserves supported geometry and known LibreOffice
zero-length omissions. A compatible representable dormant definition survives
deleting the last note and later reinserting one. Used unsupported or differing
page definitions refuse without publishing a partial document. Native DOCX
save/reopen uses a bounded canonical special-note/settings mapping with format
precision checks; arbitrary imported separator XML remains preserved opaquely.

The [separator work record](../../validation/zotero-footnote-separators-20261121/README.md)
retains local regression evidence, fourteen direct ODT geometry cases and three
active-citation fixtures through two real LibreOffice saves with controlled
native refresh and DOCX/ODT cycles between them. The identified development
converter preserves the tested direct ODT geometry but normalizes custom DOCX
separator paragraphs. That failed route, installed Word rendering, supported
release-host qualification and live Zotero plugin workflows remain separate
acceptance work.

## Next implementation and acceptance steps

### Writing-position continuation (22 November 2026)

Native Refresh and style changes now track writing endpoints by paragraph
identity and transform their offsets through supported citation replacements,
deletions and note conversions. Bibliography growth or shrinkage no longer
redirects subsequent typing into another paragraph. Both endpoints of body and
Notes selections are retained, including direction; Notes affinity is retained.
Metadata-only and identical-visible-text updates keep interior offsets.
Positions inside changed citation results move to the replacement end, while
exact starts remain before the field. Replaced bibliography-owned positions
use its start/end boundary. Removed or converted sole-note positions return to
the body anchor. New citation/research insertion retains its explicit caret
destination; cross-processor transfer keeps its existing separate policy.

The [continuation record](../../validation/zotero-parity-20261122/README.md)
tracks incoming-ref reconciliation, remote checkpoints and local validation.
Passive positions in unchanged frames and generated contents paragraphs do
not make those stories eligible for native Zotero fields. That position
increment left visible `Field.select` context and malformed-field recovery as
separate gaps. The following increments add selected-field presentation and
bounded recovery for damaged metadata with complete structural ownership.

### Selected-field context continuation (22 November 2026)

An explicit native `Field.select` now exposes freshly validated original
source ranges and renders a temporary highlight beneath the document text.
The prompt shows the current citation or bibliography, bounded surrounding
prose and its body/footnote/endnote location. Multipart bibliographies retain
each entry's ownership; note display offsets exclude generated labels. The
writing caret, forward/backward selection, active Notes target, focus, dirty
state and undo history remain independent of the presentation. Zotero's
protocol-selected field still drives its own cursor-in-field responses.

Source ranges never come from pending insertion or transfer-import clones.
Those fields have an explicit pending status, with no unpublished text or
detached model handle exposed as live content. Deletion, unlinking, insertion
transitions, completion, cancellation, callback errors and stale host targets
clear or suppress the presentation. Each prompt belongs to its own operation,
so an older prompt cannot adopt a newer selection. Temporary scrolling is
bounded by the canvas and returns to the prior view only when the user has
not moved or changed the target. Context remains scrollable in compact
commands and the full references workspace.

The [source and validation record](../../validation/zotero-field-context-20261122/README.md)
separates controlled HTTP/controller/widget/raster checks from installed
Zotero, Word and LibreOffice acceptance. The metadata-recovery increment below
builds on this original-source presentation.

### Damaged-metadata recovery continuation (22 November 2026)

Native transactions now admit recognized citation fields with malformed JSON
or invalid citation schema, and bibliography fields with invalid JSON, when
their complete result packets have exclusive supported owners. A citation
still occupies one supported paragraph; a multipart bibliography must own
complete, contiguous entry paragraphs in one actual block container. The
native adapter sends the damaged payload to Zotero without manufacturing a
repair. Explicit `Field.select` uses the original field's source highlight,
excerpt and location while the prompt identifies its damaged metadata.

All repair callbacks stay detached until completion. Zotero's temporary empty
citation reset is accepted only as an intermediate recovery state and is never
saved as an active citation. Every remaining active field must have valid final
metadata. Cancellation, unfinished repair, changed source or stale host state
keeps the staged result unapplied; a successful repair is one undoable change
and persists through DOCX save/reopen.

Quds also offers confirmed per-field **Convert to text** for eligible damaged
metadata. This preserves the visible result and formatting; undo restores the
original code, and a reopened converted file contains ordinary text. Native
`Field.removeCode` likewise preserves cached text, while `Field.delete` removes
it. The adapter follows the callback Zotero sends: a native corrupt-reference
**No** choice must not be documented as invariably preserving the result.
Document-wide unlinking now uses the same native ownership checks for complete
damaged fields. Its confirmation identifies the damaged count, and every field
is retained if any conversion is unsafe. The
[continuation record](../../validation/zotero-parity-next-20261122/README.md)
owns this extension's source and qualification.

Locked, nested, opaque or incomplete packets, cross-owner ranges, shared
paragraph/result objects and unsupported stories remain guarded. This
increment does not infer missing Word field boundaries or solve arbitrary
structural corruption. The
[recovery work record](../../validation/zotero-field-recovery-20261122/README.md)
records the bounded contract and local qualification. Installed Zotero repair
dialogs and Word/LibreOffice round trips still require acceptance against
identified release versions; this is not a claim of complete plugin parity.

The [combined round-trip completion](../../validation/zotero-roundtrip-complete-20261121/README.md)
reconciles the latest accepted bibliography, image, note-style and Mail work.
It adds semantic uppercase import with preserved raw text and citation
boundaries, and corrects continuous-header picture identity and inline
annotation-picture formatting. Its qualification records four real converter
fixture routes, separate PNG/JPEG cycles, bounded intake and the exact source.
Installed Zotero/Word/LibreOffice acceptance remains a separate next step.

1. **Complete cross-application separator acceptance.** The
   [active-separator increment](../../validation/zotero-footnote-separators-20261121/README.md)
   delivers the native model, note reservation/pagination, editor/PDF rendering,
   explicit ODT import/export and bounded native DOCX persistence. Direct
   LibreOffice ODT saves preserve the tested geometry and active references.
   Its custom-DOCX separator normalization remains a retained failed route;
   installed Word rendering and live Zotero plugin acceptance are still open.
   A broader DOCX mapping or host-specific workaround requires separate
   evidence before this route can be called interoperable.
2. **Qualify release-host editable ODT workflows and production formatting.**
   Use the implemented carrier and retained synthetic fixtures with current
   Word/LibreOffice and their actual Zotero plugins. Resolve any converter findings
   against identified release versions. Check citations, rich bibliographies,
   authored notes, tables, images and repeated transfers. Extend the bounded
   [native ODT reader](native-odt-input.md) from additional preserved real
   documents, using the retained prose/style qualification as a baseline.
   Active Asian typography and richer note/page structures retain their own
   acceptance requirements. Exercise the explicit
   [editable ODT export](native-odt-output.md) with actual Zotero plugins:
   Refresh, citation editing, bibliography editing, style changes and repeated
   saves. The normal imported document still saves as DOCX; an ODT export copy
   does not redirect that save destination.
   Retain failing historical relative-table files and continued-list conversions as separate
   regression targets rather than treating regenerated passing fixtures as
   evidence for those earlier routes.
3. **Extend table structure and formatting.** Improve merged-row height distribution and map
   header/footer row groups and custom styles to native structures with explicit
   ownership. Qualify their citation order, geometry, save/reopen behavior and
   rendering before accepting them. Add table-cell editing in the Notes pane
   deliberately; its current text view exposes surrounding paragraphs.
4. **Extend image fidelity deliberately.** Handle JPEG orientation and
   grayscale/CMYK output consistently in editor, DOCX and PDF before removing
   current refusals. Additional raster formats need matching rendering and
   resource bounds, rather than a permissive data-URI allowlist.
5. **Extend structural replacement deliberately.** Cell-local paragraph ranges
   are implemented. Model ranges crossing cells and content-control boundaries,
   comments, existing fields and note references before accepting those
   selections. Preserve the ordinary-paragraph range,
   authored-note, stale-selection, composition and undo guarantees already delivered.
6. **Run release-host acceptance.** Exercise current native Zotero, Word and
   LibreOffice with a synthetic library on each supported desktop platform.
   Check picker cancellation, damaged-metadata repair choices and their exact
   delete/unlink behavior, metadata updates, note-style conversion,
   image/ink annotation and horizontally/vertically merged table insertion, adjacent-citation
   refresh, bibliography refresh, saved-file
   reopening and return-to-writing focus. Record exact application versions,
   source and artifacts. Browser and mobile support require their own acceptance scope.
   Qualify any legacy Apache OpenOffice target separately with explicitly
   identified application, Zotero and plugin versions.

7. **Qualify Zotero item navigation on installed desktop hosts.** The
   [safe item selection increment](../../validation/zotero-selection-links-20261122/README.md)
   adds explicit Zotero desktop selection from loaded local/group item details
   and unambiguous stored citation identities, without changing the citation.
   Exercise `zotero://select/…` on macOS, Windows and Linux with the active
   Zotero installation; verify closed-app handler recovery, missing items,
   different profiles, group permissions and return focus. A personal Web API
   ID alone does not identify the active desktop profile; do not auto-select
   such an item without a locally verified identity handshake.
Each step should begin with a bounded remote-ref intake, preserve original
incoming ancestry, save incremental remote checkpoints, run meaningful local
checks, and merge the qualified result. GitHub Actions are not a required wait
path for these continuations.

## Primary references

- [Current Zotero word-processor plugin requirements](https://www.zotero.org/support/system_requirements)
- [Supported applications and plugin troubleshooting](https://www.zotero.org/support/word_processor_plugin_troubleshooting)
- [Zotero Word plugin workflows](https://www.zotero.org/support/word_processor_plugin_usage)
- [Zotero LibreOffice plugin workflows](https://www.zotero.org/support/libreoffice_writer_plugin_usage)
- [Zotero 9 Add Annotation](https://www.zotero.org/blog/zotero-9/#add-annotation)
- [HTTP citing protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [Word processor transfer guidance](https://www.zotero.org/support/kb/moving_documents_between_word_processors)
- [Pinned annotation serialization](https://github.com/zotero/zotero/blob/c5b271dd05050257b6e035db6347beedbabbd73e/chrome/content/zotero/xpcom/editorInstance.js)
- [Pinned embedded-note image export](https://github.com/zotero/zotero/blob/c5b271dd05050257b6e035db6347beedbabbd73e/chrome/content/zotero/xpcom/data/notes.js)
- [Pinned native note insertion](https://github.com/zotero/zotero/blob/c5b271dd05050257b6e035db6347beedbabbd73e/chrome/content/zotero/xpcom/integration.js)
- [Pinned note-editor image and table schema](https://github.com/zotero/note-editor/blob/bdf61e0c275e483c3068ce4fcb86b44691b22afc/src/core/schema/nodes.js)
- [ProseMirror table serialization schema](https://github.com/ProseMirror/prosemirror-tables/blob/v1.7.1/src/schema.ts)
- [Pinned native Refresh citation merging](https://github.com/zotero/zotero/blob/98f6486db71115d4198d1f746f487aef45805a2b/chrome/content/zotero/xpcom/integration.js)
- [Pinned HTTP integration field and capability contract](https://github.com/zotero/zotero/blob/98f6486db71115d4198d1f746f487aef45805a2b/chrome/content/zotero/xpcom/httpIntegrationClient.js)
- [Pinned ProseMirror span and column-width schema](https://github.com/ProseMirror/prosemirror-tables/blob/a99f70855f2b3e2433bc77451fedd884305fda5b/src/schema.ts)
- [Pinned ProseMirror table column sizing](https://github.com/ProseMirror/prosemirror-tables/blob/a99f70855f2b3e2433bc77451fedd884305fda5b/src/tableview.ts)
- [Pinned ProseMirror column resizing](https://github.com/ProseMirror/prosemirror-tables/blob/a99f70855f2b3e2433bc77451fedd884305fda5b/src/columnresizing.ts)
