# Zotero in Quds Office

Quds Office supports local and online Zotero libraries, native Zotero citation
dialogs, active DOCX citation fields, generated bibliographies, research notes
and annotations, and editable Zotero ODT import/export.

The full implementation and validation record is preserved in
[Zotero details](zotero-support-details.md).

## Choose a workflow

| You want to | Use | Requirement |
| --- | --- | --- |
| Browse and search references | **Insert → References** | Local catalog or Zotero Web API |
| Open a library item in Zotero desktop | **Reference details → Open in Zotero** | Validated local or group identity and a desktop protocol handler |
| Insert/edit citations with Zotero's picker | **Insert → Zotero → Document** | Zotero desktop running on the same computer |
| Insert a note or annotation | **Add Zotero note / annotation** | Zotero 9+ for direct annotations |
| Refresh citations and build a bibliography | **Document** commands | Active citation fields in an editable DOCX |
| Repair damaged citation or bibliography metadata | **Document → reference actions → Repair in Zotero…** | Running Zotero desktop and a complete, safely owned field |
| Work from LibreOffice Writer | Open a supported native ODT, then save DOCX | Supported ODT subset |

## Native desktop formatting

On native desktop hosts, open a Word document and choose **Insert → Zotero →
Document**. Quds uses Zotero's local HTTP Citing Protocol, so no API key is
needed and Zotero must already be running.

Available commands:

- **Add/Edit citation** — `Ctrl+Alt+C` (`Cmd+Alt+C` on macOS);
- **Refresh citations** — `Ctrl+Alt+R` (`Cmd+Alt+R` on macOS);
- **Bibliography**;
- **Citation style**;
- **Add Zotero note**;
- **Add Zotero annotation** (Zotero 9+).

Changes are applied as one undo step. Cancelling the picker or declining a
formatting review returns focus to the document without changing it. Finish IME
composition before starting a command.

Refresh and citation-style changes retain your writing position in surrounding
prose, even when earlier citations grow or a bibliography changes its number
of paragraphs. Body and Notes selections retain their direction. A caret
inside changed citation text moves to that citation's new end; a caret exactly
at its start stays before it. If a citation-only note is removed or converted,
its writing position returns to the corresponding body anchor. Undo restores
the original selection, and redo restores the updated position.

When Zotero explicitly selects a citation or bibliography for a native prompt,
Quds temporarily highlights that reference and shows its current document text with its body,
footnote or endnote location. The prompt includes surrounding prose and a
scrollable excerpt for long references. Your writing selection stays in place.
The temporary view ends when Zotero finishes or the operation is cancelled;
any scrolling or zooming you do while reviewing it is respected. A new or
transferred reference whose position is still being prepared is identified
as pending.

Switching from Word to Mail or another app cancels the pending operation for
that Word view, including when you return before Zotero responds. Close and
reopen the Zotero workspace to start a new operation. The citation and refresh
chords remain reserved when customizing workspace shortcuts.

Native desktop integration is available even before the catalog browser is
connected. The Zotero windows may open behind the office app.

## Reopen references saved by LibreOffice

Supported LibreOffice-saved DOCX citations remain editable when Writer has
added ordinary character formatting or empty formatted runs inside the field
code. Refresh and citation editing retain that internal formatting; the full
operation is still one undo step. Unknown field metadata, locks, revisions and
incomplete structures continue to block editing.

