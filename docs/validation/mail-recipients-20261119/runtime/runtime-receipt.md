# Runtime qualification — 2026-11-19

## Installed workspace runtimes

- Pinned Flutter 3.47.8 from official tag `737ba8f885dc774b53b442759999a312c9461e4e` at `/workspace/scratch/32e3793609d8/runtime/flutter`.
- Bundled Dart 3.13.7 at `runtime/flutter/bin/cache/dart-sdk/bin/dart`.
- Flutter tester / patched Linux SDK artifacts downloaded successfully.
- Standalone Dart 3.14.1 is also available at `runtime/dart-sdk/bin/dart`; qualification below uses the pinned Flutter bundled Dart 3.13.7.
- `source /workspace/scratch/32e3793609d8/runtime/env.sh` configures pinned PATH, workspace PUB_CACHE, workspace TMPDIR, CI, and suppressed Flutter analytics. TMPDIR is required because `/tmp` is absent in this executor.

## Full workspace gate

`flutter pub get` was interrupted while resolving dependencies. The executor tool returned: `Unified exec process failed: network approval was cancelled before a decision was returned`.

No mirror, escalation, or network retry was used to bypass that boundary. A strictly offline, lock-preserving attempt:

```sh
flutter --no-version-check pub get --offline --enforce-lockfile
```

exited 69 because `flutter_lints` was absent from cache. No repository package config or tracked lockfile change was produced. Full Flutter/widget/MIME/engine suites and full workspace analysis remain unexecuted. Full engine testing also needs uncached `image` and `characters` packages, and archive ^4.0.0 while cached archive is 3.6.1.

Logs: `flutter_pub_get.log`, `flutter_pub_get_offline.log` in this directory.

## Focused offline source qualification

A normal standalone pub package at `runtime/core-validation` depends by path on the actual repository `packages/quds_mail_core`, with dev dependency `test: 1.31.1`. `dart pub get --offline` succeeded using cached packages and generated its own package config. No workspace config was fabricated, no repository manifest was altered, and the tested source was not copied or patched.

```sh
cd /workspace/scratch/32e3793609d8/runtime/core-validation
source /workspace/scratch/32e3793609d8/runtime/env.sh
dart test /workspace/scratch/32e3793609d8/quds_office_suite/packages/quds_mail_core/test --reporter expanded
```

Result: **54 tests passed**, exit 0. Log: `mail_core_offline_test.log`.

Core source Git tree: `2860c22f05dacc4cdeb18552e419c01e9d9b6862`.

Qualification limit: this harness uses a permitted cached resolution, not the repository's full locked dependency graph. Cached `crypto` is 3.0.7 versus repository lock 3.0.8; cached analyzer is 10.1.0 versus lock 13.3.0. `test` 1.31.1, `test_api` 0.7.12, and `test_core` 0.6.18 match the lock. This validates the unchanged core source under the documented harness and does not close the full workspace gate or qualify the new Flutter composition/provider/UI changes.

GitHub Actions were not used.
