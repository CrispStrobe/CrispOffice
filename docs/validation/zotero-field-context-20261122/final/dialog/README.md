# Accepted integrated native field-context dialog qualification

This is a fresh execution on source commit
`67677aa7e16ea5e4eff3bcd06ffa6e27c5907246`, tree
`9409113e6440e62f73c3db00ab84b4505bc3bcd2`. It follows the main/Mail integration
and the message-area sizing correction. The Git head already contained that
correction before this execution began.

The complete `word_zotero_field_context_dialog_test.dart` suite passed
**21 distinct cases**, with no failures or skips. Loader/setup/teardown events
are excluded. [dialog-receipt.json](dialog-receipt.json) records exact commands,
source identifiers, case names, return code, timestamps and log hashes;
[dialog.jsonl](dialog.jsonl) retains the raw events. All five captured Dart
source/test files and five manifest/lock/FVM records remained unchanged during
this run.

Coverage includes staged-original excerpts, all native alert button mappings,
repeated selection, cancellation, stale/disposed host cleanup, pending inserted
fields, footnote/endnote Notes selections, multipart bibliography context, the
compact dialog at 360 × 640/2× text, and both cancellation paths in the regular
references workspace at 700 × 440/2× text with a long bibliography. The latter
cases exercise scrolling, Cancel reachability, context cleanup and unchanged
writing selection/document history.

The message area now retains its existing bounded, natural-height scroll rather
than reserving a flex share. Selected context remains flexible and the busy
instruction remains bounded. This rerun checks the complete field-context
suite with that correction; pagination-specific qualification belongs to the
separate existing-editor cohort.

Strict analysis of the same test file uses `--fatal-infos --fatal-warnings`;
its exact command, source and result are in
[analysis-receipt.json](analysis-receipt.json) and [analysis.txt](analysis.txt).

The earlier integrated execution on `c6941f9a` is preserved unchanged under
[attempt-1](attempt-1/README.md). Its 21 passes are historical and are not added
to the accepted total above. Earlier diagnostics remain under the work record's
`checks/dialog/` directory. This run does not attribute its results to later
source changes without a separate comparison or rerun.

The official pinned runtime and locked dependencies are retained. Commands use
`--no-pub`, `--no-version-check`, analytics suppression and `CI=true`. No source
edits, GitHub Actions waits, installed Zotero session or Word/LibreOffice
application qualification are part of this rerun.
