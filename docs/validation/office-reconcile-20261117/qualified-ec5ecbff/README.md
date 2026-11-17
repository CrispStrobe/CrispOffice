# Canonical Office continuation qualification — 17 November 2026

## Accepted source and result

The complete qualification passed on remote source commit
`ec5ecbff742580c0e7d1136507b953e8cc877e4c`, tree
`147b6903c88d72fc8844513f6fe357fac6d608c0`.

**3,494 substantive Dart/Flutter passes across 189 test files**, and separately
**113 Python controls passed**. No test skips or failures occurred. All seven
strict-analysis scopes and all 100 selected handwritten formatting targets passed.
The raw Dart/Flutter success count is 3,496; two inherited private-PDF tests return
before assertions because the private input is unavailable, and are excluded from
substantive coverage. Historical results are not added to these fresh totals.

| Fresh cohort | Files | Substantive passes |
| --- | ---: | ---: |
| aot-contract | 6 | 99 |
| editor-integration | 38 | 410 |
| editor-zotero | 13 | 186 |
| engine-integration | 99 | 2186 |
| engine-zotero | 19 | 390 |
| gector-contract | 11 | 194 |
| harper-contract | 3 | 29 |

This includes all 576 Zotero tests, 194 GECToR tests with the pinned real native
fixture, 99 optional AOT package tests, and 12 Studio AOT widget tests within the
410-test editor integration cohort.

## Suite retention and new coverage

All 179 files selected by the previous accepted qualification are retained. Ten
files are added: all six `quds_proofing_aot` test files, Studio AOT widget tests,
ODT PAGE-field fidelity, ODT table/tab fidelity, and German noun agreement.
The new dedicated engine suites contain 22 PAGE-field, 10 table/tab, and 47
noun-agreement cases. Existing suite files also contain newer regressions;
`test-counts-by-file.json` gives the fresh raw per-file counts.

The optional AOT package's complete `lib`, `test`, and `tool` Dart surface is
analyzed (16 files), with its Studio integration analyzed separately. The other
analysis scopes cover selected engine, editor, Harper, GECToR, incoming ONNX tool,
and model/AOT runner paths. Analysis scopes can overlap; they are not test counts.
Generated German data is excluded from formatting only after authenticating the
committed generation manifests and file hashes. The full-repository formatter is
not claimed.

## Inputs, native fixture and Python converter

The source is checked out in its own detached worktree. All source manifests are
unchanged. The external validation workspace has 110 packages and uses the exact
historical lock SHA-256
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
Adding the AOT workspace member required no lock or dependency-version change.
Flutter 3.47.8 / Dart 3.13.7 are preserved in a private runtime copy; package cache
metadata is private and dependency sources are read-only links to the recovered
cache. The setup receipts retain the exact offline resolver commands and hashes.

The native GECToR test executed real forward calls, verified both output heads,
checked deterministic independent output ownership, rejected invalid input, and
checked disposal behavior. Its authenticated library SHA-256 is
`9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604`; the mixed-Q4_K
model SHA-256 is
`549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b`.
The optional native case is a substantive pass in this run. It does not establish
new end-to-end model-quality or intended-device latency measurements.

Python controls ran in the recovered environment containing ONNX and ONNX Runtime.
The tiny real quantizer test passed and verified preservation of both output-head
matrices. All 113 selected Python IDs succeeded, with no optional skip. Python,
NumPy, ONNX and supporting dependency input hashes are recorded before and after.

## Evidence verification

The runner reports unchanged source, dependency, runtime, workspace, system/fixture,
and harness maps, and successful restoration of its temporary analyzer package
configuration. A separate event-audit script reparses the raw JSON event streams,
checks raw and compressed log hashes, verifies that every started test ID completed
exactly once, and compares every executed suite path with the planned paths. It
recounts all fresh totals and both private-PDF exclusions. The audit also rereads
all 3,482 non-documentation source files against their recorded hashes, verifies
the frozen commit/tree and clean checkout, and checks the native and converter
case outcomes. Its result is `independent-event-audit.json` with no errors.

The accepted commands started at `2026-11-17T17:57:22.626066+00:00` and completed at
`2026-11-17T18:03:30.936675+00:00`. Individual command timings are in `receipt.json`.

## Preserved failed preflight

The first attempt targeted `60a116d2df566793720bfb4f76d7f6523529bcb2`. All seven
strict-analysis scopes passed, then formatting identified one extra blank line in
`packages/quds_office_engine/test/odt_paragraph_decoration_test.dart`. No tests
started. Its original output, failure receipt and before/after maps are retained.
The separate remote correction `ec5ecbff` removed that blank line, and this complete
qualification reran on the corrected immutable source. The earlier attempt is
neither erased nor counted toward the accepted totals.

The earlier setup-only rehearsals at `7a9702c3` and `b9bfe664` resolved frozen
workspaces and inspected selection plans; they ran no application tests.

## Reproduction

The evidence package includes byte-exact prior runners, the continuation adapter,
Python controls, `prepare_workspace.py`, `run_frozen.py`, and the independent
recount script. `prepare_workspace.py --repository <clone> --source-commit <sha>`
creates a fresh detached worktree and locked external workspace, refusing existing
outputs. `run_frozen.py --source-commit <sha> --output <fresh-output>` launches the
complete plan with the native fixture and ONNX environment required. Supply the
recorded Flutter SDK, cached dependencies, Python environment and pinned native
pack at the paths recorded in the scripts/setup receipts; large runtime/model
binaries are deliberately absent from the Git evidence archive.

No GitHub Actions, workflow, check-run or CI-status endpoint was queried or awaited.
This qualification covers engine, editor, transport, widget and proofing-contract
behavior plus the native fixture/control described above. The AOT service tests use
controlled fixtures/transports; no live external AOT service was queried. Full
CrispCloud application/viewer/export-dialog acceptance, live Zotero or Microsoft
Word interoperability, Wasm acceptance, and broad language-model quality remain
separate scopes. Any separately executed LibreOffice consumer evidence keeps its
own runner and result attribution.
