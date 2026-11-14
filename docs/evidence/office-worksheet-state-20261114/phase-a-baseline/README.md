# Worksheet view-setting negative control

The 20 new regressions were executed against unchanged production source
`2d2a7be43e19b478c532025fe1f275ed7b00ef75`. All 20 failed through normal
assertions; no compilation failure occurred. The full log, exact new test source,
400 input hashes, resolved dependency snapshots and runtime record are retained.
All recorded inputs stayed unchanged during execution.

The failures cover persisted RTL/freeze settings missing dirty/revision/history
updates, mutation in viewing/selecting modes, no-op and owning-sheet behavior,
pending drafts, and direct/isolate save sequences. This is an expected failing
baseline, not passing acceptance of a later implementation.

The sibling run_phase_a.py preserves the collection/execution procedure and its
original workspace layout. Reproducing the baseline requires the stated source
commit plus the exact decompressed sheet_view_history_test.dart snapshot.
