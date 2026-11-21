# Final fetched-ref accounting

Captured UTC: 2026-11-21T19:39:16.323976+00:00.
Latest main: `2058a434b2bcc76e7fc7e8a449ff6ce31488eb25`. Checkpoint: `bb2dfd5272ff8de27ed2ec7f68b71801a2e41886`.

The exact snapshot includes every fetched remote ref. Symbolic origin/HEAD is retained in the raw snapshot but excluded from totals.

## Summary

```json
{
  "total_refs": 385,
  "by_remote": {
    "origin": 43,
    "pull": 338,
    "upstream": 4
  },
  "by_disposition": {
    "ancestor_of_main_and_checkpoint": 364,
    "later_concurrent_ongoing_ref": 5,
    "current_checkpoint_ancestry_only": 2,
    "independently_verified_historical_equivalent": 14
  },
  "initial_tips": 375,
  "initial_coverage": {
    "ancestor_of_main_and_checkpoint": 361,
    "independently_verified_historical_equivalent": 14
  },
  "historical_proofs_verified": 14,
  "new_refs": 10,
  "advanced_refs": 3,
  "main_is_checkpoint_ancestor": true,
  "snapshot_stable": true
}
```

All initial task-start tip identities are checked independently of whether their branch names advanced later. Historical proof candidates are reverified from Git object identities.

## Later concurrent ongoing refs

| Ref | SHA | Subject |
| --- | --- | --- |
| refs/remotes/origin/codex/word-vba-typography-20261121 | `a646cf761f7eafe7915988a1d84f90ca6dbe5793` | feat(word): add guarded VBA font baseline positioning [skip ci] |
| refs/remotes/origin/codex/zotero-roundtrip-20261121 | `7a830c71a91e414b2fe02f64d6bc9422d6b41211` | Qualify Zotero images on current main with 1688 local passes [skip ci] |
| refs/remotes/origin/codex/zotero-roundtrip-complete-20261121 | `538d002ab9da5a8a12ef6adbb66c8062b0560810` | Preserve styled inline pictures in ODT comments [skip ci] |
| refs/remotes/pull/336 | `a646cf761f7eafe7915988a1d84f90ca6dbe5793` | feat(word): add guarded VBA font baseline positioning [skip ci] |
| refs/remotes/pull/337 | `7a830c71a91e414b2fe02f64d6bc9422d6b41211` | Qualify Zotero images on current main with 1688 local passes [skip ci] |

These refs are accounted for as ongoing work. This audit does not claim they were merged, qualified, or approved for integration.

## Incoming main commits absent from checkpoint

None.

No Git mutations or GitHub Actions interactions were performed.
