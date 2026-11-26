# Mail rich templates — continuation validation

Recorded **25 November 2026**. Feature source:
[`93445de76e82f6ec4f799d1eab7c75f1d9406b43`](https://github.com/CrispStrobe/quds_office_suite/commit/93445de76e82f6ec4f799d1eab7c75f1d9406b43).

This record follows the original
[rich-composition qualification](../mail-rich-compose-20261125/README.md).
Earlier test totals are evidence for their named commits and are not claimed
as executions of the new rich-template source.

## Source and review boundary

The continuation:

- Integrates main through `1eb5a9af54d97732696057dffae1d29d5b76074f`.
- Fixes the two rich-test undeclared imports and the inherited redundant
  editor test import, without changing dependencies or lockfiles.
- Adds typed rich templates, schema 22 and quota/corruption handling.
- Preserves formatting in template save, editing, settings reopen and reuse.
- Fences draft revisions and same-revision pending settings replacements.
- Corrects the actual Enter and narrow-window synchronization fixtures exposed
  by the first real Flutter execution.

The [source manifest](source_manifest.json) binds the 25 changed feature/runtime
fixture files by SHA-256, byte length and Git blob identity. Each local file was
checked against its remote blob at the feature commit. Production and test
changes received separate implementation and review passes.

No local Dart or Flutter runtime is available in this continuation's workspace.
The filesystem initially had approximately 2 MiB free; only selected sources
were materialized. This record does not reuse the earlier isolated harness as
if it were still present, and does not claim local Dart analysis or test execution.

## Executed SQL migration check

`schema_sql_smoke.py` extracts the actual schema-21 and schema-22 SQL from
`packages/quds_mail_store/lib/src/schema/database.dart` and runs it with Python's
SQLite **3.53.1** in an isolated compose-table fixture.

All seven checks passed:

1. Additive nullable HTML column.
2. Transaction rollback removes the column and restores the schema version.
3. Legacy literal body bytes remain unchanged after retry.
4. The compose-settings revision remains unchanged.
5. A binary HTML value is rejected.
6. The SQL byte ceiling is enforced.
7. Foreign-key checking reports no violation.

The [executed receipt](schema_sql_smoke.json) includes the full schema source and
exact migration SQL hashes. This is actual SQLite DDL execution, **not** a claim
of Dart/Drift execution or whole-database migration coverage.

Reproduce from the repository root:

```sh
python docs/validation/mail-rich-templates-20261125/schema_sql_smoke.py .
```

## Added regression registrations

| Scope | Added cases | Principal assertions |
| --- | ---: | --- |
| Core compose settings | 7 | Rich/plain agreement, immutable copies, explicit clearing, empty typing styles, per-template and aggregate bounds |
| Store/settings/migrations | 16 | Real close/reopen, formatting-only revisions, stale/failed writes, quota rollback, corrupt HTML/UTF-8/types/version, transfer preflight, schema-21 rollback/retry and historical upgrades |
| Template editor widgets | 9 | Metadata/text/format-only preservation, reopen, unsupported-content Undo, conflict recovery, retired owners, same-revision pending changes and equivalent settings rebuilds |
| Existing rich-compose widgets | 2 | Rich whole-message replacement through save/send; changed-draft refusal during Save as template |
| Sender/template integration | 2 | Conflict rejection and native settings reopen through draft/Outbox/private-Bcc recovery |
| **Total new registrations** | **36** | Supplied source; runtime execution tracked below |

Ten existing migration-related test files update current-version expectations
to 22. Deliberate old-version fixtures remain unchanged, and future-version
rejection fixtures advance to 23/24.

A final parent-integration review found that Writing tools creates a new settings
wrapper during ordinary rebuilds. The follow-up source compares all pending
scalars and ordered immutable members instead of outer-object identity. The
ninth template-editor regression verifies that an equivalent wrapper keeps the
editor usable while actual pending changes still retire it.

## First real Flutter results for the preceding source

Original head
[`5d1f13c0dc4e6ef3e5255e56b7558a355e81ca5e`](https://github.com/CrispStrobe/quds_office_suite/commit/5d1f13c0dc4e6ef3e5255e56b7558a355e81ca5e)
completed the
[Studio mail job](https://github.com/CrispStrobe/quds_office_suite/actions/runs/45659937210/job/139366763915)
with **2,664 passed and 3 failed**.

Two rich-compose failures simulated Enter with `insertText('\n')`, which
inserts a soft break inside a paragraph. They now call the actual
`insertParagraphBreak()` API used by the editor's Enter/IME handlers and assert
two live and saved paragraphs. The adjacent ordinary-Enter case had passed
while testing a soft break; it now uses the structural API too.

The third failure was a narrow Cc/Bcc fixture measuring Send before pending
field/caret scrolling had settled. It now pumps those edits before scrolling
and asserts the button is hit-testable. Recipient, body and disposal assertions
remain intact. This correction requires a Flutter rerun; the prior tap miss
alone was not evidence of an inaccessible product control.

The preceding rich source's individual Studio results were:

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Rich Word conversion | 33 | 0 |
| Rich compose widgets | 15 | 2 |
| Rich MIME/Outbox | 10 | 0 |
| Preview data | 9 | 0 |
| Real rich draft persistence | 14 | 0 |
| Rich preview widgets | 6 | 0 |

Its separate core job passed all 45 canonical-body tests. All four Mail package
jobs passed on that earlier head: core **743**, MIME **84**, store **1,239**,
transport VM **654**, plus **13** transport browser-boundary tests. These totals
overlap the rich-suite rows and must not be added to them.

## Existing unrelated CI failures

The original editor analysis found two PR-introduced `package:test` imports in
the Flutter example. Both now use its declared `flutter_test` dependency. An
inherited unnecessary engine import was also removed.

The original
[engine job](https://github.com/CrispStrobe/quds_office_suite/actions/runs/45659937210/job/139366763866)
reported 17,552 passed and five failures. The same five failures, expectations
and stack locations already occurred on main
`8be821c974c6ff0d98e947e23b8cc587303563a4` in
[baseline CI](https://github.com/CrispStrobe/quds_office_suite/actions/runs/45653667597/job/139344519582):
language metadata, two empty-cell style cases, inherited PowerPoint
markup-compatibility handling and standalone page-break geometry. They are
outside the Mail template changes.

Two older baseline cached-host cancellation failures did **not** reproduce in
the original PR's completed Mail run and are not counted as current failures.

## Current-head qualification

The new source is supplied to the repository's existing pinned Flutter 3.47.8
CI. The Mail package jobs run strict analysis and tests, the editor job runs
`flutter analyze`, and the Studio mail job includes all new widget/integration
files with:

```sh
cd packages/quds_office_editor/example
flutter test test/studio_mail*_test.dart test/studio_saved_mail_test.dart
```

At this documentation checkpoint, new-source CI is pending. No passing
Dart/Flutter result is yet claimed for the template increment or corrected
fixtures. Current workflow results must be inspected independently of earlier
head results.

The PR remains draft. Installed builds, browser persistence, platform
clipboard/file-picker behavior and actual mail-client rendering remain open.
No live mail was sent.
