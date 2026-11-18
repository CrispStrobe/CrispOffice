# Incoming integration qualification

**78 substantive tests pass across five existing suites, with zero skips/errors
and all three actual test processes exiting 0.** Every accepted run is bound to
final combined source `b2bcfc23e692476d16d9a7a534ea95a93ae94cd3`, containing the
observed spelling/document-review frontier and current merged main.
These counts are separate from the complete Zotero cohort.

| Cohort | Suites | Passed | Seconds | Actual exit |
| --- | ---: | ---: | ---: | ---: |
| Engine comparison | 2 | 39 | 14.92 | 0 |
| Editor review | 2 | 31 | 15.24 | 0 |
| Studio comparison | 1 | 8 | 8.39 | 0 |
| **Total** | **5** | **78** | | **0** |

## Existing suite coverage

| Existing suite | Passed |
| --- | ---: |
| `word_comparison_test.dart` | 24 |
| `word_comparison_adversarial_test.dart` | 15 |
| `word_review_controller_test.dart` | 18 |
| `word_review_dialog_test.dart` | 13 |
| `studio_document_comparison_test.dart` | 8 |

The Studio suite checks real generated DOCX comparison inputs and the changed
XML preflight: valid namespaces/empty Word documents are retained; spreadsheet
inputs, missing main content, wrong root/namespace/body, multiple/nested bodies,
truncated XML, undeclared names/entities and other malformed XML are rejected.
It does not load an arbitrary external document corpus.

The engine runner invokes `package:test` directly with the configured Dart
package graph, JSON reporting and concurrency 2. The editor and Studio runners
use `flutter test --no-pub`; they acquire the shared `flutter-cli.lock` before
capturing source or running Flutter, serializing with the complete Zotero cohorts.
No runner invokes Pub or GitHub Actions.

Each cohort retains the exact command/runtime version in `run.json`, raw actual
process output in `events.jsonl` and `stderr.log`, substantive outcomes in
`cases.json`, separately excluded hidden suite-loading events, and acceptance in
`summary.json`. The aggregate `summary.json` binds the three cohort summaries.

## Source and process guards

All accepted runs started and ended at the final combined source commit above.
Before/after SHA-256 and Git-blob inventories remain identical for **391 engine**,
**472 editor**, and **505 Studio** source/selected-test inputs. These overlapping
input counts are not test totals. Each scope includes relevant engine/parser
libraries; editor adds editor libraries and Studio also adds example libraries.

The bound runtime binaries, package graph/configuration, workspace lock and test
package manifest remain unchanged. Every selected suite ran, every started event
completed once, and each runner emitted one successful completion. All three
runs have zero print events, empty stderr and no warning/overflow/missed-tap
diagnostics; their `diagnostics.json` files record the raw-output scan and hashes.

## Linux golden path verification

**All seven existing Linux-specific routes resolve to checked-in PNG files.**
A standalone probe invokes the actual `officeGolden` helper on this Linux host.
For each returned path, `golden-paths/verification.json` records PNG dimensions,
byte count, SHA-256 and both actual/final-HEAD Git blob identities. All match.
The helper itself is unchanged before/after and matches the checked-in file:
SHA-256 `a379efdd2ea6658fea371ae361e5321ca431cf121067b74dfd65be6fba3a2bf7`.

This verifies path routing and existing image identity only. It does not render
new goldens, compare fresh screenshots, update images or add test cases. The
probe command and complete source are retained with its actual exit 0 and output.
The seven checks are not added to test totals.

## Earlier qualification retained

The earlier 39-engine/31-editor runs passed against the earlier integration.
When the final incoming frontier was incorporated, their complete original
runners, logs, inventories, summaries, golden-path check and README were moved to
`../attempts/incoming-before-frontier/`. Those 70 overlapping passes are retained
for traceability and excluded from the accepted 78-test total above.

## Reproduction

Run `engine/run_incoming_engine.py`, `editor/run_incoming_editor.py`, or
`studio/run_incoming_studio.py` with `--repo`, `--workspace`, `--toolchain` and a
fresh `--output` directory. Run `golden-paths/check_golden_paths.py` with `--repo`,
`--toolchain` and another fresh `--output` directory. All use the genuine runtime
and workspace layout recorded by the surrounding Zotero validation report.
