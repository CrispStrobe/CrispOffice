# Mail store continuation — 18 November 2026

## State of this checkpoint

**M05 durable storage is implemented and saved remotely. Final qualification is
BLOCKED.** The first combined Mail run passed all four test cohorts and both
browser compilation checks, but failed the overall gate on two test-file lint
infos and one formatting mismatch. The subsequent disk-full condition prevented
new local commands, including cleanup. Lint repairs and a stricter qualification
event parser were then saved through the GitHub API; those final edits have
**not** been executed.

The [recovered receipt](checks/receipt.json) is explicitly an observation summary,
not the original raw receipt and not a PASS. The original aggregate output and
some independent-review/late-integration logs remain in the local workspace;
they could not be read or uploaded after the filesystem helper stopped starting.
The source implementation, fixtures, runtime provenance, earlier 56-case Office
receipt, and the continuation instructions are saved in the remote branch.

No GitHub Actions workflow, job or check status was queried, awaited or rerun.
All source checkpoint messages use `[skip ci]`.

## Implemented M05 behavior

| Area | Implementation |
| --- | --- |
| Durable repository | New original-MIT `quds_mail_store`, using exactly pinned Drift 2.35.4 and sqlite3 3.9.1. The common public interface accepts an exclusively owned executor; native and browser openers enforce profile ownership. |
| Atomic synchronization | Message records, mailbox memberships, tombstones, local-intent reconciliation and the next opaque cursor commit together. Each page compares the cursor read before provider work, then checks the account lease before commit. |
| Drafts and outbox | Draft revision comparison prevents lost updates. Queued wire bytes, envelope, attachment blobs and draft revision remain immutable. Validated transitions and durable attempt history reject forged terminal states and reuse of old attempt IDs. |
| Recovery | The store captures interrupted submission candidates when opening. Recovery changes a persisted interrupted `submitting` attempt to `uncertain`, retaining its exact bytes and envelope. It cannot relabel an attempt begun by the current owner or authorize automatic retry. |
| Search and cache | Bounded FTS5 searches metadata and supported plain text using literal terms. The indexer does not interpret HTML or contact a provider. Header updates and migration backfill decode metadata without loading cached attachment/source BLOBs. |
| Blob ownership | Immutable hash-checked snapshots, reference ownership for drafts/outbox/cache/editor pins, and read preflight of stored lengths and aggregate size before transferring BLOB bytes. Cache eviction preserves outgoing or pinned content. |
| Account lifecycle | Logout preserves work and records durable host-vault cleanup. Explicit local account/profile deletion retires identities so stale callbacks cannot recreate content. Retired profiles can reopen to complete cleanup acknowledgements. |
| Schema and limits | Versioned transactional migrations, v1-to-v2 preservation, bounded explicit FTS backfill and rejection of unknown future versions without reset. Logical quotas cover identity, cursor, tombstone, journal and reference metadata as well as content. |

The core persistence contract now requires `expectedCursor`; the sync coordinator
passes the cursor it read. Two concurrent-page regressions extend the prior
28-case core suite to 30 cases.

See the [package guide](../../../packages/quds_mail_store/README.md) for the API,
ownership contract, limits and host responsibilities. The database is not
encrypted, and logical deletion is not secure erasure. Vault cleanup is a durable
request that the host must execute and acknowledge, not a claim that a vault was
contacted by the repository.

## Native and browser boundaries

The native opener stores each host/profile database below an explicitly supplied
absolute application container. A sibling SQLite ownership database holds an
exclusive lock for the live repository; operating-system process termination
releases that lock. The content database uses WAL and FULL synchronous mode.
The executed native environment is Linux x64.

The browser entry requires explicit same-origin SQLite Wasm and worker assets,
a storage namespace and Web Locks. It refuses unsafe concurrent IndexedDB,
in-memory fallback and conflicting existing storage locations. Hosts must serve
the recorded Wasm artifact and the compiled worker; there is no implicit CDN.

**Actual browser storage remains NOT RUN/unqualified.** The single Chromium
launch in this continuation aborted before rendering because its singleton
socket was denied. Node tests and JavaScript compilation do not exercise
browser persistence, quota events, reload, cross-tab ownership or recovery.
The [launch receipt](runtime/chromium-smoke.json) preserves the failure.
Reader rendering/network-denial acceptance remains open as recorded in the
[earlier reader report](../mail-reader-20261118/README.md).

## Observed local results

The following rows belong to the combined run started on
`8a6105a7ec217b48105d171703c8d0294c7d2dc6`. Their raw output remains locally in
`build/mail-store-qualification/attempt-1/`; the recovered summary records what
was actually inspected before new filesystem commands became unavailable.

