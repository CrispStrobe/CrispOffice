# Post-merge local qualification

The incoming document-review head
`ecbb1e0bd8129a5c8737496d1877863dd0eea3f2` changes the editor review pane and
proofing capture/cache implementation after the preceding saved Zotero
qualification. The previous passing results and every unsuccessful attempt
remain unchanged in their original directories. They are historical evidence,
not acceptance of this later merged source.

The integration owner will save the resolved merge remotely before either
cohort executes. The complete 26-suite editor Zotero cohort and this 20-suite
review/proofing cohort are rerun against that saved source. Both use the common
`zotero-toolchain/flutter-cli.lock`; their test-suite selections are disjoint.
No GitHub Actions, workflow, or CI-status endpoint is required or used.

## Merge resolution

`word_live_review_selection_test.dart` is the sole conflicting file. The
resolution combines both sides' assertions for the unchanged selected text:

- The immediately retained issue is non-null, differs from the old issue, and
  refers to the same untouched paragraph at the current revision.
- Its original text and start/end offsets match the old finding, preserving
  the incoming checks.
- The old issue is stale and cannot apply a suggestion; its paragraph remains
  unchanged after the rejected application.
- All four captured caret fields remain unchanged, and the incoming explicit
  paragraph, selection-anchor and logical-offset checks remain present.
- All original assertions after the explicit document recheck remain present.

The changes helper auto-merges. All incoming cases, including native-boundary
previews, language changes, read-only language controls and restoration of
ignored findings, remain present. The helper continues to reveal the filter
header, read public expansion state, tap only if collapsed, and require real
hit-testable taps. The incoming `_drain` starts a frame before its bounded
duration; the redundant identical initial frame in `_tap` is removed. The
incoming product files are not changed by conflict resolution.

## Selected suites and strict targets

All 18 previously selected review/proofing and consumer suites remain selected,
plus these two new suites:

- `word_incremental_proofing_menu_test.dart`
- `word_proofing_capture_cache_test.dart`

The new runner explicitly asserts 20 unique suites, all present, including the
three original incoming suites and the two new suites. It excludes every
`word_zotero*_test.dart` path. All paths are relative to
`packages/quds_office_editor/test/`; the runner records the complete selection.

Strict analysis (`--fatal-infos --fatal-warnings`) and nonmutating formatting
cover the previous seven targets plus the two new tests: **nine targets**.
The three product targets are `office_controller.dart`,
`word_review_pane.dart`, and `word_proofing.dart`. The six test targets are
`word_incremental_proofing_test.dart`, `word_live_review_changes_test.dart`,
`word_review_controller_test.dart`, `word_live_review_selection_test.dart`,
`word_incremental_proofing_menu_test.dart`, and
`word_proofing_capture_cache_test.dart`.

Before the source checkpoint, static preflight records formatting and analysis
on those exact nine files, with before/after hashes. It does not execute tests
and does not establish full acceptance. The final guarded runner repeats both
strict checks after binding the saved source commit.

## Final-run guards and evidence

`run_incoming_editor.py` is a new copy of the prior guarded runner. The prior
executed runners and receipts are not edited. This copy retains the original
source/dependency/runtime/workspace guards, lock, exact runtime, raw events,
actual process exit, completed-start counting, fixture/icon-font bindings,
source-commit Git blob checks and descendant check. A source mismatch fails
preflight before tests. Every selected suite must execute, every start must
finish exactly once, and skips/errors/parser issues/layout or missed-tap
diagnostics fail acceptance. Historical and focused runs add nothing to its
passing count.

From the checkout, after the remote source checkpoint:

```bash
python docs/validation/zotero-citation-workflow-20261118/post-merge/run_incoming_editor.py \
  --source-commit FROZEN_MERGE_COMMIT_SHA \
  --output docs/validation/zotero-citation-workflow-20261118/post-merge/incoming-editor
```

The output directory must be fresh. It retains the summary, strict-check
output, selected paths, raw machine events, input inventories and artifact
hashes. The parent integration owner saves the final receipts remotely.
