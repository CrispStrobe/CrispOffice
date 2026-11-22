# Remembered Archive destinations

This increment completes the custom-destination step after
[provider Archive](provider-archive.md) and
[connected account navigation](connected-account-navigation.md). It retains the
existing reviewed single-message and checked-selection commands and durable
per-message outcomes.

## User workflow

For a connected IMAP, Exchange EWS or Microsoft 365 account with Move support,
open **Archive destination** in the Mail toolbar. The control works without a
selected message, in an empty folder, and while viewing the chosen destination.
Choose an exact folder from a fresh provider catalog and **Save destination**.
Saving this preference moves no messages. **Clear saved destination** restores
the existing provider-default/manual-choice workflow; Cancel performs no write.

Each Archive action still reviews the account, source, count and exact target.
A saved custom destination takes precedence over discovery, and the host checks
its exact identity against a fresh folder catalog before showing confirmation.
Names, translated labels and similar paths never substitute for the saved ID.

| Account | With a saved custom folder | After clearing the preference |
| --- | --- | --- |
| IMAP | Revalidate the exact selectable same-account path, then review a durable Move | Discover the unique advertised ordinary Archive folder, or require an explicit choice |
| Exchange EWS | Revalidate the exact ordinary folder ID, then review a durable Move | Require an explicit destination for each action |
| Microsoft 365 | Revalidate the exact ordinary folder ID, then review a durable Move | Resolve the well-known ordinary Archive folder, or require an explicit choice |
| Gmail | This setting is not exposed or read | Keep the existing Inbox-label removal workflow; do not invent an Archive folder |

If a saved folder is missing or no longer a usable ordinary folder, Archive
stops and directs the user to change or clear the destination. It never silently
falls back to another folder. The settings dialog retains the missing ID for
repair. A catalog-read failure blocks saving a replacement but still permits
explicitly clearing a successfully loaded preference. Failed/conflicting saves
require a reload before retrying.

## Ownership and persistence

`MailArchiveDestinationSettings` and the optional
`MailArchiveSettingsRepository` port own one exact destination per durable
account. Studio uses the same non-secret provider/endpoint/login/sender identity
as drafts. Live provider account IDs are translated at the host boundary and
never persisted as the durable owner. Folder case and significant whitespace
remain exact; malformed Unicode, controls, foreign ownership and excessive
metadata are rejected.

Schema **17** adds account-owned metadata with transactional revision checks.
Clearing retains a new revision, so a stale dialog cannot recreate an older
choice. Settings survive restart, logout and cached-folder eviction; explicit
account/profile removal clears them. Quotas include the new metadata. The v17
migration preserves existing v16 Archive receipts and pending operations;
pre-v16 validation runs only for databases that actually predate that action.

The native draft owner serializes accepted settings operations with its other
writes and drains them before closing. Session-bound toolbar callbacks, late
catalog responses and dialogs cannot redirect a replacement account. After
Archive confirmation, the host reloads the preference and rejects a changed
revision/destination before constructing the durable command. Once an exact
Move intent exists, ordinary journal and provider uncertainty rules apply.

This local preference does not change server-side account settings, create
folders, add automatic rules, or authorize background moves. Cached mail stays
read-only. Clearing a preference does not move already archived messages back.

## Related lifecycle correction

The integrated EWS/Gmail/Graph Close path now starts observer cancellation before
waiting for a first cached-mail snapshot. It saves retained drafts first and
waits for late acquisitions and owner release before exiting. Failed draft saves
retain the connection; failed cancellation retains ownership for explicit retry.
This closes a locally reproduced wait cycle without replaying mail operations.

## Qualification and next milestones

The [work and local qualification record](../../validation/mail-remembered-archive-20261122/README.md)
records the original Archive source checkpoints, commands, observed results and
intake coverage. The [current integration record](../../validation/mail-account-workspace-20261122/README.md)
adds complete compose/Outbox receipt ownership and reconciles delayed account
admission without changing the saved-destination contract.
Deterministic local tests do not establish live-provider or installed-platform
release acceptance. GitHub Actions queue completion is not a dependency.

Continue with provider-aware categories/tags and ordered rules with preview and
durable outcomes; then indexed body/provider search, persistent conversations,
provider Drafts/Sent reconciliation and controlled multi-account background work.
Full Outlook, Thunderbird and eM Client parity remains a staged product goal.

Primary comparison references checked 22 November 2026:

- [Thunderbird Archive location settings](https://support.mozilla.org/en-US/kb/archived-messages).
- [Outlook Archive workflows and account differences](https://support.microsoft.com/en-us/outlook/mail/archive-in-outlook-for-windows).
- [eM Client mail workflows](https://www.emclient.com/features-email).

These are workflow references, not a claim of identical behavior across product
editions or of automatic archiving, local-folder filing or online-archive support.
