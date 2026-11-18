# First incoming-cohort run — failed, evidence retained

Tested source: `3668ed92829dfa012ec5b129943a86738ebb7992`. This attempt is **not acceptance**.
The guarded 18-suite run completed with **262 passed, 7
failed and 0 skipped**, actual Flutter process exit
**1**, in 33.1 seconds. Both static
checks passed on all six incoming Dart targets: strict analysis reported no
issues and the nonmutating formatter reported zero changed files.

All **550** recorded source inputs match the specified
commit. Source, dependency, runtime and workspace inventories remained unchanged;
all selected suites executed and every test start finished exactly once. The
report records 7 error events and
6 missed-tap/layout diagnostics; these are
failures, not excluded warnings. Nothing from this attempt is added to a final
passing total.

## Failures and diagnosis

- `word_live_review_selection_test.dart`, test **unchanged selected text rebinds
  after another paragraph is corrected**: the old assertion expects a temporary
  null selection after correcting another paragraph. Incremental proofing now
  immediately preserves/rebinds the untouched paragraph's finding. Any repair
  must still check current revision, correct paragraph/caret, and rejection of
  the stale original issue.
- Six cases in `word_live_review_changes_test.dart` fail in `_choose`. The filter
  `ExpansionTile` has `maintainState: true`; a collapsed child's finder therefore
  exists without being hit-testable. The helper uses existence to decide whether
  to expand, taps the hidden dropdown, then fails to locate the unopened choice.
  Repair must operate the visible expansion control and require hit-testable
  user interactions rather than suppressing tap warnings.

No product or test input was changed by the runner or by this failure review.
The integration owner received the complete failure report before any requested
repair. Future attempts must use a new output directory and bind their committed
source separately, preserving these original receipts.

After that report, the integration owner authorized test-only repairs to the
two affected files. The null-selection expectation was replaced with stronger
current-revision/paragraph/caret and stale-application checks, and the change
filter helper now expands and taps genuinely visible controls. No cases or
existing post-check safety assertions were removed. The new runner checks seven
targets; this attempt's original six-target runner is preserved below and its
SHA-256 still matches `summary.json`.

## Evidence

- [Full summary and static-check output](attempt-1/summary.json)
- [Raw machine events](attempt-1/events.jsonl.gz)
- [Before/after inputs and source binding](attempt-1/inputs.json.gz)
- [Runner output](attempt-1/runner.log)
- [Executed runner](attempt-1/run_incoming_editor.py)

No GitHub Actions, workflow or CI-status endpoint was used.
