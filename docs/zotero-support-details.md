# Zotero support
> **Detailed reference.** See [zotero-support.md](zotero-support.md) for the current overview. This file preserves the pre-rewrite detail and historical qualification notes.


Quds Office includes local and online Zotero catalog browsing, a shared Flutter
references workspace, and DOCX citation/bibliography fields. Native desktop
hosts can now use Zotero's citation picker, document style dialog and complete
document CSL processor through its HTTP Citing Protocol. CrispCloud uses the
same engine and editor source through its guarded vendor manifest.
Supported native ODT files can also be converted into editable Word documents
with active citations and saved as DOCX.
The separate **File → Export Zotero ODT…** action creates an ODT copy with
supported native Zotero marks and preferences for LibreOffice.
Supported embedded inline pictures from Zotero notes and annotations now also
survive native ODT reopening and subsequent DOCX saves.
Uniform table margins now control native text layout, pagination and ruler
insets, and the bounded editable ODT path retains supported uniform padding.

## Native Zotero document formatting

See [Open a native LibreOffice ODT](#open-a-native-libreoffice-odt) for the
supported import subset and source-preserving DOCX save workflow. The separate
[inspection API and diagnostic](#inspect-a-native-libreoffice-odt) reports native
fields and findings without opening or changing the document.

Open Zotero on the same computer, open a Word document in Quds Office or
CrispCloud, and choose **Insert → Zotero → Document**. Native desktop hosts show
**Zotero desktop citation tools** even before connecting the catalog browser.
They need the local transport and a running Zotero application, without an API
key. Zotero's own windows may open behind the office application.

In Quds Studio, **Insert → References** also offers **Add/Edit citation**,
**Bibliography**, **Add Zotero note**, **Add Zotero annotation**, **Refresh
citations**, and **Citation style** on native desktop platforms. These show a
compact progress dialog and immediately start the selected Zotero command.
**Add/Edit citation** edits the citation at the active body or
Notes-pane caret, or one enclosing the selection within a paragraph; otherwise
it uses that insertion point. Opening **Zotero** normally also selects Document when a citation or
bibliography is at the caret, with a direct **Edit current citation…** action
for offline editing and an **Edit current reference in Zotero…** action when
desktop transport is available. A caret immediately after a field belongs to
the following text. The Document field list's **Edit in Zotero…** action remains
available for explicitly choosing a field anywhere in a supported story.

In native Studio Word, **Ctrl+Alt+C** opens Add/Edit citation and **Ctrl+Alt+R**
refreshes citations; on macOS use **Cmd+Alt+C** and **Cmd+Alt+R**. The ribbon
tooltips show these Quds shortcuts. They work from the body and Notes text
editor, require an editable Word document, and do not open another workspace
over an existing dialog. These are Quds defaults, not Zotero's Word defaults.

Direct ribbon and keyboard commands show a compact progress dialog and return
keyboard focus to the resulting body or Notes caret when Zotero finishes.
Successful changes remain one undo step. Cancelling a native picker, declining
a formatting review, or completing without changes also returns to writing.
Connection, document and formatting errors remain visible with **Return to
document**; there is no automatic network retry. **Cancel operation** waits for
Zotero to acknowledge and drain the outstanding transaction before returning.
The normal **Zotero** references workspace stays open for browsing and repeated
operations. It is available in Studio's viewing and selecting modes too;
commands that change the document still require editing mode.

Finish active input-method composition before opening Zotero. Body and Notes
composition prevent direct commands from starting; composition beginning during
native work invalidates its result. Returning to the document preserves an
unchanged composing draft.

<a id="insert-text-annotations-directly-from-zotero"></a>

### Insert text and image annotations directly from Zotero

With **Zotero 9 or later** running, place the caret or select ordinary text
across consecutive paragraphs in one body section or authored footnote/endnote, outside
existing fields, and choose **Insert → References → Add Zotero
annotation**, or **Document → Add annotation from Zotero…** in the references
workspace. Zotero opens its annotation picker, where you can browse or search
and select one or more annotations. An intermediate Zotero library note is
not required. This follows Zotero's native
[Add Annotation workflow](https://www.zotero.org/blog/zotero-9/#add-annotation),
introduced in [Zotero 9](https://www.zotero.org/support/9.0_changelog).

Quds retains the selected annotation text, embedded PNG image/ink annotations,
comments, supported formatting and links supplied by Zotero. Citation placeholders become active fields, with the
source identity and locators supplied by Zotero. Their inline, footnote or
endnote placement in the body follows the document's Zotero preferences.
Inside an authored note, citations stay in that same note without creating
nested notes; an incompatible footnote/endnote style is refused. Subsequent
**Refresh citations** and **Bibliography** commands include them in the complete
document sequence. The text, citation fields, any new notes and style preferences
apply together as one undo step and survive Quds DOCX saving and reopening.

Cancelling the picker before it supplies content also discards staged
preferences and temporary fields. Direct ribbon commands return focus to the
document after completion or cancellation. A changed insertion point, active
text composition, unsupported content or incomplete citation conversion keeps
the result from being applied.

This command uses the same supported image formats, content bounds and insertion
targets as Add Note below. Images arrive embedded in Zotero's response and
become native inline pictures; they are not downloaded from a separate URL.
Zotero itself can replace an unavailable image with explanatory text or omit
unavailable content before sending the result; Quds cannot restore content
absent from that result. Older Zotero versions do not provide the annotation
command: use **Add Zotero note** to insert supported annotation notes, or update
Zotero. The command dialog and workspace tooltip identify the version requirement.

### Insert a Zotero research note

Place the caret or select ordinary text across consecutive paragraphs in one
body section or authored footnote/endnote, outside existing fields, and
choose **Insert → References → Add Zotero note**, or **Document → Add note from
Zotero…** in the references workspace. Select a research note in Zotero's native
note picker. This imports the research content of a Zotero library note. When
the Notes pane is active, the content goes into that authored footnote/endnote.
A deliberate text selection is replaced only when Zotero supplies a complete,
supported result. Cancelling preserves the selected text and its selection.

Paragraphs, empty paragraphs, soft line breaks, heading levels 1–6, supported
character formatting, and ordinary HTTP(S), mail and Zotero links are retained.
Bullet and decimal numbered lists are retained as native Word lists, including
mixed nested lists up to nine levels and positive starting numbers. An item can
contain rich inline text, multiple paragraphs, supported pictures, and nested
lists, with active citation placeholders throughout. Only its first paragraph
receives a bullet or number; subsequent paragraphs and text after a nested list
remain indented as continuations of that item. Each nested list has its own
counter and starting number. Separate imported lists do not continue or change
surrounding document lists.
Default PDF annotation note wrappers and their title headings are recognized.
Citation placeholders become active Zotero fields with the source data, rather
than remaining ordinary hyperlinks. Zotero controls their formatting and
inline/footnote/endnote placement in the body and receives the complete document order for
later citation and bibliography updates. Documents containing imported research
notes retain the active fields through DOCX saving and reopening. Within an
authored footnote/endnote, embedded citations inherit that note's ownership and
reading order. They never create a nested note. A style requesting the opposite
note kind is refused before application. Numbered lists in each authored note
retain their own visible labels and counters when the DOCX is reopened.

The whole insertion, including new footnotes/endnotes, bibliography callbacks
and document style preferences, is staged until completion and applied as one
undoable operation. The active body or Notes caret finishes after the imported
content. Surrounding
prose and its formatting remain intact; headings and list items occupy their own
paragraphs. Undo restores the original selection, including its direction, and
the previous numbering definitions; unrelated
document parts and relationships remain intact after saving and undo/redo.
Cancelling the note picker before it supplies any text also discards temporary
fields and staged preference changes.

Selections can span up to 10,000 consecutive ordinary paragraphs in one body
section, authored note or body table cell. In a table, select text entirely
inside one cell before using **Add Note** or **Add Annotation**. This includes
the originating cell of a merged region and a cell in an existing nested table.
The selected text and intervening paragraph
breaks are replaced; unselected prefix/suffix runs, links and active citations
remain intact. A separate surviving suffix keeps its original paragraph
formatting. A single inserted ordinary paragraph joins the prefix and suffix
under the starting paragraph's formatting. The automatic note marker and its
separator stay before the imported content. Forward and backward selections,
empty paragraphs and a selection containing only a paragraph break are supported.

A multi-paragraph selection cannot cross a section, cell, nested table, frame
or content control. A cell range must contain consecutive ordinary paragraphs
in that exact cell's block list. Content-control/drawing ancestors and hidden
vertical-merge continuation cells are refused. Paragraph-owned bookmarks and
unrepresented field boundaries are guarded, as are paragraphs shared by more
than one document position. Existing fields, note references, pictures, commented
text, protected ranges and structural markers inside the selected range are
refused. This includes ordinary complex
Word fields such as DATE or REF, even when only their cached text is visible.
Selections touching bookmark boundaries or empty atomic field tokens are also
refused. Finish active text composition
first; moving the selection or editing the destination while Zotero is open
invalidates the staged result. Replacing a cell, row, table or owning block
list while the picker is open also invalidates a multi-paragraph result, even
when its visible text is unchanged. Headers, footers, comments and text frames remain
unsupported destinations. Notes containing tables require a paragraph in the
main flow of the body or authored note, outside an existing table. Lists deeper
than nine levels, custom or reversed list markers, and unsupported custom
formatting are refused with an explanation before application. Ordered-list
starting numbers must be integers from 1 to 999999. Malformed, missing, repeated
or unconverted citation placeholders also refuse the whole
result. Nothing is silently flattened to make these structures fit.

### Tables in notes and annotations

Add Note and Add Annotation preserve supported rectangular tables, including
tables nested inside cells and horizontal/vertical merged cells, as native Word tables. HTML `colspan`
values from 1 to 32 map to native `gridSpan`; `rowspan` values from 1 to 256 map
to native restart/continuation cells. Both spans can be combined in one cell.
Every row must cover the same number of logical columns, up to 32, including
positions occupied by preceding row spans. A fully covered row can contain no
authored cells. Spans must fit the actual rows and stay within their row group;
overlaps, uncovered positions and malformed spans refuse the whole insertion.
Cells can contain ordinary or empty paragraphs, soft line breaks,
headings, supported character formatting, links, lists, pictures, active
citation fields and nested tables at ordinary cell block boundaries. Nested
tables may also be wrapped in ordinary `div` elements. Empty cells and an
entirely empty table retain their structure.
Header-cell text starts bold and retains explicit inline emphasis changes.

Citations follow the note's source order: rows from first to last, cells within
each row, and then the blocks inside each cell, descending into a nested table
at its position in that cell. Refresh and bibliography
commands include that sequence. Lists in separate cells retain independent
counters and starting numbers. The tables, cell content, native fields and
supported formatting remain part of DOCX saving and reopening.

Place the caret in ordinary main-flow text, or select consecutive ordinary
main-flow paragraphs within one body section or authored footnote/endnote.
A result containing a table cannot be inserted
into an existing table cell. Surrounding prose stays in paragraphs outside the
new table. A leading table in an authored note leaves the automatic note marker
and separator before the table; citations inside it retain that note's
ownership. When imported content ends in a table, the insertion caret returns
to a main-flow paragraph immediately after it. The Notes pane edits the
surrounding prose; it preserves table cells without exposing them as ordinary
Notes text.

Tables share the complete note's 8 MiB payload, 10,000-paragraph,
10,000-link and image budgets. Parsing a cell does not restart those limits.
The additional table bounds are:

| Limit | Supported range |
| --- | --- |
| Tables in one note | Up to 64 across all nesting levels |
| Table nesting depth | Up to eight levels, counting the outermost table |
| Rows per table | Up to 256 |
| Logical columns per table | Up to 32, equal across all rows |
| Horizontal span per cell | An integer from 1 to 32 |
| Vertical span per cell | An integer from 1 to 256, within its actual row group |
| Native cells across the complete note | Up to 4,096, including generated continuation cells |
| Native paragraphs across the complete note | Up to 10,000, including continuation cells and trailing cell paragraphs |
| Supplied column width | An integer from 1 to 4,000 CSS pixels; 0 means unspecified |
| Total native table width | At most 4,000 points |

When present, a cell's `data-colwidth` vector must contain exactly one entry
per logical column covered by its span. Each entry is an integer: 0 leaves
that column unspecified, and 1–4,000 supplies its width in CSS pixels.
Explicit widths for the same logical column must agree across rows, including
rows with different merge patterns. Widths use the same conversion as pictures:
96 CSS pixels become 72 points. After reconciling all rows, a column with no
explicit width uses a 120-point default. Each cell's native width is the sum of
the grid widths it covers. Each nested table reconciles its own widths without
changing the containing table's grid. The existing table layout fits an
oversized grid to the available display width. Layout uses each table's uniform
cell margin, including zero; newly authored native tables default to 4 pt.
Nested tables keep their own margins. Text wrapping, row height, pagination,
picture fitting and ruler insets use that geometry. If the final scaled cell
width leaves no positive space between its margins, layout refuses it rather
than silently reducing the margins. Cell backgrounds accept
three- or six-digit hexadecimal colors, integer RGB colors, or transparent.

The supported HTML structure is `table`, optional `tbody`, `tr`, `td` and
`th`. A cell ending in a nested table receives a native trailing paragraph
before citation/list indexes are finalized; saving and reopening retains that
same paragraph order. Tables inside list items, inline paragraphs or links,
unequal logical row widths,
spans crossing row-group boundaries, separate header/footer row groups,
captions, custom table classes and other
table/row/cell styling are refused. A malformed table, unsupported image, or
missing/repeated/unconverted citation placeholder refuses the entire staged
result. The existing cancellation, stale-selection, composition and single-step
undo guarantees apply to the table and its surrounding content together.

Merged-cell shading and borders continue on each page occupied by the cell.
Clicks and navigation resolve to its originating paragraph; row handles retain
physical row geometry. The layout currently assigns the originating cell's
content height to its first row. Compact distribution of that height across
several rows, as in Word, remains a separate fidelity item.

The [nested-table work record](validation/zotero-nested-tables-20261121/README.md)
identifies the current implementation and its qualification scope.
The [vertical-table validation record](validation/zotero-vertical-tables-20261120/README.md)
retains that increment's source-specific evidence.
The [horizontal-merge and Refresh record](validation/zotero-merged-cells-20261120/README.md)
retains the preceding increment's evidence. The [earlier table record](validation/zotero-research-tables-20261120/README.md)
retains its original evidence.
Local model and controller checks are separate from opening and refreshing the
result in an installed Word or LibreOffice application.

### Embedded pictures in notes and annotations

Add Note and Add Annotation accept **static PNG pictures** and **upright,
three-component RGB/YCbCr JPEG pictures** embedded by Zotero as base64 data.
Image/ink annotations normally use PNG. The original accepted image bytes are
embedded in the DOCX, with Zotero's supplied dimensions, alternative description,
title and ordinary image hyperlink. Pictures occupy one native inline position,
so adjacent citation placeholders retain their positions and reading order.
A note containing only a picture is supported too. Picture-only list items and
continuation paragraphs retain their list position and ordinary image links
through saving and reopening.

Zotero's positive, finite HTML width/height values use CSS pixels: 96 pixels
become 72 points. Fractional values produced by the note editor's resize and
aspect-ratio calculations retain their precision. When one dimension is missing,
Quds derives it from the intrinsic aspect ratio; when both are missing, it uses the intrinsic pixel dimensions.
Both displayed dimensions must lie between 1 and 4000 points, matching the
native image writer's supported extent. Resize an image in Zotero when its
displayed dimensions fall outside that range.

The note payload remains limited to 8 MiB. It can contain up to 32 images and
4 MiB of decoded image-file bytes in total. Each raster is limited to 8192
pixels on either edge and 16,777,216 pixels; the complete note is limited to
33,554,432 pixels. PNG scanline expansion is limited to 32 MiB per image and
the aggregate decoded raster-data budget is 64 MiB. These are data-size limits;
decoder intermediate allocations can consume more memory. Compressed PNG metadata
has a separate 1 MiB budget across the note. Encoded sizes, checksums, dimensions,
pixel streams and expansion budgets are checked before applying the document
transaction.

Animated PNG, GIF, SVG and other formats, external image URLs or files,
unresolved attachment keys, custom image CSS/classes, and images inside a
citation placeholder are refused. JPEG images requiring EXIF rotation or
flipping, and grayscale or CMYK JPEGs, are also refused because the current PDF
path does not reproduce those variants consistently; export an upright PNG or
RGB JPEG from the source instead. A malformed or unsupported image refuses the
whole insertion, including its text, citations and staged preferences.
Cancellation and stale-document guards retain the same atomic behavior.

Saving and reopening preserves the native pictures alongside their active
citations. Refreshing the citations leaves the image payloads and dimensions
intact. Undo removes the inserted content and restores the previous caret;
redo restores the pictures, citations and resulting caret together.

### Go to a citation or bibliography

In **Zotero → Document**, open a field's **Reference actions** menu and choose
**Go to reference**. The workspace closes and selects the complete citation or
bibliography in the document body, a body table cell, or an exposed Notes
paragraph. Navigation brings the Notes pane into view when needed, scrolls to
the note and restores its text selection. It does not edit document content or
add an undo step.

Navigation also works in read-only selecting mode, including for locked fields.
Viewing mode still permits reference inspection and export. Missing, stale,
nested, malformed or opaque field handles and unsupported stories cannot be
navigated through this action; the control is disabled when the available
structure cannot be selected. Selecting a complete multi-paragraph bibliography
allows the workspace to reopen on that bibliography.

### Cite while writing a footnote or endnote

Click in the **Notes** pane and place the caret where the citation belongs.
Use **Add/Edit citation** or its shortcut to insert directly into that existing
note. To edit an existing citation, place the caret inside it or select text
wholly inside the citation. Paragraph breaks and the hidden space following an
automatic note marker are mapped to the correct note positions. Opening the
toolbar or citation workspace retains the note selection; returning to the
document canvas returns commands to the body.

Native insertion preserves the existing note, its body reference, explanatory
text, and character formatting. Multiple citations can share the note, and
Zotero receives their reading order and the owning note's physical note index.
No nested note is created. Inline-style citations can also be placed inside an
authored note; requesting the opposite note kind is refused. A bibliography
still needs a body insertion point. The Notes text pane exposes its main-flow
paragraphs, not note table cells or text frames; an embedding host can supply
an anchored note table paragraph directly to the native engine.

Offline **Insert basic citation** and imported CSL sources use the same note
caret. Native and offline changes are undoable, with the note selection restored
on undo and the resulting insertion caret restored on redo. Ordinary note-text
undo keeps citation commands attached to the visible note editor. Finish an
active input-method composition before starting a citation operation. Cancelling
Zotero, changing the target, or deleting/replacing the note discards stale staged
results instead of applying them at another location.

| Control | Result |
| --- | --- |
| **Citation in Zotero…** | Opens Zotero's native picker at the document caret; edit locators, prefixes, suffixes and citation items there |
| **Document style…** | Opens Zotero's native document preferences, including the installed CSL style, language and note placement offered by that style |
| **Refresh all with Zotero** | Lets Zotero process the document's complete supported citation sequence and bibliography together |
| **Bibliography in Zotero…** | Adds or edits a bibliography through the same document processor |
| **Add note from Zotero…** | Inserts a supported research note with active citation fields at the body/Notes caret, or replaces ordinary text across consecutive paragraphs in one body section or authored note |
| **Add annotation from Zotero…** | Opens Zotero 9+'s annotation picker and inserts selected text, image/ink annotations and comments with active citations |
| **Prepare document for transfer…** | Uses Zotero's native transfer command to replace active fields with a temporary transferable representation |
| **Import transferred references…** | Appears for a pending transfer; asks Zotero to rebuild and format its active citations and bibliography |
| Existing citation menu → **Edit in Zotero…** | Opens that citation in Zotero's native picker |
| Library selection → **Insert with Zotero…** | Seeds the native picker with selected linked catalog sources, then applies Zotero's result |

The style and language chosen in **Document style…** belong to the document.
The Document tab shows the saved style ID, language and inline/footnote/endnote
placement. **Insert with Zotero…** is the primary catalog action in a native
desktop host. If no document style has been selected, it opens Zotero's style
chooser first and then carries the selected sources into the citation picker.
Both stages stay detached from the document and become one undo step. Cancelling
either stage, losing the connection or changing the insertion point keeps the
document and source selection. You can also choose **Document style…** first,
or use **Citation in Zotero…** without selecting catalog sources.
If Zotero changes note placement while opening a seeded citation, the staged
result is discarded and the workspace asks you to select the style first.
The **Preview / export style ID** and locale fields belong to the older
individual-preview/export workflow; changing them does not switch the
document's native CSL style. Zotero document preferences are saved as native
`ZOTERO_PREF_*` custom properties and restored when the DOCX is reopened.

### Move an active document between word processors

Use **Prepare document for transfer…** with desktop Zotero connected. Zotero
confirms the operation and supplies the instructions placed at the beginning
of the document. Quds replaces supported active citations and bibliography
fields with temporary links containing their complete metadata, and appends
the document preferences. This is the official
[Zotero transfer workflow](https://www.zotero.org/support/kb/moving_documents_between_word_processors).
The transfer copy intentionally shows raw field data until the destination
word processor imports it.

Save a copy as **DOCX for Word** or **ODT for LibreOffice**, open it in the
destination, and use that application's **Zotero Refresh** command. Keep the
original document until the destination has restored and checked the active
references. Do not edit the transfer marker, metadata links or final preferences
paragraph. Merely saving ordinary active fields as another file format does
not perform this workflow.

To bring a prepared transfer into Quds, open its **DOCX** copy and choose
**Import transferred references…** or the existing **Refresh citations** command.
The leading transfer marker takes precedence over stored DOCX preferences.
Quds reconstructs fields in a detached document, then lets Zotero format every
imported field and the bibliography before applying the result. The entire
operation is one undo step. Cancelling, incomplete native formatting, changed
document state or damaged transfer data leaves the original document intact.
Other native citation-editing controls remain unavailable while import is
pending.

Supported carriers include citations in ordinary body paragraphs, table cells
and uniquely anchored authored footnotes/endnotes; complete native bibliography
ranges; surrounding rich text and inline images; XML/JSON preferences and unknown
metadata members. Formatted fragments of a link and touching citation links are
reassembled without splitting JSON titles or locators. The modern and legacy
markers and the verified Google Docs transfer-link variants are recognized.
Mixed active fields and transfer links, protected or ambiguous ownership, lost
links, duplicate preferences and oversized payloads are refused explicitly.
Temporary hyperlink appearance is removed when rebuilding native fields.

This transfer increment qualifies incoming DOCX carriers and ODT carrier export.
The separate [native ODT import](#open-a-native-libreoffice-odt) now converts
canonical `ReferenceMark`/TextSection documents within its bounded rich-content
envelope. It is a distinct file-opening path and saves active fields as DOCX. The
[transfer qualification record](validation/zotero-transfer-20261121/README.md)
distinguishes local callback/model/editor checks, actual LibreOffice file
conversion, and the remaining installed Zotero/Word/LibreOffice plugin tests.
Those scopes must not be treated as complete application parity.

The nested-table qualification used LibreOfficeDev 26.8.0.0.alpha0
(`2c87e51e`). A direct Quds ODT carrier converted to DOCX preserved three
nested tables, four active citations, merged cells, an image and list labels
`4., 5.` through import and three further Quds saves. The separate
DOCX → ODT → DOCX route changed those list labels to `4., 1.`; a flat-list
control reproduced the same change. This is a recorded limit of that converter
route and version, not an accepted numbering result. The
[nested-table work record](validation/zotero-nested-tables-20261121/README.md)
retains both outcomes and the exact synthetic fixtures. Use the direct ODT
carrier when reproducing the passing route; installed-plugin and release-version
acceptance still need their own checks.

### Combine directly adjacent citations during Refresh

**Refresh citations** and **Refresh all with Zotero** let Zotero combine citation
fields whose native packets directly touch within the same paragraph and the
same document story or authored note. Zotero decides the combined item order,
duplicate handling and CSL formatting. The resulting citation remains active
through DOCX saving and reopening.

Whitespace, zero-width text characters, bookmarks, comments, content controls,
ordinary Word fields and bibliographies prevent a merge. Citations in separate
paragraphs, table cells or notes remain separate. Staged insertion, deletion,
unlinking or note conversion cannot create a merge across the intervening
content. Visual proximity or equal visible-text offsets alone are insufficient.

The HTTP client advertises the boolean `supportsCitationMerging` capability.
Each enumerated field's `adjacent` flag describes whether **that field touches
the next enumerated field**. Quds rechecks the physical citation packets before
applying Zotero's result. A completed refresh, including any merges and
bibliography changes, is one undo/redo step. Cancellation or a stale result
leaves the detached changes unapplied. See the
[merge validation record](validation/zotero-merged-cells-20261120/README.md) for
the qualified local source and remaining installed-application acceptance.

### German “Ebd.”, numbering and disambiguation

Select a German locale and a CSL style that uses *ibid.* for repeated citations.
**Refresh all with Zotero** passes every supported citation in reading order,
including citations in anchored footnotes and endnotes. Zotero decides when a
short form is appropriate and which locator/punctuation to use; the editor
does not replace repeated author names with a fixed string.

The pinned real-processor fixture for
`chicago-notes-bibliography-subsequent-ibid` with `de-DE` produces `Ebd.` for an
immediately repeated source and locator, and `Ebd., 34.` after changing the
locator to page 34. Other styles may use another form or avoid *ibid.* entirely.
The same processor fixtures exercise numeric citation renumbering and APA
year-letter disambiguation. See the [fixture provenance and reproducible
generator](../packages/quds_office_engine/test/fixtures/zotero/citing/README.md).

Inline citations and citations in footnotes/endnotes are supported. Switching
between them is supported when a source note contains only its citation and
optional whitespace/reference marker. A note containing explanatory text,
multiple citations or additional structural fields is kept intact and refuses
conversion; ordinary refresh can still update supported citations in such a
note. Ordinary non-citation notes count toward processor note positions.

Quds renders automatic note references and note bodies in document order, and
the Notes pane follows that order. Inserting an earlier note or converting a
citation updates the visible numbering while preserving native note IDs and
links. Common decimal, letter and Roman formats, starting numbers and section
restarts are supported; custom marks remain authored text. Page-based restarts
and unsupported native number formats retain their settings and are identified
by source ID in the Notes pane. Check those formats in the target word processor.

### Small capitals

CSL small capitals are retained in citations and bibliographies, including
mixed runs and explicit returns to normal text. The accepted `small-caps` and
`normal` values follow the [CSL formatting
specification](https://docs.citationstyles.org/en/stable/specification.html#formatting).
DOCX stores native `w:smallCaps` properties and keeps the authored letters.
Refresh, editing around a protected citation, save/reopen and undo/redo retain
the formatting.

The preview, editor and PDF use a consistent synthetic display: lowercase
letters become capital outlines at **0.8 times the run size**, while existing
capitals, numbers and uncased text retain their size. This fallback does not
select a font's designed small-capital glyphs. Widths are calculated from the
displayed glyphs before wrapping. Original grapheme boundaries and UTF-16
positions remain intact, including expanded forms such as `ß` → `SS`; PDF
export stores the authored text in `/ActualText` for extraction.

Display conversion supplements Dart's simple casing with the unconditional
uppercase expansions in [Unicode 17.0.0 SpecialCasing.txt](https://www.unicode.org/Public/17.0.0/ucd/SpecialCasing.txt).
It uses default Unicode casing without Turkish/Azeri/Lithuanian locale
tailoring. A grapheme, such as a letter with combining accents, that crosses
separate run-format records keeps its original display. Unsupported variants
such as `all-small-caps` and `petite-caps` still require an explicit review
before simplification.

### Native bibliography paragraphs and layout

Use **Bibliography in Zotero…** to add or edit the document bibliography, then
**Refresh all with Zotero** after citation changes. **Document style…** selects
the CSL style that controls both citations and this bibliography.

The native result is one linked field spanning its entry paragraphs. Structural
blocks in Zotero's formatted output become real Word paragraphs; an explicit
`<br>` remains a soft break inside its entry. Zotero's native bibliography
layout supplies the body/first-line or hanging indent, line spacing, spacing
after each entry and tab stops. Those paragraph properties survive DOCX
save/reopen, later refreshes that omit the layout callback, changes in the
number of entries, and undo/redo. A style-only change can reset old indent,
spacing and tabs without replacing the citation text.

Native replacement requires a complete, contiguous bibliography range in one
block container. Every paragraph and inline must belong to the bibliography;
surrounding prose, interleaved blocks, a range crossing cells or sections,
outside bookmarks, comments, note references, hyperlinks, embedded visuals,
content-control wrappers and locked/nested/opaque fields prevent that range
replacement. It does not enable multi-paragraph citation replacement. Citation
insertion inside any bibliography entry is refused. An inline bibliography
mixed with ordinary text may use the existing protected plain-text path only
after a review explains the lost formatting; paragraph layout is not applied
to the surrounding text.

Bibliographies created by older versions may contain several entries flattened
into one paragraph. Choose **Refresh all with Zotero** or **Bibliography in
Zotero…** to obtain new native entry boundaries. A layout-only callback, or an
unchanged plain-text reply, cannot distinguish entry boundaries from internal
soft breaks. The application leaves that legacy layout unapplied, reports the
limitation and requests the layout again on a later native operation.

The separate **Document → Zotero bibliography** API preview workflow retains
its single-paragraph review contract, described below. Use the native controls
above for document-wide bibliography paragraph layout.

### Apply, cancel and undo

Zotero commands work on a detached transaction. No document changes are applied
until Zotero completes successfully and the original document, revision, story,
caret and selection are still current. The entire operation is one undo step,
including note conversion, bibliography updates and document preferences.
Undo restores the original selection as well as the document content.
Zotero also sends a completion command after reporting internal errors. The
driver recognizes its error-alert forms, acknowledges the dialog, drains the
transaction and discards every staged change in that case.

Bold, italic, underline, strike-through, superscript, subscript and small
capitals are retained
inside citations, including mixed styling such as italic book titles beside
ordinary author text. The complete citation remains a protected field when
typing, deleting, copying, pasting or splitting paragraphs. Native refresh,
safe note conversion, DOCX save/reopen and undo/redo preserve these styles.
Unsupported character variants and layout outside the native bibliography
contract require a review before simplification. Cancelling that review leaves
the document alone.
An untouched catalog seed is discarded if the native picker is cancelled.

Only one desktop citing transaction runs at a time. While Zotero is waiting in
its own picker, finish or cancel that dialog. **Cancel operation** requests
cancellation; it cannot safely abandon an unanswered desktop command and start
another transaction immediately. Requests are never automatically retried.
An ambiguous connection loss reports that Zotero may need restarting before
trying again. The desktop window can wait up to ten minutes for a native
dialog; ordinary catalog requests retain their shorter timeout.

Native processing refuses a protected document, active Track changes,
unresolved revisions, locked/nested/malformed Zotero fields, cross-paragraph
citations or incomplete bibliography ranges, and citations in unsupported
stories such as headers, footers, comments and
text boxes. Resolve those conditions first. This avoids processing an
incomplete citation sequence. The session is bounded to 10,000 fields, 100,000
body paragraphs, 20,000 commands and 8 MiB command payloads.

The 16 November feature checkpoint passed local protocol, engine, controller,
dialog, Studio transport and typography/PDF qualification. Running Zotero 10.0.8
also verified saved-search execution and query scoping, plus four native refresh transactions
across German Chicago and a synthetic small-capital/double-line style, including
DOCX reopen. The [feature overview](validation/zotero-fidelity-20261116/README.md)
links the exact source receipts, native protocol traces and before/after files.
Those native traces qualify their recorded historical source. The later
[Notes workflow qualification](validation/zotero-note-workflow-20261118/README.md)
covers local model, controller, widget and controlled-transport behavior; it
does not add live desktop or Word/LibreOffice reopening acceptance.
The earlier native picker/style-selection acceptance remains separately
recorded with its original source identity. Full compiled application builds and opening
the exported file in Microsoft Word or LibreOffice remain separate acceptance
steps. See [current validation](zotero-validation.md).

## Using the editor

Open a Word document and choose **Insert → Zotero** (the **References** ribbon
group in Quds Studio and CrispCloud). The workspace has three tabs:

- **Library:** choose an online library or, in a native desktop host, Zotero
  desktop on this computer. Online connections use a dedicated API key or a
  public user/group library ID; desktop connections need no API key. Browse personal/group libraries, collections,
  desktop saved searches, and paged search results. Select up to 20 sources for a citation, then review
  its text and per-source locator, label, prefix, suffix and author options.
- **Document:** search and reuse already cited references; inspect existing
  Zotero citations and bibliographies; edit safe fields; generate or update a bibliography; refresh basic citations; copy the
  embedded CSL JSON; or explicitly convert a field to ordinary text. Each
  document operation is undoable and advances the editor's save revision.
- **Import CSL JSON:** paste a Zotero CSL JSON export for offline work. A single
  item, a CSL array, and Zotero's `{"items": [...]}` envelope are accepted.
  Import is bounded to 1 MB and 500 records. Linked Zotero URIs are retained;
  records without them remain offline embedded references. Search the loaded
  references by title, creators, year or DOI, then select sources across filters.

The selected references can also be copied as BibTeX, BibLaTeX, RIS, or CSL JSON
from the Library tab. Source exports are copied as reference data, not inserted
as document text. Library exports accept numeric user/group identities or unsynced local identities
from one matching connected library. Desktop exports need Zotero 10 or later
with database and library-version headers. Use **Document → Copy embedded CSL
JSON** for sources already in mixed-library or offline documents. Use
**Copy stored CSL JSON** in Import, or under **Library → Export selected**, to
copy the current selection without a connection, including with an older
desktop client. This copies stored metadata; it does not fetch updates.
Set the preview/export style ID and locale in Document (defaults: `apa` and `en-US`) before
requesting a bibliography or individual citation preview. In the citation
composer, expand a source's title to edit its locator and affixes.

### Inspect references and manage a selection

Choose the **Reference details** information button beside a catalog result to
inspect its full title, creators and roles, publication, date, publisher, DOI,
URL, Zotero identity, tags and abstract when available. The view uses metadata
already loaded for that result and makes no extra request. **Copy details**
copies a plain-text summary; the individual metadata fields are also selectable.
URLs remain text, and scientific comparisons such as `A < B` in abstracts are
preserved. Opening or copying details does not select the item or change the
document.

Choose a tag in the details view to add it to the current tag filters. This
returns to page one of the last submitted search in the current library,
collection or saved search, while retaining selected references and unfinished
text in both search inputs. Tags already applied are marked with a check.
Names that cannot be filtered exactly, including surrounding whitespace or
reserved search syntax, remain visible with an explanation in their tooltip.
The existing count and length limits apply; disabled tags make no request.
Manual and automatic Zotero tags are both available, with exact duplicates
shown once.

Use **Review selected** in **Library**, **Document** or **Import CSL JSON** to see all
selected sources, including references on another result page or hidden by a
filter. Move a source up or down to arrange the order passed to the citation
composer or Zotero's native picker, or remove one source without clearing the
others. A Zotero style may apply its own citation order. **Apply selection**
keeps the revised selection; **Cancel** or dismissing the dialog discards those
changes. Reordering and removal preserve each source's identity and embedded
metadata and do not add document history. Inserting a citation remains a
separate, undoable operation. The selection limit remains 20 sources.

The information button beside an imported result, or within **Review selected**,
opens **Stored reference details**. Inspect the complete title, creator roles,
publication and date, publisher, identifiers, source links and abstract supplied
with that reference. **Copy details** copies the same readable summary, and each
field can also be selected. This view works offline and in a read-only document.
It uses the stored metadata without fetching updates; imported records do not
need a connected Zotero library. Links remain selectable text.

Opening details within selection review keeps any staged reordering and removals.
Closing details returns to that review; **Apply selection** or **Cancel** still
decides whether to keep the staged selection. Duplicate imported IDs remain
separate references. Unknown CSL fields remain available through **Copy stored
CSL JSON**. If selecting another imported reference would exceed the 20-source
limit, the workspace explains the limit; use **Review selected** to remove a
source even when it is hidden by the current search.

### Read research notes and inspect attachments

In **Library**, open a source's **Reference details**, then choose **Notes and
attachments…**. This explicitly loads that source's direct child notes and
attachments in pages of 25. Opening ordinary reference details still uses the
already loaded metadata without making an extra request. **Previous page**,
**Next page** and **Reload** fetch only when chosen; returning from a child
keeps the current page. If Zotero reports a changed library version while
paging, reload from the first page to avoid mixing shifted results.

Open a note to read its plain-text preview, then choose **Copy note text**.
Paragraphs, line breaks, lists, table-cell separation, preformatted whitespace,
Unicode and scientific comparisons remain readable. Formatting and active
citation links are not copied. Images and other embedded content are omitted
and identified in the preview; their resources are never loaded. Unsupported
or malformed note markup shows a per-note explanation while other results
remain available. For insertion with live citation fields, use the native
**Add Zotero note** workflow described above.

Attachment details show the supplied title, filename, content type, storage
mode and URL, with **Copy details**. An attachment's embedded note can also be
read and copied. File contents remain in Zotero, URLs stay selectable text,
and linked-file paths are not exposed or used to invent a filename. This
workflow does not download or launch files or inspect attachment annotations.

Only records visible to the current connection are shown; online note access
depends on library visibility and API-key permissions. Desktop inspection
requires **Zotero 10 or later** and a parent reference loaded through the same
identified database connection. Older or headerless snapshots show a reconnect
explanation. Switching the desktop database, changing the connected library,
or closing the view prevents an old response from being presented as current.
Errors retain the previous page when appropriate and offer an explicit retry;
online backoff is respected without automatic requests.

Inspection and copying work in read-only documents. They preserve selected
references, unfinished search and tag input, the document content, and undo
history. Notes are bounded to 1 MiB of UTF-8 each; a child response is bounded
to 8 MiB, and overly complex markup is refused for that preview. No note or
attachment data is added to the document merely by browsing it.

### Cite a stored document reference again

Choose **Document → Cited references…** to search the sources already cited in
the document by title, creator, year or DOI. The list shows the number of
citation occurrences and offers **Stored reference details**. It uses embedded
metadata without connecting to a library or fetching updates, including in
read-only documents and while Track changes is enabled.

Select references across searches and choose **Use selected sources**. The
selection joins sources chosen in Library or Import and shares their 20-source
limit. **Cancel** discards the selection changes. Back in Document, use
**Review selected** to arrange or remove sources, **Copy stored CSL JSON** to
copy their stored metadata, or **Review and insert citation…** to create a new
citation at the original caret. Native desktop hosts also offer **Insert with
Zotero…** for selections with retained Zotero links. Insertion still requires
an editable document with Track changes off.

References appear in first-cited order. Repeated linked sources are grouped
only through their declared, validated Zotero URI aliases; equal IDs or item
keys in unrelated libraries remain separate. The first available stored
snapshot supplies the details and all declared aliases remain attached.
Offline records with the same ID and different stored metadata stay separate.
A source without a stored snapshot is identified explicitly; its retained
identity can still be inspected and selected.

Reusing a source starts a new citation occurrence: the earlier page number,
locator label, prefix, suffix and author-only/suppress-author options do not
carry over. Original citations remain unchanged. Selection, inspection and
copying add no document history; applying a citation is one undoable change.
If the document or caret changes while the review is open, the staged result
is rejected and the workspace explains how to reopen it.

#### Show where a source is cited

In **Document → Cited references…**, choose **Show citations** beside a source.
The list shows each citation's stored text and location, including the body
section and paragraph or the displayed footnote/endnote number. Choose
**Go to citation** to close the references workspace and select that citation
in the document or Notes pane. This works offline and in **Read and copy** mode;
it does not change the document, its saved state or its undo history.

Each distinct citation field appears once, including when the source occurs
more than once within the same citation. The list uses the same declared URI
aliases and embedded-source identities as Cited references, so equal item keys
in unrelated libraries are not combined. Headers, footers, comments and other
locations that the editor cannot reveal remain inspectable with navigation
unavailable. Note labels use the document's numbering settings; unsupported or
orphaned note numbering is identified by source ID.

**Back to cited references** retains the source picker's search and staged
selection. **Go to citation** leaves those draft selection changes unapplied.
If the document, caret or selected field changes while the list is open, the
old destination is refused; reopen Cited references to use the current document.

### Change the sources in a citation

Choose an existing field's **Reference actions → Edit citation**, or review a
new selection. Move sources up or down, remove them, inspect stored details,
or choose **Add stored sources**. The local chooser searches references already
cited in the document, references selected in Library, and loaded CSL imports.
With a connected library, **Search Zotero…** also searches Zotero directly
*while the citation editor stays open*. Enter a title, creator or year and
submit Search. Results are fetched in pages of 25; **Load more** keeps the
submitted query, and selections survive new searches and page changes. Open
stored details before adding a result. Typing alone makes no network request.
The search box receives keyboard focus when the chooser opens. **Review selected**
shows every staged search selection, including sources hidden on other pages or
by a later search. Reorder, inspect or remove these sources, then choose
**Apply selection**; **Cancel** leaves the staged selection unchanged. Removing
a hidden source frees capacity for another result. Use **Down** from the search
box to focus the first result, **Up/Down** to move between results, and **Enter**
or **Space** to toggle a source. **Up** from the first result returns to the
search box. Keyboard movement scrolls results into view, including long result
lists and enlarged text. This review changes only the chooser's selection;
adding the selected sources and the citation editor's final apply remain
separate steps.
Only citable results with CSL metadata can be selected; Zotero items that do
not supply CSL data are excluded. Unsynced desktop items without a durable
Zotero URI enter as standalone embedded references. Without a connection,
select Library sources or import CSL JSON to make other references available.

Source changes remain staged until **Update citation** or **Insert citation**.
Cancelling the composer discards them. Reordering preserves each occurrence's
locator, affixes and author options, even when two occurrences have the same
source ID. Newly added sources start with fresh citation options. At least one
source is required. Adding is limited to 20 sources; an imported citation that
already exceeds that count keeps all its sources available for editing,
reordering or removal.

Basic author–year text updates with the current source list and per-source
options. In custom-text mode, changing membership, order, locator, label,
prefix, suffix, or author-only/suppress-author options requires editing the
visible text or explicitly confirming that it matches the revision. These
changes discard the previous processor-specific formatted cache; restoring
the original options without other changes preserves it. For full
CSL numbering, disambiguation and bibliography updates, use **Edit in Zotero…**
and the native refresh tools. A connected single-source preview always uses
the current source after edits; preview errors keep the citation draft.

### Convert all citations to ordinary text

Choose **Document → Unlink all citations…** to convert the document's linked
citations and bibliography fields together. The confirmation shows the number
of each kind and explains that Zotero can no longer update the converted text.
Keep a linked copy if you will need later citation updates. **Cancel** keeps
the fields and does not add undo history.

The complete conversion is one undoable change. It retains the visible text,
character and paragraph formatting, notes, and reusable document style
preferences, including multi-paragraph bibliographies. It covers fields in
modeled document stories, rather than only the visible page. If a locked,
nested, malformed or unsupported Zotero field prevents a complete conversion,
the operation refuses before unlinking any fields. Protected content and
unresolved tracked changes are also checked. Zotero instructions retained in
unmodeled native content prevent a partial conversion.

Read-only documents and active Track changes disable this action. Changing the
document or insertion point while the confirmation is open invalidates the
confirmation. Undo restores all field links together; after closing and
reopening the unlinked file, it contains ordinary text. The existing per-field
**Convert to text (undoable)** action remains available for a single reference.

### Search imported references and copy stored data

After **Load references**, use **Search imported references** to filter the
loaded CSL records immediately. Each whitespace-separated search term must
appear in the title, a creator name, publication year or DOI. Matching ignores
case and treats punctuation literally. All supplied author/editor names are
searchable, including names beyond the visible label. Creator and year labels
help distinguish records with the same title.

The result count shows how many loaded references match and how many selected
sources are outside those results. Filtering and clearing the search keep all
selections and their order, including sources selected in Library. **Review
selected** still lets you reorder or remove them. Duplicate CSL IDs or titles
retain their separate original import positions. Loading a new valid export
clears the search and replaces only imported selections; an invalid export
keeps the previous list, filter and selection intact.

Choose **Copy stored CSL JSON** to copy the entire current selection in its
reviewed order, including hidden sources and references from different
libraries. The copied array retains embedded metadata, unknown CSL fields and
Zotero URI aliases. It can be pasted back into **Import CSL JSON**. Repeated
records and IDs are retained; this action does not deduplicate them or refresh
their metadata. Citation-specific locators and affixes remain in the citation
and are not part of the reference export. The copied JSON must fit the existing
1 MB import limit; a missing or malformed snapshot stops the copy with an
explanation instead of silently leaving out a selected source.

Searching, reviewing and copying stored references work in a read-only document
and make no network requests or document-history changes. The connected
BibTeX/BibLaTeX/RIS/CSL JSON export choices continue to use the selected library.
The import view scrolls vertically in smaller windows. Status and error
messages have their own scroll area when space is limited, so their complete
text remains available with enlarged text.

### Find and sort references

Choose **Search options** (the sliders icon beside the search box) in the Library
tab to choose:

- **Search in:** the default title/creator/year search, or **Include full text**
  to include content indexed by Zotero. Results depend on that library's indexed
  content, and local and online quick searches can differ.
- **Reference type:** all types, books, book sections, journal articles,
  conference papers, theses, reports or web pages.
- **Sort by:** date modified, date added, title, creator, publication date or
  reference type, in ascending or descending order.

These controls apply to the whole library, selected collection, or desktop
saved-search result before Zotero divides it into pages. The default remains
most recently modified first. Changing an option submits the current search and
starts at its first page; selected sources stay selected. Choosing **All types**
removes the type filter.

Typing in the search box does not change the result set until you submit the
search or change an option or catalog scope. **Next page** and **Previous page**
continue using the last submitted search, so an unfinished edit cannot skip to
the middle of a different result set. Expanded options and chosen filters remain
available when reconnecting within the same references workspace.

#### Filter by tags

In **Search options**, enter an exact tag name in **Filter by tag**, then press
Enter or **+**. Add another tag to require **every added tag**. For example,
`reviewed` and `primary sources` show references that have both tags. Zotero
applies these filters across the complete library, collection or desktop saved
search before pagination; the editor does not filter just the current page.

Applied tags appear as removable chips. Use a chip's **Remove tag** button or
**Clear tags** to broaden the results. Adding, removing or clearing tags returns
to the first page of the last submitted search and retains selected sources.
Draft text in either input does not change paging or tag-removal requests.
Submit the main search separately to use a new query. The count on the sliders
icon shows that tag filters remain active when options are collapsed. Filters
also remain available when changing catalog scope or reconnecting in this
workspace; they are not written into the document or persisted across dialogs.

Surrounding whitespace is trimmed and identical tags are added only once;
capitalization and spaces within a name are retained. An initial hyphen is
treated as part of a tag name. Literal names containing `||` or beginning with
`\-` cannot be represented consistently by Zotero's online and desktop search
syntax and show an inline error. No search request is made for invalid input.

The filter accepts at most 20 tags, 256 UTF-16 code units per name and 2,048
in total. Empty names, control characters and malformed Unicode are rejected.
Long labels are shortened visually, with the full tag available in their
tooltip, and the chip list scrolls within narrow windows. Filtering is read-only
and does not add, remove or rename tags in Zotero.

#### Browse available tags

Choose **Search options → Browse tags…** to find actual tag names in the
connected library or selected collection. In a desktop saved search, the picker
explicitly browses **Library tags**; it does not claim to list tags or counts
limited to that saved search. This is separate from the reference search:
**Search tag names** supports containing or starting with a phrase, and the
arrow buttons move through pages of 50 API records. Typing does not submit a
search; paging and changing the match mode keep the last submitted phrase.

Choose tags across pages and searches. Selected tags remain visible as chips,
including tags outside the current results, and can be removed individually or
cleared. **Apply tags** updates the complete filter selection and returns the
reference results to the first page of the last submitted reference search.
Selected references and unfinished search/tag text remain intact. **Cancel**
discards all draft filter changes; applying an unchanged selection makes no
new reference request.

Zotero can report manual and automatic records for the same tag. The picker
shows one choice for each exact name on a page and never adds their counts
together. Usage counts are displayed only when supplied and unambiguous on that
page. They may cover the whole library, including notes and attachments, even
while browsing a collection; they are not counts of the current reference
search. API pagination still advances by records, so the same name can occur on
another page without being selected twice.

Names that cannot be represented by the existing literal-tag filter remain
visible with an explanation and cannot be selected. The same 20-tag and text
limits apply. The picker preserves exact capitalization and Unicode; it never
silently trims a returned name. Requests use the existing online credentials
or isolated local desktop connection. Errors are displayed without an automatic
retry; closing during a request ignores its later result. A changed catalog
connection or library prevents an old picker result from being applied.

### Connection and credentials

Create a dedicated key at <https://www.zotero.org/settings/keys/new> with library
read access and group read access when needed. No write access is needed. The
Web API operates on the synced online library; the local Zotero application is
not required. Public libraries can be read without a key.

Keys live in host session state. Quds Studio does not persist them. CrispCloud
can remember a key only when its selected credential store supports persistence
and the user checks **Remember key when connecting**. Unchecking it removes the
stored key immediately; **Disconnect & forget** also clears the session. Keys
are never added to DOCX, CSL snapshots, reference exports, or request URLs.

Hosts supply the network transport. For online access, CrispCloud uses its
existing selected proxy and TLS policy, refuses redirects, limits each response to 8 MB, bounds the
request to 20 seconds, closes pending requests when the editor closes, and
displays fixed diagnostics without network response bodies or credentials.
The online client fixes its HTTPS origin to `api.zotero.org`, requests API v3,
and sends authentication in the `Zotero-API-Key` header.

### Zotero desktop on this computer

Native Quds Studio and CrispCloud on Linux, Windows and macOS offer
**Reference library source → Zotero desktop (this computer)**. Open Zotero,
then enable **Settings → Advanced → Allow other applications on this computer
to communicate with Zotero**. Choose **Connect desktop** in the reference
workspace. Browsing, collection navigation, saved searches, pagination, search and selection use
the locally available personal and group libraries, including unsynced items.
The source selector and connection do not change the document.

#### Browse a saved search

After connecting the desktop catalog, choose the personal or group library,
then **Saved searches** beside **Collections**. Choose an existing search in the
**Saved search** menu. **More searches** pages through longer search lists;
**Refresh saved searches** reloads that list after you edit it in Zotero and
asks you to choose again. Use **Search within saved search** to add a
title/creator/year filter and the normal result pagination to browse matches.
Selected sources remain selected when switching views, so they can feed
**Insert with Zotero…** or the basic citation action.

Zotero evaluates its saved conditions locally, including conditions beyond the
editor's quick-search filter. The workspace does not create or edit saved
searches. Notes and attachments returned by a search are not offered as citation
sources. A removed search clears its old result list and asks you to refresh;
switching libraries or reconnecting cannot reuse a stale result. Saved-search
execution is desktop-only because the [official local API](https://www.zotero.org/support/dev/web_api/v3/local_api)
provides `/searches/<searchKey>/items`, while the online API exposes search
metadata without evaluating it. This feature requires a desktop version that
implements that endpoint; no older-version compatibility is assumed.

#### Desktop transport and source identities

Desktop reads go directly to the fixed `http://localhost:23119/api/` endpoint,
with API version 3 and Zotero's allowed-request header. They bypass CrispCloud's
remote proxy and never carry an online API key, cookie or authorization header.
They retain the same timeout, response-size, redirect and disposal limits.
Switching sources makes no request; connecting is explicit. The saved online
key and Remember preference stay available when switching back. **Disconnect
desktop** closes the workspace's local connection without forgetting that key.

The client probes the plain-text API root and validates its version. When
Zotero supplies a `Zotero-Server-ID`, later requests pin that database identity;
a changed database requires reconnecting. Older desktop versions may omit the
header. Local and online object-version numbers are not compared.

Connected document operations check the complete saved source URI, including
the local profile key, against the returned item. Matching an eight-character
item key alone is insufficient. Scheme/hostname aliases are normalized for
comparison, while original citation IDs, URIs, locators, affixes and unknown
JSON members are retained. Two different local profiles are separate source
libraries even though both are requested through `/users/0`.

Before a selected-source export or formatted bibliography, the client fetches
one bounded metadata response and verifies every requested key and identity.
Missing, duplicate, additional or mismatched records refuse the operation.
Desktop aggregate operations also require a pinned `Zotero-Server-ID` and a
`Last-Modified-Version` that stays unchanged between metadata verification and
formatted output. A reported database switch or library-version change refuses the
result. These checks detect changes between responses; they do not create a
server-side snapshot transaction. This requires Zotero 10+; older clients can still browse, cite, refresh
basic citations and provide individual previews when the same JSON response
proves the source identity. Basic refresh requests metadata only, so it does
not require a citation style or ask Zotero to generate formatted text. Use the
embedded CSL export or basic bibliography when a connected aggregate operation
cannot be verified.

**Refresh basic citations** fetches up to 1,000 distinct linked sources in
sequential batches of at most 50 per library. Repeated citations share the same
metadata request: 101 sources from one library require three requests, and
1,000 require twenty. Personal, group and unsynced local libraries retain
separate identities even when item keys match. Each response must contain every
requested source exactly once with usable CSL data. All batches stay staged
until the complete refresh succeeds, and applying it remains one undo step.
A changed document or insertion point, a failed batch, or a requested API pause
stops the operation without applying earlier results. Closing the dialog also
discards staged results and prevents subsequent batches. More than 1,000
distinct sources are rejected before any metadata request.

Connected basic refresh and the **Zotero bibliography** API workflow resolve
source aliases declared anywhere in the document before requesting metadata.
For example, an older citation may contain only an unsynced local URI, while a
later citation explicitly records that local URI and its synced user-library
URI. Online refresh can then use the declared synced identity for both citations.
Late and transitive alias declarations work, including declarations in custom or
native citations that have no embedded snapshot of their own.

Only basic citations are rewritten by basic refresh. Original citation and item
IDs, URI arrays, locators, labels, prefixes, suffixes and unknown metadata remain
intact; custom/native citation caches remain intact. Equal item keys in unrelated
libraries or local profiles do not establish an alias. Each alias group uses one
deterministic request identity: the first numeric identity online, or the first
declared identity on desktop. A failed request stops the operation without
trying other identities. The 1,000-source refresh and 50-source API bibliography
limits count resolved sources; resolving more than 10,000 distinct validated
URI aliases across the document is refused before metadata requests.

Collection pages merge by collection key. If a collection moves between pages
or is renamed, its latest metadata replaces the earlier entry while its order,
selection and selected references remain intact. Responses from a closed dialog
or an obsolete library request are discarded. See the
[large-library validation](validation/zotero-large-library-20261116/README.md)
for the local regression coverage.

Native document refresh also avoids repeatedly scanning all field IDs and
rebuilding note positions for every citation. Each field-list response computes
the current reading order once; later commands recalculate it after insertions,
deletions or note conversion. The [optimization evidence](validation/zotero-optimization-20261116/README.md)
contains the measured engine scope, correctness checks and remaining limits.

Persistent item identities are separate from request addresses. `/users/0`
selects the local user but is never written as a citation URI. Signed-in items
use the actual numeric account URI. Unsynced items retain a validated
`users/local/<localUserKey>/items/<itemKey>` URI. If Zotero supplies only a
citation key and no durable URI, the editor clearly embeds an offline source
with a generated ID instead. Local CSL export arrays and one-item envelopes
are accepted, while ambiguous multi-item responses are refused.

| Desktop source | Available workflow |
| --- | --- |
| Numeric user/group identity | Browse, cite, refresh basic citations, selected-reference export, individual style preview and one-library bibliography |
| Unsynced `users/local/…` identity | Browse, cite, preserve DOCX/CSL links, refresh basic citations and preview a single source through the matching desktop library; selected-reference export and Zotero bibliography with Zotero 10+ identity/version checks |
| Citation key without a persistent URI | Browse and cite as an explicitly offline embedded source; basic formatting and embedded CSL export |

Sources without a persistent identity remain offline and cannot use connected
refresh, previews or formatted exports. Unsynced local identities require the
matching desktop database; the online API cannot resolve them. No request is
redirected to another library to approximate these operations.
Browsing the desktop database works offline; a missing citation style can
still cause Zotero itself to download that style. Desktop access is not offered
in browser/mobile hosts. Catalog browsing uses the local API; the native
document tools above use the separate HTTP Citing Protocol.

## Formatting and interoperability

| Operation | Supported behavior | Boundary |
| --- | --- | --- |
| Native document processing | Zotero picker, document style/locale, complete citation refresh, numeric ordering, disambiguation and style-dependent ibid | Running desktop Zotero required; supported stories and safe note conversions only; full app/Word interoperability remains a separate acceptance step |
| Native bibliography layout | One linked field across entry paragraphs, supported indents, line/entry spacing and tab stops | Complete contiguous paragraph ownership; legacy flattened entries need native content refresh; arbitrary CSS and multi-column layouts are still reviewed |
| Small capitals | Native DOCX flag; consistent synthetic preview/editor/PDF display; authored text and logical positions preserved | Scale 0.8, default Unicode casing without locale tailoring or font-designed small-capital features; unsupported capital variants remain reviewed |
| Basic citations | Author–year fallback, multiple sources, locators and affixes | Not a named CSL style |
| Single-source style preview | Zotero's individual citation text for a style ID and locale | Review locators and document numbering; this is not a document-wide CSL run |
| Zotero bibliography API preview | One complete API rendering of up to 50 distinct sources in one library, with supported rich character formatting including small capitals | Single-paragraph review; paragraph CSS layout is simplified; no separately formatted batches are concatenated |
| Basic bibliography | Sorted, deduplicated entries from embedded source snapshots | Useful offline, without complete CSL formatting |
| Refresh | Fetch metadata for at most 1,000 distinct linked sources in verified batches of at most 50 per library, and atomically refresh Quds basic author–year citations | Local identities require the matching desktop connection; imported/custom style caches are not automatically replaced |
| Existing DOCX fields | Preserve Zotero codes, unknown JSON members, source data and rich cached text, including multi-run simple fields | Nested, locked and opaque replacement is refused; multi-paragraph replacement is limited to complete native bibliography ranges |
| Native Zotero document preferences | Read and write Zotero's XML/JSON preferences in chunked `ZOTERO_PREF_*` custom properties; translate native `Field` and wire `Http` types | Unknown preferences and unrelated properties are retained; malformed, duplicate, incomplete or ambiguously owned data is refused |
| Document transfer | Native export/import callbacks, temporary metadata hyperlinks, DOCX save/reopen and ODT carrier export; native reformatting before applying an import | The qualified incoming carrier route uses DOCX; direct native ODT conversion has the separate envelope below; installed-plugin acceptance remains open |
| Native ODT import | Supported paragraphs/styles, external links, authored notes, simple lists and supported merged/nested tables become an editable Word document; independent script formatting in retained LibreOffice prose; canonical Zotero citations/bibliographies and preferences remain active through DOCX saves | All-or-nothing bounded conversion; unsupported used structure/formatting and active content-sensitive defaults refuse |
| Editable Zotero ODT export | Explicit copy export writes citation ReferenceMarks, bibliography TextSections and ReferenceMark preferences with exact supported ownership; rich body/cell/decimal-note fields remain active | Ordinary ODT export still writes cached results; the explicit path refuses unsupported active fields, and installed-plugin acceptance remains separate |

New citations use complex Word fields with `ADDIN ZOTERO_ITEM CSL_CITATION`
codes, durable Zotero item URIs, and embedded CSL item snapshots. New linked
sources reject `/users/0`, zero-valued group IDs and malformed local identities;
imported opaque source metadata remains preserved without automatic repair. Bibliographies
use `ADDIN ZOTERO_BIBL … CSL_BIBLIOGRAPHY`. Legacy `ADDIN CSL_CITATION` fields
are recognized. Existing source JSON is retained, including members not modeled
by this editor. Library identity includes both user/group kind and numeric ID;
an item key alone is not a unique source identifier. Known URI scheme/hostname
aliases are deduplicated without rewriting imported metadata.

**Basic bibliography** and **Copy embedded CSL JSON** resolve all source aliases
declared by the document before choosing an embedded snapshot. If citations for
source A and source B appear before a later citation carrying both A and B as
URIs, they produce one exported source or bibliography entry. Longer alias
chains and alias declarations without their own CSL snapshot also work. The
first available embedded snapshot is retained in full; citation IDs, URI order,
locators, affixes and unknown metadata are left intact. Equal item keys or CSL
IDs in unrelated linked libraries or desktop profiles remain distinct.

The new desktop adapter delegates complete CSL processing to Zotero. Basic
formatting and individual previews remain available when the desktop is not
connected, and remain explicitly identified. A citation processed by native
Zotero is marked separately so **Refresh basic citations** cannot overwrite
its CSL result. The transfer workflow above extends this with explicit temporary
carriers. Its qualification record identifies exactly which file-converter paths
were exercised and which installed-application paths remain unqualified.

### Rich bibliography review and imported citation preservation

**Document → Zotero bibliography** now opens a formatted review. **Keep Zotero
formatting** is selected initially. Bold, italic, underline, strike-through,
superscript, subscript and small capitals are inserted as native Word run properties and remain
available after saving, reopening, updating, undo and redo. Numeric bibliography
labels stay beside their entry text. Turn off **Keep Zotero formatting** to edit
and insert a plain-text version explicitly. Cancelling the review does not
change the document; a changed caret or document still refuses stale insertion.

This API review preserves small capitals with the display limits described
above. Hanging indents, spacing, multi-column margins and arbitrary paragraph
CSS are still simplified in this workflow, and the review reports known
unsupported formatting. Entries retain their order and text using line breaks
in one bibliography paragraph. Native **Bibliography in Zotero…** supports the
separate paragraph-layout workflow. Links remain inert text. A bounded XHTML parser accepts only supported
text styling, never loads images or external resources, ignores active content,
and rejects malformed markup instead of silently replacing an existing field.

Rich updates support a bibliography that occupies a complete paragraph,
including a safe field reopened from DOCX. A bibliography mixed with surrounding
text or outside structural markers refuses rich replacement; the plain-text
workflow remains available. Imported bibliography additions, omissions and
custom entries retain their existing protection.

Imported multi-run `w:fldSimple` Zotero fields retain their link and styles by
using Word complex-field boundaries internally and on export. Lock/dirty flags
and unknown container attributes are retained; unknown attributes make
replacement read-only. A numeric citation cache or the Zotero locator label
`page` is not mistaken for a native Word `PAGE` field. Unchanged citation edits
preserve the existing result runs and original `formattedCitation` value without
trying to interpret its processor-specific syntax. The composer starts from
the actual visible field cache even if imported `plainCitation` metadata is stale.

The native document workflow also generates protected mixed-format inline
citations and performs complete CSL processing through Zotero. **Insert basic
citation** remains an explicit author–year fallback in desktop hosts; hosts
without native transport retain **Insert citation** for the same basic workflow.

Ordinary save/reopen retains unsupported fields instead of replacing them with
plain text. Converting a field to text is an explicit, undoable user action.
Imported bibliographies with nonempty `uncited`, `omitted`, or `custom` settings
are preserved and refuse basic/API replacement, so these choices are not
discarded. Use Zotero's native bibliography controls to manage those choices.
Citation edits refuse when Track changes is active or an unresolved revision
affects the target paragraph. Insertion into a multi-paragraph Zotero field is
also refused. Async operations recheck the original document, content revision,
story, caret and selection before making a change; a failed request or stale
target leaves the document unchanged.

## Embedding in another host

```dart
final session = ZoteroSession(); // Retain for this editor session only.
await showWordZoteroDialog(
  context,
  controller: wordController,
  session: session,
  transport: yourZoteroTransport,
  // Native desktop only; fixed localhost, direct connection, no credentials.
  // localTransport: yourDirectDesktopZoteroTransport,
  // Optional: persistApiKey: yourExistingSecureStore,
);
```

The transport receives a `ZoteroHttpRequest` and returns a
`ZoteroHttpResponse`. Disable redirects, set request/response bounds, and close
owned clients on disposal. `localTransport` is an explicit host opt-in and is
never a fallback for online requests. Native hosts must bypass external proxies
and reject credentials before creating a local client. A citing-capable local
transport must additionally allow POST only to
`/connector/document/execCommand` and `/connector/document/respond`, with the
two allowed headers and the supplied bounded native-dialog timeout. It must
close active requests on disposal. The Studio transport is reusable for one
workspace invocation and disposed when that workspace closes. The pure Dart engine
never imports Flutter or
`dart:io`. Hosts without a transport can still offer offline import, field
management, and embedded-source export.

The engine exports `ZoteroClient`, `ZoteroLibrary`, `ZoteroItem`, `ZoteroItemChild`,
`ZoteroItemChildKind`, `ZoteroSavedSearch`,
`ZoteroCitation`, `ZoteroCitationItem`, and `WordZotero`. The editor adds
`WordEditorController.insertZoteroCitation`, `updateZoteroCitation`,
`refreshZoteroCitations`, `insertZoteroBibliography`,
`updateZoteroBibliography`, `unlinkZoteroField`, and `unlinkZoteroFields`.
The latter returns the converted field count and performs an atomic,
document-wide conversion. `zoteroFieldAtCaret` returns a fresh field handle
for the active body/Notes caret or a selection confined to one paragraph. Hosts can pass
`initialTab: WordZoteroTab.document` to `showWordZoteroDialog`, or an explicit
`initialCommand: ZoteroCitingCommand.addEditCitation` (and the other native
commands) to begin that command immediately with their local transport.
Live field handles must be
re-inspected after a mutation or history operation.

`ZoteroClient.itemChildren(library, parentKey)` returns a validated, paginated
read-only list of direct child notes and attachments, without CSL rendering or
file requests. In a desktop host, pass `expectedLocalServerId` from the
parent's `ZoteroItem.localServerId`; this provenance belongs to the exact
catalog response and must match the client's already pinned database. It is
never embedded in CSL or document metadata. The child model retains raw
`noteHtml` as untrusted data. The editor's note preview converts it to inert
text with explicit input, token, nesting and attribute bounds.

`WordNotesPane` publishes focus, selection and composing ranges through
`setNoteEditingTarget(note, selection, composing: range)`. Custom note editors
must do the same using offsets in `WordNotes.editableText(note)`, and call
`clearNoteEditingTarget()` when the user returns to the document canvas or the
note editor is removed. Keep the note target while focus moves to a toolbar or
modal. Merely changing raw body-caret coordinates is not a replacement for
this lifecycle contract. `noteEditingTarget` is an immutable record containing
the note identity, selection and composing range; the native and shared-dialog
stale-operation guards include it. New documents clear it. Active composition,
deleted notes and invalid selections cannot receive a native result.

For native transactions, use `ZoteroCitingClient`, `ZoteroCitingCancellation`,
`WordZoteroCitingSession` and `WordEditorController.beginZoteroTransaction`.
Run the transaction's current-target guard before every protocol command and
after host prompts. Review any reported simplifications, then apply the
completed transaction once. `WordZoteroDocumentData` handles native preference
ownership, translation and serialization. Raw session `apply` belongs inside
the controller's rollback boundary, not directly in a host widget.

### Direct commands, reference navigation, research notes and annotations

Pass `initialCommand` and `closeAfterCommand: true` to
`showWordZoteroDialog` for the compact command flow. The default remains the
persistent workspace for existing embedding hosts. After the dialog closes, the
shared helper requests the controller's current body or Notes editing focus;
it does not restore an obsolete selection captured before the command.

`WordEditorController.canRevealZoteroField` provides a cheap availability hint.
`revealZoteroField` reinspects a short-lived field handle before selecting its
complete supported range. Hosts may call `requestEditingFocus()` after their
own chrome closes. `noteFocusRequest` lets a custom Notes host observe requests
to reveal and focus the retained note target. These operations require selection
permission but not mutation permission.

`ZoteroCitingCommand.addNote` and `ZoteroCitingCommand.addAnnotation` use
`Document.insertText` and
`Document.convertPlaceholdersToFields`. The session advertises
`supportsTextInsertion` only at a supported insertion point. When constructing a
controller transaction directly, pass the actual `command` for the same early
eligibility checks used by the shared dialog. `command.insertsNoteText` identifies
both research-content commands. The native session also checks insertion and
conversion before staging and applying data. If either command completes with
`hasInsertedNoteText == false`, discard the transaction, including staged
preferences: this is the cancelled-picker path. Add Annotation requires Zotero
9 or later and uses the native `addAnnotation` command, without an automatic
fallback to a different picker.

For a session constructed without the editor controller, `insertionParagraph`
may be an anchored body or note paragraph. `insertionOffset` is the start of the
insertion or replacement. Optional `insertionEndParagraph` defaults to the start
paragraph; `insertionEndOffset` defaults to the start offset and is measured
within that end paragraph. Both offsets must be valid UTF-16 text boundaries.
Distinct endpoint paragraphs must be ordered, exclusively owned, consecutive
ordinary blocks in the same body-section, authored-note or table-cell block
list, subject to the limits above. The session pins the original owning
section/note, table/row/cell chain and actual block list. Shared paragraphs,
replaced owners, protected structural ancestors and continuation-cell targets
are refused before publication. Native engine sessions can address cells in
authored notes; the standard Notes pane continues to expose only main-flow
note text, so it does not provide this cell-editing surface.
An end offset of zero selects the preceding paragraph
break without selecting text from the last paragraph.

The range uses native paragraph offsets, including any hidden note-reference
separator. The controller maps the Notes pane's visible selection to those
offsets. A raw offset of zero at the start of an authored note also preserves
its existing automatic reference separator during multi-paragraph replacement.
A nonempty range applies only to research-content insertion; ordinary citation
commands keep their existing caret/field behavior. The surrounding rollback
boundary is still required.

`WordZoteroNoteText.blocks` retains table ownership. Its `paragraphs` view
contains those same paragraph objects in row-major order, and citation/list
indexes address that view. Hosts preserving a parsed fragment must clone its
blocks and flatten the cloned tree; cloning the paragraph view alone discards
the table containers. A table-containing payload is checked against the actual
destination container when staged and again before application. The final
caret remains in the main flow even when the payload ends in a table.

### Native bibliography layout contract

The adapter accepts Zotero's
[`Document.setBibliographyStyle`](https://www.zotero.org/support/dev/client_coding/http_integration_protocol#documentsetbibliographystyle)
callback and applies its validated values to every supported entry paragraph.
The callback's body and first-line indent are related: the first-line position
is their sum, as specified by Zotero's
[wire protocol](https://www.zotero.org/support/dev/client_coding/libreoffice_plugin_wire_protocol#document_setbibliographystyle).

| Callback value | Native paragraph mapping |
| --- | --- |
| `indent` | Left/body indent; twips divided by 20 to points |
| `firstLineIndent` | Relative first-line indent; negative values become a hanging indent |
| `lineSpacing` | Automatic line-spacing multiplier; callback value divided by 240 |
| `entrySpacing` | Spacing after each entry; twips divided by 20 to points |
| `tabStops` and `tabStopsCount` | Validated matching list/count; tab positions in twips divided by 20 |

The line-spacing conversion follows Zotero's
[`getBibliographyFormatParameters()`](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/cite.js),
which encodes the CSL line multiplier in units of 240.

Existing entry paragraph properties are retained when a later refresh supplies
text without another callback. `ZoteroFormattedText.paragraphBreakOffsets` and
`toParagraphRuns()` distinguish structural entry boundaries from soft breaks.
`WordZotero.canReplaceNativeBibliography()` checks exclusive ownership in the
real block list before replacement; ordinary inline edits retain their
narrower contract. New entries copy modeled paragraph formatting without
duplicating opaque source XML or structural aliases.

When native layout has not been applied, the adapter requests it again by
clearing only `bibliographyStyleHasBeenSet` in the exchanged XML/JSON document
data. A callback that cannot be applied to all eligible bibliography fields
does not mark the layout complete. This also repairs the preference left by
older simplified bibliographies after a successful native content refresh.

The client returns typed errors for access, rate limits, network/server failures,
and invalid responses. `Backoff` and `Retry-After` are respected without waiting
indefinitely or starting a hidden retry loop. The remaining delay is available
to hosts through the error's `retryAfter` value.

The online pause belongs to the host's `ZoteroSession`. Reconnecting, changing
public libraries, forgetting credentials, or closing and reopening the dialog
with that same session retains an unexpired pause. A late response from a closed
dialog can still extend it, and concurrent responses cannot shorten it. Desktop
catalog access keeps independent state and remains available during an online
pause. The deadline is checked on the next attempted request; it creates no
background timer, automatic retry, credential persistence or document data.
Custom hosts that replace online clients can pass the same `ZoteroBackoffState`
to each new client. Clients sharing that state must use the same clock.

## Current and previous qualification evidence

The [table-layout record](validation/zotero-table-layout-20261121/README.md)
tracks native table margins and bounded editable ODT uniform padding, including
inheritance, nested/merged cells, precision limits and repeated saves. Its local
checks and identified converter results remain separate from an installed
Zotero session in Word or a supported LibreOffice release.

The [LibreOffice style record](validation/zotero-libreoffice-styles-20261121/README.md)
tracks current script/default mapping, the exact untouched LibreOfficeDev 26.8
prose fixture and a separately identified synthetic Zotero extension using the
same style envelope. The earlier
[rich ODT import record](validation/zotero-rich-odt-20261121/README.md)
retains its original reader, active-field conversion, asynchronous editor/Studio
opening, DOCX save routing and then-observed style refusal. The continuation
addresses that exact fixture without editing its input bytes.
Synthetic import and controlled Zotero transaction tests do not establish an
installed Word/LibreOffice/Zotero round trip or legacy Apache OpenOffice parity.
The earlier [ODT inventory record](validation/zotero-odt-inventory-20261121/README.md)
retains its separate read-only scope and results.

The [table-cell range work record](validation/zotero-table-cell-ranges-20261121/README.md)
tracks cell ownership, rich replacement, cancellation/history and DOCX reopening
for that increment. Its local checks are distinct from installed
Word/LibreOffice plugin acceptance.

The [document-transfer work record](validation/zotero-transfer-20261121/README.md)
tracks the current handshake, carrier implementation, complete remote intake
and fresh local qualification. It keeps file conversion and controlled callback
tests separate from a live native Zotero plugin session.

The [multi-paragraph replacement work record](validation/zotero-multiparagraph-20261121/README.md)
retains the preceding implementation, complete remote intake and local qualification.
The preceding [vertical-table work record](validation/zotero-vertical-tables-20261120/README.md)
retains its own source and evidence. The earlier
[horizontal-merge and Refresh work record](validation/zotero-merged-cells-20261120/README.md)
records its incoming-work reconciliation, remote checkpoints,
exact-source checks and remaining application acceptance. Its qualified source,
`180399f99a3898501ab1959e3b845150d7da59fd`, completed 495 engine passes, 378
editor passes with eight skips, and 928 incoming Word/Mail passes: 1,801 passes
and eight skips across the three final processes, with zero failures or errors.
All 257 Zotero editor cases executed and passed; the eight skipped cases are
existing image-only layout fixtures, identified in the record. The same skips
are excluded from the corrected earlier-source tally. Repeated runs are not
added to the final total. PR #276 merged into main as `698209aaa6e7f1350b6541df5eb192b7b233443d`. These results
do not claim a new installed Zotero, Word or LibreOffice run, complete plugin
parity, or active ODT citation transfer. The
[research-table work record](validation/zotero-research-tables-20261120/README.md)
retains the preceding table increment's evidence. The
[authored-note and selected-text record](validation/zotero-note-targets-20261120/README.md)
retains the preceding increment's evidence and execution limits.

Zotero's current desktop plugin comparison targets are Word and LibreOffice.
Its [troubleshooting guidance](https://www.zotero.org/support/word_processor_plugin_troubleshooting)
explicitly excludes Apache OpenOffice from supported applications. Any Apache
OpenOffice compatibility work remains a separate legacy target, requiring
identified application, Zotero and plugin versions.

Embedded pictures and structured research lists have [completed local qualification](validation/zotero-parity-continuation-20261120/README.md)
on the combined source at `708f2821`, including incoming Office and Mail
regressions. The [earlier image checkpoint](validation/zotero-note-images-20261120/README.md)
is retained with its original development status and attribution.
The [Word/LibreOffice parity roadmap](roadmaps/zotero/word-processor-parity.md)
separates implemented workflows, current content boundaries and remaining live
interoperability acceptance. Earlier results below retain their original sources.

The research-note insertion, reference-navigation and direct-command continuation
has a [separate status report](validation/zotero-word-parity-20261118/README.md).
Its implementation and incoming branch integration are saved remotely. The report
separates completed development checks from the final exact-source run that was
blocked by shared executor disk exhaustion. That historical source has no
final passing total; the newer work records identify their own tested sources
and results.

The previous continuation started from Quds
`dc5f93b673e6087cccc6d66b33dfbfd099668f77` and CrispCloud
`45ed126a6d7da0ecd80f3a765155f54008b278f3`, after the prior Zotero PRs #47
and #149 and terminal PR #140 were merged. Before feature work, the initial
snapshot accounted for all **60 branch heads and 198 PR heads** across both
repositories. Main includes the subsequent ODS metadata work.

Its final incoming-work cutoff was **16 November 2026 at 05:17:13 UTC**. It
accounts for **62 branch heads and 199 PR heads**. The two continuation branches
are recorded separately; all **259 external refs** are actual ancestors after
merging the new CrispCloud terminal PR #160 at
`49d63f78d0b854ba76289dba69fdb6584f8a1260`. That merge preserves both parents.
The standalone parser pin is unchanged. The explicit cutoff bounds concurrent
work; it does not claim to include commits created after the snapshot.

Work is saved incrementally on `codex/zotero-support-20261116` in both
repositories. Checkpoints carry `[skip ci]`; no GitHub Actions are queried,
polled, awaited or rerun. Local verification uses official Flutter/Dart and
genuine locked dependency graphs. In the previous continuation, the local
catalog and document-refresh path passed against running Zotero 10.0.8 with synthetic sources, including
German `Ebd.`/page locators, native style selection, first-use catalog insertion
and DOCX save/reopen. Native locator-popup editing remains outside the successful
live acceptance scope; the seeded locator was accepted and preserved.

The saved-search, small-capital and bibliography-layout increment has a
[separate overview of completed qualification and live acceptance](validation/zotero-fidelity-20261116/README.md),
with its own exact-source receipts. Its checks do not reuse the previous run's
test totals or imply a full compiled application or Word/LibreOffice check.
See [zotero-validation.md](zotero-validation.md) for the recorded tested source,
results, reproduction commands and native acceptance scope. Full
compiled application builds and Microsoft Word/LibreOffice interoperability
remain separate acceptance steps. Historical evidence retains its original
source identity.

## Export an editable Zotero ODT copy

In Studio Word, choose **File → Export Zotero ODT…**, or **Export Zotero ODT**
on the File ribbon. Choose a new destination for the `.odt` copy. The operation
preserves supported active citation marks, complete bibliography sections and
Zotero document preferences; it does not need Zotero running. The active Word
file keeps its normal DOCX save destination and remains dirty if it has unsaved
changes. Cancelling the picker makes no document change.

The export supports complete unlocked fields in body paragraphs, visible body
table cells, and uniquely anchored authored footnotes/endnotes with ordinary
decimal numbering. Unsupported fields refuse before the save picker opens,
with a reason. Examples include incomplete or locked packets, fields in
headers/controls/note tables, partial bibliographies, and ambiguous note owners.
Choose a document style with Zotero first if the document has active fields but
no saved preferences.

Supported body tables write their uniform native cell margin as ODT padding,
including zero. Each nested table keeps its own margin. Values must be finite,
nonnegative, within the native DOCX margin limit of 32,767 twentieths of a point
(1,638.35 pt), and leave a positive content width in every emitted cell after
rounding. Table lengths in this ODT output use two decimal places in points;
DOCX margins use twentieths of a point (0.05 pt). Cross-format saves can therefore
round geometry. The [table-layout record](validation/zotero-table-layout-20261121/README.md)
documents this bounded behavior rather than an exact-geometry guarantee.

Editable ODT export also refuses effective absolute raised/lowered baseline
positions in text, paragraph marks and note markers. Inherited positions are
checked; explicit zero overrides and supported superscript/subscript remain
accepted.

Supported inline PNG and upright RGB JPEG pictures keep their raster bytes,
physical size, links, accessible titles and alternative descriptions in the
editable ODT copy. Duplicate or empty drawing-object names receive deterministic
unique names; the accessible metadata and original document objects are retained.
Reopening the supported subset retains one picture at each original position
and keeps adjacent citations editable. The document-wide limit is 32 pictures
and 4 MiB of image-file bytes, with the same raster bounds as Add Zotero Note.
Adjusted/floating pictures, shared picture owners and pictures inside citation
or bibliography results are outside this export contract and refuse before
saving. The [picture work record](validation/zotero-odt-images-20261121/README.md)
describes the tested conversions and remaining host-application boundaries.

Ordinary ODT export still writes visible citation caches. This explicit action
adds native Zotero metadata within the existing writer's formatting envelope;
it does not promise arbitrary Word formatting preservation or that every
exported document fits Quds' narrower ODT import subset. The
[native-output contract](roadmaps/zotero/native-odt-output.md) gives the precise
scope. Local round-trip tests and the recorded LibreOfficeDev file-save check
are separate from installed Zotero plugin acceptance on a release host.

## Open a native LibreOffice ODT

Supported uppercase character formatting now remains editable through native
ODT opening and later DOCX/ODT saves. The visible capitals do not rewrite the
underlying text or move citation boundaries. Explicit normal-case spans inside
uppercase paragraphs retain their authored case. Other case transformations
and an effective combination of uppercase with small capitals still refuse.
See the [combined round-trip qualification](validation/zotero-roundtrip-complete-20261121/README.md)
for the actual file-conversion scope and remaining native-plugin checks.

Studio **Open** accepts `.odt` files. A supported file opens in Writer with
editable paragraphs and active Zotero fields. The normal Zotero document tools
can then edit or refresh those fields with desktop Zotero running. The first
save proposes a `.docx` filename and asks for a destination; it does not reuse
the original ODT path. Keep the resulting DOCX to retain active citations and
document preferences. Ordinary **Export as ODT** keeps its visible cached-result
behavior. Use the separate [Export Zotero ODT](#export-an-editable-zotero-odt-copy)
action to preserve supported native editable marks in an ODT copy.

The importer accepts a bounded subset:

- Paragraphs and unnumbered headings with supported inherited character and
  paragraph formatting, explicit whitespace, external absolute hyperlinks and
  a compatible page layout. Supported Latin, complex-script and Asian font,
  size, weight, italic and language differences become native runs while
  retaining text and field positions.
- Canonical Zotero citation ReferenceMarks and bibliography ReferenceMarks or
  TextSections, including rich bibliography entries, empty paragraphs,
  multi-item options, adjacent fields and identical-looking citations with
  different native identities.
  Ordinary single-column bibliography section styles written by LibreOffice
  are accepted after their inherited formatting and protection are checked.
- Authored footnotes/endnotes with ordinary decimal numbering and live note
  anchors, simple decimal/bullet lists with independent starts/restarts and
  nested continuations, and rectangular tables with supported horizontal and
  vertical merges, nested up to eight levels. Citation ownership stays with its actual paragraph, note or cell.
  Identified LibreOffice decimal notes may use its zero-based starting offset;
  their visible note labels must match the complete sequence exactly.
- XML/JSON Zotero preferences, including unknown members. The explicit import
  converts `ReferenceMark` storage to Word `Field` only after reconstruction.
  Standard document properties are mapped; the exact original `meta.xml` is
  also retained as archival DOCX custom XML, including unrelated properties.
- Embedded character-anchored PNG and upright RGB JPEG pictures, including
  their size, supported run formatting, title, alternative description and
  ordinary links. Pictures occupy one native position; citations before or
  after them retain their original ownership and offsets.

Merged tables require an explicit ODT covered-cell element at every covered
logical position. Column spans are bounded to 32 and row spans to 256, within
the actual table. Citation text and metadata stay in the originating cell;
native continuation cells contain no duplicate citation. Supported widths,
row settings and inherited shading use the existing Word table representation.
Missing or overlapping coverage refuses the import. Covered cells containing
stored content, including empty paragraph elements or non-XML whitespace,
also refuse rather than losing hidden data. A covered cell's effective shading
and authored or inherited padding must be absent or agree with its origin.
Explicit borderless declarations are accepted; visible borders and other
unrepresented covered-cell styling remain outside this subset. Repeated
rows/cells remain unsupported. The document-wide cell and paragraph limits
include generated continuations and nested tables.

Cell padding resolves through family defaults and named parent styles. All four
effective sides must match, and every visible cell in one table must share that
margin. Zero is supported; no effective padding declaration means zero.
Nested tables resolve independently. Asymmetric padding, differing cell margins
and unsupported row/column default-cell styles refuse the import. Margins must
be finite, nonnegative, within the native DOCX storage limit above and leave
positive cell content width. ODT output and subsequent DOCX saves use their
respective point precision; exact geometry across formats is not promised.

The original merged-table [work record](validation/zotero-odt-merged-tables-20261121/README.md)
retains its earlier execution blocker. The subsequent
[editable-output qualification](validation/zotero-editable-odt-20261121/README.md)
executes those engine/editor regressions and preserves the actual results.
Imported decimal endnotes now retain their numbering through DOCX reopening.

Unsupported used formatting or structure rejects the whole import before it
replaces the active document. Examples include floating or adjusted drawings, comments,
revisions, protected/linked sections, repeated table owners, custom note
numbering, unsupported list continuation/affixes, relative/internal links and
ambiguous citation ranges. A citation cache containing a hyperlink is outside
the current editable field contract; external hyperlinks outside citations are
preserved. A field cannot enclose a note anchor or picture. Unsupported raster
formats, external image URLs, missing media and picture resource exhaustion
also refuse the whole import. Package, XML,
text and structural budgets apply throughout. The
[native-input contract](roadmaps/zotero/native-odt-input.md) gives the exact
envelope and remaining work.

The untouched LibreOfficeDev 26.8 prose fixture now opens with its Latin 11-point
and Arabic 10-point formatting intact. The
[style qualification record](validation/zotero-libreoffice-styles-20261121/README.md)
identifies its exact bytes and distinguishes it from the synthetic Zotero field
extension. Supported default settings are resolved after inheritance; dormant
Asian typography requires non-Asian current text and known supported break
languages. Active Asian typography, nonstandard default tab spacing used by
actual tabs, an active page grid and a used custom footnote separator still
refuse explicitly.

Editable Zotero ODT export preserves fixed table widths with left, center or
right alignment. This prevents LibreOffice from expanding those tables to fill
page margins. Returned table-only, bibliography and endnote-only documents are
checked independently through native reopening and further saves in the
[round-trip work record](validation/zotero-odt-roundtrip-20261121/README.md).
Actual footnotes using a LibreOffice separator remain outside the reader's
current formatting subset; accepting the note-numbering metadata does not
remove that layout restriction.

Complete uniform DOCX table margins, including zero, survive intervening saves
and supported table-style inheritance. Unsupported imported margin forms remain
in their original source XML. Native layout now uses the modeled uniform margin
for measurement, wrapping, row height, pagination and ruler insets, including
nested tables. Oversized grids can be scaled to a page or enclosing cell; if
that final width cannot contain the margins and positive content space, layout
refuses it. The [table-layout continuation](validation/zotero-table-layout-20261121/README.md)
records the delivered scope. Ordinary ODT export retains its existing formatting
and cached-result behavior.
Native editable notes declare exact superscript marker styles and the final
endnote page master; reopening refuses changed marker scaling or incompatible
page geometry. Optional soft-page caches are recomputed while authored hard
breaks are preserved.

Conversion preserves supported current content, rather than a complete live
ODF style engine for future typing or Zotero replacements. General LibreOffice
file compatibility, a lossless native ODT editing round trip, full plugin parity
and installed Zotero acceptance remain separate work. The original ODT bytes
are unchanged by either successful or failed conversion.

The next dedicated note-formatting milestone is a native footnote-separator
model, matching pagination/rendering and interoperable DOCX/ODT mapping before
admitting active LibreOffice separators. Actual installed Zotero workflows in
Word and supported LibreOffice releases still require separate validation.

Engine hosts can explicitly convert and save supported input:

```dart
final document = await OdtDocumentReader.readBytes(odtBytes);
final docxBytes = WordSerializer().writeBytes(document);
```

Editor hosts should call `WordEditorController.loadBytesAsync(odtBytes)` or use
`OfficeIsolateOpen.word` in their existing asynchronous open flow. The controller
refuses a result made stale by an edit, another open, document replacement or
disposal. Its synchronous `loadBytes` rejects native ODT with guidance to use
the asynchronous API. Hosts saving the returned Word document must select a
DOCX destination; Studio implements this routing automatically. The archived
metadata preserves source information, while ordinary Zotero callbacks use
the separately normalized native preferences.

## Inspect a native LibreOffice ODT

From `packages/quds_office_engine`, run:

```bash
dart run tool/zotero/odt_inventory.dart document.odt
```

The command prints JSON containing native citation marks, bibliography sections,
original field codes and preferences, visible cached text, exact endpoint
locations and findings. It reads the file without modifying it or starting a
Zotero session. Namespace aliases, authored notes, table cells and stored
unsupported stories retain their own identities. Malformed or ambiguous fields
remain visible with reasons; invalid packages and resource-limit failures return
a nonzero exit code instead of a partial success.

Applications can call the same public engine API:

```dart
final inventory = await OdfZotero.inspect(odtBytes);
final report = inventory.toJson();
```

`isValid` describes a field's canonical native name and metadata.
`isImportCandidate` also requires a supported, unambiguous physical range.
These remain inspection results. This API does not open an editable document,
normalize `ReferenceMark` preferences or change ordinary ODT export. The
separate [rich reader](#open-a-native-libreoffice-odt) performs the explicit
conversion after validating and reconstructing the supported content.
The [native ODT contract](roadmaps/zotero/native-odt-input.md) specifies bounds,
synthetic fixtures and the distinct inspection/import/installed-host scopes.

## Protocol sources

- [Zotero Web API v3](https://www.zotero.org/support/dev/web_api/v3/basics)
- [Zotero authentication](https://www.zotero.org/support/dev/web_api/v3/oauth)
- [Zotero local API](https://www.zotero.org/support/dev/web_api/v3/local_api)
- [Zotero 10 developer notes](https://www.zotero.org/support/dev/zotero_10_for_developers)
- [Local API implementation](https://github.com/zotero/zotero/blob/045d5204410f1abfd80910e1cd0aa92dceec741b/chrome/content/zotero/xpcom/server/server_localAPI.js)
- [Tag catalog desktop routes](https://github.com/zotero/zotero/blob/b589b7ff2f9fa5f1fea2a69b61a9e583e50d8cb8/chrome/content/zotero/xpcom/server/server_localAPI.js)
- [CSL JSON translator](https://github.com/zotero/translators/blob/master/CSL%20JSON.js)
- [HTTP citing protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [Bibliography wire-protocol parameters](https://www.zotero.org/support/dev/client_coding/libreoffice_plugin_wire_protocol#document_setbibliographystyle)
- [CSL character formatting](https://docs.citationstyles.org/en/stable/specification.html#formatting)
- [Unicode 17.0.0 special casing](https://www.unicode.org/Public/17.0.0/ucd/SpecialCasing.txt)
- [Pinned HTTP integration client](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/httpIntegrationClient.js)
- [Pinned Zotero integration implementation](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/integration.js)
- [zotero-cli reference implementation](https://github.com/jbaiter/zotero-cli)
- [Word processor transfer limits](https://www.zotero.org/support/kb/moving_documents_between_word_processors)
