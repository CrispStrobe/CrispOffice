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

This is the initial work checkpoint. Implementation and qualification are in
progress; no new behavior or test result is claimed yet.
