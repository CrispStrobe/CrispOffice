# Incoming integration qualification

This checks the document-comparison code and Linux golden path selection brought
in before the new Zotero work. It is separate from the Zotero test totals.
The accepted incoming cohort totals **70 substantive passes across four suites**,
with zero skips/errors and both underlying test processes exiting 0.

## Engine comparison

**39 substantive tests pass in two existing suites, with zero skips/errors and
actual Dart process exit 0.** The run took 12.68 seconds on the genuine local
Dart 3.13.7 runtime. Both start/end heads were
`604fa00427f88d18ffa96df71128c38e38502afb`.

| Existing suite | Passed |
| --- | ---: |
| `word_comparison_test.dart` | 24 |
| `word_comparison_adversarial_test.dart` | 15 |
| **Total** | **39** |

The runner invokes `package:test` directly with the configured Dart package graph,
JSON reporting and concurrency 2. It does not invoke Pub or GitHub Actions.
`engine/run.json` retains the exact command and runtime version;
`engine/events.jsonl` and `engine/stderr.log` retain the actual process output.
`engine/cases.json` lists substantive outcomes separately from two hidden suite
loading events. `engine/summary.json` records the actual exit, successful runner
completion and guards.

All **391 engine/parser source and selected-test inputs** have identical before
and after SHA-256/Git-blob inventories. The bound Dart binary, package graph,
package configuration, workspace lock and test package manifest are unchanged.
Every started event completed once and both selected suites executed.

## Editor review

**31 substantive tests pass in two existing suites, with zero skips/errors and
actual Flutter process exit 0.** The run took 10.26 seconds on genuine local
Flutter 3.47.8 / Dart 3.13.7. Both start/end heads were
`6aa6ffb5043cd03b344e582bb6119a4da63823c7`.

| Existing suite | Passed |
| --- | ---: |
| `word_review_controller_test.dart` | 18 |
| `word_review_dialog_test.dart` | 13 |
| **Total** | **31** |

The runner uses `flutter test --no-pub`, JSON reporting and concurrency 2. It
acquires the same `flutter-cli.lock` used by the main Zotero cohorts before
capturing inputs or running Flutter, so the invocations cannot race. The exact
command, raw JSON stream, actual exit and cases are retained under `editor/`.

All **472 editor/engine/parser source and selected-test inputs** remain identical
before/after, as do the bound Dart/Flutter tester binaries, graph, configuration,
workspace lock and test package manifest. Both suites ran and every started
event completed once. There are no print events, warning/overflow/missed-tap
diagnostics or stderr bytes; the separate `editor/diagnostics.json` records this
scan of the retained output.

## Linux golden path verification

**All seven existing Linux-specific routes resolve to checked-in PNG files.**
A standalone probe invokes the actual `officeGolden` helper on this Linux host.
For each returned path, `golden-paths/verification.json` records PNG dimensions,
byte count, SHA-256 and both actual/current-HEAD Git blob identities. All match.
The helper itself is unchanged before/after and matches the checked-in file:
SHA-256 `a379efdd2ea6658fea371ae361e5321ca431cf121067b74dfd65be6fba3a2bf7`.

This verifies path routing and existing image identity only. It does not render
new goldens, compare fresh screenshots, update images or add test cases. The
probe command and complete source are retained with its actual exit 0 and output.

## Reproduction

Run `engine/run_incoming_engine.py` or `editor/run_incoming_editor.py` with
`--repo`, `--workspace`, `--toolchain` and a fresh `--output` directory. Run `golden-paths/check_golden_paths.py` with
`--repo`, `--toolchain` and another fresh `--output` directory. Both use the
runtime/workspace layout recorded by the surrounding Zotero validation report.
