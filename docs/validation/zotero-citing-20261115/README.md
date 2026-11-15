# Native Zotero citing — executed qualification

Canonical source **`55d46a0fb5f7392dab1a604bc3c15126bd3e380d`** passed all
**593 selected tests** and all strict analysis, formatting and whitespace
checks. This source includes the concurrent main integration through PR #46.
The exact commands, exit codes, runtime/dependency identity and log hashes are
in [final/receipt.json](final/receipt.json).

| Executed check | Result | Evidence |
| --- | ---: | --- |
| Zotero/Word engine, client, formatting and related import cohort | **380 passed** | [Engine log](final/engine-tests.log) |
| Shared editor controller, formatter and dialog cohort | **117 passed** | [Editor log](final/editor-tests.log) |
| Actual Quds Studio native transport | **16 passed** | [Studio log](final/studio-tests.log) |
| Incoming ODS/conditional-affix integration cohort | **80 passed** | [Integration log](final/integration-tests.log) |
| **Total canonical selected tests** | **593 passed** | [Receipt](final/receipt.json) |
| Changed engine targets, `dart analyze --fatal-infos` | Clean | [Engine analysis](final/engine-analysis.log) |
| Changed editor targets, `dart analyze --fatal-infos` | Clean | [Editor analysis](final/editor-analysis.log) |
| Changed Studio targets, `dart analyze --fatal-infos` | Clean | [Studio analysis](final/studio-analysis.log) |
| All 27 changed Dart targets, formatter check | Clean | [Formatter log](final/format-check.log) |
| Incremental Git diff, whitespace check | Clean | [Whitespace log](final/diff-check.log) |

All **1,558 source/dependency-input files** retained identical before/after
hashes. Source matched the recorded commit, HEAD stayed unchanged and all
harness inputs stayed unchanged during qualification. The final evidence and
guide commits may advance the branch without changing these tested code files.
The [before](final/source-before.json) and [after](final/source-after.json)
inventories make that claim independently checkable.

CrispCloud records its actual host tests and managed-source verification in its
companion validation directory. Its separate terminal integration checks are
also distinguished from the Office/Zotero feature cohort. Counts from repeated
development or earlier qualification runs are not added to these totals.

## New regression inventory

| Added canonical test area | Cases |
| --- | ---: |
| Native HTTP Citing Protocol and failure cleanup | 40 |
| Native document preference ownership, translation and persistence | 49 |
| Staged Word adapter, note order/conversion and real CSL fixture application | 59 |
| Editor transactions, rollback, save/reopen, caret and undo selection | 21 |
| Native controls, result review, alerts, cancellation and stale targets | 15 |
| Studio citing transport and catalog compatibility | 16 |
| **Added canonical cases** | **200** |

The preceding 313-case engine/editor selection remains in the run. The
80-case ODS cohort additionally checks the incoming conditional-affix changes;
it is integration evidence, not 80 new Zotero cases. CrispCloud's new citing
transport cases are counted in its own receipt. Some parameter tables exercise
many invalid inputs inside one test; totals count executed test cases rather
than individual assertions or table rows.

The actual Zotero wrapper is exercised by an executable contract fixture, and
Zotero's pinned bundled citeproc-js generated **five scenarios and nineteen
citation outputs**. The adapter applies those outputs and round-trips them
through DOCX. German `Ebd.`, changed-page `Ebd., 34.`, numeric ordering after an
earlier insertion, and APA year-letter disambiguation are among the checked
results. See the [fixture README](../../../packages/quds_office_engine/test/fixtures/zotero/citing/README.md)
for immutable sources, SHA-256 values, licenses and reproduction. These are
real processor outputs, not a live desktop/Word acceptance run.

## Reproduce locally

