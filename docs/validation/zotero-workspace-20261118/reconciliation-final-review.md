# Final incoming refresh — 18 November 2026

Read-only live ref snapshot at `2026-11-18T12:15:29.960467+00:00`. GitHub metadata was read for main and PRs #157–#159. `git ls-remote` inspected all origin/upstream branch and PR heads without fetching or changing any local ref. No Actions/status endpoint was queried.

## Landed incoming work

Main advanced from `1ffcf91a3443caf9a6e8b45a3e6cab3f041831ae` to `1e07cb852766f8651815138785be74c64a09ddc0`. Compared with the continuation’s starting point (`2292548eb69de2dbb5240ab9da59256f362137c6`), this is one additional merge commit with **zero changed files**.

| PR | Current state | Head | Recorded merge commit |
| --- | --- | --- | --- |
| #157 | Merged | `9fc211f6c72be9495767bd7cacfd8df51abf2fad` | `3813f79e04b177d0cfce3755b77b209a58be528a` |
| #158 | Merged | `5dd3eb7c1434f0c1063290d5698fa5c760c201e2` | `841714fed1efbad2927048b0e2c8deaf06872ab8` |
| #159 | Merged | `2292548eb69de2dbb5240ab9da59256f362137c6` | `1e07cb852766f8651815138785be74c64a09ddc0` |

Only draft PR #153 remains open in this snapshot. Its existing head is already contained in the combined source.

## Concurrent branch work retained separately

| Branch | Observed head | Scope / status |
| --- | --- | --- |
| `integrate/native-spacy-distribution-20261118` | `8cd413c1e0454278abd703264bdda589a90f2d48` | One new commit after the merged #159 head. Optional NER ABI, verified model install and Studio display; catalog model remains absent until publication. Ten changed files, no Zotero source files. |
| `codex/document-review-20261118` | `b0044f5a04ba71e58468a7a22297b56f926e4d39` | Three commits ahead of main. New document comparison/review UI and engine, shared Office controller changes and tests. Commit explicitly says it is a checkpoint and further dialog/comparison qualification continues. Already incorporates the Zotero branch’s initial reconciliation evidence. No corresponding open PR at this snapshot. |
| `codex/native-spelling-continuation-20261118` | `d6a9ca51b16daa9d3d54e163bc723b76659d70ac` | Two commits ahead of main. German short-accented suggestions, identifier guards, tests, documentation and both package changelogs. No corresponding open PR at this snapshot. |

**Reconciliation decision completed:** checkpoint `d36413a2cc8e1de9fd7493b5d1baf2900e63f04b` incorporates new main `1e07cb852766f8651815138785be74c64a09ddc0` as its second parent. This changes incoming history only because main’s tree equals the original #159 base. Keep the three newly active external work branches as independent increments. They emerged after the initial integration cutoff, have no new completed PR at this snapshot, and the document-review commit explicitly says qualification is still continuing. Their exact observed heads and scopes remain recorded; none is claimed as integrated or qualified by this Zotero increment. Root will refresh remote heads again near completion to record subsequent movement.

The document-review head touches `office_controller.dart`, so merely observing no direct Zotero file changes would be insufficient to infer no effect on Zotero. Keeping this unfinished increment separate preserves the tested combined Zotero source.

## Snapshot counts and evidence

The live snapshot contains 358 origin refs and eight upstream refs (366 total), including this work’s `codex/zotero-workspace-20261118` checkpoint `b292ee94f8792df19e3758a2a271d40230e638ca`. Compared with the initial audit, two external refs advanced and two external branches were added; the third new branch is this Zotero continuation. Upstream refs did not move.

- `reconciliation-final-remote-refs.json`: exact live ref list, changes and additions.
- `reconciliation-final-pr-state.json`: merge states and tree-identical main comparison.
- `reconciliation-final-external-comparisons.json`: commit relationships and per-file stats for the three concurrent heads.
