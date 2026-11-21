# Independent review: Zotero table-cell paragraph ranges

**Accepted; no blocking findings remain in the reviewed scope.** This review
examined the engine ownership resolver, insertion path, existing transaction
guards and the new engine/controller coverage. `review.json` records exact
reviewed file identities and runtime routing.

## Independent execution

All **21 supplemental VM probes passed**, exit 0, with zero stderr. Before/after
hashes of all engine Dart sources, the engine manifest, repository lockfile and
probe program are identical during the accepted run. The package configuration
resolves the engine to the actual repository source through the validation
workspace; the Dart executable and configuration hashes are recorded.

The probes exercise a real nested-cell replacement and DOCX reopening;
replacement of every level of its owner chain before staging and after native
completion; a continuation ancestor; paragraph aliasing through a separate
frame; covariant paragraph-list ownership with rich heading content; and the
existing rejection of incoming tables inside cells. These 21 probes are separate
from the product regression suite totals.

## Findings resolved during review

1. A cell with an explicit `List<WmlParagraph>` accepted the target but rich
   heading/list insertion threw a runtime iterable type error. Inserting each
   supported block individually fixes the covariance mismatch. The accepted
   independent replay passes; engine and controller regressions cover typed
   owners and preservation.
2. Constructor ownership originally captured only the first endpoint. The
   resolver now requires both endpoints, their order and consecutive ordinary
   initial blocks, preventing a previously invalid cross-cell raw session from
   becoming eligible after reparenting that leaves the flat paragraph order
   unchanged.

The original failing probe output and the first green development output are
retained. The latter detected a concurrent source edit and is deliberately not
the accepted source-bound result.

## Source and test assessment

The implementation changes the range-owner resolution without broadening the
existing field, protected-content or incoming-table payload contracts. It pins
the section/note and every nested table, row, cell and mutable list identity,
rechecks that chain before publication, bounds the resolver, and retains the
whole-document paragraph-occurrence check. Vertical continuation cells and
control/frame ancestry do not become eligible merely because their visible
text looks ordinary.

The reviewed tests cover body and authored-note engine targets, nested cells,
merged origins, prefix/suffix simple and complex active citations, changed
formatted lengths, rich content, forward/reverse selections, exact undo/redo,
DOCX reopening, typed owners, aliases, stale ownership without revision changes,
cross-cell/row boundaries, selected table bands and direct Add Note/Add
Annotation completion/cancellation. Controller rollback remains the supported
boundary for applying a staged engine session.

## Limits

This is local source qualification. It does not establish installed
Zotero/Word/LibreOffice plugin interoperability or a Notes-pane table-cell UI.
The new stale check pins owner and list identities; it does not promise detection
of every raw geometry mutation that bypasses the host's revision contract.
No GitHub Actions or status endpoints were queried or awaited.
