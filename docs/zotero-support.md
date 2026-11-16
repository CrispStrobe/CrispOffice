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

### Apply, cancel and undo

Zotero commands work on a detached transaction. No document changes are applied
until Zotero completes successfully and the original document, revision, story,
caret and selection are still current. The entire operation is one undo step,
including note conversion, bibliography updates and document preferences.
Undo restores the original selection as well as the document content.
Zotero also sends a completion command after reporting internal errors. The
driver recognizes its error-alert forms, acknowledges the dialog, drains the
transaction and discards every staged change in that case.

Bold, italic, underline, strike-through, superscript and subscript are retained
inside citations, including mixed styling such as italic book titles beside
ordinary author text. The complete citation remains a protected field when
typing, deleting, copying, pasting or splitting paragraphs. Native refresh,
safe note conversion, DOCX save/reopen and undo/redo preserve these styles.
Small caps and unsupported bibliography layout still require a review before
simplification. Cancelling that review leaves the document alone.
An untouched catalog seed is discarded if the native picker is cancelled.

Only one desktop citing transaction runs at a time. While Zotero is waiting in
its own picker, finish or cancel that dialog. **Cancel operation** requests
cancellation; it cannot safely abandon an unanswered desktop command and start
another transaction immediately. Requests are never automatically retried.
An ambiguous connection loss reports that Zotero may need restarting before
trying again. The desktop window can wait up to ten minutes for a native
dialog; ordinary catalog requests retain their shorter timeout.

Native processing refuses a protected document, active Track changes,
unresolved revisions, locked/nested/malformed or cross-paragraph Zotero fields,
and citations in unsupported stories such as headers, footers, comments and
text boxes. Resolve those conditions first. This avoids processing an
incomplete citation sequence. The session is bounded to 10,000 fields, 100,000
body paragraphs, 20,000 commands and 8 MiB command payloads.

This integration is covered by local protocol, engine, controller and dialog
tests plus outputs from Zotero's pinned real CSL processor. A live desktop
session, full native application build and native Word/Zotero refresh acceptance
remain to be checked. See [current validation](zotero-validation.md).

## Using the editor

Open a Word document and choose **Insert → Zotero** (the **References** ribbon
group in Quds Studio and CrispCloud). The workspace has three tabs:

- **Library:** choose an online library or, in a native desktop host, Zotero
  desktop on this computer. Online connections use a dedicated API key or a
  public user/group library ID; desktop connections need no API key. Browse personal/group libraries, collections,
  and paged search results. Select up to 20 sources for a citation, then review
  its text and per-source locator, label, prefix, suffix and author options.
- **Document:** inspect existing Zotero citations and bibliographies; edit safe
  fields; generate or update a bibliography; refresh basic citations; copy the
  embedded CSL JSON; or explicitly convert a field to ordinary text. Each
  document operation is undoable and advances the editor's save revision.
- **Import CSL JSON:** paste a Zotero CSL JSON export for offline work. A single
  item, a CSL array, and Zotero's `{"items": [...]}` envelope are accepted.
  Import is bounded to 1 MB and 500 records. Linked Zotero URIs are retained;
  records without them remain offline embedded references.

The selected references can also be copied as BibTeX, BibLaTeX, RIS, or CSL JSON
from the Library tab. Source exports are copied as reference data, not inserted
as document text. Library exports accept numeric user/group identities or unsynced local identities
from one matching connected library. Desktop exports need Zotero 10 or later
with database and library-version headers. Use **Document → Copy embedded CSL
JSON** for mixed-library or offline documents, or with an older desktop client.
Set the preview/export style ID and locale in Document (defaults: `apa` and `en-US`) before
requesting a bibliography or individual citation preview. In the citation
composer, expand a source's title to edit its locator and affixes.

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
workspace. Browsing, collection navigation, pagination, search and selection use
the locally available personal and group libraries, including unsynced items.
The source selector and connection do not change the document.

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
not require a citation style or ask Zotero to generate formatted text. Use the embedded CSL export or basic bibliography
when a connected aggregate operation cannot be verified.

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
| Native document processing | Zotero picker, document style/locale, complete citation refresh, numeric ordering, disambiguation and style-dependent ibid | Running desktop Zotero required; supported stories and safe note conversions only; live native acceptance pending |
| Basic citations | Author–year fallback, multiple sources, locators and affixes | Not a named CSL style |
| Single-source style preview | Zotero's individual citation text for a style ID and locale | Review locators and document numbering; this is not a document-wide CSL run |
| Zotero bibliography | One complete API rendering of up to 50 distinct sources in one library, with supported rich character formatting | Review before insertion; small caps and paragraph layout are simplified; no separately formatted batches are concatenated |
| Basic bibliography | Sorted, deduplicated entries from embedded source snapshots | Useful offline, without complete CSL formatting |
| Refresh | Fetch metadata for at most 50 distinct linked sources, verify their complete saved identities, and atomically refresh Quds basic author–year citations | Local identities require the matching desktop connection; imported/custom style caches are not automatically replaced |
| Existing DOCX fields | Preserve Zotero codes, unknown JSON members, source data and rich cached text, including multi-run simple fields | Nested, locked, opaque and multi-paragraph replacements are refused |
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

