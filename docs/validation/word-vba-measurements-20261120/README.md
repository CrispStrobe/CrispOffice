# Word VBA physical measurements — integration and validation

## Result and scope

This continuation adds eight source-level Word measurement helpers:
`InchesToPoints`, `PointsToInches`, `CentimetersToPoints`,
`PointsToCentimeters`, `MillimetersToPoints`, `PointsToMillimeters`,
`PicasToPoints` and `PointsToPicas`. Global, `Application` and
`With Application` calls reuse the existing typed source compiler.

Only the conversion vocabulary and `_wordUnitConversion` change in production
code. The parser, binder call routes, native operation catalog, runtime,
permissions, model and serializers are retained. The implementation uses
binary64 intermediates, exact physical ratios, round-trip-checked common
integer grids and the existing computed numeric-result bound. It does not
emulate VBA `Single` or round values implicitly to a destination's native grid.
See the [exact contract](../../VBA_WORD_MACROS.md#physical-measurement-conversions).

## Qualification status — local execution blocked

**The new Dart suites have not been executed.** This environment could not
start the checkout: sandbox setup reported
`bwrap: Can't create file /workspace/scratch/3d152a44d444/.git: No space left on device`.
The execution service subsequently returned
`exec-server rejected request (-32603): No such file or directory (os error 2)`.
The desktop runtime was also unavailable. No checkout, Dart SDK process,
analyzer, formatter, VM test, compiled-JavaScript driver, CLI test or installed
Word-host test completed in this turn.

Source review and a separate V8 arithmetic model are useful evidence for the
small change, but are **not** Dart compilation or native execution. Historical
qualification counts in other records do not qualify this source. No pass
count is claimed for the authored regressions. GitHub Actions, workflow runs,
status/check endpoints and queue completion were neither queried nor awaited.

### Completed checks

- Independently audited current fork and upstream source coverage, with exact
  heads and historical equivalence proofs.
- Independently reviewed the source implementation, declared numeric types,
  dormant-source call checks, evaluation order and existing resource guards.
- Compared production source outside the conversion set and evaluator and
  confirmed that it is unchanged from the captured main.
- Reviewed the actual example, model/XML/OPC APIs, native numeric expectations,
  rollback/policy behavior and MCP calls used by the new fixtures.
- Evaluated fixed physical ratios, canonical native values, near-grid values,
  large binary64 results and legacy line behavior with a separate arithmetic
  model. This did not invoke the Dart compiler or the document runtime.
- Read back the remote commits and branch heads after checkpoint publication.

The [source-review receipt](source-review.json) identifies the reviewed source
and the exact checks recorded for the final checkpoint.

### Authored regression coverage

| File | Coverage written; execution pending |
| --- | --- |
| `office_vba_word_measurements_test.dart` | Eight helpers, global/member/With calls, numeric Variants and explicit conversion, helper composition, once-only argument evaluation, dead/unused source refusals, name reservation, dialect isolation, native precision, numeric bounds and shared work budget |
| `office_vba_word_measurements_integration_test.dart` | Actual BAS, native XML twips, empty/untouched paragraphs, existing tabs and bold text, save/reopen, replay, rollback, policies and opaque DOCM project preservation |
| `web_vba_word_measurements_smoke.dart` | Actual BAS bytes on VM and compiled JavaScript, repeated native round trips, rollback, read-only policy and MCP compile/run |
| Incoming `office_vba_word_unit_conversions_test.dart` | Independent physical-unit fixtures, explicit CLng twip rounding, scalar-only plans, legacy division fallback and pending-spacing argument-side-effect restrictions |
| Incoming `office_vba_word_unit_conversions_integration_test.dart` | Independent nine-operation BAS, saved native decimal values, repeatability, policies, rollback, explicit rounding and scalar-only no-op publication |

Test paths are under `packages/quds_office_engine/test`; the portable driver is
under `packages/quds_office_engine/tool/macros`. Both examples are retained:
`word_measurements.bas` emits eight writes including a tab and custom line
spacing; `word_unit_conversions.bas` emits nine paragraph-format writes.

## Incoming source integration

Initial main was `c954d00d2fc85604ae394674bca91ea8a1dede0e` with tree
`1d279ced85f247b7fae5e21a04dd8ea354a75919`.
The [intake receipt](intake.json) records all 33 pre-task branch heads and the
audit classification. All 270 PR heads are accounted for: 256 exact ancestors
and 14 historical equivalents. Thirteen replacements have identical complete
Git trees; the remaining ODT replacement matches every one of its 37 changed
file blobs and modes. All four upstream branch heads and four upstream PR
heads are exact ancestors. There were no open PRs in the captured inventory.

The sole new maintenance commit, `332d7b26a320ca560f4f2214e1e63da9392269ab`,
only changes a matrix row in the temporary golden-attribution workflow.
Main deliberately removed that workflow. Merge commit
`30c8401d6c6083737c2bdb55dd08e5aa03162aff` retains main's exact tree and records
that maintenance head as a second parent. This is a reviewed modify/delete
resolution, not a claim of content equivalence.

### Concurrent Word continuation

While this branch was being developed,
`codex/word-vba-compatibility-20261120-continuation` published
`dd8e73a7d6252b336b2e7a437c4931addc42d491` with the same eight helpers.
The reconciliation records that head as an additional parent and retains its
two new suites, BAS example and historical intake evidence.

The overlapping production and documentation edits are resolved explicitly:
retain one coherent Set/contains dispatcher and the reviewed conversion
evaluator with binary64 intermediates and numerator/divisor metric fallbacks;
consolidate the Word contract and changelog; include the incoming explicit
`CLng` rounding guidance. The incoming Map/containsKey alternative is not
mixed into the Set implementation. Both complete implementations remain
recoverable through their original commits. Neither side's unexecuted tests
are described as passing.

## Pending local commands

Run these in a properly provisioned checkout using the repository's pinned
Dart/Flutter toolchain and resolved dependencies, from
`packages/quds_office_engine`:

~~~sh
dart test test/office_vba_word_measurements_test.dart \
  test/office_vba_word_measurements_integration_test.dart \
  test/office_vba_word_unit_conversions_test.dart \
  test/office_vba_word_unit_conversions_integration_test.dart \
  test/office_vba_word_line_spacing_test.dart \
  test/office_vba_word_line_spacing_integration_test.dart
dart analyze lib/src/automation/office_vba_language.dart \
  test/office_vba_word_measurements_test.dart \
  test/office_vba_word_measurements_integration_test.dart \
  test/office_vba_word_unit_conversions_test.dart \
  test/office_vba_word_unit_conversions_integration_test.dart \
  tool/macros/web_vba_word_measurements_smoke.dart
~~~

Also run the repository formatter on the changed Dart files before treating
formatting as verified. The fixtures were manually aligned with surrounding
style, but no formatter pass is claimed.

The portable driver consumes the actual committed example bytes:

~~~sh
QUDS_MEASUREMENTS_BAS=$(base64 < example/macros/word_measurements.bas | tr -d '\n')
dart run -DWORD_MEASUREMENTS_BAS_BASE64="$QUDS_MEASUREMENTS_BAS" \
  tool/macros/web_vba_word_measurements_smoke.dart
mkdir -p build/measurement-validation
dart compile js -DWORD_MEASUREMENTS_BAS_BASE64="$QUDS_MEASUREMENTS_BAS" \
  tool/macros/web_vba_word_measurements_smoke.dart \
  -o build/measurement-validation/word_measurements.js
node -e 'globalThis.self = globalThis; require("./build/measurement-validation/word_measurements.js")'
~~~

Compare the VM and JavaScript JSON results only after both commands succeed.
Those pending commands are not a record of executed tests.
