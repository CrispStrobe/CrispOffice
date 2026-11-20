# Zotero word-processor parity

This roadmap compares Quds' native desktop integration with Zotero's Word and
LibreOffice workflows. It distinguishes implemented behavior, deliberate
content limits and interoperability acceptance. The older OpenOffice naming
does not change the need to test the actual target application and file format.

The [usage guide](../../zotero-support.md) describes the current controls. The
[embedded-image continuation](../../validation/zotero-note-images-20261120/README.md)
records the latest source, local evidence and incoming-work reconciliation.
Historical results retain their original source and platform attribution.

## Workflow coverage

| Workflow | Quds implementation | Remaining boundary |
| --- | --- | --- |
| Add/edit citation | Native Zotero picker, selected catalog sources, locators, prefixes/suffixes, multiple items, body and authored-note caret | Unsupported stories and structural ranges remain guarded |
| Document preferences | Native style, locale and inline/footnote/endnote preferences stored in the document | Conversion refuses authored notes whose extra content would be lost |
| Refresh | Complete supported document sequence sent to Zotero's processor, including note order, numeric renumbering, disambiguation and style-dependent ibid. | Live acceptance must be repeated on the exact release/host |
| Bibliography | Native add/edit, entry paragraphs, rich runs, hanging indents, spacing and tab stops | Replacement requires a complete exclusively owned bibliography range |
| Unlink citations | Explicit individual and document-wide conversion with undo | Verify final target-application files separately |
| Add Note | Rich paragraphs, headings, flat lists, ordinary links, active citations and supported embedded pictures | Body caret only; tables, nested lists and multiparagraph list items remain unsupported |
| Add Annotation | Zotero 9+ native annotation picker, text/comments and supported PNG image/ink content with active citations | Uses the same bounded image/content envelope as Add Note |
| Library/source discovery | Local/online catalogs, collections, saved searches, tags, source details, cited-source reuse and occurrence navigation | Local and online catalog APIs have different connection/version requirements |
| Research materials | Read-only direct-child note previews and attachment metadata | No separate attachment-file download or Zotero library write workflow |
| DOCX persistence | Active fields/preferences, native notes, rich bibliography structure and embedded pictures survive supported save/reopen paths | Local tests are separate from actual Word/LibreOffice application round trips |
| Cross-word-processor transfer | Explicit transfer limitations remain documented | Active ODT field transfer and Zotero export/import handshakes need a dedicated qualified implementation |

The native controls use Zotero's own CSL processor. The separate basic/offline
citation and single-item preview/export paths retain their narrower formatting
contract; they are not evidence of complete document-wide CSL parity.

## This increment: embedded research pictures

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

## Next implementation and acceptance steps

1. **Preserve richer note structure.** Extend nested and multiparagraph lists,
   then tables, using native Word structures and explicit ownership. Include
   citations in every supported block, surrounding-text preservation, independent
   list numbering, save/reopen and single-step undo. Keep unsupported formatting
   atomic until it has a real model mapping.
2. **Broaden insertion targets.** Add research-note insertion into an authored
   footnote/endnote and replacement of a deliberate selection. Specify how
   Zotero-generated citations inherit the target story and how note-style
   citations avoid nested notes. Exercise stale selections and active composition.
3. **Extend image fidelity deliberately.** Handle JPEG orientation and
   grayscale/CMYK output consistently in editor, DOCX and PDF before removing
   current refusals. Additional raster formats need matching rendering and
   resource bounds, rather than a permissive data-URI allowlist.
4. **Qualify active document transfer.** Establish Word/LibreOffice fixtures
   containing active citations, rich bibliographies, authored notes and images.
   Verify the actual Zotero transfer/import/export protocol and ODT field
   representation before advertising cross-format editing parity.
5. **Run release-host acceptance.** Exercise current native Zotero, Word and
   LibreOffice with a synthetic library on each supported desktop platform.
   Check picker cancellation, metadata updates, note-style conversion,
   image/ink annotation insertion, bibliography refresh, saved-file reopening
   and return-to-writing focus. Record exact application versions, source and
   artifacts. Browser and mobile support require their own acceptance scope.

Each step should begin with a bounded remote-ref intake, preserve original
incoming ancestry, save incremental remote checkpoints, run meaningful local
checks, and merge the qualified result. GitHub Actions are not a required wait
path for these continuations.

## Primary references

- [Zotero Word plugin workflows](https://www.zotero.org/support/word_processor_plugin_usage)
- [Zotero LibreOffice plugin workflows](https://www.zotero.org/support/libreoffice_writer_plugin_usage)
- [Zotero 9 Add Annotation](https://www.zotero.org/blog/zotero-9/#add-annotation)
- [HTTP citing protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [Word processor transfer guidance](https://www.zotero.org/support/kb/moving_documents_between_word_processors)
- [Pinned annotation serialization](https://github.com/zotero/zotero/blob/c5b271dd05050257b6e035db6347beedbabbd73e/chrome/content/zotero/xpcom/editorInstance.js)
- [Pinned embedded-note image export](https://github.com/zotero/zotero/blob/c5b271dd05050257b6e035db6347beedbabbd73e/chrome/content/zotero/xpcom/data/notes.js)
- [Pinned native note insertion](https://github.com/zotero/zotero/blob/c5b271dd05050257b6e035db6347beedbabbd73e/chrome/content/zotero/xpcom/integration.js)
- [Pinned note-editor image schema](https://github.com/zotero/note-editor/blob/bdf61e0c275e483c3068ce4fcb86b44691b22afc/src/core/schema/nodes.js)
