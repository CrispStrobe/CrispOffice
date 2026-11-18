# Zotero continuation: incoming work reconciliation

Snapshot recorded at `2026-11-18T12:50:08.288997+00:00`. The combined starting commit is
[`80168fd5605e0c519b26f35b775bec85ef0692b1`](https://github.com/CrispStrobe/quds_office_suite/commit/80168fd5605e0c519b26f35b775bec85ef0692b1)
on `codex/zotero-continuation-20261118`.

## Included current work

The starting commit preserves three parents: current fork main, the latest
document-review PR head, and the platform golden-helper follow-up. Main already
contains the completed Zotero workspace (#161), native spelling (#160), and
macOS/NER follow-up (#163). The old interrupted Zotero work is saved and included.

| Source | Exact included head | Treatment |
| --- | --- | --- |
| Fork main including merged Zotero, spelling and spaCy follow-ups | `517f6d10f0ec2509b1381b3cf23807645bba4f92` | Direct parent |
| Zotero reference details and selection review, PR #161 | `acfa3c2bf543debd2fff518304ab514ab677418b` | Exact ancestor |
| Document review and comparison, PR #162 | `9ecf4c420f6b4251744308530f0934f8cd5f3b37` | Direct parent |
| Working-directory-independent platform golden selection | `ca42a7fa3947d0b59b9b2d3e14e807116327d714` | Direct parent |
| Native spelling continuation, PR #160 | `8cbdb9d9a05ff7f0e795efe0ee7848b196f424a3` | Exact ancestor |
| Published macOS capsule and opt-in NER follow-up, PR #163 | `ce4d3d19a21eae96a473291ffb9f47ac3be6a74c` | Exact ancestor |
| Advanced original spaCy distribution branch | `8f93545eb46c1f1f4c653c7beaf23d28c3307940` | Exact ancestor |
| Upstream main | `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` | Exact ancestor |

The incoming review dialog, comparison regression tests and golden helper have
identical blob IDs at their source heads and the combined starting commit.
Their bindings are retained in `incoming_file_identity_checks` in the JSON.

## Inventory and exact classification

**372 incoming refs / 241 distinct heads** were inspected: 201 fork branches,
163 fork PR heads, four upstream branches and four upstream PR heads. The
symbolic `origin/HEAD` and this continuation branch are excluded. Every included
remote ref name and SHA, together with its source ref and ancestry result, is in
[reconciliation-initial.json](reconciliation-initial.json).

| Classification | Refs | Distinct heads |
| --- | ---: | ---: |
| Exact ancestor of the combined starting commit | 344 | 227 |
| Unchanged historical tip with an earlier identical-tree trial merge | 10 | 5 |
| Unchanged historical tip already landed through a reconciled PR | 18 | 9 |
| New or changed unaccounted head | 0 | 0 |

Against the [previous Zotero inventory](../zotero-workspace-20261118/reconciliation-initial.json),
there are nine new refs, two changed refs and no removed refs. All eleven new or
changed refs are exact ancestors of this starting commit. This includes both
newly incorporated document-review and golden-helper heads. All upstream heads
are included.

## Historical branches

All 28 historical nonancestor refs match the exact names and SHAs in the
[prior reconciliation](../zotero-workspace-20261118/RECONCILIATION.md). Its base
`2292548eb69de2dbb5240ab9da59256f362137c6` remains an exact ancestor here.
For the 18 previously landed refs, every recorded landed PR commit was freshly
verified as an ancestor. Their PR numbers are **#135, #136, #137, #140, #141, #142, #145, #149, #151**.

The ten earlier identical-tree cases are branch/PR pairs for:

- `docs/aot-removal`
- `docs/ods-dynamic-validation`
- `docs/ods-icon-sets`
- `integrate/odt-column-boundary-144`
- `integrate/office-union-150`

The prior trial results are reused only for unchanged tips and their retained
ancestor base; this audit does not claim a new trial merge. The JSON identifies
each prior entry, binds the prior evidence file by Git blob and SHA-256, and
records the fresh ancestry checks. No obsolete implementation is replayed.

## Method and scope

The audit reads already fetched `refs/remotes/*` and checks each distinct head
with `git merge-base --is-ancestor`. Exit 0 means exact ancestry; exit 1 is
classified separately using the prior evidence. Unexpected Git errors fail the
audit. This is source reconciliation, not a fresh validation result for the
combined product. Local product checks are recorded separately.

No checkout, index or ref was changed by this audit. No GitHub Actions, check,
workflow or CI-status endpoint was queried or awaited. The snapshot covers the
recorded cutoff; refresh remote refs before final delivery to catch later work.
