# Canonical Word follow-up qualification

Qualified source: `a379ecc455890032906098b6cf58e17504581ed0`.
Tree: `0b083a5019ca07503765a649e4ff5c9712f705c6`.

This source merges canonical main `c1678ade3b5b9fd13088e94d752fd17fd14eb3e8`
into the published reconciliation head
`1c7b0c121ed476090def463d9bc59f5c8a3462b7`. Both parents are retained. The merge
was clean and preserves the extra sorting/formatting/grid undo regression.
CrispCloud main `2c373371973b2506fc4fc03e599ef093d14a4be1` now imports this
canonical Word work, so the follow-up keeps the combined source ownership
coherent when that application commit is integrated.

## Source scope

Four Word engine files change: the document model records imported duplicate
content-control IDs; bookmark handling repairs unpaired imported endpoints;
content-control validation permits only the duplicate counts present in the
source; and deserialization reads block-level bookmarks and tolerant finite
measurements. The modified bookmark fidelity suite and two new Word import
suites accompany those changes. The only other incoming file is the README.
`source-reconciliation.json` records the exact files and ancestry.

The source does not include open canonical PRs #9 (symbol characters), #10
(text-box nesting), or #11 (media deduplication). No dependency manifest or
package lock changed in this follow-up.

## Executed qualification

All commands ran on native Linux with Flutter 3.47.8 and Dart 3.13.7. Exact
commands, working directories, start/end times, exit codes and raw-log hashes
are retained in the individual receipts.

| Gate | Suites | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Focused Word engine | 9 | 117 | 0 | 0 |
| Existing worksheet/presentation history cohort | 10 | 115 | 0 | 0 |
| Total | 19 | 232 | 0 | 0 |

The Word cohort covers the changed import behavior, bookmark ranges and
copying, note-story edits, rich content controls, auxiliary stories, repeated
save/reimport and command-line mutation guards. The complete earlier
ten-suite editor cohort was repeated, including the combined sort/style/grid
regression, worksheet ownership, pending edits and slide notes.

Strict `dart analyze --fatal-infos` passed with no issues for all four changed
engine files, all nine selected Word test files, the Office controller and
the sort-history regression. Every gate exited zero.

All **2,955 captured source/generated input hashes** remained unchanged across
the gates, and source HEAD and the worktree stayed unchanged and clean. The
inventory includes all tracked files outside historical `docs/evidence/`,
plus the resolved workspace package configuration, package graph and lockfile.
Before/after inventories and dependency snapshots are retained as gzip files.
`runtime.json` identifies the SDK and launcher bytes used.

## Retained initial launch failure

Two initial concurrent Flutter/Dart wrapper launches collided on the shared
`engine.stamp.tmp.17` file before either test runner started. Their exit-1
receipts and raw logs are retained under `attempt-1-bootstrap/`; no test cases
ran in those attempts. No source correction was needed. The successful retry
used the direct pinned Dart SDK executable for the engine and one Flutter
launcher for the editor. The successful analysis run is retained separately.

## Qualification boundary

These are focused native Linux Dart/Flutter tests and static analysis. They do
not establish browser, live-cloud, external schema/render, whole-editor-suite
or whole-application qualification. The earlier 115-test receipt remains bound
to `cb42ef232e5794ac4c147ef1992133cf8710ab01`; the separate CrispCloud 790-test
cohort remains bound to `331981649872e363253aef13f57a638e5747b8e5`. Neither old
receipt is relabelled as a run on this new source.
