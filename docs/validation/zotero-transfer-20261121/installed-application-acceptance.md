# Remaining installed-application acceptance

This matrix is the next acceptance step, not a record of completed runs. The
automated transfer fixture and local receipts are described in `README.md`.

## Record each environment

Record the Quds commit, operating system, Zotero version, word processor version,
plugin version and exact input/output hashes. Use a synthetic Zotero library with
two authors sharing surnames, repeated works, locators, a non-Latin title and an
uncited bibliography item. Keep private library data out of the retained fixtures.

Word and LibreOffice are distinct acceptance targets. Identify exact versions
for any Apache OpenOffice legacy experiment; do not infer its support from a
LibreOffice result.

## Required routes

| Route | Operations | Acceptance evidence |
| --- | --- | --- |
| Quds → Word | Prepare transfer; save DOCX; open in Word; use Zotero Refresh; edit a locator; refresh bibliography; save and reopen | All native fields active; exact item identities and unknown metadata; expected CSL text, ordering and bibliography entry layout |
| Word → Quds | Use Zotero's switch-word-processor workflow in Word; save transfer DOCX; open in Quds; import with desktop Zotero | Framing removed only after complete native formatting; fields remain editable; one undo/redo step restores each complete state |
| Quds → LibreOffice | Prepare transfer; save ODT; open in LibreOffice; use Zotero Refresh; edit a citation; save and reopen ODT | Transfer links become native reference marks; fields and preferences survive; note/table ownership and surrounding content retained |
| LibreOffice → Quds | Prepare transfer with the native plugin; save its transfer copy as DOCX; import in Quds | Complete field metadata and preferences restored; no native ODT reader behavior is inferred |
| Repeated transfer | Complete Quds → Word/LibreOffice → Quds twice | Stable citation identity, item URIs, uncited/omitted/custom bibliography metadata, note indexes and unknown fields |

## Inspect content and transactional behavior

Run the routes with inline and note styles, directly adjacent citations, multiple
citations in one authored note, citations in table cells, a multi-paragraph rich
bibliography, ordinary hyperlinks, surrounding bold/italic text and an inline
picture. Inspect Unicode metadata, locators, affixes, font settings, italic and
small-capital results, bibliography indents and spacing, note numbering, body
reading order and repeated save/reopen. Temporary link color/style must not
become the appearance of active citations.

Cancel Zotero's export and import dialogs, close the document during a callback,
change the selection/document while the operation is pending, and exercise undo
and redo after successful import/export. A pending transfer must prevent native
citation edits until import completes. A truncated code, removed hyperlink or
duplicated preferences carrier must be reported while the source stays intact.

Retain the original and returned files, the native Zotero callback transcript
with synthetic identifiers, screenshots of the restored fields and formatting,
and the exact command/version/hash receipt. Mark each route independently;
successful file conversion alone does not establish plugin acceptance.

## Separate implementation work

Directly opening native ODT Zotero reference marks requires a richer ODF reader,
modeled reference-mark ownership and preference restoration. The delivered
incoming Quds transfer route is DOCX. Do not count the ODT carrier exporter or a
LibreOffice-to-DOCX conversion as implementation of that reader.
