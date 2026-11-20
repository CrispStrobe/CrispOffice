# Word VBA paragraph spacing controls

Date: 20 November 2026 (Europe/Berlin).

## Scope and incoming work

This continuation starts at `0201b549d0dc3f601c50e36255d557034cb01699`,
the latest head of Word paragraph-spacing PR #263. It includes captured remote
main `5ad4461a93c835479bf67acab63623944b3900a3`, completed cached-Mail
PR #262, the prior Word list-level increment and all captured branch/PR work.
The [incoming audit](incoming-review.md) independently recomputes 25 fork
branch heads, 263 fork PR heads, four upstream branches and four upstream PRs,
including 13 complete-tree historical equivalents and the exact 37-path ODT
continuation. No captured reference is uncovered.

PR #263's final source-preservation correction was not yet on captured main;
its committed record withheld final qualification. The final Word gate here
must cover that incoming custom line-spacing increment as well as the new
paragraph controls. Prior Mail acceptance is inherited evidence; Mail/Flutter
tests are not being rerun as part of this headless Word gate.

Remote checkpoint branch: `codex/word-vba-paragraph-controls-20261120`.
Every checkpoint uses an expected-head, non-forced GitHub ref update and its
complete Git tree is compared with the staged local tree. No GitHub Actions,
workflow-run or status endpoints are queried or awaited.

## New supported behavior

| VBA method on Paragraph or ParagraphFormat | Native action | Result |
| --- | --- | --- |
| `OpenUp` | `docx.paragraphSpaceBefore`, `open` | Set before spacing to 12 points |
| `CloseUp` | `docx.paragraphSpaceBefore`, `close` | Set before spacing to zero |
| `OpenOrCloseUp` | `docx.paragraphSpaceBefore`, `toggle` | Current zero becomes 12 points; current positive becomes zero |

The receiver is evaluated once and the toggle resolves at native execution
time, after earlier edits to the detached document. Both toggles in a sequence
execute. A recording retains the action and resolves its replay target at
replay time. Source compilation remains document-independent and cannot read
live property values. Typed aliases, `ByVal` helpers, named helper arguments,
nested `With`, and supported statement/`Call` forms remain available.

Only the before-spacing attribute group becomes direct formatting, including
same-value writes. Unedited after/line spacing retains its inheritance and
source metadata. Ambiguous/unsupported source is rejected before mutation,
including automatic or line-based before spacing, malformed native twips,
duplicate property packets, markup alternatives, unbalanced fields, unmodeled
numbering/table spacing and ambiguous style identities/inheritance.

Independent review found valid default-style flags `true`/`on` being ignored,
and foreign style/identity/based-on lookalikes influencing the effective
cascade. Narrow native namespace and Boolean handling corrections address
those concrete failures while preserving the original styles part. The exact
supported subset is described in the [Word contract](../../VBA_WORD_MACROS.md#opening-closing-and-toggling-paragraph-spacing).

The actual [word_paragraph_controls.bas](../../../packages/quds_office_engine/example/macros/word_paragraph_controls.bas)
performs ten operations on three existing paragraphs and finishes with
12, zero and 12 points before spacing. Explicit resets make it repeatable.
Incoming [word_line_spacing.bas](../../../packages/quds_office_engine/example/macros/word_line_spacing.bas)
remains part of the portable qualification.

## Current checkpoint status

Implementation and focused development checks are present. Final acceptance is
pending the frozen-source Word/Office regression union, strict whole-engine
analysis, changed-file formatting, both exact BAS examples on VM and compiled
JavaScript, independent review and final remote consistency verification.
Development attempts are separate from final passing totals.

## Primary contracts

- [ParagraphFormat.OpenUp](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.openup)
- [ParagraphFormat.CloseUp](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.closeup)
- [ParagraphFormat.OpenOrCloseUp](https://learn.microsoft.com/office/vba/api/word.paragraphformat.openorcloseup)
- [Paragraphs.OpenUp](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs.openup), whose example selects one paragraph
- [Paragraphs.OpenOrCloseUp](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs.openorcloseup), whose example selects one paragraph
- [SpaceBeforeAuto](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.spacebeforeauto)

These are specification-derived bounded expectations. An installed Microsoft
Word host, general COM execution and complete VBA compatibility are not claimed.
