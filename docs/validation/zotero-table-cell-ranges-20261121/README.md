# Zotero research-content replacement within a table cell

## Scope and starting point

This increment extends Add Note and Add Annotation from ordinary main-flow
paragraph ranges to consecutive ordinary paragraphs owned by one table cell.
The goal is to preserve the native cell and surrounding content, active citation
fields, rich paragraph formatting, atomic publication and one undo/redo action.
Cross-cell ranges and incoming nested-table payloads remain separate work.

Implementation is complete; the broad local qualification is in progress.
The initial reconciliation checkpoint was saved as
`674ce9701e185971388fc2e517d305689ccba471` before the implementation checkpoint.
No installed-application acceptance is implied by the local checks.

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

## Implemented behavior and focused checks

The session resolves an exclusively owned consecutive range within one real
cell block list. Existing nested-table ancestry and merged originating cells
are supported; continuation cells, control/drawing ancestors, aliases,
cross-cell ranges and incoming table payloads are refused. It pins the exact
section/note and table/row/cell/container identities at transaction creation and
rechecks them before staging and applying the result.

Ordinary text, headings, lists, supported pictures and active citations remain
inside the existing cell. Surrounding paragraphs, unselected native citation
packets, cell properties and neighbor cells survive. The controller publishes
one undo/redo step and restores the original selection direction on undo.
Raw engine sessions support body and authored-note cells; the standard Notes
pane's UI boundary is unchanged.

Independent development probes found a covariant `List<WmlParagraph>` insertion
failure for rich headings/lists. Inserting each actual block into the existing
owner fixes that valid-model case. New engine and controller regressions cover
the behavior and retained history/serialization.

The focused engine run completed 121 cases with zero failures or skips: 62 new
cell-range cases and 59 existing paragraph-range cases. The complete affected
controller suite also passes, including direct Add Note/Add Annotation dialog
completion/cancellation. These development checks precede the final source-bound
regression receipt and are not added to its eventual totals.

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
