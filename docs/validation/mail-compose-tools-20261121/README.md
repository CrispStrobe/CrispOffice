# Mail compose tools — implementation and local qualification

## Intake and scope

Baseline: `115f1c20131bf0157d047dfe2e9d704ddffb22a2` on remote `main`.
All 31 observed branch tips, all 101 PRs created since 20 November 2026
(#221–#321), and upstream main `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`
are already ancestors of that baseline. No open PR remained at intake.
The machine-readable branch and PR checks are retained beside this file.

Development branch: `work/mail-compose-tools-20261121`. Its final checkpoint
`32a6dcd4e56584b5af34625b44a845eb15ba44bd` was incorporated into
`codex/word-vba-extensions-20261121` together with the latest remote main.
GitHub Actions are not an acceptance dependency.

## Implemented user-visible increment

- Account-scoped persistent plain-text signatures with independent defaults for
  new messages and replies/forwards.
- Named reusable Quick Text, inserted through the existing undoable Word editor.
- The same composition tools in native IMAP/SMTP, EWS, Gmail, Microsoft 365 and
  offline draft entry, with draft/outbox content retained as immutable snapshots.
- Additive SQLite migration, bounded validated metadata, revision conflicts and
  account/lifecycle guards; English, German and Arabic host controls.

This extends the authoring boundary in M07. It does not complete mail-client
parity, alias/SMTP-identity routing, rich HTML authoring, provider Drafts,
background delivery, rules or end-to-end encryption.

## Qualification

Local checks ran on the repository-pinned Flutter 3.47.8 / Dart 3.13.7,
using locked dependencies and the actual SQLite package build hook (SQLite
3.54.1 with FTS5). No tracked manifests or dependency versions changed.

| Check | Result |
| --- | --- |
| Complete Mail core suite | 476 passed |
| Compose settings and schema migrations | 57 passed |
| Complete Mail store suite, initial run | 922 passed; 2 stale v7 fixture failures |
| Complete sync suite after fixture correction | 23 passed, including both previously failing cases |
| Flutter plain-text insertion | 21 passed |
| Flutter compose settings, store and dialog | 37 passed |
| Existing Native/EWS/offline compose, draft, reply and forward tests | 56 passed |
| Strict analysis of changed core/store/editor/host paths | No issues found |

The store coverage combines the initial full run and the corrected sync-file
rerun; it is not a second full-suite run. The v7 fixtures now remove the new
v10 compose tables before reconstructing an old database. They also verify
interrupted migration rolls back those tables and a successful upgrade exposes
revision-zero compose defaults. No production storage change was needed.

Runtime review also corrected `WordEditorController.insertPlainText`: when the
Notes pane owns the selection, the method refuses insertion before touching the
retained body caret. Footnote and endnote regressions check unchanged text,
selection, dirty state and history, followed by normal body insertion after
the note target is cleared. Remaining changes are formatting and analyzer
cleanup of the previously unexecuted increment.

Reproduce with the pinned toolchain and resolved workspace dependencies:

```bash
cd packages/quds_mail_core
dart test
cd ../quds_mail_store
dart test
cd ../quds_office_editor
flutter test --no-pub test/word_plain_text_insertion_test.dart
cd example
flutter test --no-pub test/studio_mail_compose_tools_test.dart test/studio_mail_compose_tools_store_test.dart test/studio_mail_compose_tools_dialog_test.dart
```

These checks qualify local models, persistence and Flutter host behavior.
They do not constitute live mail-provider transmission tests.
