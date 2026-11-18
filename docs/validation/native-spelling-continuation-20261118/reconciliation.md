# Native spelling continuation: incoming work reconciliation

The continuation starts from merged main
`1e07cb852766f8651815138785be74c64a09ddc0`. PR #159 was merged with an
expected head of `2292548eb69de2dbb5240ab9da59256f362137c6`; that head is the
integrated source baseline audited here. The merge preserves existing main
`1ffcf91a3443caf9a6e8b45a3e6cab3f041831ae` and the active work below.

| Incoming work | Included head | Disposition |
| --- | --- | --- |
| Native spelling quality, PR #157 | `9fc211f6c72be9495767bd7cacfd8df51abf2fad` | Ancestor of #159; all six changed production/test/tool files remain exact Git blobs. |
| Zotero tag filtering, PR #158 | `5dd3eb7c1434f0c1063290d5698fa5c760c201e2` | Ancestor of #159; all five changed production/test files remain exact Git blobs. Both changelog entries are retained. |
| Native spaCy distribution and Studio setup, PR #159 | `2292548eb69de2dbb5240ab9da59256f362137c6` | Merged into main. Analysis installation is explicit and manual grammar remains default-off. |
| Office continuation | `e397671e815232847d7223314ba946d1d6740f44` | History and its evidence retained through #159; the history merge changes no package source. Main's accepted common-parent `QudsTextFrame` implementation remains in place. |
| Native spaCy W7, draft PR #153 | `2e013f26c7d4db54ecabe2c955117cbce5379408` | Already an ancestor of initial main and #159. Its stacked PR state does not indicate missing source. |

## Complete reference snapshot

[refs.json](refs.json) records a fresh live `git ls-remote` snapshot for the
fork and upstream. It contains **365 references and 235 distinct commit
heads**: 198 fork branches, 159 fork PR heads, four upstream branches and four
upstream PR heads. Symbolic refs and PR test-merge refs are excluded. All
commit objects were available for inspection.

| Disposition | References |
| --- | ---: |
| Ancestor of the integrated #159 head | 335 |
| Current-task merge of that head (main and continuation branch) | 2 |
| Historical patch equivalent already accepted on main | 22 |
| Historical exact integration-tree equivalent on main | 6 |
| Unresolved incoming work | 0 |

The zero-unresolved result above is specific to the initial snapshot at
**13:03:43 CET (12:03:43 UTC)**. It does not assert that later concurrent product
changes are included; the final refresh below records those separately.

The 22 patch-equivalent refs represent eleven distinct historical branch/PR
pairs; all eleven stable Git patch IDs were recomputed and matched. The six
tree-equivalent refs represent three distinct integration heads; all three
root tree IDs were independently rechecked and matched. Every accepted
counterpart is an ancestor of #159. This explains branches retained after
squash merges without replaying old changes over later fixes.

Upstream `MohammedAsaadAsaad/quds_office_suite` remains at main
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`; every upstream branch and PR head
is contained. The newly observed concurrent branch
`codex/zotero-workspace-20261118` pointed to `2292548e` at this snapshot and
therefore added no independent delta. Any later concurrent commits must be
recorded separately.

## Preserved decisions and scope

The intentional AOT/RML removal is retained; the integration contains no
`packages/quds_proofing_aot` tree. Native spaCy installation and manual grammar
remain explicit opt-ins. Historical native acceptance and the W6 grammar
panel preserve their original provenance and are not rerun as spelling
qualification data. Superseded Office frame implementations are not restored.

This audit establishes source reconciliation and exact preservation of the
incoming spelling and Zotero changes. It does not establish fresh runtime,
physical-device, installer or native-model acceptance. The initial GitHub API
observation showed open PRs #159, #158, #157 and stacked draft #153; the live
ref snapshot was captured after the #159 merge. These are distinct
observations. No GitHub Actions, workflow, check or CI-status endpoint was
queried or awaited.

## Final refresh: concurrent work after initial integration

A separate live cutoff at **13:16:57 CET (12:16:57 UTC)** observed **366 refs
and 239 distinct heads**: 199 fork branches, 159 fork PR heads, four upstream
branches and four upstream PR heads. Main remains
`1e07cb852766f8651815138785be74c64a09ddc0`; this spelling branch is saved at
`d6a9ca51b16daa9d3d54e163bc723b76659d70ac`. All observed commit objects were
already fetched and available locally. Fetching those objects does not merge
their product source into the qualified spelling tree.

Three active continuation branches advanced after the initial integration:

| Concurrent branch | Exact observed head | Latest commit time (CET) | New work and recorded validation |
| --- | --- | --- | --- |
| `codex/document-review-20261118` | `b0044f5a04ba71e58468a7a22297b56f926e4d39` | 13:15:18 | Document comparison engine, controller operations and review dialog/tests. The checkpoint explicitly states that dialog and comparison qualification continues. |
| `codex/zotero-workspace-20261118` | `b292ee94f8792df19e3758a2a271d40230e638ca` | 13:14:13 | Reference inspection, metadata and staged-selection UI. Its retained receipt reports 445 engine cases across 22 suites; current complete editor/Studio qualification is not recorded in this head. |
| `integrate/native-spacy-distribution-20261118` | `8cd413c1e0454278abd703264bdda589a90f2d48` | 13:05:40 | Opt-in NER ABI, installer and Studio display after the merged #159 head. The NER catalog entry remains absent until model publication; this commit adds no new qualification receipt. |

**These three late product checkpoints are retained remotely and are not
included in the qualified spelling continuation.** Their exact changes and
every commit since integrated main, including timestamps and validation
provenance, are recorded in [final-frontier.json](final-frontier.json). None
changes the native spelling provider or German spelling implementation from
the initial baseline. This task does not republish their reported test results
as its own qualification or merge unfinished parallel work into its tested
source set.

The remaining refs are accounted for as 334 ancestors of integrated main, 22
patch equivalents, six exact tree equivalents and this task's continuation
head. No branch disappeared. The only open PR at the corresponding GitHub
metadata observation was stacked draft #153, whose source is already
contained. The newly created spelling PR, later evidence-only checkpoints and
any future concurrent changes fall after this fixed cutoff and are recorded
separately at delivery.
