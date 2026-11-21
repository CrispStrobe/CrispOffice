# Zotero research replacement across paragraphs

Implementation checkpoint: `6ac854de0583b7955470648916c53c76b67c0fff`, tree
`5bd40fb467d6710987e06634934e84c3dc513bfa`.

This increment extends Add Note and Add Annotation to consecutive ordinary
paragraphs in one body section or authored footnote/endnote. It follows the
range milestone in the [parity roadmap](../../roadmaps/zotero/word-processor-parity.md).
Complete local qualification and the publication intake are being recorded
before the final merge. Intermediate remote checkpoints preserve the work.

## Behavior

- Replace the selected ordinary text and paragraph breaks; retain the rich
  unselected prefix and suffix, links and active citation packets.
- Preserve original suffix paragraph formatting when the suffix remains in a
  separate paragraph. A single plain inserted paragraph joins both fragments
  under the starting paragraph's formatting.
- Keep native paragraphs, headings, lists, images and tables, including active
  citation ownership. Existing table/image/content bounds still apply.
- Map both Notes-pane endpoints and preserve the automatic note marker and
  separator, including raw engine offset zero and a whitespace-leading suffix.
- Retain one atomic undo/redo operation, original selection direction on undo,
  and cancellation, composition, stale-target and document-revision guards.
- Retain active fields across repeated Quds DOCX save/reopen and another
  multi-paragraph replacement.

Ranges are limited to 10,000 consecutive ordinary main-flow paragraphs in one
section or note. They cannot cross tables, frames, controls, section boundaries
or selected fields, note references, images, comments and bookmark boundaries.
Paragraph-owned bookmarks, unrepresented native field flags, zero-width
citations on consumed boundaries and shared paragraph objects are guarded.
Ordinary single-paragraph citation editing keeps its established behavior.

## Initial intake

The [initial intake](intake/README.md) captured 329 fork/upstream branch and PR
heads. It proved 304 ancestors and 24 exact historical equivalents, then
integrated the one remaining continuation, `bbccae1b`. Remote checkpoint
`e5b9240512158c329dd2671aa9f36eb08cb74e11` retains both main and that branch as
parents. Thirty distinct incoming evidence files keep their exact bytes;
source-specific narratives are not substituted for current test results.

The only new incoming Mail behavior is a compatibility alias for inert remote
image candidates. The current algorithms and stronger journal, cancellation
and image-budget guarantees remain intact. Its six affected suites passed
60 unique local cases with unchanged source inputs; the final evidence bundle
will retain that source-bound receipt.

## Verification boundaries

The new regression families exercise body/footnote/endnote ranges, both native
research commands, forward/backward and empty endpoints, rich content, tables,
active citation order, native field packets, cancellation, stale edits,
composition, exact undo/redo, protected structures and DOCX persistence.
Independent review identified and verified fixes for paragraph-owned metadata,
shared paragraph identity, note-separator whitespace and native endpoint
packets. Its source-bound report is recorded with publication evidence.

Local protocol/model/controller tests do not establish live Zotero or installed
Word/LibreOffice/OpenOffice interoperability. Active ODT fields and Zotero's
cross-word-processor export/import handshake remain explicit next work. The
supported current comparison application is LibreOffice; any historical Apache
OpenOffice target requires separately specified application/plugin versions.

GitHub Actions, workflow/check/status endpoints and queue completion are not
used as acceptance gates. No workflow or dependency policy is changed.
