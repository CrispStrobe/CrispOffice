# Mail bulk actions: independent local intake

Status: **FAIL** at `b60c0ec26f2a80c984076fb1d480eb2e641b542e`.

Captured 38 fork branches, 272 fork PR heads, 4 upstream branches and 4 upstream PR heads. Uncovered current references: **6**. Uncovered earlier API-captured references: **0**.

After executor recovery, all 14 historical substitutes were independently recomputed from immutable Git objects: 13 complete-tree identities and the exact 37 changed ODT paths. Modes, types and object IDs agree, and each accepted substitute is a target ancestor. This supersedes only the earlier snapshot’s local-replay limitation; the original API report is retained as historical evidence.

History reconciliation `4d9cddeea2608ac1d7a8f1acfdd5ecc1482f5114` has exactly the parents `c954d00d2fc85604ae394674bca91ea8a1dede0e` and `332d7b26a320ca560f4f2214e1e63da9392269ab`. Its complete Git tree equals main’s tree `1d279ced85f247b7fae5e21a04dd8ea354a75919`; the temporary golden workflow remains absent. The reconciliation is an ancestor of this reviewed target.

## Replay

From the repository root, with the recorded objects available:

```sh
python3 docs/validation/mail-bulk-actions-20261120/intake-local.py --report-prefix intake-local-latest
```

To refresh, fetch fork/upstream branches and PR heads into the dedicated `refs/audit-bulk/` namespaces, then add `--capture --target <commit>`. The checker writes only its own report files. Unknown heads fail the audit. Incoming runtime evidence is not a new test run. GitHub Actions, workflow runs and status endpoints were neither queried nor awaited.
