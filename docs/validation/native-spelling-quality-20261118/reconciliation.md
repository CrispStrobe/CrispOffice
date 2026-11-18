# Native spelling quality: incoming work

The implementation baseline is `1ffcf91a3443caf9a6e8b45a3e6cab3f041831ae`,
the completed merge of [PR #155](https://github.com/CrispStrobe/quds_office_suite/pull/155).
The continuation is saved on `codex/native-spelling-quality-20261118`.

## Captured refs and integration

The task began by fetching all **193 fork branches and 156 PR heads**.
Main initially pointed to `c8eca37d1639ac1d20efb83ba2e9da51981a3ad4`.
The [machine-readable inventory](refs.json) records the observed initial
heads, subsequent baseline refs, PR states and exact dispositions. Its later
snapshot contains **195 branch heads and 156 PR heads**, including the new
Zotero tags branch and this continuation branch. Symbolic refs are excluded.
The 351 refs identify 228 distinct commits; counts of dispositions include
both a branch and its PR ref when both exist.

| Work | Exact included head | Result |
| --- | --- | --- |
| Native spelling #155 | `7e1294cd5d61566b4f0a1a479614f6bccd89a862` | Included through the resolved PR merge |
| Zotero catalog/aliases #156 | `f4aa218c87293527b3e2b7514500a28d13bd8f70` | Included through concurrent main merge `c60fce9c37ca960eb64dd06c7ffc55b2fdbb2ed7` |
| Optional native spaCy #139 | `6df76a0dff0051312faa04317af41d479dd94162` | Already in #155; GitHub subsequently marked #139 merged |
| spaCy W7 packaging #153 | `2e013f26c7d4db54ecabe2c955117cbce5379408` | Already in #155; the PR remained draft/open at observation |
| Office qualification #154 | `295752ff93b24bafc510e60197b62faa647e2aa3` | Already included in initial main |

Main advanced while #155 was being merged. The old main was an ancestor of
#155; after #156 landed, the only overlapping changes were the engine and
editor `CHANGELOG.md` additions. Both sets of entries were retained in
`536ee2086ce46ab629d4d77144d1ca22a43e3c19`. Its tree is
`412616ecc86358398355b7dbe66786b7fca3d740`, and the resulting PR merge is the
baseline above. All six source heads recorded under `baseline_contains` in
the inventory are verified ancestors of that baseline.

## Historical branches

The earlier [native spelling reconciliation](../native-spelling-20261118/reconciliation.md)
still applies to historical branches. This audit independently recomputed
all **11 stable patch-equivalence pairs** and rechecked all **three exact
integration-tree pairs**. Their accepted main commits are ancestors of the
baseline. The unchanged four Office recovery heads are superseded by later
accepted Office fixes; their original evidence remains on their remote
branches. PR #150 was superseded through #152. Reapplying those old variants
would not add completed work.

Main's intentional AOT/RML removal is retained: the baseline contains no
`packages/quds_proofing_aot` tree. Native spaCy remains optional and
default-disabled. Historical native/model acceptance panels retain their
original provenance; inclusion here is not a new qualification run.

## Concurrent Zotero tags continuation

`codex/zotero-tags-20261118` initially equalled main `c60fce9c`. It later
advanced to `115a040c19c3df4ba78c4e573d4fa99433efd965`, adding only:

- `docs/validation/zotero-tags-20261118/README.md`
- `docs/validation/zotero-tags-20261118/incoming.json`

There is **no product or test change** in that observed increment. Its README
explicitly describes tag-filter implementation and validation as in progress.
This concurrent planning/evidence checkpoint remains preserved on its remote
branch, separately from the completed product baseline. The inventory freezes
these observations; it does not claim to include future concurrent commits.

No existing branch was rewritten or deleted. No GitHub Actions, workflow,
check or CI status endpoint was queried or awaited. This report records
source reconciliation, not runtime test results.
