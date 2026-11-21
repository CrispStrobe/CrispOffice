# Explicit offline Mail downloads — integration qualification

Recorded on **21 November 2026** for
`CrispStrobe/quds_office_suite`, branch
`work/mail-offline-retention-20261121`.

This milestone lets a connected account explicitly retain the complete message
content behind synchronized headers, then reopen it offline. The page action
operates on at most 100 headers from the loaded page, including rows hidden by
filters, with a 64 MiB content budget per request. Individual missing messages
also have a download action. Completed snapshots are skipped on retry;
cancellation, provider failure, session retirement and storage limits preserve
acknowledged earlier writes. Downloading does not mark mail as read or advance
the folder synchronization cursor.

The account's existing repository owns each atomic raw-message/body/attachment
write. No second repository is opened. The UI exposes progress, cancellation and
localized completion/failure explanations in English, German and Arabic.

Incoming native Quit handling was also corrected: `maybePop` honors the
composer's save guard, accepted route transitions finish before account disposal,
and an unfinished or failed save blocks window closure. A later Quit can proceed
after an asynchronous save succeeds.

## Integration and remote preservation

The initial `main` head was `4090feb5`; intake advanced to `97cfb09b`, which
already includes PRs **#294** (credential-vault unlock/native menus) and **#295**
(localization/screenshot polish). The new performance branch `5332c5ff` was then
merged at checkpoint `f0c2599b`. Implementation checkpoint `63f54066` follows it.
The third remote checkpoint is
`7414e0fa044d47c9b5eb96ddf66a1aa5d315613c`, tree
`0104861b56e568bb45952418f7eb00759318fc19`, preserving the qualification fixes,
roadmap and durable-host regressions. All three checkpoints were published to, and verified on,
the remote work branch.

Ten historical nonancestor branches were checked by Git tree/blob identity
against their established ancestor replacements. Their content is already
represented; they are not missing feature work. [intake.json](intake.json)
records the exact heads, replacement objects and comparison scope.
The final [branch snapshot](branch-snapshot.json) checks 52 captured remote
branches: 42 are ancestors and the remaining 10 are exactly represented by the
verified replacements. No captured branch remains unresolved.

The latest captured remote `main`, `f92c0d24` containing Word head `13fa9ad5`,
was merged first at `4f894512`. Zotero PR #296 head `96a6b1b1` followed, producing
local integration `cd78a3baae61e5eaf9a70e63100ccf8146327dd7`. Only additive
editor changelog conflicts required resolution; all entries were retained.
These captured heads replace the earlier Word/Zotero heads
`75b429e3`/`6270ec92`. The seven qualification-fix source hashes recorded in
[intake.json](intake.json) are unchanged after both integrations.

The combined integration was published and remotely verified as
`8335a43934825af60a8b13a4f4ba42caae88d05b`, tree
`5731b5ab05735cc8f154973e5e93e08057094ee4`, with parents `7414e0fa`, `f92c0d24`
and `96a6b1b1`. Its tree exactly matches local integration `cd78a3ba`.

The fifth remote checkpoint,
`283ec4ae7c690787ae29b9342872b3206cc57b67`, tree
`03a23d9663c813a1532bc83674f694097d677c4d`, contains the final scrollable
compact-layout implementation and its tests; both recorded source hashes are
now published.

**Local qualification is complete.** The final captured Zotero continuation
`c4e1d67540e7c3a706d2f0a3fead0cb17949f437` was integrated as
`33b3b2add0fbabb6b445d2a6e4b9a1f85330eb89`. Its Mail fixes duplicate the preserved
current fixes; the two file conflicts retained the qualified implementations.
An exact Git diff verifies that all tested Mail application code and tests are
unchanged from `283ec4ae`. The complete source delta is two editor changelog
lines and the new 432-line `nested_table_acceptance.dart` utility; that utility
also passes static analysis. These immutable checkpoints bind the evidence.
Final publication and remote-main readback are recorded in the GitHub pull
request, rather than embedding the evidence commit's own future identifier here.
GitHub Actions were not awaited, retried or used as acceptance evidence.

## Observed local results