| Check | Observed result |
| --- | --- |
| Locked dependency resolution | PASS |
| Core fatal-info analysis | PASS |
| Store fatal-info analysis | FAIL: unnecessary import and missing braces in `test/repository_test.dart` |
| Formatting gate | FAIL: `test/native_platform_test.dart` needs formatting |
| Mail core VM | 30 passed; zero failures/skips/error events |
| Mail core Node | The same 30 passed; zero failures/skips/error events |
| Mail store VM | 87 passed; zero failures/skips/error events |
| Portable store Node | 39 passed; zero failures/skips/error events |
| Browser public entry | JavaScript compilation PASS |
| Browser worker | JavaScript compilation PASS |
| Whitespace | PASS |
| Overall combined run | **FAIL** |
| Final lint/parser edits and 18 parser regressions | **NOT RUN** |

The 87 store VM cases comprise 32 codec, 16 repository, 16 adversarial, seven
native platform, four configuration, seven migration and five transaction-crash
cases. The 39 Node cases comprise the same 32 codec and four configuration cases,
plus three JavaScript error-policy cases. Repeated runs and cross-runtime
executions are not additional distinct tests.

The earlier focused native runs passed the seven migration cases and five true
process-crash cases. Those cases are included in the 87-case combined suite;
they are not added to it again. The independent-review account and preservation
limits are in [review/README.md](review/README.md).

### Actual process termination

The transaction fixture reports its real owner PID and an explicit READY barrier.
Its parent sends SIGKILL to that process, requires exit `-9`, and opens the same
container. The accepted focused run tested these five boundaries:

| Termination boundary | Verified recovery |
| --- | --- |
| After sync-record writes | The original page, cursor, cache, draft and queued outbox remain intact. |
| Before cursor write | Uncommitted records, tombstones and cache pruning roll back with the cursor. |
| After draft-blob writes | The original draft revision and attachment references/bytes survive. |
| After outbox write | The entry remains queued; an uncommitted attempt-history insertion rolls back too. |
| After a submitting save returns | Reopening recovers to durable `uncertain`, retains exact wire hash/recipients, forbids automatic retry, and survives another reopen. |

A separate native platform case kills an owner process and verifies lock release
and preservation of its committed account. These are process-termination tests;
they do not qualify sudden power loss, physical disk failure, mobile suspension
or Apple packaging.

### Migration and resource tests

The seven real-file migration cases exercise preserved drafts, outbox, original
bytes/attachments and cursor state; bounded explicit reindexing; rollback of a
failed migration followed by successful retry; rejection of future schema
versions without modifying the main database file; and reopening under stricter
single-blob/aggregate limits without first loading oversized BLOB payloads.
Positive controls verify that the fixtures would otherwise load those bytes.

## Findings and repairs

Independent review reproduced a rollback-observer defect: the database transaction
rolled back its rows, but Drift forwarded queued table invalidations during
cleanup. The repository now publishes domain invalidations only after a successful
transaction returns. The regression verifies that observers receive no extra
snapshot for the failed transaction.

Native migration failure tests also found quota errors nested inside Drift
worker exceptions. Bounded typed cause unwrapping now preserves quota/storage
classification without parsing SQL or exception messages.

Resource and lifecycle review added length preflight before BLOB transfer,
metadata-only indexing, quota coverage for provider identity/tombstone/journal
rows, retired-profile cleanup access and a typed foreign-profile logout failure.
The behavior suites passed before the disk blocker.

The qualification runner review separately found that malformed JSON event
records could disappear from the apparent test count. The recovery checkpoint
requires one start and one terminal result, complete unique test-ID pairs, no
malformed event records and no events after completion. Eighteen regression
fixtures are saved. This last runner change and the two lint repairs remain
unexecuted; formatting and a fresh full gate are still required.

## Incoming Office reconciliation

Before store implementation, the continuation fetched all branch and PR-head
refs and reconciled the new main/review work. The
[initial inventory](incoming/initial-audit.json) and
[merge account](incoming/README.md) preserve those dispositions.
The initial selected integration cohort passed **56 distinct tests**
(25 Studio and 31 editor), with source hashes unchanged; its raw evidence is
already remote in [incoming/checks/receipt.json](incoming/checks/receipt.json).

The later complete capture at **2026-11-18 20:39:26 UTC** contained 212 branch
heads and 173 PR heads. Excluding this task's branch and PR #172 leaves:

| External refs | Included by ancestry | Verified historical equivalents | Total |
| --- | ---: | ---: | ---: |
| Branch heads | 197 | 14 | 211 |
| PR heads | 158 | 14 | 172 |

All eight newly observed commits and these three heads are included as ancestors
of the saved integration `8a6105a7`:

- `35b3052f988c232f461df4168b3e619b1c129210` — document-review branch, including the saved Mail continuation and Zotero work.
- `243f0175a0d2d3d724677aba15b57927ef43d3a9` — Zotero native note insertion/reference navigation/direct-command return and draft PR #173.
- `7530f83a5503987dbee5b9678af56116ca98621f` — thesaurus review-packet export and compiled-byte/offline-harness binding.

