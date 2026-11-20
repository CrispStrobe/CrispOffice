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
[research-table work record](../../validation/zotero-research-tables-20261120/README.md)
records the latest source, incoming-work reconciliation, remote checkpoints,
checks and remaining acceptance. The earlier
[structured-note continuation](../../validation/zotero-parity-continuation-20261120/README.md)
retains its evidence for embedded pictures and research lists. Historical
results retain their original source and platform attribution.

## Workflow coverage

| Workflow | Quds implementation | Remaining boundary |
| --- | --- | --- |
| Add/edit citation | Native Zotero picker, selected catalog sources, locators, prefixes/suffixes, multiple items, body and authored-note caret | Unsupported stories and structural ranges remain guarded |
| Document preferences | Native style, locale and inline/footnote/endnote preferences stored in the document | Conversion refuses authored notes whose extra content would be lost |
| Refresh | Complete supported document sequence sent to Zotero's processor, including note order, numeric renumbering, disambiguation and style-dependent ibid. | Live acceptance must be repeated on the exact release/host |
| Bibliography | Native add/edit, entry paragraphs, rich runs, hanging indents, spacing and tab stops | Replacement requires a complete exclusively owned bibliography range |
| Unlink citations | Explicit individual and document-wide conversion with undo | Verify final target-application files separately |
| Add Note | Rich paragraphs, headings, nested lists up to nine levels, multiparagraph items, links, pictures, rectangular tables and active citations; insertion in body or authored notes and replacement within one paragraph | Table payloads require a main-flow destination; merged/nested tables, header/footer row groups, custom table styling, broader selections and custom/reversed list markers remain unsupported |
| Add Annotation | Zotero 9+ native annotation picker, text/comments and supported PNG image/ink content with active citations | Uses the same bounded image/content envelope as Add Note |
| Library/source discovery | Local/online catalogs, collections, saved searches, tags, source details, cited-source reuse and occurrence navigation | Local and online catalog APIs have different connection/version requirements |
| Research materials | Read-only direct-child note previews and attachment metadata | No separate attachment-file download or Zotero library write workflow |
| DOCX persistence | Active fields/preferences, native notes, rich bibliography structure, tables and embedded pictures use supported save/reopen paths | Local tests are separate from actual Word/LibreOffice application round trips |
| Cross-word-processor transfer | Explicit transfer limitations remain documented | Active ODT field transfer and Zotero export/import handshakes need a dedicated qualified implementation |

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
Selections across paragraphs or through existing fields, atomic content,
commented text or structural/protected ranges remain guarded. Native complex
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

Merged or nested tables, tables inside list items, unequal row lengths,
separate header/footer row groups, captions and custom table/row/cell styling
remain unsupported. The
[implementation and validation record](../../validation/zotero-research-tables-20261120/README.md)
separates local source checks from live Zotero and Word/LibreOffice acceptance.
This increment does not establish active ODT transfer or complete plugin parity.

## Next implementation and acceptance steps

1. **Broaden replacement ranges deliberately.** Extend beyond single-paragraph
   text selections only after modeling ownership of paragraph boundaries,
   comments, content controls, existing fields and note references. Keep the
   authored-note ownership, stale-selection, composition and undo guarantees
   established by the existing increments.
2. **Extend table structure and formatting.** Map merged cells, nested tables,
   header/footer row groups and custom styles to native structures with explicit
   ownership. Qualify their citation order, geometry, save/reopen behavior and
   rendering before accepting them. Add table-cell editing in the Notes pane
   deliberately; its current text view exposes surrounding paragraphs.
3. **Extend image fidelity deliberately.** Handle JPEG orientation and
   grayscale/CMYK output consistently in editor, DOCX and PDF before removing
   current refusals. Additional raster formats need matching rendering and
   resource bounds, rather than a permissive data-URI allowlist.
4. **Qualify active document transfer.** Establish Word/LibreOffice fixtures
   containing active citations, rich bibliographies, authored notes, tables and
   images. Verify the actual Zotero transfer/import/export protocol and ODT field
   representation before advertising cross-format editing parity.
5. **Run release-host acceptance.** Exercise current native Zotero, Word and
   LibreOffice with a synthetic library on each supported desktop platform.
   Check picker cancellation, metadata updates, note-style conversion,
   image/ink annotation and table insertion, bibliography refresh, saved-file
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
