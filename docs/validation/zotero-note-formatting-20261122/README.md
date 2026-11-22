# Zotero research-note formatting — 22 November 2026

## Goal and starting state

Continue the native Zotero Word/LibreOffice parity roadmap by preserving the
paragraph direction, indentation, alignment and inline colors that Zotero
exports with research notes. Existing citation fields, detached completion,
selection ownership, undo/redo and DOCX persistence remain acceptance criteria.
Exact supported values and remaining format limits will be recorded with the
completed implementation and local results.

Work starts at remote main `3f3cb8508663dde917e913867908dbfd6c3efcf0`.
All 37 captured fork branch heads, 100 most recently updated PR heads and four
upstream branch heads are ancestors of that commit. No PR was open. A fresh
check also found `codex/word-vba-string-search-20261122`, initially at the same
main commit. The intake audit is retained in `intake.json` and will be refreshed
before final publication to preserve concurrent work.

## Execution plan

1. Preserve an initial checkpoint on `codex/zotero-note-formatting-20261122`.
2. Implement the bounded canonical note-formatting contract from pinned Zotero
   note-editor sources, with focused engine and editor regressions.
3. Run local checks with the repository-pinned Flutter/Dart runtime and locked
   dependencies. Record exact commands, counts and any remaining limitations.
4. Reconcile new remote commits, preserve incremental checkpoints and merge the
   qualified result into remote main without waiting for GitHub Actions.

Installed Zotero, Word and LibreOffice plugin acceptance remains a separate
requirement; controlled protocol tests and file round trips do not establish it.

## Implemented contract

Canonical paragraph/heading `dir`, `data-indent` and `text-align` now map to
native properties. The redundant 40 CSS px compatibility padding is counted
once at 30 pt per level. Explicit alignment is independent of reading order;
absent direction stays automatic. Formatting follows the final paragraph
owners through merged cells and composes after heading/list/quote styles.
Structured insertion protects the unselected surrounding paragraphs.

Opaque exported foreground/background colors use opt-in note parsing, keeping
ordinary CSL formatting unchanged. Arbitrary RGB highlights persist through
native Word run shading. Authored highlights paint opaquely in the canvas,
matching PDF and export semantics. Heading styling preserves explicit colors.

The controller distinguishes authored empty-paragraph direction from its own
automatic language-following state. Native directions survive relayout,
typing, undo/redo and DOCX reopening; ordinary blank paragraphs still follow
the selected interface language until the user sets their direction.

The support details and parity roadmap document the accepted forms and
remaining boundaries. In particular, directional lists, RTL child paragraphs
inside lists, indent levels above seven, alpha/dynamic colors and arbitrary
layout CSS remain guarded. Installed-plugin acceptance is still open.

## Remote checkpoints

| Checkpoint | Commit |
| --- | --- |
| Intake audit and execution plan | `e84fc1d6c872d450dc485f1b981562792fbd082f` |
| Paragraph/color implementation and regression cases | `7b9d50259f9d6bb9b39678ec4afced644e88c38b` |
| Direction lifecycle, exact highlight rendering and support contract | `aac3dda7a052c18f6f5bcc5e84a8d7c8cea8af95` |

The first late intake identified new Word substring-assignment work and an
unfinished Mail Archive checkpoint. The Word head
`19a63d4455540bd797e546ab82ec14db128abea0` passed its four new suites and seven
shared language suites in an independent checkout before integration. Its
original ancestry and author evidence are retained. Final integrated checks
will report their own counts separately from development/isolated runs.

Mail head `9d8758e55` was explicitly marked unfinished and added an enum case
without all downstream switch handling. It remains preserved on its source
branch while a completed successor is checked before publication. The exact
late-ref audit is `late-intake-1.json`; this does not change the initial proof
that all captured starting branches/PRs were already included in main.

Local development checks have exercised the implementation and identified the
empty-paragraph and alignment/direction fixes above. Final integrated source
qualification, actual converter observations and publication reconciliation
are in progress. Their exact results will replace this progress note.
