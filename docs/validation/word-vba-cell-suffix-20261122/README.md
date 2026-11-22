# Word VBA cell suffix qualification

## Implemented capability

Direct `Cell.Range.InsertAfter` now compiles to the dedicated native operation
`docx.tableCellRangeInsertAfter`. It appends text inside an existing ordinary,
single-paragraph, unmerged main-story table cell. Supported source forms include
typed Table/Cell/Range aliases, named `Text` arguments, bare/parenthesized/`Call`
syntax, nested `With`, and optional or named `ByVal Range` helper arguments.
Receivers and text expressions are evaluated once, in source order.

The native operation preserves original runs, sparse and zero-width metadata,
table ownership and protection checks. Appended text inherits the last text
character's formatting, or the retained empty-run/paragraph-mark fallback for
empty cells. Reusing the same range for formatting includes appended text.
Execution, recording, replay and rollback use the existing atomic macro path.

The alias checker now follows the complete possible-source graph. A direct-cell
origin can reach a cycle without being incorrectly rejected. Every terminal
source must be valid; an unbound, noncell or rootless-cycle origin is rejected.
The same correction applies to existing direct cell-range text assignment.

See the [runnable BAS example](../../../packages/quds_office_engine/example/macros/word_table_suffix.bas),
[user guide](../../VBA_WORD_MACROS.md), [detailed contract](../../vba-word-macros-details.md)
and [73-case conformance corpus](../../../packages/quds_office_engine/test/fixtures/vba_conformance/word_cell_suffix_v1.json).

## Intake and incremental remote saves

