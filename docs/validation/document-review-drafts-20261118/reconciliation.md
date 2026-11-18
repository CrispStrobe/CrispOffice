# Incoming reconciliation audit

Verified locally against `bfa88aab88a74028285619dfa07f3a81868fe59b`. No GitHub Actions status was queried or awaited.

The bounded final observation was recorded at **2026-11-18T19:23:15.181640+00:00**. It contains **210 fork branches, 171 actual PR heads, and 4 upstream branches: 385 references to 251 unique heads**.

**357 references / 237 heads** are included through commit ancestry. **28 references / 14 historical heads** are verified equivalents. No head is unaccounted for.

## Initial reconciliation

The four initial merge checkpoints preceded the first application-change checkpoint. The thesaurus merge resolved two conflicts: relocated duplicate proofing-target declarations and shortcut ordering. The resolved files retain the first-parent versions, which already contain the incoming thesaurus work and newer Zotero note behavior.

| Incoming | Published merge | Conflicts |
| --- | --- | --- |
| `ff151851` | `d1dc3416` | 0 |
| `b9e8c159` | `2bdd66dd` | 2 |
| `17fe8db8` | `34c585e2` | 0 |
| `9232b056` | `39eada31` | 0 |

## Final bounded reconciliation

All four final merges have disjoint changed paths on the two sides, and the incoming file delta exactly matches the saved merge.

| Incoming | Published merge | Incoming files |
| --- | --- | --- |
| `46d7422d` | `078f3733` | 317 |
| `0e84dc95` | `fc65ed55` | 26 |
| `c93fc23b` | `46191bd8` | 47 |
| `637b67c5` | `bfa88aab` | 2 |

## Historical equivalents

Ten heads have only patch-equivalent commits according to `git cherry`; three have trees identical to already-integrated commits; one has all 37 changed path entries identical to the corresponding merged PR #140 commit. The equivalent commits are ancestors of the final source. These checks were repeated against the frozen source.

## Provenance notes

- The bounded final snapshot records review branch and PR162 at b9728ea1. Later self-checkpoints c914be7a and the final merges are descendants and intentionally do not trigger another moving-frontier observation.
- historical-equivalence.json retains inherited evidence_record="incoming-reconciliation.json" labels from the prior turn. That provenance resolves to docs/validation/document-review-inflight-20261118/incoming-reconciliation.json; all equivalence methods were independently rechecked against the final source in this report.

All ten saved checkpoint trees and expected parents match the publication records. Local merge trees match the published merge trees. The repository HEAD and working-tree status stayed unchanged during this audit.

Inconsistencies: none.

## Latest saved candidate

Candidate `66919cf857fe2439a3512a821817f35981760a75` has the expected tree `33faed80ab06c0d5aa3e8b9faa73ceff27892246` and retains `bfa88aab88a74028285619dfa07f3a81868fe59b` as an ancestor. The same bounded **385 references / 251 heads** remain valid: **357 references / 237 heads through ancestry**, plus **28 references / 14 historical equivalents**. All historical methods were checked again against this candidate. No new remote frontier was observed.

The vendored `third_party/enough_mail` tree is exactly `e9bc3047922df465b29806b47ea0b06858345169` in both this candidate and incoming Mail commit `46d7422d5ac356c327759872ff28adcd154b75ad`. The root reported that the Mail fixes pass offline lock enforcement and strict analysis, with lock, package configuration, and runtime hashes unchanged. This audit did not rerun those checks.
