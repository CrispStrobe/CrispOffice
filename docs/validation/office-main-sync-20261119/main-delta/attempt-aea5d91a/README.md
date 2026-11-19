# Failed native reporter attempt at `aea5d91a`

This exact-source attempt remains **FAIL**. Its native groups observed 159
successful test assertions, zero failed assertions and zero skipped cases,
but three non-JSON missing-dictionary diagnostics violated strict reporter
admission. These observed successes are not accepted qualification totals.
The 17 publisher controls passed separately. Node and browser compilation
never started because the native gate failed.

The source, runtime, head and tracked checkout remained unchanged throughout.
See [original execution](execution.json), [indexed raw evidence](evidence.index.json)
and [archive audit](archive-audit.json). No results from this attempt are added
to a later accepted gate.

Investigation also reproduced a product defect: a valid affix file paired with
an absent dictionary could return a successful native result. The following
source checkpoint adds a preflight for both files, an explicit regression and
real temporary paths for the lifecycle fixture. The reporter parser remains
unchanged. Failing-before development evidence and the final repaired run retain
their own identities.
