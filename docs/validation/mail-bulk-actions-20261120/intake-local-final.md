# Mail bulk actions: independent local intake

Status: **FAIL** at `65468fdff43c3acec20fd0d7fd8d4ae9d254d572`.

Captured 38 fork branches, 274 fork PR heads, 4 upstream branches and 4 upstream PR heads. Uncovered current references: **2**. Uncovered earlier API-captured references: **0**.

After executor recovery, all 14 historical substitutes were independently recomputed from immutable Git objects: 13 complete-tree identities and the exact 37 changed ODT paths. Modes, types and object IDs agree, and each accepted substitute is a target ancestor. This supersedes only the earlier snapshot’s local-replay limitation; the original API report is retained as historical evidence.

History reconciliation `4d9cddeea2608ac1d7a8f1acfdd5ecc1482f5114` has exactly the parents `c954d00d2fc85604ae394674bca91ea8a1dede0e` and `332d7b26a320ca560f4f2214e1e63da9392269ab`. Its complete Git tree equals main’s tree `1d279ced85f247b7fae5e21a04dd8ea354a75919`; the temporary golden workflow remains absent. The reconciliation is an ancestor of this reviewed target.

## Frozen source cutoff

Inventory: `docs/validation/mail-bulk-actions-20261120/intake-local-cutoff-refs.json` (SHA-256 `1dcc95a5959fa8f0347fea77751e4e12aaa1b4cec712fd6e36528da4a6ecc94f`). Latest fetched ref timestamp: `2026-11-20T20:57:12.305837+00:00`; manifest recorded `2026-11-20T21:08:35.177505+00:00`. This audit uses those saved heads. It does not imply coverage of later concurrent branch or PR changes. Latest main is checked separately before publication.

## Replay

From the repository root, with the recorded objects available:

```sh
python3 docs/validation/mail-bulk-actions-20261120/intake-local.py --report-prefix intake-local-final
```

To rebind this same frozen cutoff to a later target, add `--capture --target <commit> --cutoff-manifest docs/validation/mail-bulk-actions-20261120/intake-local-cutoff-refs.json` with a new report prefix. No ref fetch is needed. The checker writes only its own report files. Unknown heads fail the audit. Incoming runtime evidence is not a new test run. GitHub Actions, workflow runs and status endpoints were neither queried nor awaited.
