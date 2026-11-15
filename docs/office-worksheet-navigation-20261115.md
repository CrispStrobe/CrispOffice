# Worksheet navigation continuation — 15 November 2026

Working branch: `codex/office-recovery-20261115`.
Recovered Quds source: `5133ce0343cb7c9456f852a4e760c771294ae6de`.
Recovered CrispCloud source: `8a24763fb4b2c720ff6b617cebbea8971191bdca`.

## Recovery and scope

The previous branch was merged and removed. Its saved
[navigation plan](office-worksheet-navigation-20261114.md) survives, but the
implementation and baseline results described in the interrupted conversation
are absent from both current remote trees. This continuation reconstructs that
work and records new evidence. The earlier reported 11 failures, eight controls,
ten host cases, and 102-test group are not claimed as recovered results.

The work retains NAV-01 through NAV-04: draft-safe worksheet switching,
same-sheet no-op behavior, the optional navigation hook, localized host sheet
selection and guarded rename, and independent validation of exact host uploads.
Add/remove/reorder/hide and persistent native active-tab state remain outside
this increment. Canonical changes reach CrispCloud through its guarded sync.

Current main CI and fidelity runs stop on three existing engine-test lint
findings: one unused import and two non-final local variables. Those findings
will be repaired without changing their test behavior. Baseline and positive
execution receipts will identify their own source revisions and input bytes.

## Canonical acceptance

Implementation source: `e6da5be3a7e085dc200e35d6300161658179463c`.

| Requirement | Result |
| --- | --- |
| NAV-01: draft-safe switching and effective same-sheet no-op | Passed. Valid input commits to its owning worksheet; invalid, protected and read-only drafts retain their visible input and original sheet. Navigation preserves history and clean state. |
| NAV-02: navigation builder | Passed. The optional builder renders below the grid, rebuilds with its controller, and follows controller replacement. |
| Find compatibility | Passed. Same-sheet find commits valid drafts before changing cells; rejected reveal leaves the successful query, hits and cursor intact. Library shortcuts and existing Studio callers show a correction path. |
| Existing Studio navigation | Passed. Tabs and existing add/delete actions reject pending invalid input before mutation. Workbook replacement explicitly resets selection and viewport. |
| CI engine lint blockers | Fixed. The entire engine analyzer passes with fatal infos enabled. |

The corrected original-source regression baseline has 10 passes and 22 failures
across 32 cases. The exact same cases pass on the implementation. The full
acceptance consists of 148 focused editor tests, nine Studio/workspace tests,
and three shared Word/Slide find controls: **160 passing tests**. Both analysis
gates report no issues. All five positive gates bind the same 2,096 unchanged
inputs to the implementation source.

The [retained evidence](evidence/office-worksheet-navigation-20261115/README.md)
contains separate baseline attempts, exact commands, source and runtime hashes,
generated dependency snapshots, and raw compressed logs. The initial baseline's
two extra assertion failures are labeled as test-harness errors; they are not
counted as product witnesses.

CrispCloud consumes this source through a guarded sync verifying 2,197 managed
files. NAV-03/NAV-04 app acceptance and hosted workflow status are recorded in
the app's continuation record. Local canonical acceptance does not establish
physical-device behavior or independent Office rendering.
