# Later-section column-boundary evidence

The production writer qualified here is `9b33bec05df4e08bde06c6768f1e6b5a4af59a1a`.
Subsequent changes to the two regression files and this evidence harness do not
change its product source. The final source bridge records those file hashes.

## Repaired behavior

The writer previously retained an empty source fragment before a leading hard
column break only in section zero. A later multi-column section could therefore
consume that authored break in its own page/section boundary. The fix checks the
actual section's column count and retains its source fragment.

The final two-file controls exercise all four section-break kinds both with and
without an explicit paragraph page break, plus the exact restored DOCX packet
containing two hard column breaks. Against an isolated incoming writer, nine
tests fail and twelve pass. Against the final writer, all twenty-one pass on
both the Dart VM and JavaScript/Node. Every run has zero skips and unchanged
source/test inputs. These are overlapping runs, not additive test totals.

## Independent consumers

`make_boundary_fixtures.dart` saves five authored models as direct ODT, native
WordSerializer DOCX references, and DOCX-imported ODT. Four models cover the
repaired later-section layouts. In all twelve resulting PDF variants, the
destination and both followers must occupy the right column on the expected
page, with the followers below the destination. Two followers prevent natural
section balancing from imitating the authored column break.

The fifth model is a bounded control for retained page-break precedence in an
ordinary paragraph. Its target stays at the left-column origin on page two in
all three variants. All text and its bookmark range survive, and both followers
remain on that page. LibreOffice balances the final ODT follower into the right
column while its native DOCX import keeps that follower left. This difference
predates the fix: both `content.xml` and `styles.xml` are byte-identical between
incoming and final writers for the direct and imported ODT cases. Five fully
equivalent native layouts are not claimed.

The accepted run additionally reopens all ten ODTs as DOCX, verifies exact
bookmark-selected text and source order, and validates forty package parts
against the unchanged official ODF 1.3 schemas. Its source, harness, executable,
lockfile and package-configuration snapshots remain unchanged.

Additional retained controls resolve the section/page interaction explicitly:

- All four later-section cases with `pageBreakBefore=true` also match native
  DOCX: twelve PDF variants retain the target and followers in the right column.
- The exact original raw DOCX regression packet places “Second section” in the
  right column of page two and “Continuation” in the left column of page three.
  Final ODT has that same sequence; the incoming writer incorrectly uses two
  pages. The original packet omits paper size, so LibreOffice chooses Letter
  while the engine chooses A4. Column origins are derived separately from each
  page's geometry; identical default paper dimensions are not claimed.

`audit_boundary_controls.py` verifies these additional observations from their
retained raw receipts. The native source document XML is identical in the exact
before/after comparison.

## Scope corrections and retained failures

The archive keeps the complete development sequence. An initial candidate also
split ordinary page-before paragraphs; native evidence rejected that extension,
and the production condition was narrowed. A restored test expectation still
coalesced a column break at a new section; the exact native source established
that this expectation was stale, so the test now checks the three-page sequence.

The first consumer attempt used custom 400 × 500 pt paper. LibreOffice normalized
only the native DOCX reference height to about 498.9 pt. The accepted fixtures
use standard Letter geometry, retaining the same strict 0.2 pt size and 0.4 pt
horizontal tolerances. The later overbroad fifth-case assertion about follower
balancing is retained as a failed attempt, alongside its original harness bytes.
Only the accepted, explicitly bounded assertions qualify the final product.

The recorded consumers are Dart 3.13.7, LibreOfficeDev 26.8.0.0.alpha0 at
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, and Poppler `pdftotext` 25.03.0.
These results establish behavior in those local consumers. They do not establish
live Microsoft Word acceptance or pixel-identical layout for all documents.

## Reproduction

Use the resolved validation workspace and the recorded SDK/schema files:

```sh
python3 verify_boundary_consumers.py \
  --repo /path/to/source \
  --workspace /path/to/resolved-validation-workspace \
  --dart /path/to/dart \
  --schemas /path/to/official-odf-schemas \
  --output /path/to/new-empty-output \
  --commit CURRENT_SOURCE_COMMIT

python3 audit_boundary_controls.py --evidence /path/to/extracted-field-review-evidence
```

The neighboring field-review archive/index retain the accepted receipts,
negative controls, additional native observations, exact test/writer inputs,
and rejected attempts. No GitHub Actions, check-run or CI-status endpoints were
queried or awaited.
