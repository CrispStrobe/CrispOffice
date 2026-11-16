# Fresh engine validation — 16 November 2026

**Passed against source `6f87a4e849f9dc172fea7a0e57d1d9072d99efe3`.**
The run started at **14:52:57 UTC** and completed at **14:57:42 UTC**.
This record covers engine and optional-provider contract checks. Editor tests,
browser acceptance, and a fresh native/Wasm Harper build are separate scopes.

## Results

| Check | Observed result |
| --- | --- |
| Full engine `lib test tool` analysis | Passed with `--fatal-infos` |
| German proofing | **49 tests passed**, including 11 newly added regressions |
| Compiled German JavaScript | **10 checks passed** under Node |
| Pinned dictionary regeneration | All **18 generated files** matched exactly |
| German hyphenation regeneration | Exact output from **36,709** pinned patterns |
| Hyphenation, bidi, Word layout, DOCX and PDF regression group | **231 tests passed**, no skips |
| Incoming ODS, Zotero and comment-style regression group | **496 tests passed**, no skips |
| Harper Dart library and tests analysis | Passed with `--fatal-infos` |
| Harper provider contract | **8 tests passed** |
| Harper native lifecycle/availability guards | **3 tests passed, 1 real-library test skipped** because no native library was built in this environment |

The two large engine groups include overlapping tests. Their totals are not a
unique repository-wide count. The exact file lists, working directories,
commands, durations, exit codes and log hashes are in [receipt.json](receipt.json).

## Bound inputs

All **4,273 recorded repository files**, **3,400 cached dependency source/configuration
files**, and **36 runtime/configuration inputs** had identical before/after
hashes. The tracked working tree was clean. Compressed original manifests are
retained beside the receipt. The compiled German JavaScript hash is recorded;
execution under Node does not establish real-browser delivery or interaction.

The official Dart 3.13.7 SDK archive and its SHA-256 are recorded in
[dart-runtime.json](dart-runtime.json). The exact dependency harness,
resolved lock and package configuration are retained. The harness resolved
pure-Dart engine and Harper dependencies; this run does **not** claim that it
resolved the complete Flutter workspace.

The pinned dictionary download matched SHA-256
`55b457fac8e322146853f45bbda59046a55496a3e3deb32d3a88feb908eca243`.
The current model/data sources were not replaced, no new dependencies were
added to the product manifests, and the experimental German model was neither
enabled nor rerun.

## Preserved first attempt

[initial-harness-attempt.tar.gz](initial-harness-attempt.tar.gz) contains the
first attempt's complete logs, receipt, runner and input manifests. The fixture
tests initially ran from the separate harness directory; relative paths to
document fixtures and fonts therefore failed. The final runner executes each
test group from its package directory using the same resolved test runner.
Product source did not change between the attempts. The final passing receipt
does not hide or count the failed attempt.

## Reproduction

Use an isolated working directory with this layout:

- `quds_office_suite/`: checkout of the exact source commit above;
- `runtime/dart-sdk/`: Dart 3.13.7 from the recorded official archive;
- `runtime/pub-cache/`: Pub cache;
- `runtime/engine-env/`: copy `harness-pubspec.yaml` as `pubspec.yaml` and
  `harness-pubspec.lock` as `pubspec.lock`;
- `evidence/core/run-validation.py`: copy the exact retained runner here.

Set `PUB_CACHE` to the absolute cache directory, resolve the harness with
`dart pub get --enforce-lockfile`, and copy its package configuration to the
checkout's `.dart_tool/package_config.json`, converting each relative
`rootUri` to an absolute URI against the original configuration location.
Do not reuse the captured absolute paths on another machine. Run
`python3 evidence/core/run-validation.py` from the isolated working directory.
The runner verifies the source revision and clean tracked state, captures
inputs, runs the checks and compares the final hashes. Node and Python are
also required. Place any prior output elsewhere before a rerun.

No GitHub Actions, workflow, check-run or commit-status endpoints were queried
or waited for during this continuation.
