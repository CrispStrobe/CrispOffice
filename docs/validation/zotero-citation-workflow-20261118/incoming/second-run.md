# Second incoming-cohort run — failed, evidence retained

Tested source: `00ac2edf606359cea003b4ebb3a5f3aaac7b67cf`. This attempt is
**not acceptance**. The guarded 18-suite run completed with **261 passed,
8 failed and 0 skipped**, actual Flutter process exit **1**, in 44.3 seconds.
Strict analysis and the nonmutating formatter passed all seven targets.

All **550** recorded source inputs matched the specified commit. Source,
dependency, runtime and workspace inventories stayed unchanged; all selected
suites executed and every test start finished exactly once. The report records
eight error events and zero layout/missed-tap diagnostics. No result from this
attempt is added to a final passing total.

## Diagnosis and follow-up

The repaired selection suite passed all nine cases, including immediate
rebinding at the current revision, stable caret and rejection of the stale
original issue. The other sixteen unaffected suites also passed. All eight
failures were in `word_live_review_changes_test.dart`: combined filters,
filtered navigation/resolution, accept shown, reject shown, stale filtered
batch, viewing mode, and narrow scaled English and Arabic flows. Each failed
inside the helper while `scrollUntilVisible` tried to find a child of the still
collapsed filter tile. Requiring hit-testable taps correctly prevented a false
success, but trying to reveal that hidden child before opening its parent was
the wrong order.

The integration owner authorized a second helper-only repair. It first reveals
the tile header, reads the public `Expansible.controller.isExpanded` state,
taps the header only when collapsed, and only then reveals/taps the dropdown.
This also distinguishes an expanded but off-screen child without closing its
parent. All taps retain the hit-testable assertion and use real pointer input;
the controller is read, not used to force a transition. No product behavior or
test cases were changed or removed.

Focused development attempts have separate source-diff, input, process-exit and
raw-event receipts under [development](development/). They are excluded from
the final acceptance count. The next full 18-suite acceptance attempt must use
a fresh saved source commit and a fresh output directory.

## Evidence

- [Full summary and static-check output](attempt-2/summary.json)
- [Raw machine events](attempt-2/events.jsonl.gz)
- [Before/after inputs and source binding](attempt-2/inputs.json.gz)
- [Runner output](attempt-2/runner.log)
- [Exact executed seven-target runner](attempt-2/run_incoming_editor.py)

The executed runner SHA-256 matches the summary. No GitHub Actions, workflow or
CI-status endpoint was used.
