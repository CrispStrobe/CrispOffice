# Worksheet state and history continuation — 14 November 2026

Canonical baseline: `2d2a7be43e19b478c532025fe1f275ed7b00ef75`.
App baseline: `a3897dfbe2d3721e0ec0756a1872132daf9f6b90`.
Remote checkpoint branch: `codex/office-recovery-20261114` in both repositories.

## Findings and selected scope

Source review found that right-to-left layout and frozen-pane commands directly
change persisted worksheet properties without dirty-state, save-revision or
undo/redo commands. They also omit the interaction-mode mutation guard. The
engine writes these properties to XLSX, and the app exposes them in its ribbon.
An unsaved close or an older asynchronous upload can therefore miss these edits.

A separate grid-history defect restores a snapshot through the currently active
worksheet and re-executes callbacks that read the current selection. Switching
tabs between a formatting/structural edit and undo/redo can mutate the wrong
worksheet. Its fix will be checkpointed separately from view-setting commands.

| Task | Acceptance | Status |
| --- | --- | --- |
| WS-01 | RTL and freeze/unfreeze use owner-bound commands; exact no-ops preserve redo and revisions; viewing/selecting reject mutation; pending cell drafts remain intact. | Passed: the same 20 tests go from 20 baseline failures to 20 passes at `e02feac5`; focused analysis reports no issues |
| WS-02 | Grid undo/redo stays on the original worksheet and replays the original operation independently of later tab/selection changes. | Passed at `30cb194a`: 14 new grid cases plus the view/fill/style/cell-state/pending-save overlap group, 80 passing tests total; scoped analysis reports no issues |
| WS-03 | Actual app toolbar, close/save and delayed-upload tests retain view changes; saved workbooks preserve the other worksheet through history. | Host acceptance pending |
| WS-04 | Exact native-fill and worksheet-state outputs reach the CI schema job; missing/unexpected artifacts fail inventory checks. | CI integration pending |

## Execution boundaries

The existing engine, editor and host results retain their original source and
scope. New baseline failures, implementation checkpoints and positive validation
will receive separate receipts. The hosted jobs remain queued without assigned
runners; no executed failure establishes a queue cause.

Reusable controller logic stays in Quds and reaches the app only through the
guarded source synchronization tool. Each meaningful code/evidence increment is
saved remotely. This work does not add broad clipboard behavior or claim a new
physical-device, browser or renderer acceptance run.

The [view-setting baseline](evidence/office-worksheet-state-20261114/phase-a-baseline/README.md)
retains all 20 assertion failures, the exact new test source and 400 unchanged
input hashes. The initial implementation captures each worksheet and its scalar
values in commands. It does not reuse the grid snapshot helper or commit/discard
pending cell drafts. The [positive receipt](evidence/office-worksheet-state-20261114/phase-a-positive/README.md)
binds 20 passing tests and focused analysis to the published implementation
checkpoint. The controller is the sole changed input; all 400 execution inputs
remain stable.

The [grid-history negative control](evidence/office-worksheet-state-20261114/phase-b-baseline-corrected/README.md)
retains 14 expected assertion failures and 408 stable inputs. The grid fix keeps
the original worksheet and selection, restores captured before/after states,
and reuses the original cell objects so ordinary cell-edit history remains
attached. It retains empty row indices, column metadata, row heights, merges and
every modeled cell field. The existing full-grid snapshot approach now retains
both states for deterministic redo. The initial test-helper failure is preserved
separately and is not counted as a product witness.

The [integrated positive receipt](evidence/office-worksheet-state-20261114/phase-b-positive/README.md)
records all 80 passing editor tests. The exact corrected grid tests go from 14
baseline failures to 14 passes, with the controller as the sole changed input.
The app consumes this source at its `bd910b14` integration checkpoint; all 2,176
managed files match the guarded source and Git index verification.
