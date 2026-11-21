# Editable Zotero ODT output

`OdtDocumentWriter.writeEditableZoteroBytes(document)` creates a separate ODT
copy with native Zotero references. In Studio Word, choose **File → Export
Zotero ODT…**, or **Export Zotero ODT** on the File ribbon. The source document,
its normal DOCX save destination, dirty state and undo history remain intact.
Export needs no running Zotero instance or network connection; active fields
must already have valid document preferences.

This closes the native metadata output gap identified by the
[word-processor parity roadmap](word-processor-parity.md). The
[implementation and qualification record](../../validation/zotero-editable-odt-20261121/README.md)
contains exact local and converter evidence. Installed Zotero/LibreOffice and
Word plugin acceptance remains a separate requirement.

## API and compatibility

```dart
final odtBytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
```

The existing `OdtDocumentWriter.writeBytes(document)` API keeps its ordinary
cached-text export behavior. The explicit method validates ownership before
returning bytes. It throws when it cannot account for the Zotero data in the
document; it does not silently fall back to a flattened result.

Studio serializes a detached snapshot before asking for a destination. Cancelling
the picker leaves the document alone. The export adds `.odt` when necessary,
does not mark the source clean, and does not redirect its later normal save.
Edits made while the picker is open remain in the active document and do not
change the already serialized copy. Unsupported cases show the exporter reason.

## Native storage contract

