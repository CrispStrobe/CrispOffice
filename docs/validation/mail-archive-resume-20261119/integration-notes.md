# Incoming source reconciliation decisions

The initial source at `596430dc` already contained main `caf378f4` and GUI
`2d7360a2`. Later preserved parents include VBA `f6b8638d` and GUI `8c6acd04`.
Further incoming fixes were integrated from VBA `61bb3ee4` and GUI `a2c144be`
(which includes `2dbd1c58`), preserving each original commit in the ancestry.

## Slide ink and rendering tests

Local qualification exposed two separate findings in the incoming dark-slide
test: a small-font raster assertion required too many fully opaque black pixels,
and DrawingML table-cell text colors were attached to the enclosing shape on
readback. The initial local correction routed cell ink to the active cell and
added three separate direct-XML/theme/PPTX-repeat regression cases. The newer
VBA contribution independently fixed the parser and added broader table-cell
regressions. Its parser version also retains the first explicit cell color and
was selected during reconciliation; the three local regression cases remain.

The final dark-slide test combines the two incoming test improvements. It keeps
VBA's fractional black coverage, pixel equality against unadapted authored ink,
wrong-light-ink and blank controls, and actual deserialized cell-color checks.
It also keeps GUI's contrast coverage on light/dark fills, authored-model checks
and independent checks of serialized XML text/fill colors. The obsolete GUI
comment treating the importer defect as still present is removed. The earlier
local tolerance adjustment is superseded by these stronger combined checks.

GUI ruler font selection/registration and all later Studio tab/header/footer
improvements are preserved. Local validation will qualify the combined source;
incoming historical reports are supporting evidence and are not fresh counts.

## Evidence whitespace

Three incoming raw captures (`before-source.diff`, `after-source.diff`, and
`incoming-context.diff`) contain a literal space on diff context blank lines.
Their bytes are preserved unchanged. The first preflight found the third capture
after formatting and analysis passed; no behavioral tests ran in that attempt.
The corrected whitespace command explicitly excludes only those three raw captures;
all product files and all other changed paths remain checked. This exception
does not alter formatting, analysis or behavioral test selection.
