# Initial grid-history baseline attempt

This original attempt is retained without altering its input or log bytes.
Ten cases reach expected product failures. Four structural cases stop on a
test-helper mistake: separately constructed `SmlCellRef` objects were compared
by identity. This attempt is not a 14-case product-failure claim.

The helper was corrected to compare row and column coordinates. The unchanged
production controller then failed all 14 intended history assertions. See
`../phase-b-baseline-corrected/README.md` and
`../phase-b-baseline-correction.json` for that separate completed control.