Native ODT opening also accepts the observed unnumbered heading declarations
and Writer's exact clear-shading marker paired with an explicit supported
background color. The retained body, footnote and table-cell DOCX files retain
editable citations through native Refresh and repeated DOCX saves. The retained
ODT files also pass native DOCX and editable ODT save/reopen checks. The retained
DOCX table-cell file now reopens through explicit editable ODT export with its
four supported border sides and active citations intact, including borders
stored using Word's leading/trailing edge names. Installed Word/LibreOffice
Zotero-plugin acceptance remains a separate check. See the
[converter work record](validation/zotero-converter-parity-20261122/README.md)
and the later [border qualification](validation/zotero-table-borders-20261122/README.md),
along with [supported input details](zotero-support-details.md#libreoffice-field-formatting).

## Repair damaged reference metadata

An existing citation or bibliography can retain readable text even when its
stored reference data is damaged. The Document tab identifies that condition
and offers **Repair in Zotero…** when the field has a complete, safely owned
structure. Native Refresh can also pass those fields to Zotero for recovery.
This covers damaged citation JSON or citation metadata that fails validation,
and bibliography JSON that cannot be decoded.

When Zotero selects the damaged reference, its prompt shows the original text
and location. The original code, text and formatting remain unchanged until
the complete operation succeeds. An empty citation used temporarily by Zotero
during repair is never saved as an active field. Cancellation, unfinished
repair or a changed document leaves the staged result unapplied. Successful
repair is one undoable change, and active fields survive DOCX save/reopen.

To keep the visible wording without a live reference, choose Quds'
**Convert to text…** or the reference menu's **Convert to text (undoable)**.
For damaged metadata, Quds asks you to confirm. This keeps the text and
formatting; undo restores the original damaged field. A reopened converted
file contains ordinary text. Zotero controls its own repair choices and can
request deletion, so its native **No** button is not a substitute for Quds'
explicit conversion action.

**Document → Unlink all citations…** also converts complete references with
damaged metadata. Its confirmation shows the damaged-field count. The complete
document conversion keeps visible text, formatting and notes in one undo step;
if any reference cannot be converted safely, every field stays unchanged.

Locked, nested, opaque, incomplete or ambiguously owned fields remain
protected. Quds does not infer missing field boundaries or repair a field
shared across incompatible owners. See the
[recovery scope and validation record](validation/zotero-field-recovery-20261122/README.md)
for the supported structures and remaining installed-application acceptance.

## References workspace

Use **Insert → References** in Quds Studio to:

- browse imported references and inspect metadata and attachments;
- search and sort local or online libraries;
- insert text and image annotations from Zotero;
- insert research notes with supported quotations, lists, links and pictures;
- change the sources in an existing citation;
- navigate from a citation to its bibliography entry;
- open a verified local or group-library item in Zotero desktop;
- convert citations to ordinary text;
- export an editable Zotero ODT copy.

Citation placeholders remain active fields. Reordering, refreshing or changing
the style updates numbering and the bibliography. Moving an active document
between Word and Writer is supported only through the documented formats and
conversion path.

## Notes and annotations

**Add Zotero note** imports research notes with supported formatting, block
quotations, lists, pictures and links. **Add Zotero annotation** imports selected text or image
annotations directly. Both commands require a caret or selection outside an
existing field.

Inserted pictures become native inline images. Unsupported content is refused
rather than flattened into an unrelated style. Annotation placement follows the
document's Zotero preferences for inline, footnote or endnote citations.

Block quotations keep their own paragraphs and active citations, with 18 pt
of additional left indentation per level, up to eight levels. Following prose
keeps its original formatting. Headings and lists inside a quotation are
supported; quotations inside list items and tables inside quotations remain
outside this increment. See the
[quotation details](zotero-support-details.md#block-quotations-in-research-notes).

Research-note paragraphs and headings also retain explicit left-to-right or
right-to-left direction, left/right/center/justified alignment, and Zotero's
exported indentation levels 1–7. Each indent level adds 30 pt on the exported
side, alongside any list or quotation indentation. Authored empty paragraphs
keep their direction when you return to writing.

Opaque text colors and highlights in exported notes are preserved in the
editor and through DOCX saving, including highlight colors outside Word's
named palette. Unsupported color expressions or paragraph layouts cause the
whole insertion to be refused. See the
[note-formatting details](zotero-support-details.md#paragraph-layout-and-colors-in-research-notes)
for the accepted forms and exchange boundaries.

## Open a reference in Zotero

In a loaded reference's details, or the details of an embedded citation
source, choose **Open in Zotero** to ask the operating system to select that
item in the desktop Zotero application. This uses Zotero's
`zotero://select/…` protocol; it does not edit or refresh the reference.

The action is offered only for an item from the active local desktop catalog
or an unambiguous stored local/group source identity. Group-library selection
depends on having that group accessible in Zotero. A remote personal-library
Web API ID does **not** establish which Zotero desktop profile is active, so
Quds does not guess or offer a selection link for it. Offline records,
malformed URIs and conflicting library identities also have no launch action.
If Zotero or the protocol handler is unavailable, the details remain open;
the citation is unchanged.

## ODT interoperability

Open a supported native LibreOffice ODT containing Zotero fields to convert it
into an editable Word document with active citations. Save remains source-bound
and produces DOCX; the original ODT is not silently overwritten.

**File → Export Zotero ODT…** creates a separate ODT copy with supported native
Zotero marks and preferences. The export is a deliberate copy, not an in-place
ODF editor.

The bounded ODT path supports the documented Zotero field, citation, note and
inline-picture subset. Unknown ODF XML, unsupported field structures and
unreviewed page styles remain outside the conversion.

Supported research tables retain solid borders and active citations through
editable ODT export and reopening. Each table can use one opaque RGB color and
a width from 0.25 to 12 pt in eighth-point steps, with individual sides enabled
or disabled. Nested tables can use different strokes. Inherited styles,
explicitly disabled edges and supported merged cells retain their ownership;
uniform cell padding is preserved. Import requires an explicit collapsing border
model. The bounded ODT reader refuses mixed widths/colors within a table,
dashed/double borders, visible separating borders and conflicting covered-cell
overrides. This does not qualify arbitrary per-cell strokes or styles in an
external DOCX.

DOCX opening and saving now place leading/trailing cell borders on the correct
physical side after resolving the table's direction, including inherited
direction. Editable ODT export still refuses tables with right-to-left column
order before writing the copy; the original document and citations stay
unchanged. Supported right-to-left paragraphs inside a left-to-right table are
separate from that table-order limit.

Three research-table cases pass six actual LibreOffice saves and twelve paired
native DOCX/ODT cycles, with all 376 captured engine inputs unchanged. These
include the original black-bordered DOCX cell, a colored table with disabled
sides, and a colored vertically merged cell. The
[border interoperability record](validation/zotero-table-borders-20261122/README.md)
identifies the LibreOfficeDev build and exact scope; installed Word/LibreOffice
Zotero-plugin acceptance and identical rendering remain separate checks.

Editable ODT exchange preserves automatic decimal and lower/upper Roman
footnote and endnote numbering, including Word's default Roman endnotes.
Each note class must use one continuous sequence with a starting number from
1 to 32,768. Footnotes and endnotes can start at different numbers. Ordinary
uncited notes participate in the sequence, and citation identity and numeric
note order remain separate from the visible Roman labels. Accepted numbering
survives opening the ODT and saving the result as DOCX. Roman ordinals are
supported through 3,999, and decimal sequences through 65,535. Custom labels,
alphabetic formats, mixed settings within one note class and page/section
restarts remain outside this exchange path. See the
[numbering and unlink continuation](validation/zotero-parity-next-20261122/README.md).

Supported footnote separators retain their color, width, alignment and spacing,
with matching pagination and editor/PDF rendering. Direct editable ODT exchange
preserves the tested geometry through LibreOffice saves. Quds also retains a
bounded native DOCX representation, but LibreOffice normalizes custom DOCX
separator paragraphs. Use **Export Zotero ODT** for that qualified exchange;
the [separator work record](validation/zotero-footnote-separators-20261121/README.md)
documents the exact scope and remaining host limitations.

## Embedding in another host

Hosts can call the same controller and command layer used by Studio. The public
contract covers:

- document and reference commands;
- citation and bibliography navigation;
- research-note and annotation insertion;
- native bibliography layout and style preferences;
- undo transactions and source-bound saving.

Hosts that keep a document mounted across view changes can pass an optional
`isCurrent` predicate to `showWordZoteroDialog`. Tie it to the originating
document view and navigation generation; it stays true while Zotero's own
modal dialogs are open. A stale operation cannot publish changes or take
editing focus after completion. See the
[host-ownership qualification](validation/zotero-host-ownership-20261121/README.md).

Custom native hosts should drive callbacks through
`WordZoteroTransaction.handle`, retain their own `Document.displayAlert` UI,
and call `clearFieldContext` in their finally/disposal path. The optional
`isCurrent` predicate on `beginZoteroTransaction` also guards temporary
presentation. `presentedFieldContext` belongs to one operation;
`WordCanvas.zoteroFieldRanges` accepts its validated `sourceRanges`. Re-read
`presentedFieldContext` on controller changes instead of caching live source
ranges across document mutations. Use
`clearFieldContext(notify: false)` during widget teardown and schedule any
surviving editor repaint after unmount. The
[selected-field context record](validation/zotero-field-context-20261122/README.md)
documents this API and its local qualification.

See the [details](zotero-support-details.md) for exact command names,
async completion and cancellation behavior, and the native bibliography layout
contract.

## Limits

- Zotero desktop must be running for native picker/style/bibliography commands.
- The catalog browser and the native document commands use different transports;
  a connected catalog does not replace a missing desktop app.
- Direct annotation insertion requires Zotero 9 or later.
- Embedded images must be present in Zotero's response; Quds cannot recover an
  image Zotero omitted.
- The ODT path supports a bounded, reviewed subset, not arbitrary ODF
  round-tripping.
- No model, citation style or library data is downloaded automatically.
- Live-provider and installed-platform acceptance is separate from local tests.
- Opening a Zotero item requires an installed desktop protocol handler; an accepted launch does not guarantee the item exists in the active library.
