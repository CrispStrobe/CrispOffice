# Reconciliation of incoming main after the reviewed checkpoint

> Historical incoming PR #271 source-reconciliation record, retained from main `e975cec1`.
> Statements about current review refer to that continuation; the executed local results are indexed in [README.md](README.md).

## Concrete resolution

Remote main first advanced from `c954d00d2fc85604ae394674bca91ea8a1dede0e`
to `b01cb23dc1b7bc94b691d68a2507b61dc6d48d7a` while PR #271 was being
finalized. PR #272 consolidated both concurrent Word measurement branches and
this branch's implementation checkpoint `dd8e73a7` as actual ancestry.

Main then advanced to `22cf73b816328cd5fe54ec1793c89f1cc322db3b`, incorporating
this branch's `8ca1958d` history, large-scalar test and six historical evidence
files. The named-argument production compiler remained unchanged.

The reconciliation uses that latest incoming main tree
`a566dec42ed55859563f0bb08f490d870e709c7e` as its base, with ordered commit
parents:

1. `c12ad8bc9c17f1849acdf92b2245e9198f1005b8` — this branch's saved evidence.
2. `22cf73b816328cd5fe54ec1793c89f1cc322db3b` — latest observed remote main.

It keeps the incoming production compiler
`07dc3c5737661abaf3b17db24439c71482de22ed` unchanged. This preserves the
official named-argument extension to all ten conversion functions. The whole
incoming production and test tree is retained without edits.

## Files and evidence

Of incoming main's 30 changed paths since the initial main, 29 retain exactly
the incoming blob and mode. Only this validation folder's README is replaced
with a current evidence index. The incoming 202-case conversion suite already
contains the large-scalar test, so the reconciliation has **zero production
source or test changes relative to incoming main**.

All incoming source, tests, documentation, BAS examples, portable drivers and
other validation records are preserved by building on the complete main tree.
Ten evidence files saved on this branch retain their original blob IDs: six
are already present in incoming main, and four are restored from `c12ad8bc`.
The original intake is already shared and remains unchanged.

The exact manifests, exception and current later-head dispositions are in
[main-reconciliation.json](main-reconciliation.json).
[source-review-main.json](source-review-main.json) and
[historical qualification](incoming-pr271-main-qualification.json) bind current review
to compiler `07dc3c57` and retained test blobs.

The previous 210,069 JavaScript assertions and 60,144 BigInt/binary64 grid
decisions were performed against compiler `a105ddd7`. Their reports and
source-checking reproducer are preserved as historical evidence. They are
not reused as qualification of the adopted compiler.

## Scope and validation limits

The complete initial inventory remains reconciled: 288 ancestor references
and 23 proven equivalents out of 311, with zero initial exclusions or
unclassified references. The temporary workflow remains deleted through the
documented modify/delete resolution.

Both later Word heads are actual ancestors through PR #272.
The two captured later Mail heads remain preserved and explicitly deferred;
they first appeared after the frozen initial intake and have no new runtime
qualification here.

The local execution service could not start Dart, analysis, formatting,
compiled JavaScript, native document execution or CLI processes. Authored
test counts are not passing-test counts. Source review and independently
executed arithmetic models are identified separately.

No GitHub Actions endpoints are queried or awaited. The final checkpoint
requires a non-forced update from the known branch head. Publication requires
a fresh remote-main read, a normal PR merge, and complete-tree/ancestry
readback with the remote checkpoint branch retained. That final proof is
recorded in PR #271.
