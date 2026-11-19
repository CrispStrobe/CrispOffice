# VBA procedures and functions — 19 November 2026

The reusable-procedure extension passed **341 focused regression tests**,
strict analysis of the entire engine, three JavaScript compile/execution
checks, formatting, and whitespace verification. All **448 recorded input
hashes** remained unchanged during the combined run. An independent depth
stress check also passed on the Dart VM and JavaScript.

## Source and remote reconciliation

- Initial main: `81ae98688860599f118748afca19bdb2ec45da37`.
- Tested source: `24eee8145f4edb19a33a95156a7e0a94093a8f75`.
- Tested tree: `22e35b3de48354891716428b5336aeb49c8c6217`.
- The prior macro/MCP PR #201 and Excel VBA PR #202 code were already in main.
  The stale stacked PR #202 was closed as already integrated; no source was
  removed. GitHub refused to retarget it because it has no new commits versus
  main.
- The [initial remote audit](remote-audit.json) inventories all then-current
  branches and verifies the merged or superseded equivalents of older tips.
- A concurrently published language-ID smoke-test fix,
  `ff71fa44c693ee2a30fb0372eac206af257c8477`, was reconciled before this work.
  Its single assertion now follows `identifier.topK`, whose implementation
  already defaults to 5. Newer main product code was retained.
- The [final refresh](final-refresh.json) found draft PR #205 preparing mail
  portability work. At captured head `de8ab2e93cc5f2139e89ba72d117bf9b18ba4cae`,
  its source tree exactly matches the integration checkpoint already included
  here; it contains no new mail implementation. That active draft was retained
  for its own implementation instead of marking its preparation merge complete.

| Remote checkpoint | Purpose |
| --- | --- |
| `f0ce86842452ee7397afcf21b93c73e126d7d07e` | Reconcile the latest language-ID contribution on current main |
| `9b48009fae8d5325db9fc9ba05cdb4e90db840f5` | Save compiler, tests, procedural report, documentation, and initial audit |
| `24eee8145f4edb19a33a95156a7e0a94093a8f75` | Reject ambiguous line labels and save its regression tests |

Each checkpoint was published through the GitHub connector with an expected
prior branch head. Each remote tree was checked against the staged local Git
tree, and original merge ancestry was retained. GitHub Actions were not
awaited; the user requested local validation because the hosted queue is
starved. Checkpoint commits use `[skip ci]`.

## Environment

[Environment and setup](environment.json) records the pinned Dart **3.13.7**
SDK, corresponding to Flutter **3.47.8**, and all resolved dependency versions.
The reduced workspace contains the engine, legacy parser, and engine example,
using copied manifests and live source links. Tracked dependency manifests and
lockfiles did not change. Dependencies include `test` 1.33.0 and `analyzer`
14.7.0, matching the preceding VBA acceptance environment.

## Combined acceptance

The [machine receipt](receipt.json) contains exact argument vectors, working
directories, exit codes, durations, input hashes, and log hashes. The test count
is from one final combined run, not a sum of repeated development runs.

| Gate | Result | Evidence |
| --- | --- | --- |
| Entire engine `dart analyze --fatal-infos` | Passed | [Analysis](analysis.log) |
| Combined macro and command regressions | 341 passed; no failures or skips | [Regressions](regressions.log) |
| Existing native macro JavaScript program | Compiled and executed | [Compile](web_smoke_compile.log), [run](web_smoke_run.log) |
| Existing Excel VBA JavaScript program | Compiled and executed | [Compile](web_vba_smoke_compile.log), [run](web_vba_smoke_run.log) |
| New procedure JavaScript program | Compiled and executed | [Compile](web_vba_procedures_smoke_compile.log), [run](web_vba_procedures_smoke_run.log) |
| Changed Dart formatting | No changes required | [Formatting](format.log) |
| Diff whitespace | Passed | [Whitespace](whitespace.log) |
| Input stability during acceptance | All 448 hashes unchanged | [Receipt](receipt.json) |

