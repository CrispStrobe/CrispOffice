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

## Qualification status

Implementation checkpoint. Focused compiler/native checks, independent
conformance, a complete BAS example, CLI/MCP transaction tests, portable
VM/JavaScript execution and final source-bound receipts are being completed.
No final passing count is claimed by this checkpoint.

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
