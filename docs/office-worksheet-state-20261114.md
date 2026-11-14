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
worksheet. Its fix was checkpointed separately from view-setting commands.

| Task | Acceptance | Status |
| --- | --- | --- |
| WS-01 | RTL and freeze/unfreeze use owner-bound commands; exact no-ops preserve redo and revisions; viewing/selecting reject mutation; pending cell drafts remain intact. | Passed: all 20 view tests are included in the final 100/100 gate at `0f935a6f`; original 20-failure baseline retained |
| WS-02 | Grid undo/redo stays on the original worksheet and replays the original operation independently of later tab/selection changes. | Passed: all 14 new grid cases and relevant overlap cases are included in the final 100/100 gate; original corrected 14-failure baseline retained |
| WS-03 | Actual app toolbar, close/save and delayed-upload tests retain view changes; saved workbooks preserve the other worksheet through history. | Passed: all five worksheet host cases complete their full positive paths on app `ccba883b`, retaining 17 exact XLSX files |
| WS-04 | Exact native-fill, worksheet-state and style-history outputs are routed to the CI schema job; missing/unexpected artifacts fail inventory checks. | Implemented and locally validated: 23 controls pass; 176-file synthetic inventory and 149-file rendering staging pass; 27 current XLSX files independently pass SDK validation. Hosted workflow execution remains queued |
| WS-05 | Actual ribbon styling uses canonical owner-bound commands; undo preserves native fill/font intent as well as worksheet ownership. | Passed: 20 typed-style cases in the final 100-test canonical gate; both styling host cases and the native-fill overlap pass on `ccba883b`; all six app routes use canonical commands |

## Execution boundaries

The existing engine, editor and host results retain their original source and
scope. New baseline failures, implementation checkpoints and positive validation
have separate receipts. At the recorded hosted-CI observation, the jobs were
queued without assigned runners; no executed failure establishes a queue cause.

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

## Ribbon formatting history completion

The app's separate `_CellStyleCommand` still resolved the active worksheet during
undo and assigned color setters without restoring their native-edit intent.
Two actual ribbon baselines on app `bd910b14` reproduced the remaining defects:
cross-sheet Bold undo left Budget bold, and same-sheet Bold undo changed an
authored gradient to a no-fill pattern in the uploaded XLSX. The independently
authored source passed SDK schema validation before these results were accepted.

Four typed APIs now support bold, font size, horizontal alignment and the
existing six-field clear-formatting action through the corrected grid history.
The app uses them alongside the existing fill/font-color APIs and has removed
its duplicate style command. Scalar no-ops preserve redo and revisions without
creating cells, font sizes must be finite and positive, and the commands respect
interaction modes and pending drafts. Clear formatting retains its existing
scope; this change does not redefine other cell-formatting semantics.

The final canonical acceptance group includes all three new regression files
and the relevant existing overlap cases: 100 tests across eight files. The new
APIs have no fabricated pre-API unit baseline; the actual host ribbon supplies
the independent failing behavior witnesses. Exact implementation metadata is
retained in `evidence/office-worksheet-state-20261114/phase-c-implementation.json`.

The [final canonical receipt](evidence/office-worksheet-state-20261114/phase-c-positive-corrected/README.md)
records 100/100 passing tests and zero analysis issues at `0f935a6f`. All 409
inputs stayed unchanged: 406 tracked files matched their Git blobs, and three
generated dependency inputs have retained payloads. The initial 96-pass/four-
fixture-failure attempt is retained separately; its correction only normalized
the test formula type before recording expectations. Production code did not
change. The app's final guarded sync verifies all 2,177 managed files.

## Completed app acceptance

App source `ccba883b3a042582d3fd80f75772c20bff9e2c4b` pins the validated canonical
source `0f935a6f24ae11aa9851a5cc3498808554194446`. Eight focused host cases pass:
five worksheet-setting/grid cases, two ribbon-style history cases, and the
existing native-fill preservation case. All three collections and final scoped
analysis use the same 4,743 unchanged inputs. Analysis of the app ribbon and
both host test files reports no issues. The temporary CI SQLite hook restores
the committed pubspec bytes after collection and receipt verification.

The independent OpenXML SDK accepts all 27 fresh workbook files with zero
errors: three authored inputs and 24 captured uploads. Separate cohort receipts
retain their exact input/output hashes and validator self-tests. The final CI
controls also preserve all original 146 rendered host outputs and three pinned
references; the new 27 artifacts have explicit schema scope. The 176-file
synthetic inventory/staging check is distinct from actual host/schema results.

The app's [continuation record](https://github.com/CrispStrobe/CrispCloud/blob/codex/office-recovery-20261114/docs/office-worksheet-state-20261114.md)
links the final host, inventory and independent validation bundles, including
raw logs, LCOV, generated dependency snapshots and every captured workbook.
Earlier baseline and test-helper failures remain immutable and honestly labeled.

The [hosted-CI observation](evidence/office-worksheet-state-20261114/hosted-ci/execution-sources.json)
at 20:10:10 UTC records the fidelity runs for these two implementation sources.
They were queued with runner ID zero and no executed steps. Local acceptance is
complete; a hosted workflow pass is not claimed. No new physical-device,
browser, external-Office rendering or combined application-coverage result is
inferred from these scoped checks.
