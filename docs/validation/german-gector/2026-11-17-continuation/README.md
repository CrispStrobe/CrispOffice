# German grammar continuation — 17 November 2026

## Remote synchronization

The continuation started from provider checkpoint `216d9a4`. The captured
inventory covers 381 branches in the four cooperating repositories. Quds had
new main, morphology, Office fidelity, annotation and continuation work; the
other three grammar branches and their relevant base histories were current.
No GitHub Actions run was dispatched, polled or awaited.

Integration commit `aa6c50ed3736cea2c871f4bed7ae18a60e0cbb8b` retains every
captured Quds branch tip as an ancestor, including the two byte-verified section
histories equivalent to main. All source changes are preserved through merge
parents; no incoming feature branch was reset or rewritten. `integration.json`
records exact inputs, the final tree, conflict decisions and checks.
`incoming-refs.json.gz` contains the complete captured branch/PR inventory.

The ODT writer conflicts were resolved around the newer bounded comment and
note implementation, keeping main's section layout styles. Independent source
comparison checked GECToR preservation, ODP transforms/tables, annotation
exclusion, complete note regression coverage and section support.

Six focused engine test files covered 119 distinct tests. The first invocation
passed 118 and failed one fixture lookup because it was run from the repository
root. Running that eight-test file from the engine package passed all eight.
Both logs are retained; no product test assertion or fixture was changed to
resolve the invocation error.

## Recovered compiled baseline

The previous completed AOT receipt is preserved unchanged in the
[provider evidence](../2026-11-17-native-dart/README.md). Its source/runtime
identities and all case outputs were independently rechecked before new guard
work. Keep this v1 baseline and its JIT comparison immutable.
