# Studio Zotero transport qualification — 18 November 2026

**Accepted: all 18 substantive transport tests passed in the one selected Studio suite, with zero skips or error events.** The Flutter child and evidence runner exited zero and the complete raw event stream ends with one successful completion. One hidden suite-loading event is excluded. The selected path is `packages/quds_office_editor/example/test/studio_zotero_citing_transport_test.dart`, which does not overlap the engine or editor cohorts.

The run used the actual external workspace and the same frozen product `1ccf329da190d47720962bd9d8c65c90acf562db`, genuine Flutter/Dart runtime and shared CLI lock as the accepted editor run. Exact observed Git heads, command, elapsed time and package closure are recorded in `summary.json`. The child ran for 14.982 seconds.

All guards passed: 596 current Studio/editor/engine/reports/parser/Harper source, selected test, asset, fixture and manifest files; 2738 reachable dependency files; 1170 Dart/Flutter runtime inputs; 16 exact workspace inputs; and the one-file test selection. Every before/after map is retained. The exact graph, lock, manifests and analysis inputs are preserved in `workspace-inputs.json.gz`.

`events.jsonl.gz` preserves complete unmodified machine output; `stderr.log.gz`, `machine-envelopes.json.gz`, `cases.json.gz` and `process-exit.json` preserve stderr, machine infrastructure envelopes, substantive cases and the early child-exit receipt. The exact runner is `../editor/run_editor.py`, bound by `runner_sha256`. Separate post-run replay recomputed all 18 successes, verified final completion and child exit, rechecked every indexed artifact hash, and compared all four before/after map pairs.

The three accepted selections are disjoint: **408 engine + 215 editor + 18 Studio = 641 substantive tests**. Setup smokes, focused development tests and the rejected first editor attempt are excluded from this total.

This is execution of the example Studio's real transport implementation under its test doubles. It does not establish live Zotero/Desktop/private-account or packaged-app acceptance. No GitHub Actions/status endpoint was used.
