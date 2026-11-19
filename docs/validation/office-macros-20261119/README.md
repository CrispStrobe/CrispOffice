# Office macros acceptance — 19 November 2026

The macro/MCP implementation passed **217 focused regression tests**, full
engine strict analysis, formatting, and a compiled JavaScript execution check.
The checked source files remained byte-identical across the acceptance checks.

## Source and runtime

- Base: `e00ca1495551ffaf61dd9b3ee7770f8bfde7e897` (`main` at integration).
- The added/changed runtime, tests, examples, command tools, and workflow are
  bound by SHA-256 in [receipt.json](receipt.json). Later evidence-only changes
  do not change these checked source bytes.
- Flutter pin: **3.47.8** from `.fvmrc`; Dart **3.13.7**.
- A reduced workspace resolved the engine, legacy parser, and engine example
  with copied manifests and live source links. No tracked dependency manifest
  or lockfile was changed. The receipt records the resolved dependency versions.
- A newly merged proofing export was reordered alphabetically to retain
  `--fatal-infos` analysis. Its source hash is included.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| Entire engine `dart analyze --fatal-infos` | Passed | [Log](analysis.stdout.log.gz) |
| Focused native regression suite | 217 passed | [Log](regressions.stdout.log.gz) |
| Public API compiled to JavaScript | Passed | [Log](javascript_compile.stdout.log.gz) |
| Compiled code executed under Node | Passed | [Log](javascript_run.stdout.log.gz) |
| All changed Dart source formatting | No changes required | [Log](format.stdout.log.gz) |
| Staged diff whitespace checks | Passed | Exit code in receipt |

The JavaScript check performs a real workbook macro, verifies `A1 = 42` and
`A2 = 84`, confirms revision `1`, then proves that a later failing transaction
preserves the exact prior bytes. It also exercises portable MCP inspection.
This checks the portable runtime; it does not exercise a Flutter browser UI.

## Regression scope

The selected tests include the six new macro/operation suites, the existing
Office step, Word atomicity/vocabulary/structure/grid suites, and existing
macro-package preservation tests. They exercise:

- Native parameter types, literal substitution, version/schema errors,
  immutable recording, whole-plan publication, cancellation, overlapping runs,
  readonly policy, and per-tool allowlists.
- Same-operation behavior through the public catalog, old fidelity entry
  points, native macro runtime, and MCP tools.
- Actual command-line examples for Word, spreadsheets, and presentations;
  actual MCP subprocess initialization, calls, recording, malformed/oversized
  messages, validation, successful persistence, and persistence failure.
- Exact opaque VBA bytes and workbook content type/relationships through
  native macro edits; embedded VBA is never executed.
- Signed/protected input refusal, locked content controls, explicit image
  authority, binary PPTX part preservation, and invalid target rejection.
- Input/output ZIP expansion and entry limits, forged declared sizes,
  duplicate names, large merge/table geometry, formula reference/generator
  limits, LET literal-resolution cases, and preservation of formula caches on
  formatting-only edits.
- Parameter amplification within one call and across calls, byte accounting
  before oversized construction, aggregate compiler output bounds, and
  serialization round-trip at the macro byte ceiling.

The 217 count is the final combined run, not a sum of repeated development
runs. It is a focused suite, not the full repository's test count. The standard
Office fidelity workflow may run broader independent gates on the pull request;
those remote results are separate from this local acceptance record.

## Reproduction

The [Office macros workflow](../../../.github/workflows/office-macros.yml)
contains the SDK setup, exact regression selection, strict analyzer, and
JavaScript compile/execute commands for a complete checkout. The machine receipt
records the actual local commands and package-resolution environment.

The [macro guide](../../MACROS.md) documents usage and boundaries. VBA execution,
COM/ActiveX, event macros, live editor undo/ribbon integration, native Microsoft
Office interoperability, and hard process-level resource isolation are outside
this increment. Macro work limits cover the specified expansion paths and do
not establish a general CPU/memory sandbox.
