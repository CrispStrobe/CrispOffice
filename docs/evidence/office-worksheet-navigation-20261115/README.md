# Worksheet navigation evidence — 15 November 2026

## Baseline

`canonical-baseline` records the original production source at
`2d33a9213e760197557fb4fabcb422446f15227a` with the new regression tests:
**10 passed, 22 failed** across 32 cases. The 2,095 recorded inputs stayed
unchanged during execution. The receipt retains exact command, source tree,
test payloads, dependency resolution, runtime hashes and input manifest.

`canonical-baseline-initial` retains the first diagnostic attempt (8 passed,
24 failed). Two extra failures came from comparing cell-reference objects by
identity. Three assertions were corrected to compare their A1 addresses;
production source did not change between baseline attempts. Only the corrected
32-case baseline is used as the behavior witness.

These are new executions. They do not recover or relabel results mentioned
in the interrupted 14 November conversation. Positive acceptance is pending
at this checkpoint.
