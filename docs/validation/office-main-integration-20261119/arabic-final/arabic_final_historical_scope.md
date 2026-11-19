# Arabic integration: historical evidence and reference scope

This independent read-only audit binds to frozen source
`e41679f85c511bc8cf42447d3d1af0931884dee2`, tree
`9cdc66213dc329265057a8511357ce53f4583604`.

## Captured history is included

The previously saved inventory still accounts for **409 actual refs**:
213 fork branches, 175 PR identities, 17 tags and four upstream branches.
It contains 267 distinct peeled commit heads. At the new frozen source,
**381 refs are ancestors and 28 have historical source-equivalence proofs**.
All 14 equivalence proofs were freshly reverified; no refs are unaccounted for.

Four explicitly supplied later incoming heads are also ancestors:

| Observation | Included commit |
| --- | --- |
| Main after PR176 | `f059065fa622da8cee7824d66d29a2aff414d529` |
| PR177 head | `c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e` |
| PR178 head | `0b8f8f7f78fbf4e2e26671ecf9a0d858c38ca75c` |
| Main after PR180 | `f7117a493055008a72e6e16713dd67a4f7c2ad39` |

The PR176/PR180 merge secondary parents were derived from their immutable
commits and independently checked as ancestors. These four known-head
observations are an addendum to the saved inventory, not a fresh advertisement
or an increase to 413 unique refs. Stale local PR aliases remain recorded as
originally observed. No moving remotes were queried or represented as frozen.

## Historical test files and dependency closures

The original 129-suite/2,018-case qualification, overlapping 14-suite/208-case
native fixture and successful web compilation remain attributed to
`39843ed4874c7b56572c7aa8195716e5892aeca2`. Their archives, indexed members and
historical source hashes were verified; no historical application tests or web
build were rerun by this audit.

Of 4,992 ordinary original source records, **4,968 remain identical and 24
differ**. There are 37 added non-documentation repository paths relative to
the original tree. All **129 original suite files** remain identical.

The Arabic provider's engine export and registration in the default Word and
Studio proofing engines change the conservative tracked import/export/part
closures:

| Historical cohort | Suites | Changed tracked closures |
| --- | ---: | ---: |
| Engine / review / Zotero | 42 | 33 |
| Editor / Notes / headers / Zotero | 73 | 72 |
| Studio / review / navigation | 10 | 10 |
| Mail reader | 4 | 4 |
| **Total** | **129** | **119** |

Ten original tracked closures remain identical. The four Mail-reader closures
still differ through the previously changed Mail core message/provider files;
none of the original 129 closures reaches the modified vendor TLS/parser code.
The remaining closure changes reach the Arabic provider/export, default Word
proofing registration and, for Studio, its provider registration.

All **five protected Notes files remain byte-identical** to the original
qualified versions. That file-preservation finding does not imply identical
transitive proofing behavior. The separate `ac1e4c8c` finding of 125 unchanged
closures / 1,988 historical cases remains a prior-phase result and must not be
reattributed to this Arabic source.

## Native fixture and web build limits

All original fixture/helper file bytes remain identical, but **all 14 native
tracked closures and the web fixture closure now have changed inputs** through
the engine export/provider and default Word proofing path. The historical
native pass and web build are preserved evidence for their original source;
they are not current-source results. Static closure expansion is not a test
failure and does not itself require rerunning all 129 suites. Fresh affected
engine/editor/Studio and Mail qualification is reported separately by its own
source-bound gate, without adding overlapping historical counts.

## Prior phase preserved and replay

The five saved `ac1e4c8c` capture/audit files were hash-checked before and after
this work and remain unchanged. HEAD, index and refs also remained unchanged
during the saved-reference audit. Source and tested-runtime files were not
edited; no GitHub Actions were queried or awaited.

The final reports are `arabic_historical_continuity.json`,
`arabic_ancestry_review.json`, `arabic_known_heads_review.json` and
`arabic_prior_phase_preservation.json`. Their replay scripts and unchanged
saved capture inputs are listed in `arabic_review_index.json`.
