# Durable foreground Move and Delete

Native Studio now records single-message Move and Delete through the same
durable command pipeline as read/unread and flag changes. This advances the
next ordered task after [retained-folder navigation](retained-folder-navigation.md).
It does not close the full desktop-client parity milestone.

## User workflow

In a connected IMAP account, open a message and choose **Move message** or
**Mark deleted**. The host checks the server's advertised capabilities before
opening the destination picker or delete confirmation. The picker uses the
currently observed selectable folders, excludes the source, and retains exact
folder identities. Reader-only and older flag adapters do not gain these
controls implicitly.

Exchange EWS and Microsoft 365 retain their existing Move and Delete controls;
those controls now use the durable journal. Gmail supports its existing Trash
operation and continues to refuse folder-style Move. Delete is a separate
provider capability and is unavailable unless advertised.

| Provider | Delete behavior | Move behavior |
| --- | --- | --- |
| IMAP | Set the exact UID's `\Deleted` flag and verify it; do not expunge | Require server MOVE support and an observed selectable destination |
| Exchange EWS | Move to Deleted Items and confirm the original identity is no longer available | Use the existing EWS move and confirmation path |
| Gmail | Trash the message and confirm its TRASH label | Unavailable; label operations are a separate continuation |
| Microsoft 365 | Move to Deleted Items through the existing Graph path | Use the existing move response/immutable-identity checks |

IMAP's confirmation explains that another client or the server can later purge
messages marked deleted. The command leaves the row visible until refresh;
it does not present a deletion marker as a permanent purge. A confirmed move,
or a confirmed EWS/cloud delete, removes the original row from the current
foreground view. The host then requires an explicit folder refresh. The old
pagination cursor and cached-view subscription cannot restore that row.

The checked-message menu remains read/unread/flag/unflag only. Its callback
cannot bypass the separate single-message destination/confirmation workflow.
Durable bulk organization remains subsequent work.

## Intent, dispatch and restart

The existing `MailBulkFlagPlan`, runner, journal and receipt types retain their
public names for compatibility and now also accept Move/Delete. There is one
dispatch algorithm, not a second retry or background queue.

1. Freeze the source account/provider/folder, exact message identity, action,
   destination when moving, and displayed subject.
2. Commit that intent to the account-owned repository.
3. Commit an applying marker before invoking the provider.
4. Save the provider's confirmed, certified-no-effect failure, or uncertain
   outcome. Finalization retains any unattempted tail.

Failure to save intent or the applying marker prevents dispatch. A failure to
save a returned acknowledgement stops later work and preserves the live
outcome; the original owner may finish local receipt persistence once. It never
repeats the provider request. A crash after the applying marker but before a
durable acknowledgement recovers as uncertain.

Closing or disconnecting retires further dispatch and UI publication while the
original storage owner remains open long enough to save a late reply. A stale
destination popup or confirmation cannot act on a newer account/folder view.
Capability discovery cannot overlap or cancel an applying native command.

## Activity history and boundaries

**Mail activity** in the connected or cached account retains the action,
original subject, exact destination folder identifier for moves, and the
four outcome counts. English, German and Arabic history/details retain
readable controls at compact sizes and enlarged text.

A flag observation cannot establish where a moved message went, whether an
IMAP deletion marker caused a later purge, or how an opaque provider identity
changed. Move/Delete therefore do not offer **Check current status** through
the flag-recovery interface. The store and both host recovery entry points
reject that use before any observer call. Uncertain membership receipts stay
unresolved and protected from completed-history cleanup; they never replay.

Generic success does not identify a destination message or prove complete
membership. This increment deliberately retains cached browsing windows and
synchronized headers as their last dated observations, until an explicit
browse refresh or synchronization observes the provider again. It neither
invents destination rows nor deletes retained content, drafts or archive data.
The history view explains this boundary. Local cache storage is not encrypted
by this change.

## Storage compatibility

Schema 13 adds a nullable destination field to the existing command journal.
Older flag receipts retain a null destination. Move requires a different
same-account destination; other actions forbid one. Receipt restoration,
account rebinding, completion and quota checks preserve that identity exactly.
Migration from versions 1–12 is additive and transactional; failed upgrades
leave the old schema/data usable. Malformed action/destination combinations
are rejected instead of becoming executable intent.

## Qualification and next increments

The subsequent [membership recovery increment](membership-recovery.md) now
implements explicit provider-specific current-location checks with persisted
evidence. It preserves historical uncertainty and dated cache views. The
sequence below is the original plan; identity-transition capture and atomic
cache reconciliation remain the unfinished part of its first step.

The [local qualification record](../../validation/mail-durable-mutations-20261122/README.md)
records the remote intake, incremental checkpoints, source-bound native/Node
checks, process-kill recovery, localized UI review, environment limitations and
final reconciliation. Synthetic fixtures do not qualify live accounts or
installed macOS/Windows/mobile platforms.

The remaining sequence is:

1. Provider-specific membership observations and recovery: IMAP UIDVALIDITY,
   deletion flags and MOVE results; Gmail labels/trash; EWS changed IDs; Graph
   immutable IDs. Reconcile source/destination cache state without inventing
   identity or rewriting historical uncertainty.
2. Durable visible-selection move/archive/delete with destination preview,
   per-message outcomes and stop-after-current behavior.
3. Shared connected/multi-account navigation, preserving source coverage and
   account isolation.
4. Indexed body search, account-wide conversations, tags/categories and ordered
   rules with previews, built on the same durable operations.
5. Rich authoring, provider Drafts/Sent reconciliation, Calendar/People,
   security and installed/live-provider acceptance as separate milestones.

The comparison targets are complete workflows: [Outlook's rules](https://support.microsoft.com/en-us/outlook/mail/manage-email-messages-by-using-rules-in-outlook),
[Thunderbird's synchronization and offline boundaries](https://support.mozilla.org/en-US/kb/imap-synchronization),
and [eM Client's organization/authoring capabilities](https://www.emclient.com/features-email).
They inform the sequence; this increment does not claim full parity.
