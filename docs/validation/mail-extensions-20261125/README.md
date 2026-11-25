# Mail extensions — local validation, 25 November 2026

The sender identity/template and provider-search extension was checked against
CrispOffice's pinned Flutter **3.47.8**, bundled Dart **3.13.7**, and unchanged
workspace dependency lockfile on Linux x86_64. The source baseline is
`ef120d1ce3fb3e0a4753b33876b6a3c9722e9b61`. Source checkpoints are preserved on
`codex/mail-capabilities-20261125`.

## Results

| Executed test group | Result |
| --- | --- |
| Mail core | 698 passed |
| Mail SQLite store | 1,238 passed |
| Mail transport, native | 649 passed |
| Mail transport, browser boundary | 13 passed |
| Studio composition and recovery | 483 passed |
| Studio search and Exchange | 91 passed |
| Studio native and Outbox alias hosts | 99 passed |
| Studio Gmail and Microsoft 365 | 59 passed |
| Studio final template/RTL UI | 8 passed |
| Studio final search feedback | 3 passed |

These counts describe executed groups, not distinct tests to be added together.
The 483-test composition run overlaps the subsequent template and Outbox host
runs. Its 31 selected files later gained additional tests, so replaying that
command on the final source can produce a larger passing count.

Full `dart analyze --fatal-infos` passed in mail core, store and transport.
Strict analysis also passed for all 22 changed Studio Dart source/test paths.
`git diff --check` passed. The final small search-help wording change was covered
by the last three-test dialog run. The core and transport suites were rerun after
the final independent search-count review.

[results.json](results.json) records command/cwd pairs, observed passing counts,
log checksums and SHA-256 identities for the modified production Dart files.
It binds this report to the tested source without relying on historical roadmap
test totals. The local logs contain synthetic fixtures rather than private mail.

## Important exercised behavior

- Schema 21 migrations preserve existing signatures, Quick Text, revision and
  unrelated data across every published schema 1–20. Interrupted migration
  rolls back and succeeds on retry. Existing real SIGKILL/reopen tests pass.
- Account ownership, aggregate quotas, strict UTF-8, corrupt stored data,
  immutable lists, identity references and concurrent revision conflicts.
- Selected sender persistence through draft recovery, MIME, frozen Outbox and
  editable copies; explicit SMTP From matches MIME From; Bcc stays private.
- Native direct and frozen-Outbox alias sends use the original authenticated
  account. EWS refuses an alias before submission and preserves its payload.
- Explicit template replacement, empty-body replacement, attachment/thread
  reset, Save as template without draft mutation, stale owner/confirmation
  guards, and narrow enlarged German/Arabic layouts.
- Provider query literal isolation, supported-field refusals, UTC boundaries,
  bounded pages/bytes, duplicate/malformed results, continuation ownership,
  membership races, account retirement and cancellation.
- EWS contradictory exhausted totals become estimates. Core refuses an exact
  complete result whose total differs from its row count. Gmail estimates and
  Graph unknown totals are labeled honestly in the UI.
- Search opens a result outside the loaded mailbox page through the existing
  guarded reader without mutating flags or membership.

## Environment and resolved failures

The SDK archive was verified against the published SHA-256. Dart's package HTTP
requests stalled in this workspace; the exact hosted archives from the existing
lockfiles were fetched with curl, checksum-verified, and resolved offline. No
repository dependency versions or lockfile entries were changed.

Flutter's default cloud-environment detection attempted a metadata probe that
automatic approval review blocked. All subsequent Flutter runs use the SDK's
supported `CI=true` short circuit, which disables that probe. The sandbox also
requires an explicitly created writable `TMPDIR`; initial test startup failed
before any cases ran until that variable was supplied. Declared real assets were
hydrated from the repository for widget tests. SQLite's normal pinned native
library hook succeeded; no system-library or source override was used.

The first full store run found 15 historical migration-fixture assumptions
about schema 20. Fixtures now reconstruct their actual historical structures
and compare original columns while admitting only the new additive schema-21
objects. The final complete store run is green. An existing Quick Text focus
regression exposed by the expanded settings UI was fixed and retested. The final
independent review found the EWS count contradiction; its regressions and full
core/transport reruns are included above.

## Reproduction

Use the pinned Flutter SDK, run `flutter pub get` (or `flutter pub get --offline`
with the exact cache populated), and create a writable temporary directory.
In this workspace, tests used these environment variables:

```bash
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true
export TMPDIR=/workspace/scratch/563da1ee84d9/test-tmp
export PUB_CACHE=/workspace/scratch/563da1ee84d9/toolchains/pub-cache
```

`flutter` and `dart` below refer to the pinned SDK executables. On another
machine, use equivalent writable temporary/cache paths.

### Mail core

Working directory: `packages/quds_mail_core`.

```bash
dart test --concurrency=4 --reporter expanded
```

### Mail SQLite store

Working directory: `packages/quds_mail_store`.

```bash
dart test --concurrency=4 --reporter expanded
```

### Mail transport, native

Working directory: `packages/quds_mail_transport`.

```bash
dart test --reporter expanded
```

### Mail transport, browser boundary

Working directory: `packages/quds_mail_transport`.

```bash
dart test --platform node test/ews_unsupported_test.dart test/ews_configuration_test.dart test/unsupported_test.dart test/cloud_unsupported_test.dart --reporter expanded
```

### Studio composition and recovery

Working directory: `packages/quds_office_editor/example`.

```bash
flutter test --no-pub test/studio_mail_compose*_test.dart test/studio_mail_draft*_test.dart test/studio_mail_outbox*_test.dart test/studio_mail_attachment*_test.dart test/studio_mail_recipients_test.dart test/studio_mail_reply_test.dart test/studio_mail_forward_test.dart test/studio_mail_threading_test.dart test/studio_mail_sender_templates_test.dart test/studio_mail_identity_templates_ui_test.dart --reporter expanded
```

### Studio search and Exchange

Working directory: `packages/quds_office_editor/example`.

```bash
flutter test --no-pub --reporter expanded test/studio_mail_provider_search_test.dart test/studio_mail_provider_search_dialog_test.dart test/studio_mail_server_search_dialog_test.dart test/studio_mail_ews_test.dart
```

### Studio native and Outbox alias hosts

Working directory: `packages/quds_office_editor/example`.

```bash
flutter test --no-pub --reporter expanded test/studio_mail_test.dart test/studio_mail_outbox_host_test.dart
```

### Studio Gmail and Microsoft 365

Working directory: `packages/quds_office_editor/example`.

```bash
flutter test --no-pub --reporter expanded test/studio_mail_cloud_test.dart
```

### Studio final template/RTL UI

Working directory: `packages/quds_office_editor/example`.

```bash
flutter test --no-pub --reporter expanded test/studio_mail_identity_templates_ui_test.dart
```

### Studio final search feedback

Working directory: `packages/quds_office_editor/example`.

```bash
flutter test --no-pub --reporter expanded test/studio_mail_provider_search_dialog_test.dart
```

## Remaining acceptance gates

This is source and local fixture qualification. New search adapters still need
disposable live-account acceptance. SMTP aliases remain subject to provider
permission; EWS/Gmail/Graph alias submission is deliberately not enabled.
Installed macOS/Windows/Linux/mobile behavior, browser SQLite quota/reload/Web
Locks, background execution, signed binaries and release qualification are not
established by these tests. The optional browser tests cover transport boundaries,
not full browser mail persistence. No real mail was sent during this work.
