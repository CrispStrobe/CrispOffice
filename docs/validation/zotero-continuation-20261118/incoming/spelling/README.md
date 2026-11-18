# Incoming spelling qualification — 18 November 2026

The fixed incoming-work cutoff includes native spelling branch
`f482b06fc47545c8b03124c30ea78f54e8e4b9e5`. Its source was integrated into
**`b2bcfc23e692476d16d9a7a534ea95a93ae94cd3`** before these checks. The branch's
earlier development reports are not counted as results here.

## Accepted local results

| Cohort | Suites | Passed | Failed / skipped |
| --- | ---: | ---: | ---: |
| German spelling and affected normalization consumers | 19 | 526 | 0 |
| Native provider, projection, identifiers, vocabulary and Word dialog | 7 | 64 | 0 |
| **Disjoint test total** | **26** | **590** | **0** |

The separate portable Dart VM panel accepts **48 of 48 cases**. These panel
cases are not added to the test total. Every actual test/panel process exited
zero. The [aggregate summary](summary.json) links the underlying acceptance.

The engine selection covers all seven direct `german_spelling_*` suites,
suggestion quality, lexical queries, nominal and participle suggestions,
literal ranges and proofing range validation. It also covers the grammar,
agreement, morphology and writing-rule consumers of `normalizeGermanWord`.
This bounds the effects of the new discretionary-hyphen projection, identifier
protection and decomposed dictionary comparisons.

The editor selection comprises all seven `platform_spelling_*` suites. These
exercise the changed native provider through injected services and controlled
Flutter platform-channel replies, including Word review/correction and history.
The newly imported identifier, identifier-review and Unicode vocabulary cases
are included once. No product or test edits were required during qualification.

The parent workflow's [final strict checks](../../checks/summary.json) also
analyze both changed providers, the new tests and the portable panel with
`--fatal-infos`. That analysis was reused directly rather than run again here.

## Source and runtime binding

[source-commit-binding.json](source-commit-binding.json) binds all **497 unique
source inputs** to the qualified commit. The engine, editor and panel manifests
contain 408, 477 and 390 inputs respectively; these overlapping input counts
are not test counts. Shared inputs agree across the cohorts, and all files
matched both their saved commit and the validation workspace.

Each cohort retains its exact command, working directory, runtime version,
start/end commit and actual process exit in `run.json` and `summary.json`.
Before/after SHA-256 and Git blob inventories agree. Package configuration,
package graph, workspace lock and runtime binary bindings remain unchanged.
All selected test suites executed, every started event finished exactly once,
and no error, overflow or missed-tap diagnostics appeared in the accepted runs.

The editor run acquired the shared `flutter-cli.lock`, preventing concurrent
Flutter tool invocations. Dart engine and VM panel commands use the existing
package configuration without dependency resolution. The runtime is the same
locally provisioned Flutter 3.47.8 / Dart 3.13.7 used for the Zotero cohort.

## Preserved receipt correction

The original engine receipt runner exited one because it resolved Dart's
relative JSON suite paths against the repository directory instead of the
recorded engine test working directory. The test process itself exited zero,
with all 526 tests passing; all source/runtime guards already passed.

[suite-path-correction.json](engine/suite-path-correction.json) records the
exact 19 observed paths and exact 19 selected paths after resolution against
the saved working directory. It rechecks raw completion events, counts,
skips, source guards and runtime guards. The original
[summary](engine/summary-before-path-normalization.json) and
[executed runner](engine/run_spelling_at_execution.py) are retained. The
corrected summary explicitly refers to this derivation. No test was rerun,
and neither source nor test content changed for the correction.

`run_spelling.py` contains the corrected path handling for reproduction;
`correct_suite_paths.py` is the retained derivation script used on this run.

## Reproduction

Use the same validated runtime/package workspace described in the parent
report. Supply fresh output directories because the runner refuses to replace
an existing run receipt:

```bash
python3 run_spelling.py --cohort engine \
  --repo /path/to/quds_office_suite \
  --workspace /path/to/validation-workspace \
  --toolchain /path/to/zotero-toolchain \
  --output /path/to/new-engine-results

python3 run_spelling.py --cohort editor \
  --repo /path/to/quds_office_suite \
  --workspace /path/to/validation-workspace \
  --toolchain /path/to/zotero-toolchain \
  --output /path/to/new-editor-results

python3 run_spelling.py --cohort panel \
  --repo /path/to/quds_office_suite \
  --workspace /path/to/validation-workspace \
  --toolchain /path/to/zotero-toolchain \
  --output /path/to/new-panel-results
```

Raw test events, stderr, individual case lists, synthetic-event exclusions and
artifact hashes are retained under `engine/` and `editor/`. The panel's raw
stdout and structured case results are under `panel/`.

## Scope

These are local Dart and Flutter checks using controlled native responses.
They do not qualify an installed operating-system dictionary, a physical
device, desktop application interaction, AOT output or JavaScript parity.
The finite portable cases are not an estimate of general spelling accuracy.
No GitHub Actions or CI status was queried, awaited or rerun.
