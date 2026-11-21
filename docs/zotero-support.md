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
| Insert/edit citations with Zotero's picker | **Insert → Zotero → Document** | Zotero desktop running on the same computer |
| Insert a note or annotation | **Add Zotero note / annotation** | Zotero 9+ for direct annotations |
| Refresh citations and build a bibliography | **Document** commands | Active citation fields in an editable DOCX |
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

Switching from Word to Mail or another app cancels the pending operation for
that Word view, including when you return before Zotero responds. Close and
reopen the Zotero workspace to start a new operation. The citation and refresh
chords remain reserved when customizing workspace shortcuts.

Native desktop integration is available even before the catalog browser is
connected. The Zotero windows may open behind the office app.

## References workspace

Use **Insert → References** in Quds Studio to:

- browse imported references and inspect metadata and attachments;
- search and sort local or online libraries;
- insert text and image annotations from Zotero;
- insert research notes with supported lists, links and pictures;
- change the sources in an existing citation;
- navigate from a citation to its bibliography entry;
- convert citations to ordinary text;
- export an editable Zotero ODT copy.

Citation placeholders remain active fields. Reordering, refreshing or changing
the style updates numbering and the bibliography. Moving an active document
between Word and Writer is supported only through the documented formats and
conversion path.

## Notes and annotations

**Add Zotero note** imports research notes with supported formatting, lists,
pictures and links. **Add Zotero annotation** imports selected text or image
annotations directly. Both commands require a caret or selection outside an
existing field.

Inserted pictures become native inline images. Unsupported content is refused
rather than flattened into an unrelated style. Annotation placement follows the
document's Zotero preferences for inline, footnote or endnote citations.

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
