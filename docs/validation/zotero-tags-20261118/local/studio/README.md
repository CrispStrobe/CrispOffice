# Studio Zotero transport validation

**Passed: 18 substantive tests in one suite, with zero skips or error events.** Both the Flutter child and evidence runner exited zero. One hidden suite-loading event is excluded. The selected path is `packages/quds_office_editor/example/test/studio_zotero_citing_transport_test.dart`, which does not overlap the engine or editor cohorts.

## Exact source and execution

The run used saved product commit **`270a38adf97b9a027b79a00e2654acac6ebb1df6`**, the same pinned runtime and unchanged dependency graph as the editor cohort. Complete commands, package closure, UTC timestamps, Git heads and the child-exit receipt are retained. The parameterized runner is `../editor/run_editor.py`, bound by its SHA-256 in the execution records. Child execution took 14.253 seconds.

All before/after guards pass: 596 production source, selected test, asset, fixture and manifest files; 2738 dependency files; 1142 runtime files; 16 exact workspace inputs; and the one-file test selection. `source-commit-equivalence.json` also verifies every recorded source file against the saved commit, with zero missing or different files.

`events.jsonl.gz` and `stderr.log.gz` preserve complete raw output; `cases.json.gz` separates substantive outcomes from loading events. `machine-envelopes.json.gz` retains Flutter infrastructure envelopes, and `workspace-inputs.json.gz` contains the exact unchanged manifests, lock and generated dependency graph. Setup, focused development and interrupted editor runs are excluded.

## Scope

This cohort executes the Studio transport implementation using its local HTTP controls and test doubles. It verifies regression behavior with the current product source; it does not establish live-account, desktop-picker, full application build, Word or LibreOffice acceptance. No GitHub CI/check/status endpoint was used or awaited.
