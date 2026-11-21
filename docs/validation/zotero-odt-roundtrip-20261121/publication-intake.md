# Final fetched-ref accounting

Captured UTC: 2026-11-21T20:07:24.727150+00:00.
Latest main: `aa861c28e336b17bcd4c259351164380cd6b1438`. Checkpoint: `4b33109aa85e077e2798265efa045d640e6ead4e`.

The exact snapshot includes every fetched remote ref. Symbolic origin/HEAD and upstream/HEAD are retained in the raw snapshot but excluded from totals.

## Summary

```json
{
  "total_refs": 386,
  "by_remote": {
    "origin": 43,
    "pull": 339,
    "upstream": 4
  },
  "by_disposition": {
    "ancestor_of_main_and_checkpoint": 369,
    "current_checkpoint_ancestry_only": 3,
    "independently_verified_historical_equivalent": 14
  },
  "initial_tips": 375,
  "initial_coverage": {
    "ancestor_of_main_and_checkpoint": 361,
    "independently_verified_historical_equivalent": 14
  },
  "historical_proofs_verified": 14,
  "new_refs": 11,
  "advanced_refs": 3,
  "main_is_checkpoint_ancestor": true,
  "snapshot_stable": true
}
```

All initial task-start tip identities are checked independently of whether their branch names advanced later. Historical proof candidates are reverified from Git object identities.

## Later concurrent ongoing refs

| Ref | SHA | Subject |
| --- | --- | --- |

These refs are accounted for as ongoing work. This audit does not claim they were merged, qualified, or approved for integration.

## Incoming main commits absent from checkpoint

None.

No Git mutations or GitHub Actions interactions were performed.
