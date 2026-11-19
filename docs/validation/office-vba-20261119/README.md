# Excel VBA subset acceptance — 19 November 2026

The `vba-excel` extension passed **286 focused regression tests**, strict
analysis of the entire engine, native and VBA JavaScript execution checks,
formatting, and diff whitespace verification. The recorded source hashes
remained unchanged throughout this combined run.

## Source and environment

- Base: `3c1764f5ff8bf9f89e090ef4e04e3142c4ccf90a`, the shared macro/MCP
  implementation in PR #201.
- SDK: Dart **3.13.7**, matching the repository's Flutter **3.47.8** pin.
- Dependency resolution used a reduced engine + legacy parser + engine-example
  workspace with copied manifests and live source links. No tracked dependency
  manifests or lockfiles changed.
- The [machine receipt](receipt.json) records the exact commands, source SHA-256
  hashes, exit codes, durations, SDK identity, and resolved dependency versions.
  This run resolved `test` 1.33.0 and `analyzer` 14.7.0; these differ from the
  preceding macro acceptance record and are recorded explicitly.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| Entire engine `dart analyze --fatal-infos` | Passed | [Analyzer log](analysis.stdout.log) |
| Combined focused native regressions | 286 passed | [Test log](regressions.stdout.log) |
| Existing portable macro API compiled to JavaScript | Passed | [Compile log](web_smoke_compile.stdout.log) |
| Existing portable macro API executed under Node | Passed | [Run log](web_smoke_run.stdout.log) |
| VBA compiler and runtime compiled to JavaScript | Passed | [Compile log](web_vba_smoke_compile.stdout.log) |
| Compiled VBA path executed under Node | Passed | [Run log](web_vba_smoke_run.stdout.log) |
| All changed Dart formatting | No changes required | [Format log](format.stdout.log) |
| Diff whitespace and source stability | Passed | [Receipt](receipt.json) |

The count is from one final combined test run, not a sum of repeated development
runs. It retains the preceding 217-test macro/command selection and adds 55
compiler unit tests, 12 integration tests, and two shared worksheet-selector
tests.

## What was exercised

- Source lexing, case-insensitive entry selection, declarations, strict scalar
  and object bindings, nested `With`, inclusive positive/negative loops,
  conditions, arithmetic, concatenation, Boolean precedence, and signed zero.
- Full syntax/object-shape checking of inactive branches and unused procedures;
  unsupported calls, document reads, default members, and active-selection
  references fail explicitly.
- Token, depth, statement, variable, work, string, emitted-operation, and
  aggregate-JSON bounds. Empty loops consume work, and huge rectangles are
  rejected before expansion. Large integer products cannot wrap into accepted
  values on the native VM.
- One-based VBA indexes and named worksheets, including shared direct/native/
  MCP behavior, rename/reorder behavior, and refusal of ambiguous names.
- Real serialized workbook values, formulas, styles, colors, and clearing;
  detached validation; exact-byte rollback; read-only policy, allowlists, and
  execution-step limits.
- Default MCP dialect discovery, compilation, structured source diagnostics,
  validation, and playback. Existing actual MCP subprocess tests remain in
  the combined selection.
- Actual `.bas` CLI compilation, validation, playback, custom entry points,
  incompatible-document rejection, and preservation of existing outputs after
  source or execution errors.
- Preservation of opaque VBA bytes and workbook package metadata during an
  explicitly invoked source macro. Embedded projects are never executed.

The committed monthly example expands to **76 operations**. The test verifies
revenue **153,000**, cost **85,200**, and net **67,800**, along with heading
formatting and the twelfth month's label. These are synthetic demonstration
values.

The VBA JavaScript check verifies `A3 = 42`, `B1 = 84`, the RGB fill `0A141E`,
unchanged bytes after validation and a late failure, and a subsequent MCP
compile/run ending at revision 2. It also checks numeric-limit rejection,
Boolean precedence, and signed-zero comparison after compilation to JavaScript.
The original JavaScript check independently retains `A1 = 42`, `A2 = 84`, and
late-failure byte preservation.

## Reproduction and scope

The [Office macros workflow](../../../.github/workflows/office-macros.yml)
contains the pinned SDK setup, the exact combined test selection, whole-engine
analysis, and both JavaScript compile/run commands for a complete checkout.

This is focused local acceptance. It does not claim that the full repository
test suite, Flutter editor integration, native Microsoft Office interoperability,
or general VBA execution was qualified. The [VBA dialect guide](../../VBA_MACROS.md)
documents binary64 numeric semantics, strict type boundaries, supported source,
and limits; the [macro guide](../../MACROS.md) documents document admission and
the shared transaction model. Remote CI results are separate from this record.
