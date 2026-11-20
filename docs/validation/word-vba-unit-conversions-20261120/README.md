# Word macro measurement qualification — 2026-11-20

This is the authoritative local qualification record for the reconciled Word
measurement implementation. The incoming checkpoint reports in this directory
are preserved as historical evidence; their earlier runtime limitations do not
describe the executed results below.

## Latest-main native follow-up

The later intake of main at
`e975cec13b289fe067ef406cd3044701ecc44744` changes native Word layout and
deserialization, while the measurement compiler remains byte-identical. The
integration repairs header-picture identity/placement handling and preserves
explicit table-header run color and bold-off formatting. The accepted
[latest-main qualification](../word-main-integration-20261120/README.md) binds
the frozen run at `cdd98460c2eed261719c660351f11adc962e2ca5` and the test-only
correction at `cf25a0a3d80ee18d2550161af182bacc4e49d18f`.

That follow-up refreshes 709 macro cases already contained in the historical
3,598-case corpus; they are not added to that count. It accepts 312 native/layout
passes across 26 files by retaining 271 unchanged cases and replacing the
41-case contained-text suite after its geometry correction. Editor checks
passed 103 cases, with eight explicitly documented image-only fixtures skipped
because they have no editable paragraphs. Strict analysis and both actual
BAS examples on VM and optimized JavaScript passed. The eight lowercase font
filename aliases were source-reviewed and statically analyzed only.

The linked report preserves the initial false receipt, the successful focused
correction, exact case identities, source/runtime seals and coverage limits.
The historical numbers and receipts below remain bound to their stated earlier
source; they do not claim that native Word files stayed unchanged through this
later intake.

## Result and captured source

The accepted VM regression corpus contains **3598 passing cases across
69 suites**, with no failures or skips. This combines 62 unchanged
baseline suites with the seven final measurement suites, without counting
superseded runs twice. See [the accepted suite union](accepted-suite-union.json),
[the final Word receipt](final-word-qualification.json), and the hashed raw
receipts in [local-qualification.tar.gz](local-qualification.tar.gz).

| Input | Captured value |
| --- | --- |
| Broad baseline commit | e08635b3f21c60ad21888821050dc97c2dbf7086 |
| Broad baseline tree | d88010d76bc881ad4d4519c89472abcc9d0282e0 |
| Final measurement commit | cb5909fefe6dd41db0f9c38207db83166072dcaf |
| Final measurement tree | 3eca24612f32567d7312ae098d7b30c049bb6e3b |
| Compiler SHA-256 | 41de865411b884d18c1097e9a80d68cd6bf1fb245e1844a46f72af05636f5ecd |
| Engine runtime | Dart 3.14.1; 56 hosted dependency versions and archive hashes match the repository lock |
| JavaScript runtime | v24.22.3 |

The dependency archive proof is retained in the archive at
historical-mail-core/hosted-dependencies.json. It records the same 56 hosted
packages used by the Word harness, with cached hashes matching the repository
lock. The captured Mail-core and Word lockfiles are byte-identical.

The Mail-only checkpoint `85f4ef96` retained all 986 of these Word inputs. The
subsequent main intake is covered by the native follow-up described above.
No GitHub Actions
run, check status, or workflow result was awaited or used as a qualification
gate. Workflow settings were not changed.

## Capability covered

The Word source adapter adds InchesToPoints, PointsToInches,
CentimetersToPoints, PointsToCentimeters, MillimetersToPoints,
PointsToMillimeters, PicasToPoints, and PointsToPicas. Together with the existing
LinesToPoints and PointsToLines functions, all ten accept either one positional
argument or the official case-insensitive named argument. Global,
Application-qualified, and leading-dot calls inside With Application are covered.

Tests check numeric Variant inputs, explicit conversions, argument evaluation
exactly once, invalid and omitted arguments, source work limits, unreachable
call shapes and statically known types, host-specific name reservations,
near-grid values, large scalar arithmetic, and native precision boundaries.
A Variant's contents are checked when that value is evaluated. No implicit
String, Boolean, Empty, Null, or omitted-Variant coercion is added.

The source compiler still produces an immutable native operation plan without
reading the live document. Execution retains detached transaction, cancellation,
read-only, operation-allowlist, work-limit, rollback, revision, and recording
behavior. The change does not add a native operation or alter the serializer.

The [Word macro contract](../../VBA_WORD_MACROS.md) documents the complete
supported subset and links all three retained examples:

| Example | Native operations | Qualification |
| --- | ---: | --- |
| word_measurements.bas | 8 | Integration suite and actual file on VM and optimized JavaScript |
| word_unit_conversions.bas | 9 | Independent integration suite, including explicit twip rounding |
| word_named_measurements.bas | 13 | Integration suite and actual file on VM and optimized JavaScript |

## Executed local gates

