# Editor Zotero tag-filter validation

**Passed: 235 substantive tests in 17 suites, with zero skips or error events.** The Flutter child and evidence runner exited zero. The 17 hidden loading events are excluded. Focused development runs, the interrupted run, and setup smokes contribute nothing to this accepted total.

## Source and execution

The complete cohort ran from saved product commit **`270a38adf97b9a027b79a00e2654acac6ebb1df6`**. The selection contains the prior 16 editor Zotero suites plus `word_zotero_tag_filter_test.dart`; it includes the 20 new tag UI cases once. The complete command, working directory, UTC timestamps and observed Git heads are in `run.json`, `process-exit.json` and `summary.json`.

The corrected tag test's SHA-256 is `65431a886247a564abfa7b63f1adbe8db03786cd71a617db74390111e2743229`. The tested implementation includes the corrected **“Capitalization is kept as entered.”** helper text. Tag input spelling is preserved; the client does not promise case-sensitive upstream matching.

All before/after guards pass:

- 535 production source, selected test, asset, Zotero fixture, manifest and analysis inputs;
- 1966 reachable dependency source inputs;
- 1142 pinned Dart/Flutter runtime inputs;
- 13 exact generated graph, lock, manifest and analysis inputs;
- the exact 17-file test selection.

`source-commit-equivalence.json` additionally verifies that every recorded source file is byte-identical to its blob at the saved product commit. The unchanged manifest/graph content is retained in `workspace-inputs.json.gz`.

`events.jsonl.gz` preserves raw machine events; `stderr.log.gz`, `machine-envelopes.json.gz`, `cases.json.gz` and the early child-exit receipt preserve the complete execution outcome. The parameterized runner is `run_editor.py`. Elapsed child-run time was 51.971 seconds, a test duration rather than a product benchmark.

## Preserved development attempts

- `attempts/focused-1/`: 18 successes and two test-harness failures; the delete tap ran before the caret-reveal scroll settled, and Flutter removed the newline input before application validation. The helper was corrected and a preserved TAB control input substituted. No product changes were needed for those failures.
- `attempts/focused-2/`: the focused 20-case run passed after those harness corrections. Its results overlap this full cohort and are excluded from accepted totals.
- `attempts/full-before-wording-correction/`: the first full run was intentionally interrupted for the product wording/test-name correction. The executor returned 130. The Flutter child exit was not recorded and remains explicitly unknown; this incomplete attempt is excluded.

The historical focused test name described case sensitivity, but its assertions only checked capitalization preservation in outgoing tag inputs. The final source corrects that wording before this accepted run.

## Scope

These are genuine Flutter widget/controller executions with synthetic documents and controlled Zotero responses. Coverage includes existing editor Zotero behavior, repeated tag requests, submitted-query pagination, selection retention, scopes, reconnect, validation/recovery, pending-close disposal, and 20-tag layouts at 320, 360 and 420 pixels. This is not live-account, desktop-picker, complete-application-build, Word or LibreOffice acceptance. The Studio transport cohort is separate and disjoint. No GitHub CI, check or status endpoint was used or awaited.
