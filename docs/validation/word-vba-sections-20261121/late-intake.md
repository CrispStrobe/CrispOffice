# Late branch intake: Word section macros

Review captured **21 November 2026, 05:57:54 UTC**. This is a later snapshot
than the [initial 335-ref reconciliation](intake.md), which remains complete
for its captured refs. The initial integrated base was
`2cd11ced136a30354169fd0043e002079bcabfa3`, including remote main
`84046975f286407e3c62e5e5352bc16bc89c0d26` and the three performance commits.
GitHub Actions were not queried or awaited.

| Later branch | Captured head | Disposition |
| --- | --- | --- |
| `work/mail-repository-sessions-20261121` | `c375becb51939dcca5c145bf1bcdb14a4febe041` | Selected for integration: bounded repository streams and a qualified replacement-layout retry correction. |
| `codex/zotero-transfer-20261121` | `fb692a7fdee8020470eb772f7bb0adc4fa28545e` | Deferred active implementation checkpoint: concrete editor and model integration gaps remain. |
| `feat/proofing-scheduling-20261121` | `0b6b44a631ddceb52dc7ec0dfbdd7143ee1c3d1e` | Deferred active WIP scheduler checkpoint, without new tests or qualification evidence in this commit. |

## Mail: ready source and evidence

The Mail commit adds bounded cached-mailbox catalog/view streams, with typed
failures, commit-only invalidation, pause coalescing and cancellation/close
handling. It also restores the stale-layout flag if replacement layout fails,
so subsequent reads retry instead of returning the previous document's layout;
timed-listener bookkeeping is released on controller disposal.

Its `store-validation.json` reports **117 native SQLite tests passed**, including
11 new stream scenarios, and strict analysis. The source-bound
`incoming-word-validation.json` reports strict analysis and **70 Flutter tests
passed, 8 skipped, 0 failed**. Those skips are existing image-only DOCX fixtures
with no editable paragraphs; both new replacement-layout failure tests passed.
This is correctness evidence, not a profile-mode typing-performance result.

The reviewer independently compared the commit's Git blobs against all **8
store receipt hashes and 3 incoming Word receipt hashes**: every hash matched.
These are prior local executions attached to that exact source, not executions
performed by the late-intake review. The new source does not overlap the Word
VBA compiler or native section-operation files. Its controller changes depend
on the already integrated `2cd11ced` lazy-layout work. The original commit and
receipts are to remain in ancestry; final publication must verify that ancestry.

## Zotero: incomplete protocol-to-host integration

The branch's own README identifies this as its first wire-protocol checkpoint
and says model/editor qualification is still in progress. Review found two
concrete gaps at the captured SHA:

- It adds `ZoteroCitingCommand.exportDocument`, but the exhaustive command-title
  switch in `packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart`
  has no arm for that value. This leaves the editor switch non-exhaustive.
- The wire driver accepts the current placeholder callback shape
  `(documentId, codes, placeholderIDs, noteType)`, but the handler in
  `packages/quds_office_engine/lib/src/word/model/word_zotero_citing.dart`
  still checks argument 4 as `Http` and interprets arguments 2/3 as IDs/note
  type. Thus the newly admitted callback does not reach a compatible model
  implementation. That model also still advertises no transfer support.

The checkpoint's protocol tests do not establish editor compilation or complete
document transfer. Keep the branch available while its owner completes the
continuation, then assess a completed successor rather than publish this
intermediate snapshot as a finished feature.

## Proofing: explicit WIP

The commit is titled `WIP: proofing scheduler on word/sentence completion,
pause and idle`. It changes six source files (777 additions, 192 deletions),
including roughly 900 changed lines in `word_proofing.dart`, and introduces no
tests or qualification receipt in that commit. Its controller additions touch
proofing visibility and are separate from the Mail layout retry fix, but the
scheduler needs its own completed behavior and validation before integration.

Refresh remote main and these active branches before final publication. This
record freezes the reviewed SHAs and disposition; a later successor requires a
new check. No branch was deleted, reset, force-pushed, or overwritten by this
review.
