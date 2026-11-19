# Accepted integrated qualification at `5c18db77`

The full local run and independent audit **PASS** at
`5c18db77505f876bf70bf7e89c49e8c3b617e0d4`. The run spans
10:51:27 CET–11:00:37 CET on 19 November 2026.

| Cohort | Platform | Suite runs | Passed cases |
| --- | --- | ---: | ---: |
| Native Hunspell, installation, disposal and cancellation | VM / Flutter VM | 4 | 28 |
| Mail cursor and store integration | VM / Flutter VM | 4 | 50 |
| Arabic writing and range rules | VM / Flutter VM | 3 | 294 |
| Word language inheritance and finding merges | VM / Flutter VM | 5 | 70 |
| Word editing and proofing integration | VM / Flutter VM | 4 | 73 |
| Studio, PDF, Notes, Zotero and dictionary setup | VM / Flutter VM | 18 | 119 |
| Portable Hunspell provider | Node | 1 | 11 |
| Portable Mail cursor and configuration | Node | 2 | 17 |
| Portable Arabic writing and ranges | Node | 3 | 294 |
| Portable Word language and finding merges | Node | 5 | 70 |
| **Total** | **Native + Node** | **49** | **1,026** |

These 1,026 case executions span 49 suite/platform runs and 38 distinct test
files. Twenty-one Python controls are separate: seventeen bundle controls and
four packaging controls. All 89 strict analysis and formatting targets, locked
offline resolution, whitespace and browser compilation pass. Failed/skipped
cases, reporter errors, duplicate/unfinished cases and suite discrepancies are
all zero. The original 1,372/90 baseline and every rejected/development attempt
are excluded from these totals.

## Evidence

[summary.json](summary.json), [execution.json](execution.json),
[independent-summary.json](independent-summary.json),
[continuity.json](continuity.json), and [reconciliation.json](reconciliation.json)
are readable copies or summaries of the original source-bound receipts.
The independent audit verifies 5,125 source inputs, 11,171 runtime inputs and
thirteen native fixture files. All source/runtime fingerprints remain stable.

[evidence.tar.xz](evidence.tar.xz) contains 103 exact original qualification,
audit and publication-review members. [evidence.index.json](evidence.index.json)
records every original size and SHA-256. The separate
[review archive](../reviews/evidence.tar.xz) has 233 preserved development/review
members with zero qualification contribution. Both are listed in the
[publication manifest](../publication-manifest.json).

## Replay and limits

Use the [committed v4 driver and instructions](../README.md) at this exact source.
The thirteen fixture identities are in [fixture-plan.json](../fixture-plan.json);
the original compiled libraries and dictionary fixtures are retained in the
[earlier native review archive](../../main-delta-v2/reviews/evidence.tar.xz),
whose index records their original paths. The runtime recovery procedure and
original baseline/pre-resolution receipts retain their own identities. A replay
in a new absolute path requires new baseline receipts as explained by the driver
guide; do not edit old evidence to imitate a replay.

The scope is Linux native code, controlled host/Flutter widget behavior, Node
execution and Dart browser compilation. It does not establish an installed
macOS/Windows/mobile build or launch, an actual browser WebAssembly-worker
session, independent linguistic acceptance, live Zotero, installed OS shortcuts,
or actual Word/LibreOffice reopening. No GitHub Actions workflow, job, status or
queue was queried or awaited.