The one conflict used the full draft-limit-message assertion and retained the
390-pixel/1.4-scale Arabic regression. The ribbon row's minimum sizing and Zotero
features are both present. All 14 historical equivalences were reverified.
The [full captured frontier](incoming/final-frontier.json) is a faithful
reconstruction from the saved initial inventory plus the four observed changed
refs after the disk blocker; its reconstruction provenance is explicit.
This is a capture-time statement, not a claim that other branches stopped moving.

### Late integration qualification is still open

The new Office cohorts did not produce an accepted overall run. The engine
reported 87 passing events, but its process exited nonzero, so those events are
**not accepted as a passing cohort**. The editor/Studio cohorts had no completed
substantive results, and the exporter/harness cohorts reported failures.
Targeted analysis was observed passing.

Filesystem exhaustion was directly observed while these checks were running,
but inaccessible raw logs prevent attributing every individual failure to that
cause. The exact commands, observed results and limits are saved in
[incoming/late-checks/recovery-summary.json](incoming/late-checks/recovery-summary.json).
Those groups need reruns after log recovery. Their numbers are not added to the
earlier 56 accepted cases.

## Runtime and dependency provenance

The [runtime report](runtime/README.md) retains the official Flutter 3.47.8 archive
hash, original framework/engine revisions and Dart 3.13.7 identity. The default
sqlite3 native-assets hook supplied SQLite 3.54.1 with FTS5 and the recorded native
binary hash. No system SQLite override or encryption extension was substituted.

Workspace resolution added eight dependencies and changed/removed no previously
locked versions. The complete 29-package closure, 27 hosted-package notices,
archive/license hashes and expected Wasm artifact are recorded in the store's
[dependency inventory](../../../packages/quds_mail_store/DEPENDENCIES.json) and
[notices](../../../packages/quds_mail_store/THIRD_PARTY_NOTICES.md).
Original Quds source remains MIT; the earlier adapted enough_mail source keeps
its MPL notices. Product-level host/assets/licensing clearance remains separate.

## Remote checkpoints and preservation

| Checkpoint | Purpose |
| --- | --- |
| `cbc5836acfc38b30f145118f467e4cc9fb6a6459` | Reconcile captured Office review and Mail history. |
| `a39f786d5707af308b1f9899c3461a72e62b4b68` | Save durable SQLite repository, core cursor CAS, codecs, platform openers and tests. |
| `32fd8ca9a3841f1cd116dd60ea62cc5140df661a` | Save migration/crash fixtures, error/bounds fixes, runtime and initial Office evidence. |
| `8a6105a7ec217b48105d171703c8d0294c7d2dc6` | Integrate the three later heads and all eight new commits. |
| `7848eca0eec8e291cd88ed6e353151508b77784e` | Save lint/parser repairs, 18 parser fixtures and the explicit blocked receipt through GitHub after local execution stopped. |

Each update used the expected prior remote SHA and a non-forced ref update.
Through `8a6105a7`, the published tree was fetched back into the local checkout.
Later recovery writes are verified through the GitHub API. A clean local tree
or local/final-remote tree equality cannot be claimed after the disk failure.

## Concrete continuation

1. Free space by removing the disposable `late-integration` worktree. Its complete
   merged tree was saved at `8a6105a7`; do not remove the working repository,
   evidence or toolchain. Normal cleanup could not launch because bwrap itself
   needed disk space, and the environment policy rejected sandbox escalation.
2. Preserve the raw files under `docs/validation/mail-store-20261118/review/`,
   `build/mail-store-qualification/attempt-1/`, and
   `docs/validation/mail-store-20261118/incoming/late-checks/` before removing
   reproducible build output. Upload these as historical attempts, not final PASS.
3. Fetch the saved remote branch and reconcile the local documentation drafts
   with the API-recovered versions. Preserve local evidence and inspect changes
   before updating the checkout.
4. Format `packages/quds_mail_store/test/native_platform_test.dart`; execute
   `python3 -m unittest discover -s tools/mail -p test_check_store.py -v`.
5. Run `python3 tools/mail/check_store.py --flutter-sdk /path/to/flutter` into a
   fresh output directory. Retain exact before/after source hashes, raw events,
   all exit codes and a successful complete receipt before closing this gate.
6. Inspect the late Office failures and rerun the failed groups from their recovery
   summary. Refresh/reconcile newer refs once, then verify remote readback and
   local cleanliness.
7. Continue M06 native accounts and bounded IMAP synchronization, followed by
   M07 composition/submission and M04W's mailbox workspace. Actual browser,
   low-memory/mobile, product notices, Apple and CrispCloud migration gates remain
   independent release work.

The blocker requires restored writable workspace capacity. It is unrelated to
GitHub Actions queue capacity.
