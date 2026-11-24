# Durable foreground Outbox

This increment advances M07 after [durable drafts](draft-recovery.md) and
[reply/forward fidelity](reply-forward.md). Native Studio Mail now uses the shared
SQLite outbox for **Send** and also offers **Queue in Outbox**. The same workflow
is connected to IMAP/SMTP, on-premises EWS, Gmail and Microsoft 365 on native hosts.
It reuses the existing account identity and store owner; account management is a
separate lane.

The later [management continuation](outbox-management.md) adds local message
review/export, atomic edit-copy and explicit stop-retrying while delivery remains
unknown. The original sending contracts below remain in force.
The [scheduling continuation](scheduled-send.md) adds **Send later** and a
ten-second Undo window, each explicitly armed within an active Outbox session.

## User workflow

1. Connect the intended account and open **Compose**, **Reply**, **Reply all**, or
   either forward action. Existing draft autosave and attachment limits apply.
2. Choose **Send** to save a frozen outbox item and start one explicit foreground
   attempt, or **Queue in Outbox** to save it without contacting the provider.
3. Open **Outbox** from the mailbox toolbar. It lists local message subjects,
   sender, attempt count and state. Expand **Envelope recipients (includes Bcc)**
   to inspect the complete saved transport recipient list.
4. Choose **Send now** on a queued item. A definite retryable rejection offers
   **Retry**. Refresh, reconnect and application restart never start a send.
   An explicitly armed **Send later** or Undo timer follows the separate
   [foreground scheduling contract](scheduled-send.md).
5. An uncertain attempt requires **Check delivery and retry**, a warning and a
   new unchecked acknowledgement. Confirming sends the same frozen message and
   may create a duplicate. An earlier uncertainty remains guarded even if that
   retry is definitely rejected.
6. **Cancel queued message** is available only before possible acceptance, or
   after a definite retryable failure with no earlier uncertainty. Cancellation
   retains the frozen local item. **Remove local record** separately confirms
   deletion of accepted, cancelled or definitely rejected terminal items and
   releases their unreferenced bytes. It never recalls mail or deletes a server
   copy. Confirmed acceptance after an acknowledged retry also permits local
   cleanup; earlier duplicate risk was not disproved by that acceptance.

After restart, reconnect to the same scoped account and open Outbox. An attempt
interrupted after its durable start marker becomes uncertain. A queued item
remains queued. The list and send actions remain local to the selected identity.
The first version does not expose this account-scoped store before reconnecting.

## State and recovery contract

| Stored state | Meaning | Available actions |
| --- | --- | --- |
| Queued | Frozen item; no new provider attempt has started | Send now, cancel or edit as a new draft; inherited uncertainty instead requires acknowledged retry or stop retrying |
| Submitting | Attempt identity committed before provider invocation | Wait; no second send or cancellation |
| Submitted | Sending service acknowledged acceptance | Remove local record; acceptance is not final delivery |
| Retryable failure | Latest attempt definitely not accepted | Explicit retry, cancel or edit as a new draft; older uncertainty instead requires acknowledged retry or stop retrying |
| Permanent failure | Latest attempt definitely rejected | Review/export and remove when no older uncertainty remains; otherwise acknowledged retry or stop retrying |
| Uncertain | Acceptance cannot be established or excluded | Review/export, delivery check, explicitly acknowledged retry or stop retrying |
| Cancelled | Future sending of this queued item disabled locally | Review/export; remove local record |
| Closed uncertain | Explicit local stop; earlier delivery remains unknown | Review/export; separately confirmed removal; no retry |

An older uncertain attempt is represented independently of the latest outcome.
Ordinary retry and cancellation cannot erase that history. Only the explicit
acknowledgement path can start another attempt while it exists. Each attempt has
a fresh cryptographically random identity and the repository checks state plus
attempt identity before accepting a transition.

No client can promise exactly-once delivery after losing a provider's acceptance
response. The Outbox makes that uncertainty visible and never resolves it by
automatically sending again. Native SMTP's aggregate transport reports arbitrary
exceptions conservatively as uncertain; this increment does not invent missing
per-recipient outcomes. A matching native post-submission cleanup exception still
means acceptance and does not authorize retry.

## Atomic composition handoff