The new desktop adapter delegates complete CSL processing to Zotero. Basic
formatting and individual previews remain available when the desktop is not
connected, and remain explicitly identified. A citation processed by native
Zotero is marked separately so **Refresh basic citations** cannot overwrite
its CSL result. Active citation transfer through ODT and native Zotero/Word
refresh certification remain outside the executed acceptance scope.

### Rich bibliography review and imported citation preservation

**Document → Zotero bibliography** now opens a formatted review. **Keep Zotero
formatting** is selected initially. Bold, italic, underline, strike-through,
superscript and subscript are inserted as native Word run properties and remain
available after saving, reopening, updating, undo and redo. Numeric bibliography
labels stay beside their entry text. Turn off **Keep Zotero formatting** to edit
and insert a plain-text version explicitly. Cancelling the review does not
change the document; a changed caret or document still refuses stale insertion.

Small caps, hanging indents, spacing, multi-column margins and arbitrary CSS are
not rendered faithfully. The review reports known unsupported formatting.
Entries retain their order and text using line breaks in one bibliography
paragraph. Links remain inert text. A bounded XHTML parser accepts only supported
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
are preserved and refuse replacement, so these choices are not discarded.
Update those choices in Zotero before regenerating the bibliography here.
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

The engine exports `ZoteroClient`, `ZoteroLibrary`, `ZoteroItem`,
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

The client returns typed errors for access, rate limits, network/server failures,
and invalid responses. `Backoff` and `Retry-After` are respected without waiting
indefinitely or starting a hidden retry loop. The remaining delay is available
to hosts through the error's `retryAfter` value.

## Development baseline and verification

The native-citing continuation starts from Quds
`f40aa887325982ea70c8285b25f8ff5b92a46eb9` and CrispCloud
`fe22a0458acfa90c0cce457d20fecbaa85a260e6`. Before feature work, all 45 live
branches and all 42 Quds/recent 50 CrispCloud PR heads were reconciled. No new
distinct work was missing: Quds main through #42, CrispCloud main through #152
and terminal #140 were already included; five retained Quds branches were exact
tree equivalents of integrated squash changes. The standalone parser pin stays
unchanged.

The final reconciliation also includes work that arrived during implementation:
Quds main through **#46**, CrispCloud main through **#156**, and terminal #140
through `a965bfd4a61ca01e6f50bf4d8c433c3fdc9e1423`. The main and terminal merges
retain both parents. Quds #40 was merged during the work; a new draft PR carries
the continuation beyond it. Final audit receipts distinguish the initial
snapshot from this later integration.

Work is checkpointed incrementally on `codex/zotero-support-20261115` in both
repositories. Checkpoints carry `[skip ci]`; GitHub Actions are not awaited.
Local Dart/Flutter execution is available. Current test results, exact source
fingerprints, runtime/dependency receipts and reproduction commands are recorded
in [zotero-validation.md](zotero-validation.md). Historical validation retains
its original source identity. Full builds and live native acceptance are
reported separately from local source qualification.

## Protocol sources

- [Zotero Web API v3](https://www.zotero.org/support/dev/web_api/v3/basics)
- [Zotero authentication](https://www.zotero.org/support/dev/web_api/v3/oauth)
- [Zotero local API](https://www.zotero.org/support/dev/web_api/v3/local_api)
- [Zotero 10 developer notes](https://www.zotero.org/support/dev/zotero_10_for_developers)
- [Local API implementation](https://github.com/zotero/zotero/blob/045d5204410f1abfd80910e1cd0aa92dceec741b/chrome/content/zotero/xpcom/server/server_localAPI.js)
- [CSL JSON translator](https://github.com/zotero/translators/blob/master/CSL%20JSON.js)
- [HTTP citing protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [Pinned HTTP integration client](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/httpIntegrationClient.js)
- [Pinned Zotero integration implementation](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/integration.js)
- [zotero-cli reference implementation](https://github.com/jbaiter/zotero-cli)
- [Word processor transfer limits](https://www.zotero.org/support/kb/moving_documents_between_word_processors)
