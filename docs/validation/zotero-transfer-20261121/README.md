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

The pinned HTTP client also exposes an existing Add Note compatibility error:
its callback is `(documentId, codes, placeholderIDs, noteType)`, while the old
Quds contract expected `(documentId, placeholderIDs, noteType, Http)`. Both the
previously cited upstream revision and the current revision use the former
shape. This continuation accepts the actual upstream form and retains the old
Quds form for compatibility. `upstream-sources.json` records exact source
commit and blob identities.

## Validation status

This first implementation checkpoint contains the wire protocol and regression
tests. Model, editor and interoperability qualification are still in progress.
Final commands, counts, source binding and remaining boundaries will be recorded
before publication to main. Intermediate runs are not final acceptance.
