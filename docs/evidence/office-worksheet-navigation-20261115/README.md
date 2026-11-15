# Worksheet navigation evidence — 15 November 2026

## Accepted implementation

All five positive gates use exact source
`e6da5be3a7e085dc200e35d6300161658179463c` with 2,096 unchanged inputs.
The shared input-manifest SHA-256 is
`4020e15ff1032c6d6e45e6ea9ae8f94dfc52d1dc6e0afcadb1e2f90fc052c8f7`.
Flutter 3.47.8 / Dart 3.13.7 ran the native tests.

| Gate | Outcome |
| --- | --- |
| `canonical-positive` | 148 passing tests: new navigation plus relevant draft, rename, worksheet history, sorting and Word find/replace coverage |
| `example-positive` | 9 passing tests: 8 new Studio navigation cases and existing workspace smoke |
| `shared-find-positive` | 3 passing shared Word/Slide find and shortcut controls |
| `engine-analysis` | Entire engine analyzer, fatal infos enabled: no issues |
| `scoped-analysis` | Seven changed canonical/example files: no issues |

Total: **160 passing tests**. `acceptance.json` binds the cohorts and proves
that both new navigation test files match the corrected baseline byte for byte.
Each gate retains command, source tree, runtime hashes, generated dependency
snapshots, input manifest and compressed log. This does not claim physical-device
acceptance or independent Office rendering. Hosted CI and app results are separate.

## Baseline

`canonical-baseline` records the original production source at
`2d33a9213e760197557fb4fabcb422446f15227a` with the new regression tests:
**10 passed, 22 failed** across 32 cases. Its 2,095 inputs stayed unchanged.
Those same 32 cases all pass on the implementation.

`canonical-baseline-initial` retains the first diagnostic attempt (8 passed,
24 failed). Two extra failures came from comparing cell-reference objects by
identity. Three assertions were corrected to compare A1 addresses; production
source did not change between attempts. Only the corrected baseline supplies
the behavior witness.

These are new executions. Results mentioned in the interrupted 14 November
conversation are not relabeled as recovered evidence.
