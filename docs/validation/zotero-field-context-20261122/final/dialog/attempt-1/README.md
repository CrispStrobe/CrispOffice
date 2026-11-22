# Integrated native field-context dialog qualification

This is a fresh execution on integrated source commit
`c6941f9ae82c74bf0f8d8a2a15d2a7a2c47c9f4f`, tree
`4b9bc320788c30daf5b17bd8868ad8a651c86fa3`, after the captured main and Mail
integration. It does not reuse earlier dialog passes as a new execution.

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

Strict analysis of the same test file uses `--fatal-infos --fatal-warnings`;
its exact command, source and result are in
[analysis-receipt.json](analysis-receipt.json) and [analysis.log](analysis.log).

The official pinned runtime and locked dependencies are retained. Commands use
`--no-pub`, `--no-version-check`, analytics suppression and `CI=true`. No source
edits, GitHub Actions waits, installed Zotero session or Word/LibreOffice
application qualification are part of this rerun. Earlier diagnostic evidence
remains in `../../checks/dialog/`; repeated runs are not added to these 21 cases.
