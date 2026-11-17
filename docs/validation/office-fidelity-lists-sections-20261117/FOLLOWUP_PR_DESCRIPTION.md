## Why

PR #101 was merged while its local qualification reports were being finalized. This follow-up preserves the complete reports, raw evidence archives, and independent reviews on the existing `codex/office-fidelity-20261117` branch.

The qualified product source is **`cf60a17bcd825dc9b4ecdf840d54e6a0271d3647`**. Later changes on `main` are outside this qualification. The initial incoming snapshot remains explicit: **240 named references / 241 reference-revision pairs / 162 distinct heads**, all included by ancestry before implementation.

## What this PR adds

- Final VM/Node receipts, source/runtime inventories, raw events, and reconstruction instructions.
- Fresh LibreOffice/Poppler and official ODF 1.3 schema evidence for lists, sections, RTL indents, pictures, and frame geometry.
- Independent source/code reviews, captured-ancestry verification, and published-tree audit.
- Preserved failed attempts and exact checker corrections, separate from accepted totals.
- A small verified Git bundle containing the exact historical local source objects referenced by the receipts.

## Local results

| Scope | Result |
| --- | --- |
| Final Dart VM | **353 passes / 18 files** |
| Final JavaScript/Node repetitions | **236 passes / 10 files** |
| Final failures / errors / skips | **0 / 0 / 0** |
| Independent office fixtures | **24 / 24 passed** |
| Official ODF 1.3 XML parts | **96 / 96 passed** |
| Evidence reconstruction | **1,109 files across eight archives** |

Node repeats selected VM cases. All **89 new regression cases** run on both platforms. Final cohorts bind **1,670 source inputs / 8,606 runtime inputs**, using genuine Flutter 3.47.8 / Dart 3.13.7 / Node 24.22.1 with the unchanged enforced lock. Consumer qualification separately binds **392 source / 10,420 runtime inputs**, including **557 fonts**.

Incoming work has separate historical qualification: **343 passing Dart/Flutter executions**, one explicit native-inference fixture skip, and **65 Python checker passes**. The initial engine strict-gate failure and its correction are preserved. The selected 85 proofing/GECToR files match the corrected incoming source; whole historical import-closure equivalence is not claimed.

The complete prior **83-file report tree** remains byte-identical to `8eb01db0`.

## Scope and limits

The original frame-text assertion and the original **540 pt RTL edge** expectation were retained. The final result is a fresh complete run. Complex list markers retain literal labels; changed continuous page styles use a page boundary; first/alternating headers and inherited native stories remain outside the writer. Frame geometry is checked, while fill/outline/insets retain documented limitations. Native GECToR inference and universal Office round trips are not claimed.

[Complete report and reconstruction instructions](https://github.com/CrispStrobe/quds_office_suite/blob/codex/office-fidelity-20261117/docs/validation/office-fidelity-lists-sections-20261117/README.md)

**No GitHub Actions jobs, checks, or commit-status endpoints were queried or awaited.** Checkpoints use `[skip ci]`.

