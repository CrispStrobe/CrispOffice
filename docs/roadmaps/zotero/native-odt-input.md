# Native ODT Zotero input: implementation contract

Status: **Bounded horizontal/vertical merged-table input is locally qualified
by the [editable-output continuation](../../validation/zotero-editable-odt-20261121/README.md).
Imported decimal and lower/upper Roman notes retain their numbering through
DOCX saves; the [numbering continuation](../../validation/zotero-note-numbering-20261122/README.md)
adds exact continuous start-one sequences and native settings. The
[next continuation](../../validation/zotero-parity-next-20261122/README.md)
supports independent continuous starts from 1 to 32,768 with explicit producer
conventions and exact cached labels. Earlier
rich-import and LibreOffice style results retain their original sources.
The [picture continuation](../../validation/zotero-odt-images-20261121/README.md)
adds bounded embedded inline PNG/JPEG input, with local lifecycle checks and
separately retained LibreOfficeDev converter evidence.
The separate [native-output contract](native-odt-output.md) now defines explicit
editable ODT copy export. Installed-host/plugin acceptance remains open.**

The [table-layout continuation](../../validation/zotero-table-layout-20261121/README.md)
adds effective uniform table-cell padding, including zero and supported style
inheritance. Native table layout now uses those modeled margins. The precision,
covered-cell and final layout limits are defined in Increment 8 below.

The [native round-trip continuation](../../validation/zotero-odt-roundtrip-20261121/README.md)
extends reopening of actual LibreOffice-saved bibliography sections and
identified decimal-note metadata. It also corrects editable table export
geometry. Its current validation and remaining footnote-layout boundary are
recorded separately from the preceding milestones.

`OdtDocumentReader.readBytes` builds an editable `WmlDocument` from the supported
ODT subset below. The asynchronous Word loader and Studio Open use this reader;
the resulting active document saves as DOCX. The
[style continuation record](../../validation/zotero-libreoffice-styles-20261121/README.md)
records its qualified source, remote checkpoints, local execution and exact
untouched LibreOfficeDev fixture. The earlier
[rich-import validation record](../../validation/zotero-rich-odt-20261121/README.md)
retains its original source and then-observed style refusal.

`OdfZotero.inspect` and `tool/zotero/odt_inventory.dart` remain read-only. Their
[inventory validation record](../../validation/zotero-odt-inventory-20261121/README.md)
retains its original source and results. The earlier execution-blocked
checkpoint is preserved as history; its lack of runtime qualification is not
attributed to either delivered increment.

