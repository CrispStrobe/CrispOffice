# Word VBA table-cell formatting qualification

## Scope

This continuation enables `Cell.Range.Font` and `Cell.Range.ParagraphFormat`
through the bounded Word VBA compiler, including paragraph spacing controls
and tab stops. Cell identity is preserved through aliases, `With`, loops and
`ByVal` helpers. The existing `Cell.Range.Text` operation is unchanged.

Native formatting uses the explicit `tableCell` story and the same direct-table,
ownership, source-fidelity and protection checks as cell text. Font changes are
prepared on detached runs before publication, including when a public in-memory
model shares run-property objects or import maps with unselected text.

The supported target is one ordinary paragraph in an existing, rectangular,
unmerged main-story table. Font changes apply to current nonempty ordinary text,
not paragraph/end-cell marks or future insertion formatting. Paragraph formatting
can target an empty cell. Reads, arbitrary ranges, rich/merged/nested-cell
semantics, and embedded VBA execution remain outside this contract.

## Integration intake

The initial remote `main` was
`c522851d165b395a7f60422a1be969dffc39c9ff`. All 17 non-main branch tips were
already ancestors of that commit, and there were no open PRs. The exact initial
branch tips are preserved in [intake.json](intake.json). Work is checkpointed
on `codex/word-vba-cell-formatting-20261122` with ordinary, non-forced ref updates.

GitHub Actions is not used as a waiting gate. Checkpoint messages include
`[skip ci]`; no workflow or branch-protection settings are changed.

## Local validation

Local qualification completed against saved source checkpoints with the
official Dart 3.14.1 Linux x64 SDK. Its archive checksum was verified against
the official published SHA-256. The isolated validation workspace contains
the engine, legacy DOC parser and pure-Dart engine example from the same commit.
Package source and package manifests stay unchanged; only the temporary root
workspace excludes unrelated Flutter packages. Hosted dependency versions are
retained from the repository lockfile. Tracked editor fonts are supplied for
the native layout tests that need them.

| Check | Result |
| --- | --- |
| Baseline macro/VBA suites at `c522851d` | 6,352 cases across 121 files passed after supplying the required tracked font fixtures |
| Final macro/VBA coverage | 6,491 cases across 124 files passed, combining the broad run with the corrected integration-suite rerun described below |
| Separate native Word operation regressions | 123 cases across 5 files passed |
| Changed/new Dart files | Strict analysis of all 10 files passed with `--fatal-infos` |
| Actual BAS on Dart VM and compiled JavaScript/Node | Both passed all assertions; structured results agree |
| Actual BAS through CLI | Compile, validate and run passed for 52 native operations; output formatting and opaque payloads verified |
| CLI late-failure behavior | A missing cell at step index 2 failed without changing the input or an existing output file |

Final distinct coverage is **6,614 cases across 129 files**. The three added
test files contribute 84 compiler cases, 31 native selector/isolation cases
and 24 integration cases. Repeated runs are not added to those counts.

The broad 124-file run at `75e067c9749de0f1acaf7214d28c61ace6b4f411`
reported 6,485 passes and six failures in the new integration test's preservation
expectations. Those expectations incorrectly treated normal save timestamps
and an XML declaration as immutable payload changes. At
`ca4d7ea9d8e4850f3d5d451724c87e1e45cca3cd`, the complete corrected
24-case integration file passed. The 6,491-case result uses the broad run's
6,467 cases outside that file plus the corrected 24-case rerun; it does not
describe the earlier broad command as having exited successfully. Production
source is identical between those two commits.

The five separate native suites cover operation atomicity, vocabulary,
structure and table-grid addressing. The compiler tests additionally prove
cell-specific alias/helper identity, line-spacing pairing and explicit refusal
of unsupported direct cell-range APIs. Integration tests cover DOCX and DOCM,
MCP, preview without publication, recording/replay, inherited table styles,
mixed runs, empty cells, structural/protection refusals and whole-run rollback.

The real report is loaded from the committed BAS for VM and JavaScript runs.
Both execute 52 operations, replay 52 recorded operations and perform two
additional save/reopen cycles. JSON comparison distinguishes booleans from
numbers and compares numeric values across integer/double representations.
Raw stdout differs for equivalent values such as `14.0` and `14`; byte-identical
VM/JavaScript diagnostic output is not claimed.

Preservation checks materialize lazy OPC parts before comparing their bytes.
Opaque VBA and custom XML bytes stay exact. XML comparisons retain expanded
names, substantive attributes and ordered children. Core metadata comparison
permits only a valid updated `dcterms:modified` text value. The fixture first
performs an ordinary control save to account for the serializer's preexisting
materialization of an inherited second-section header. These controls are
explicit in the tests; they do not hide changes to document content or other
metadata.

See [validation.json](validation.json) for exact commands, runtime provenance,
source identities, individual exit codes and evidence paths. Intermediate
fixture/harness failures remain recorded separately from the final result.
This record does not claim installed Microsoft Word differential execution,
Flutter UI validation or complete VBA compatibility.

## Concurrent main integration

Remote main advanced to `bcc55cb6e86e796056e2d75c3fdca50857dbf6e7`
with Mail PR #354 during qualification. Merge checkpoint
`81d6023b30def58fda5be2279445a08b925d53a5` has that commit and
`ca4d7ea9d8e4850f3d5d451724c87e1e45cca3cd` as real parents. The
merge was conflict-free. Its incoming changes are limited to Mail source,
Mail documentation and Studio Mail source/tests. Engine, legacy parser,
font fixtures and root manifest/lock/config blobs are unchanged from the
qualified source, so those test results remain applicable to the merged branch.

## Reproducible entry points

- Compiler contract: `test/office_vba_word_cell_formatting_test.dart`.
- Native selectors, detached property editing and malformed ownership:
  `test/office_macro_word_cell_formatting_test.dart`.
- DOCX/DOCM transactions, persistence, inherited formatting and refusal paths:
  `test/office_vba_word_cell_formatting_integration_test.dart`.
- Actual BAS report: `example/macros/word_table_formatting.bas`.
- VM/JavaScript example check:
  `tool/macros/web_vba_word_cell_formatting_smoke.dart`.

All paths above are relative to `packages/quds_office_engine`. The portable
check takes the actual BAS content through `WORD_CELL_FORMAT_BAS_BASE64`,
allowing VM and JavaScript to execute the same committed source without
filesystem access in the compiled program.

See the [supported cell-formatting contract](../../vba-word-macros-details.md#formatting-existing-table-cells)
for the exact API and structural limits.
