# Zotero research-content replacement within a table cell

## Scope and starting point

This increment extends Add Note and Add Annotation from ordinary main-flow
paragraph ranges to consecutive ordinary paragraphs owned by one table cell.
The goal is to preserve the native cell and surrounding content, active citation
fields, rich paragraph formatting, atomic publication and one undo/redo action.
Cross-cell ranges and incoming nested-table payloads remain separate work.

Implementation and local qualification are in progress. This initial checkpoint
records the completed source intake before feature work; it makes no new
runtime or installed-application acceptance claim.

The starting main is `e2abbcda6d19f932bfbacc85e0dafd41a3c478f8`. The initial
observation was `fcb3ff13537eb31c2cabead033a50723124682c5`; the newer main also
includes PR #285's final two performance documentation files. Its runtime
implementation was already incorporated. The checkpoint branch is
`codex/zotero-parity-20261121-next`.

## Completed incoming-history audit

All 338 captured external heads are accounted for: 46 fork branches, 288 PR
heads and four upstream branches. There are 314 actual ancestors and 24
independently verified historical equivalents, with zero uncovered references.
The checkpoint branch is recorded separately.

The audit recomputes 13 complete tree identities and two exact changed-path
comparisons (37 ODT-continuation paths and three PPTX-integration paths),
including Git modes and object identities. Every accepted replacement is an
ancestor of the target. The full inventory, candidate mappings, proofs and
replay script are retained in `intake/`.

```bash
python3 docs/validation/zotero-table-cell-ranges-20261121/intake/audit_refs.py \
  --repo . --head HEAD \
  --snapshot docs/validation/zotero-table-cell-ranges-20261121/intake/snapshot.json \
  --candidates docs/validation/zotero-table-cell-ranges-20261121/intake/historical-candidates.json \
  --output /tmp/zotero-table-cell-intake.json
```

GitHub Actions and check/status queues are neither queried nor awaited.
Incremental commits are saved to the remote checkpoint branch; final publication
will use locally qualified source and a non-forced merge into remote main.

## Parity decisions

The core native citation, bibliography, preference, refresh, unlink and transfer
workflows already exist. The next useful editing gap is cell-local paragraph
replacement. Direct active ODT input requires a structured ODT reader, reference
mark ownership and preference restoration; the existing ODF text extractor is
not that reader. It remains an explicit roadmap dependency.

The standard Notes pane exposes authored-note main-flow text, not table-cell
editing. Engine coverage for cells in authored footnotes/endnotes must not be
reported as a new Notes-pane editing surface. Actual Word/LibreOffice Zotero
plugin acceptance remains distinct from local protocol and DOCX checks.

See the [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) and
[usage guide](../../zotero-support.md) for the existing workflow contract.