| Gate | Observed result |
| --- | --- |
| Broad macro/VBA baseline | 3,110 passed across 64 suites; zero failures or skips |
| Final seven measurement suites | 645 passed; zero failures, skips, or reporter errors |
| Accepted regression union | 3,598 cases across 69 suites; superseded runs excluded |
| Incoming conversion suite on Node/dart2js | All 63 cases passed; same case identities as VM |
| Strict whole-engine analysis | No issues found with --fatal-infos |
| Formatting | All affected final Dart tests/drivers clean |
| Actual eight-operation BAS | VM and optimized JavaScript results identical |
| Actual thirteen-operation BAS | VM and optimized JavaScript results identical |
| Nine-operation unit conversion BAS | Passed its independent integration suite |
| Source and runtime seals | All 986 captured source inputs and runtime inputs unchanged during the final run; root package configuration unchanged |

The broad baseline completed all 3,110 cases in 64 macro/VBA suites on an
unchanged source checkout. Its 147-case and 10-case measurement suites are
superseded by the final seven suites. Thus the accepted count is
3,110 − 157 + 645 = 3598. The earlier four-suite 378-case run and
the extra Node run are useful corroboration, not additional VM corpus cases.

Before/after source and runtime hashes accompany the raw receipts. The source
retention comparison confirms that all production inputs, dependencies, and
the 62 retained baseline suites are unchanged. A separate fixture-reference
inspection confirms that those retained suites do not read the measurement
examples or portable drivers that were reorganized during intake.

An independent actual-compiler probe also passed on both VM and JavaScript:
610 native-grid round trips, ten just-outside-bound refusals, 60 other-host
scope checks, and a side-effecting named argument evaluated once. Its source,
results, and compiler hash are included in the archive.

## Precision and document ownership

The contract is bounded binary64 Double arithmetic, not VBA Single emulation.
Physical ratios use 72 points per inch, 3600/127 points per centimeter,
360/127 points per millimeter, and 12 points per pica or line. Native-grid
canonicalization requires exact inverse equality; it does not use a tolerance
or round arbitrary dimensions automatically.

CentimetersToPoints(1) is a valid scalar. Assigning that unrounded value to an
exact-twip native property is refused. A macro author can explicitly request
rounding with CLng(CentimetersToPoints(1) * 20) / 20, producing 28.35 points.
Existing native property precision and range checks remain in force.

DOCM tests save, reopen twice, and replay recorded plans. They verify the
expected paragraph values, unrelated paragraph/style content, and opaque VBA
bytes. The existing indentation serializer owns the edited w:ind group and
replaces it, including foreign attributes inside that group. These tests do
not claim byte-for-byte preservation of every edited XML group or validity of
cryptographic signatures after modification. Embedded VBA remains inert. No
installed Microsoft Word host, live COM object model, or full VBA compatibility
is claimed by this engine qualification.

## Intake and incremental persistence

The [initial incoming review](incoming-review.md) and
[reconciliation record](reconciliation.md) explain the captured main, branch,
and PR heads, including verified historical squash equivalents. The bounded
final inventory captured 38 branches and two open PRs. Current-main Word
continuation, Zotero intake history, and the additional Word suite carried by
the Mail branch were preserved. The overlapping Mail implementations are
qualified separately in the final integration report.

Implementation, examples/tests, and each reconciliation were saved incrementally
on codex/word-vba-unit-conversions-20261120 with non-forced, expected-head ref
updates. Every published tree was compared with its local staged tree. The
final measurement run used the real remote commit identified above.

## Earlier failed fixture and interrupted run

The first run of the six restored measurement suites produced 573 passes and
eight failures. All eight came from one parameterized incoming test that placed
a declaration after an executable statement. Moving both declarations before
the assignment allowed the fixture to reach its intended invalid-Variant
check. Expected errors and production code were unchanged. The failed receipt
and raw logs are retained in the archive. A separate attempt was interrupted during initial suite loading without a terminal result. Its log and interruption record are retained; no cases from it are counted as passes or failures. The fresh retry supplied the successful receipt above.

## Reproduction

The archive contains raw test events, analyzer and compiler output, case
identities, source/runtime manifests, incoming historical receipts, and the
exact qualification scripts. [receipt-manifest.json](receipt-manifest.json)
lists the SHA-256 and size of every uncompressed archived file and the archive
itself. Generated SDKs, package archives, kernels, and JavaScript outputs are
not committed; rebuild them from the pinned inputs.

For a fresh Linux checkout, first copy reproduce_runtime.py,
qualify_main_reconciled_measurements.py, and environment.json from this
directory to a directory outside that checkout. Check out the final measurement
commit above, then run the following, substituting absolute paths:

    python3 /path/to/scripts/reproduce_runtime.py \
      --repo /path/to/fresh-checkout \
      --runtime /path/to/new-runtime \
      --record /path/to/scripts/environment.json
    source /path/to/new-runtime/env.sh
    python3 /path/to/scripts/qualify_main_reconciled_measurements.py \
      --repo /path/to/fresh-checkout \
      --root-repo /path/to/fresh-checkout \
      --runtime /path/to/new-runtime \
      --out /path/to/new-word-results

The runtime bootstrap verifies the official SDK archive hash and resolves
the recorded dependency versions in an isolated headless harness. It leaves
tracked workspace manifests and the lockfile unchanged. Python 3, curl, and
Node are required. To rerun the entire current macro/VBA corpus after setup,
run the generated test wrapper from the engine directory with
test/office_vba*_test.dart and test/office_macro*_test.dart as its file arguments.
The original 64-suite baseline can be reproduced independently at its captured
commit using qualify_measurements.py.
