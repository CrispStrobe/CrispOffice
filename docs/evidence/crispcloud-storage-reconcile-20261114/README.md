# CrispCloud source reconciliation — 14 November 2026

This companion branch combines canonical main at `4bdb70c9d86fd1ee09ed99d3114b178e965cfa01`
with the worksheet continuation at `e3e3255425c408098456f1024cd26225b93d1bf0`.
Both parents remain in the merge history. Main includes the notes/sorting branch
through `cc8ff1ed4dfbf170012c43704d5730490275a2c4`.

The two CrispCloud branches pinned different canonical controller revisions.
Their only source conflict is the grid-history snapshot: the worksheet
continuation now preserves cell object identity for every grid operation and
also retains empty rows. This is the stronger shared representation. Sorting
keeps its owning-sheet, dirty-state, pending-edit and undo/redo behavior while
using that representation, without the older optional identity-preservation
flag. Worksheet direction, frozen panes, grid history and canonical formatting
commands remain intact. All tests and historical evidence from both parents
are retained.

This checkpoint supplies one canonical source for CrispCloud's guarded sync.
It adds no dependency or public API and does not alter main. Focused acceptance
for the combined source is recorded in the subsequent validation receipt;
historical parent results are not relabeled as combined-source passes.
