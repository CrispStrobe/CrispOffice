# Reconciled local qualification — 18 November 2026

**Subsequent completion:** the [19 November integrated report](../resumed-20261119/README.md) records the completed final 2,018-case union and fresh native/build evidence. This page preserves the earlier evidence-checkpoint status.

This continuation integrates the captured Mail, Zotero and Notes/header review
heads into PR #174, including the later Notes language/history and Zotero
research-list changes. The refreshed incoming checkpoint is `a6c165d3`; the final application fix
is saved at `3847d5f4`. All **391**
captured branch/PR/upstream refs are accounted for: 363 by ancestry and 28 by
freshly replayed historical equivalence. See `incoming/`.

The source checkpoint repairs the Notes test fixtures, rejects hidden/loader
failures and skips in the Mail result parser, adds an optional offline locked
dependency resolution, and binds thesaurus execution to effective workspace
roots and source-verified browser result records. Original failed and
interrupted attempts are preserved in the evidence archives.

## Status at the evidence checkpoint

- Mail: 152 distinct Dart cases plus 34 parser controls passed. VM/Node repeats
  are recorded separately. Actual browser persistence is not qualified.
- Notes/Review integration: the host now preserves Notes state when Review
  opens, closes or changes layout. All 28 focused pane cases passed; these are
  not added again to the complete union plan.
- Workspace/browser harness: 36 controls passed. These are synthetic/control
  execution, not actual browser acceptance.
- Combined Notes/Zotero/Studio/Mail UI: the committed plan selects 129 distinct
  suites; the complete replay is still pending at this checkpoint.
- Final native fixture: 208 cases passed; release compilation produced 1,155
  files / 87,446,594 bytes. Preparation and independent byte verification passed
  for the 1,156-file installed inventory. Actual browser execution is not run.
- The fresh `linguistic/` packet preserves 15 observed queries, 109 distinct
  meaning records and ten original notices. Human decisions remain blank.
- Actual offline browser, installed Studio/OS IME, and independent human
  linguistic review remain open.

## Replay the affected-suite union

Use the pinned Flutter 3.47.8 / Dart 3.13.7 runtime, a verified dependency cache
and its preserved runtime receipts. `run_targeted.py` runs directly from the
source checkout, checks every local package root, binds installed external
dependency/framework contents, and saves source/environment inventories before
and after. It requires committed input sources and a new output directory.

```sh
python3 docs/validation/thesaurus-20261118/reconciled/run_targeted.py \
  --runtime /absolute/verified-runtime \
  --output /absolute/new-combined-evidence
```

The 28 analysis/format targets are Dart files changed since `5535d2eb`; the
129-suite test selection is the union of the prior pending Notes and Zotero
plans, plus the other three Mail UI suites, refreshed research-list tests and
direct callers of the changed WordLists numbering API. Mail core/store/MIME are covered by
their separate accepted gates. This is targeted qualification, not a fresh
whole-repository run. No GitHub Actions result is used or awaited.
