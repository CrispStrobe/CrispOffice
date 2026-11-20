# Captured branch and PR reconciliation

**All captured work is retained** by published candidate `906843fbf2bfc20f8040543a122d88c93f20de83` (tree `b6671cdc8383261711e00a77cf9f07a1dc5da18e`). No missing commit objects, unresolved captured heads, or genuinely missing work remain within the two saved inventories.

| Saved inventory | Branch rows | PR rows | Branch disposition | PR disposition |
| --- | ---: | ---: | --- | --- |
| `initial-remote-inventory.json` | 18 | 100 | 9 ancestors; 9 verified equivalents | 98 ancestors; 2 verified equivalents |
| `remote-intake-02.json` | 15 | 100 | 6 ancestors; 9 verified equivalents | 98 ancestors; 2 verified equivalents |

Together these contain **117 distinct captured commit heads**: **106 direct ancestors** of the candidate and **11 independently recomputed historical equivalents**. The 200 PR observations cover 100 distinct PR numbers. The eleven equivalence checks cover all nine older divergent branches plus the two PR-only heads below. All **477** complete original delta path comparisons matched in mode, object type, object ID, and deletion/absence state. Six pairs additionally have identical entire trees.

| PR-only historical head | Captured original | Retained equivalent | Complete original delta |
| --- | --- | --- | ---: |
| #147, ODT column boundary | `cee6e2632f891a3fe21c5c02d6bf508805973051` | `bb5556e8cc4cb73e2c668b5319a2844a20c6c50c` | 105 paths; identical full tree |
| #152, Office union | `da9c956ec5d65c0e5a9f9ea84c2b0bca98e824a0` | `23f3b4204fce45d38a103e3159bdc7f1e8d37c4e` | 79 paths; identical full tree |

## Evidence and reproducibility

- `reconciliation-906843.json`: complete final report, every captured branch/PR row, exact candidate and head trees, full per-path proofs, snapshot changes, and zero unresolved findings.
- `reconciliation-e129.json`: initial audit against the preceding published checkpoint, with the same coverage and successful result.
- `summary.json`: compact counts and findings.
- `audit_captured_work.py`: portable auditor using only local read-only Git commands.
- The two adjacent inventory JSON files are byte-identical copies of the resumed repository snapshots; their hashes are embedded in the reports.
- `historical-mappings.json`: immutable original/equivalent pairs cross-checked against both the retained Zotero research-materials and VBA initial reconciliation ledgers. Ledger paths and SHA-256 digests are retained. Earlier claimed success is not used as proof: identities and ancestry are recomputed.
- `object-fetch.json`: records fetching the two known PR-only objects and the exact published candidate without destination refs, tags, or FETCH_HEAD writes.

Run from any directory after the captured commit objects are present in a clone:

```sh
python /path/to/audit_captured_work.py --repo /path/to/quds_office_suite --candidate 906843fbf2bfc20f8040543a122d88c93f20de83 --output /path/to/report.json
```

The auditor disables automatic lazy fetching and optional Git locks, and fails with explicit unresolved rows when required objects are absent. It does not discover heads, contact GitHub APIs, query Actions/status endpoints, change refs, stage files, or modify product source. Its output JSON is the only written file.

## Interpretation

This audit is bounded to the exact saved branch inventories and latest-100-PR samples. It makes no assertion about newer uncaptured remote work. The initial capture has no precise wall-clock timestamp; that limitation remains in the copied snapshot. The later capture spans 2026-11-20 05:21:08–05:21:09 UTC.

The complete original delta is calculated from the unique merge base of each original/equivalent pair to the original head with rename detection disabled. An equivalent commit must itself be an ancestor of the audited candidate. This proves the captured work exists in retained history; later intentional edits and behavioral qualification of the final source are evaluated separately by the integration validation cohorts.
