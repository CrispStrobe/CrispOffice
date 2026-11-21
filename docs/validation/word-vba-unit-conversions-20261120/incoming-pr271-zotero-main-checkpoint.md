# Word VBA measurements: reconciled publication and qualification

## Current source and result

This continuation reconciles remote main
`22cf73b816328cd5fe54ec1793c89f1cc322db3b` with this branch's checkpoint
`c12ad8bc9c17f1849acdf92b2245e9198f1005b8`. These are required ordered
parents of the reconciliation checkpoint: this branch first, incoming main
second. Publication is through **PR #271**.

Incoming main retains **PR #272** at `b01cb23dc`, which consolidated the
Word conversion and named-argument branches. Its subsequent merge also
retains this branch's `8ca1958d` history, large-scalar regression case and
six historical evidence files.

The incoming main compiler is retained exactly as blob
`07dc3c5737661abaf3b17db24439c71482de22ed`. It consolidates the eight physical
conversion functions developed in the concurrent Word branches and adds
official named arguments to all ten Word unit functions, including
`LinesToPoints` and `PointsToLines`. The full current contract is
[Physical measurement conversions](../../VBA_WORD_MACROS.md#physical-measurement-conversions).

| Functions | Named argument for the forward function | Named argument for the inverse function | Exact relation |
| --- | --- | --- | --- |
| InchesToPoints / PointsToInches | Inches | Points | 1 inch = 72 points |
| CentimetersToPoints / PointsToCentimeters | Centimeters | Points | 2.54 cm = 72 points |
| MillimetersToPoints / PointsToMillimeters | Millimeters | Points | 25.4 mm = 72 points |
| PicasToPoints / PointsToPicas | Picas | Points | 1 pica = 12 points |
| LinesToPoints / PointsToLines | Lines | Points | 1 line = 12 points in this adapter |

All functions support an unqualified call, `Application.Function(...)`, and
a leading-dot call inside `With Application`. They accept one positional
numeric expression or one correctly named numeric expression. Names are
case insensitive. Argument expressions are evaluated once.

The adapter retains its numeric type and finite-range restrictions. It does
not implement general VBA `Single` coercion. A scalar conversion does not
relax a destination property's native precision or range requirements.
Exact native-grid canonicalization uses a round trip to the input double,
without tolerance-based snapping. One centimeter is a valid fractional-point
scalar; authors must choose rounding explicitly before an exact-twip property
write. Native operation, document runtime and serializer implementations are
unchanged by this continuation.

## What the reconciliation preserves

The complete incoming main tree is the base. Its compiler, contract, changelog,
new named-conversion tests, prior line-spacing test updates, three BAS examples,
two portable drivers and measurement validation folder are retained.

Of the **30 paths changed by incoming main since the initial intake**,
**29 keep exactly their incoming blobs and modes**. Only this evidence README
is updated into a current index. No production source, test, example, driver,
contract, changelog or other incoming documentation is changed.

The incoming `office_vba_word_unit_conversions_test.dart` already contains
this branch's large-scalar test. Its blob remains
`d5caee5321cbf18e65466c2bf43fcec49397e725`, with **202 authored cases**.

The six authored cases in
`office_vba_word_unit_conversions_integration_test.dart` and the nine-operation
`word_unit_conversions.bas` example retain their exact blobs. Both were
already incorporated by PR #272 from this branch's earlier implementation
checkpoint. The incoming `incoming-review.md` is also retained unchanged.

[main-reconciliation.json](main-reconciliation.json) gives the exact incoming
paths, preserved blobs, ordered parents and later-reference dispositions.
[main-reconciliation.md](main-reconciliation.md) explains the resolution.
Historical evidence remains intact and source-bound, as described below.

## Validation status

**This publication is source-reviewed and runtime-unqualified.**
No Dart test, analyzer, formatter, VM program, compiled Dart JavaScript,
native document runtime or CLI was executed by this continuation. The execution
environment failed before command startup, initially with sandbox
`No space left on device`, and subsequently with an unavailable exec service.
[environment-blocker.json](environment-blocker.json) records the failures.

The authored 202 compiler cases and six integration cases are **not passing-test
counts**. Incoming branches' development test claims and earlier paragraph-spacing
regression totals are not counted as qualification of this merged source.

- [source-review-main.json](source-review-main.json) reviews the adopted
  compiler, its official named-argument binding, numeric canonicalization,
  evaluation order and the retained test expectations.
- [current-qualification.json](current-qualification.json) binds the exact
  current source and evidence. It records which checks ran and which did not.
- [main-arithmetic-result.json](main-arithmetic-result.json) records **246
  passing source-bound JavaScript checks** for the adopted compiler. Independent
  replay produced the same result. These checks include canonical values,
  native-precision refusals, large scalars, legacy fallbacks and boundaries.
  They are not Dart execution. The [reproducer](check-main-arithmetic.mjs)
  checks exact source identity; its standalone Node wrapper was not launched.
- Remote readback verifies the committed source and tree. Post-merge proof is
  recorded in PR #271 because a commit cannot contain its own final hash.

No GitHub Actions runs, checks, statuses or queue endpoints were queried or
awaited. Checkpoint ref updates are non-forced and require the previously
observed branch head.

## Complete initial intake

Initial main `c954d00d2fc85604ae394674bca91ea8a1dede0e` contained 39 commits
and 88 changed files beyond the preceding paragraph-spacing handoff
`52c7f27fc7b6998e209e3ac8c815d6cf1ca6f867`.

The frozen [intake.json](intake.json) covers **311 references**:
33 fork branch heads, 270 fork PR heads, four upstream branches and four
upstream PR heads. Independent review read the complete 2,786-commit initial
main graph through 28 pages and verified parent closure.

| Initial captured source | Actual ancestor references after reconciliation | Proven equivalent references | Total |
| --- | ---: | ---: | ---: |
| Fork branches | 24 | 9 | 33 |
| Fork PR heads | 256 | 14 | 270 |
| Upstream branches | 4 | 0 | 4 |
| Upstream PR heads | 4 | 0 | 4 |
| **Total** | **288** | **23** | **311** |

There are **zero excluded or unclassified initial references**. Thirteen
squashed PR heads have complete-tree equality with their ancestor squash
commits. PR #140 has all 37 of its changed files preserved with identical
blobs and modes; eight unrelated spreadsheet differences explain its
whole-tree mismatch.

The last initially unincorporated head,
`fix/main-green-20261120` at `332d7b26a320ca560f4f2214e1e63da9392269ab`,
became an actual second parent of checkpoint `8ca1958d`. The modify/delete
resolution retains main's deletion of the temporary golden-regeneration
workflow. The workflow directory stays unchanged. The historical initial
snapshot's exclusion entry is superseded by
[incoming-reconciliation.json](incoming-reconciliation.json) and
[incoming-reconciliation.md](incoming-reconciliation.md); it is not silently
rewritten.

All work deferred in the previous handoff was reconciled at initial intake,
including paragraph controls, App Store documentation, Arabic settings,
bookmark/layout changes and the earlier Mail parity work.

## Work appearing after the frozen intake

The historical [late-scope.json](late-scope.json) and
[late-scope.md](late-scope.md) captured four later active heads. Their current
dispositions are:

| Captured later head | Current disposition |
| --- | --- |
| `codex/word-vba-measurements-20261120` at `4d0086ab` | Incorporated through PR #272 / main `b01cb23d` |
| `codex/word-vba-unit-conversions-20261120` at `e08635b3` | Incorporated through PR #272 / main `b01cb23d` |
| `work/mail-bulk-actions-20261120` at `69ab514b` | Preserved and deferred; active work appeared after initial intake |
| `work/mail-bulk-flags-20261120` at `0cc6316c` | Preserved and deferred; active work appeared after initial intake |

The two Mail heads contain later bulk-action/coordinator or intake work and
overlapping Word state. They have not been qualified by this Word continuation.
No new Mail runtime run is claimed. Exact hashes and reasons are in the
current reconciliation manifest. These later deferrals do not alter the
complete initial inventory's result.

## Historical evidence and exact source boundaries

The following files are retained as historical evidence for the checkpoint
where they ran. Their old source identities and conclusions are not relabeled
as current-source execution:

| Evidence | Bound source / meaning |
| --- | --- |
| `source-review-initial.json` | Initial implementation review before the final numeric promotion |
| `source-review.json` | Compiler `a105ddd7`, 202-case suite `d5caee53`, six-case integration suite `d44ec892` |
| `arithmetic-result.json` | 210,069 JavaScript arithmetic/source assertions and 60,144 separate BigInt/binary64 grid decisions for `a105ddd7` |
| `check-arithmetic.mjs` | Reproducer requires the exact historical compiler `a105ddd7`; run against checkpoint `c12ad8bc`, not the adopted compiler |
| `qualification.json` | Reviewed checkpoint `8ca1958d` and publication requirements before main advanced |
| `late-scope.json` / `late-scope.md` | Earlier snapshot with four active later heads; superseded only by the explicit current dispositions above |

The JavaScript function bodies behind the historical arithmetic result ran in
the tool runtime. Its Node filesystem wrapper was not executed. None of these
checks substitutes for Dart test execution.

The incoming measurement validation folder is also preserved verbatim. Its
own source review distinguishes independent arithmetic from unexecuted Dart
qualification. This continuation does not turn inherited reports into a new
runtime result.

## Incremental remote checkpoint ledger

| Commit | Saved work |
| --- | --- |
| `e938eebba6ee1b52868acdcd3a1f9d69b5af6891` | Complete initial intake and classification |
| `dd8e73a7d6252b336b2e7a437c4931addc42d491` | Physical-unit implementation, tests, example and contract |
| `8ca1958d9eb737beb88269bb962a2418f7a3a44a` | Complete initial history reconciliation, final numeric promotion, larger-value test and evidence |
| `c12ad8bc9c17f1849acdf92b2245e9198f1005b8` | Independent review, frozen late scope and source-bound qualification |
| Reconciliation checkpoint containing this README | Incorporate incoming main `22cf73b8`, retain named conversions and preserve all prior checkpoint history |

The checkpoint branch is
`codex/word-vba-compatibility-20261120-continuation`.
The final PR records the reconciliation checkpoint and remote-main hashes,
complete-tree equality, required ancestry and retained checkpoint branch.
