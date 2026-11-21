# Word VBA physical-unit conversions: intake and qualification

> Historical PR #271 final evidence record captured at `c12ad8bc9c17f1849acdf92b2245e9198f1005b8`.
> Its source binding and blocked execution status apply to the earlier positional-only candidate.
> The reconciled compiler retains official named arguments; see [README.md](README.md) for final observed qualification.

## Incoming work reconciled first

The initial source is remote main `c954d00d2fc85604ae394674bca91ea8a1dede0e`
(tree `1d279ced85f247b7fae5e21a04dd8ea354a75919`). It contains **39 additional
commits** after the prior paragraph-spacing handoff
`52c7f27fc7b6998e209e3ac8c815d6cf1ca6f867`; the comparison changes 88 files.

The captured inventory is in [intake.json](intake.json). It covers every fork
branch and PR returned by complete pagination, plus every upstream branch and
PR. The checkpoint branch created for this increment is outside that initial
snapshot.

| Captured source | Actual ancestors | Equivalent squash commits | Preserved, explicitly excluded | Total |
| --- | ---: | ---: | ---: | ---: |
| Fork branch heads | 23 | 9 | 1 | 33 |
| Fork PR heads | 256 | 14 | 0 | 270 |
| Upstream branch heads | 4 | 0 | 0 | 4 |
| Upstream PR heads | 4 | 0 | 0 | 4 |

There are **zero unclassified captured references**. All earlier deferred
paragraph controls, App Store documentation/screenshots, Arabic settings,
bookmark/layout work and Mail parity work are now incorporated. The prior
main-green work is incorporated through `1e723bd4`; its later temporary
workflow-only commit is classified separately below.

### Evidence behind the classifications

The audit read the complete 2,786-commit graph reachable from the fixed initial
main through 28 GitHub REST pages (100 entries per page, final page 86). All
commit IDs are distinct and every referenced parent is present. Ancestor
classifications require exact SHA membership in that closed graph.

Thirteen remaining PR heads have exactly the same complete Git tree as their
ancestor squash commits. PR #140 is the sole remaining tree mismatch: all
**37 files changed by that PR have identical blob IDs and file modes** at its
ancestor squash commit. Its eight other tree differences belong to the
independent spreadsheet data-bar work. The exact heads, squash commits, tree
IDs and file-level proof are recorded in the JSON.

### One deliberately excluded WIP workflow

The branch `fix/main-green-20261120` remains preserved at
`332d7b26a320ca560f4f2214e1e63da9392269ab`. Its only commit after the incorporated
parent `1e723bd4bc96e07b1b790daf9b82897a846c6096` changes one matrix row in
`.github/workflows/tmp-regenerate-editor-goldens.yml`.

Initial main deliberately merged that parent **without the temporary
golden-regeneration workflow**, and the workflow is absent from its captured
workflow directory. This increment retains that choice. The audit records the
later commit and exact patch; it does not reintroduce the removed WIP workflow
or claim that this later head was merged.

## Incremental publication and validation

This first checkpoint preserves the intake before implementation. It makes no
Word runtime or validation claim. The intended next increment adds bounded
Word VBA physical-unit conversion functions on the existing source adapter.

The workspace could not launch local commands or write local files because the
execution environment reported no available space. This checkpoint therefore
contains connector-based source/ancestry review only. Implementation, tests
and any later validation results must be documented separately as they
complete.

No GitHub Actions runs, statuses, checks or queue endpoints were queried or
waited on. Checkpoints use a non-forced branch update with the previously
observed head as the expected SHA.

## Implementation checkpoint

Added `InchesToPoints`, `PointsToInches`, `CentimetersToPoints`,
`PointsToCentimeters`, `MillimetersToPoints`, `PointsToMillimeters`,
`PicasToPoints` and `PointsToPicas` through the existing Word conversion
dispatcher. The native operation/runtime/serializer files are unchanged.
The existing line functions retain their exact factors and multiply/divide
fallback order.

