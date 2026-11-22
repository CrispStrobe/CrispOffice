# Native Zotero field-context dialog checks

The focused suite is
`packages/quds_office_editor/test/word_zotero_field_context_dialog_test.dart`.
It exercises the actual native HTTP driver, controller transaction, dialog
routing, and context view with a controlled local Zotero transport.

The accepted second run passed **19 distinct cases**, with no failures or
skipped cases. Loader/setup/teardown events are excluded. See
[attempt-2-receipt.json](attempt-2-receipt.json) and the raw
[events](attempt-2.jsonl). The five directly relevant implementation/test files
captured in that receipt were unchanged between the start and end of the run.
This is a focused source check, not an installed Zotero/Word/LibreOffice run.

Coverage includes:

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

The first run's 18 passes and one failed expectation are preserved separately
in [attempt-1-receipt.json](attempt-1-receipt.json). The stale-target expectation
incorrectly looked for a raw host error; the native driver intentionally wraps
that error in its existing safe message. The corrected case also stages a real
replacement before invalidation. No product change was needed. Repeated passes
are not added to the accepted count.

## Command

```bash
source /workspace/scratch/2437eaf6f35d/toolchains/env.sh
cd /workspace/scratch/2437eaf6f35d/quds_office_suite/packages/quds_office_editor
"$FLUTTER_ROOT/bin/flutter" --no-version-check --suppress-analytics test \
  --no-pub --reporter json test/word_zotero_field_context_dialog_test.dart
```

The environment retains `CI=true`, preventing Flutter's cloud metadata
autodetection; SDK/dependency provenance belongs to the runtime record.

Strict analysis of the new test file also completed with no issues using
`dart analyze --fatal-infos --fatal-warnings`; see
[analysis-receipt.json](analysis-receipt.json) and [analysis.log](analysis.log).
