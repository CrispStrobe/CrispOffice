# Frozen combined-source static validation

This gate validates `6ba219a03a9933eded77980f9d7cdbd118183ee1` against original main `a5b4eb7d329b0700768b1fc72bb63cf58a9f5cd6`. It includes all 58 added or modified Dart paths across incoming Mail, Word VBA, and Zotero recovery.

## Results

- `dart analyze --fatal-infos` on all 58 explicit paths: **passed**, exit 0, no issues found.
- `dart format --output=none --set-exit-if-changed` on those paths: **failed**, exit 1, exactly one file requires formatting: `packages/quds_office_editor/example/test/studio_mail_flag_journal_test.dart`.
- No source files were modified by these checks.
- Before/after HEAD is the expected frozen commit; hashes are stable for all 2,730 tracked Dart/source configuration files, 34 dependency/configuration files, and 3 toolchain metadata files in the declared scope.

The formatting difference is in incoming Mail membership test additions. The original main version of the file passes the same formatter (exit 0); the frozen combined version fails (exit 1). The file's latest change at the frozen commit is `cd6aa8044a7c6fb0738758a4038cdbd626b5721d`. This is an incoming Mail formatting issue, not an inherited original-main failure. `format-baseline-comparison.json` records the exact revision reads and read-only stdin commands, and `frozen-combined-format.diff` records the formatting difference.

## Evidence

`commands.json` and `commands.sh` record exact commands and working directory. `analyze.run.json` and `format.run.json` record timing, exit codes, HEAD, and raw stdout/stderr hashes. Each command's stdout and stderr are stored separately. `source-hashes-before.json`/`source-hashes-after.json`, corresponding dependency and toolchain snapshots, and `state-before.json`/`state-after.json` prove stability. `provenance.json` documents scope, Dart SDK version, and environment setup. `summary.json` is the compact machine-readable result.

This gate used the provided task-local toolchain environment. It did not run Flutter tests, wait on CI, alter source, commit, or perform remote actions. Later incoming changes require a separate delta gate rather than overwriting these results.

## Final-state coverage after late Mail intake

The separate `late-918e/` gate validates all 13 late Dart changes at `918e7dd12e66b79e75082a41c250887a92db0d4e`; fatal-info analysis and read-only formatting both pass. It resolves the one earlier Mail formatting failure without overwriting that failure's evidence. The two gates cover all **67 unique Dart files** in the complete original-main-to-final diff (58 + 13 - 4 overlaps), with no uncovered paths. The remaining 54 first-gate paths are byte-identical at final source; dependency and toolchain snapshots are unchanged between gates. `final-coverage.json` records the exact coverage union, chosen evidence stage for each path, and matching source hashes.
