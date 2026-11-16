# Continuation checkpoint

The incoming integration is saved at `0d19b16e10c6bc8492f47880321df2d9f2561223`.
All 151 observed fork/upstream branch and PR heads are included. The only new
incoming source change is the ODS default page layout from PR #73. Its feature,
vendor and mainline revisions have identical patches and trees; the real Git
octopus merge completed without conflicts. See `incoming-inventory.json`.

The next checkpoint preserves the implementation and regression tests while
the pinned local Dart/Flutter runtime is being restored. At this checkpoint,
new tests and static analysis have **not yet been run**. A final report and
source-bound local receipts will supersede this pending-validation status.

The subsequent structural checkpoint also preserves aligned TrueType glyph
offsets, bounded composite processing, validation of malformed glyph records,
and retained font metrics/style metadata with recomputed subset coverage. It
includes the MIT FontTools notice for the numeric OS/2 range transcription.
Independent review fixes reject incompatible CID/subset pairings and preserve
simple-glyph validation; capacity tests exercise resource splitting and reuse.
Formatting has run, but test/analyzer qualification is still pending here.

The PDF work separates character codes from subset glyph IDs so two authored
Unicode scalars sharing an outline keep independent extraction/search mappings.
It adds a real CIDToGIDMap stream and CID-indexed widths, including a bounded
65,535-character resource encoding. Office exporters use this path; low-level
callers retain identity encoding unless they opt in and emit the new CIDs.

The updated strategy distinguishes current source from stale comparison reports
and records eligible native shaping options. This checkpoint adds no production
dependency or bundled font. Shared editor/headless shaping remains future work.

GitHub Actions are not queried, awaited, polled or rerun. Checkpoints use
`[skip ci]`; qualification is local.
