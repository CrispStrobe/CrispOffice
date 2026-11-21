# Send later and a ten-second Undo window

Native Studio Mail's Outbox now supports fixed-time scheduling and a short
pre-submission undo delay through the existing account-owned SQLite store.
IMAP/SMTP, EWS, Gmail and Microsoft 365 use the same Outbox dialog and existing
submission adapters. This is a foreground workflow: keep Outbox open and the
application active. Server-side and OS-background scheduling remain separate
milestones.

## User workflow

1. Compose a message and choose **Queue in Outbox**. The existing atomic handoff
   saves frozen MIME, attachments and the full recipient envelope, including
   Bcc, before clearing that draft revision.
2. Open **Outbox**. For a queued message that has never been attempted, choose
   **Send later**. Select a date/time, **In one hour**, or **Tomorrow at 09:00**.
   The dialog shows the local date, time and UTC offset before confirmation.
3. Choose **Schedule send**. The deadline is saved before a foreground timer
   is armed. When due, the message receives one attempt through the existing
   durable submission path.
4. Alternatively, choose **Send with 10-second undo**. The full usable ten-second
   window starts after storage and readback complete. **Undo / remove schedule**
   returns the message to an ordinary queue without sending or changing its
   frozen contents. It does not recall a message already submitted.
5. **Pause sending** retains the saved deadline. **Send later** changes it.
   **Send now** explicitly confirms removing an existing schedule before an
   immediate attempt. Existing cancellation and atomic edit-as-draft remain
   available before an attempt begins.

Closing Outbox, suspending/leaving the app or changing the account pauses its
foreground schedules. After reopening, choose **Resume scheduled send** and
confirm. Overdue entries can then send immediately. Opening, refreshing or
reconnecting by itself never starts sending. Once an attempt starts, ordinary
retry and uncertainty handling follow the existing Outbox contract.

The original composer **Send** and Outbox **Send now** remain immediate explicit
actions. This increment does not change their default to delayed sending.

## Time and lifecycle rules

- Store a canonical UTC instant. A later time-zone change changes its local
  display, not the saved instant. The picker rejects calendar times normalized
  through a DST gap and displays the selected offset. An ambiguous repeated
  local time uses the platform-selected instant shown by that offset.
- Both the actual wall clock and monotonic elapsed time guard a live undo
  delay. A forward wall-clock jump cannot shorten the ten usable seconds;
  a backward jump postpones dispatch until the saved deadline is reached.
- Check deadline, account ownership, foreground state and permission generation
  again after the durable attempt write and immediately before provider use.
  A pause/resume cycle during a pending write cannot silently restore permission.
- Remove foreground permission before an attempt, including a failed attempt.
  There is no automatic retry. An interrupted submitting marker reopens as
  uncertain and retains the existing explicit delivery-check workflow.
- A failed schedule or Undo write leaves the durable entry available for
  inspection and does not arm a new send. Failed Undo also pauses any existing
  foreground permission before attempting the write.

## Persistence and concurrency

`MailOutboxEntry` carries `sendNotBefore` and `scheduleRevision`. Only a queued,
never-attempted entry without inherited uncertainty can be scheduled. Replacing
or clearing a schedule increments the revision even if the chosen time repeats.
This prevents an old UI snapshot from becoming current again after an edit away
from and back to the same deadline.

Outbox payload version 3 reads existing versions 1 and 2 as unscheduled. No new
database schema or dependency is required. All timed and previously timed
transitions compare the expected schedule revision. Cancellation, submission,
completion, recovery and atomic edit-copy preserve the frozen payload and
timing history; stale operations fail without contacting a provider.

Foreground permission is intentionally not persisted. The stored deadline is
eligibility; explicit scheduling or Resume grants permission for the current
active Outbox session. Storage-only consumers never start a worker by reading
an entry.

## Local verification and next parity step

The [work record](../../validation/mail-scheduled-send-20261121/README.md)
retains the exact local commands, source/checkpoint identities, regression
results, incoming Office reconciliation and remaining boundaries. Tests include
actual SQLite reopen/rollback, ABA races, clock changes, lifecycle events during
pending storage, immutable recipients/bytes and EN/DE/AR layouts.

The next sending milestone is an account-owned background scheduler with
explicit host lifecycle/credential ownership, bounded rate/backoff policy,
provider-specific Sent reconciliation and installed/live-provider acceptance.
The complete synchronized mailbox workspace, durable move/delete operations,
identity routing, richer authoring and Office attachment workflows remain in
the ordered [mail roadmap](README.md#desktop-mail-parity-ordered-increments).

Comparison references checked 21 November 2026:
[Outlook delayed/scheduled send](https://support.microsoft.com/en-us/outlook/mail/delay-or-schedule-sending-email-messages-in-outlook)
and [eM Client mail capabilities](https://www.emclient.com/features-email).
Product versions and providers have different scheduling constraints; this
increment claims its documented foreground behavior, not full product parity.
