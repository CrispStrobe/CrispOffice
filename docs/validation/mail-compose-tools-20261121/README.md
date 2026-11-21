# Mail compose tools — source and qualification record

## Outcome and qualification

Account-scoped signatures and literal Quick Text are implemented in the core,
SQLite repository and shared native Studio composer. The code and all authored
regressions are retained in incremental remote checkpoints.

**Subsequent local runtime qualification passed during Word style integration.**
The genuine pinned Flutter 3.47.8 / Dart 3.13.7 SDK passed all 476 Mail core and
924 Mail store tests, all 37 composer/settings/adapter tests, and 19 plain-text
insertion tests. Strict analysis and formatting also passed. The v7 migration
fixture was corrected to remove both new v10 tables before reconstructing the
old schema. See the [completion record](../word-vba-styles-complete-20261121/README.md)
for retained commands and receipts. Installed-app and live-provider checks
remain outside this local qualification.

The initial increment below had source review and ancestry checks only because
its executor failed. That historical record is retained without treating its
unexecuted tests as passing evidence.

The [feature contract](../../roadmaps/mail/compose-tools.md) gives the user path,
storage semantics and exact selection/authoring limits.

## Intake and reconciliation

Initial remote main: `115f1c20131bf0157d047dfe2e9d704ddffb22a2`.

