# Authoritative move identities and retained mailbox reconciliation

This increment continues [current-location recovery](membership-recovery.md).
A successful IMAP or Exchange EWS move can now preserve the destination identity
returned by the server. Its durable receipt can update exact retained source and
destination folder entries in the same local transaction. A location observation
and a mutation acknowledgement remain different kinds of evidence.

## User workflow

1. Connect an IMAP or EWS account and move a message with the existing explicit
   destination picker.
2. Open **Mail activity**. A move with authoritative identity evidence shows a
   **Saved move acknowledgement**, the original/destination folders, its saved
   time, and whether retained folder entries were updated.
3. Refresh or synchronize the connected folder to obtain current server
   contents and coverage. A move receipt does not establish a fresh full scan.
4. Reopen the account or use cached activity to read the same saved evidence
   without contacting the provider or repeating the operation.

English, German and Arabic activity views expose both projected and
refresh-required outcomes. The workflow retains the existing capability checks,
destination confirmation, durable applying marker, and conservative interruption
behavior. It does not add a copy command or change the meaning of Delete.

## Exact provider evidence

| Provider path | Accepted move evidence | Missing or invalid evidence |
| --- | --- | --- |
| Native IMAP | A single COPYUID response supplies destination UIDVALIDITY and the exact requested source UID paired with one destination UID; existing source-absence confirmation remains | Missing COPYUID preserves generic confirmed success without a mapping; malformed, duplicate, oversized, wildcard, extra-UID or mismatched evidence becomes uncertain |
| Native Exchange EWS | MoveItem requests new IDs, then verifies the returned exact replacement identity in the destination parent; verifies old-identity absence when the ID changed | A supported empty MoveItem response can retain generic success without a mapping after the existing confirmation; malformed or contradictory evidence remains uncertain |
| Microsoft 365 / Gmail | Existing unit-result mutation paths remain compatible | This increment does not manufacture Graph identity/parent or Gmail label transitions |
| Delete / IMAP deletion marker | Existing provider-specific behavior | No destination mapping is inferred from deletion or an unavailable old identity |

The vendored IMAP parser retains raw tagged and untagged COPYUID response codes
without letting a later completion overwrite earlier evidence. It recognizes
response-code atoms case-insensitively and preserves duplicates so the transport
can reject ambiguous mappings. The single-message parser never expands an
untrusted UID range.

EWS uses the original item's exact parent rather than treating an opaque item ID
as folder evidence. It requests metadata only while confirming a move. Subjects,
RFC Message-ID, search results and an absent old item never supply a guessed
replacement. Generic success without a mapping still requires refresh.

## Typed compatibility contract

`MailProvider.apply` remains available with its original unit result.
`MailMutationReceiptProvider.applyWithReceipt` is optional and returns a
`MailMutationReceipt` with an optional `MailMoveIdentityTransition`. A transition
binds the operation ID, source/destination remote identities, exact source and
destination mailbox IDs, and destination local message key. Account, provider,
folder, metadata-size and UTF-16 checks reject invalid evidence.

Confirmed `MailBulkFlagAttempt` and `MailBulkFlagItemResult` values carry the
transition through the existing shared sequential coordinator. Mismatched
command/source evidence becomes uncertain and stops later dispatch. Receipt
restoration rejects nonconfirmed or mismatched transitions. Older providers,
custom hosts and flag-only adapters keep their existing behavior.

Studio explicitly rebinds both identities and both folders from the connection
namespace into the stable repository account. It computes the same canonical
local ID used by browse captures and sync pages; a provider-local message ID is
not persisted as a Studio cache key. Late acknowledgements remain recordable by
the original active storage owner after the visible account/folder changes.

## Storage, projection and stale writers

Schema 15 adds `move_identity_transitions` and `mailbox_move_revisions` without
reinterpreting published schemas 1–14. Evidence is keyed by account, batch and
item; stored receipt metadata includes `recordedAt` and `cacheProjected`.
Account cleanup and history cleanup observe the existing ownership rules.

The applying-marker transaction captures the final local observation epoch.
On acknowledgement, the same journal transaction validates the frozen command,
retains its transition, and conditionally updates the cache. Any intervening
relevant local write retires projection authority, while the confirmed receipt
can still be saved. Finishing a previously saved item checks evidence equality
and never projects it twice.

