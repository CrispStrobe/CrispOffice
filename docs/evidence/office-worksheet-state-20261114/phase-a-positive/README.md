# Worksheet view commands: positive validation

Implementation checkpoint: `e02feac5fba98fbd7b9c20ee4a2593ac4d257400`.

All 20 tests in `sheet_view_history_test.dart` pass on this checkpoint. The same
test bytes produced 20 assertion failures on baseline
`2d2a7be43e19b478c532025fe1f275ed7b00ef75`. The controller is the only changed
input between the two runs. All 400 recorded inputs remained unchanged during
the positive execution and focused analysis.

The cases cover RTL and freeze/unfreeze commands, dirty state and revisions,
undo/redo ownership, read-only interaction modes, unchanged settings, pending
cell drafts, viewport clamping, and direct/isolate native saves. Focused analysis
of the controller and new test reports no issues. This receipt does not establish
app host, browser, device, renderer, or grid-history acceptance.

`completion.json` records both outcomes, the exact input comparison and file
hashes. `validation.json` and `analysis.json` retain commands, source revisions,
exit codes and log hashes. The raw logs, compressed test source, dependency
configuration, lockfile, runtime settings and 400-file hash inventory are kept
alongside them. The original failing evidence is retained in
`../phase-a-baseline/`.