The draft adapter saves the exact validated editor snapshot, generates MIME once,
and supplies its saved revision to `SqliteMailRepository.enqueueDraft`. One SQLite
transaction performs both operations:

- Store the frozen MIME bytes, complete sender/recipient envelope, account,
  source draft ID/revision and initial outbox state.
- Replace that exact draft revision with its next cleared tombstone and collect
  unreferenced draft attachment blobs.

Failure rolls back the transaction. There is no interval in which the queue is
committed but the old ordinary draft remains independently resendable. A stale
autosave cannot overwrite the tombstone. The frozen MIME owns its attachment
bytes, so later draft edits, source-file changes and local draft cleanup do not
alter the queued message.

The source draft and queue use the same repository and native profile lease.
Opening a second owner for the account is rejected. In-process operations are
serialized, but the provider call occurs outside that storage queue. Active
attempt tracking prevents refresh from mistaking a live submission for a crash.
If completion persistence fails, the next inspection conservatively recovers
the orphaned submitting item as uncertain. Closing the host does not discard it.

## MIME, providers and account isolation

MIME is generated from the supported composer format, not imported arbitrary raw
mail. It is ASCII-safe, with encoded Unicode content and filenames, and preserves
reply metadata and attachment snapshots. Date, Message-ID and MIME boundaries
are fixed when queued. Bcc is kept in the explicit saved envelope and omitted
from the frozen composer MIME headers.

The native adapter parses the frozen ASCII representation and requires exact
render equality before calling `sendMessage`, supplies the saved envelope
explicitly, and leaves `appendToSent` false as in the prior native workflow.
SMTP framing such as dot handling remains the transport's responsibility. This
does not establish a general binary SMTP path.

EWS, Gmail and Microsoft 365 retain their existing provider request encodings
and private-recipient handling. The host verifies the stable local account and
sender, then rebinds only the account identifier to the current verified provider
session. Wire bytes, envelope, draft ID and revision remain unchanged at this
host boundary. Existing provider-specific acceptance and Sent-copy behavior
continues to apply. A stale session does not begin a new provider call.

Legacy recovered drafts with an uncertain-send marker transfer that uncertainty
into Outbox. The composer still requires its existing acknowledgement before
Send or Queue. A later Outbox retry requires a fresh acknowledgement.
Injected draft-only host adapters retain their former foreground contract; the
production native SQLite adapter supplies the durable outbox capability.

## Limits and remaining parity work

- Up to 100 local outbox entries per scoped account, within the existing SQLite
  account/blob quotas. Terminal cleanup releases storage; queued or uncertain
  work is not silently evicted.
- Current ten-attachment/20 MiB combined decoded attachment limit, 1 MiB plain
  body limit and 40 MiB generated-wire limit. The frozen envelope includes all
  validated To/Cc/Bcc recipients. Provider message limits remain authoritative
  and may reject a locally admissible message.
- Native application-data storage is local and unencrypted. Credentials and
  tokens do not enter the outbox. No server-side Drafts synchronization is added.
- The [scheduling continuation](scheduled-send.md) adds foreground Send later
  and Undo. There is no background worker, automatic reconnect sending or
  message recall. The management
  continuation atomically cancels a safely editable item and opens a new draft.
- Review/exact export, editing a queued copy and explicit local uncertain
  closure are implemented in the management continuation. Provider-specific Sent
  reconciliation and detailed SMTP recipient outcomes remain follow-ups.
- Live-provider accounts and installed desktop/mobile lifecycle qualification
  remain release gates. Local deterministic/loopback tests establish the recorded
  scenarios, not arbitrary device power-loss durability or delivery by a real
  provider.

## Qualification and next increment

The [source and local evidence](../../validation/mail-outbox-20261120/README.md)
separates initial intake, incremental checkpoints, failed development attempts,
accepted tests and final integration. It records the exact runtime and source.
GitHub Actions are not an acceptance dependency.

The [management increment](outbox-management.md) completes the review/export,
edit-copy and local uncertain-closure loop. The [scheduling increment](scheduled-send.md)
adds foreground deadlines and Undo on the same frozen-entry foundation. Multiple
drafts, signatures and Quick Text are available; rich composition, templates and provider Drafts
synchronization remain ordered milestones in the [parity roadmap](README.md).
