# Mail restore resume cross-review

This review covers the native restoration loop and Studio resume/progress
management implemented by other agents. The reviewer authored the database
checkpoint portion; that portion received the root agent's separate review.
This division is explicit: the storage author's development tests are not
described as independent acceptance of their own implementation.

The inspected mail implementation includes the destination-unavailable
correction. Exact hashes for its targeted replay are in
[destination-unavailable-replay.json](independent-review/destination-unavailable-replay.json).
The root owns the final combined-source freeze, acceptance and publication.
No Actions, status, workflow-run or job endpoint was queried or awaited.

## Findings resolved before acceptance

### Management must remain possible after lowering write quotas

The root's storage review found that listing saved progress originally used the
current `maxRestoreJobs` and `maxRestoreReceipts` write quotas. Reopening under
tighter limits therefore hid all progress behind a quota error, preventing the
management UI from offering explicit cleanup even though the deletion API was
designed to permit it.

Management reads now use the absolute supported ceilings of **10,000 jobs and
1,000,000 receipts**. A bounded receipt-count preflight runs before aggregation.
Normal imports still obey the destination's configured write quotas, with
defaults of 64 jobs and 100,000 receipts. Existing progress is never silently
evicted. The tighter-quota regression now verifies that both retained records
remain listed and can be deliberately deleted while originals remain intact.

### Losing the destination must terminate receipt lookup

The independent native review found that an `unavailable` receipt lookup was
handled by the same catch block as an unavailable source file. Closing the
archive from a progress callback therefore attempted every remaining receipt
and counted repeated failures against an already unavailable destination.

The correction marks failures originating from destination receipt lookup and
terminates on `unavailable`, matching the existing write-failure behavior.
An unavailable source EML remains an individual failed item, so other valid
messages can still be restored. The new close-on-resumed-progress test retains
one confirmed resumption, reports one failed lookup at ordinal two, and stops
with a partial/unavailable result. The independent two-case replay also runs
the existing sparse-source recovery case to protect that distinction.

The replay passed **2 cases, zero failures, zero skips**, with process exit 0,
a successful final JSON reporter event and unchanged hashes for all six
recorded mail source/test inputs. It is a targeted development replay, not an
additional contribution to the final acceptance total.

### Incoming compatibility fixes retain existing restore behavior

The later GUI frontier `ba51c40a` supplied two additional mail corrections.
Review confirmed that existing adversarial tests observe completed
`MailArchiveOperation.archive` events to cancel after a commit; the new receipt
write's operation identity had prevented those callbacks from running. Receipt
writes now retain the existing archive diagnostic identity while committing
content, provenance and progress atomically.

The incoming source/codec correction also preserves bounded per-item failures
when a thrown codec error is sanitized to `storageFailure`. The combined loop
keeps those source failures separate from the destination failure above:
destination `storageFailure` and `unavailable` terminate after one failure;
source/codec failures permit remaining items to be tried. The existing
adversarial fixture expects all three failed source items with only one retained
failure detail. The merged code was inspected; its final execution belongs to
the combined-source acceptance run, not the earlier two-case replay.

## Native behavior reviewed

- **Preview trust:** `withCheckpoint` is advisory. Restoration rereads and
  decodes the current manifest under the current restorer limits. Neither
  preview counts nor a caller-supplied checkpoint can authorize a skip. Receipt
  lookup uses the freshly decoded item and its one-based ordinal.
- **Manifest identity and movement:** progress uses the SHA-256 of decoded
  manifest text and the destination archive. Paths are not persisted in jobs.
  An unchanged export can therefore move directories and be inspected again.
  Changed decoded text produces a different identity; a stale preview is
  rejected. UTF-8 decoding semantics are relevant, so this is not a claim of
  hashing every original encoded manifest byte.
- **Source versus destination verification:** default/full mode rereads and
  checks every source original before parsing. Explicit resume checks the
  destination original's size/hash, retained metadata projection, FTS fields
  and every expected normalized provenance record before reusing a receipt.
  It deliberately does not reread EML files for those confirmed receipts.
- **Corruption and repair:** corrupt original/metadata yields a storage failure;
  missing or stale FTS yields a conflict. Neither becomes a successful skip.
  Missing expected provenance returns no reusable receipt, causing ordinary
  source verification and the atomic import path to repair the missing origin.
  A full rerun can rebuild an existing index from its verified retained
  projection; it never replaces the original bytes with a codec reconstruction.
- **Accounting:** saved, duplicate and failed messages are separate from
  resumed messages. Source bytes verified in this run are separate from
  destination bytes rechecked for receipts, as are current and prior indexing
  warnings. Processing counts include resumptions exactly once.
- **Cancellation and overlap:** the owner is claimed before asynchronous work,
  across restorer instances sharing the archive. The owner is released in
  `finally`. Per-message transaction success is counted before subsequent
  observer or cancellation checks, preserving confirmed work. Cancellation
  before the transaction's commit barrier rolls back content, index, origins
  and receipt together. Observer exceptions only increase the observer-error
  counter.
- **Filesystem boundaries:** the preexisting link/type/ancestor and file-stat
  checks remain in both full and resume paths, including manifest checks around
  each receipt. These are observed portable filesystem checks, not protection
  against every hostile replacement between operating-system calls.

## Studio behavior reviewed

The preview defaults to resume only when recorded committed messages are
present, displays the saved counts as recorded progress, and explains that
their source files will not be reread. Clearing the option requests full source
verification without deleting checkpoints. The original inspected selection is
passed unchanged to the store; the native restorer establishes current truth.