Baseline: [`1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0`](https://github.com/CrispStrobe/quds_office_suite/commit/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0).
The [continuation record](../../validation/zotero-native-odt-20261121/README.md)
records that checkpoint's frozen remote intake, two then-outstanding branch
heads and local execution blocker. Both heads were subsequently integrated
into main. The delivered increments advance the existing
[word-processor parity roadmap](word-processor-parity.md) with separate scopes
for inspection, conversion into an editable Word document, native ODT output
and installed-host interoperability.

## Baseline finding: rich ODT input was a prerequisite

At the baseline above, the tree had a native ODT exporter and bounded ODF text
extraction, but no ODT-to-`WmlDocument` reader. Adding reference-mark handling
to the text extractor alone would have lost the formatting and structural
ownership needed by editable citations. These baseline boundaries informed the
new reader and remain useful when distinguishing its responsibilities.

| Baseline boundary | Contract to retain |
| --- | --- |
| [`odf_text.dart`](https://github.com/CrispStrobe/quds_office_suite/blob/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0/packages/quds_office_engine/lib/src/odf/odf_text.dart) | Namespace-aware text decoding with cumulative output limits. Body extraction deliberately omits authored notes, annotations, covered-cell stories and stored revisions. It does not retain mark endpoints. |
| [`office_text_extractor.dart`](https://github.com/CrispStrobe/quds_office_suite/blob/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0/packages/quds_office_engine/lib/src/extract/office_text_extractor.dart) | Produces extraction results, not a rich editable Word document. |
| [`office_open_decode.dart`](https://github.com/CrispStrobe/quds_office_suite/blob/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0/packages/quds_office_engine/lib/src/opc/office_open_decode.dart) | The Word route calls the DOCX deserializer; a native ODT route needs explicit format dispatch. |
| [`word_deserializer.dart`](https://github.com/CrispStrobe/quds_office_suite/blob/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0/packages/quds_office_engine/lib/src/word/serial/word_deserializer.dart) | Reads OOXML document parts. Passing an ODT package here is not an import implementation. |
| [`odt_document_writer.dart`](https://github.com/CrispStrobe/quds_office_suite/blob/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0/packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart) | Ordinary ODT export writes visible cached Zotero results. Editable metadata is intentionally omitted; transfer carriers follow their separate hyperlink contract. |
| [`word_zotero_data.dart`](https://github.com/CrispStrobe/quds_office_suite/blob/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0/packages/quds_office_engine/lib/src/word/model/word_zotero_data.dart) | Normal native callbacks accept Word/HTTP field storage. The explicit transfer conversion separately handles foreign field types. Do not widen ordinary callbacks to accept ODT marks. |
| [`word_zotero.dart`](https://github.com/CrispStrobe/quds_office_suite/blob/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0/packages/quds_office_engine/lib/src/word/model/word_zotero.dart) | Active fields own native paragraph/story ranges and validated instructions. A flattened text match is insufficient ownership. |

The existing [ODT writer test](https://github.com/CrispStrobe/quds_office_suite/blob/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0/packages/quds_office_engine/test/odt_document_writer_test.dart)
explicitly checks cached-result export without hidden Zotero instructions.
Native ODT output must therefore be a separately specified behavior, with its
own tests, rather than an incidental change to ordinary export.

## Increment 1: read-only inventory with explicit ownership

Implementation entry point:
`packages/quds_office_engine/lib/src/odf/odf_zotero.dart`.
Immutable results and limits are in `odf_zotero_models.dart`; preference
inventory is in `odf_zotero_preferences.dart`. The API is
`Future<OdfZoteroInventory> OdfZotero.inspect(Uint8List bytes, {OdfZoteroLimits limits})`.

The reader examines the actual ODT package's `content.xml`, optional
`styles.xml` and optional `meta.xml`, after checking its MIME type and ZIP
directory. Embedded subdocuments are not recursively opened. Their owners are
reported as unsupported. Canonical marks and sections in other stories remain
visible as inventory records. A field's `isValid` refers to its canonical name
and metadata; `isImportCandidate` additionally requires an unambiguous supported
range. Neither property makes an editable document or validates a full ODF
formatting model. `toJson()` explicitly reports `editable: false`.

Paths contain zero-based element-child indexes, independent of XML prefixes.
Each endpoint retains its part, story identity and structural owner chain.
An endpoint inside a paragraph also retains its paragraph path/index and
UTF-16 offset; section boundaries can have null paragraph coordinates, with
their paragraph ranges retaining those coordinates separately. Deferred
collapsed spaces are resolved
before final offsets are published. Bibliographies retain separate paragraph
ranges, including empty paragraphs. Unknown, protected, linked, repeated and
overlapping ownership stays ineligible. Source bytes and properties are never
rewritten.

Default bounds are 64 MiB archive bytes, 10,000 ZIP entries, 16 MiB per XML part,
24 MiB total selected XML, 128 XML levels, 200,000 XML elements, 10,000 fields,
20,000 endpoints, 100,000 paragraphs, 1 Mi UTF-16 units plus 32 for native
names, and separate 16 MiB UTF-8 budgets for decoded text and cached field text.
Section traversal records its own paragraph interval, so an empty section does
not rescan unrelated paragraphs. Cumulative range work is capped at 200,000
candidate paragraph visits, and materialized field ranges at 100,000 independently
of their text length. Empty or repeatedly nested content cannot evade these
limits.
Duplicate ZIP members and expanded XML attributes reject before ownership is
selected. A bound failure throws instead of returning a partial inventory.
Preference data retains its existing 256 Ki UTF-16 limit, with separate
property, chunk and collected-text limits.

Read the original package and return typed immutable records. Do not mutate
package parts, create Word fields, start a Zotero session or advertise editable
ODT support. Retain enough original information to explain every finding and
allow a later importer to make an explicit conversion decision.

Each detected Zotero mark should retain its original name, logical field code,
field kind, validated payload when available, exact endpoint identities, cached
visible text, and findings. Endpoint identity should include the source part,
story, paragraph and structural owner chain, including table cells. Distinguish
body, footnote, endnote, annotation, drawing/text-box and hidden/revision
contexts. A mark in an unsupported story must be reported; silently omitting it
would make a later importer falsely believe the document is citation-free.

Keep recognition, validity and import eligibility separate:

- A recognizable name with malformed metadata is a detected invalid mark.
- A valid field in an unsupported or ambiguous range remains an inventory
  record with a concrete reason it cannot yet be imported.
- A supported range is only an importer candidate. It is not an active
  `WmlZoteroField` until the rich document and native ownership exist.

Pair only namespace-qualified reference-mark endpoints with matching
namespace-qualified names. Ordinary non-Zotero reference marks and foreign
namespace lookalikes must not become citations. Detect duplicate names across
the package, duplicate starts/ends, missing endpoints, crossed/nested ranges
and endpoints that change story or structural ownership. Do not pair a body
start with an endpoint inside a note, annotation or nested cell.

An empty point reference mark must be detected and classified explicitly.
Do not invent cached text for it. Native bibliographies may be stored as named
LibreOffice TextSections: the pinned plugin's bibliography update path creates
a section, and its `getFields('ReferenceMark')` enumerates sections as well as
reference marks. Inventory namespace-qualified `text:section` elements whose
`text:name` contains a recognized Zotero bibliography code, retaining the
section's native block ownership and paragraph boundaries. Pairing only
reference-mark-start/end elements would miss this native bibliography form.
Ordinary sections and namespace lookalikes must not become bibliographies.
Detect duplicate names and overlapping ownership between section and mark
records. Preserve nested, protected, linked or otherwise unsupported section
findings explicitly. Initial eligibility limits belong in code and tests.

### Native name and preference contracts

Pin the initial implementation against Zotero LibreOffice integration
[`0a31b434371eb21a1297c5bce8ca4978cb9ab425`](https://github.com/zotero/zotero-libreoffice-integration/commit/0a31b434371eb21a1297c5bce8ca4978cb9ab425).

Current [ReferenceMark.java](https://github.com/zotero/zotero-libreoffice-integration/blob/0a31b434371eb21a1297c5bce8ca4978cb9ab425/build/source/org/zotero/integration/ooo/comp/ReferenceMark.java) combines the
`ZOTERO_` prefix, the logical field code and a final random identity suffix.
[Document.java](https://github.com/zotero/zotero-libreoffice-integration/blob/0a31b434371eb21a1297c5bce8ca4978cb9ab425/build/source/org/zotero/integration/ooo/comp/Document.java) defines the suffix length and alphabet,
additional legacy prefixes, and document preference property families.

For the current canonical form, preserve the complete name and separate only
the verified terminal ` RND` plus ten alphanumeric characters. Never split at
an arbitrary occurrence inside quoted citation JSON. Distinct random suffixes
keep otherwise identical citation payloads independently identifiable.

Parse citation and bibliography payloads with the existing bounded Zotero
metadata semantics. Preserve unknown supported metadata fields and raw codes.
Reject invalid trailing content, malformed JSON, mismatched kind/suffix and
oversized data explicitly. Legacy prefixes and old suffix forms must either
have dedicated fixtures and a qualified path or remain detected but
unsupported; current canonical support is not evidence of historical plugin
compatibility.

Read preference chunks from the actual `office:meta` owner in `meta.xml`.
Use expanded namespace names, not literal prefixes or arbitrary descendant
matches. [Properties.java](https://github.com/zotero/zotero-libreoffice-integration/blob/0a31b434371eb21a1297c5bce8ca4978cb9ab425/build/source/org/zotero/integration/ooo/comp/Properties.java) writes numbered chunks
of at most 255 Java string characters. Test numeric ordering beyond chunk 9,
duplicate names, gaps, noncanonical indexes, conflicting property families,
incorrect value types and malformed XML/JSON. Respect ODF's default value-type
semantics rather than rejecting a valid omitted type attribute by assumption.

Preserve the original preference string and unrelated properties. The explicit
native-ODT import boundary in Increment 2 normalizes `ReferenceMark` preferences
only after it has constructed the corresponding fields. Reuse the existing
256 Ki UTF-16-unit preference bound; do not weaken `WordZoteroDocumentData.toHttp`
to make an unconverted ODT document appear valid.

### Whitespace, offsets and resource bounds

Decode text while observing endpoints. Literal XML whitespace, explicit
`text:s`, tabs, line breaks, span boundaries and Unicode must use one
consistent positional model. Define offsets as UTF-16 code units if they
will feed the existing Word/Dart model. Handle pending collapsed whitespace
at endpoints deliberately and test it; decoding the whole paragraph first
and searching for citation text cannot distinguish identical occurrences.

Reuse the package/XML safety limits and cumulative ODF output budgeting where
applicable. Bound mark count, depth, decoded text, name/code length and
preference length before allocations. Report the limit reached rather than
returning a partially successful inventory with silently missing marks.
Unsupported embedded objects must retain an explicit ownership finding.

### Required tests for this increment

Implemented tests:

- `test/odf_zotero_reference_marks_test.dart`
- `test/odf_zotero_preferences_test.dart`
- `test/odf_zotero_ownership_test.dart`
- `test/odf_zotero_resource_test.dart`
- `tool/zotero/odt_inventory_acceptance.dart`

These paths are relative to `packages/quds_office_engine`. Fixtures are synthetic
and pinned to the native plugin's storage contract; they are not claimed as
files produced by an installed LibreOffice/Zotero session.

| Area | Required cases |
| --- | --- |
| Basic fields | Citation, reference-mark and section-backed bibliography, multiple clusters, identical metadata with different names, non-Zotero marks/sections, empty point marks. |
| Text positions | Arabic and supplementary Unicode, escaped XML/JSON, styled spans, quoted ` RND` in JSON, leading/trailing literal spaces, explicit repeated spaces, tabs and line breaks. |
| Ownership | Body, authored footnote/endnote, ordinary and nested table cells, covered cells, annotation and drawing stories, stored revisions, multiparagraph bibliography. |
| Ambiguity | Duplicate names even across stories and section/mark records, duplicate or missing endpoints, crossed/nested marks, overlapping sections/marks, cross-cell and cross-story ranges, malformed native names. |
| Preferences | One/many chunks, ordering past 9, gaps, duplicates, invalid indexes/types, absent default type, conflicting families, extensions, malformed content, exact limit and over-limit data. |
| Preservation | Original bytes and unrelated metadata unchanged; unsupported content reported explicitly; deterministic order and stable identities on repeated reads. |
| Bounds | Deep trees, many marks, large names/JSON, whitespace expansion, cumulative text, preferences, and failure without a misleading partial-success result. |

Run meaningful parser tests using the repository-pinned Flutter/Dart SDK and
locked dependencies. Run targeted existing ODF extraction, Word Zotero data,
field and transfer tests to establish that the new reader has not weakened
their contracts. Static review alone does not qualify this parser.

## Increment 2: bounded rich ODT import

Implemented entry points:

- `Future<WmlDocument> OdtDocumentReader.readBytes(Uint8List bytes,
  {OdfZoteroLimits limits = const OdfZoteroLimits()})` performs the conversion.
- `OfficeIsolateOpen.word` dispatches supported ODT by package bytes and lays
  out the result through the existing Word open path.
- `WordEditorController.loadBytesAsync` publishes a successful result only
  while the original document, revision and open request remain current.
  An import failure, intervening edit/open or disposal leaves the active
  document untouched. Synchronous `loadBytes` explicitly directs ODT callers
  to the asynchronous API.
- Studio Open accepts `.odt`, clears the original save path after successful
  import and proposes a `.docx` filename.
  The first save chooses a DOCX destination instead of overwriting the ODT.

The reader validates an immutable source copy with the existing inventory, then
reconstructs native paragraphs, runs, note stories and table-cell owners. Field
identity comes from exact XML endpoints and ownership, never a visible-text
search. Its rich decoder records its own UTF-16 mark positions so whitespace
around visible note anchors stays on the correct side. Source endpoint order
distinguishes a citation immediately after a note from a field containing that
note, even when their text offsets coincide. Native note markers are populated
after source-range reconstruction, preserving editor and DOCX offsets.

| Content | Implemented envelope |
| --- | --- |
| Paragraphs and runs | Paragraphs, unnumbered headings, literal/explicit spaces, tabs, line breaks, supported character formatting and absolute external hyperlinks. Named, default and automatic style inheritance is resolved into model properties. |
| Formatting and page layout | Supported fonts, exact half-point sizes, bold/italic, underline/strike, small capitals, semantic superscript/subscript, colors, language, explicit paragraph direction/alignment, indents, spacing and supported tab stops. One compatible page layout may supply page size, margins and equal-width columns. Used unsupported properties reject the import. |
| Zotero fields | Canonical citation ReferenceMarks and bibliography ReferenceMarks/TextSections become active native fields. Multi-item options, unknown citation/bibliography metadata, rich cache, empty bibliography paragraphs and distinct adjacent/identical-looking fields survive DOCX reopening. |
| Authored notes | Footnotes/endnotes with supported blocks, continuous document-wide automatic decimal or lower/upper Roman numbering with independent starts from 1 to 32,768 and live body anchors; citations retain their actual note story. Roman ordinals are limited to 1–3,999. Custom labels, alphabetic formats, restarts, unsupported styles, nested notes and citations enclosing note anchors are refused. |
| Tables | Rectangular tables with bounded horizontal/vertical merges and explicit covered cells, nested up to eight levels; supported widths/alignment, row minimum height/keep behavior, inherited shading and uniform effective padding. Citations retain their originating cell. Hidden covered content, conflicting effective shading/padding, asymmetric or per-cell margins, repeated rows/cells and ambiguous coverage refuse. Increments 4 and 8 define the merge and padding boundaries. |
| Lists | Simple decimal or supported depth-specific bullets, up to nine levels, explicit starts/restarts and multiple paragraphs per item. Independent sequences, nested continuations and source paragraph margins are retained. Continuation references/consecutive numbering, bullet affixes, conflicting first-line geometry and tables inside list items are refused. |
| Inline pictures | Embedded static PNG and upright RGB/YCbCr JPEG in character-anchored frames; original bytes, physical dimensions, title/description, supported run properties and ordinary hyperlinks. Pictures own one native character; adjacent Zotero ranges retain exact offsets. The picture continuation below defines the bounds. |
| Preferences and metadata | Explicit `WordZoteroDocumentData.fromOdt` converts valid `ReferenceMark` storage to native `Field` after reconstruction; ordinary Word/HTTP callbacks remain strict. Style/locale/note mode and unknown XML/JSON preferences survive. Standard document properties are mapped; the exact original `meta.xml`, including unrelated/future properties, is archived in DOCX custom XML. |

The import is all-or-nothing. Invalid/ambiguous marks, crossed owners, protected
or linked sections, ordinary unsupported sections, bookmarks, unsupported drawings,
annotations, revisions, embedded objects, unsupported used styles and resource
exhaustion refuse before publication. Relative/internal hyperlinks and genuinely
different visited-link formatting on authored text require further ownership/
formatting support. The equivalent-style continuation below permits different
names only when supported formatting and inheritance state match. A citation
whose cached runs contain a hyperlink also remains outside the native editable
field contract; ordinary external hyperlinks outside citations are preserved.
Unused style
definitions do not expand the accepted content envelope. The inventory's shared
package/XML/text/field bounds remain in force; the rich reader adds explicit
table, cell, list, note and style-definition limits. Script materialization also
has a shared 100,000-run limit, including alternating-script text across stories.

The original ODT bytes remain unchanged. This conversion preserves supported
content in the Word model; the archived metadata is not a lossless copy of the
whole source package and is never consulted by ordinary Zotero callbacks.
Save the result as DOCX to retain active fields and preferences. Ordinary ODT
export keeps its established cached-result behavior; native editable ODT output
needs its own implementation and qualification.

Local tests cover repeated DOCX saves, exact rich ownership, preference
normalization, edit/unlink, a staged citation/bibliography refresh transaction,
and inline/footnote/endnote conversion. Loader, controller and Studio checks
cover dispatch and publication/save routing. The current validation record
retains exact commands and totals; these synthetic checks do not establish an
installed Word, LibreOffice or Zotero session.

The original rich-import increment refused the untouched LibreOfficeDev 26.8
sample at `fo:hyphenation-ladder-count`. Increment 3 below resolves the complete
style envelope needed by that exact file; the historical record remains intact.

## Increment 3: retained LibreOffice style qualification

The original `native-prose.odt` is retained byte-for-byte with SHA-256
`9fd4e0d23bf9cd2be0248bd5e9cfb496dfe512ec1226c456f324f2171705e1bd`.
It was produced by LibreOfficeDev 26.8.0.0.alpha0 at source commit
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. It contains Latin 11-point and
Arabic 10-point text, bold, italic and supplementary Unicode. Its Asian font
and language slots are separate from the current source text.

Text styles resolve normal, complex-script and Asian settings independently
through inheritance, including relative sizes against the corresponding parent
slot. Current text is materialized into native runs when the effective font,
size, weight, italic, language or proofing behavior requires separate routing.
Unicode code points, combining marks, hyperlink ranges and field UTF-16 offsets
are preserved. Imported script slots survive DOCX serialization; ignorable
provenance confines later scalar-edit synchronization to those imported
projections. Ordinary DOCX properties retain their independent sparse slots.

Supported LibreOffice defaults are checked after inheritance. Automatic color,
opacity and hyphenation must resolve to supported effective values. Disabled
page grids, empty header/footer style containers, no-fill drawing-page styles,
zero gutter and an unused footnote separator can be accepted. Unknown or foreign
properties still refuse. Content-sensitive paragraph rules require that the
current text and resolved languages do not activate unrepresented Asian
spacing, hanging punctuation or line-breaking behavior. Unknown break locales
refuse conservatively. A nonstandard default tab interval with actual tabs,
an active page grid or an unsupported active separator also refuses. The later
active-separator increment below admits explicitly modeled solid/hidden rules.

The retained fixture checks exact text/style and native DOCX properties over
repeated saves. A separately labeled synthetic extension adds canonical
citations, a multi-paragraph bibliography and preferences without changing its
style envelope. It checks staged refresh, field editing, rich cache, unknown
metadata, original `meta.xml` bytes and repeated reopen. This does not claim
that the original converter file contained Zotero fields or that an installed
Zotero plugin produced the synthetic extension.

This is conversion of supported current content into the Word model. Dormant
ODF typography settings are not retained as a general live ODF style engine for
future typing or Zotero refresh. The qualified artifact still saves as DOCX;
native editable ODT output was still open at that checkpoint. The separate
[native-output continuation](native-odt-output.md) now implements explicit copy
export; complete release-host behavior remains open.
See the [current work record](../../validation/zotero-libreoffice-styles-20261121/README.md)
for exact executed checks and the pinned-source typography rationale.

## Increment 4: bounded native merged-table input

The importer accepts column spans from 1 to 32 and row spans from 1 to 256,
within the actual rectangular table. Each logical covered position must have
its own `table:covered-table-cell`. It validates the source occupancy grid
before parsing rich origin content. Native `gridSpan` and vertical
restart/continuation cells retain the existing Word geometry and logical
addressing model; continuations are empty and never duplicate source citations.

Column widths are summed for each native merged cell. Existing table/row style
handling remains in force. Supported cell backgrounds resolve through
inheritance, including default styles. A covered cell without an effective fill
declaration is inert; an effective fill must match its originating cell.
Unsupported properties and conflicting backgrounds, including a distinct
transparent override, refuse the import.

ODF permits stored content inside covered cells. This bounded conversion
refuses all child elements and non-XML whitespace there rather than discarding
hidden content. Missing, orphaned or overlapping covered positions, out-of-grid
spans, repeated row/cell owners and invalid span syntax also refuse atomically.
Span syntax accepts decimal positive integers with optional plus signs and XML
whitespace; hexadecimal lookalikes and nonbreaking-space padding refuse.

The existing eight-level/64-table bound remains. All origins, generated
vertical continuations and nested cells share the 4,096-native-cell limit.
Generated empty cell paragraphs share `maxParagraphs` with source paragraphs.
Covered horizontal positions do not create independent Word cells or fields.

The [work record](../../validation/zotero-odt-merged-tables-20261121/README.md)
contains source-review findings and the original execution-blocked scope.
The [editable-output continuation](../../validation/zotero-editable-odt-20261121/README.md)
subsequently executes the pending formatter, analyzer and engine/editor checks
with the genuine pinned SDK. Those new results are separately attributed and
do not establish broad real LibreOffice table acceptance.

Primary format contract: OASIS ODF 1.3 Part 3
[section 9.1.5 and span attributes 19.680/19.682](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html).

## Increment 5: bounded inline pictures

The [picture continuation](../../validation/zotero-odt-images-20261121/README.md)
extends the reader to complete `draw:frame` elements explicitly anchored
`as-char`, each containing one embedded `draw:image`. Frame names, `svg:title`,
`svg:desc`, native physical dimensions, supported text-span properties and
ordinary image hyperlinks become independently owned native picture runs.
No file or network retrieval occurs. Package paths must resolve inside
`Pictures/` without traversal, external authority or ambiguous separators.

The read-only inventory remains conservative about drawings. Only findings at
the exact frame/image paths that the rich reader fully validates and consumes
may be discharged. Unsupported drawing stories and descendants remain errors.
Rich field anchors include the picture's one U+FFFC position; source order
distinguishes adjacent fields from fields enclosing a picture. Pictures inside
citation or bibliography caches refuse, including otherwise empty ranges.

The complete document shares the existing note-image decoder's limits: 32
pictures, 4 MiB total encoded raster bytes, 8192 pixels per dimension, 16 Mi
pixels per picture, 32 Mi pixels in total, 32 MiB PNG scanline expansion per
picture and 64 MiB total decoded-image budget. Displayed dimensions must be
between 1 and 4000 points. The reader validates actual raster streams and
preserves accepted bytes; filename extensions do not select the decoder.
Animated PNG, SVG, external images, unsupported JPEG orientation/color modes,
OLE, text boxes, alternative image representations and active image
transformations retain explicit refusals.

Effective picture styling is checked after inheritance. Only supported or
inactive properties under the validated inline-bitmap content model can pass;
unknown or active crop, color, opacity, border, shadow and transformation
settings refuse. Visited-link glyph styling can be inactive for a link whose
entire content is validated pictures; mixed or authored text links keep their
existing guard. This does not implement a general ODF drawing/style engine.

The matching explicit ODT output preserves picture metadata and emits one
frame without duplicating the native object placeholder as literal text. The
picture record separates local edit/save/undo tests from untouched output of
the identified LibreOffice converter and from installed-plugin acceptance.

## Increment 6: native reopening after LibreOffice saves

The reader accepts the ordinary section style LibreOffice assigns to a native
Zotero bibliography. It resolves section-family defaults and parents before
qualifying a single column, zero margins, transparent background and inactive
protection/editing flags. Rich entries and empty bibliography paragraphs retain
their exact ownership. Active section geometry, protected/hidden/linked content,
unknown properties and malformed inherited styles still refuse. Unused sequence
declarations are checked for valid names, outline-level syntax and a single
Unicode separator; their authored content and active sequence fields refuse.

LibreOffice stores the note configuration's starting value as a zero-based
offset, unlike the normative ODF initial-number description. An unambiguous
stock LibreOffice/LibreOfficeDev generator with a complete project revision
qualifies that convention. Offsets from 0 to 32,767 require exact visible
labels; the numbering continuation admits decimal and lower/upper Roman
formats. The exact generator `CrispOffice Zotero ODT note-offsets/1` declares the
same offset encoding for Quds editable exports without enabling LibreOffice
defaults or style quirks. It requires explicit per-class configurations, formats
and start values. Independent footnote/endnote sequences and their native
`numStart` settings survive DOCX conversion. Unknown producers retain the
normative initial-number convention; recognized malformed or ambiguous offset
declarations are refused. Non-one literal starts also require exact nonempty
cached labels. Numbering is never inferred from those labels.
Alphabetic/other formats, restarts, custom labels and unsupported note styling
remain refused. A present generic configuration must declare its numbering
format. Qualified LibreOffice omission defaults require matching cached labels;
Quds does not infer a format from the display text.

Configured note-marker and main-flow anchor styles are admitted only when their
effective default/parent chain specifies exactly superscript at 65 percent and
adds no unrepresented formatting. Bare consumer-selected superscript, 58-percent
scaling and custom marker fonts/colors remain refused. An endnote page master
must resolve to the same supported geometry as every used body master; it cannot
silently replace a different note-page layout. The explicit writer declares
these native styles and the final section's regular master before a host save.
Configured note paragraph styles remain outside the editing envelope.

Optional `text:use-soft-page-breaks` flags and empty cached soft-page markers are
validated and recomputed by native layout. Authored hard page breaks retain
their distinct paragraph/run properties; reexport does not copy stale hints.

Known separating/collapsing table border-model defaults are inert for
borderless tables. Increment 8 adds bounded uniform padding; the solid-border
continuation below extends visible input with an explicit collapsing model.
Editable export now pairs absolute widths with physical left/center/right
alignment. The earlier `margins` alignment expanded tables in LibreOffice and
converted their columns to unsupported relative-only widths. Historical files
from that route remain explicit failures; regenerated output has its own
retained qualification.

At this historical checkpoint, actual LibreOffice footnote separator geometry
was outside the native model. The active-separator increment below extends it.
Endnote-only and table-only files have separate acceptance scopes. The
[work record](../../validation/zotero-odt-roundtrip-20261121/README.md) retains
unmodified converter files, controlled native field updates, repeat-save
checks, source manifests and the exact remaining limits.

## Increment 7: semantic uppercase text

Supported `fo:text-transform="uppercase"` maps to native display-only capitals.
The original Unicode text, citation caches, metadata and UTF-16 field positions
remain unchanged, including characters whose displayed uppercase form expands.
Explicit `none` overrides inherited capitals; subsequent styles can enable it
again. Latin, complex-script and Asian formatting retain their separate slots.
The native renderer and repeated ODT/DOCX saves use the same semantic property.

Lowercase and capitalization transforms remain unsupported. A simultaneous
effective non-default text transform and font variant has undefined behavior in
[ODF 1.4 section 20.227](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.html),
so uppercase combined with small capitals refuses after inheritance. A child
style can resolve that combination with explicit `normal` or `none` before use.
The [combined work record](../../validation/zotero-roundtrip-complete-20261121/README.md)
distinguishes native regression tests, actual converter saves and remaining
installed-plugin acceptance.

## Increment 8: uniform table padding and native margin layout

The reader resolves `fo:padding` and its four side properties through the
table-cell family default, named parents and selected cell style. Within each
layer, the shorthand sets all four sides before explicit side properties
override them, regardless of XML attribute order. A child shorthand therefore
resets inherited side values. The effective result must be uniform on all four
sides and across all visible originating cells of one table. An absent effective
declaration means zero. Nested tables resolve independently rather than
inheriting padding from their containing table.

The accepted lengths are finite, nonnegative absolute values in `pt`, `pc`,
`in`, `cm` or `mm`. Percentages, CSS length lists, `auto`, literal `inherit`,
asymmetric sides and differing visible-cell margins refuse. The existing
row/column `table:default-cell-style-name` forms remain unsupported. A covered
cell without any effective padding declaration adds no override; authored or
inherited padding must agree with its merged origin. Border declarations with
the value `none` are accepted; the solid-border continuation below extends the
earlier visible-border boundary. Hidden covered-cell content remains outside
the contract.

The native scalar margin is bounded by the DOCX storage limit of 32,767
twentieths of a point (1,638.35 pt). Padding must leave positive content width in
each cell, using the total width of its merged span. Explicit editable ODT
output retains the uniform margin on cell styles and checks emitted cell
geometry after rounding. ODT output uses two decimal places in points; later
DOCX saves round margins to twentieths of a point (0.05 pt). The supported
round trip therefore permits format precision changes and does not promise
exact geometry for arbitrary input lengths.

Native measurement, wrapping, row heights, pagination and ruler insets now use
each table's modeled margin, including zero. Nested picture fitting accounts
for the sum of enclosing margins, including temporary tall-row layout and
authored notes. A table may be scaled to its page or containing cell; layout
refuses a final scaled cell width that leaves no positive content space. This
can refuse extreme geometry that fit at its original source width.

The [work record](../../validation/zotero-table-layout-20261121/README.md)
separates local inheritance/layout/lifecycle regressions and identified
LibreOffice converter evidence from installed Zotero/Word/supported-release
LibreOffice acceptance. Ordinary ODT export retains its existing formatting and
cached-result contract. Source ODT bytes remain unchanged on success or refusal.

Primary semantics: [ODF 1.3 Part 3, table-cell styles and padding](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html)
and [XSL 1.0 section 5.2, shorthand precedence](https://www.w3.org/TR/2001/REC-xsl-20011015/slice5.html#refine-shorthand).

## Increment 9: active footnote separators

`WmlDocument.footnoteSeparator` represents independent before/after gaps, nominal
line thickness, a fraction of body width, physical left/center/right alignment,
RGB color and solid/hidden line style. The native layout reserves the complete
sum of both gaps and nominal thickness on every page with footnote content,
including continuation pages. Hidden and zero-width lines reserve their
thickness while drawing no rule, matching the identified Writer behavior.
Pages without footnotes reserve no space. Supported dormant geometry survives
reopening so removing the final note does not erase its settings.

The reader requires explicit dimensions, relative width, color and line style;
only physical left alignment has an ODF default here. For an unambiguous stock
LibreOffice/LibreOfficeDev generator declaration, omitted width/before/after
lengths mean zero, following the retained converter outputs. Other omitted
producer-dependent attributes refuse when active. Explicit malformed values
always refuse. Active dashed/dotted rules, incompatible used master settings
and geometry consuming the body area remain outside the envelope. Unsupported
dormant presets keep the preceding validation-only behavior.

Native ODT output writes all supported geometry explicitly. ODT lengths use
two decimal places in points; relative width uses six decimal places in
percent. DOCX native persistence uses twip gaps/indents and eighth-point border
thickness, with uniform stored body widths and nonzero thickness from 0.25 to
12 points (hidden zero-thickness rules are also represented). Native DOCX
reopening accepts only the full canonical special-note shape and matching
settings references. Unsupported imported separator XML remains opaque.

The [work record](../../validation/zotero-footnote-separators-20261121/README.md)
retains three actual Zotero-footnote converter routes, zero-gap/hidden-line
probes, controlled native refresh, repeated saves and the failed custom-DOCX
route. LibreOffice normalizes custom DOCX separator paragraphs; native DOCX
persistence does not claim that route preserves their appearance. Installed
Word and actual Zotero plugin sessions remain separate acceptance gates.

<a id="increment-8-installed-host-acceptance"></a>

## Solid-border continuation: editable research tables

Visible cell borders require an explicitly resolved `table:border-model="collapsing"`.
All visible edges in one table must use one solid opaque `#RRGGBB` stroke with
a width from 0.25 to 12 pt in exact eighth-point steps. The parser accepts the
supported absolute length units; widths that would change when saved as DOCX
refuse. Named colors, alpha, dashed/double lines, mixed widths/colors and visible
separating or unspecified models remain unsupported.

The cell-family default, parent styles and selected cell style are resolved in
order. At each layer, `fo:border` resets all four sides before explicit side
properties override them, independent of XML attribute order. `none` clears an
inherited edge. Covered cells may omit a border declaration, but any effective
declared side must agree with its merged owner. No covered content or citation
is duplicated. Each nested table resolves its own stroke. Explicit native masks
keep absent/disabled sides from inheriting the stored table stroke on DOCX save.

Uniform cell padding retains the preceding contract and is stored numerically
unchanged. Actual LibreOffice controls show that uniform halfstroke padding
compensation would introduce save-cycle drift. Table-position and vertical
layout differences remain separately qualified; negative table margins are not
accepted merely because a border is supported.

Table writing-mode properties remain outside the bounded ODT reader. Editable
ODT output likewise refuses right-to-left table column order before returning
bytes, with the source document and active fields unchanged. Supported
right-to-left paragraph direction inside a left-to-right table is a separate
capability and keeps its existing mapping.

The [work record](../../validation/zotero-table-borders-20261122/README.md)
includes unchanged retained Writer DOCX cell fixtures, native Refresh and
repeated editable ODT/DOCX checks. The DOCX source now has an independent
four-side assertion: `start`/`end` take precedence over legacy `left`/`right`,
effective table direction is resolved before mapping to physical sides, and
DOCX output maps those sides back consistently. This fixes the source alias
loss discovered during converter qualification; it does not extend the native
common-stroke model to arbitrary DOCX per-cell strokes or styles.

Three cases pass six actual LibreOffice saves and twelve paired native
DOCX/ODT cycles in the identified LibreOfficeDev build, with all 376 captured
engine inputs unchanged. They cover the original black-bordered DOCX cell,
colored explicit-off sides and a colored vertical merge. Native tests, actual
converter evidence and installed Word/LibreOffice Zotero-plugin acceptance
remain separate, and earlier failed evidence is retained.

## Equivalent hyperlink style continuation

Ordinary hyperlinks may use different unvisited and visited style names when
both resolve in the same inherited context to equivalent supported formatting
and inheritance state. Compare all native script projections and retained
script XML, plus raw nullable complex/Asian slots and explicit-property state;
equal current glyph appearance alone is insufficient for nested spans.

The [continuation record](../../validation/zotero-link-equivalence-20261122/README.md)
contains 20 authored regression cases and independent source-review findings.
Runtime tests, analyzer/formatter checks and converter/plugin acceptance remain
pending. Actual state-dependent appearance, missing definitions and child-only
masking of unequal parent styles stay refused. Existing glyph-free image-link
handling is preserved.

## Increment 10: installed-host acceptance

Run an actual current Zotero session with identified Word and LibreOffice
versions and synthetic library data. Exercise native-file input separately
from the existing transfer-carrier route, in both directions. Preserve
source/application versions, original and returned files, citation identities,
preferences and observed refresh results.

The earlier converter finding remains open: on the recorded LibreOffice
development build, DOCX to ODT to DOCX changed a continued list from
`4., 5.` to `4., 1.`. Keep that failing route visible until an identified
release and actual fixture demonstrate a resolution. Do not mask distinct
numbering instances with a reader heuristic.

Apache OpenOffice is a separate legacy target. Zotero's current
[troubleshooting guidance](https://www.zotero.org/support/word_processor_plugin_troubleshooting)
does not support it; any historical compatibility claim needs exact host,
Zotero and plugin versions. Current LibreOffice acceptance cannot establish it.

## Continuing after bounded rich import

The [converter continuation](../../validation/zotero-converter-parity-20261122/README.md)
admits the exact inert Writer outline shape observed in the retained
paragraph/color files: empty `style:num-format`, optional matching `%N%`
`loext:num-list-format`, and a single label-alignment property block with
`text:label-followed-by="nothing"` and no positioning. Affixes, numbered
formats, nonmatching templates, unknown properties and authored style text
remain refused. Paragraph heading level, direction and indentation continue
to come from their existing native mappings.

It also accepts exact `loext:char-shading-value="0"` only when the same
text-property declaration has an explicit supported `fo:background-color`.
This preserves a clear pattern's RGB background or transparent reset. The
compound Writer brush may reset inherited color when shading is declared
alone; this is an inference from the importer, and that wider form remains
refused pending converter qualification.
The original six saved ODTs are tested through native Refresh, DOCX and
editable ODT reopening with their unchanged semantic expectations. General
numbered outlines, patterned shading and installed-plugin parity are outside
this bounded increment.

1. Refresh current main and recent branch/PR heads, preserving incoming history.
   The earlier two pending heads and the subsequently discovered Word text
   branch are integrated by this continuation; keep their recorded cutoffs.
2. Expand the documented rich-document envelope from additional retained real
   files. The exact prose fixture and supported script/default mapping above
   provide a baseline. Complete the cross-application separator acceptance
   above, preserving the known custom-DOCX converter limitation. Extend active
   Asian typography, additional drawings and further note/list configurations,
   and qualify the explicit native ODT output with matching ownership, rendering
   and persistence checks; keep remaining refusals visible.
3. Save each working increment on a remote branch with an expected-head lease.
4. Review the integrated diff, rerun checks affected by incoming changes, then
   merge the qualified implementation to current remote main and verify the
   resulting commit/tree and branch ancestry.
5. Do not query or wait on GitHub Actions as the acceptance path. Preserve
   concrete local results and state any installed-host limits separately.

Increment 1 remains a read-only capability. Increments 2 through 9 convert a bounded
native ODT subset into an editable Word document that saves as DOCX. These
increments do not establish complete plugin parity or installed-host acceptance
for Zotero, Word, LibreOffice or legacy Apache OpenOffice. Ordinary ODT export
retains its cached Zotero citation behavior; the picture continuation also fixes
its placeholder emission, accessible metadata, image-run styling and drawing
names.
