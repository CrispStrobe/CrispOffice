# Zotero document transfer — work record

## Starting point and intake

The continuation starts at remote main `84046975f286407e3c62e5e5352bc16bc89c0d26`.
An exhaustive frozen audit captured 334 fork/upstream branch and pull-request
heads: 309 ancestors, 24 independently verified exact historical equivalents
and one incoming branch. The three commits on `perf/keystroke-trace-20261121`
ending at `2cd11ced136a30354169fd0043e002079bcabfa3` were integrated with their
ancestry intact. Remote checkpoint `48411168cd33045bd6de807ab145e2b2eba9de37`
contains that integration. The replay records 310 ancestors and 24 verified
equivalents, with zero uncovered refs. The complete inventory and reproducible
proofs are in `intake/`. No GitHub Actions, workflow status, checks or queues
were queried or awaited.

## Implementation scope

Implement the official Zotero transfer handshake and hyperlink carrier, using
its marker, raw citation/bibliography codes and serialized preferences. Preserve
detached staging, document identity, complete native formatting and one undo
step. Qualify DOCX carrier round trips and ODT export separately from installed
Word/LibreOffice/Zotero interoperability. Direct native ODT reference-mark
import remains a separate milestone.

`upstream-sources.json` records exact upstream commit and blob identities.
An initial hypothesis of an Add Note callback mismatch was rejected after tracing
the caller as well as the wrapper: the wrapper parameter names are stale, but
its actual positional arguments match the existing Quds implementation. The
speculative compatibility change in checkpoint `fb692a7f` was removed in
`3da241d5`; it is not part of the delivered behavior. The original callback
contract and regression tests remain intact.

## Publication intake and implementation findings

A second frozen inventory at 2026-11-21 06:06:59 UTC captured 338 branch and PR
heads. It identified four new incoming heads: Word section controls
`81b76200`, Mail repository sessions `4d435f81`, proofing scheduling `ef30d540`
and keystroke harness improvements `1460876e`. The respective preserving merge
checkpoints are `d480d31e`, `43fb2e1a`, `d24240ee` and `f4c493d9`. Both package
changelog conflicts retain the complete entries. The replay on `f4c493d9`
accounts for 314 ancestors and 24 freshly verified historical equivalents,
with zero uncovered refs. `publication-intake/` retains the captured refs,
immutable-SHA fetch receipts, deltas, reviews and replay.

Transfer/model/UI checkpoint `3da241d5` and carrier/appearance checkpoint
`c21b6d51` preserve the implementation before the final integrated gate.
Development qualification found and fixed three file-format issues: adjacent
ODT links could lose the second citation's Unicode suffix in LibreOffice;
undefined generated Bibliography styles caused the tested converter to append
an extra character; and imported temporary links could leave active citations
with hyperlink color/style. The fixes coalesce equal-target ordinary ODT link
runs, provide the missing referenced bibliography style without replacing
custom styles, and remove only recognized carrier appearance.

A programmatic covariant block list also exposed a publication atomicity defect.
Transfer now preflights every outgoing container before any source mutation and
publishes individual compatible elements. Incompatible, fixed and immutable
owners fail before mutation; editor snapshots retain covariant undo/redo and
check restorability before entering the application/rollback sequence.

## Validation status

The final combined-source gate is pending. Focused development runs are retained
separately; they are not final acceptance totals. Final commands, exact input
hashes, raw case events, counts, converter artifacts and remaining boundaries
will be recorded before the authorized merge to main. Installed Zotero/Word/
LibreOffice plugin sessions and direct native ODT input remain unqualified.
See `installed-application-acceptance.md` for the next versioned acceptance
matrix.
