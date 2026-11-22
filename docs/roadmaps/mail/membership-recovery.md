# Checking the current location after uncertain Move/Delete

This increment continues [durable foreground Move/Delete](durable-mutations.md).
Connected Mail activity can explicitly check the original message identity and
save what the provider currently reports. A current observation is separate from
the historical outcome: an interrupted command remains uncertain, is never
replayed, and stays protected from completed-history cleanup.

## User workflow

1. Connect the same account and open **Mail activity**.
2. Open a completed Move/Delete receipt containing an uncertain item.
3. Choose **Check current location**. Merely opening history performs no network
   work. Flag-only or reader-only adapters do not acquire this capability.
4. Read the observed folder/labels or the reason the original identity could not
   be located. Each saved observation shows its check time alongside the
   original subject, source, requested destination and unchanged outcome counts.
5. Refresh the folder or synchronize explicitly to obtain a new mailbox view.

The check can be repeated. Storage keeps one bounded latest observation per
uncertain item, rather than appending an unbounded event stream. If the new
check fails, the previous saved observation remains. Earlier successful items
in a multi-item check remain saved when a later item fails or the user stops.
Closing history, disconnecting or changing account cancels publication of stale
results. **Stop checking** is available during a check. English, German and
Arabic controls support narrow windows and enlarged text.

Cached history displays already saved evidence without connecting or creating
a provider. It explains that connecting the account is required for a fresh
check. The saved timestamp matters: another client may have changed the message
since that observation.

## Provider-specific evidence

| Provider | Read performed | What the observation establishes | What it cannot establish |
| --- | --- | --- | --- |
| IMAP | Select the original folder, check UIDVALIDITY, then bounded exact-UID metadata with BODY.PEEK | Whether that original UID is currently available in its generation and whether it has the Deleted marker | A moved destination UID, permanent removal, or whether the earlier command caused the current state |
| Gmail | Exact message GET with minimal `id,labelIds` | The explicit complete label set and presence/absence of the exact TRASH label | Folder-style Move semantics, delivery history or who changed the labels |
| Microsoft 365 | Exact message GET with `id,parentFolderId` and immutable-ID preference; resolve the actual Deleted Items folder ID | The current parent of the same immutable identity and whether it is Deleted Items | A replacement identity after an archive-mailbox transfer or proof that the earlier operation caused the location |
| Exchange EWS | Narrow GetItem `ParentFolderId` projection for the original ID; resolve distinguished Deleted Items | The original item's current parent when its ID remains available | The replacement ID or destination after EWS changes an ID during a move |

Missing original identities are presented as **unavailable**, with destination
and historical result unverified. Absence from a loaded row list is never used
as provider evidence. An IMAP generation change stops before reading the reused
UID. EWS `ErrorItemNotFound` is an unavailable-identity observation, not proof of
permanent deletion. Cloud recovery accepts only item-specific not-found codes
on the exact message GET; mailbox-level, unknown or malformed 404 errors fail the
check. A profile or Deleted Items lookup failure never becomes message absence.

Providers use metadata reads only. They do not fetch bodies or attachments,
change Seen, issue MOVE/STORE/EXPUNGE, submit mail, retry a mutation, or search by
subject or RFC Message-ID to guess a replacement. Wrong returned IDs, missing
parent/label data, duplicate labels, invalid identities, quota overruns and stale
leases fail explicitly. Graph requests keep `Prefer: IdType="ImmutableId"` on
every request; folder IDs remain opaque and case-sensitive.

## Core and storage contract

`MailMembershipObserver` is optional and independent of `MailFlagObserver`.
The immutable `MailMembershipObservation` carries the exact requested identity
and one of present, missing or identityChanged. Present IMAP evidence contains
its source mailbox and deletion marker. Gmail evidence contains a complete label
set; Graph/EWS evidence contains exactly one parent. A separately supplied
provider-resolved deletion mailbox establishes trash membership. Omission of
that mailbox means deletion status is unknown, not false.

