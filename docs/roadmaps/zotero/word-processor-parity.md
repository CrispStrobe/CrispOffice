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
[nested-table work record](../../validation/zotero-nested-tables-20261121/README.md)
tracks bounded nested research content and its qualification. The
[table-cell range work record](../../validation/zotero-table-cell-ranges-20261121/README.md)
tracks the latest cell-local editing increment. The
[document-transfer work record](../../validation/zotero-transfer-20261121/README.md)
records the latest source, incoming-work reconciliation, remote checkpoints,
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
| Bibliography | Native add/edit, entry paragraphs, rich runs, hanging indents, spacing and tab stops | Replacement requires a complete exclusively owned bibliography range |
| Unlink citations | Explicit individual and document-wide conversion with undo | Verify final target-application files separately |
| Add Note | Rich paragraphs, headings, nested lists up to nine levels, multiparagraph items, links, pictures, rectangular tables nested up to eight levels with combined row/column spans and active citations; insertion in body or authored notes and replacement across consecutive ordinary paragraphs in one section, note or table cell | Table payloads require a main-flow destination; cross-cell/control ranges, selected protected/structural content, compact merged-row height distribution, header/footer row groups, custom table styling and custom/reversed list markers remain unsupported |
| Add Annotation | Zotero 9+ native annotation picker, text/comments and supported PNG image/ink content with active citations | Uses the same bounded image/content envelope as Add Note |
| Library/source discovery | Local/online catalogs, collections, saved searches, tags, source details, cited-source reuse and occurrence navigation | Local and online catalog APIs have different connection/version requirements |
| Research materials | Read-only direct-child note previews and attachment metadata | No separate attachment-file download or Zotero library write workflow |
| DOCX persistence | Active fields/preferences, native notes, rich bibliography structure, tables and embedded pictures use supported save/reopen paths | Local tests are separate from actual Word/LibreOffice application round trips |
| Cross-word-processor transfer | Native export/import handshake, temporary metadata hyperlinks, DOCX import/save/reopen and ODT carrier export; complete native formatting before import publication | Direct native ODT reference marks and installed Zotero/Word/LibreOffice plugin acceptance remain separate; actual converter findings are recorded explicitly |

The native controls use Zotero's own CSL processor. The separate basic/offline
citation and single-item preview/export paths retain their narrower formatting
contract; they are not evidence of complete document-wide CSL parity.

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
limitations. DOCX is the incoming format for Quds. ODT export uses the temporary
hyperlink carrier; direct native ODT `ReferenceMark` import is not implemented.
Installed native-plugin acceptance remains a separate gate.

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
main-flow destination; supporting existing nested-cell ownership does not add
nested-table payload parsing.

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

## Next implementation and acceptance steps

1. **Finish installed-application transfer acceptance and native ODT input.**
   Use the implemented carrier and retained synthetic fixtures with current
   Word/LibreOffice and their actual Zotero plugins. Resolve any converter findings
   against identified release versions. Check citations, rich bibliographies,
   authored notes, tables, images and repeated transfers. Implement native ODT
   reference-mark/preference ownership in the ODF reader before claiming direct
   active-ODT editing; the current Quds import path is DOCX.
2. **Extend table structure and formatting.** Improve merged-row height distribution and map
   header/footer row groups and custom styles to native structures with explicit
   ownership. Qualify their citation order, geometry, save/reopen behavior and
   rendering before accepting them. Add table-cell editing in the Notes pane
   deliberately; its current text view exposes surrounding paragraphs.
3. **Extend image fidelity deliberately.** Handle JPEG orientation and
   grayscale/CMYK output consistently in editor, DOCX and PDF before removing
   current refusals. Additional raster formats need matching rendering and
   resource bounds, rather than a permissive data-URI allowlist.
4. **Extend structural replacement deliberately.** Cell-local paragraph ranges
   are implemented. Model ranges crossing cells and content-control boundaries,
   comments, existing fields and note references before accepting those
   selections. Preserve the ordinary-paragraph range,
   authored-note, stale-selection, composition and undo guarantees already delivered.
5. **Run release-host acceptance.** Exercise current native Zotero, Word and
   LibreOffice with a synthetic library on each supported desktop platform.
   Check picker cancellation, metadata updates, note-style conversion,
   image/ink annotation and horizontally/vertically merged table insertion, adjacent-citation
   refresh, bibliography refresh, saved-file
   reopening and return-to-writing focus. Record exact application versions,
   source and artifacts. Browser and mobile support require their own acceptance scope.
   Qualify any legacy Apache OpenOffice target separately with explicitly
   identified application, Zotero and plugin versions.

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