Eligible projection requires existing source and destination browse views. It
removes only the exact source entry, compacts retained browse positions, adds the
authoritative target header to already-retained destination coverage, and
advances both browse revisions, even when the moved synchronized source was
outside the retained browse window. It also advances applicable sync revisions.
Existing target headers keep their newer metadata. Original capture/update
timestamps, continuation/completeness flags and provider cursor bytes are
preserved. No new complete folder catalog or synchronization checkpoint is
invented. Requiring both browse views conservatively leaves sync-only caches
unprojected until browse commits can carry their own persistent move fence.

Destination limits include the complete retained headers,
identities and synchronized folder metadata, including the folder display name.

Missing source/target coverage, mixed IMAP generations, identity collisions,
full destination windows, incompatible local state, revision exhaustion and
aggregate metadata limits prevent projection. The receipt states that folder
refresh is required. Optional cache projection runs in a required nested
savepoint: if cache growth alone exceeds the account quota, its changes roll
back while an otherwise admissible acknowledgement remains saved with
`cacheProjected: false`. Receipt quota failures and other storage errors still
roll back the outer transaction. A backwards wall-clock correction also rolls
back settlement rather than persisting a receipt whose recorded time exceeds
the batch update time. If storage cannot retain the acknowledgement, the live
report keeps it, but restart recovery remains uncertain; no command is replayed
to recover a lost mapping.

Original source message bytes and blob references remain under the original
identity. A newly created destination row is header-only until its body is
explicitly read/downloaded; an already cached destination body is preserved.
Normal later synchronization and cache cleanup retain their existing lifecycle.
The older unscoped repository FTS API can include both retained source and target
rows until cleanup; Studio's cached-header search is scoped to retained folder
membership. Drafts, Outbox payloads, archive records and credentials are outside
this operation.

### Null-safe synchronization fences

Provider cursor values alone cannot reject a page captured before a local move
when that move leaves the provider cursor unchanged. A separate persisted
mailbox move revision now fences those commits, including after restart or
cache cleanup/recreation.

`MailSyncSnapshotRepository` is an optional extension with an atomic
`readSyncSnapshot` and `commitSyncPageWithSnapshot`. Its
`MailSyncRepositorySnapshot` holds the mailbox, nullable provider cursor and
local revision. The coordinator, bounded runner and Studio adapter preserve that
capability. This also fences the first synchronization page when no provider
cursor exists yet; a fresh explicit run can then capture the new revision.

Legacy cursor-based callers can use the repository-only revision attached by
`readCursor`. Unstamped cursors denote revision zero and are refused after a
move changed that folder. Consumers that can encounter an absent cursor after a
move must adopt the optional snapshot contract. Provider cursor encoders ignore
this repository metadata; server cursor bytes and synchronization schedules do
not change.

## Qualification and remaining scope

The [local qualification record](../../validation/mail-identity-reconciliation-20261122/README.md)
contains source-bound commands, results, runtime provenance, remote checkpoints
and final reconciliation. Synthetic protocol tests, SQLite persistence tests and
Flutter fixtures qualify those local paths. They do not establish live account
interoperability, browser persistence or installed-platform release readiness.
Full Outlook, Thunderbird and eM Client parity remains open.

The next ordered implementation is durable visible-selection move/archive/delete:
freeze the visible identities and destination preview, preserve per-message
outcomes, stop after the current operation, and reuse this journal/recovery
contract. Extend authoritative provider membership receipts where appropriate;
never treat Gmail labels as exclusive folders or IMAP deletion markers as purge.
Then continue connected multi-account navigation, indexed body search and
cross-folder conversations, tags/categories and ordered rule previews, richer
composition, provider Drafts/Sent reconciliation, and live/platform qualification.

## Primary references checked on 22 November 2026

- [RFC 4315, UIDPLUS](https://www.rfc-editor.org/rfc/rfc4315.html): paired exact COPYUID sets and destination UIDVALIDITY.
- [RFC 6851, IMAP MOVE](https://www.rfc-editor.org/rfc/rfc6851.html): MOVE semantics and untagged COPYUID responses.
- [EWS MoveItem](https://learn.microsoft.com/en-us/exchange/client-developer/web-service-reference/moveitem-operation): returned new identities and cases without them.
- [EWS ReturnNewItemIds](https://learn.microsoft.com/en-us/exchange/client-developer/web-service-reference/returnnewitemids): explicit request for new item IDs.
- [Thunderbird synchronization](https://support.mozilla.org/en-US/kb/imap-synchronization): synchronized and offline workflows.
- [eM Client mail features](https://www.emclient.com/features-email): organization and authoring workflow targets.
- [New/classic Outlook comparison](https://support.microsoft.com/en-us/outlook/getstarted/feature-comparison-between-new-outlook-and-classic-outlook): track the two Outlook variants separately when assessing parity.
