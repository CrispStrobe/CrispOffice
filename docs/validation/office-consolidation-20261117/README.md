# Completed Office consolidation — 17 November 2026

The continuation is integrated, repaired and locally qualified at published
source **`f5021f1c364baf010049fda2dd4bf7f414deda79`**, tree **`afd7a513dfa91472f58c27ead4d8be3f4b75c262`**. The selected
**191 primary test files pass 3,541 substantive cases**; Node repeats 486 cases
with exact VM identity/outcome agreement; all 117 Python controls pass.
Independent Office consumers pass **29 fixtures and 116 ODF XML-part checks**.

Work is saved incrementally on `codex/office-consolidation-20261117`.
The starting checkpoint is `93c832f53982a9f5956f19ae0cb9418f55fac8c0`.
All checkpoint messages include `[skip ci]`; no CI endpoint or queue is used.

## Incoming work integrated first

The [fixed snapshot](incoming-snapshot.json) captured **268 external references
/ 179 distinct heads** at **18:36:23 Berlin time / 17:36:23 UTC**: 142 fork
branches, 118 fork PR heads, four upstream branches and four upstream PR heads.
Every head is an ancestor of integration checkpoint `c175f718` before the new
product repairs. The destination branch is excluded from that inventory.

This brings in optional AOT analysis/manual grammar and Studio integration,
completed parallel Office/morphology/GECToR evidence, table borders/row heights,
paragraph tab stops, and bounded German noun agreement with evaluation tools.
The recovered PAGE fields, strict paragraph colors, structured frame extraction
and all prior regression coverage remain. Both decoration suites remain active.

[Integration decisions](integration.md), [ancestry/preservation audit](integration-audit.json)
and [duplicate feature patch verification](vendor-patch-equivalence.json) record
the exact donors, conflicts and original/vendor histories.

## Product repairs

**ODT tables and tabs:** Paragraph styles include the emitted tab configuration.
Distinct positions, alignment and leader characters remain independent. Rows
retain minimum-height semantics, including multiline content. Invalid numeric
dimensions and cell colors cannot produce malformed ODF, and valid border flags
survive invalid fills. Input models remain unchanged. The 37 new regressions
first produced 30 failures, two XML errors and five passes; all now pass.
[Writer repair and retained negative controls](writer-repair.md)

**German predicate scanning:** A linear scanner replaces overlapping whitespace
backtracking while retaining the existing finite language and source offsets.
Nineteen added controls cover Unicode/long whitespace, accepted/rejected tails,
correction and recheck. The bounded old/new comparison has zero differences
across 228,692 inputs; that is a gate-equivalence check, not a grammar benchmark.

**Candidate evaluator:** The evaluator now executes the exact source bytes
admitted by its hash checks. Unreviewed cached bytecode or a file replacement
during native import cannot substitute the program being executed. Four added
controls retain the original three failing adversarial cases.
[Proofing repairs and evidence](proofing-repair.md)

Together these repairs add **56 Dart regression cases and four Python controls**.
Historical and development executions are not added to fresh qualification counts.

## Fresh local qualification

| Primary cohort | Files | Substantive passes |
| --- | ---: | ---: |
| Engine Zotero — Dart VM | 19 | 390 |
| Editor Zotero — Flutter | 13 | 186 |
| Engine integration — Dart VM | 100 | 2,232 |
| Editor integration — Flutter | 37 | 398 |
| Harper contracts — Dart VM | 3 | 29 |
| GECToR, including native fixture — Dart VM | 11 | 194 |
| AOT contracts — Dart VM | 6 | 99 |
| Configured Studio — Flutter | 2 | 13 |
| **Total** | **191** | **3,541** |

All prior 180 primary files remain. Two private-PDF early returns are excluded
from the total. **No Dart/Flutter or Python case was skipped**: the real pinned
native GECToR fixture and tiny ONNX converter control both executed.

All six strict-analysis scopes and 101 handwritten formatting targets pass.
The run uses Flutter 3.47.8 / Dart 3.13.7 / Node 24.22.1 and the unchanged pinned
lock. Source, dependencies, selected runtime, workspace, system fixtures, native
fixtures and harness inputs remained unchanged. Analyzer configuration was restored.
[Complete qualification, exact selection and reconstruction](qualification/README.md)

## Independent Office consumers

All original 26 fixture specifications/assertions remain, with three additions:
adjacent tab configurations, minimum row heights with multiline content, and
validated cell colors/borders. LibreOffice reopening retains exact tab tuples
and `atLeast` row semantics; PDF geometry and pixel checks verify positions,
leaders, visible lines and colors. All 29 fixtures and 116 official ODF 1.3 XML
parts pass. All 400 source and 10,420 runtime inputs remain unchanged.
[Consumer measurements, tolerances, raw outputs and reproduction](consumer/README.md)

## Later concurrent work and scope

A separate [18:56:31 Berlin observation](later-observation.json) records later
daemon-free AOT PR #120, ODT columns PR #119, ODP chart-data PR #121, and further
morphology/GECToR/parallel qualification updates. These arrived after the initial
integration snapshot; they are outside this frozen source and its qualification.
Their exact heads remain in the later-arrivals record.

The qualification covers the stated local engine, editor, Studio, transport,
native-fixture and Office-consumer behavior. Representative model quality,
unavailable private fixtures, all-device acceptance and new live AOT-daemon
inference remain outside these measurements. Incoming historical evidence keeps
its original source/runtime attribution.

The [independent audit](independent-review/README.md) reconstructed the raw
outcomes, exact suite/case coverage, input identities and consumer measurements
with **zero discrepancies**. All **508 members** of the two main evidence
archives were independently verified. These audit checks are separate from
product test counts. Complete archive bytes were then
[read back from GitHub](publication/github-archive-readback.json) and matched
the saved files exactly.

The [checkpoint ledger](checkpoints.json) records published trees and parents.
Publications after the qualified source contain documentation/evidence only;
the [published-tree check](publication/published-tree-review.json) verifies
unchanged product source.
