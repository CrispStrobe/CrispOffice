# Superseding cursor review — 19 November 2026

**The earlier review below missed a real cursor-token reuse defect.** Its
no-blocking-defect conclusion does not cover safe concurrency across repeated
sweeps and is superseded on that point by this finding. The original receipt is
retained verbatim below so the review history remains explicit.

The affected v2 implementation is present in the earlier reviewed checkpoint
`5fcdf726694b5356d8fb85fb8e01a715e0fadc0c` and the subsequently qualified
`960fb72f` source. The historical 1,000-pass run remains evidence for the tests
actually executed on that source; it did not include the regression exposing
this defect and does not qualify the later repair.

## Finding and repair

A completed v2 sweep always encoded the same mailbox scope, UIDVALIDITY,
`nextUid = 1` and `ceiling = 0`. After a newer completed sweep removed an
expunged message or updated its flags, an older uncommitted page could still
present that identical expected cursor. The repository's atomic compare-and-set
therefore succeeded despite intervening work, allowing stale message state to
be restored. This is an ABA problem: the comparison token returns to an earlier
value. Repeated intermediate positions in later sweeps have the same risk.

Incoming commit `0669ac119da05f5eb777c8cfdbce32e0261df647` introduces the v3
transport cursor with a durable page revision. Every returned page advances
the revision, including empty/completed sweeps and UIDVALIDITY resets. After
either of two concurrent pages commits, the other's expected earlier revision
fails the existing repository comparison. An uncommitted or rolled-back page
does not advance durable state, so a retry may correctly propose the same next
revision. The store continues to commit page data and cursor atomically.

Static re-review found no additional blocking defect in this repair. Its
cursor/provider code and the three affected transport test files were verified
unchanged in the reconciled source
`56b3c8e66bf6b1aa4042f650f6e40d47f3929115`. This note records source review;
passing execution of the final merged source must be bound to a separate
qualification receipt.

## Compatibility and required regression coverage

V1 numeric-window and v2 discovery cursors retain their saved position and
ceiling and enter v3 at revision zero. The first returned page advances to
revision one. No database schema migration is required: the revision belongs
to the opaque transport cursor, independently of SQLite schema v3.

Older transport versions reject a persisted v3 cursor as `invalidInput`.
Downgrading must not silently reset the database or cursor to make that failure
disappear. The repair assumes the upgraded provider is the writer; it cannot
make an old implementation that still emits repeated v2 tokens safe.

Revisions are bounded by the exact shared VM/JavaScript integer maximum,
9,007,199,254,740,991. An exhausted cursor is rejected before credential or
protocol work; revisions do not wrap or reset when UIDVALIDITY changes.

Required qualification on the final integrated source includes:

- `host_store_integration_test.dart`: the actual-provider/SQLite regression
  **completed sweeps reject stale pages without restoring expunged data**.
  It retains an older complete provider result, commits a newer sweep with an
  expunge and changed flags, then requires a conflict and unchanged newer data
  when the stale result attempts to commit.
- `cursor_test.dart` on both the native VM and Node: v1/v2 continuation,
  exact v3 integer-boundary round trips, invalid revisions, version shape and
  mailbox scope.
- `uid_discovery_test.dart`: revisions across partial, completed, empty and
  reset sweeps; legacy cursor upgrades; and exhaustion without protocol work.
- The affected transport/core/store gates with their source/runtime identities
  and retained raw results. Earlier totals must retain their historical source
  attribution.

The original static review follows unchanged.

---

# Core/store range and provider boundary review

Reviewed implementation checkpoint: `5fcdf726694b5356d8fb85fb8e01a715e0fadc0c`.

**Result: no blocking implementation defect or additional required test gap
identified in the reviewed scope.** This is a static source and test-design
review, not an additional execution receipt. Final frozen-source qualification
is recorded separately.

The reviewer independently inspected the core/store range implementation and
its integration with the provider. The reviewer also authored the fork's strict
UID-search primitive; review of that primitive is not represented as independent
of its implementation.

## Transaction and identity checks

- `MailImapSyncRange` validates ordered nonzero uint32 bounds and UIDVALIDITY.
  `MailSyncPage` rejects foreign mailbox/account ranges, non-IMAP records,
  mismatched UIDVALIDITY and records outside the authoritative interval.
- The repository checks active account/provider ownership, the operation lease,
  incoming page/metadata limits and cursor compare-and-set before range writes.
  Its preflight reads existing mailbox memberships with the configured account
  message limit plus one overflow sentinel. Numeric UID gaps are not expanded.
- Range absence is evaluated only in the exact mailbox and UIDVALIDITY. Explicit
  tombstones remain disjoint from survivors and are excluded from inferred
  absences, avoiding duplicate pending-operation revision changes.
- Missing stored members pass through the existing tombstone journal, which
  transitions queued/applying operations to reconciliation. Pruning preserves
  records and cached bytes needed by queued/applying/reconcile operations.
  Membership removal, tombstones, indexes, pending state and cursor remain in
  one SQLite transaction, with lease checks before cursor and final commit.
- UIDVALIDITY resets retain their existing full-mailbox reset semantics. The
  range scan's work bound is distinct from that pre-existing reset path.

## Provider boundary

Discovery selects at most the requested number of existing UIDs. A page ends at
its last selected UID when more remain, otherwise at the frozen sweep ceiling.
The provider rejects fetched UIDs absent from discovery; disappearance between
SEARCH and FETCH is reconciled as absence. New arrivals above the ceiling wait
for the next sweep. Saved v1 cursors retain their continuation position, and a
backwards UIDNEXT cannot authorize a saved unfinished range.

The existing conservative rejection of ambiguous unsolicited UID-less flag
updates is preserved. Discovery count and protocol-byte budgets both apply;
the line-byte bound may be reached before the configured UID-count bound.

## Test coverage inspected

The core/store range suites cover numeric and scope validation, immutable page
inputs, sparse/full-width intervals, empty observations, actual stored-only
tombstones, account/mailbox/UIDVALIDITY isolation, pending-edit and cached-byte
retention, rollback at all three relevant transaction checkpoints, retry, stale
cursor conflicts, lease invalidation, metadata/duplicate/page rejection, reopened
scan quotas, removals exceeding incoming page count, explicit tombstone
coexistence and generation reset.

The provider and real-SQLite/coordinator integration suites cover high-UID paging,
durable resume/reopen, frozen ceilings, legacy cursors, malformed discovery,
SEARCH/FETCH identity disagreement, resource failures, cancellation and account
invalidation. Historical execution totals are not attributed to this review.
