# Worksheet navigation and rename continuation — 14 November 2026

Branch: `codex/office-recovery-20261114` in Quds and CrispCloud.
Starting suite checkpoint: `a85a977a8ab95bcf42214eb6dd05c73e2fcb5243`.
Starting app checkpoint: `f974b9911b1547c806279279a87f2b21a1ac4357`.

## Scope

The previous worksheet/history increment is complete at its recorded sources.
This increment exposes worksheet selection and the existing reversible rename
operation in the app. Inspection found no host worksheet selector, an unused
`QudsSheetEditor.navigationBuilder` hook, and a switching path that uses the
weaker `commitCellEdit()` boundary. Pending-input failures will be reproduced
before changing that boundary.

| Task | Acceptance | Status |
| --- | --- | --- |
| NAV-01 | Switching commits valid drafts to their original sheet; rejected drafts remain visible on that sheet; effective same-sheet navigation changes no state. Navigation alone remains clean and preserves history. | In progress |
| NAV-02 | The existing optional sheet navigation builder renders below the grid, rebuilds with the controller, and leaves the default editor layout unchanged when absent. | In progress |
| NAV-03 | The app has a localized, keyboard-accessible selector and guarded rename dialog. Actual host saves preserve worksheet contents and rewritten references through rename/undo/redo. | In progress |
| NAV-04 | Exact new host captures are included in the CI schema inventory, independent validation checks their bytes, and existing artifact requirements remain intact. | Planned |

## Boundaries

Keep existing index-clamping and formula-evaluation semantics. Navigation in
viewing/selecting modes is allowed when it does not need to mutate a pending
draft. Add/remove/reorder/hide operations and persistent native active-tab state
are outside this increment. Sheet names remain authored content.

Canonical changes reach the app through the guarded source synchronization
tool. Each meaningful implementation/evidence checkpoint is saved remotely.
Baseline failures, positive runs and external validation retain separate source
and input receipts; earlier acceptance is not relabeled. Hosted CI was still
queued at the initial read and is not treated as a passing result.