The initial contract follows Zotero LibreOffice integration commit
[`0a31b434371eb21a1297c5bce8ca4978cb9ab425`](https://github.com/zotero/zotero-libreoffice-integration/commit/0a31b434371eb21a1297c5bce8ca4978cb9ab425),
including `ReferenceMark.java`, `Document.java` and `Properties.java`.

| Data | Export representation |
| --- | --- |
| Citation | Paired `text:reference-mark-start` / `text:reference-mark-end` at the exact native packet boundaries |
| Bibliography | One named `text:section` around the complete, exclusively owned entry paragraphs, including empty entries |
| Name | Canonical `ZOTERO_ITEM CSL_CITATION … RNDxxxxxxxxxx` or `ZOTERO_BIBL … CSL_BIBLIOGRAPHY RNDxxxxxxxxxx` |
| Identity | Fresh ten-character alphanumeric suffixes, checked for uniqueness within each export; citation IDs and payloads remain unchanged |
| Document preferences | `ZOTERO_PREF_1`, `ZOTERO_PREF_2`, … string properties in `meta.xml`; chunks contain at most 255 UTF-16 units and never split a surrogate pair |
| Storage preference | Explicit `WordZoteroDocumentData.toOdt` conversion to `ReferenceMark`; ordinary Word/HTTP callback guards stay unchanged |

Citation item order, locators, affixes, author suppression, source URIs, unknown
supported metadata, bibliography inclusion/exclusion data, style, language and
note preferences remain in their existing payloads. The visible cache retains
the modeled rich formatting. Small capitals, uppercase transformation and
complex-script font/emphasis slots are emitted by this explicit path as well.
Supported uppercase transformation also reopens natively without rewriting
source text. Other case transforms and uppercase combined with small capitals
remain outside the reader's envelope. See the
[native-input contract](native-odt-input.md#increment-7-semantic-uppercase-text).

## Ownership and supported content

The preflight traverses native structural owners and separately accounts for
every field start and end emitted by the writer. Identical visible citations
and copied complete payloads remain distinct fields. It does not infer an owner
from a text match.

Supported active fields are complete unlocked citation packets and whole
paragraph citations in body paragraphs, visible body table cells, and uniquely
anchored authored-note paragraphs. Bibliographies must own consecutive ordinary
paragraphs completely; heading/list entries and partial ranges refuse. Fields
in table cells must remain in one native cell owner.

The explicit writer retains valid body-table grid widths as absolute ODF widths.
It uses physical left, center or right alignment for those fixed widths; the
ODF `margins` value means fill the available width and overrides that geometry
in LibreOffice. Other alignments refuse this explicit path. The ordinary writer
retains its existing fill-width behavior. See the
[round-trip continuation](../../validation/zotero-odt-roundtrip-20261121/README.md)
for the actual converter reproduction and corrected table fixtures.
Intervening DOCX saves retain complete uniform table-cell margins, including
zero; partial/asymmetric/logical-edge source margins remain opaque and sparse.
The explicit ODT writer now emits each table's modeled uniform margin as
`fo:padding` on its cell styles. Nested tables keep independent margins, and
cell-style reuse accounts for padding. Native measurement, wrapping, row height,
pagination, picture fitting and ruler insets use the same modeled margin.
Bounded merged tables use explicit covered-cell positions. Empty native vertical
continuation paragraphs become empty ODF covered cells without duplicating their
origin's citation text. Existing cached-result export remains unchanged.

This supports one effective value on all four sides and across all visible
cells in each table. The native reader resolves family defaults and parent
styles before testing that uniformity; authored or inherited covered-cell
padding must agree with its merged origin. Asymmetric/per-cell padding,
unsupported row/column default-cell styles and visible ODT borders remain
outside that reader envelope. Border declarations with the value `none` are
accepted. The [table-layout record](../../validation/zotero-table-layout-20261121/README.md)
documents the delivered margin and padding scope.

Margins must be finite, nonnegative and at most 32,767 DOCX twentieths of a point
(1,638.35 pt). They must also leave positive content width in every emitted cell,
including merged spans and the effects of serialization rounding. ODT lengths
are emitted to two decimal places in points; DOCX margins round to twentieths
of a point (0.05 pt). These are bounded precision conversions, not an
exact-geometry guarantee across formats. Native layout may scale a table to its
page or enclosing cell and refuses a final width exhausted by the margins.
Ordinary `writeBytes` keeps its existing table-formatting and cached-result
contract; uniform-padding output is specific to the explicit editable path.

Cited notes require ordinary automatic decimal numbering. The exporter keeps
their native note ownership, emits automatic ODF note labels, and refuses
custom/Roman/restarted cases outside this initial contract. The native ODT reader
now records admitted decimal endnote numbering explicitly in the Word model so
DOCX reopening does not switch it to Word's Roman default.

The ordinary ODT writer's document-formatting envelope still applies. Editable
Zotero metadata does not establish arbitrary Word/ODF formatting fidelity.
For example, the ordinary writer flattens tables inside notes, so this explicit
path refuses active Zotero fields inside those tables. A file that preserves
native metadata may contain formatting outside Quds' bounded native ODT reader;
the tests distinguish metadata inventory from full editable reopening.

### Inline note and annotation pictures

The [picture continuation](../../validation/zotero-odt-images-20261121/README.md)
preserves bounded embedded inline PNG and upright RGB/YCbCr JPEG pictures
alongside active citations. Each picture is an independently owned canonical
one-character run. Its accepted raster bytes, physical size, image link,
accessible title/description and supported run styling survive the qualified
native ODT/DOCX paths. ODT dimensions are written to two decimal places; the
actual converter check permits at most 0.03 pt of size quantization. `svg:title`
and `svg:desc` carry the accessible metadata. Drawing-object names are unique
across stories: duplicate or empty names receive deterministic names without
mutating the source objects, and reopening adopts the assigned names. The writer
emits the picture frame once, without writing an extra literal U+FFFC placeholder
beside it.

The explicit exporter validates the complete document against the same raster
budgets as native picture input: at most 32 pictures and 4 MiB of raster bytes
in total, with the decoder's pixel and expansion limits. Shared visual owners,
noncanonical picture runs, unsupported stories and pictures in bibliography or
citation caches refuse. Cropping, rotation, color adjustments, transparency,
borders, shadows, flipping and unlocked aspect-ratio behavior are outside this
initial inline-picture contract. Ordinary cached-result export retains its
existing metadata behavior while receiving the picture placeholder, accessible
metadata, run-style and drawing-name fixes.

## Refusals and bounds

Export refuses incomplete, malformed, locked, nested or overlapping Zotero
packets; unsupported headers, footers, comments, controls and frames; hidden or
unreachable field owners; ambiguous/cyclic/shared model ownership; duplicate or
missing note anchors; and partial bibliography ownership. Pending tracked
changes and protected document states refuse. Prepared document-transfer
carriers must be imported before using this API.

Unclaimed instructions, native Zotero bookmarks and retained opaque XML are
examined as well as enumerated fields. Entity-encoded names cannot bypass that
check. The exporter refuses recognizable Zotero data it cannot preserve.
Metadata must contain valid XML characters and well-formed surrogate pairs.

The plan bounds fields at 10,000, paragraphs at 100,000, native story nesting at
64 levels, and aggregate native names/preferences at 16 MiB UTF-8. Preferences
retain their separate 256 Ki UTF-16 limit. Opaque metadata receives bounded
streaming inspection. These limits supplement the existing Word field codec and
ODT serializer rather than relaxing their limits.

## Qualification and next work

Automated checks cover independent citation ownership, simple/complex/whole
paragraph and empty packets, rich/empty bibliography entries, note numbering,
merged tables, repeated ODT/native/DOCX conversions, native refresh and unlink,
Unicode and extension metadata, refusal atomicity, source preservation, and
Studio export cancellation/save routing.
The [table-layout continuation](../../validation/zotero-table-layout-20261121/README.md)
adds uniform-padding inheritance/refusal checks, nested and merged table
lifecycles, native margin layout and separately identified converter evidence.
It does not establish complete Word/LibreOffice plugin parity.

`packages/quds_office_engine/tool/zotero/odt_export_acceptance.dart` creates two
synthetic documents and checks exact native inventory after an external ODT
save. The recorded LibreOfficeDev 26.8.0.0.alpha0 run preserved all seven field
records, preferences and structural ownership across both files. This is a real
file conversion result, not an installed Zotero plugin session or stable-release
compatibility claim.

The next dedicated note-formatting increment needs a native footnote-separator
model, matching pagination/rendering and interoperable DOCX/ODT mapping before
the reader can admit active LibreOffice separators. Retained opaque DOCX
separator definitions alone do not supply that geometry.

Use installed Zotero with Word and supported LibreOffice release versions to
refresh, change styles, edit citations/bibliographies and repeat saves on these
fixtures. Then qualify Word transfer and additional native documents, especially
notes with richer numbering, fields in note tables, additional image behavior
and styles beyond the current reader. Legacy Apache OpenOffice requires its
own identified versions and acceptance evidence.

The native round-trip continuation also opens returned LibreOffice files through
the Quds reader rather than checking their metadata inventory alone. Inert
bibliography section styles and the qualified decimal note-offset convention
are now represented, while used footnote separators retain their explicit
reader limitation. Converter acceptance does not expand the ordinary writer's
general document-formatting contract.

For native editable notes, the writer declares a 65-percent superscript style
for both the main-flow anchor and the number inside the note. Endnotes select
the final section's regular page master, avoiding a host-selected default with
different margins. Reopening validates the full effective marker style and
requires compatible used page geometry. Arbitrary marker formatting, differing
note-page layouts and configured note paragraph styles remain unsupported.
