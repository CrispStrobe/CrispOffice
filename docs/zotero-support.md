# Zotero support

Quds Office includes a read-only Zotero Web API client, a shared Flutter
references workspace, and DOCX citation/bibliography field support. CrispCloud
uses the same engine and editor source through its guarded vendor manifest.

## Using the editor

Open a Word document and choose **Insert → Zotero** (the **References** ribbon
group in Quds Studio and CrispCloud). The workspace has three tabs:

- **Library:** connect using a dedicated Zotero API key, or open a public user
  or group library by numeric ID. Browse personal/group libraries, collections,
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
as document text.

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

Hosts supply the network transport. CrispCloud uses its existing selected proxy
and TLS policy, refuses redirects, limits each response to 8 MB, bounds the
request to 20 seconds, closes pending requests when the editor closes, and
displays fixed diagnostics without network response bodies or credentials.
The shared client fixes its HTTPS origin to `api.zotero.org`, requests API v3,
and sends authentication in the `Zotero-API-Key` header.

## Formatting and interoperability

| Operation | Supported behavior | Boundary |
| --- | --- | --- |
| Basic citations | Author–year fallback, multiple sources, locators and affixes | Not a named CSL style |
| Single-source style preview | Zotero's individual citation text for a style ID and locale | Review locators and document numbering; this is not a document-wide CSL run |
| Zotero bibliography | One complete API rendering of up to 50 distinct sources in one library | Inserted as plain text; no separately formatted batches are concatenated |
| Basic bibliography | Sorted, deduplicated entries from embedded source snapshots | Useful offline, without complete CSL formatting |
| Refresh | Fetch source metadata and atomically refresh Quds basic author–year citations | Imported/custom style caches are not automatically replaced |
| Existing DOCX fields | Preserve Zotero codes, unknown JSON members, source data and cached text | Unsupported rich/nested/locked/multi-paragraph replacements are refused |
| Native Zotero document preferences | Preserve imported `ZOTERO_PREF_*` properties as opaque package content | New document-wide style/session preferences are not fabricated |

New citations use complex Word fields with `ADDIN ZOTERO_ITEM CSL_CITATION`
codes, durable Zotero item URIs, and embedded CSL item snapshots. Bibliographies
use `ADDIN ZOTERO_BIBL … CSL_BIBLIOGRAPHY`. Legacy `ADDIN CSL_CITATION` fields
are recognized. Existing source JSON is retained, including members not modeled
by this editor. Library identity includes both user/group kind and numeric ID;
an item key alone is not a unique source identifier. Known URI scheme/hostname
aliases are deduplicated without rewriting imported metadata.

The field codec does not implement Zotero's desktop HTTP citing transaction
protocol or a complete CSL processor. It does not claim automatic document-wide
numeric ordering, disambiguation, ibid, cross-word-processor transfer, or native
Zotero/Word refresh certification. Those require a separate complete processor
or desktop adapter and native acceptance checks. The UI identifies basic
formatting and individual previews explicitly.

Ordinary save/reopen retains unsupported fields instead of replacing them with
plain text. Converting a field to text is an explicit, undoable user action.
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
  // Optional: persistApiKey: yourExistingSecureStore,
);
```

The transport receives a `ZoteroHttpRequest` and returns a
`ZoteroHttpResponse`. Disable redirects, set request/response bounds, and close
owned clients on disposal. The pure Dart engine never imports Flutter or
`dart:io`. Hosts without a transport can still offer offline import, field
management, and embedded-source export.

The engine exports `ZoteroClient`, `ZoteroLibrary`, `ZoteroItem`,
`ZoteroCitation`, `ZoteroCitationItem`, and `WordZotero`. The editor adds
`WordEditorController.insertZoteroCitation`, `updateZoteroCitation`,
`refreshZoteroCitations`, `insertZoteroBibliography`,
`updateZoteroBibliography`, and `unlinkZoteroField`. Live field handles must be
re-inspected after a mutation or history operation.

The client returns typed authentication, permission, pagination and rate-limit
failures. `Backoff` and `Retry-After` are respected without waiting indefinitely
or starting a hidden retry loop. The next attempt reports a remaining delay.

## Development baseline and verification

The continuation started from Quds `1d7fee380def59d5a766cab106e519952d5c3292`
and CrispCloud `ebb8d13cd7688e32c24be81dafd88c6f8de82f0c`. All branch and PR
heads were fetched and reviewed. There were no open PRs at that cutoff. Recent
squash-merged feature heads were verified with `git cherry` and their ancestry
was recorded without changing the current source tree. CrispCloud also includes
the previously unmerged terminal documentation checkpoint
`8261a0de7290a09320129c55ae513aa061a2f7d6`.

Before Zotero changes, CrispCloud's Quds mirror was synchronized from
`3d255f0f5c37af3efbaf69b29f4fcfc869de3eaa` to current Quds, retaining the
UTF-16 custom-XML bibliography fix and ODS conditional formatting. Its separately
maintained legacy DOC parser pin remains unchanged.

Changes are checkpointed incrementally on `codex/zotero-support-20261115` in
both repositories. Engine and editor changes are separate commits. Hosted CI is
not awaited; checkpoint commits carry `[skip ci]` to avoid consuming a starved
Actions queue. Local checks and their scope are recorded in
`docs/zotero-validation.md`.

## Protocol sources

- [Zotero Web API v3](https://www.zotero.org/support/dev/web_api/v3/basics)
- [Zotero authentication](https://www.zotero.org/support/dev/web_api/v3/oauth)
- [Zotero local API](https://www.zotero.org/support/dev/web_api/v3/local_api)
- [HTTP citing protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [Zotero integration implementation](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/integration.js)
- [Word processor transfer limits](https://www.zotero.org/support/kb/moving_documents_between_word_processors)
