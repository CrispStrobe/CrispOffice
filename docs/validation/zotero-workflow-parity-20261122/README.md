# Zotero quoted research-note continuation — 22 November 2026

## Delivered behavior

Native Add Note and Add Annotation now accept Zotero block quotations, which
previously caused the entire research note to be refused. The implementation
preserves quotation paragraphs, nested quotes, supported headings and lists,
inline pictures, rich text, hyperlinks and active citation placeholders.

Each quote level adds **18 pt of left indentation**, with a maximum of eight
levels. Lists retain their additional indentation and hanging markers; headings
retain their heading properties. Quotes in table cells retain those owners,
including merged-cell paragraph remapping. Structured insertion prevents quote
formatting from leaking into unselected prefix/suffix prose.

Body text, authored footnotes/endnotes and supported table-cell selections use
the existing detached transaction. Citation formatting and preferences publish
only after completion and source validation. One undo restores original text,
formatting, fields and selection direction. DOCX saves retain active citations
and native quote indentation.

## Source contract and boundaries

The pinned [Zotero note-editor schema](https://github.com/zotero/note-editor/blob/bdf61e0c275e483c3068ce4fcb86b44691b22afc/src/core/schema/nodes.js)
exports blockquote containers with block children. Zotero's
[note export](https://github.com/zotero/zotero/blob/5fa1cdac02a94475bab5672e60e36454905c7aab/chrome/content/zotero/xpcom/data/notes.js)
and [native integration](https://github.com/zotero/zotero/blob/5fa1cdac02a94475bab5672e60e36454905c7aab/chrome/content/zotero/xpcom/integration.js)
preserve this structure before `Document.insertText`. Quds now maps it to native
paragraph indentation. The note editor's stylesheet is not exported; this
mapping does not reproduce its blue border or exact surrounding spacing.

The following remain explicit refusals: quotes inside list items, tables inside
quotes, direct inline-only quote content, arbitrary quote layout CSS and more
than eight quote levels. Canonical `dir`/`data-indent` paragraph attributes and
inline foreground/highlight colors retain their existing separate limitations.
The existing empty-note guard remains; picture-only notes and empty tables
retain their earlier support.

Native quoted lists are supported and survive DOCX. The existing editable ODT
continued-list boundary remains: an independent mixed quoted-list probe exports
but native reimport refuses `style:list-level-properties`. This failed route is
kept separate from the passing quote-only ODT fixtures. Installed Zotero,
Microsoft Word and supported-release LibreOffice plugin acceptance are still
required before declaring complete application parity.

## Intake and remote preservation

Work began at remote main `bbc4f82c7562e1004c59804b30a5baafcf53e4d1`.
The intake fetched all fork branches, all **375 PR heads** and the **four
upstream branches**, and inspected the 100 most recently updated PRs plus an
explicit open-PR query. No PR was open. The newer Word table-navigation branch
was incorporated through `4eca268cfaab0a765816cd4f0bbadd7b414bfa30`, retaining its
original ancestry. All 41 captured refs (including the new checkpoint branch)
and all 100 recent PR heads are ancestors of the integrated checkpoint.
The exact snapshot is [intake.json](intake.json).

Remote checkpoints on `codex/zotero-workflow-parity-20261122`:

| Checkpoint | Commit |
| --- | --- |
| Integrated recent Word navigation and existing main | `0fda534bc517556f8cf159f0a400496783a60527` |
| Quote parser, native insertion and 35 new engine/editor tests | `e3f6b4e74241f805531156e0f1308041813c4f70` |

The implementation checkpoint has tree
`6f16fa1faf934e33138e354ff295902d9edf137c`, verified against the immutable local
snapshot before advancing the remote branch. Checkpoints use expected-head,
forward-only updates. No branch is force-pushed or deleted.

GitHub Actions were neither queried nor awaited. Local checks qualify this
increment; repository protection settings were not changed.

The final fetch found published Word PR #376, main
`1efcd62b9386da473bc5884834955ab2cdcd10a2` and its topic head
`26370962b40dc761f17f5f7038a628f06d5189f8`. This late delta contains six Word
documentation/evidence files and no executable changes. The integration keeps
that main ancestry and all of its original validation records. All product,
test and dependency paths still match the Zotero implementation checkpoint;
the incoming Word author's additional checks retain their own attribution and
are not added to this report. [Publication intake](publication.json) captures
the final refs and source-continuity checks.

## Local validation

The runtime is the repository-pinned **Flutter 3.47.8 / Dart 3.13.7**. The official
SDK archive and 204 dependency archives passed SHA-256 verification. Offline
resolution enforced the lockfile; tracked manifests and locks stayed unchanged.

| Accepted cohort | Suites | Passing cases | Source |
| --- | ---: | ---: | --- |
| Zotero engine note/parser/session regressions | 8 | 341 | Quote implementation retained at `e3f6b4e7` |
| Editor controllers and Notes pane | 9 | 348 | `e3f6b4e7` |
| Studio transport, shortcuts and ODT export | 3 | 45 | `e3f6b4e7` |
| Incoming Word navigation/compiler/conformance/CLI | 4 | 205 | Integrated intake `0fda534b` |

The Zotero cohorts contain **734 passing cases**, including **35 new cases**.
The incoming Word cohort contains **205 passing cases** on the earlier
integrated intake checkpoint, before the quote-only source extension. All
accepted reporter streams have zero failures, errors, skips or unfinished
cases. Earlier focused runs overlap with these cohorts and are not added.
All four changed/new Dart files pass fatal-info analysis and read-only
formatting. Editor/Studio qualification verifies 1,537 repository inputs,
6,179 dependency files and seven runtime/configuration inputs unchanged across
execution. Incoming Word qualification retains its separate 433-input receipt.

The engine cohort covers the 19 new quote cases and existing Add Note, table,
nested-table, research-target, cell-range and image behavior. Editor coverage
includes both insertion commands in body, footnote, endnote and table-cell
destinations, staged publication, backward selection recovery, undo/redo, stale
targets, unsupported-content refusal and repeated DOCX saves. Studio coverage
checks transport, shortcut dispatch and editable ODT export. The incoming Word
navigation/compiler, conformance, native integration and CLI suites are checked
separately from Zotero behavior.

Independent review reproduced an extra blank paragraph after an empty quoted
heading. The fix is covered in body and table-cell contexts and verified after
DOCX reopening. Additional probes preserve emoji/image/citation offsets,
adjacent quote scopes, list continuations and vertical-merge ownership.

The [qualification summary](qualification.json) records commands, source hashes,
test counts and converter results. The [evidence archive](evidence.tar.xz)
retains raw reporters, independent probes, fixtures and runtime receipts; its
[per-member index](evidence-index.json) records lengths and SHA-256 values,
independently checked after packaging. Historical counts from earlier Zotero
milestones are not added to this increment.

The earlier engine run executed the authored working-tree implementation later
preserved at `e3f6b4e7`; it did not capture its own before/after input manifest.
Its raw reporter and exact command are retained. The separately captured
editor/Studio manifests verify the published implementation's input continuity;
they are not represented as contemporaneous engine-run manifests.

## Actual LibreOffice conversion findings

Converter: **LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.

Three primary fixtures exercise quoted body text, an authored footnote and a
table cell, with two active citations in each. Their original editable ODT
files pass native import and DOCX reopening. Two actual LibreOffice saves of
each file preserve the quotation text, exact 18/36 pt indentation, full field
metadata/order, ordinary hyperlink target and native story ownership, as
verified independently from the saved XML.

However, all six converted primary files are **refused by Quds' reader** because
LibreOffice adds distinct visited/unvisited text hyperlink styles. The existing
reader deliberately guards that unrepresented formatting distinction. These
files and their failed import logs are retained; successful conversion alone
is not reported as successful application reopening.

One separately named **no-ordinary-link body control**, also with two active
citations, passes both actual LibreOffice saves, native ODT imports and DOCX
reopening with unchanged assertions for text, quote indents, bold/italic runs,
field metadata/order and preferences. It contains no ordinary text hyperlink
or continued list. It does not replace the primary fixtures or qualify their
failed route.

## Next parity steps

1. Qualify actual Zotero pickers, refresh, bibliography editing and style
   changes against identified installed Word/LibreOffice releases and saved
   files. File conversion and controlled HTTP callbacks do not replace this.
2. Extend canonical paragraph direction and indentation, then inline note
   colors, with consistent native rendering and DOCX/ODT persistence.
3. Resolve the existing continued-list ODT route before widening its claim to
   mixed quoted research lists, and represent visited/unvisited text-link
   styles before accepting those Writer-normalized files. Retain failed
   fixtures as regression inputs.
4. Extend quote/list/table structural combinations only after their paragraph
   ownership and geometry are represented explicitly.

The [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) retains the
broader table, image, transfer and release-host acceptance boundaries.