Schema 14 adds `membership_item_observations`, keyed by account, batch and item.
It preserves schemas 1–13 through transactional migration. Published v13
membership receipts are not reinterpreted as earlier flag-only data. Evidence
is included in metadata quotas and account cleanup; malformed stored evidence
is rejected. No versions or dependency locks are changed.

Before network work, `beginMembershipReconciliation` captures the original
repository owner, exact identity, revision, account lease, observation epoch,
clock and current-view predicate. `recordMembershipObservation` rechecks those
fences and atomically saves the evidence with the next journal revision. Account,
message, journal, membership and sync changes retire stale observations. Failed
writes, quota exhaustion or cancellation roll back the new evidence. Reopening
the repository retires old handles.

The original action, destination, per-item outcome, uncertainty count and error
evidence are unchanged. Membership observations are deliberately not flag
resolutions: they cannot make an uncertain command eligible for history cleanup.
There is no command replay or recovery queue.

## Cache and acceptance boundaries

This increment saves explicit current-state evidence. It does not rewrite saved
browsing windows, synchronized memberships, cached flags/bodies, drafts, Outbox,
archives or sync cursors. Those retain their earlier dates and coverage until an
explicit refresh or synchronization observes the provider again. This avoids
inventing destination identities or complete membership from a partial check.
Connected hosts require refresh after checking.

The [local qualification record](../../validation/mail-membership-recovery-20261122/README.md)
records exact source, commands, results, runtime provenance and remote checkpoints.
Synthetic protocol fixtures and local persistence tests do not qualify live
provider accounts, installed platform releases, browser persistence or hardware
power-loss behavior. Complete Outlook/Thunderbird/eM Client parity remains open.

## Ordered continuation

The first step below is now implemented for authoritative IMAP/EWS Move replies
in [identity transitions](identity-transitions.md), with schema-15 evidence,
conditional atomic retained-cache reconciliation and null-safe sync snapshots.
Generic results and unavailable mappings remain refresh-only. Read-only
membership observations in this document retain their original semantics.

1. Persist authoritative identity transitions when mutation responses provide
   them, including IMAP COPYUID and EWS new IDs. Reconcile exact source/destination
   cache memberships atomically with view revisions, without changing historical
   uncertainty or inventing a mapping lost before acknowledgement.
2. Add durable visible-selection move/archive/delete with a destination preview,
   per-message outcomes, stop-after-current behavior and the same recovery model.
3. Extend shared connected and multi-account navigation with clear coverage,
   account isolation and repository-driven updates.
4. Add indexed body search, persistent cross-folder conversations, tags/categories
   and ordered rules with previews through the existing durable operations.
5. Continue rich authoring, provider Drafts/Sent reconciliation, Calendar/People,
   security and installed/live-provider qualification as separate milestones.

## Protocol references checked for this increment

- [Microsoft Graph immutable IDs](https://learn.microsoft.com/en-us/graph/outlook-immutable-id): per-request preference, same-mailbox lifetime and folder-ID boundary.
- [Graph Get message](https://learn.microsoft.com/en-us/graph/api/message-get?view=graph-rest-1.0): exact identity reads and explicit projections.
- [Gmail messages.get](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/get): exact message and minimal metadata access.
- [EWS ParentFolderId](https://learn.microsoft.com/en-us/exchange/client-developer/web-service-reference/parentfolderid): required folder ID with optional ChangeKey.
- [Microsoft mailbox-level REST 404 errors](https://learn.microsoft.com/en-us/troubleshoot/exchange/user-and-shared-mailboxes/rest-api-is-not-yet-supported-for-this-mailbox-error): why HTTP status alone cannot identify missing mail.

The broader workflow benchmarks remain [Outlook rules](https://support.microsoft.com/en-us/outlook/mail/manage-email-messages-by-using-rules-in-outlook),
[Thunderbird synchronization](https://support.mozilla.org/en-US/kb/imap-synchronization)
and [eM Client mail features](https://www.emclient.com/features-email).
