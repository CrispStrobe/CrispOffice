# Zotero nested research tables — 21 November 2026

## Objective and current status

Extend the existing native Add Note / Add Annotation workflow to preserve
bounded tables nested inside research-note cells. This is one implementation
milestone toward Zotero Word/LibreOffice parity. It does not establish complete
plugin parity, native ODT editing, or installed-application interoperability.

Implementation and local qualification are in progress. Final results and exact
source identities will replace this status before publication to main.

## Reconciled starting point

The initial main was `4090feb56f308cd3657c5edd1d045ff1197ff79b`. During intake,
PR #294 landed as `f2025d3275c8b5ac8313f788286b17c657894567`; it is included.
The captured intake covers 49 fork branches, 294 PR heads and four upstream
heads. Of these 347 references, 321 were already ancestors, 24 had freshly
verified historical equivalents, and two contained additional recent work.

Both additional branches were merged with their original ancestry retained:

| Incoming work | Original head | Remote checkpoint |
| --- | --- | --- |
| Studio localization and screenshot polish | `e6a38e2bd7b0bc8a267f4fbd416c7f6bcd96cf2b` | `f3eb60ad795dbfa5938f5dcb28a460dbd96f654c` |
| Word layout and typing performance | `5332c5ff4d3e72dffcd6fa78444dca22787be88e` | `23903dfe7b680cc8df2319f25e3fbf2e5f116b36` |

All four upstream heads are already included. The 15 unique historical proofs
comprise 13 complete-tree equalities and two changed-path equalities; each
replacement is an ancestor. These old branches are not replayed over newer
implementations. `intake.json` records the captured references and proofs.

Incremental checkpoints are retained on
`codex/zotero-parity-20261121-continuation`. Checkpoint publication verifies the
complete Git tree against the local index and updates the remote branch with an
expected-head lease. No force push or history rewrite is used on the remote.
GitHub Actions and check statuses are neither queried nor awaited.

## Implementation contract

- Accept nested tables at ordinary cell block boundaries, to a maximum of eight
  table levels including the outermost table.
- Preserve native table/cell ownership and recursive document order for rich
  paragraphs, supported images, lists and active citation placeholders.
- Validate each table's row/column spans and widths independently. Continue
  counting tables, generated merge cells, images, links and paragraphs across
  the entire note; nesting never resets a resource budget.
- Give a cell ending in a nested table a native trailing paragraph before final
  citation/list index mapping, so its structure is stable through DOCX reopening.
- Retain detached staging, cancellation, stale-target guards and one undo/redo
  transaction in body and authored footnote/endnote targets.
- Keep table-bearing note insertion restricted to main-flow destinations.
  Tables in list items or inline paragraphs, header/footer row groups, custom
  table styling and cross-cell replacement remain outside this milestone.

## Why this milestone

The engine already models, lays out and serializes nested Word tables. Its
Zotero note parser currently refuses them and reconstructs only a single active
table/cell. Extending that parser uses the existing document representation and
transaction model. Native ODT input is a separate, larger subsystem: the
current ODF path extracts text and exports ODT but does not deserialize an ODT
document into the editable Word model.

The parity comparison uses Zotero's own
[Word](https://www.zotero.org/support/word_processor_plugin_usage) and
[LibreOffice](https://www.zotero.org/support/libreoffice_writer_plugin_usage)
workflows. LibreOffice is the current supported OpenOffice-family comparison;
legacy Apache OpenOffice requires separately identified versions and acceptance.
See the [parity roadmap](../../roadmaps/zotero/word-processor-parity.md).

## Local qualification plan

Use pinned Flutter 3.47.8 / Dart 3.13.7 and enforce the committed dependency
lockfile. Exercise the nested parser, native citing session, DOCX persistence,
controller transactions and actual nested-table layout. Regress existing Zotero
commands and incoming layout/notification behavior, plus the incoming
localization/Mail consumers. Preserve raw output and identify the tested source;
do not count repeated or overlapping executions as additional distinct tests.

Installed Zotero, Microsoft Word, LibreOffice and legacy Apache OpenOffice
plugin acceptance remain explicitly separate from these local checks.
