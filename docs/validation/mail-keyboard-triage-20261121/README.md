# Mail keyboard triage continuation — 21 November 2026

## Scope and source

Repository: `CrispStrobe/quds_office_suite`.
Captured main: `3058d36c5354d46bde418555d59282116cce1e26`.
Captured tree: `db88a060d16939c4614cfab3ee34ab8bb4f6cd70`.
Work branch: `work/mail-keyboard-triage-20261121`.

This continuation advances everyday loaded-mailbox triage with contiguous
checked selection and corrects synchronized-view header search. It does not
claim complete Outlook, Thunderbird or eM Client parity.

## Initial intake completed

The fork branches endpoint returned six heads including main. Every other head
was compared against the exact captured main. There were no unintegrated commits:

| Branch | Captured head | Result |
| --- | --- | --- |
| codex/word-vba-authoring-20261121 | cf06b018ec125ce3b5abfda41a7fbbdcf7d30a47 | Ancestor, 43 commits behind |
| codex/word-vba-compatibility-20261121 | 3058d36c5354d46bde418555d59282116cce1e26 | Identical |
| codex/zotero-note-layout-20261121 | 2089e1e35a8ba81ea7f0a077b348f93ca70953c8 | Ancestor, 22 commits behind |
| codex/zotero-odt-roundtrip-20261121 | 05072dc2d59d0fa4ea97de4d6a842700ef333fab | Ancestor, 37 commits behind |
| work/mail-live-search-20261121 | c3d55be30d91694b1a427d261cddbe47b1dd5eec | Ancestor, 22 commits behind |

The dedicated open-PR endpoint returned zero PRs. The latest 50 updated PRs
were inspected, including the merged Word VBA, Zotero, shortcuts, scheduled-send
and saved-search refresh continuations. Existing merged work is inherited from
main rather than replayed over later changes.

Upstream main `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` is also an ancestor
of captured main (zero upstream-only commits; 3,409 fork-only commits). No
upstream integration is needed at this cutoff.

## Intended acceptance boundary

- Shift+Up/Down/Home/End extends or contracts a checked range over the current
  visible ordering, without opening messages or submitting operations.
- Shift+checkbox selects a visible range from a stable anchor. Ordinary
  checkbox and Space actions remain independent toggles.
- Checked rows outside the active range remain deliberate selections; contracting
  a range removes only rows introduced by that range.
- Query, sort, folding, scope and host-revision changes invalidate the active
  range. Filtered or collapsed children can never enter an action snapshot.
- Bulk work remains explicit through the existing immutable, generation-guarded
  visible-selection callback. Read-only, busy and refresh-required hosts do not
  gain selection permission.
- English, German and Arabic help makes keyboard/range behavior discoverable.
- Synchronized-view from/to/cc searches include both displayed names and
  mailbox addresses, consistently with other mailbox views, without Bcc/body data.

## Execution availability

The local command sandbox failed before command execution with
`bwrap: Can't create file .../.git: No space left on device`. Subsequent
attempts reported that the unified exec process was unavailable. Source reads
and sequential Git writes use the connected GitHub API.

**No fresh Dart or Flutter tests, analyzer, formatter, build, visual inspection
or live-provider checks are claimed at this checkpoint.** New regression tests
will be committed with the implementation; their execution remains a separate
qualification requirement if the executor cannot recover.

GitHub Actions will not be queried or awaited. Checkpoints use ordinary
fast-forward ref updates with the expected prior SHA and `force=false`.
No branch is deleted and no history is rewritten.

## Checkpoints

1. Intake and acceptance contract — this initial remote checkpoint.
2. Shared range selection and localized help — pending.
3. Synchronized header search and regression coverage — pending.
4. Final source review, current-main reconciliation and merge — pending.
