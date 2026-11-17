# Canonical merged-source qualification — 17 November 2026

**The accepted full run passed all nine required commands and 2,576 substantive
test cases across 144 selected files.** The raw runner reported 2,578 successes;
the two unavailable private-PDF cases described below are excluded from
substantive coverage. No errors, failed cases or reported skips occurred.

This is a fresh local qualification of canonical source
`837d06edbde08a2465e99cbbb15927ee4c87d8ac`, tree
`c2173f93159150b078c1bae466c30d95a030f35b`, in
`CrispStrobe/quds_office_suite`.

The previous conversation reported a 1,849-pass combined qualification, but its
latest logs and receipts were not found on the saved remote branch. Those
reported counts are not reused here. Earlier committed qualifications retain
their original source attribution and are not added to the new run.

## Accepted full-run results

`run-3/receipt.json` is the accepted terminal receipt. The two earlier attempts
are preserved separately and contribute zero passes to this table.

| Cohort | Selected files | Raw successful events | Substantive passes |
| --- | ---: | ---: | ---: |
| Engine Zotero | 19 | 390 | 390 |
| Actual Flutter editor Zotero | 13 | 186 | 186 |
| Engine ODF, PDF/rendering, spreadsheet, layout and proofing integration | 73 | 1,588 | 1,586 |
| Actual Flutter editor integration | 36 | 385 | 385 |
| Harper transport/source contracts | 3 | 29 | 29 |
| **Total** | **144** | **2,578** | **2,576** |

The three strict-analysis commands and the 81-file formatting gate also passed.
Every selected test suite matched the exact physical source path after resolving
the recorded command working directory; no unexpected suite was accepted.
The 390/186 Zotero counts are explicit gates, not inferred historical numbers.

All before/after integrity comparisons passed: 3,327 committed non-evidence
files, 5,099 resolved dependency inputs, 13 runtime artifacts, 12 workspace
manifest/configuration inputs, six observed system paths and seven harness
inputs. The absent private PDF is one of those six observed system paths.
These are overlapping integrity records, not additional tests. Analyzer
configuration was restored, source blobs/modes still matched the frozen commit,
and the checkout remained at the same source SHA.

Later ODT-list work uses a separate bounded amendment at
`2ae8bf3420bd20ec33115c96a44a38a0d3a78df0`. The full-run counts above retain
their exact `837d06ed` attribution; see the amendment's separate source delta
and receipt for its narrow additional coverage.

## Scope

The new plan derives from the committed
`docs/validation/office-fidelity-20261117/cohorts.json` and the recovered Zotero
runner. It contains 144 distinct package/test paths:

| Cohort | Test files |
| --- | ---: |
| Engine Zotero | 19 |
| Flutter editor Zotero | 13 |
| Engine ODF, PDF/rendering, formulas/styles/rename, layout and proofing | 73 |
| Flutter editor rendering, spreadsheet history and proofing | 36 |
| Harper transport/source contracts | 3 |

`word_zotero_test.dart` is removed from the engine integration list because it
already belongs to the Zotero group. The new German agreement/context suite is
explicitly included. The Zotero group must report exactly 390 engine and 186
editor successes. The engine/editor/Harper scoped strict-analysis commands and
one formatting command complete the nine required commands. Strict analysis
covers 123 paths. Formatting covers all 77 existing non-evidence Dart paths
changed from captured main `6860985f` to the frozen source, plus four recovered
Zotero production targets from the prior scope (81 paths total).

## Preserved first attempt and scope correction

`run-1/` passed all three strict-analysis commands and stopped at formatting;
**zero tests executed in that attempt**. Its initially overbroad formatting
selection reported four inherited Zotero test files:

- `packages/quds_office_editor/test/word_zotero_format_test.dart`
- `packages/quds_office_engine/test/word_zotero_test.dart`
- `packages/quds_office_engine/test/zotero_client_test.dart`
- `packages/quds_office_engine/test/zotero_identity_client_test.dart`

All four retain the exact same Git blobs and modes on captured main and the
frozen candidate. They were not touched by this integration. The original
formatter diagnostics, return code, source/runtime/input manifests and original
runner remain in `run-1/`; `scope-amendment.json` binds their identities and
the exact scope decision. No production or test bytes were changed.