The runtime is official **Flutter 3.47.8 / Dart 3.13.7**, framework
`737ba8f885dc774b53b442759999a312c9461e4e` and engine
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`. The setup and final receipts record
SDK artifact hashes, complete scratch manifests/locks and genuine resolved
package graphs. Production dependency constraints were not relaxed.

Reconstruct the engine, editor and Studio harnesses from
[setup-receipt.json](setup-receipt.json), rebasing path dependencies to the
checkout. Their `lib` and `test` directories must link to the actual canonical
source. Resolve with the pinned SDK and enforce the recorded lockfiles. Supply
writable scratch paths for `PUB_CACHE`, `TMPDIR` and configuration. Then run:

```sh
export FLUTTER_ROOT=/absolute/path/to/flutter-sdk
python3 docs/validation/zotero-citing-20261115/run-focused-checks.py \
  --source /absolute/path/to/quds_office_suite \
  --engine-harness /absolute/path/to/harness/quds_office_engine \
  --editor-harness /absolute/path/to/harness/quds_office_editor \
  --studio-harness /absolute/path/to/harness/quds_office_studio \
  --output /absolute/path/to/results
```

`--plan` validates paths and prints commands without executing the cohort. The
runner checks exact runtime pins, calls the official Dart binary and Flutter
tool snapshot directly, reuses genuine package graphs for canonical-file
analysis, and restores temporary ignored analyzer configurations. It does not
resolve dependencies, invoke CI or substitute implementation stubs. The direct
runtime avoids a shell-wrapper stamp-file collision observed when independent
tool calls ran concurrently in this workspace.

The [pre-reconciliation run](pre-reconciliation/README.md) is retained as an
intermediate receipt. Its 513 tests passed, but overall qualification failed on
one analyzer info and formatting in `word_zotero.dart`. Incoming main already
contained the correction. Those overlapping passes are not counted again.

## Reconciliation and remote checkpoints

The [initial audit](branch-audit.json) accounts for 45 live branches and all 42
Quds / 50 recent CrispCloud PR heads before feature work. Existing main changes
and terminal #140 were already included, with five retained Quds squash heads
proven exact-tree equivalent.

During implementation, Quds PR #40 was merged and both repositories received
further work. The continuation therefore reconciles Quds main through **#46**,
including conditional-affix support, multi-section content-control handling
and the backlog documentation. Main was merged at
`ba9451b7426f126187ddd2b4c57f8eeb5b859638` with both parents preserved. The final
source qualification above ran after that integration and formatter cleanup.
The final audit and CrispCloud receipt record the companion main/terminal
integration. A new draft Quds PR carries the work beyond the now-merged #40.

The [final integration proof](final-integration.json) uses the incoming-work
snapshot at **2026-11-15 22:34:47.559 UTC**. All **53 branch heads and 192 PR
heads** are accounted for by ancestry or exact-tree equivalence. It includes
CrispCloud main through #156 and terminal #140 through
`a965bfd4a61ca01e6f50bf4d8c433c3fdc9e1423`. The [mid-task audit](final-branch-audit.json)
retains the incoming differences and merge previews. Later commits produced
by other work are outside that explicit snapshot; our own documentation
checkpoints advance the tested source without adding feature changes.

Work is saved incrementally on `codex/zotero-support-20261115` in both
repositories. Every checkpoint created for this continuation includes
`[skip ci]`. No GitHub Actions were queried, polled, awaited or rerun.

## Acceptance boundaries

The [implementation review](REVIEW.md) explains exact protocol shapes,
discovered defects, rollback and preservation behavior. The
[user guide](../../zotero-support.md) describes the controls.

Full native application builds, a live Zotero session/private account, actual
OS keychain behavior and native Word/Zotero refresh acceptance remain
unverified. Active ODT citation transfer is not implemented. Mixed inline
styling, small caps and bibliography paragraph layout are simplified with
review; unsupported stories and ambiguous note conversions refuse mutation.
Quds note preview labels still follow stored note IDs, while CSL note indices
follow body order and DOCX uses automatic note references. Verify displayed
note numbering in the target word processor.
