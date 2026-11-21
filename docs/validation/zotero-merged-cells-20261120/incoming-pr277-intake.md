# Zotero continuation: reconciled incoming source

## Scope and baseline

Before Zotero feature edits, this continuation reconciled the captured fork and
upstream work against `c954d00d2fc85604ae394674bca91ea8a1dede0e`.
This is a bounded source intake, not an assertion about later concurrent pushes.
The compact [receipt](intake.json) records exact heads, outcomes and independently
recomputed historical-equivalence proofs. No GitHub Actions, workflow, check,
status or queue endpoint was queried or awaited.

| Captured source | Heads |
| --- | ---: |
| Fork branches | 37 |
| Fork PR heads | 271 |
| Upstream branches | 4 |
| Upstream PR heads | 4 |
| Total | 316 |

Initially 286 references were ancestors and 30 references pointed at 20 distinct
nonancestor heads. Fourteen of those heads were already represented in main:
13 have identical complete Git trees to landed ancestor commits; the ODT head
`c34945761e7991f5fe49037d79529acdd260b31c` matches its landed replacement
`2c47165d01d01cc883135a434ac9f6591ce6e770` on all 37 changed paths. These checks
were recomputed locally; old product patches were not replayed.

## Integrated captured work

| Branch | Captured head |
| --- | --- |
| `codex/word-vba-measurements-20261120` | `4d0086aba52fc804424145d8eabe3c4c1c10f201` |
| `codex/word-vba-unit-conversions-20261120` | `e08635b3f21c60ad21888821050dc97c2dbf7086` |
| `work/mail-bulk-actions-20261120` | `69ab514b57a4d6d4db062d802eb853c2691d80fe` |
| `work/mail-bulk-flags-20261120` | `0cc6316c61efd8b39a9cb0cfed6b2879f7865d48` |

The first Word head already includes PR #271 at
`dd8e73a7d6252b336b2e7a437c4931addc42d491`. The Mail bulk-flags head has the
same complete tree as `d33875709546a323c786f1a0ec487e7ccdd1c03a` (the bulk-actions
parent); its merge preserves that parallel history without another content change.
All four captured heads are actual merge ancestors of the integrated result.
There are now 293 ancestor references, 23 references covered by the 14 verified
historical replacements, and zero uncovered captured references.

### Word overlap resolution

The combined source retains the named-argument checker and once-only evaluator
from the unit-conversions branch, including its bounded binary64 arithmetic and
exact round-trip-checked native-grid normalization. The independent
`office_vba_word_unit_conversions_*` suites and their BAS remain available.
The first measurement branch's original compiler/integration suites, portable
driver and BAS are preserved under `*_positional_*` names; imports and fixture
paths point to those preserved originals. No original regression assertion was
removed. Current usage documentation includes named calls, explicit `CLng`
rounding and all three examples.

The first executed run found an error in an incoming test fixture: the
nonnumeric-Variant test declared its result variable after an executable
assignment, so the existing declaration-order guard prevented it from reaching
the intended numeric check. The fixture now declares both variables first;
the expected `vba_type_error` assertion is unchanged for all eight functions.
Production behavior was not weakened to accommodate the fixture.

### Temporary workflow

The retained maintenance head `332d7b26a320ca560f4f2214e1e63da9392269ab`
changes only a matrix line in a deliberately retired temporary golden workflow.
Existing merge `30c8401d6c6083737c2bdb55dd08e5aa03162aff` has main's exact tree
and preserves that maintenance head as a parent. This continuation retains the
workflow deletion. Its history remains reachable through the incoming branches.

### Mail scope

The captured Mail change adds a bounded foreground bulk flag coordinator and
its independent test suite. It assigns explicit read/unread/flag/unflag states,
retains confirmed/failed/uncertain/unattempted outcomes, and stops subsequent
dispatch after an uncertain outcome. This intake does not advertise unfinished
Mail UI work from later branches.

## Local qualification

The actual Flutter 3.47.8 / Dart 3.13.7 SDK and the workspace's locked dependencies
are used. An initial test-runner startup failed before running tests because the
sandbox has no `/tmp`; a writable workspace `TMPDIR` resolved that environment
issue. The locked `test` 1.31.1 runner is invoked directly with the real package
configuration, `--compiler=source` and `--concurrency=1`.

The first eight-file Word run completed 693 cases: 685 passed and eight
exercised the malformed fixture described above. After the declaration-order
correction, the incoming baseline completed **724 passing cases**: 693 Word and
31 Mail. The [incoming receipt](incoming-validation.json) binds that result to
published source `835b8019cbb873c72424e63d4df292174edd3c3e` and preserves the
original failure, unchanged assertions and corrected acceptance. Formatting
completed on the 12 changed Dart files.

The later current-main checkpoint `180399f99a3898501ab1959e3b845150d7da59fd`
retains main `e975cec13b289fe067ef406cd3044701ecc44744` as its second parent.
Its expanded 11-suite Word/Mail run completed **928 passing cases**, preserving
canonical, named and positional measurement fixtures and main's large-scalar
regression. Final current-main engine/editor runs completed 495 engine passes
and 378 editor passes plus eight existing image-only layout skips. All 257
Zotero editor cases executed and passed. The three final processes therefore
record **1,801 passes and eight skips**, with successful terminal events, exit
code 0 and zero failures or errors. All 769 engine and 904 editor captured input
hashes remained stable before/after execution.

The earlier `6a00886f2c7f2ceddf859fcc1ccb99fbfcbb989a` editor run also had 378
passes and eight skips; its initial tally incorrectly included skipped success
events as passes. The [continuation report](README.md) identifies those fixtures
and the corrected classification. Publication targets remote `main` through
the continuation pull request.
Repeated populations are not added together, and historical incoming branch
records retain their original attribution.
