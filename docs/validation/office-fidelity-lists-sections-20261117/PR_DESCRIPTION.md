## Why

ODF export was losing paragraph and story formatting, table structure, comments,
and slide geometry. The latest incoming section and nested-list writers also
misattached section page styles, changed list sibling/marker semantics, and lost
numbering state. Local consumer checks exposed an inherited RTL-indent reversal;
section-anchored frames exposed an interaction with text extraction and search.

## Changes

- Preserve nested-list siblings across skipped or initially nonzero levels,
  mixed markers, supported decimal starts/restarts and continuation, default
  descendant resets, and exact large counters. Keep unsupported cached markers
  literal and auxiliary/covered-cell counters separate from body numbering.
- Apply section page styles to the first real paragraph, list, table, picture,
  frame, or empty anchor, including through nested controls. Preserve resolved
  first-paragraph properties, odd/even entry masters, and equivalent continuous
  sections without an extra break or blank paragraph.
- Preserve physical left/right paragraph indents in RTL ODT output. Retain the
  original independent 540 pt edge expectation and add an ordinary RTL control.
- Keep anchored text-box paragraphs extractable and searchable without
  duplicating surrounding inline text, losing explicit whitespace, or exposing
  hidden annotation/covered-cell stories. The original failing assertion remains
  unchanged.
- Add **89 new regression cases** in this continuation: 40 list, 26 section,
  five RTL mapping, and 18 text-box extraction/search cases, all run on VM and Node.

Earlier ODT paragraph/table/header/footer/note/comment, ODP centered rotation
and rotated-table, conditional-formatting, and logical-PDF-text changes remain
integrated. Their earlier broad qualification is preserved separately; this
continuation does not claim to rerun every earlier cohort.

## Incoming integration happened first

Integration checkpoint: `097475fbda96aa4a6497d92f28d10f1aa5f640b4`.

The finite snapshot contains **240 named references**: 126 fork branches,
106 fork PR heads, four upstream branches, and four upstream PR heads. A branch
moved between REST collection and Git fetch, so both tips are preserved:
**241 reference/revision pairs covering 162 distinct heads**. Every captured
head is included by ancestry. Git observation completed **17 November 2026,
15:49:26 Europe/Berlin**; later arrivals are outside this snapshot.

This includes main `2277634a`, sections PR #104, nested lists PR #106 and their
original/vendor histories, morphology PR #105, the optional GECToR package and
manual editor grammar lane, and namespace-correct ODF annotation extraction.
Conflict decisions and exact inventories are in the report.

## Completed local qualification

Final qualified product source: **`cf60a17bcd825dc9b4ecdf840d54e6a0271d3647`**,
tree `4a1a29d5029d25da9700b56a1fd244f3f5679547`.

| Final cohort | Passing executions | Test files | Failures / errors / skips |
| --- | ---: | ---: | --- |
| Dart VM | **353** | **18** | **0 / 0 / 0** |
| JavaScript / Node repetitions | **236** | **10** | **0 / 0 / 0** |
| Final source total | **589** | **28 file executions** | **0 / 0 / 0** |

Node repeats ten VM files; these are not 236 additional unique cases. Strict
scoped analysis and formatting pass for the three changed production files and
selected tests. Source/runtime/lock/HEAD guards and exact raw-event suite coverage
pass with genuine **Flutter 3.47.8 / Dart 3.13.7 / Node 24.22.1**. Both cohorts
bind **1,670 source inputs** and **8,606 runtime inputs**.

Incoming work was qualified separately: **97 GECToR VM**, **78 engine VM**,
**119 actual Flutter editor**, and **49 Node repetitions**, totaling **343
passing executions across 22 file executions**, plus **65 ancillary Python
checker passes**. One native-inference case is explicitly skipped without its
pinned fixtures. The initial engine static failure and bounded braces/formatting
correction remain recorded; subsequent strict requalification passed. These
historical runs are not relabeled as final-source runs.

## Independent office checks

All **24 consumer fixtures** and **96 official OASIS ODF 1.3 XML-part validations**
pass in a fresh complete run from the same final source. LibreOffice and Poppler
check section page geometry, headers/footers, parity with automatic blanks retained,
list labels and indentation, continuous-section behavior, and exact text geometry.

- RTL heading edges: **539.916 / 539.911 pt**, against the original **540 pt**
  expectation, with exact **18 pt** line spacing. The ordinary control separately
  checks physical **540 pt right / 66 pt left** bounds.
- Leading picture: intended second page, **36 pt** left edge, measured
  **39.75 x 21 pt** for authored **40 x 20 pt**, within the declared **1 pt**
  raster tolerance.
- Reopened frame: exact page-relative **(60, 100, 180, 40) pt** position and size.

The run binds **392 source** and **10,420 runtime inputs**, including **557 font
files**, unchanged before/after. Per-fixture assertions are explicit. The original
19/20-failing semantic baseline, 22/23 attempt, and RTL diagnostic controls remain
archived. The accepted result is a fresh complete run, with no relaxed heading
expectation and no composition of failed historical receipts.

## Evidence and limits

[Complete continuation report, inventories, consumer measurements, independent
reviews, and reconstruction instructions](https://github.com/CrispStrobe/quds_office_suite/blob/codex/office-fidelity-20261117/docs/validation/office-fidelity-lists-sections-20261117/README.md).

The independent audit reconstructs raw-event counts, source/runtime identities,
import closures and incoming ancestry, and restores **1,109 files across eight
indexed archives**. All accepted final receipts, command logs, and consumer outputs
are explicitly bound to those archives. A separate read-only code review found no
blocker in the section/list/RTL scope. Failed runs and audit-format corrections
remain separate from passing totals.

The complete prior 83-file report tree remains byte-identical to `8eb01db0`.
The explicitly selected 85 proofing/GECToR files match the corrected incoming
source exactly; whole historical import-closure equivalence is not claimed.
A verified small Git bundle preserves the exact local historical source IDs.

The [prior completed qualification](https://github.com/CrispStrobe/quds_office_suite/blob/8eb01db06c1457fa04ab3f3b8b2ef8fef791fb43/docs/validation/office-fidelity-resume-20261117/README.md)
retains its original evidence and limits.

Complex list markers use literal labels rather than fully editable native
multilevel numbering. A continuous section with changed page geometry or normal
stories uses a page-boundary fallback. First/alternating headers, inherited native
story reconstruction, columns and line numbering remain outside this writer.
Frame geometry is qualified, while default consumer fill/outline and missing
internal insets remain explicit limits. Text-box extraction follows source order;
nested tables contribute visible cell paragraphs rather than separate structured
table entries. Native GECToR inference, complete Office round trips, all repository
tests, and universal shaping parity are not claimed.

Incoming work adds optional GECToR workspace/package manifests; the enforced
dependency lock is unchanged. No new font or model binaries are committed and no
native shaping backend is added.

**No GitHub Actions jobs, checks, or commit-status endpoints were queried or
awaited.** Remote checkpoint messages use `[skip ci]`.
