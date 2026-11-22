# Word VBA cell prefixes and portable text constants — 22 November 2026

## Reconciled intake and durability

Started from remote main `ec09fdccf95eb3072b4cfe4da3608f8d9b13eb75`.
The [intake](intake.json) records all 27 fork tips, all four upstream tips,
and the latest 100 updated PRs. All PR heads and all upstream tips were already
ancestors of main. The one outstanding fork checkpoint,
`762acfabdf32624154bc27c311b774e17d8ea243`, contains only completed Zotero
qualification evidence and changelog entries. Merge `ee3ba4f6a7d5f2a9d73926d95d41e16580bf97c0`
preserves that history and its expanded validation README.

Remote checkpoints use `codex/word-vba-continuation-20261122`. Changes are
saved incrementally with verified Git trees and non-forced expected-head
updates. The final target is main. GitHub Actions are not queried or awaited;
local tests and analysis qualify the implementation.

| Remote checkpoint | Purpose |
| --- | --- |
| `ee3ba4f6a7d5f2a9d73926d95d41e16580bf97c0` | Reconcile the initial outstanding Zotero evidence history before implementation. |
| `118ac7c391a3a378886c9fa0c87f20224259f967` | Compiler, native operation, independent corpus and regression tests. |
| `e2639923376de79f7abfa9bdfba8746fe297cadb` | Complete BAS, portable runner, CLI/MCP coverage, documentation and future workflow coverage. |
| `806525fdb06d501fff09d4fb6b12ee95ef6cf4b2` | Integrate completed main at `b13a170c` (PR #364) and correct integration assertions. |
| `258ae2a5d73bccd293b4b423918fc3d7646e9bc4` | Final source: resolved formatter output for two new tests and a roadmap clarification. |

The [late intake](final-intake.json) records 31 fetched fork refs, the unchanged
four upstream heads and an empty open-PR query. The only tips outside the Word
checkpoint are the newer Mail membership and Zotero note-numbering branches.
Both explicitly retain qualification-in-progress status in their own validation
READMEs. Those active branches remain intact; their unfinished changes are not
represented as accepted Word work. The completed main refresh changes only two
Zotero evidence paths relative to the initial reconciled baseline.

## Implementation scope

- `Cell.Range.InsertBefore` and the selected ordinary paragraph's
  `Range.InsertBefore` prefix current cell text while preserving existing
  characters, run formatting, paragraph/cell markers and native metadata.
- Required `Text:=` named arguments work case-insensitively on existing
  body/header/footer paragraph ranges and on the new cell selectors.
- Shared source String constants `vbTab`, `vbCr`, `vbLf`, `vbCrLf`, `vbBack`,
  `vbFormFeed`, `vbVerticalTab` and `vbNullChar` have their fixed VBA UTF-16
  values. Source calculations can use these characters; native Word writes
  still reject structural and invalid XML controls other than tabs.
- The native operation is `docx.tableCellRangeInsertBefore`, with zero-based
  table/row/column and String text. Existing generic replaceText/story admission
  is unchanged. Selected cells still require one ordinary paragraph in a
  supported direct rectangular unmerged main-story table.

The native prefix is constructed on a detached clone with a new initial run.
It does not use global run coalescing, which would discard distinct kerning
or zero-width run metadata in some otherwise supported public models. Empty
prefixes still validate their target and retain normal session publication
semantics. Named arguments do not broaden unrelated member-call contracts.

## Local qualification

The final implementation is qualified at source checkpoint
`258ae2a5d73bccd293b4b423918fc3d7646e9bc4`. The production delta is confined to
four engine automation files. No engine version, dependency lock, workspace
manifest, global run-edit utility or editor/Studio production code changes.

| Check | Observed result |
| --- | --- |
| Broad regression: [154 suites](suites.txt), concurrency 2 | **7,508 passed, one 30-second timeout, zero skipped.** The invocation exits 1; its original failure is retained. |
| Entire affected table-cell integration suite, concurrency 1 | **7 passed, zero failed/skipped**, with the original timeout. The previously timed-out case completes in 102 ms. |
| Five new test files within the broad run | **285 passed**: native 67, compiler 52, shared constants 73, conformance 79 and integration 14. These are included in the broad count. |
| Final integration/corpus gate | **93 passed**, zero failed/skipped. |
| Two tests after formatter-only edits | **146 passed**, zero failed/skipped. |
| Final strict analysis | `dart analyze --fatal-infos lib test tool`: **no issues found**, exit 0. |
| Final resolved formatting and whitespace | **15 Dart files, zero formatting changes**; `git diff --check` passes. |
| Complete BAS on Dart VM and compiled JavaScript/Node | Both execute successfully; semantic and byte-for-byte JSON outputs match. |
| Independent 78-case corpus on VM and JavaScript/Node | Both execute successfully; canonical JSON is byte-identical. |

The one broad-run failure is the existing
`empty replacement, tabs and supplementary Unicode survive reopening` case in
`office_vba_word_table_cells_integration_test.dart`. It reports a timeout rather
than an assertion failure. The entire unchanged seven-case suite passes on its
own with no timeout increase, retry annotation or test skip. This targeted
recheck resolves the observed deadline failure; the broad invocation itself is
not relabeled as a clean pass. Counts above overlap and must not be summed.

The independent corpus contains 34 explicit native plans and 44 exact diagnostic
expectations. Its provenance assertion is the 79th test. New coverage includes
direct/projected/aliased selectors, named `Text:=`, inactive-source refusals,
single evaluation, limits, String constants and invalid native text. Native
checks cover mixed formatting/kerning and empty-run metadata, repeated and
empty prefixes, imported paragraph-mark formatting, protected/sparse/unsupported
content, rollback and save/reopen preservation.

The actual [BAS example](../../../packages/quds_office_engine/example/macros/word_table_prefix.bas)
executes six operations and six recorded/replayed steps. The portable runner
checks DOCM preservation, two additional reopens, paragraph/cell properties,
unrelated package parts, opaque VBA and late rollback. Integration tests also
exercise DOCX, CLI and MCP execution, repeat runs, validate-only behavior,
read-only/tool/step/cancellation policies, schema validation and unchanged
output after compile/native failure.

### Toolchain and exact input binding

Execution used the official **Dart 3.13.7** SDK and **Node v24.22.3**. The SDK
archive's published SHA-256 was verified. All 56 resolved dependency entries
match the repository lockfile's versions, sources and archive hashes. A scratch
workspace reduced only its root workspace membership to the engine, legacy
parser and engine example; tracked package manifests, source, tests and editor
font fixtures were copied byte-for-byte. The original repository manifest and
lock were unchanged.

The strengthened harness serializes synchronization/execution with an exclusive
lock. It hashes source, copied target, package configuration, root manifests,
SDK executables/snapshots and harness inputs before and after each final run.
All final runs, including the broad timeout, pass input-integrity checks with
no source, target or toolchain drift. Node receipts separately bind the runtime,
compiled JavaScript, output and error streams before and after execution.

The broad run and portable gates execute checkpoint `806525fd` inputs. The only
later engine changes are six formatter-generated wrapping edits in two new test
files. Both suites and strict analysis were rerun on the final committed bytes
at `258ae2a5`; production, BAS, corpus and portable-runner bytes are unchanged.
[Qualification bindings](final/qualification.json) compare each executed source
manifest against the committed Git blobs and explicitly list that two-file
formatting difference instead of assigning an inferred HEAD to copied inputs.

### Retained evidence

- [Qualification summary and per-run source binding](final/qualification.json).
- [Committed source index](final/committed-source-index.json.gz): Git blob IDs
  and SHA-256 values for every bound source input.
- [Complete raw evidence](final/raw-evidence.tar.xz): exact commands, stdout,
  stderr, exit codes, before/after manifests, portable comparisons, runtime
  provenance, isolated manifests and harness/coordinator scripts.
- [Archive member hashes](final/archive-manifest.json) and
  [artifact hashes](final/artifacts.json).

The archive retains the earlier unsuccessful development runs as well as the
final gates. They expose the fixes for String-constant default evaluation and
incorrect test expectations; they are not counted as final passing evidence.
Original absolute paths in receipts describe the execution environment. Archive
members retain the corresponding `validation-results/`, `runtime/`,
`isolated-workspace/` and formatting-audit relative paths.

For a normally resolved engine checkout, the broad regression command is:

```bash
cd packages/quds_office_engine
mapfile -t suites < ../../docs/validation/word-vba-cell-prefix-20261122/suites.txt
dart test --concurrency 2 --reporter json "${suites[@]}"
dart analyze --fatal-infos lib test tool
```

The complete portable commands, including exact compile-time BAS/corpus bytes,
are retained in the archive and implemented by the archived coordinator.

## Boundaries

No installed Microsoft Word host is executed. Live document reads, arbitrary
range offsets, InsertAfter, structural line/paragraph insertion, multiple cell
paragraphs, merged/nested tables and embedded VBA execution remain outside this
increment. Host-dependent `vbNewLine` and external-call `vbNullString` retain
their distinct unsupported contracts.

## Primary API references

- [Range.InsertBefore](https://learn.microsoft.com/en-us/office/vba/api/word.range.insertbefore)
- [Cell.Range](https://learn.microsoft.com/en-us/office/vba/api/word.cell.range)
- [Paragraph.Range](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.range)
- [VBA miscellaneous constants](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/miscellaneous-constants)

Microsoft documents the method and characters. Quds' selector/content limits,
boundary formatting and native plans are explicit local contracts, not results
observed in an installed Office host.
