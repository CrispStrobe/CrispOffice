# Native Zotero citing implementation review

## Scope and evidence

This continuation adds a desktop Zotero document transaction to the existing
catalog browser, citation fields and bibliography support. Zotero supplies its
own picker, document preferences and CSL processor. Quds supplies a bounded
HTTP driver, a staged Word document adapter and one atomic editor command.
CrispCloud uses the shared engine/editor source with its own restricted native
transport.

This review records the implemented contract, defects found during development
and remaining acceptance boundaries. The [qualification README](README.md)
and its receipts are authoritative for the exact qualified source fingerprints,
executed commands, test results and runtime/dependency identity. Counts from
earlier checkpoints are deliberately not repeated here. These are selected
local checks; this review does not claim that the entire workspace, a full
native application build or a live Zotero/Word session was tested. GitHub
Actions were not awaited.

The [user guide](../../zotero-support.md) describes the controls and limitations.
The [branch audit](branch-audit.json) records the reconciliation performed before
feature work.

## Implemented protocol contract

The implementation follows the pinned Zotero source at
`992853536935dce3249a4ecf61d0d129883f85c4`, particularly:

- [HTTP application, document and field wrapper](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/httpIntegrationClient.js).
- [Connector transaction endpoints](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/server/server_connectorIntegration.js).
- [Integration commands, preferences, citation ordering and error handling](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/integration.js).

