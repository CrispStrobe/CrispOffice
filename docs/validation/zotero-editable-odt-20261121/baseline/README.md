# PR #323 baseline qualification

Genuine Flutter 3.47.8 / Dart 3.13.7, locked official dependencies.

- Eight prescribed engine suites: **219 passed, 0 failed, 0 skipped**.
- Four prescribed editor suites: **93 passed, 0 failed, 0 skipped**.
- Fatal-info analysis of all four #323 files: clean after five automatic string interpolation lint fixes in the merged-table test.
- Final formatting check: four files checked, zero changes.
- No reader behavior changes were required.

The first normal `dart test` launcher emitted no test events and was interrupted (exit 130). The exact locked test runner entry point was then executed with the actual workspace package configuration under the same SDK and completed successfully. Both attempts are retained.

`receipt.json` includes exact commands, suite paths, actual results, source/log hashes, and scope limits. `source-initial.json` and `source-final.json` expose concurrent source changes; they do not claim a sealed source run. Editor verification completed before the concurrent new ODT writer integration. Final combined writer qualification remains the parent task.
