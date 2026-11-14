# Phase C final integrated acceptance

The final eight-file editor gate passed **100 tests, zero failures** on source
commit `0f935a6f24ae11aa9851a5cc3498808554194446`. Scoped analysis of the controller
and the new style test file reported **no issues**.

| Test file | Passed |
| --- | ---: |
| `sheet_style_history_test.dart` | 20 |
| `sheet_grid_history_test.dart` | 14 |
| `sheet_view_history_test.dart` | 20 |
| `sheet_fill_intent_history_test.dart` | 6 |
| `sheet_font_color_intent_test.dart` | 2 |
| `sheet_explicit_style_history_test.dart` | 3 |
| `sheet_cell_state_history_test.dart` | 2 |
| `pending_edit_save_test.dart` | 33 |
| **Total** | **100** |

## Source and input binding

All **409 captured inputs remained unchanged** through tests and analysis.
At capture, all **406 tracked inputs matched the source commit's Git blobs**.
The remaining three generated inputs—`pubspec.lock`,
`.dart_tool/package_config.json`, and `.dart_tool/package_graph.json`—have their
exact gzip snapshots alongside the receipts. `inputs.json.gz` records every
input path and SHA-256; `runtime.json` identifies the toolchain and environment.
External package-cache and runtime/native payloads are not archived here.

The manifest archive SHA-256 is
`137c85e52b59c418c209783c24d821acbde78c8e45d2358dd1ff81f35b28dd91`.
The raw `completion.json` SHA-256 is
`948bb8d17e6a1106ff76b4133e359a484643d77973fb3119609dcda4bcecc1c6`.

`validation.json` records the exact test command and outcome; `analysis.json`
records the scoped analyzer command. The full logs and the new test's exact
source snapshot are included. The executed capture/test/analysis runner is
[../run_phase_c_corrected.py](../run_phase_c_corrected.py).

## Retained initial attempt

The initial attempt is archived at
[../phase-c-initial-attempt/](../phase-c-initial-attempt/). It recorded 96 passes
and four new-test fixture failures: formula-bearing cells were assigned a
numeric type, and expected state was captured before normal recalculation
changed their type to formula. The [one-line correction](../phase-c-correction.patch)
recalculates that fixture before capturing expected state. Assertions and
production code were unchanged; the corrected test file is the only input
that differs between the two attempts.

All raw receipts, logs, and gzip snapshots were copied byte-for-byte. Raw
receipts retain their original scratch paths, including the initial-attempt
reference `../phase-c-positive/validation.json`; use the archived path above
when following that reference in this repository. The full correction record
is [../phase-c-correction.json](../phase-c-correction.json).
