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
