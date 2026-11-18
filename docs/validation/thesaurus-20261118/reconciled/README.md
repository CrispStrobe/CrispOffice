# Reconciled local qualification — 18 November 2026

This continuation integrates the captured Mail, Zotero and Notes/header review
heads into PR #174. The remote incoming checkpoint is `0ea205e0`. All **391**
captured branch/PR/upstream refs are accounted for: 363 by ancestry and 28 by
freshly replayed historical equivalence. See `incoming/`.

The source checkpoint repairs the Notes test fixtures, rejects hidden/loader
failures and skips in the Mail result parser, adds an optional offline locked
dependency resolution, and binds thesaurus execution to effective workspace
roots and source-verified browser result records. Original failed and
interrupted attempts are preserved in the evidence archives.

## Status at this source checkpoint

- Mail: 152 distinct Dart cases plus 23 parser controls passed. VM/Node repeats
  are recorded separately. Actual browser persistence is not qualified.
- Notes controller: 33 cases passed after correcting the fixture; this isolated
  result is not added again when the complete union plan runs.
- Workspace/browser harness: 31 controls passed. These are synthetic/control
  execution, not actual browser acceptance.
- Combined Notes/Zotero/Studio/Mail UI: the committed plan selects 122 distinct
  suites; the complete replay is still pending at this checkpoint.
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

The 23 analysis/format targets are Dart files changed since `5535d2eb`; the
122-suite test selection is the union of the prior pending Notes and Zotero
plans, plus the other three Mail UI suites. Mail core/store/MIME are covered by
their separate accepted gates. This is targeted qualification, not a fresh
whole-repository run. No GitHub Actions result is used or awaited.
