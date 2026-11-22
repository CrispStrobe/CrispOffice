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

Qualification is being completed against saved source checkpoints with the
official Dart 3.14.1 Linux x64 SDK. Its archive checksum was verified against
the official published SHA-256. The isolated validation workspace contains
the engine, legacy DOC parser and pure-Dart engine example from the same commit.
Package source and package manifests stay unchanged; only the temporary root
workspace excludes unrelated Flutter packages. Hosted dependency versions are
retained from the repository lockfile. Tracked editor fonts are supplied for
the native layout tests that need them.

The final receipt will distinguish the initial baseline, intermediate failures
and corrected source qualification. This record does not claim installed
Microsoft Word differential execution, Flutter UI validation or complete VBA
compatibility.

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
