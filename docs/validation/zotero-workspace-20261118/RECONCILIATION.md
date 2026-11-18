# Incoming work reconciliation — 18 November 2026

Inspected at `2026-11-18T12:01:55.645905+00:00`. New work starts from PR #159 head `2292548eb69de2dbb5240ab9da59256f362137c6`; fork main was `1ffcf91a3443caf9a6e8b45a3e6cab3f041831ae`.

## Scope and method

Enumerated all 196 fork branches through the GitHub API (100 + 96 + empty final page), all 4 upstream branches, all 4 open fork PRs, the 30 most recently updated fork PRs, and recent upstream PRs. Locally inspected **363 branch/PR refs** (235 unique heads): 196 fork branches, 159 fork PR heads, 4 upstream branches, and 4 upstream PR heads.

No GitHub Actions runs, workflow jobs, or commit-status endpoints were queried. This audit did not change checkout, refs, or index. Trial merges used a separate scratch object directory with the repository object store as a read-only alternate.

## Decisions

| Source | Head | Decision |
| --- | --- | --- |
| [PR #159](https://github.com/CrispStrobe/quds_office_suite/pull/159) | `2292548eb69de2dbb5240ab9da59256f362137c6` | Use as combined base; 30 commits ahead of main, no commits behind. Preserves earlier Office conflict resolutions. |
| [PR #158](https://github.com/CrispStrobe/quds_office_suite/pull/158) | `5dd3eb7c1434f0c1063290d5698fa5c760c201e2` | Already an ancestor of #159; no Zotero-file differences between this head and #159. |
| [PR #157](https://github.com/CrispStrobe/quds_office_suite/pull/157) | `9fc211f6c72be9495767bd7cacfd8df51abf2fad` | Already an ancestor of #159; native spelling changes retained. |
| [PR #153](https://github.com/CrispStrobe/quds_office_suite/pull/153) | `2e013f26c7d4db54ecabe2c955117cbce5379408` | Already an ancestor of main and #159; no additional changes to integrate. |

All four open PR discussions/reviews were empty. PR #159 reported `mergeable: true` and `mergeable_state: clean`; this is a mergeability observation, not a CI result.

The upstream repository is [MohammedAsaadAsaad/quds_office_suite](https://github.com/MohammedAsaadAsaad/quds_office_suite). Its main `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` is an ancestor of fork main (fork ahead by 1,440 commits). Latest upstream PR #7 was merged on 12 October; all four upstream PR heads are contained in this base.

## Exact ref classification

| Classification | Ref count | Treatment |
| --- | ---: | --- |
| Ancestor of combined base | 335 | Already included |
| Clean trial merge with identical tree | 10 | Already included by equivalent/reconciled content |
| Non-ancestor tip of an already merged PR | 18 | Preserve landed result and later reconciliation |
| New unincorporated content | 0 | None |

The 18 non-ancestor refs are nine branch/PR pairs. Each corresponding GitHub merge commit is an ancestor of the combined base. Several were rebased or squashed; a naïve re-merge conflicts with later changes. The API merge evidence and `git cherry` output are retained in `reconciliation-initial.json`. They are not treated as newly outstanding work.

| Previously merged PR | Branch | Landed commit |
| --- | --- | --- |
| [#140](https://github.com/CrispStrobe/quds_office_suite/pull/140) | `codex/odt-field-continuation-20261117` | `2c47165d01d01cc883135a434ac9f6591ce6e770` |
| [#136](https://github.com/CrispStrobe/quds_office_suite/pull/136) | `docs/ods-color-scale` | `4eaca83b192897edad82658107dfeb5bcbed0920` |
| [#142](https://github.com/CrispStrobe/quds_office_suite/pull/142) | `docs/ods-data-bar` | `52c73ae4dbadf2ca00a5d619144350ccc353b31a` |
| [#135](https://github.com/CrispStrobe/quds_office_suite/pull/135) | `feat/ods-color-scale` | `4584d5f319aab198f1d705f48b4d6647e6cbabea` |
| [#141](https://github.com/CrispStrobe/quds_office_suite/pull/141) | `feat/ods-data-bar` | `b3f41eb4b4bca8ca13676b4114891ea6d9185043` |
| [#137](https://github.com/CrispStrobe/quds_office_suite/pull/137) | `feat/ods-dynamic-validation-links` | `d754bf15b07a24c8a86c8dce339ca749fecd9531` |
| [#145](https://github.com/CrispStrobe/quds_office_suite/pull/145) | `feat/ods-icon-sets` | `c84d5e16024c502f6c451fd04b9807b1e65f20d3` |
| [#151](https://github.com/CrispStrobe/quds_office_suite/pull/151) | `feat/ods-time-period-conditions` | `34dc6b6806869570e9ec342e4d7ee0d6951c0ba6` |
| [#149](https://github.com/CrispStrobe/quds_office_suite/pull/149) | `integrate/office-union-148` | `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` |

`codex/office-continue-20261118` (`e397671e815232847d7223314ba946d1d6740f44`) and its resume ancestors are already in #159. The base intentionally preserves main’s common-parent `QudsTextFrame` implementation, plus the alternate branch’s evidence and history, as documented in [the #159 integration record](https://github.com/CrispStrobe/quds_office_suite/blob/2292548eb69de2dbb5240ab9da59256f362137c6/docs/validation/native-spacy-distribution-20261118/README.md). No superseded writer implementation is reintroduced.

## Limitations

This is an incoming-source inventory and ancestry/content reconciliation, not requalification of all historical changes. The next Zotero increment must be tested on this combined base. Refresh remote refs once more before the final checkpoint to catch concurrent work.
