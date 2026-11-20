# Publication intake and source applicability

The published reconciliation checkpoint is `79e10ef8375aa9950d624eb9702ba1ff19a19e8c`, tree
`d3a472f1e23bb98c1898087bdbd1ddf9d07f4c8d`. The [immutable Git comparison](publication-source-applicability.json)
verifies that both later main advances, `e975cec1` and `698209aa`, are ancestors,
along with the accepted Mail baseline and the accepted frozen-intake target.

The final follow-up from `5034494d` changes only braces around an existing
single-statement conditional in `test/zotero_citing_test.dart`. Production is
identical, and all 492 previously bound Word inputs are identical to that parent.
The protocol test has its own separately owned publication gate.

## Source inventory

The original frozen cutoff remains **320 refs**: 38 fork branches, 274 fork PR
heads, four upstream branches and four upstream PR heads. Its accepted audit
has zero uncovered refs and fourteen independently recomputed historical
replacement proofs. Its target remains an ancestor of this checkpoint, so the
cutoff result remains valid. No branch/PR inventory was refreshed; the two
publication-time main advances are separately recorded additions.

## What remains identical

| Scope compared with accepted sources | Result |
| --- | --- |
| All tracked files in Mail packages | **222 identical modes/types/blobs**, identical path set |
| Mail Dart feature scope | **211 identical modes/types/blobs**, identical path set |
| Word acceptance input scope | **488 of 492 identical SHA-256 inputs** |

The 211-file scope is the complete Dart content of Mail core, transport and UI,
plus Studio's `studio_mail*.dart` library/test files. The broader 222-file
comparison additionally covers MIME/store and non-Dart Mail package files.
These scopes overlap and must not be added together.

The four changed Word-scope inputs are exactly the new Zotero implementation:

- `lib/src/word/model/word_zotero.dart`
- `lib/src/word/model/word_zotero_citing.dart`
- `lib/src/word/model/word_zotero_note.dart`
- `lib/src/zotero/zotero_citing.dart`

Those paths are relative to `packages/quds_office_engine/`. Each published blob
matches incoming main `698209aa`. The accepted VBA parser, corrected layout and
deserializer, every selected Word test, all examples/portable drivers and the
other scoped inputs remain identical. The earlier 961 VM / 758 Node and BAS
results remain their own bounded source acceptance. The new Zotero dependencies
have separately owned publication engine/editor receipts; their terminal
outcomes and source bindings must be consulted for that changed code.
**This source report does not assert any unknown runtime gate passed.**

## Inherited Word and Mail reconciliation

The [canonical-content proof](intake-local-main698-word-proof.json) is retained
and checked against the published tree. Nine canonical Word files match exactly,
two named suites retain their thirteen compiler and one integration additions,
and four redundant positional aliases have proved replacements under accepted
canonical names. The older Mail coordinator snapshot from the incoming branch
was already superseded and was not restored. All four incoming Mail core files
are accounted for by the earlier `835b8019` equivalence review.

The VBA documentation retains the accepted three example families, numeric
contract and exact-unit citations, and links to the fresh Word qualification.
Useful new Zotero implementation and historical evidence were incorporated
without rewriting earlier intake or runtime receipts. GitHub Actions, workflow
runs, checks and status endpoints were neither queried nor awaited.
