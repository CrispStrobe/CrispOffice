# Zotero support

Quds Office includes local and online Zotero catalog browsing, a shared Flutter
references workspace, and DOCX citation/bibliography fields. Native desktop
hosts can now use Zotero's citation picker, document style dialog and complete
document CSL processor through its HTTP Citing Protocol. CrispCloud uses the
same engine and editor source through its guarded vendor manifest.

## Native Zotero document formatting

Open Zotero on the same computer, open a Word document in Quds Office or
CrispCloud, and choose **Insert → Zotero → Document**. Native desktop hosts show
**Zotero desktop citation tools** even before connecting the catalog browser.
They need the local transport and a running Zotero application, without an API
key. Zotero's own windows may open behind the office application.

| Control | Result |
| --- | --- |
| **Citation in Zotero…** | Opens Zotero's native picker at the document caret; edit locators, prefixes, suffixes and citation items there |
| **Document style…** | Opens Zotero's native document preferences, including the installed CSL style, language and note placement offered by that style |
| **Refresh all with Zotero** | Lets Zotero process the document's complete supported citation sequence and bibliography together |
| **Bibliography in Zotero…** | Adds or edits a bibliography through the same document processor |
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

The current source passed local protocol, engine, controller, dialog, Studio
transport and typography/PDF qualification. Running Zotero 10.0.8 also verified
saved-search execution and query scoping, plus four native refresh transactions
across German Chicago and a synthetic small-capital/double-line style, including
DOCX reopen. The [current feature overview](validation/zotero-fidelity-20261116/README.md)
links the exact source receipts, native protocol traces and before/after files.
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
- **Document:** inspect existing Zotero citations and bibliographies; edit safe
  fields; generate or update a bibliography; refresh basic citations; copy the
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

Use **Review selected** in either **Library** or **Import CSL JSON** to see all
selected sources, including references on another result page or hidden by a
filter. Move a source up or down to arrange the order passed to the citation
composer or Zotero's native picker, or remove one source without clearing the
others. A Zotero style may apply its own citation order. **Apply selection**
keeps the revised selection; **Cancel** or dismissing the dialog discards those
changes. Reordering and removal preserve each source's identity and embedded
metadata and do not add document history. Inserting a citation remains a
separate, undoable operation. The selection limit remains 20 sources.

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
its CSL result. Active citation transfer through ODT and opening the exported
file in Microsoft Word or LibreOffice remain outside the executed acceptance
scope.

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

The engine exports `ZoteroClient`, `ZoteroLibrary`, `ZoteroItem`, `ZoteroSavedSearch`,
`ZoteroCitation`, `ZoteroCitationItem`, and `WordZotero`. The editor adds
`WordEditorController.insertZoteroCitation`, `updateZoteroCitation`,
`refreshZoteroCitations`, `insertZoteroBibliography`,
`updateZoteroBibliography`, and `unlinkZoteroField`. Live field handles must be
re-inspected after a mutation or history operation.

For native transactions, use `ZoteroCitingClient`, `ZoteroCitingCancellation`,
`WordZoteroCitingSession` and `WordEditorController.beginZoteroTransaction`.
Run the transaction's current-target guard before every protocol command and
after host prompts. Review any reported simplifications, then apply the
completed transaction once. `WordZoteroDocumentData` handles native preference
ownership, translation and serialization. Raw session `apply` belongs inside
the controller's rollback boundary, not directly in a host widget.

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

## Previous continuation evidence and current qualification

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

## Protocol sources

- [Zotero Web API v3](https://www.zotero.org/support/dev/web_api/v3/basics)
- [Zotero authentication](https://www.zotero.org/support/dev/web_api/v3/oauth)
- [Zotero local API](https://www.zotero.org/support/dev/web_api/v3/local_api)
- [Zotero 10 developer notes](https://www.zotero.org/support/dev/zotero_10_for_developers)
- [Local API implementation](https://github.com/zotero/zotero/blob/045d5204410f1abfd80910e1cd0aa92dceec741b/chrome/content/zotero/xpcom/server/server_localAPI.js)
- [CSL JSON translator](https://github.com/zotero/translators/blob/master/CSL%20JSON.js)
- [HTTP citing protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [Bibliography wire-protocol parameters](https://www.zotero.org/support/dev/client_coding/libreoffice_plugin_wire_protocol#document_setbibliographystyle)
- [CSL character formatting](https://docs.citationstyles.org/en/stable/specification.html#formatting)
- [Unicode 17.0.0 special casing](https://www.unicode.org/Public/17.0.0/ucd/SpecialCasing.txt)
- [Pinned HTTP integration client](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/httpIntegrationClient.js)
- [Pinned Zotero integration implementation](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/integration.js)
- [zotero-cli reference implementation](https://github.com/jbaiter/zotero-cli)
- [Word processor transfer limits](https://www.zotero.org/support/kb/moving_documents_between_word_processors)
