# Late Mail delta static validation

This read-only gate validates the 13 added or modified Dart paths from `6ba219a03a9933eded77980f9d7cdbd118183ee1` to `918e7dd12e66b79e75082a41c250887a92db0d4e`.

- `dart analyze --fatal-infos`: passed, exit 0, no issues found.
- `dart format --output=none --set-exit-if-changed`: passed, exit 0, 13 files checked and zero changes.
- HEAD, all 2,731 tracked Dart/source configuration hashes, 34 dependency/configuration hashes, and 3 toolchain metadata hashes stayed stable across this gate.
- The updated `studio_mail_flag_journal_test.dart` now passes formatting. The initial frozen-source failure remains preserved in the parent evidence directory.

Exact commands, raw stdout/stderr, timestamps, exit codes, declared snapshot scopes, and before/after hashes are saved alongside this README. No source files were modified, no Flutter tests were run, and no commit or remote action was performed by this gate.

The two static gates cover exactly all **67 unique Dart files** changed from original main to final source: 58 first-gate files plus 13 late-gate files minus 4 overlaps. The 54 first-gate files not revisited are byte-identical at final source, and dependency/toolchain snapshots are identical between gates. See `../final-coverage.json` for per-path evidence selection and hashes.
