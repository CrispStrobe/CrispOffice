# Latest incoming frontier review

This review is bound to exact Git commits. It does not query GitHub Actions or
status checks. The companion `frontier-audit.json` records full hashes and file
identities; `mail-evidence-audit.json` records an independent audit of the incoming
author's evidence.

## Integration snapshot

The integration checkpoint is
[`596430dcb816dd418204d62e78f4dc518afdc0e1`](https://github.com/CrispStrobe/quds_office_suite/commit/596430dcb816dd418204d62e78f4dc518afdc0e1).
Its three direct parents are our previous checkpoint `2aff66a8540beb2015e606e67e46d228d7bf695e`,
the incoming GUI head `2d7360a217b51c34ccf72eb5ed78c82ccd20bae5`, and remote main
`caf378f40fd5bda50f504a6816404d01d8bbb8f8`.

All 18 new GUI paths outside validation evidence match the incoming GUI blobs
exactly in this integration checkpoint. The macro engine tree is unchanged from
our previous checkpoint. The separate editor fixture corrections were already
part of that previous checkpoint and are covered by their own retained evidence.

GitHub's compare response returned only 300 files without an explicit truncation
flag. All path counts, overlap checks, and preservation claims in this review use
complete local Git tree comparisons instead.

## GUI advance: PR #211

[PR #211](https://github.com/CrispStrobe/quds_office_suite/pull/211) was observed
open and draft, updated at 2026-11-19 18:21:07 UTC, with head
`2d7360a217b51c34ccf72eb5ed78c82ccd20bae5`. The previous reviewed checkpoint was
`4fd010fcae209b6ea033828d76908508b7327b9f`.

Compared with common ancestor `ae4c8223d1814df4a500518c8b223831cbb0b51f`, the new
head changes 433 paths: 415 validation paths and 18 other paths. These do not
overlap the changes from that ancestor to our previous checkpoint.

The substantive additions are:

- Studio Page Layout and Paragraph dialogs, with staged edits, precise unit
  conversion, localized numbers, validation, captured targets, and one undoable
  apply operation. Paragraph patches retain mixed and unedited properties.
- Compact ribbon menus with selected-value feedback, explicit slide animation
  choices, and Document mode controls in File/View.
- Material chrome and dialog contexts that follow light, dark, or high contrast
  appearance, including an already open Settings dialog.
- Display-only slide text color adaptation against known solid backgrounds,
  table cell backgrounds, and the painted Morph fill. Mixed or animated backing
  is treated conservatively; exported model colors remain authored values.

Five new test files are present: `studio_layout_theme_test.dart`,
`studio_page_layout_dialog_test.dart`, `studio_paragraph_dialog_test.dart`,
`studio_slide_sheet_menus_test.dart`, and `office_dark_slide_test.dart`.
Four existing comment/review/Zotero suites use the new Document mode helper.
The integration owner included these and the existing File, Desktop, and Ribbon
regressions in the expanded qualification cohort.

The PR body still described 17 first-checkpoint editor tests and work in progress
on host dialogs/ribbon tests and visual review. That claim is not final acceptance
for the new GUI head. Our final qualification is recorded separately.

Focused source inspection covered dialog capture/freshness checks, preflight and
single-apply behavior, precision and mixed-value preservation, themed contexts,
and slide backing selection. It found no definite production defect in those
paths. During the expanded local cohort, the first new dark-slide test failed at
the white table-cell pixel assertion: 3 pixels within RGB tolerance 3 of black,
against a threshold greater than 15. The renderer paints that cell at the exact
sampled origin with 13 px text. A retained diagnostic copy preserves the original
assertions while recording raw raster colors and an adaptation-disabled control;
the follow-up diagnosis is separate from this static review.

## Mail publication: PR #209

[PR #209](https://github.com/CrispStrobe/quds_office_suite/pull/209) merged at
2026-11-19 18:16:42 UTC. Its head is
`6275d21246040e03f6264b27171992c88d1474a2`; merge commit
`caf378f40fd5bda50f504a6816404d01d8bbb8f8` has the identical tree
`b80e63de4a71f6857c44e96cee33fc0bcbba1ae5`.

The author accepted source commit `0c77b3488eb534868a7f98271ba2923d06759b8d`.
All 419 changed paths between that source and the published head are validation
artifacts. This advance adds evidence and ancestry, with no product/test-source
change.

The independent audit script in this folder reads immutable Git objects. It does
not import or execute the author's acceptance helpers. It:

- Checks the five acceptance receipt hashes and all stdout/stderr hashes for 22
  accepted commands.
- Independently parses raw Dart JSON events for 10 cohorts, requires completed
  successful runs, and matches case identities, results, platforms, and expected
  files against the saved case artifacts and receipt counts.
- Rehashes all 4,441 recorded repository inputs against the accepted source,
  published mail head, and merged main tree; all match.
- Compares the published before/after inventories for 9,298 dependency inputs and
  1,108 runtime inputs. It does not rehash those external files, which belong to
  the author's separate workspace.
- Checks all 12 screenshot hashes, PNG dimensions, and published-copy equality.
  This does not claim an additional visual or native-app review.

The audit passes with **1,640 author-run cases passed, zero failed or skipped,
90 distinct files, 10 cohorts, and 22 accepted commands**:

| Author cohort | Passed |
| --- | ---: |
| Mail core VM | 54 |
| MIME VM | 84 |
| Mail store VM | 508 |
| Mail store Node | 9 |
| Mail UI | 33 |
| Studio mail | 388 |
| Incoming macros/VBA | 269 |
| Incoming branding/structure | 216 |
| Incoming editor PDF/review | 52 |
| Incoming Studio desktop/ribbon/lifecycle | 27 |

These are verified records of the author's executions. They add **zero** to our
local macro or GUI qualification counts and do not qualify later macro/GUI source.
The published claim covers Linux native SQLite, synthetic/loopback fixtures,
Flutter widgets, and declared Node boundaries. It does not establish live-account
interoperability, installed-platform packaging, full repository qualification, or
full database/provider restoration. Manifests remain unsigned and portable
filesystem checks cannot exclude every concurrent path-replacement race.
