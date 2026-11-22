# Word VBA cell paragraphs — local qualification

## Intake and persistence

The 22 November 2026 intake started from remote `main`
`a5b4eb7d329b0700768b1fc72bb63cf58a9f5cd6`. All 23 other observed remote
branch heads were ancestors of that commit, and GitHub reported no open pull
requests. The recent Word, Mail and Zotero changes were already integrated.
No unmerged branch was discarded or replaced.

Work is checkpointed incrementally to
`codex/word-vba-compatibility-20261122`. The requested final target is remote
`main`. GitHub Actions are not an acceptance dependency for this change;
qualification runs locally and records actual results here.

## Scope

Expose the existing ordinary paragraph in an explicitly selected table cell
through `Cell.Range.Paragraphs(1)` and `Cell.Range.Paragraphs.Item(1)`, preserving
table, row and column identity through typed aliases, nested `With` and `ByVal`
helpers. Enable the existing bounded paragraph Style and background Shading
contracts on this selected paragraph, alongside its existing text formatting.

The supported native target remains one ordinary paragraph in a direct,
rectangular, unmerged main-story table. Paragraph styles and shading are
distinct from cell/table formatting. Live reads, collection enumeration,
arbitrary text subranges, multiple cell paragraphs, insertion, list operations
and embedded project execution are separate work.

## Evidence status

Implementation and local qualification are in progress. This intake checkpoint
does not claim tests have run, Microsoft Office differential qualification, or
a completed merge.

## Primary contracts

- [Range.Paragraphs](https://learn.microsoft.com/en-us/office/vba/api/word.range.paragraphs)
- [Paragraphs.Item](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs.item)
- [Paragraph.Style](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.style)
- [Paragraph.Range](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.range)
- [Paragraph.Shading](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.shading)

These references specify Microsoft APIs. Quds' single-paragraph selectors,
supported style/color subsets and resource limits are explicit dialect
restrictions, not results observed from an installed Microsoft Office host.
