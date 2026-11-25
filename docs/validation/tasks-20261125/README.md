# Tasks foundation validation — 25 November 2026

## Runtime

Checks use the official **Dart 3.13.7** runtime from the pinned Flutter 3.47.8
Linux archive. The archive was streamed, SHA-256 verified, and only the Dart
SDK, Flutter package sources and cache metadata needed for pure-Dart checks
were extracted. No Flutter engine/tester binary or SDK git history is claimed.

- Archive: `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz`
- Archive SHA-256: `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`
- Dart executable SHA-256: `01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb`
- Hosted packages restored from the existing workspace/tool lockfiles and their
  published hashes; `dart pub get --offline --enforce-lockfile` passed on the
  initial checkout. New workspace entries resolved offline without changing
  `pubspec.lock`.

The standard `dart test` invocation entered unrelated workspace build hooks and
did not complete during the initial attempt. It was interrupted. The same
installed **test 1.31.1** runner was then invoked directly using the generated
workspace package configuration, and the actual suites completed. This avoids
claiming a full workspace/native-assets build. All packages under test here are
pure Dart or native loopback fixtures without a Flutter engine.

Equivalent test invocation from an affected package directory:

```sh
dart --packages=../../.dart_tool/package_config.json \
  "$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart" \
  test/cloud_oauth_test.dart test/cloud_oauth_loopback_test.dart \
  --reporter expanded
```

## Microsoft task consent checkpoint

From `packages/quds_mail_transport`:

- `dart analyze lib/src/cloud/configuration.dart test/cloud_oauth_test.dart`:
  **passed, no issues**.
- OAuth and native loopback suites above: **37 passed**.
- Formatting of both changed Dart files: **passed**.
- `git diff --check`: **passed**.

New cases cover unchanged mail scopes, explicit task opt-in, rejection for
Gmail, authorization URL scopes, insufficient task grants, refresh scope
retention and downgraded-grant credential invalidation. Existing PKCE, refresh,
callback ownership and cancellation regressions ran alongside them.

This validates source behavior and local HTTP fixtures. It does not certify
Microsoft tenant consent, live task interoperability, OS credential storage,
desktop Tasks UI, or background synchronization.

## Portable task core checkpoint

From `packages/quds_tasks_core`, strict `dart analyze` and formatting passed.
The direct installed runner (same invocation pattern, no explicit test paths)
executed **25 passing tests**. `dart compile js` of
`test/compile/portable_import.dart`, followed by Node execution, passed and
exercised real reconciliation through the public package import.

Coverage includes immutable/scoped identities and pages, valid civil dates,
wall-time equality, sparse null clearing, disjoint and competing changes,
local-revision fencing, remote deletion against local edits, and conservative
local deletion when remote versions or unknown payloads differ. Coupled-field
regressions cover reopening against a remote completion timestamp and reversed
start/due dates, without guessed conversions between date kinds or zones. These
tests validate an in-memory reconciliation plan, not durable synchronization.

## Microsoft Graph adapter checkpoint

From `packages/quds_tasks_graph`, strict analysis and formatting passed. The
direct installed runner executed **35 passing tests**. JavaScript compilation
of `test/compile/portable_import.dart` and execution in Node both passed.

Fake-transport tests cover scoped cursors and credential origin, list/task
delta pagination, empty continuations, final-event handling for repeated IDs,
tombstones, sparse and explicit-clear writes, date/HTML preservation, fresh
recurrence checks before completion changes, operation-marker recovery,
authentication refresh, throttling, expired cursors, uncertain writes, and
byte/item limits. Native policy tests exercise refusal before unsafe dispatch.

No live Graph request was made. Conditional-write semantics, native network
behavior against Microsoft, personal/work account consent, extension expansion,
and To Do date-only display remain acceptance gates. Protected-list admission,
durable state and token persistence remain host integration responsibilities.
