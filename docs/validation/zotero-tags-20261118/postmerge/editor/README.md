# Editor Zotero — complete validation after main refresh

**Passed: 235 substantive tests across 17 suites, with zero skips, error events or missed-tap warnings.** The Flutter child and evidence runner both exited zero. The 17 hidden loading events are excluded.

## Current product binding

This accepted cohort runs saved merge commit **`4e06d42d20521f56164303aa6c135d5580ea0948`**, which incorporates main `1ffcf91a3443caf9a6e8b45a3e6cab3f041831ae` and retains the tag improvements. The complete selection is all 17 editor `test/*zotero*_test.dart` suites: the prior 16 suites plus the 20-case tag-filter widget suite.

The external workspace uses all 11 exact current manifests and the refreshed **110-package** graph, including the new spaCy workspace member. The hosted lock and pinned runtime are unchanged. Commands, UTC timestamps, package closure, start/end Git heads, exact manifest/graph/lock text and actual child exit are retained in the execution records and `workspace-inputs.json.gz`.

All before/after guards pass:

- **536** source/test/asset/fixture/manifest inputs;
- **1966** reachable dependency files;
- **1142** pinned runtime inputs;
- **13** exact workspace inputs;
- the exact **17-file** test selection.

The source inventory includes the newly merged German agreement implementation and changed platform spelling and German proofing libraries. `source-commit-equivalence.json` additionally verifies that every recorded source file exactly matches its blob at the saved merge commit. There are zero missing or different files.

## Preserved evidence

`events.jsonl.gz` and `stderr.log.gz` retain complete raw output. `cases.json.gz` retains substantive outcomes; `machine-envelopes.json.gz` preserves Flutter infrastructure envelopes. `process-exit.json` records the Flutter child exit before parsing; `runner-exit.json` records the evidence-runner exit. The parameterized runner is `run_editor.py`, bound by its SHA-256. `replay.json` independently replays raw events and rechecks all original indexed artifacts and guard pairs. Child execution took **51.774 seconds**; this is a local test duration, not a product benchmark.

The earlier complete cohort at `270a38ad…` remains unchanged in `../../local/editor/` as historical baseline evidence. It is not added to this current-source total. Earlier focused, setup and interrupted runs also contribute nothing to current acceptance.

## Scope

This is genuine Flutter execution with synthetic documents and controlled Zotero responses/local HTTP controls. It establishes targeted current-source regression behavior, including the tag UI when applicable. It does not establish live-account, desktop-picker, complete-application-build, native-spaCy feature, Word or LibreOffice acceptance. No GitHub CI/check/status endpoint was used or awaited.
