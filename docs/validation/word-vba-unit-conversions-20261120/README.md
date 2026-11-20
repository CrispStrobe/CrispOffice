# Word VBA physical-unit conversions: intake and qualification

> Historical checkpoint from the concurrent continuation. Its source, tests and
> example are preserved by the [measurement reconciliation](../word-vba-measurements-20261120/README.md).
> That record supersedes the implementation choice and records the later merge
> of the workflow-only history while keeping the temporary workflow deleted.

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
