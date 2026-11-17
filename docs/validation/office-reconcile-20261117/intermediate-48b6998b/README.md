# Second-wave canonical qualification at intermediate source 48b6998b

## Attribution and acceptance boundary

This complete local selection passed on immutable source
`48b6998bb47ffdf43e95025229dc5a5eab09ee9a`, tree `741494bdebf9afa7c2a341f745f85f07a799cad1`.
It is preserved as an **intermediate positive qualification**, not final acceptance
of the continuation. During this run, a separate host path exposed a concrete gap:
a leading inline `WmlBreakType.column` imported from DOCX can be lost in ODT export.
The property-based column-break tests in this selection do not cover that imported
inline form. The correction and its controlled regression require a new immutable
source and a complete fresh qualification. None of the counts below may be reused
as coverage for the corrected source.

## Fresh results for this source

**3,774 substantive Dart/Flutter passes across 206 files**;
separately **117 Python controls passed**. There were no test skips or failures.
All seven strict-analysis scopes and 121 selected handwritten formatting targets
passed. Raw Dart/Flutter successes total 3,776; exactly
two private-PDF tests return before assertions because the private file is absent,
and are excluded from the substantive total.

| Cohort | Selected files | Substantive passes |
| --- | ---: | ---: |
| engine-zotero | 19 | 390 |
| editor-zotero | 13 | 186 |
| engine-integration | 108 | 2346 |
| editor-integration | 39 | 423 |
| harper-contract | 3 | 29 |
| gector-contract | 14 | 247 |
| aot-contract | 10 | 153 |

All 189 previously qualified files are retained, including all 179 from the earlier
baseline. Seventeen files were added: nine engine suites for columns, decoration,
tabs/tables, nominal words and participles; three GECToR suites; four AOT suites;
and the Studio example widget suite. Every added or modified tracked testpath
relative to `ec5ecbff` is assigned to a cohort. File retention does not imply that
historical outcomes were counted. Parallel suites exercise overlapping behavior;
these are fresh executed test cases, not counts of distinct semantic capabilities.
Raw and substantive per-file counts are recorded separately.

## Runtime, dependency and optional coverage

Flutter 3.47.8 and Dart 3.13.7 ran in the private runtime copy. The external workspace
resolved 110 packages offline with the exact historical lock SHA-256
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`. Source manifests and lock bytes did not
change. The AOT workspace member did not require dependency-version changes.

All 247 GECToR cases passed, including real native dual-head calls, independent
output ownership and disposal checks using the authenticated native library
`9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604` and model
`549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b`.
These fixture checks do not establish broad model quality or intended-device
latency. The Python environment contains ONNX and ONNX Runtime; its real tiny
quantizer control passed and preserved both output-head matrices. All 117 selected
Python case IDs succeeded without an optional skip.

The full AOT Dart `lib`, `test` and `tool` surfaces and Studio integration are
strictly analyzed. Its153 cases cover controlled transports, the local
child-process protocol, caching and source mappings. The process worker used by
these tests is a controlled Dart fixture. Linux executed the applicable platform
cases; web/mobile-only registrations are not represented as tested. The three
native build/smoke/CLI Python scripts were AST-parsed and hashed without being
imported or executed; CMake and worker sources were hashed. **No fresh native AOT
compilation, real dictionary inference or live external AOT service is claimed.**
The recovered environment lacks cmake, flex and bison. Any incoming native AOT
qualification evidence must retain its separate source/runtime attribution.

## Integrity and independent recount

All recorded source, dependency, runtime, workspace, system/fixture and harness
maps matched before and after. The temporary analyzer package configuration was
restored. A separate audit reparsed every raw JSON event stream, checked raw and
compressed hashes, matched selected and executed suite paths, verified every
started test ID completed exactly once, and recounted the two private exclusions.
It rehashed 3,509 source files, checked frozen HEAD/tree and
clean checkout, and confirmed real native and ONNX case outcomes. The audit passed
with no errors in `independent-event-audit.json`.

The run started `2026-11-17T18:25:05.667318+00:00` and finished `2026-11-17T18:31:49.065292+00:00`.
No GitHub Actions, workflow, check-run or CI-status endpoint was queried or awaited.

## Preserved preflight and reproduction

Attempt 1 at `4a4101c11d471adf525849b38dea0a52b9c0b394` passed all seven analyses,
then formatting failed on `odf_text.dart` and AOT `client.dart`. No tests began.
Its raw output, receipts and input maps remain intact. The exact two-file
formatting-only diff is retained; remote 48b6998b applied it and this complete run
started from zero. Earlier ec5ecbff qualification archives remain unchanged and
are not added to these counts.

The archive contains exact prior runners, the versioned second-wave adapter,
Python controls, fresh-workspace setup, complete plan, raw logs, input hashes and
recount script. `prepare_workspace.py --repository <clone> --source-commit <sha>`
creates a new detached source and locked external workspace;
`run_frozen.py --source-commit <sha> --output <fresh-output>` runs the full plan.
Supply the recorded recovered SDK, cached dependencies, Python environment and
pinned native fixture pack. Large model/runtime binaries are not in the archive.

Separate LibreOffice consumer and host evidence keeps its own attribution. This
run does not establish full application/viewer/export-dialog acceptance, live
Zotero/Word interoperability, real native AOT or Wasm acceptance, or broad language
quality. The known imported-inline column-break gap above is explicitly pending.
