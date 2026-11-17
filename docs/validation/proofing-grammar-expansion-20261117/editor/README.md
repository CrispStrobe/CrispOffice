# Editor review and correction checks

The final full integration receipt binds these tests to the committed source.
The focused logs here retain the implementation-stage runs and overlap those
final checks; they are not additional independent grammar cases.

- `german-editor-initial.log.gz`: initial widget run. Seven restore-label
  assertions queried the widget tree immediately after scrolling. The test
  harness was corrected to pump after `ensureVisible`; product labels were
  already present.
- `german-editor-reviewed.log.gz`: all 19 real-provider/editor integration
  tests passed, including new rule corrections, recheck, undo/redo, stale
  source rejection and ignore/restore labels.
- `proofing-context.log.gz`: all five context-preview widget tests passed,
  including long paragraphs, joined emoji, insertion semantics, bounded
  finding previews and a narrow window with larger text.

The authored soft-hyphen correction test spans differently formatted German
runs preceded by an English no-proof segment and emoji. The replacement uses
original UTF-16 coordinates, and undo restores the authored text and formatting.
