# Zotero desktop item selection — 2026-11-22

## Intake

- Repository: `CrispStrobe/quds_office_suite`.
- Main at intake: `3b375e1a71a6356371611421d6c1f6d19917b40a`.
- Every non-main branch discovered (15 branches) was 0 commits ahead of main; no open PRs.
- No unrelated branch was force-moved, rebased or discarded.
- Feature checkpoint branch: `codex/zotero-select-navigation-20261122`.
- Each source, regression-test and documentation change was separately committed
  to that remote branch. Commit messages use `[skip ci]` to avoid the free-tier
  Actions queue, which was not queried as a gate.

## Delivered behavior

- Add `Open in Zotero` to catalog and stored-source details when a canonical
  local Zotero library or group identity can be validated.
- Use Zotero desktop's `zotero://select/library/items/KEY` and
  `zotero://select/groups/ID/items/KEY` selection URLs.
- Keep offline records, arbitrary URLs, malformed identities, remote personal
  Web API user IDs and ambiguous cross-library/cross-profile references inert.
- Open only after an explicit user click; the app's external protocol handler
  is invoked with no HTTP request, account credentials or citation mutations.
- Retain the details dialog and show a recoverable error if the launch fails.
- Allow a host-injected opener for deterministic UI tests.

## Added regression coverage

- `packages/quds_office_editor/test/word_zotero_selection_uri_test.dart`
  (six unit tests): local and group routes, personal-library refusal, alias
  equivalence, conflicting identities and unsafe URI refusal.
- `packages/quds_office_editor/test/word_zotero_selection_navigation_test.dart`
  (six widget tests): local/group launch, blocked remote personal selection,
  stored source stability, failed launch and missing/ambiguous actions.
- Existing reference details and stored-source widget tests remain relevant.

## Local qualification and limits

Suggested commands in a workstation with the repository's Flutter SDK:

```sh
flutter test packages/quds_office_editor/test/word_zotero_selection_uri_test.dart \
  packages/quds_office_editor/test/word_zotero_selection_navigation_test.dart \
  packages/quds_office_editor/test/word_zotero_library_details_test.dart \
  packages/quds_office_editor/test/word_zotero_stored_details_dialog_test.dart
dart format --output=none --set-exit-if-changed \
  packages/quds_office_editor/lib/src/embed/word_zotero_format.dart \
  packages/quds_office_editor/lib/src/embed/word_zotero_library.dart \
  packages/quds_office_editor/test/word_zotero_selection_uri_test.dart \
  packages/quds_office_editor/test/word_zotero_selection_navigation_test.dart
```

The current execution environment does **not** contain `dart` or `flutter`.
These are implemented test cases, not claims of an executed passing suite.
No installed Zotero plugin, Word or LibreOffice session was available for
live navigation or round-trip acceptance. Do not infer release-host support
from static inspection or a successful scheme handoff alone.

## Follow-up acceptance

Test the desktop handler on Windows, macOS and Linux with Zotero running
and stopped; exercise local/group and missing-item cases, multiple profiles,
group access, return focus, and the existing citation undo/refresh tests.
Cross-app Word/LibreOffice Zotero plugin parity remains tracked in
`docs/roadmaps/zotero/word-processor-parity.md`. Apache OpenOffice is a
separate historical integration target, not a current supported Zotero plugin.
