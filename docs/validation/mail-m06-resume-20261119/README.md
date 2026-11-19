# Mail M06 continuation — 19 November 2026

## Recovered source and incoming reconciliation

The continuation restored `eafcd80fdfbd7ff678a7a04fb9a9a98b5330ad00` from
`codex/mail-reader-20261118`. The previously isolated M06 source had not been
published. It is being implemented and reviewed separately from the baseline
qualification below.

Three subsequently captured commits from the thesaurus and Zotero branches
were integrated into published source
`479e1e038af0467b7f07b35d80bac9e4cc60a198`, tree
`03b895b74affd80c54fa1c35dfa87a6eb1d645c6`. All 389 captured external references
are accounted for by ancestry or 14 freshly reverified historical equivalents.
The five existing Notes source/test/changelog files were preserved exactly;
the incoming integration changes only documentation and evidence. See
[incoming verification](incoming/post-integration-source-verification.json),
[ref audit](incoming/post-integration-audit.json), and
[remote readback](incoming/published-readback.json).

## Fresh baseline Mail qualification: PASS

The [receipt](baseline/mail-receipt.json) binds source commit `479e1e03` and
records 186 passing test executions, zero failures and zero skips:

| Cohort | Passing cases |
| --- | ---: |
| Core VM | 30 |
| Core Node | 30 |
| Native store VM | 87 |
| Portable store policy/codec Node | 39 |

The 42 Python launcher regressions, enforced offline lock resolution, strict
core/store analysis, formatting, browser entry/worker compilation and whitespace
checks also pass. Source hashes and all direct launcher/native asset inputs
are unchanged before and after execution. VM and Node repetitions are reported
as separate executions, not distinct test scenarios.

[Original logs and case lists](baseline/mail-results.tar.xz) are retained with
an [archive index](baseline/mail-results.tar.index.json). Actual browser
persistence, locking, reload and quota behavior are not covered by these Node
and compilation checks.

## Runtime and Office qualification

The official Flutter 3.47.8 / Dart 3.13.7 archive, 176 hosted package archives,
SQLite hook asset and workspace native mapping were independently restored
and verified. The root dependency lock was unchanged. The [runtime receipt](runtime/runtime.json)
and [original restoration evidence](runtime/restore-evidence.tar.xz) retain the
new run's identities, command logs, retained input manifest and omissions.

The 72-suite Office/reader plan passed against the same frozen source with
**1,230 cases, zero failures and zero skips**: 233 engine, 887 editor, 99 Studio
and 11 Mail-reader cases. Strict analysis, formatting and whitespace checks
passed. All 5,002 materialized source inputs and 11,163 runtime inputs remained
unchanged. See the [complete receipt](baseline/office-verification.json),
[original evidence](baseline/office-results.tar.xz), and
[archive/case-list audit](baseline/office-archive-audit.json). Historical counts
from earlier work are not included in these fresh results.

## Continuation boundaries

Checkpoint `c2db80d4caacb4818c06d596566e50f25811d28a` preserves nullable
durable standard flags and schema v3 migration source. Its additional behavior
tests remain unexecuted at this evidence checkpoint. Bounded native IMAP
transport is being integrated next, followed by complete local protocol/store
validation. The baseline test results above apply to source `479e1e03`.
System-browser OAuth, actual browser storage, live disposable-account
interoperability, SMTP composition/submission and the account-aware UI retain
their independent implementation and acceptance gates.

No GitHub Actions workflow, job or status was queried, awaited or rerun.
Remote checkpoints use `[skip ci]` and non-forced expected-head updates.
