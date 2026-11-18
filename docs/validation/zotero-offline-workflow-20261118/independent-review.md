# Stored reference details: independent interaction review

## Scope and result

All **11 new widget cases passed** using genuine Flutter 3.47.8 / Dart 3.13.7.
The process exited zero; the expanded log contains no framework exception,
overflow, or missed-tap diagnostic. Every interaction helper requires a
hit-testable target, and missed-tap warnings are fatal.

Only the new widget test file was authored by this reviewer. Product source
changes were written by the parent agent and independently exercised here.

## Behavior covered

- Imported records with duplicate CSL IDs open the correct metadata without
  selecting the record as a side effect.
- Offline and read-only inspection preserves reference metadata, unknown fields,
  linked identities, document text, citation fields, content revision, caret and
  undo state. DOI and inert URL text remain available.
- Clipboard failure keeps selectable text available, reports a manual-copy
  fallback, and permits retry. Closing a dialog with a pending copy does not
  update disposed state or lose the parent selection.
- Opening nested details preserves staged selection reordering and removal.
  Cancel restores the original selection; Apply commits the staged order.
- Mixed connected, imported offline and imported group selections remain
  inspectable when hidden by the import filter, with no additional fetch.
- The 20-source limit includes a connected source hidden from import results.
  Attempting a 21st selection reports the limit and retains 20 sources;
  inspecting the rejected record remains possible. Deselection still works,
  after which a different source can be selected.
- The complete import, details, failed-copy/retry and nested-review flow passes
  at **320 × 480 with doubled text in both LTR and RTL**.
- A 20-source review at the same narrow doubled-text size allows nested details,
  reordering and removal while keeping source values unchanged.
- A reference without stored CSL item metadata can still be inspected and
  copied using its retained source identity.

## Validation commands

Working directory: `zotero-validation/packages/quds_office_editor`.

```sh
source /workspace/scratch/7f793b53d474/zotero-toolchain/env.sh
flutter test --no-pub test/word_zotero_stored_details_dialog_test.dart --reporter expanded
dart analyze --fatal-infos --fatal-warnings test/word_zotero_stored_details_dialog_test.dart
```

Both commands exited zero; strict analysis reported **No issues found**.
The new file is formatted using the recovered SDK formatter.

Current saved implementation checkpoint:
`3ad7c8b6e14ae09985bb58c9c7ce8a25277e056a`.

Test-file SHA-256:
`8104f6b112b1be5c6059eecf55f31f737aebe8f4091bf5c796562ad5a1cabec9`.

## Retained first attempt

The initial run passed seven cases and failed four before their intended
interactions because the fixtures used a local CSL ID in a widget key even when
the existing importer had replaced that ID with the first linked Zotero URI.
Only the test fixtures were corrected to the established importer identity.
No product fix was required. Both the first log
(`development/widget-first-attempt.log.gz`) and successful log
(`development/widget-focused-pass.log.gz`) remain available.

## Incoming cutoff

The final remote snapshot contains **377 refs**, including this implementation
branch and PR #165. Excluding those two leaves **375 incoming refs**. Compared
with the first resumed snapshot, 372 are unchanged and three changed:
the spelling branch now points to the already-included baseline; the review
branch and PR #162 point to one new documentation-only commit
`e9dc92798d1c39ac48474d0aa5af7321e75e6bb0`.
Its sole change is
`docs/validation/document-review-live-20261118/incoming-audit.json`.
That history is preserved in final integration commit
`02da86d9ba82f5d14dc04a3759c247064bcd6a25`, whose parents are the tested
implementation checkpoint and the observed documentation head. A local diff
confirms that product and test inputs do not change. All 375 incoming refs are
accounted for: 347 are exact ancestors, while ten historical no-op refs and
18 historically landed refs retain their identical prior names, SHAs and
classifications. No further remote polling was performed after this cutoff.

## Limits

These are real Flutter widget interactions with a controlled clipboard channel
and catalog transport. They do not establish new live-account behavior, installed
device acceptance, native application builds, or operating-system clipboard
integration. No GitHub Actions, workflow, CI-status or check endpoint was queried.