The public [HTTP citing documentation](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
provides context, but some documented tuple responses and argument lists differ
from the current wrapper. The pinned implementation and the executable wrapper
fixture determine the implemented shapes.

`ZoteroCitingClient.execute` starts an explicit `addEditCitation`,
`addEditBibliography`, `refresh`, `setDocPrefs` or `removeCodes` command by
posting `{command, docId}` to
`http://localhost:23119/connector/document/execCommand`. Each received message
has `{command, arguments}`. The JSON value returned by the application handler
is posted directly to `/connector/document/respond`; it is not double encoded.
The driver never responds to `Document.complete`.

| Boundary | Implemented representation |
| --- | --- |
| Active document | Object with `documentID`, `outputFormat: html`, footnote/endnote support and processor name |
| Optional capabilities | Import/export, arbitrary text insertion and citation merging are advertised as unsupported |
| Document commands | Arguments begin with the exact document ID |
| Field commands | Arguments begin with the document ID and an already registered field ID |
| Field enumeration/insertion | Objects containing `id`, `code`, `text`, `noteIndex` and optional `adjacent`; enumeration preserves reading order |
| Field reads | The upstream wrapper caches code, text and note index; those reads do not issue HTTP commands |
| Conversion | `Document.convert(documentID, fieldIDs, Http, noteTypes)`; the HTTP wrapper does not send the legacy count argument |
| Formatting | HTML text goes through the existing bounded, inert formatted-text parser |
| Alerts | Button results preserve Zotero's exact OK/Cancel/Yes/No integer conventions |
| Completion | A terminal message with no response; successful application additionally requires no recorded failure and a current editor target |

`Document.cleanup` is a no-op in the current HTTP wrapper, so no cleanup command
is expected from the desktop. The driver's abort cleanup is its own bounded
protocol drain: it acknowledges activation/error notices and refuses further
document mutation. An initial HTTP 503 is treated as another transaction's
ownership; no response is submitted into that transaction.

The native field boundary translates `ITEM CSL_CITATION {...}` and
`BIBL {...} CSL_BIBLIOGRAPHY` into Word's `ADDIN ZOTERO_ITEM ...` and
`ADDIN ZOTERO_BIBL ...` instructions. Temporary fields may exist while staging,
but an unfinished field cannot be committed. Preferences translate only the
supported `prefs.fieldType` storage choice between native `Field` and wire
`Http`; unrelated XML/JSON preference data is retained by that translation.
Bookmark and unknown storage types are refused.

## Word preferences, notes and editor transaction

`WordZoteroDocumentData` reads the package-owned custom-properties part through
its OPC relationship, rather than assuming a filename owns the data. It reads
and writes numbered `ZOTERO_PREF_1`, `ZOTERO_PREF_2`, ... string properties,
preserves unrelated custom properties and unknown preference content, and
rejects duplicate, incomplete, malformed or ambiguously owned data. A null
model override preserves imported storage; an empty override explicitly clears
the Zotero properties. Chunking avoids splitting a UTF-16 surrogate pair.

The numbered-property convention and 255-character chunk limit were also
checked against Zotero's Word for Windows integration at
`d35757038a4bbb323a706ab6dc6b69c1c94c3dc7`:

- [document.cpp](https://github.com/zotero/zotero-word-for-windows-integration/blob/d35757038a4bbb323a706ab6dc6b69c1c94c3dc7/build/zoteroWinWordIntegration/document.cpp): `getDocumentData`/`setDocumentData` use the preference property; `getProperty`/`setProperty` concatenate and update numbered chunks.
- [zoteroWinWordIntegration.h](https://github.com/zotero/zotero-word-for-windows-integration/blob/d35757038a4bbb323a706ab6dc6b69c1c94c3dc7/build/zoteroWinWordIntegration/zoteroWinWordIntegration.h): `PREFS_PROPERTY` and `MAX_PROPERTY_LENGTH` define the name and limit.

`WordZoteroCitingSession` traverses body flow, including tables, and inserts
anchored note citations into that reading sequence. The processor's note index
is the note's ordinal in body order, independent of the stored note ID or the
order of objects in the footnote/endnote bucket. Ordinary notes with no Zotero
citation still count, and multiple citations within one note share its index.
New native citations can be inline, in a footnote or in an endnote. Moving an
existing note citation between those placements requires a note containing only
that citation and optional whitespace/reference marker; explanatory prose or
additional fields cause conversion to fail before application.

The session stores field descriptors and proposed preferences without changing
the live document. `WordZoteroTransaction` binds it to the original document,
monotonic content revision, caret, selection and editing context. Guards run
before/after protocol handlers and again before application. The controller
applies the completed result inside a rollback boundary, captures the result,
restores the original model, and commits the captured result as one history
command. Snapshots preserve paragraph and container identity, run properties,
owning block lists, note buckets and document preferences. An application
failure restores the original model without recording a partial operation.
Undo restores the original selection; redo restores the completed result.

## Defects found and corrected

### Completion after a Zotero error

Upstream `Integration.execCommand` calls completion from `finally`, including
after `_handleCommandError`. Treating every completion as success could apply
citations already changed before a later processor error. The driver now
recognizes the upstream STOP/OK and STOP/YES_NO error forms, displays and answers
the alert normally, then drains without dispatching any further handler calls.
It throws even if the desktop subsequently completes. The STOP/OK_CANCEL
replacement question remains an ordinary user choice. Regression transcripts
cover a partial field update followed by an error, both YES/NO answers,
subsequent mutation attempts, cancellation and failed acknowledgment.

### An unlinked field remains addressable

The actual HTTP wrapper permits `removeCode` followed by another operation on
the same field handle, including `delete`. Removing that handle from the
driver's known-field registry prematurely rejected a valid sequence. Only
deletion now removes the handle. The executable upstream wrapper fixture
reproduces the unlink-then-delete sequence.

### Note insertion at an existing marker

When a new note was inserted exactly at an existing note marker's start, field
ordering placed the new citation first but the note-index calculation could
assign it index 2. The tie now gives inserted/converting notes priority over
existing anchors, matching the actual insertion position. The regression checks
field order and note indices before application and after the live model has
received the insertion. Separate cases use nonsequential note IDs, reversed
note buckets, ordinary notes and several citations in one note.

### Catalog seeds, style placement and native XML defaults

A catalog selection appears to Zotero as an existing field. Upstream
`Session.cite` does not automatically move that field into the chosen style's
note placement. Always constructing it inline therefore gave note styles an
incorrect placement and note index. Seeds now use validated existing document
preferences. The workspace requires **Document style…** first when those
preferences are not usable. A completed seeded result whose final note type
differs is discarded; moving an already processed field afterward would not
repair its earlier CSL context.

The preference reader also accounts for Zotero's XML writer omitting falsy
preferences. An absent XML `noteType` means inline placement, matching upstream
`DocumentData.unserializeXML`; it is not treated as missing configuration when
the style and field type are otherwise valid. JSON values retain their explicit
type validation. An untouched catalog seed is discarded when the native picker
is cancelled.

### UTF-8 preference output must satisfy the reader's byte bound

The final custom-properties XML can occupy more UTF-8 bytes than its string
length suggests. A near-limit non-ASCII case reproduced a write/read mismatch:
output could be accepted for writing and then exceed the reader's 2 MiB part
limit. Serialization now checks the final encoded UTF-8 payload against that
same byte limit before any package mutation. Unknown properties still count
toward the final part size.

### Native result provenance

A citation formerly marked `qudsFormat: basic-author-year` must stop belonging
to the basic metadata-refresh formatter after native Zotero processes it.
Native citation results now record `qudsFormat: zotero-desktop`. A code-only
native update to a formerly basic citation is considered a real change even
when its display text and returned code would otherwise compare equal. This
prevents a later basic refresh from overwriting the native CSL result.

### Selection restoration through the history hook

The transaction's undo restored its selection snapshot, but the generic history
hook then collapsed it. The hook now preserves an explicitly restored
selection for this command. The transaction continues to collapse the selection
and place the caret after a newly inserted result when applying/redoing it.

## Real processor and wrapper provenance

The [fixture directory](../../../packages/quds_office_engine/test/fixtures/zotero/citing/README.md)
contains the generator, complete synthetic item/citation inputs, formatted
outputs, bibliography outputs and source metadata. The generator verifies the
Git blob SHA of every upstream input before executing it. Each source entry
also records its SHA-256 digest, repository, exact commit, source path, URL and
license declaration.

The processor is Zotero's unmodified bundled
[citeproc-js 1.4.61](https://github.com/zotero/zotero/blob/992853536935dce3249a4ecf61d0d129883f85c4/chrome/content/zotero/xpcom/citeproc.js).
It runs complete citation sequences through `rebuildProcessorState(..., html)`
and obtains bibliography output with `makeBibliography`. There are five
scenarios and nineteen formatted citation outputs:

| Scenario | Citation outputs | Evidence |
| --- | ---: | --- |
| German Chicago notes/subsequent-ibid | 9 | Same/changed page, intervening source, locator removal/introduction and multi-source cluster; includes `Ebd.` and `Ebd., 34.` |
| Numeric original sequence | 3 | `[1]`, `[2]`, `[1]` |
| Numeric sequence after a new first source | 4 | `[1]`, `[2]`, `[3]`, `[2]`; earlier sources renumber |
| APA one work | 1 | Author/year without a disambiguating letter |
| APA two works by the same author/year | 2 | Earlier result changes to `2024a`; the other result uses `2024b` |

Styles are pinned to `d16ba6427ca3c5dada6578a6f7a0f98bd3ea03b3`:
[Chicago notes/subsequent-ibid](https://github.com/citation-style-language/styles/blob/d16ba6427ca3c5dada6578a6f7a0f98bd3ea03b3/chicago-notes-bibliography-subsequent-ibid.csl),
[Elsevier Vancouver](https://github.com/citation-style-language/styles/blob/d16ba6427ca3c5dada6578a6f7a0f98bd3ea03b3/elsevier-vancouver.csl)
and [APA](https://github.com/citation-style-language/styles/blob/d16ba6427ca3c5dada6578a6f7a0f98bd3ea03b3/apa.csl).
Locales are pinned to `14940e56f7c783e4173cafbd92e0f5856f2caa14`:
[de-DE](https://github.com/citation-style-language/locales/blob/14940e56f7c783e4173cafbd92e0f5856f2caa14/locales-de-DE.xml)
and [en-US](https://github.com/citation-style-language/locales/blob/14940e56f7c783e4173cafbd92e0f5856f2caa14/locales-en-US.xml).
The editor does not hardcode the word, punctuation or locator syntax of ibid.;
the chosen CSL style and locale determine them.

The separate protocol fixture executes the actual pinned
`httpIntegrationClient.js` with only `sendCommand` replaced at its IPC boundary.
It records seventeen commands: active document; document data read/write;
insertion eligibility; cursor field; field enumeration/insertion; field
code/text updates; conversion; bibliography layout; alert; selection; unlink;
delete; activation; completion. Assertions additionally prove that cached field
reads issue no commands and completion clears the wrapper's in-progress flag.
The DOM stand-in used for the wrapper's text cache receives plain input only;
it is not evidence of browser HTML rendering. Dart tests replay the generated
contract and consume the real processor outputs through the document adapter.

The third-party processor, wrapper, styles and locales are test-generation
inputs and are not bundled into production. Their headers declare
CPAL-1.0 or AGPL-3.0-or-later for citeproc-js, AGPL-3.0-or-later for the Zotero
wrapper and CC-BY-SA-3.0 for the styles/locales. Attribution and source identity
remain in the fixture metadata. This proves processor outputs and wrapper
shapes without claiming a live Zotero dialog or native Word refresh.

## Transport and cancellation boundaries

The engine stays independent of Flutter and `dart:io`. The host provides the
native loopback transport. Citing POSTs are allowed only to the two exact
localhost routes, with `Content-Type: application/json` and
`Zotero-Allowed-Request: 1`. Credentials, unexpected headers, redirects,
external proxies and remote targets are refused. Local catalog GET support
keeps its existing separate route policy and shorter timeout.

One citing transaction runs per Dart isolate; Zotero's own 503 ownership check
covers other clients. Commands are bounded to 20,000, fields to 10,000, body
paragraphs to 100,000 and individual request/response payloads to 8 MiB UTF-8.
The JSON driver also bounds nesting and node count. Native user-dialog requests
can wait up to ten minutes. Abort cleanup is bounded to eight requests with a
shorter timeout. No POST is automatically retried.

Cancellation is cooperative. It can interrupt an application-side handler, but
an unanswered POST may already have reached Zotero. The driver waits for a
known next command before sending an abort response rather than guessing which
desktop command owns a response. While a native picker is open, the user must
finish or cancel it for that request to return. Ambiguous transport failure or
unfinished cleanup discards the staged result and reports that Zotero may need
restarting. Disposal closes the host's owned client and rejects pending work.

Explicit application cancellation and formatting-review cancellation discard
the entire staged transaction. Native picker cancellation follows Zotero's
protocol, which has no dedicated cancellation-result message: an untouched
catalog seed is removed, and Zotero may still return its session preference
update after cancellation. No claim is made that every native cancellation
leaves its session metadata byte-identical.

## Remaining formatting and acceptance boundaries

- **Inherited note-label preview:** Quds displays note references using their
  stored IDs. Those labels can differ from the note sequence after insertion or
  conversion. The CSL adapter uses body-order ordinals and DOCX keeps native
  automatic note references; it does not renumber storage identities to hide
  the preview issue. Visual numbering in Quds remains a layout limitation, and
  native Word's resulting note display still needs acceptance testing.
- **Inline formatting:** uniform bold, italic, underline, strike-through,
  superscript and subscript can remain on one protected citation run. Mixed
  inline formatting is simplified and disclosed before application. Existing
  imported formatting remains subject to the field-preservation rules.
- **Bibliography layout:** supported character formatting and numeric labels
  are retained. Small caps, hanging indents, paragraph/entry spacing, tab stops
  and margin-column layout remain simplified. An inline bibliography that
  cannot safely accept formatted runs is kept as protected plain text, with a
  review warning.
- **Supported document stories:** body flow and anchored footnotes/endnotes
  are supported. Zotero fields in headers, footers, comments, text boxes or
  unanchored notes cause the whole operation to refuse, so it cannot silently
  process an incomplete citation sequence. Locked, nested, malformed and
  cross-paragraph Zotero fields, protected documents, Track changes and
  unresolved revisions also refuse native processing.
- **Insertion/conversion:** new citations use a body insertion point; editing
  and refreshing existing supported note citations are available. Conversion
  of notes containing explanation, multiple citations or additional structure
  remains unsupported. Arbitrary Zotero note/annotation text insertion,
  adjacent-citation merging and native import/export are not advertised.
- **Runtime and format support:** the native path requires a running desktop
  Zotero and a host-provided local transport. Basic citations and individual
  catalog previews remain separate workflows. Browser/mobile native transport
  and active Zotero citation transfer through ODT are not implemented here.
- **Acceptance still required:** full Quds Studio and CrispCloud native builds;
  live Zotero picker/style/refresh/cancellation on supported desktop systems;
  live personal/group/unsynced-library identity resolution; native window focus
  and disposal behavior; and save/open/edit/refresh in Microsoft Word with its
  Zotero plugin. Existing real OS-keychain acceptance remains separate as well.
  Local protocol, serializer, controller, widget and transport evidence does
  not substitute for these checks.

Use the [qualification README](README.md) for the final executed coverage and
the source identity to which that evidence applies.
