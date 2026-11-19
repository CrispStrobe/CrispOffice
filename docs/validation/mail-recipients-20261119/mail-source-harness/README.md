# Focused offline Studio mail qualification

**57 test cases passed**, exit 0, using the pinned Flutter 3.47.8 bundled Dart 3.13.7. The test runner loaded the original production files in the repository; those files were neither copied nor replaced with alternate implementations.

| Test source | Retained declarations | Omitted declarations | Executed cases |
| --- | ---: | ---: | ---: |
| `studio_mail_recipients_test.dart` | 8 | 4 | 8 |
| `studio_mail_reply_test.dart` | 22 | 6 | 33 |
| `studio_mail_threading_test.dart` | 16 | 8 | 16 |
| Total | 46 | 18 | 57 |

The reply source expands parameterized declarations into additional cases. This is a subset execution, not a claim that the three complete Flutter test files passed.

## Exact adaptations

`prepare_mail_tests.dart` uses the Dart analyzer AST to identify whole `test(...)` expression statements. It removes every entire declaration that contains `buildStudioMailMessage` or `QudsMimeCodec`. It does not remove individual assertions from retained tests or provide MIME stubs.

The only other changes are imports:

- `package:flutter_test/flutter_test.dart` becomes `package:test/test.dart`.
- Studio package imports become absolute file URIs to the original production files.
- Unavailable MIME/submission/enough_mail imports are removed after every dependent test declaration has been omitted.

The original source snapshots, transformed files, and unified diffs are preserved next to this report. `provenance.json` records every retained and omitted declaration name, original source line ranges for omissions, SHA-256 values, original Git blob hashes, and the production source hashes. Post-run checks confirmed that all four production files and all three original test files matched their pre-run hashes.

The retained cases exercise recipient groups, deduplication, immutable snapshots, aggregate recipient and input limits, complete mailbox limits, plain-text reply and forwarding behavior, Reply-To precedence, reply-all self exclusion, participant role deduplication, Bcc exclusion, invalid-source rejection, source scanning bounds, unsupported HTML-only quotation, thread ancestry parsing, and ancestry length limits.

## Runtime and dependency scope

The separate pub package at `/workspace/scratch/32e3793609d8/runtime/core-validation` resolves a normal path dependency on the repository's `quds_mail_core` using `dart pub get --offline`. Its `pubspec.yaml` and `pubspec.lock` are preserved here. No repository package configuration was fabricated and no tracked dependency manifest or lockfile was changed for this harness.

The cached independent graph is not the complete repository lock graph. It uses crypto 3.0.7 and analyzer 10.1.0 versus repository-locked 3.0.8 and 13.3.0; test 1.31.1, test_api 0.7.12, and test_core 0.6.18 match the repository lock. The actual source is compiled and exercised under this documented cached graph.

MIME resolution was also attempted strictly offline with normal path dependencies on `enough_mail` and `quds_mail_mime`; it failed because `synchronized` is not cached. Other required enough_mail packages are also absent. The earlier full workspace `flutter pub get` was interrupted by the executor reporting that network approval was cancelled before a decision was returned; no network retry or alternate mirror was used to bypass it.

Consequently this run does not qualify MIME serialization, SMTP/EWS/Gmail/Graph provider integration, Flutter composer widgets, or the full workspace dependency graph. Those complete suites remain pending.

## Commands and result

```sh
cd /workspace/scratch/32e3793609d8/runtime/core-validation
source /workspace/scratch/32e3793609d8/runtime/env.sh
dart run prepare_mail_tests.dart
dart test \
  /workspace/scratch/32e3793609d8/validation/mail-source-harness/studio_mail_recipients_offline_test.dart \
  /workspace/scratch/32e3793609d8/validation/mail-source-harness/studio_mail_reply_offline_test.dart \
  /workspace/scratch/32e3793609d8/validation/mail-source-harness/studio_mail_threading_offline_test.dart \
  --reporter expanded --concurrency=1
```

`test.log` is the final passing run after the final formatter normalization. `receipt.json` provides the compact final counts, source verification, dependency differences, and evidence hashes. `pre-format-test.log` and `pre-format-provenance.json` preserve the earlier passing pre-format snapshot. `first-pass-test.log` also passed 57 cases; the final run refreshed the source provenance after a new MIME-only test was added and explicitly omitted. `setup_attempt.log` records an earlier harness invocation before its scratch test files had finished being generated; no production tests ran in that setup attempt.

GitHub Actions were not used.