Starting main: `b2bba1638924237435460e4238d4bd98c407fc3a`.
[Initial intake](intake.json) verified all 29 fork topic tips, four upstream branch
tips and the latest 100 PR heads (#269–#368) as ancestors of that main commit.
There were no open PRs. Fork branches, upstream branches and PR heads were fetched.

Work is saved on `codex/word-vba-range-suffix-20261122`. Each remote update checks
the expected prior head, uses a normal fast-forward, and verifies the uploaded
tree against the local committed tree. The branch is retained after merging.
The documentation-only closure was published through GitHub's API after local
sandbox startup became unavailable; its changed-file scope is checked remotely.

| Remote checkpoint | Saved work |
| --- | --- |
| `251a8124e59ab73c05d257a5cd25dcc9a9288886` | Initial plan and intake record |
| `dbfd9329b685ff34b785d96fad0c865a1750ff9a` | Native suffix operation, source adapter, tests and corpus |
| `dc5827d86270ce9f88f1fb7b06c60c2b29b12222` | Alias graph correction, documentation and future workflow coverage |
| `ab9d9c0019b2168d3d5877e86aa54c94a40efe2d` | Incoming Mail and Zotero source histories |
| `2f8562cda86fc150347672dc6e1c1cb68824d3d7` | Missing Mail synchronization contract and regressions |
| `61cee1c16825733ccac1370e66b3ee7f46dabcc9` | Receipt-preserving Mail projection guards |
| `5326ad63426a604132175d756ebebf8bc67cd0af` | Completed Mail implementation reconciled with latest main and independent tests |
| `ab7fb01999efab093f2d5c81c9c328bb2c16a41c` | Destination folder metadata bound and 14 independent projection safety tests |
| `28b53ec8ac1151d86af5d18f6d3a22c28df857b0` | Sealed Word/Zotero evidence and intake archive |
| `d4317dcc1ecc6c7b70a1773cc121f5639ad99428` | Late Mail clock guard and overlapping cache safeguards reconciled |

Concurrent work appeared after the initial intake. Captured Zotero changes
include damaged citation unlinking and native ODT note starts; main then advanced
to `b38f2e38369855056eb9e23792f83fd1ab86ea24` through PR #369. Captured Mail work
adds authoritative move identities and null-safe synchronization snapshots.
Those histories are preserved through merge parents, with overlapping repairs
reconciled and both sets of tests retained. The later intake records identify
exact tips rather than assuming branch names are immutable.

No GitHub Actions, check suites or commit statuses were queried or awaited.
Qualification uses local execution; checkpoint commits request `[skip ci]`.

## Publication and qualification boundary

[PR #371](https://github.com/CrispStrobe/quds_office_suite/pull/371) was incorporated
indirectly on 22 November 2026 at 08:48:06 UTC when the concurrent arithmetic
integration included its complete head `d4317dcc1ecc6c7b70a1773cc121f5639ad99428`.
Remote main was subsequently observed at
`8326f191067dac1a3befab81361c5829fee9a35d`, tree
`314702d7cce8d85047db0338e0f7d92b1ac214c3`, following PR #370.
GitHub comparison confirms d431 is an ancestor, with zero commits behind main.

**The complete 141-suite result below qualifies the cell-suffix checkpoint through
d431, not the subsequently changed arithmetic compiler.** The later integration
adds integer division and signed remainder and has its own
[qualification record](../word-vba-integer-arithmetic-20261122/README.md). Its
reported focused arithmetic results do not turn the interrupted combined macro
run into a completed gate.

All 37 branch/upstream tips in the captured intake are ancestors of d431 and
therefore of the observed main. A later 39-tip sweep also found the arithmetic
work (now included), the subsequently created Mail organization branch
`f25c62e38b422598873c3dc3bb638e746dfb53b9` and Mail identity tip
`06b4e747c09851048d0b72a958e9114f7c83cc52`. Both were outside the first observed
main's ancestry. During documentation closure, PR #372 advanced main to
`682ca74fe994eb96a8133c963ae3e5f765023c2e`, tree
`cd91db179b58d29bba860f403b018c6ffa8727b5`, and incorporated the Mail identity tip.
The documentation follow-up preserves that newer main and its qualification
record. The post-intake Mail organization branch remains separate and preserved
remotely. This record does not claim every branch created after the captured
intake was merged.

[Publication summary](publication-summary.json) records the exact accepted scope,
source-continuity verification and remaining execution/storage limitations.

## Accepted Word qualification

The final accepted coverage consists of **all 141 selected macro/VBA test files**.
It combines complete passing files from the initial run with complete replacement
results for every affected file. It does not describe the failed initial run as
a successful monolithic execution.

| Accepted complete suites | Passing executions | Unique suite-path + full-test-name keys |
| --- | ---: | ---: |
| 101 wholly passing original suites | 6,176 | 6,166 |
| 40 suites rechecked in five bounded batches | 1,059 | 1,048 |
| **All 141 suites** | **7,235** | **7,214** |

All adopted suites have zero failures, skips and runner errors. Twenty-one
parameterized executions have duplicate generated names; the archive retains
each execution and the index reports both counts. Strict engine analysis
(`--fatal-infos`) and changed-engine Dart formatting passed. Each broad run
recorded 1,211 stable input hashes.

Before temporary local launcher changes, an independent continuity check at d431
verified all 1,211 successful-recheck inputs byte-for-byte and all 1,208 tracked
inputs against that commit's Git blobs. The canonical input-manifest SHA-256 was
`f26e665b0e749216efc08865f40ff4d1e899d3f371c98488fe771234871d3837`.
This is a historical source-binding check, not a later test rerun or a claim
about the arithmetic compiler now on main.

The initial broad run recorded 6,213 passes and 46 failures. Its 51 error events
were 43 temporary-storage exhaustion events, five dependent teardown failures,
and three diagnostic-position events. Ending the oversized runner released its
temporary kernel files. All 40 affected suites were then rerun in batches of
eight. Two old refusal fixtures were corrected to point to the newly recognized
`InsertAfter` method (columns 3 to 65 and 5 to 67); their expected refusal codes
and source text were unchanged. The entire containing suite passed again.
Engine production inputs were identical between those runs. The initially
failing formatter and superseded portable attempts remain in the evidence.

The independent new corpus contains **73 cases: 27 native plans and 46 positioned
diagnostics**. Its enclosing test file has 84 tests, including metadata, resource
and sequencing checks. Separate checkpoint runs cover native suffix behavior,
source integration and 40 alias-graph cases. These overlapping checks are not
added to the aggregate above.

### VM and JavaScript portability

Both the 73-case corpus and the actual committed `word_table_suffix.bas` execute
successfully under the Dart VM and optimized `dart2js -O2` output running in Node.
The respective VM and JavaScript JSON outputs are byte-identical. Final portable
receipts bind 449 repository/input files and 12 runtime/dependency-receipt hashes at
`ab9d9c0019b2168d3d5877e86aa54c94a40efe2d`, after the incoming ODT source merge.

The BAS driver checks six operations, one committed revision, six recorded and
replayed steps, two additional save/reopen cycles, preserved unrelated parts and
layout, opaque DOCM VBA retention, and rollback after a late failure. Opaque VBA
retention does not mean that an embedded VBA project was executed.

Runtime: Flutter 3.47.8, Dart 3.13.7 and Node 24.22.3. The official SDK archive and
204 Pub dependency archives were hash-verified; locked dependency resolution
left all 36 tracked dependency inputs unchanged. Runtime/source receipts contain
the exact executable and input hashes.

## Incoming integration qualification

Captured Zotero source passed **468 engine, 210 editor and 27 Studio executions**
(705 total) plus scoped strict analysis. Receipts identify their exact source
inputs. Later Mail store changes are qualified separately, rather than inferred
from those earlier Studio results.

Mail reconciliation preserves the optional snapshot repository capability and
legacy repository behavior. Store projection now requires both real retained
browse views, advances both view revisions even when the source is outside its
loaded window, and budgets complete retained destination metadata. A required
nested savepoint prevents optional cache growth from discarding an otherwise
admissible authoritative receipt. Receipt quota and unrelated storage failures
retain outer-transaction rollback. The focused native projection, transition and
migration gate passed all 47 tests before the last clock guard; that historical
run is not added to final-source totals.

### Partial Mail qualification at d431

| Scope | Verified completed subset | Remaining limitation |
| --- | --- | --- |
| Core | 27 complete suites, 629 passes; exact source continuity | Historical d431 source attribution |
| Store | 23 observed VM suites, 635 passes, zero failures/skips | 25 VM suites and the Node-only three-test suite unrun |
| Core/store analysis | Strict analysis clean, exit 0 | No claim about later source edits |
| Transport | One accepted, source-stable cohort: 8 files, 233 passes | Other cohorts need whole-file exclusions/source bridging; 3 JavaScript files unrun |
| Studio | One accepted, source-stable cohort: 8 files, 132 passes | Another 321-pass cohort's source bridge was not sealed; two files failed before load |

The transport attempts logged 573 raw passing cases and one environmental
failure. This is **not** a deduplicated accepted total: the whole failing
`host_store_integration_test.dart` file must be replaced by a successful rerun,
and another cohort observed a temporary launcher change. Studio logged 453 raw
passes across 16 files, with the bridge limitation described above. These raw
counts are not promoted to a sealed final aggregate.

The store's source-compiler retry failed before any test body, with one
`ENOSPC` loader failure. Later transport/Studio retries, Node/COPYUID checks and
remaining scoped checks could not run. Temporary-directory creation and finally
sandbox initialization failed because the shared host exhausted available
storage. An ordinary file-write probe succeeded but directory creation still
failed; it was not treated as a passing test. No privileges, filesystem settings,
SDK source or SDK binaries were changed to bypass the limit.

The original successful and failed Mail logs remain local. **No final Mail
archive or accepted aggregate was created or published.** The summary here is
based on results inspected before sandbox initialization became unavailable.
The existing sealed Word/Zotero archive is already preserved remotely.

## Reproduction and evidence

After installing the pinned SDK and resolving the locked workspace dependencies,
run from the repository root:

```sh
python3 docs/validation/word-vba-cell-suffix-20261122/run_local.py \
  --output /absolute/path/to/local-word-evidence --batch-size 8
```

The script runs all selected files in bounded batches, strict engine analysis,
formatting, JSON test accounting and before/after input hashing. Its direct test
runner is for pure engine tests. Mail store tests must use ordinary `dart test`
so SQLite native-asset build hooks run; bypassing those hooks is not a passing
store qualification.

The current reproduction driver requires every batch exit and every JSON runner
completion to succeed, including signal-terminated batches. The sealed archive
preserves the exact earlier driver used for its recorded runs; individual exits
and completion events were checked independently during evidence assembly.

[Evidence index](evidence/evidence-index.json) describes every member of
[local-qualification.tar.gz](evidence/local-qualification.tar.gz), including raw
logs, exact command receipts, input manifests, full accepted test keys, failed
attempts and reproduction scripts. Its 129 members exclude SDK/cache binaries,
compiled JavaScript, source maps, credentials and bytecode. The deterministic
archive is 1,300,946 bytes with SHA-256
`97215d1b03589df9b0c91582d7798e4451fe5d1bb1b73fa06ff06dacd989c545`.

## Local environment follow-up

The final local checkout refresh and cleanup could not execute after sandbox
startup failed. Temporary scheduling wrappers still abort with exit 75; their
exact originals remain in `runtime/bin/dart.original_for_restore` and
`runtime/bin/flutter.original_for_restore` in the task workspace. Restore those
original helper launchers when ordinary filesystem operations are available.
This affects the temporary test environment, not committed repository source or
the SDK. Verified old historical-evidence copies were locally evicted with
`skip-worktree` under storage pressure; their Git history is intact and the
restoration manifest remains in `runtime/evicted-historical-evidence.json`.
No clean or synchronized final local-checkout state is claimed.

## Compatibility limits

This is an extension of Quds's bounded VBA-to-native adapter. It does not add a
general VBA runtime or arbitrary Office COM automation. Projected paragraph
ranges and body/header/footer paragraph `InsertAfter` remain rejected, including
statically known inactive branches. Merged/nested/multiple-paragraph cells,
structural paragraph/cell characters, fields, hyperlinks and bookmarks remain
outside the supported suffix operation. Empty suffixes still validate ownership
and cell shape before succeeding.

No installed Microsoft Word differential run, live Zotero desktop acceptance,
live Mail provider acceptance or browser Mail persistence/savepoint runtime
acceptance is claimed. VM/JavaScript Word execution and native SQLite tests cover
the specific behaviors documented here.

## Primary compatibility references

- [Word Table.Cell](https://learn.microsoft.com/en-us/office/vba/api/word.table.cell)
- [Word Range.Cells](https://learn.microsoft.com/en-us/office/vba/api/word.range.cells)
- [Working with tables](https://learn.microsoft.com/en-us/office/vba/word/concepts/working-with-word/working-with-tables)
- [Word Range.InsertAfter](https://learn.microsoft.com/en-us/office/vba/api/word.range.insertafter)

Microsoft's cell examples establish the direct cell-range operation. Its
paragraph-range documentation explains why a generic paragraph append cannot
be substituted. Native source preservation and resource restrictions are
Quds's documented contract; installed Microsoft Word differential execution is
separate qualification.
