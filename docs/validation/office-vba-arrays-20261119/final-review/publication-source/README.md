# Publication source audit

This read-only audit is bound to source checkpoint
`61bb3ee42a385c5ffaffa44047693a6f378a8424`, tree
`c812fb1f2d1156099f50313390346b98f8f3d56a`. It does not refresh remote references,
query GitHub Actions/status checks, or extend review to newer work.

## Ancestry and incoming preservation

The commit has exactly these three parents, in order:

1. Our previous checkpoint `f6b8638d5c78a2d17e5e1c2fb43620c63a23b90c`.
2. GUI head `8c6acd04637ef627959fe40f518254ed538ab087`.
3. Planning head `9d6cd0504094632825d3a0990a37fffd5c1b2c05`.

Remote main snapshot `caf378f40fd5bda50f504a6816404d01d8bbb8f8` is an ancestor.
All **14 changed files** in the latest GUI advance, measured from its common
ancestor with our previous checkpoint, match the incoming blobs exactly. Both
new planning files also match exactly. The complete per-file identities and
comparison bases are recorded in `audit.json`.

The only non-validation differences from the GUI head are the retained historical
editor fixture correction, the independently justified dark-slide test correction,
the narrow table text-color parser fix, and its two engine regression cases. These
are accounted for individually in the audit. No tracked file was deleted from
either the previous root checkpoint or the remote main snapshot.

## Scope and dependencies

The source checkpoint changes 403 paths from remote main: 361 validation paths
and 42 other paths. The latter comprise the macro/compiler work, its example,
tests and workflow selection, the described GUI/API/theme additions and host tests,
the image-editor design document, and the table-color parser correction.

All **34 tracked dependency manifests, lockfiles, and runtime-pin files** selected
by the audit remain unchanged. The mail core, MIME, store, and UI implementation
trees are unchanged from remote main. The image-editor contribution is a design
document; it introduces no vendor implementation or dependency.

The only new editor export is `word_page_layout.dart`, with the described layout
value/target/scope types and controller capture/freshness/apply methods. The theme
API additions support display-only document colors. The macro changes extend the
source dialect through the existing compiler/host entry points. No unrelated API
change was identified. The existing macro workflow now selects the array suites
and JavaScript smoke program; this is source configuration, not evidence of an
Actions execution.

## Documentation after the source checkpoint

The working changes to top-level `README.md` and
`packages/quds_office_engine/CHANGELOG.md` accurately describe arrays, bounds,
`For Each`, explicit range coordinates, retained source-only evaluation, and the
first representative PPTX table-cell ink fix. Their exact SHA-256 and Git blob
identities are recorded in `audit.json`.

Neither path is present in the 856-entry engine source snapshot or the normalized
2,495-entry GUI snapshot. They are documentation-only changes after the accepted
source checkpoint, and do not alter its frozen test inputs.

The full final local qualifications were still running when this source audit was
written. Their completed receipts and the root qualification README receive a
separate final review; no preliminary or incoming-author count is reused here.
