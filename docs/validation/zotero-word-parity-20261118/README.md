# Zotero Word-style workflows — native research lists and completed local qualification

## Result

**All final local gates pass on application commit [`356a3c75c645a9e91d41af0b151d773eb938f3fc`](https://github.com/CrispStrobe/quds_office_suite/commit/356a3c75c645a9e91d41af0b151d773eb938f3fc), tree `7d43df03c43e5615d7c3c5256d0156fc6ec79120`.** The frozen run completed at **22:52:24 CET on 18 November 2026**.

The saved branch is [`codex/zotero-word-parity-20261118`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-word-parity-20261118), proposed in [PR #173](https://github.com/CrispStrobe/quds_office_suite/pull/173). This report and its evidence are a documentation-only follow-up; the qualified application, tests, plan and runner remain unchanged. Source checkpoints were saved incrementally with non-forced expected-head updates and `[skip ci]`. **GitHub Actions were neither queried nor awaited.**

The final result is **1,558 distinct Dart application cases across 98 test files**, plus **50 Python accounting cases counted separately**. The former disk/runtime block is resolved. All 31 strict analysis/format targets pass, and the independent audit accepts the complete result.

## What writers can do

| Workflow | Current behavior |
| --- | --- |
| Add a research note | **Insert → References → Add Zotero note**, or **Zotero → Document → Add note from Zotero…**, uses Zotero's native picker and inserts supported content with active citations as one undo step. |
| Import bullet and numbered lists | Flat bullet/decimal lists become native Word lists. Each item supports rich inline text, soft breaks, safe links, citation placeholders and one optional paragraph wrapper. Ordered starts from 1 through 999999 survive DOCX save/reopen. |
| Keep list counters independent | Imported lists have their own numbering instances. They neither continue surrounding lists nor cause ordinary lists created later to inherit their counters, including after saving and reopening. |
| Preserve the document on undo | Note text, citations, preferences and numbering definitions undo/redo together. Numbering snapshots preserve unrelated package parts and relationships, including after saving or reusing a relationship ID. |
| Return directly to writing | Native ribbon and keyboard citation, bibliography, refresh and style commands return to the resulting body/Notes caret. The full references workspace remains available for browsing. |
| Go to a reference | Select complete supported citations or bibliographies in body, table and Notes locations without modifying content or undo history, including in read-only selecting mode. |
| Continue citing in authored notes | Existing footnotes/endnotes retain their text, formatting, identities and correct Zotero reading order. Composition and stale-target guards remain in place. |

The [Zotero guide](../../zotero-support.md) documents exact menu paths, supported structures, command semantics and embedding APIs.

Research-note insertion requires a collapsed body caret outside existing fields. Nested lists, multi-paragraph items, per-item numbering overrides, reversed/custom markers, images, tables and unsupported formatting are refused atomically. Citation editing in existing authored notes remains a separate supported workflow.

## Incoming work reconciled before changes

The bounded snapshot at **22:21:52 CET on 18 November 2026** captured **391 refs**: 212 fork branches, 175 PR heads and four upstream branches. Three newer heads were integrated before list-support edits:

- Mail: `514c341d985e01bbc38f8ec4a1f5708e2b7fc8f3`.
- Thesaurus: `5535d2eb8ed153b937f372912d3279c7794090ed`.
- Notes/document review: `c9f8cd8e213b0d5ed3edc31546dd19db553048f2`.

Integration [`8fa115e8358e305872fd14e757f9133fa9c1540d`](https://github.com/CrispStrobe/quds_office_suite/commit/8fa115e8358e305872fd14e757f9133fa9c1540d) preserves those heads and the prior Zotero work. Both composition identity and the incoming exact header/footer variant remain in transaction guards.

A complete local audit was rerun on the qualified source: **363 refs by ancestry, 28 verified historical equivalents, zero unaccounted**. All 14 equivalence proofs pass. The 28 historical refs retain their established patch/tree/file equivalence; no artificial ancestry merges were introduced. This is a bounded snapshot, not a claim about refs created afterward.

- [Exact captured inventory](continuation/reconciliation/api-inventory-20261118.json)
- [Complete audit on the qualified source](continuation/reconciliation/final-source-audit.json)
- [Historical merge/equivalence check](continuation/reconciliation/historical-merge-check.json)

## Final qualification

| Gate | Distinct test files | Passed application cases |
| --- | ---: | ---: |
| Engine | 36 | 641 |
| Editor | 48 | 724 |
| Studio | 7 | 98 |
| Mail core | 1 | 9 |
| Mail store | 5 | 75 |
| Mail UI | 1 | 11 |
| **Total** | **98** | **1,558** |

The runner's **32** Python regressions and Mail runner's **18** Python regressions pass separately. They are not added to the application total. All 11 gates finish successfully, with zero failures, skips, reporter errors, unfinished cases, duplicate completions or requested-suite discrepancies. Loading/setup/teardown events are excluded from the case count. Earlier development and historical reports contribute no cases to these totals.

Strict analysis uses `--fatal-infos`; formatting checks all **31** selected Dart targets. The whitespace check retains the original pre-Zotero baseline for all paths except six exact, pinned, unchanged provenance blobs: one recovery patch and five verbatim license notices. The exception is refused if any blob changes; their identities match incoming integration, qualified source and final audit. Tests are not excluded by this mechanism.

Independent recounting reads the raw reporter events without importing the runner parser. It verifies exact suite/case counts, all raw/compressed/detail hashes, all **1,747** recorded source inputs and **five** environment receipts. Before/after source, runtime and dependency fingerprints are identical, with the expected HEAD/tree and a clean tracked checkout.

- [Final summary](continuation/final/summary.json)
- [Independent count/hash/source audit](continuation/final/independent-audit.json)
- [Complete raw results, logs, case details and source snapshots](continuation/final/complete-results.tar.gz)
- [Archive and member hashes](continuation/final/archive.json)
- [Independent recount implementation](continuation/final/independent_gate_audit.py)
- [Frozen 98-file plan](plan.json) and [runner](run_local.py)

## Runtime recovery

The actual runtime is Flutter **3.47.8** / Dart **3.13.7**. The official SDK archive matches SHA256 `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`. All **176** hosted package versions in the workspace/Flutter-tools lock union were verified by archive hash, including the incoming Mail dependencies.

Workspace and SDK-tool `pub get --offline --enforce-lockfile` succeeded (the SDK-tool invocation includes `--example`). All 17 workspace manifest/lock inputs remained byte-identical. The workspace lock SHA256 is `35d1ef372908f4ab278973355ec6a957cd3240bea115d615056c5b9e398df974`. [Runtime receipts and package hashes](continuation/runtime/runtime-ready.json) accompany the raw setup logs.

The previously unexecuted IME reconnection/return checks passed first in a frozen 68-case recovery run, and are included again within the current disjoint selection. [That recovery evidence](continuation/focused-ime/summary.json) remains separate and is not added to the total. Its local integration tree equals the published `8fa115e` tree.

The former executor's inaccessible staged tree is not present in this new workspace. The remotely recovered tests were preserved in history, formatted and executed anew; no comparison against unavailable original staged wording is claimed.

## Issues found and resolved

1. **Research counters leaked into later ordinary lists.** Separate reusable and independent numbering definitions now keep subsequent ordinary lists at their own starting number, before and after DOCX reopening.
2. **Numbering XML placed new instances after cleanup metadata.** Definitions and instances are now inserted in the required order, including a numbering part containing only cleanup metadata. Both findings have dedicated regressions and an [independent post-fix probe](continuation/review/independent-list-probe.dart).
3. **Recovered Notes fixtures failed before their intended checks.** The caret helper now uses the controller's collapsed-selection contract. Mixed-provider fixtures use distinct spans so intentional overlap suppression does not hide the manual finding. The IME fixture explicitly ends tracking after seeding a navigation revision. All intended identity, provider-call, composition and correction assertions remain.
4. **The narrow RTL fixture tapped below the viewport.** Actual scrolling reaches the field at the unchanged 320 × 640 viewport and doubled text scale. The selection helper now reveals the field and asserts it is hit-testable before tapping. Original citation selection, update and undo assertions pass; [gesture and full-suite evidence](continuation/review/notes-pane-reachability-review.json) is retained.
5. **The original whitespace check included verbatim evidence.** Six unchanged artifacts are now pinned rather than rewritten. All other paths retain original-baseline coverage. The runner's own regressions verify pin mismatch and invalid-exception rejection.

The first full run is preserved as an explicitly failed [diagnostic](continuation/diagnostic-9547/summary.json), with [complete raw evidence](continuation/diagnostic-9547/complete-results.tar.gz) and an independent audit. It is not represented as passing qualification.

## Replay

With the pinned SDK, verified package cache and enforced locked resolution prepared, check out the qualified commit above and run:

```bash
python3 docs/validation/zotero-word-parity-20261118/run_local.py \
  --repo "$PWD" \
  --expect-commit 356a3c75c645a9e91d41af0b151d773eb938f3fc \
  --output ../zotero-qualification-output
```

The output directory must be new and outside the checkout. Repeated `--environment-input` flags can bind setup receipts, package-hash receipts and the environment script, as recorded in the delivered run. The runner verifies a clean frozen source before and after each gate.

## Acceptance limits

This establishes local model, controller, real Flutter widget and controlled-transport behavior, including Quds DOCX serialization/reopening. It does not add a new live Zotero/account session, installed native application/OS shortcut acceptance, or actual Microsoft Word/LibreOffice reopening. Historical live acceptance retains its recorded source identity.

[Publication checkpoints](publication-checkpoints.json) preserve the incremental history. The [prior interrupted report](https://github.com/CrispStrobe/quds_office_suite/blob/2d31df46d9aa684c60b75053671b0f45016388d2/docs/validation/zotero-word-parity-20261118/README.md) remains available in Git history.
