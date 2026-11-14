# CrispCloud source reconciliation — 14 November 2026

## Latest follow-up

The later canonical Word import source was merged at
`a379ecc455890032906098b6cf58e17504581ed0`, retaining the original history and
sorting regression. Its [separate qualification](word-followup/README.md)
records 117 focused Word tests plus the repeated 115-test editor cohort,
strict analysis and unchanged source inputs. The sections below retain the
earlier reconciliation scope and its original source-bound results.

## Initial reconciliation

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
It adds no dependency or public API and does not alter main. Focused acceptance for the combined source is recorded below; historical
parent results are not relabeled as combined-source passes.

## Combined-source acceptance

Qualified source: `cb42ef232e5794ac4c147ef1992133cf8710ab01`, tree
`74992ca733610409050e898c9ce4561c93836536`. This evidence-only continuation
preserves those tested source bytes.

- All **115 tests passed**, with zero failures or skips, in the ten expected
  suites: style, grid, view, fill intent, font-color intent, explicit style,
  cell state, pending edits, sorting and speaker notes.
- The new integration regression combines sort, canonical formatting, row
  removal and history after navigating to another sheet. It checks original
  cell objects, imported empty rows and unchanged neighboring content.
- Strict Dart analysis (`--fatal-infos`) of the merged controller and sort
  regression file reports **No issues found**.
- **3,667 tracked and generated inputs** remained unchanged during the final
  test and analysis executions, including the resolved package map and lock.
  Flutter is pinned to 3.47.8, revision
  `737ba8f885dc774b53b442759999a312c9461e4e`, with Dart 3.13.7.

The [final native receipt](native/validation.json),
[analysis receipt](native/analysis.json), raw compressed JSON test events,
source inventory, dependency snapshots and runtime hashes are retained.
The [initial attempt](native-attempt-1/validation.json) passed 107 cases but
could not compile the sort suite because the newly added integration test used
`deleteRows` instead of the existing `deleteSheetRows` API. The test-only
correction was saved before the complete successful rerun. Runtime bytes did
not change after the original merge checkpoint.

This gate covers the canonical Linux unit-test profile and static analysis.
Browser, desktop application workflows and platform acceptance are separate;
CrispCloud's integration has its own host source pin and qualification.
