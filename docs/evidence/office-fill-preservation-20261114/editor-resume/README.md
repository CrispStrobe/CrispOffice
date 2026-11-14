# Resumed editor validation

The focused editor cohort passed all 11 tests on canonical source
`79d001522c6550a21b01f2c033fb293c372d3208`, including the six new fill-history
regressions. The 405 recorded inputs did not change during execution.

The input hash manifest, resolved lock and package configurations, runtime,
command receipts and complete test log are retained here. This replaces the
earlier storage-blocked attempt with an executed result.

The first analysis invocation stopped before analyzing project code because the
sparse SDK checkout omitted its dev directory. Its original failure is preserved
in validation.json and focused-analysis.log; the overall initial receipt therefore
reports passed=false even though its editor-test step passed. The corrected
analysis-only retry passed with zero issues across nine production/test items,
recorded in analysis-retry.json and analysis-retry.log. completion.json binds the
final passing assessment to the retained receipts and input snapshots.

run_editor_gate.py records the original workspace invocation. It expects to live
in a sibling editor-validation directory beside quds_office_suite and toolchain;
its package-configuration snapshots contain paths from that environment.