The genuine toolchain is **Flutter 3.47.8 / Dart 3.13.7**, framework revision
`737ba8f885dc774b53b442759999a312c9461e4e` and engine revision
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`. The bootstrap verified 202 locked
hosted packages and completed offline dependency resolution with the lockfile
enforced. No SDK, framework, test-runner or database implementation was replaced
with a fixture.

| Check | Observed result | Raw log |
| --- | --- | --- |
| All mail-core tests, including bounded body retention | **334 passed** | [mail-core-direct.log](logs/mail-core-direct.log) |
| Real native SQLite retention, restart, cancellation, retirement, rollback and quota regressions | **8 passed** | [mail-body-store-fixed.log](logs/mail-body-store-fixed.log) |
| Postmerge native adapter, synchronization/download dialog and calendar dates | **48 passed**: 5 native, 33 dialog and 10 calendar cases | [mail-merged-workflow-fixed.log](logs/mail-merged-workflow-fixed.log) |
| EWS/Gmail/Graph host download, reconnect, offline reopening and stale-session guards | **8 passed** in the corrected targeted run | [mail-sync-host-fixed.log](logs/mail-sync-host-fixed.log) |
| Native Quit/composer regressions and existing desktop menus | **8 passed** | [quit-final.log](logs/quit-final.log) |
| Postmerge Word VBA, incremental layout and nested Zotero engine regressions | **260 passed across 9 files**, at the same tree as `8335a439` | [incoming-engine-final.log](logs/incoming-engine-final.log), [receipt](logs/incoming-engine-final.receipt.json) |
| Postmerge editor notifications, layout equivalence and nested Zotero controller behavior | **68 passed, 8 skipped**, exit 0, across 3 files | [incoming-editor-final.log](logs/incoming-editor-final.log) |
| Flutter engine/body-presentation bootstrap smoke | **31 passed**; separate from feature acceptance | [flutter-smoke.log](logs/flutter-smoke.log), [runtime receipt](runtime-bootstrap.json) |
| Targeted Mail host static analysis | **No issues found** | [mail-host-analyze-fixed.log](logs/mail-host-analyze-fixed.log) |
| Final Mail static analysis | **No issues found**, exit 0 | [mail-offline-analyze.log](logs/mail-offline-analyze.log) |
| Final compact-layout source/test analysis | **No issues found** | [mail-layout-analyze-final.log](logs/mail-layout-analyze-final.log) |
| Final incoming nested-table acceptance utility analysis | **No issues found** | [incoming-zotero-tool-analyze.log](logs/incoming-zotero-tool-analyze.log) |

The earlier mixed workflow run ended with failures in the new store fixtures and
three host cases; it is **not** reported as an overall pass. Its native-adapter
and dialog files completed cleanly. The corrected store and host reruns above
replace their respective failed results. The final Mail analysis also completed
cleanly; formatting of the seven selected files and the diff check passed.

The first postmerge native/dialog/calendar cohort completed with **43 passes and
2 failures**, both in compact English/German sync-dialog layouts using the
default widget-test font. The earlier real-font screenshots did not expose that
overflow. Status/recovery controls in the message pane were made scrollable, and
three compact selected-message download-access checks were added at 390 × 844
with text scale 1.3. The corrected cohort completed **48/48**; that clean run
supersedes the failed attempt. It includes the final formatted compact-layout
source changes on top of `8335a439`, whose hashes are recorded separately in
`intake.json` and published in `283ec4ae`.

The three incoming editor files completed with **68 passes and 8 skips**. The
skipped cases are existing image-only fixtures without editable paragraphs,
covered by the suite's existing `markTestSkipped('no paragraphs to edit')` guard;
they are not counted as passes or silently treated as executed coverage.

Native SQLite checks use `openStudioMailDraftStore`, real temporary directories
and close/reopen cycles with the default native build hook; there is no SQLite
library override. They preserve existing drafts, Outbox records and folder
cursors while verifying cached raw bytes, bodies and attachments after reopening.
These results supersede the runtime bootstrap receipt's earlier
“SQLite pending” status.

## Reproduction commands

Use the pinned SDK and locked dependencies. In this workspace, the environment
was supplied by `/workspace/scratch/5627811b9768/mail-runtime/env.sh`.
The pure-Dart runs invoked the installed `package:test` 1.31.1 entry point
directly, avoiding an unnecessary CLI dependency re-resolution in the Flutter
workspace:

```bash
# Repository root
dart --packages=.dart_tool/package_config.json \
  "$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart" \
  packages/quds_mail_core/test --reporter expanded --concurrency=2

# The exact nine-file postmerge engine command is retained in
# logs/incoming-engine-final.receipt.json (run from packages/quds_office_engine).

# packages/quds_office_editor/example
flutter test --no-pub --concurrency=1 --reporter=expanded \
  test/studio_mail_body_download_store_test.dart
flutter test --no-pub --concurrency=1 --reporter=expanded \
  test/studio_mail_sync_host_test.dart
flutter test --no-pub --concurrency=1 --reporter=expanded \
  test/studio_mail_quit_test.dart test/studio_desktop_menu_test.dart

# Reproduce the clean postmerge 48-case native/dialog/calendar cohort
flutter test --no-pub --concurrency=1 --reporter=expanded \
  test/studio_mail_sync_native_test.dart test/studio_mail_sync_dialog_test.dart \
  test/studio_mail_calendar_date_test.dart

# packages/quds_office_editor
flutter test --no-pub --concurrency=1 --reporter=expanded \
  test/word_edit_notification_test.dart \
  test/word_incremental_layout_equivalence_test.dart \
  test/word_zotero_nested_table_controller_test.dart
```

## Visual review and limits

English desktop and Arabic compact rendering were inspected. Captures for the
new controls include [English batch-limit feedback](screenshots/offline-download-limit-en.png),
[German batch-limit feedback](screenshots/offline-download-limit-de.png),
[Arabic batch-limit feedback](screenshots/offline-download-limit-ar.png), and
[an English individual-message download](screenshots/offline-download-message-en.png).

Providers in automated tests are deterministic. These checks do not certify live
mail-account credentials, real-server interoperability, native macOS packaging,
or full Outlook/Thunderbird/eM Client parity. The native Quit cases run the actual
Flutter widget/native-channel boundary with a macOS target-platform variant on
the Linux tester; they are not a launched macOS application.

This is an explicit foreground download milestone. Background synchronization,
automatic full-mailbox retention, retention eviction policies, server-side move
and delete reconciliation, unified full-text search and scheduling remain
separate work. SDK binaries, downloaded packages and compiler caches are excluded
from this evidence directory.