The accepted scope for the replacement run formats every changed existing
non-evidence Dart path and the four previously qualified recovered production
targets. The inherited test formatting above is **not claimed to pass**.
All 123 strict-analysis targets and all 144 test selections remain unchanged;
`run-1-to-run-2.patch` records the runner adjustment. The replacement attempt
used a fresh `run-2/` directory.

`run-2/` passed the three analyses and corrected formatting, then executed all
390 engine Zotero tests successfully with a zero process exit and terminal
runner success. Its receipt nevertheless failed because the new evidence
parser incorrectly compared relative suite paths to an absolute-path suffix.
The source/test/runtime inputs were unchanged and no product defect appeared.
That attempt is retained unchanged and its counts are excluded from the fresh
replacement qualification. `suite-path-correction.json` and
`run-2-to-run-3.patch` preserve the defect and correction: resolve selected and
observed suite paths against the command's exact working directory, follow the
known source symlinks, and require exact equality. Unexpected suites also fail.
The new full replacement run uses `run-3/`, with unchanged source and selection.

The accepted bundle contains `run-3/`, the executed runner and correction
records. Complete earlier attempt archives are already published with the
[checkpoint report](https://github.com/CrispStrobe/quds_office_suite/blob/2ae8bf3420bd20ec33115c96a44a38a0d3a78df0/docs/validation/zotero-landing-20261117/checkpoints/README.md).

This is focused local qualification, not a full repository test run or complete
application build. Harper checks use injected transport contracts; they do not
establish new native/Wasm acceptance. No GitHub Actions jobs, checks or status
endpoints are used.

## Source, runtime and dependency integrity

The runner requires a clean checkout at the exact source SHA, compares all
tracked non-evidence files against committed Git blobs and modes, and rejects
untracked non-evidence files. Documentation/evidence lives under `docs/` and is
excluded from the production fingerprint; the inherited manifest/runner and
the executed runner/plan/config/fixture audit are separately hash-bound.

Tests run from an external workspace with unchanged copied package manifests
and implementation directories pointing at the canonical source. Its lock must
retain SHA-256
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
The expected Flutter framework is `737ba8f885dc774b53b442759999a312c9461e4e`,
engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`, and Dart version 3.13.7.
The SDK restoration has separate archive/setup provenance.

Before/after snapshots bind external package `lib`/`bin`/`assets` and manifests,
selected runtime executables/snapshots, workspace manifests/configuration/lock,
source files, system fixtures and harness files. Strict analysis temporarily
uses a normalized package graph in the canonical root; its prior bytes or
absence are restored before tests and again in `finally`.

Every command retains its exact arguments, working directory, environment
overrides, return code, timings, compressed stdout/stderr and both raw/stored
hashes. Test results require terminal runner success, all selected suites,
zero errors/skips/failures and unique source selection. Partial or failed runs
remain distinct attempts and are excluded from accepted results.

## Fixture coverage

The fixture audit reviews 150 files in the selected tests' relative Dart import
closure. All five actual Linux font fixtures and three relevant bundled font
choices are present and hash-bound. The unused Windows fallback paths do not
cause a skip on this Linux environment.

The private `/home/mohammed/Desktop/al_tahreer_profile.pdf` is absent. Two
inherited tests return before assertions when it is unavailable:

- `TrueType subsets without cmap get ToUnicode cmap for the host`
- `JPEG with DCT SMask attaches softMaskJpeg for the host`

The runner separately records raw successful test events and subtracts exactly
these two cases from substantive successful coverage. It validates their suite
and names, allowing the test runner's group prefix. Any missing required font
fixture stops qualification before test execution rather than silently counting
an early-return success.

## Reproduction

With the restored runtime and external workspace prepared, use a fresh output
directory for every attempt:

```sh
. /path/to/runtime/env.sh
python3 run_qualification.py \
  --repo /path/to/quds \
  --source-commit 837d06edbde08a2465e99cbbb15927ee4c87d8ac \
  --flutter-root /path/to/runtime/flutter-sdk \
  --workspace /path/to/runtime/harper-workspace \
  --output /path/to/new-evidence
```

Use `--plan-only` to inspect selection without executing analysis or tests.
Do not replace an existing `receipt.json`; preserve the attempt and select a
new output directory. The initial fixture scan and plan are preflight evidence,
not claims that any Dart or Flutter tests passed.
