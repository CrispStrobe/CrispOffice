# Independent late-integration verification

**PASS** for checkpoint `ed750f1f6b8acab88406fd506e0dd511adcc4485` (tree `9259de52b948a5edf0bbc86cad697a79ab38a08a`).

The actual Git commit has exactly the previous checkpoint and the three selected
original late heads as its four parents. All 12 imported path deltas were
independently reconstructed from their merge bases. Every destination was
unchanged before integration; the deltas are disjoint.

The complete resulting tree is exactly the prior checkpoint plus those deltas,
the independently reviewed macOS guard correction, and the two checkpoint
evidence files. No unrelated changes are present. The corrected shell script
matches SHA-256 `8592dd41fb59da7fa3ead05287005cfa06d90c02bb5de495e9f985062ffff904` and retains executable Git mode
`100755`.

All 1,131 qualified Word inputs preserve their exact selected path set, modes,
types and Git blob identities. The reviewed Word contract is unchanged. Local
HEAD remains the qualified source `0201b549d0dc3f601c50e36255d557034cb01699`, with a clean worktree for the
ongoing tests.

This is a source/ancestry proof. It does not claim that the pending Word gate
has completed, and it preserves the explicit absence of a real macOS build or
actual Bash 3 execution. No GitHub Actions were queried or awaited.