- All 31 branch tips observed at initial intake were ancestors of that main.
- All 101 PRs created since 20 November 2026 (#221–#321), including their heads
  and merge commits, were already ancestors.
- No open PR remained at initial intake.
- Upstream main `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` was already included.

The original [branch audit](intake.json) and [PR audit](intake-prs.json) preserve
the complete observed references.

While this increment was underway, Zotero PR #323 merged into main at
`3dbaa8429b14ac43721e165b4d50d3f6d2845309`. The mail branch adopted that main
through a normal two-parent merge. Its 12 incoming paths were disjoint from the
mail changes and were retained unchanged. Comparison after reconciliation
reported zero commits behind main.

Late intake also found `fix/mail-restore-view-20261121` (PR #324) at
`e05056dcbe3260b77916dd9255664a8c62e98bf0`. Its saved-account restoration view
was applied as an exact uniquely matched hunk outside our native compose-host
changes and retained through a normal two-parent merge at
`af662bcd726097657e2b71ec1fbb6de5eb5dde2a`.

Word VBA PR #322 remains explicitly **WIP**, draft and open at the final intake
snapshot, with head `6ad48343192a19d0da1f9a0c2c0f318b51e1e9cc`.
`codex/word-vba-styles-complete-20261121` at
`db531880f9a1ef4d5060c6fffee5fac8af537b7a` is an integration checkpoint whose
native style implementation is still pending. The newer
`codex/zotero-editable-odt-20261121` at
`0a5db51c8483e7ad0b6de088ae1e75b566942a7d` is an initial scope/validation plan,
with implementation explicitly in progress. These branches remain preserved;
this mail increment does not publish their unfinished features as complete.
Final publication rechecks current main and PR state.

## Remote checkpoints

Development branch: `work/mail-compose-tools-20261121`.

| Commit | Saved increment |
| --- | --- |
| `1750be749d683b67fb456aa513494532d5b2088b` | Reconciled initial intake and concrete milestone |
| `9c4930cdd5ebb128c640cea48858c546ff44ae50` | Typed settings, additive schema 10 and authored model/store regressions |
| `23d2aba68bb5a45542a04f921d20d5bd17e78714` | Connected/offline composer integration, localized manager and Word insertion API |
| `2c5bb8a113c5f824ec7856bbc5938ce499a2137e` | Independent-review fixes and further authored regressions |
| `32a6dcd4e56584b5af34625b44a845eb15ba44bd` | Adopt current main/Zotero PR #323 without dropping either history |
| `af662bcd726097657e2b71ec1fbb6de5eb5dde2a` | Incorporate the late saved-account restore-view branch without dropping compose changes |

Command-line Git had read access but no write credential. Connected GitHub
Git-data operations created immutable blobs/trees/commits and advanced the
branch with observed-head checks and `force: false`. The initial local checkout
was aligned to the first remote checkpoint; after executor failure, the remote
branch is authoritative. No force update or branch deletion is part of this work.

## Implemented boundaries

- Immutable bounded per-account settings, ordered named snippets and revision
  comparison. Signatures default independently for new messages and replies.
- Additive migration from schemas 1–9 to 10. Strict bounded UTF-8 reads, input
  validation, account/profile cleanup, ordinary logout retention and existing
  repository quota accounting.
- Settings changes leave drafts, prior uncertainty and frozen Outbox MIME and
  envelopes intact. The Studio facade serializes settings and draft work and
  drains accepted writes before closing.
- New-draft boundaries apply defaults once. Resume, Outbox edit-copies and
  settings reload do not rewrite message bodies.
- Explicit text insertion at a caret, within one paragraph, or over the whole
  message. Unsupported partial cross-paragraph selection fails without changing
  content. Supported insertion uses one Word undo batch and no clipboard.
- English, German and Arabic management, guarded failure/readback behavior and
  connected/offline account integration.

## Independent source review

The bounded compose-tools review used
`32a6dcd4e56584b5af34625b44a845eb15ba44bd`. The later restore-view merge at
`af662bcd726097657e2b71ec1fbb6de5eb5dde2a` preserves all compose changes and
adds only the incoming saved-account loading view. The documentation-only
checkpoint leaves that combined production source unchanged.

Review identified and corrected:

1. An initially stale tools owner could leave a new composer loading forever.
   The early return now releases pending/loading state.
2. Flat-string insertion preflight did not match legacy Word structured
   deletion across partial paragraph selections. The new boolean API and
   composer now refuse that shape before mutation; whole-message replacement
   remains supported.
3. New reply defaults were skipped by optional tools owners without draft
   catalogs. Connected hosts now prepare genuine new replies before the
   catalog-specific save, retaining the existing legacy-draft guard.
4. SQLite's non-integer primary key needed explicit `NOT NULL` ownership.
   Account/profile cleanup and a constraint regression cover the correction.

Review also checked source/API consistency, owner/account/epoch guards,
same-account next-revision acknowledgements, immutable draft/Outbox snapshots,
close serialization, migration ordering, quotas and strict stored-text decoding.
No additional concrete source defect was found. This is not a compiler result.

## Authored tests (subsequently executed)

| Suite | Intended coverage |
| --- | --- |
| Core `compose_settings_test.dart` | Immutable values, Unicode/control validation, limits, identity and uniqueness |
| Store `compose_settings_test.dart` | Persistence/reopen, CAS, rollback, owner separation, quotas/corruption, draft/Outbox preservation, migrations 1–9 |
| Existing store migration/sync/reconciliation suites | Current schema expectations retained |
| Studio `studio_mail_compose_tools_store_test.dart` | 10 helper/native-adapter cases: defaults, stale/foreign owners, persistence, frozen Outbox and uncertainty/close |
| Studio `studio_mail_compose_tools_dialog_test.dart` | 15 manager cases including EN/DE/AR layout, local CRUD, pending/uncertain save and stale acknowledgements |
| Studio `studio_mail_compose_tools_test.dart` | 12 composer cases: defaults/resume, insertion/undo/autosave, manager readback, stale callbacks and refusal |
| Editor `word_plain_text_insertion_test.dart` | 19 literal insertion/history/clipboard/guard/selection cases |

The original authored counts above are now supplemented by the passing local
execution totals in the completion notice. The whole-package store run includes
the migration/sync paths and real SQLite crash-recovery subprocesses.

## Original executor failure and toolchain receipt

- Repository pin: Flutter 3.47.8; SDK requirement Dart ^3.12.0.
- Standalone `dart --version` successfully identified Dart 3.13.7.
- The official pinned Flutter archive downloaded with SHA-256
  `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
- All 137 hosted archives from the current workspace lock were downloaded and
  checked against locked hashes. Lock SHA-256:
  `2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.
- During SDK extraction, free disk fell to zero. Every new sandboxed command,
  including deletion of reproducible setup files, failed before executing with
  `bwrap ... No space left on device`.
- A narrowly scoped cleanup escalation was rejected because the environment's
  granular policy disables sandbox escalation. Native cleanup access was
  unavailable. Later executor/helper requests also returned unavailable-process
  errors. No cleanup command is claimed to have run.
- Flutter extraction/resolution did not complete. No runtime or test pass is
  claimed from that incomplete installation.
- GitHub Actions were neither awaited nor treated as an acceptance gate.

All source authored after this failure was uploaded through the connected
GitHub API and reviewed from immutable remote blobs/commits. No current
acceptance claim depends on transient local files.

## Commands to execute when a working executor is available

Use the pinned Flutter SDK and the unchanged workspace lock. From repository
root, resolve with `flutter pub get --enforce-lockfile`, then format/analyze the
changed Dart paths. Run these focused suites from their named package roots:

```bash
# packages/quds_mail_core
dart test test/compose_settings_test.dart

# packages/quds_mail_store
dart test test/compose_settings_test.dart test/migration_test.dart \
  test/sync_mailboxes_test.dart test/flag_reconciliation_test.dart

# packages/quds_office_editor
flutter test test/word_plain_text_insertion_test.dart

# packages/quds_office_editor/example
flutter test test/studio_mail_compose_tools_store_test.dart \
  test/studio_mail_compose_tools_dialog_test.dart \
  test/studio_mail_compose_tools_test.dart \
  test/studio_mail_attachment_compose_test.dart \
  test/studio_mail_draft_store_test.dart
```

Follow with the existing affected provider-host/draft/Outbox regressions. This
record does not authorize using a real mailbox or sending test messages.
Installed-platform and live-provider qualification are separate from fixture
tests. Do not label the milestone fully qualified until those applicable checks
actually execute.
