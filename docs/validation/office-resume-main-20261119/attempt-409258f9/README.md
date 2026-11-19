# Rejected first combined gate at `409258f9`

This attempt is preserved in full and contributes **zero cases** to the final
accepted qualification. Its exact source is
`409258f91484039d771d1fe56f097bef6f2d27ea`, tree
`be431b7bed739f535f545f3aea40d2d36fa65b2b`.

The reporter recorded 797 successful visible case completions, but the Studio
cohort failed to load `studio_zotero_shortcuts_test.dart`: its remaining
`enableStudioSetting` call did not match the reconciled helper import. The strict
analyzer independently reported that undefined function. The gate correctly
rejected the attempt despite zero visible failed or skipped cases. The archived
raw events retain the hidden loading failure, stderr and nonzero process exit.

The subsequent repair uses `configureStudioForTest(showNotes: true)` consistently.
Later reconciliation also includes the bounded PR #191 checkpoint, current Mail
lifecycle fixtures, compact Review controls and explicit post-submission Mail
outcomes. Fresh final qualification runs after those changes are frozen.

The archive contains the original receipts, raw and compressed logs, exact
case/error inventories, and complete before/after source/runtime inventories.
Every archive member was reopened and checked against its size and SHA-256.
No Node test run was performed at this rejected checkpoint.