The 341 tests retain the previous **286-test** selection and add **26 procedure
tests**, **19 independent boundary tests**, and **10 integration tests**.
The workflow's test list and all three portable checks are recorded in
[Office macros and MCP](../../../.github/workflows/office-macros.yml).

After acceptance, the only edit to a hashed input clarifies in the dialect
guide that the string limit is per string, while work, operation count, and
encoded bytes are aggregate budgets. No implementation or test source changed.
The [publication check](publication-check.json) records that distinction and
verifies the accepted implementation hashes before publication.

## Behavior verified

- Forward and case-insensitive calls; `Call` and bare positional invocation;
  scalar and object arguments; nested functions; typed/default return values;
  and intentionally discarded function results.
- Explicit `ByVal`, fresh local variables and constants, separate function
  result slots, and isolation of caller object context and active loop counters.
- Once-only, left-to-right argument evaluation, including functions that emit
  document operations.
- `Exit Sub`, `Exit Function`, and innermost `Exit For` through nested `If` and
  `With`, including preservation of an exiting loop's current counter.
- Full source checking in inactive branches, unused procedures, and statements
  following an exit. Unknown procedures, incompatible argument counts/types,
  unsupported argument modes, name collisions, and ambiguous line labels fail
  explicitly.
- Exact 16/17 argument and 32/33 frame boundaries; unused recursive call graphs;
  shared work, operation, and encoded-output bounds across helper invocations.
- Real CLI subprocess compilation, detached validation, native-plan replay,
  custom entry selection, MCP compile/validate/run, and structured diagnostics.
- Host read-only and allowlist restrictions, runtime step limits, serialized
  workbook results, and exact-byte rollback after a later helper targets a
  nonexistent worksheet. Existing output files survive source and run failures.

The [procedural report](../../../packages/quds_office_engine/example/macros/procedural_report.bas)
uses reusable heading and row helpers plus nested price/discount functions.
It produces **46 ordinary native operations**, six synthetic item rows, and a
worksheet-calculated net total of **2,117.50**. The integration tests compare
direct BAS execution with execution of the saved native JSON plan.

The new JavaScript check produces `A3 = 42`, preserves the caller's value at
`B1 = 21`, retains the exiting loop counter at `B2 = 4`, and calculates
`B3 = 126`. It also verifies recursion refusal, a shared compilation work
budget, numeric bounds, unchanged bytes after validation and a late failure,
and successful MCP playback ending at revision 2.

## Independent depth interaction check

The separate [stress program](stress/procedure_depth.dart) reaches **32 active
procedure frames** in three scenarios: 50 unary operators per expression,
20 nested `If`/`With` blocks per procedure, and both together. Every scenario
emits one cell write with value `1` on the VM and after JavaScript compilation;
none produces a stack overflow or unstructured error.

The [stress receipt](stress/receipt.json) records the commands and compiler
hash. [VM output](stress/vm.stdout.log), [JavaScript compilation](stress/js_compile.stdout.log),
and [Node output](stress/js_run.stdout.log) are retained with their stderr logs.

## Scope

This qualifies the headless engine paths changed here. It does not claim a full
repository or Flutter editor test run, arbitrary VBA compatibility, or a native
Microsoft Office interoperability run. The CLD3 native library was not rebuilt
for the test-only language-ID reconciliation. No production macro runtime,
permission policy, or document publication code changed.

The [dialect guide](../../VBA_MACROS.md) describes strict scalar types,
document-independent source evaluation, unsupported constructs, and bounded
calls. Embedded VBA projects remain inert and preserved; compiled procedure
calls still emit the existing spreadsheet operations and use the shared atomic
runtime. Live workbook reads, `ByRef`, recursion, cross-module calls, events,
COM/ActiveX, Word/PowerPoint VBA frontends, ribbon controls, and editor undo
integration remain outside this increment.
