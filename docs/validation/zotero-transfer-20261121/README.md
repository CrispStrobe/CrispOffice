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
speculative compatibility change in checkpoint `fb692a7f` is removed in the next
checkpoint; it is not part of the delivered behavior. The original callback
contract and regression tests remain intact.

## Validation status

This first implementation checkpoint contains the wire protocol and regression
tests. Model, editor and interoperability qualification are still in progress.
Final commands, counts, source binding and remaining boundaries will be recorded
before publication to main. Intermediate runs are not final acceptance.

## Qualification of the integrated `3da241d5` snapshot

The status above describes the original implementation checkpoint. The Word
section-macro integration subsequently qualified and included commit
`3da241d5f1f3e43d7be47f00bcf7fbe62bd8272b`: 798 native Word/Zotero cases and
97 Flutter editor cases passed. A reviewed brace-only helper cleanup then
passed strict analysis and 30 native transfer cases. Exact source identities,
logs and limits are retained in the
[combined local acceptance record](../word-vba-sections-20261121/README.md) and
[incoming review](../word-vba-sections-20261121/incoming-zotero-engine-review.json).
This applies to that captured source, not later work on the advancing Zotero
branch. Installed Word, LibreOffice and Zotero interoperability remains
unexecuted.
