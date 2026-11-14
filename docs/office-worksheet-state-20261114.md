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
| WS-01 | RTL and freeze/unfreeze use owner-bound commands; exact no-ops preserve redo and revisions; viewing/selecting reject mutation; pending cell drafts remain intact. | Implementation pending; baseline regression witnesses to be executed |
| WS-02 | Grid undo/redo stays on the original worksheet and replays the original operation independently of later tab/selection changes. | Reproducer and bounded fix pending |
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
