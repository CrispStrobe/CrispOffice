# Final editor Zotero qualification — 18 November 2026

**Accepted: all 215 substantive tests passed across all 16 editor Zotero suites, with zero skips or error events.** The Flutter child exited zero, the evidence runner exited zero, and the raw event stream contains one successful completion. Sixteen hidden suite-loading events are excluded from the substantive count. Setup, focused-development and rejected-attempt executions are excluded.

The tested implementation is frozen product commit `1ccf329da190d47720962bd9d8c65c90acf562db`. Exact observed Git heads are recorded in `summary.json`; documentation checkpoints may advance a head, while complete source byte guards establish the tested implementation. The invocation used the actual 109-package external workspace and genuine Flutter 3.47.8 / Dart 3.13.7 runtime. It held the shared Flutter CLI lock throughout preparation, execution and final guards. Elapsed child-run time was 42.195 seconds; this is a local test duration, not an application performance benchmark.

## Guarded inputs

All selected inputs were byte-identical before and after execution:

- 534 current editor, engine, reports and parser source, selected tests, assets, fixtures and production manifests;
- 1966 files from the actual reachable dependency closure;
- 1170 Dart SDK, Flutter tester/patched-engine/font/tool/bootstrap runtime inputs;
- 13 exact generated graph, lock, current manifests and analysis inputs;
- the exact 16-file test selection.

Before/after inventories bind files by length and SHA-256. `workspace-inputs.json.gz` preserves the exact text of all unchanged graph, lock, manifest and analysis inputs. `process-exit.json` records the Flutter child exit before report parsing. `events.jsonl.gz`, `stderr.log.gz`, `machine-envelopes.json.gz` and `cases.json.gz` preserve complete raw events, stderr, valid machine infrastructure envelopes and substantive case results. Valid array envelopes and blank lines are handled separately from Dart test events. The retained raw stream was separately replayed to recompute counts and completion; every indexed artifact hash and every guard pair was rechecked.

## Rejected first attempt

`attempt-1-f57fde45/` preserves the previous complete failed run, its exact runner, raw events, replay and guards. That run exposed a pagination control that was outside the hit-testable dialog area after the added collapsed search-options header increased the default layout height. Its existing Web API pagination test failed. The final product uses a compact search-options action and expands controls only on demand; the full existing case now passes.

The first evidence summarizer also could not handle Flutter's array envelopes. Its process exited during parsing and did not retain the Flutter child exit; that missing value is explicitly left unknown. The corrected runner records process exit immediately and retains these envelope types. No first-attempt successes are added to the accepted 215.

## Scope

This cohort covers every current editor `test/*zotero*_test.dart` file using genuine Flutter execution with synthetic documents and transport doubles. It includes the new query controls, narrow dialog layouts, reconnection, source resolver and connected alias behavior. Live private accounts, a desktop Zotero application, Microsoft Word and LibreOffice acceptance are outside this result. The separate Studio transport cohort is recorded in `../studio/`; its test path does not overlap this selection. No GitHub Actions/status endpoint was used.