The [Word contract](../../VBA_WORD_MACROS.md#physical-measurement-conversions)
documents the exact physical ratios, scalar types, finite limits, explicit
rounding choice and host boundaries. The
[example](../../../packages/quds_office_engine/example/macros/word_unit_conversions.bas)
uses all eight functions and nine operations on two paragraphs.

The new compiler suite covers call routes, case, sign/zero, Variants,
single argument evaluation, invalid/dead-source calls, shadowing,
dialect isolation, canonical decimal conversions, native precision,
overflow, old line fallback behavior and custom-spacing transaction guards.
The integration suite covers the actual BAS, save/reopen and repeatability,
canonical native values, rollback, policies, explicit rounding and scalar-only
plans.

**These Dart suites have been written but have not been executed at this
checkpoint.** The command environment fails before a process can start:
first `No space left on device` while creating the sandbox; later the exec
server reports `No such file or directory`. No Dart analysis, formatting,
VM, JavaScript compilation, CLI or whole-engine regression pass is claimed.
Source review and arithmetic checks are recorded separately when complete.

## Reviewed publication scope

The historical initial intake above is superseded by the
[incoming reconciliation](incoming-reconciliation.md). Checkpoint `8ca1958d9eb737beb88269bb962a2418f7a3a44a` includes
`332d7b26` as an actual merge parent, resolving its sole
modify/delete conflict by retaining main's deletion of the temporary workflow.
All **311 initially captured references** are therefore represented:
288 actual ancestors and 23 exact-tree or changed-file equivalents.
There are no remaining exclusions or unclassified entries in that initial
snapshot. No retained source branch is rewritten.

The final numeric candidate promotes already-bounded inputs to binary64
before scaling. Every permitted integer is exactly representable; this avoids
signed-64 intermediate overflow without changing the round-trip guard or
the existing multiply/divide fallback. No native document operation or
runtime/serializer implementation changes.

### Validation that actually ran

The [arithmetic result](arithmetic-result.json) records **210,069 successful
source-bound JavaScript assertions**: 200,010 conversion-grid comparisons,
10,024 comparisons with the previous line algorithm, 12 decimal cases,
19 boundary cases and four source-shape assertions. A separate **60,144-case**
BigInt model checks signed-64 versus binary64 grid decisions for permitted
integer inputs. These are arithmetic-model checks, not Dart test counts.
Overlapping independent reviewer probes are not added to those counts.

The [reproduction harness](check-arithmetic.mjs) binds the exact reviewed Dart
evaluator text and compiler Git blob before running the same numeric model.
Its core ran in the tool's V8 isolate. The standalone Node file wrapper has
not been launched by a local process in this environment.

Independent source review covers dispatch/reservation/checker paths,
single argument evaluation, numeric boundaries, native guard retention,
the example's operation order, and the test expectations. The first review
is retained in [source-review-initial.json](source-review-initial.json);
the [final source review](source-review.json) binds the final compiler, both
suites, the BAS and the contract with no blocking findings. The
[late-scope inventory](late-scope.md) records the four active later heads.

### Validation that did not run

There are **202 authored compiler cases and six authored native integration
cases**, all **unexecuted**. The additional compiler case checks valid large
scalar results whose intermediate scale products exceed signed 64-bit range.
The [environment failure record](environment-blocker.json) records the
pre-launch errors. No Dart compile, analyzer, formatter, VM/native suite,
compiled-JavaScript parity, CLI, broader regression or installed-Word result
is claimed. Earlier commits' passing counts do not qualify this new source.

From a provisioned engine checkout, the focused pending gate is:

~~~sh
dart test test/office_vba_word_unit_conversions_test.dart \
  test/office_vba_word_unit_conversions_integration_test.dart \
  test/office_vba_word_line_spacing_test.dart \
  test/office_vba_word_line_spacing_integration_test.dart
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed \
  lib/src/automation/office_vba_language.dart \
  test/office_vba_word_unit_conversions_test.dart \
  test/office_vba_word_unit_conversions_integration_test.dart
~~~

These are reproducible next validation commands, not a transcript of executed
commands. The repository's required broader gates remain unexecuted here.
GitHub Actions were neither queried nor awaited.

### Concurrent work after the initial intake

Four active work heads appeared after implementation began: two overlapping
Word measurement continuations and two Mail bulk-action continuations.
Their exact captured heads and dispositions are retained in the late-scope
record. They are outside the frozen initial intake and remain on their
branches. In particular, the later Word measurement branch already contains
this increment's `dd8e73a7` checkpoint and adds a competing implementation plus
fixtures; the other Word branch adds named application-function arguments.
This increment keeps its reviewed positional-only contract. A fresh remote
main check is required immediately before merging; any work actually added
to main must be retained.

## Remote checkpoint ledger

| Checkpoint | Preserved state |
| --- | --- |
| `e938eebba6ee1b52868acdcd3a1f9d69b5af6891` | Complete initial intake audit, before implementation |
| `dd8e73a7d6252b336b2e7a437c4931addc42d491` | Physical conversions, example, contract and two authored suites |
| `8ca1958d9eb737beb88269bb962a2418f7a3a44a` | Actual incoming maintenance ancestry, reviewed numeric corrections and arithmetic evidence |
| Final evidence checkpoint, identified in PR #271 | Final independent review, late-scope inventory and source binding |

[historical qualification receipt](incoming-pr271-qualification.json) binds the reviewed source and the
precise validation limits. The final remote-main SHA, final checkpoint SHA,
complete-tree equality and merge-parent verification are recorded in
[PR #271](https://github.com/CrispStrobe/quds_office_suite/pull/271) after the
merge, avoiding a self-referential commit hash inside this tree.