The panel serializes workflows through `_work`, passes its cancellation token
to restoration/deletion, and checks mounted state, lifetime generation and
store identity after asynchronous operations. Late inspection/listing results
cannot open a dialog on a disposed panel. Late progress/results cannot mutate
disposed state. The management callback rechecks the owning panel before
starting deletion.

The management dialog confirms the selected manifest identity, removes its
local row only after a successful result, retains failures with sanitized
messages, and disables competing deletion/close controls during deletion.
Deletion addresses the manifest digest, not a mutable list index. The underlying
operation only removes job/receipt metadata; archived messages, provenance,
archive dates, search data and source files remain untouched.

The English/German/Arabic strings distinguish current source verification from
prior destination verification. Numeric diagnostic events do not include mail
content, provenance, manifest identities or source paths. Widget coverage for
resume choice, separate counters, confirmation, failure, disposal, cancellation
and narrow localized layouts is present; its final execution belongs to the
root's combined acceptance record.

## Preserved development evidence

| Evidence | Visible cases | Result |
| --- | ---: | --- |
| Storage checkpoint, multi-origin, repository and native development run | 140 | All passed; exit 0 |
| Checkpoint rerun after management-quota correction | 37 | All passed; exit 0 |
| Independent destination-unavailable and sparse-source replay | 2 | All passed; exit 0; six recorded inputs unchanged |

The first two runs were executed by the storage author. They include the
version-one migration, transactional fault/cancellation rollback, destination
corruption, receipt/job/byte quotas, cleanup, source relocation, distinct
destination profiles, and concurrent duplicate writes. Their raw reporters are
[checkpoint-tests.jsonl](independent-review/checkpoint-tests.jsonl) and
[checkpoint-tests-cleanup.jsonl](independent-review/checkpoint-tests-cleanup.jsonl),
with stderr retained alongside. These development runs lack the final complete
source/dependency/runtime binding and are excluded from accepted totals.

The independent replay preserves its
[exact command](independent-review/destination-unavailable-command.json),
[raw reporter](independent-review/destination-unavailable.stdout.jsonl),
[stderr](independent-review/destination-unavailable.stderr.log), and
[result/source hashes](independent-review/destination-unavailable-replay.json).
No earlier milestone's test total is reused.

## Reconciliation and review boundary

[reconciliation-final.json](reconciliation-final.json) records the exhaustive
advertised fork branch/PR and upstream inventory, including explicit pending
references if another work stream advances during the observation. It excludes
the current mail branch and PR from external incoming-work counts. Historical
equivalence relationships are freshly verified by complete changed
path/mode/type/blob checks and complete-tree checks where appropriate.

The late GUI and VBA streams require their own combined-source qualification.
The earlier combined source was
`11543634c25b639098d177d0add2afa011e3d0d5`; later frontier changes require a new
freeze and qualification. The decisions are recorded in
[integration-notes.md](integration-notes.md). The combined dark-slide
regression retains the corrected table-import round trip and negative raster
controls, direct XML export assertions, and ruler-font coverage. The older GUI
comment that the table importer necessarily loses cell colors was removed
after the newer parser fix was incorporated.

The post-freeze GUI merge
`8d9d1fe77284f76e71fbd6cb2718d3f6cfb636af` has two parents already incorporated
in that source: `a2c144beaea7b46218d3b8c4932dcdb5681004aa` and
`85c8c55186b8eefd242159ee606b2ad1fa61038f`. All 23 changed paths from its first
parent have the second parent's blob identities. Reconstructing the complete
15,179-file tree from those two parents produces exactly the remote tree
`86d4b9fa8ed4a04fa73996af69fc6097aacd376e`, so this merge adds no content beyond
those incorporated parents. This proves content redundancy, not ancestry of
the later merge. The [API observation](post-freeze-gui-observation.json),
[complete-tree proof](post-freeze-gui-proof.json), and
[read-only replay](verify-frontier-merge.py) preserve the distinction. The
exhaustive reference inventory reports the observed ancestry independently.

The subsequent [frontier follow-up](frontier-followup-review.json) identified
additional main language/download management, macOS bundled spaCy runtime,
GUI mail corrections and VBA publication evidence. They are integrated before
the final acceptance window. Cross-review identified a semantic interaction
between the two spaCy streams: bundled status must use the new NER verification
fields and enablement check, and download inventory must show model-only size.
Those findings were corrected by a separate implementation owner in product
checkpoint `7e13a48c2e591f436123a41211950702c13f8df2`. Source review confirms
both host paths use the same verified NER status helper and the inventory uses
`installOffered`/`downloadBytes`. Five focused cases cover both host paths with
missing/corrupt model data and three bundled/downloaded size configurations;
their final execution belongs to the shared acceptance inventory. Installed
macOS/native-model execution is outside the Linux acceptance scope.

At source checkpoint `ec6d527e9aaf207e131217ec24c65cd9ae409433`, the captured
frontier reconciles **232 external references: 209 ancestors, 23 freshly
reverified historical equivalents, and zero unaccounted references**. The
capture contains 18 fork branches, 212 PR heads and four upstream branches;
the current mail branch and PR are excluded from external counts.

The static incoming gate ran inside the final incoming source window and passed
three commands: macOS shell syntax, Python AST/in-memory compilation, and
licence manifest/source-pin verification. All 25 scoped source inputs and 61
execution dependencies remained unchanged. Thirteen manifest notices and nine
Studio mirrors matched their recorded bytes. The raw
`de_core_news_sm-LICENSES_SOURCES` notice also matched its original `0e03878b`
Git blob and SHA-256, including the preserved trailing blank line. These checks
contribute no behavioral test counts and do not build or execute macOS code.

No further blocking mail correctness issue was identified in this source
review. Final acceptance and publication must refer to the final reconciled
source, not merely to this development checkpoint or the author claims of an
incoming draft PR.
