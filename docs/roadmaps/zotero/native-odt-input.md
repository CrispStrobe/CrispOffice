# Native ODT Zotero input: implementation contract

Status: **Increment 1 implemented: bounded read-only inventory. Rich ODT import
and installed-host interoperability remain separate work.**

The public `OdfZotero.inspect` API and `tool/zotero/odt_inventory.dart` diagnostic
now implement the inventory below. The
[implementation and validation record](../../validation/zotero-odt-inventory-20261121/README.md)
identifies the reconciled source, remote checkpoints, executable checks and
remaining limits. The earlier execution-blocked checkpoint is preserved as
history; its lack of runtime qualification is not attributed to this increment.

Baseline: [`1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0`](https://github.com/CrispStrobe/quds_office_suite/commit/1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0).
The [continuation record](../../validation/zotero-native-odt-20261121/README.md)
records that checkpoint's frozen remote intake, two then-outstanding branch
heads and local execution blocker. Both heads were subsequently integrated
into main. This implementation advances the existing
[word-processor parity roadmap](word-processor-parity.md) without claiming
editable native ODT support.

## Finding: rich ODT input is a prerequisite

The current tree has a native ODT exporter and bounded ODF text extraction.
It does not have an ODT-to-`WmlDocument` reader. Adding reference-mark handling
to the text extractor alone would lose the formatting and structural ownership
needed by editable citations.

| Existing boundary | Contract to retain |
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
Each endpoint retains its part, story identity, structural owner chain,
paragraph path/index and UTF-16 offset. Deferred collapsed spaces are resolved
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

Preserve the original preference string and unrelated properties. A later
native-ODT import boundary may normalize `ReferenceMark` preferences only
after it has constructed the corresponding fields. Reuse the existing
256 KiB preference bound; do not weaken `WordZoteroDocumentData.toHttp`
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

After the inventory passes, introduce an explicit ODT document reader and
loader path. Define and test the first supported content envelope before
publishing an editable document. It needs sufficient paragraph/run formatting,
links, notes, lists, tables and resource ownership to avoid flattening protected
research content.

Construct native Word field ranges from validated inventory identities while
preserving paragraph and story order. Normalize document preferences at this
specific import boundary. Unsupported ranges or structures require an explicit
refusal or retained representation; do not silently discard citation metadata.

Qualify DOCX save/reopen and further Zotero operations after import, including
multi-item citations, notes, style conversion, bibliography refresh, manual
citation text, duplicate visible strings, adjacent fields and repeated saves.
Wire editor publication only through the existing detached staging,
stale-document guards and single undo/redo transaction.

## Increment 3: installed-host acceptance

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

## Continuing with rich import

1. Refresh current main and recent branch/PR heads, preserving incoming history.
   The earlier two pending heads and the subsequently discovered Word text
   branch are integrated by this continuation; keep their recorded cutoffs.
2. Begin Increment 2 with an explicit rich-document content envelope and
   rendering/persistence ownership. Use the inventory identities as evidence,
   not as a substitute for a rich ODT reader.
3. Save each working increment on a remote branch with an expected-head lease.
4. Review the integrated diff, rerun checks affected by incoming changes, then
   merge the qualified implementation to current remote main and verify the
   resulting commit/tree and branch ancestry.
5. Do not query or wait on GitHub Actions as the acceptance path. Preserve
   concrete local results and state any installed-host limits separately.

Increment 1 is a locally testable read-only capability. It does not establish
active native ODT editing, changed ordinary ODT export, or installed-host
acceptance for Zotero, Word, LibreOffice or legacy Apache OpenOffice.
