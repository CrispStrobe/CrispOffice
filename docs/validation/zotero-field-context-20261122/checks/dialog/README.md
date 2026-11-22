# Native Zotero field-context dialog checks

The focused suite is
`packages/quds_office_editor/test/word_zotero_field_context_dialog_test.dart`.
It exercises the actual native HTTP driver, controller transaction, dialog
routing, and context view with a controlled local Zotero transport.

The accepted integrated run passed **21 distinct cases**, with no failures or
skipped cases. Loader/setup/teardown events are excluded. See
[final-receipt.json](final-receipt.json) and the raw [events](final.jsonl).
The five directly relevant implementation/test files captured in that receipt
were unchanged between the start and end of the run. This is a focused source
check, not an installed Zotero/Word/LibreOffice run. It does not attribute these
results to later source changes without a separate comparison or rerun.

## Coverage

- A selected source excerpt and paragraph location remain original while
  replacement text/code are staged; completion publishes one undoable update.
- All eight buttons across Zotero's four alert button sets retain exact reply
  codes. Unchanged/cancel responses preserve the backward writing selection
  and do not create undo history.
- Repeated `Field.select` prompts replace the previous field context.
- Cooperative cancellation, stale writing targets, invalidated hosts and
  disposed hosts remove context without applying staged results.
- Newly inserted fields explain their pending position and expose neither
  detached ranges nor staged text.
- Footnote/endnote context preserves the active Notes selection; multipart
  bibliography context includes both original entries.
- Compact progress and modal alerts remain usable at 360 × 640 logical pixels
  with 2× text scaling, including a long bounded excerpt.
- The regular references workspace, with `closeAfterCommand:false`, remains
  usable at 700 × 440 logical pixels and 2× text scaling with a twelve-entry
  long bibliography. Both the pending-operation and subsequent native-alert
  paths expose scrollable source context and a reachable Cancel action.
  Cancellation preserves document content, writing selection and undo history;
  it clears context and re-enables the workspace's Close control.

## Investigation and retained attempts

The earlier 19-case run in [attempt-2-receipt.json](attempt-2-receipt.json)
preceded the regular-workspace extension and final viewport changes. Its passes
are historical and are not added to the accepted 21-case total.

The first attempt's 18 passes and one failed expectation are retained in
[attempt-1-receipt.json](attempt-1-receipt.json). The stale-target expectation
incorrectly looked for a raw host error; the native driver intentionally wraps
that error in its existing safe message. The corrected case also stages a real
replacement before invalidation. No product change was needed for that failure.

The regular-workspace extension then reproduced a real layout problem. At
700 × 440/2× scale, the workspace's 668 × 408 outer Column overflowed by 646
pixels. Isolated geometry showed that its unbounded busy instruction/Cancel Row
consumed 768 pixels, while the already bounded context used 110 pixels. The
title used 126 pixels, tabs 48, and progress 2; the TabBarView received zero
height. The detailed failed layout attempts are retained in
[attempt-3-workspace-receipt.json](attempt-3-workspace-receipt.json),
[attempt-4-workspace-diagnostic-receipt.json](attempt-4-workspace-diagnostic-receipt.json),
and [attempt-5-workspace-geometry-receipt.json](attempt-5-workspace-geometry-receipt.json).
The first layout failure also exposed missing fake-transport teardown in the
new cases; teardown now always releases a pending response so one failed test
cannot keep a native session alive into the next case.

The product correction bounds the instruction's scroll area, keeps Cancel
separate and reachable, and lets the capped context/messages share remaining
space through loose flex. Both cases then reached successful cancellation and
context cleanup. [Attempt 6](attempt-6-workspace-receipt.json) still failed its
last test-only assertion because `find.byTooltip` returns a tooltip widget,
not its IconButton. The corrected typed IconButton finder required no further
product change. The complete accepted run above includes both corrected cases;
failed and diagnostic executions receive no pass credit.

## Command and static check

```bash
source /workspace/scratch/2437eaf6f35d/toolchains/env.sh
cd /workspace/scratch/2437eaf6f35d/quds_office_suite/packages/quds_office_editor
"$FLUTTER_ROOT/bin/flutter" --no-version-check --suppress-analytics test \
  --no-pub --reporter json test/word_zotero_field_context_dialog_test.dart
```

The environment retains `CI=true`, preventing Flutter's cloud metadata
autodetection; SDK/dependency provenance belongs to the runtime record.

Strict analysis of the complete new test file uses
`dart analyze --fatal-infos --fatal-warnings`; see
[analysis-final-receipt.json](analysis-final-receipt.json) and
[analysis-final.log](analysis-final.log). Earlier static logs retain their
original test-source attribution.
