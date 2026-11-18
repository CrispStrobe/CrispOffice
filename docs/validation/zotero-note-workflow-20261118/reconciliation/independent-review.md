# Frozen Zotero reconciliation and evidence review

Review completed: `2026-11-18T19:12:58.537784+00:00`.

Frozen source: `ff1518517dd9f67e214ff56fe7eef06349f5223a`. Captured remote inventory: `2026-11-18T18:58:08.458378+00:00`.

**Result: no concrete reconciliation or target-list issue found.**

All 384 captured refs are accounted for: **210 fork branches + 170 PR heads + four upstream branches**. Fresh Git ancestry checks confirm **356 ancestors** of the frozen source. The other **28 refs** retain exactly the **14 historical heads** in the initial audit and its verified patch/tree/file equivalence. The initial local merge `19b44e8d` was published as `fcb8a4b0`: both have the exact tree `fd948cc6af4a5aea1156de247b1f6c33c6278127`. The published checkpoint and all three incoming parents are ancestors of the frozen source. The original patch-equivalence base `eedf2aee` and all four landed-equivalent commits also remain ancestors, so the historical inclusion proofs continue to apply.

The final observation adds four refs and advances four existing refs (the review/thesaurus branch and PR pairs). All advances are fast-forwards. No initial ref disappeared. The 250 distinct observed heads include every intended incoming head below.

| Intended head | Included |
| --- | --- |
| document review `b5d4df51` | True |
| thesaurus `eb1ff4dd` | True |
| mail reader baseline `0e07d247` | True |
| spacy en fr `9a90262d` | True |
| initial review `eedf2aee` | True |
| previous user zotero `6c993f74` | True |
| main `4fbc8741` | True |
| upstream main `15c5d29b` | True |

## Analysis scope

The 42-entry analysis list has no duplicates and exactly equals all changed product/test/tool Dart paths under `packages/` and `apps/` between initial review base `eedf2aee` and frozen source `ff151851`. No relevant changed application path is missing. The recorded current analysis and formatter logs report no issues and zero formatting changes.

Four changed nonproduct Dart files are outside that list: three retained thesaurus evidence fixtures under `docs/validation/` and `tools/thesaurus/benchmark.dart`. Avoid describing the 42-file result as analysis of every changed Dart file in the entire repository.

The initial review baseline contains eight Dart files changed after the user’s prior Zotero checkpoint that are outside the new target list. Their Git blobs are unchanged between `eedf2aee` and `ff151851`; the incoming review record binds its earlier 633-case validation/25-file analysis to `eedf2aee`. Keep those historical results separate from this run’s accepted totals.

## Claim boundaries

- Final acceptance requires completed current engine/editor/Studio receipts and matching before/after source/runtime fingerprints. At review time the completed logs report 549 engine and 737 editor cases passed; Studio is still running.
- Native commands and keyboard/Notes behavior are exercised with controlled protocol responses. Live Zotero/account interoperability, installed native OS shortcut dispatch, and Word/LibreOffice reopen acceptance remain external checks.
- Incoming provider tests and bundled-pack verification do not establish live downloaded spaCy model execution.
- The captured inventory is bounded at 18:58:08 UTC; this review intentionally did not fetch later refs, change source, or query CI.

Machine-readable checks and exact input hashes: `final-reconciliation-review.json`.
