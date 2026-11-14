# Grid history: corrected negative control

Production source: `ec88aa0700eff40c22e873fa0c221f98f825f011`.
The controller is unchanged from the validated worksheet-view implementation.

All 14 new grid-history tests fail by the expected product assertions. There are
no compilation failures, and all 408 captured inputs stayed unchanged. These
cases exercise wrong-sheet restoration, selection-dependent redo, detached cell
edits, structural moves and deletion, modeled metadata, dependent formulas, and
direct/isolate saved values. The exact test source is retained in compressed form
and remains unchanged for positive validation.

The first attempt in `../phase-b-baseline/` contains ten valid product failures
and four test-helper failures: the helper compared newly constructed `SmlCellRef`
objects by identity before the structural history operation. The corrected
helper compares their row and column coordinates. This attempt reaches the
intended history assertions in all four structural cases. The original attempt
is retained unchanged, with the correction described in
`../phase-b-baseline-correction.json`.

`validation.json` binds the command, source commit, unchanged-input check and raw
log hash. The controller implementation is a subsequent change; this directory
does not claim a passing result for it.
