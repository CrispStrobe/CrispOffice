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

Explicit editable ODT export refuses effective absolute raised/lowered baseline
positions on text, paragraph marks and note markers, including inherited values.
An explicit zero override and supported semantic superscript/subscript remain
accepted. This preserves the boundary introduced by native Word `Font.Position`
support instead of silently omitting that formatting during conversion.

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
padding must agree with its merged origin. Asymmetric/per-cell padding and
unsupported row/column default-cell styles remain outside the reader envelope.
The solid-border continuation below extends the earlier borderless boundary.
The [table-layout record](../../validation/zotero-table-layout-20261121/README.md)
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

Editable output preserves a table's effective borders using one solid opaque
RGB stroke with an exact eighth-point width from 0.25 to 12 pt. Each cell side
can inherit the native table default or explicitly enable/disable its border.
The output emits the actual stroke and an explicit collapsing border model.
Borderless cells retain the distinction between an absent edge declaration and
an explicit `none`, including when cell styles are reused. Nested tables use
independent stroke plans. Vertical continuation overrides must agree with the
visible merged owner; the exporter refuses a conflicting mask before returning
bytes. The original document and active citation data remain unchanged.

Uniform padding is emitted unchanged, without adding or subtracting border
width. Output checks the native modeled stroke and side ownership. Unsupported
width/color values, richer table indentation and right-to-left table column
order remain outside this contract; input rejects mixed ODT strokes and visible
separating models. Arbitrary per-cell stroke properties or styles in external
DOCX remain unqualified by the native common-stroke model.

DOCX source cell borders recognize modern `start`/`end` names with precedence
over legacy `left`/`right`, independent of XML order. Both forms map to physical
left/right sides after the default/named table style and direct `bidiVisual`
overrides resolve, including explicit false overriding inherited true. Native
DOCX saving applies the inverse mapping. An independent comparison with the
source XML now verifies all four borders in the retained Writer DOCX cell
fixture, catching the alias loss that a native snapshot alone had missed.

Editable ODT refuses an effective right-to-left table before returning bytes,
leaving the original model and active citations unchanged. It does not yet
represent reversed table column order. Supported right-to-left paragraphs
inside left-to-right tables are distinct and keep their existing direction
mapping. Ordinary cached-result ODT output keeps its previous contract.

The [border record](../../validation/zotero-table-borders-20261122/README.md)
records three passing cases through six actual LibreOffice saves and twelve
paired native DOCX/ODT cycles, with all 376 captured engine inputs unchanged.
The identified LibreOfficeDev run covers the original black-bordered cell,
colored disabled sides and a colored vertical merge. The record separates
native persistence, actual converter controls and installed-plugin acceptance;
it does not establish identical pagination in every application.

Cited note classes support continuous automatic decimal, lower-Roman or
upper-Roman numbering with an initial number from 1 to 32,768, including Word's
default Roman endnotes.
All emitted notes in a cited class, including uncited notes, must have compatible
effective native settings and exact ordinals. Footnotes and endnotes remain
independent. The exporter writes one explicit ODF format per class. For
start-one sequences it omits the start value so the normative initial-number
and LibreOffice zero-offset conventions agree. When a cited class starts above
one, it declares the exact generator `CrispOffice Zotero ODT note-offsets/1`
and writes explicit zero-based offsets for every emitted note class. Quds
accepts that versioned convention independently of LibreOffice's unrelated
style/default handling. Generic ODF producers retain literal initial-number
semantics; recognized malformed or ambiguous offset declarations refuse.
Roman ordinals are limited to 1–3,999 and decimal ordinals to 65,535. Custom labels, mixed
formats, unsupported settings and section/page restarts refuse before bytes
are returned. Alphabetic numbering remains deferred because ODF and
LibreOffice disagree on letter synchronization.

The reader stores the accepted formats and starts explicitly in native section
properties so DOCX reopening preserves them. Offset conventions and non-one
literal starts require a nonempty, exactly matching cached label for every
note. Zotero's numeric note indexes remain physical document order. This uses
genuine automatic note numbering;
the ordinary writer retains its existing fixed-label contract. See the
[numbering and unlink work record](../../validation/zotero-parity-next-20261122/README.md)
for source-bound local and converter qualification; the preceding
[Roman increment](../../validation/zotero-note-numbering-20261122/README.md)
retains its own historical results.

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

Effective nonzero absolute font baseline positions also refuse this explicit
export. Native Word `Font.Position` and DOCX `w:position` have no qualified ODT
mapping yet. Preflight checks visible runs, paragraph marks and note markers,
including resolved inherited positions, before returning bytes. Effective zero
overrides remain supported, as do the separate superscript/subscript styles.
Refusal leaves the document and its native package unchanged.

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

The [active-separator increment](../../validation/zotero-footnote-separators-20261121/README.md)
adds explicit `style:footnote-sep` output for modeled solid/hidden rules. Both
gaps, nominal thickness, physical alignment, relative width and RGB color are
emitted even when a value is zero. All native ODT writers preserve this modeled
page geometry; ordinary output continues to export cached citation text.
Lengths round to 0.01 points, relative width to six decimal places in percent.
Active geometry is checked against the emitted page dimensions before bytes
are returned, including exhaustion introduced by rounding. This is one uniform
document-wide separator, including continuation pages, rather than arbitrary
special-note content.

Direct LibreOffice ODT saves and subsequent native refresh/save/reopen are
qualified separately from native DOCX persistence. The actual converter
normalizes custom DOCX separator paragraphs; that route remains a recorded
failure, and installed Word rendering is unqualified. Keep the original ODT
and use explicit editable ODT output when exchanging this supported geometry
with the qualified LibreOffice route.

Use installed Zotero with Word and supported LibreOffice release versions to
refresh, change styles, edit citations/bibliographies and repeat saves on these
fixtures. Then qualify Word transfer and additional native documents, especially
notes with richer numbering, fields in note tables, additional image behavior
and styles beyond the current reader. Legacy Apache OpenOffice requires its
own identified versions and acceptance evidence.

The native round-trip continuation also opens returned LibreOffice files through
the Quds reader rather than checking their metadata inventory alone. Inert
bibliography section styles and the qualified decimal note-offset convention
are now represented, and the later active-separator increment extends the
supported note geometry. Converter acceptance does not expand the ordinary writer's
general document-formatting contract.

For native editable notes, the writer declares a 65-percent superscript style
for both the main-flow anchor and the number inside the note. Endnotes select
the final section's regular page master, avoiding a host-selected default with
different margins. Reopening validates the full effective marker style and
requires compatible used page geometry. Arbitrary marker formatting, differing
note-page layouts and configured note paragraph styles remain unsupported.
