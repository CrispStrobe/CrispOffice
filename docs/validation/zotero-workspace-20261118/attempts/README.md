# Excluded editor and analysis attempts

These attempts do not contribute to the accepted 720-test total.

| Archive / record | Actual outcome | Treatment |
| --- | --- | --- |
| [Initial editor run](editor-initial-overflow.tar.xz) | Exit 1; 252 successes and five genuine narrow-layout failures | Preserved; fixed by reserving space for the new wrapped action row, then rerun completely |
| [Interrupted editor run](editor-interrupted-before-test-style-fix.tar.xz) | Orchestration exit 130; Flutter child exit unknown, no final completion or after-guard claim | Preserved; interrupted before two test-only brace fixes, then rerun completely |
| [Initial source checks](checks-before-test-braces/summary.json) | Two analyzer brace-style infos in the new test; format and whitespace passed | Corrected; final strict checks all pass |

The [initial-run index](editor-initial-overflow.index.json) and
[interrupted-run index](editor-interrupted-before-test-style-fix.index.json)
record the archive hash and every retained file's original bytes/hash. Archives
contain actual commands, raw events, stderr and the available input/outcome
records. No missing final child status is inferred from wrapper interruption.
