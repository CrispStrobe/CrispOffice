# Native spreadsheet fill preservation — 14 November 2026

The implementation is saved at `9219189e9a07103b029eaeb050658ab819356591`.
It retains native fill identities during unrelated formatting edits and tracks
explicit solid/no-fill commands through import, sorting and editor history.
The change does not add gradient painting to the Quds renderer.

## Executed results

[focused-validation.json](focused-validation.json) records 26 passing engine
tests, including all five new fill regressions. They exercise direct and isolate
workbook saves, native style preservation, explicit fill commands, sorting, and
the existing namespace/style regressions. [engine-tests.log](engine-tests.log)
contains the complete observed output.

The same style-level witness was run against the exact starting source
`6e8ee9476c99676886f9d424abdb399cffe37882` and the implementation checkpoint.
The baseline fails 9 of 13 checks; the fix passes all 13. The
[source-controls-recorded.json](source-controls-recorded.json) receipt preserves
the earlier collector output, including source and fixture hashes. Both control
logs were recovered exactly: their SHA-256 hashes match that recorded receipt.

The first editor attempt executed zero tests: its compiler cache exhausted the
available filesystem. That failure remains preserved in
[editor-enospc-observed.log](editor-enospc-observed.log).

The [resumed editor gate](editor-resume/README.md) closes that execution gap on
source `79d001522c6550a21b01f2c033fb293c372d3208`: all **11 focused editor tests**
passed, including the six new fill/history regressions. Focused analysis of nine
production/test items passed with zero issues. All 405 recorded inputs remained
unchanged. Exact input hashes, resolved dependency files, runtime, command
receipts and complete logs are retained in that directory. Its initial sparse
SDK analysis setup failure is preserved alongside the successful analysis-only
retry.

After the additional cell-state and speaker-note fixes arrived, the
[combined follow-up](integrated-followup/README.md) passed **seven engine and
53 editor tests** on source `c37789b596a6f6516d9e2cee78ce57ab33872b07`, with zero
analysis issues across ten items and 409 unchanged recorded inputs. That cohort
retains the native-fill regressions while checking locks and modeled PDF-border
state through sorting/history, speaker-note history, and pending-save revision
boundaries. Its counts overlap the earlier tests and are not additive.

Independent app-side OpenXML validation subsequently found a font-child ordering
error in the authored fixture; all three actual uploaded workbooks were valid.
Checkpoint `3543b29a2daa82279777802df8728d72dc96e9c5` corrects only that ordering.
The [schema-valid fixture gate](schema-valid-fixture/README.md) passes its five
engine and six editor fill tests, with 402 unchanged inputs. All 385 production
Dart files match the earlier combined run exactly. The app retains the original
schema failure and the corrected-source acceptance as separate records.

## Recovery and reproducibility

The new implementation and tests had already been saved remotely before the
filesystem failure. The remaining evidence was recovered through the GitHub
connector from observed tool output and exact source shown in the conversation.

The 899-file local test-input manifest and its digest were not printed and could
not be recovered. They are not claimed as remotely preserved. The engine run
used checkpoint `9219189` plus two comment-only documentation edits; the parent
recovery report preserves that patch separately.

The reusable collector was reconstructed exactly from its source, including
the later harness filename change. Its pre-rename content was checked against
the SHA-256 recorded in the original receipt. The harness supplied here is the
unformatted version previously displayed and executed successfully. Its byte
hash differs from the later formatted harness recorded in the archived receipt.
Re-running the collector generates a new receipt matching the supplied files:

```sh
python3 docs/evidence/office-fill-preservation-20261114/run_controls.py --dart /path/to/dart
```

The collector extracts both source snapshots from Git and requires the expected
nine baseline failures and thirteen candidate passes. It never treats testing
the fixed source twice as successful negative-control evidence.

This scoped engine evidence does not claim a fresh full application gate,
browser/device validation, OpenXML schema validation or rendered visual
comparison for the new fill change.
