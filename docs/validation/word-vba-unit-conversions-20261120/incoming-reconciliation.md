# Incoming branch reconciliation addendum

This addendum applies when the publication checkpoint takes the reviewed feature
head `dd8e73a7d6252b336b2e7a437c4931addc42d491` and later incoming head
`332d7b26a320ca560f4f2214e1e63da9392269ab` as its ordered merge parents.
The immutable initial [intake.json](intake.json) remains the historical snapshot;
[incoming-reconciliation.json](incoming-reconciliation.json) records the exact
ancestry, file delta and publication checks for this resolution.

## Bring in the final captured head while retaining main's deletion

The only initially excluded captured head was
`fix/main-green-20261120` at `332d7b26a320ca560f4f2214e1e63da9392269ab`.
Its sole parent is `1e723bd4bc96e07b1b790daf9b82897a846c6096`, which is already an actual
ancestor of initial main `c954d00d2fc85604ae394674bca91ea8a1dede0e` and the feature
checkpoint.

That later head contains one commit changing one attribution-matrix row in
`.github/workflows/tmp-regenerate-editor-goldens.yml`. The complete parent-to-head diff
contains no other file. Initial main removes that 37-line temporary workflow.
The API comparison confirms the deletion, and the captured main workflow
directory confirms the path is absent.

This is therefore a single **modify/delete merge conflict**. The reviewed
resolution keeps main's existing deletion. Making the later head a merge parent
preserves its history, while explicitly discarding the conflicting matrix-row
edit. It does not reintroduce a temporary GitHub Actions workflow, and it does
not claim that the removed workflow content survives.

## Result for the initial captured snapshot

Once that checkpoint is published with the required parents and absent workflow,
every initially captured reference is incorporated or has the already-proven
squash equivalence:

| Captured source | Actual ancestors | Equivalent squash commits | Excluded / unclassified | Total |
| --- | ---: | ---: | ---: | ---: |
| Fork branch heads | 24 | 9 | 0 | 33 |
| Fork PR heads | 256 | 14 | 0 | 270 |
| Upstream branch heads | 4 | 0 | 0 | 4 |
| Upstream PR heads | 4 | 0 | 0 | 4 |

That is **311 references: 288 actual ancestors and 23 equivalent references**,
with zero final exclusions or unclassified entries in the initial snapshot.
The exact-tree and PR #140 file-identity proofs stay in the initial inventory.
The incoming source branch is preserved.

The final publication still requires a fresh remote-main check and verification
that the checkpoint and published main contain both reviewed parents. This
addendum is an ancestry and manual-resolution proof; it is not a Dart or native
runtime validation result. No Actions run, check, status or queue was queried.
