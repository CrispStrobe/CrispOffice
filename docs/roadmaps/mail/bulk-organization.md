# Durable organization of selected messages

This continuation builds on [authoritative move identities](identity-transitions.md)
and the existing [foreground command journal](command-journal.md). Connected
mailboxes can now move or delete a checked selection through the same durable,
sequential command pipeline as single-message organization.

## User workflow

1. Connect an account and check the messages to organize. Range selection,
   filtering, sorting and conversation folding retain the shared list's
   visible-selection rules. Hidden, collapsed and unloaded rows are excluded.
2. Open **Actions for selected messages** and choose an available **Move…** or **Delete…**
   action. The connected provider determines which choices are available.
3. Review the selected count, account and exact source folder. For Move, select
   an observed destination in that same account, review its name and identifier,
   then press **Move**. Selecting a destination alone does not
   start work. Cancel performs no provider write and creates no journal intent.
4. Inspect per-message results and, if needed, **Stop after current message**.
   Completed messages keep their results; the remaining selection is unattempted.
5. Refresh the folder after any confirmed organization or uncertain result.
   **Mail activity** retains the durable batch and any authoritative move
   acknowledgements across reopening. Reopening never repeats an action.

The confirmation dialogs provide English, German and Arabic copy, explicit
provider-specific deletion wording, scrollable content and independent Apply
controls. Selection remains separate from the currently opened reader. A reader
for an unrelated message remains open after organizing other rows.

## Provider behavior

| Connected provider | Move | Delete |
| --- | --- | --- |
| IMAP | Requires advertised MOVE support; exact source UIDVALIDITY/UIDs and an observed same-account destination | Marks each selected UID `\Deleted`; leaves rows until refreshed; never EXPUNGE or CLOSE |
| Exchange EWS | Existing MoveItem path, including authoritative replacement identities when supplied | Existing Deleted Items behavior |
| Microsoft 365 / Graph | Existing move path with the provider's identity checks | Existing Deleted Items behavior |
| Gmail | Folder-style Move is unavailable, even if a custom adapter advertises it incorrectly | Existing Trash operation |
| Cached/offline views | Unavailable | Unavailable |

IMAP organization capabilities are observed during connection and non-pagination
folder refresh, then checked again before confirmation. If optional capability
discovery fails, mail reading remains usable and bulk organization stays hidden
until a later successful check. Existing explicit reader actions can also retry
the capability check.

## Selection and lifecycle guarantees

The shared `MailMessageList.supportedBulkActions` set is copied and immutable.
Its default remains the four established read/unread/flag/unflag actions, so
existing embedding hosts acquire no organization commands implicitly. Hosts
opt in to Move/Delete through the existing `onBulkAction` callback and supply
localized labels. Cached hosts continue omitting the callback.

The list freezes the checked visible IDs in visible order when the action menu
opens. Host updates and scope/selection/projection changes invalidate pending
menu callbacks. Action availability is checked again before invocation. Each
connected host then freezes the exact local and remote identities before any
capability or confirmation await and rechecks the whole selection afterward.
Account, provider session, source folder, UID generation, repository ownership
and removed/replaced targets cannot silently change a confirmed operation.

Native adapters that implement organization without the legacy flag setters
can expose only Move/Delete. The shared widget still creates no provider,
credentials, database or transport session.

## Persistence, partial results and recovery

The existing `MailBulkFlagPlan` supports 1–1,000 unique identities from one
observed account/provider/mailbox. Move requires one different destination in
that account. The historic API names remain compatible; no new database schema
or parallel dispatch engine is introduced by this continuation.

The native command owner commits the complete plan before dispatch, then saves
an applying marker before each provider call. Each settled result is retained
before the next message starts. Authoritative IMAP/EWS move identities pass
through the existing transactional receipt and guarded cache-projection path.
Generic provider confirmations remain usable without inventing destination IDs.

Definite failures are reported separately from unknown effects. A definitely
rejected message can leave the rest of the batch eligible; uncertainty, rate
limiting, stale scope, cancellation or a persistence failure stops later dispatch.
Stop never claims to cancel a request already accepted by a provider. A crash
or missing result write leaves the applying marker uncertain after recovery.
The live report can retain a confirmed provider acknowledgement even when its
local receipt write failed; the durable record then correctly remains uncertain.

Loaded rows remain stable while the coordinator checks the frozen selection.
Confirmed moves/trash outcomes are projected after the run completes. IMAP
Deleted flags preserve read/flag observations and do not expunge rows. A cached
subscription is retired before organization so stale cache events cannot restore
removed rows. Folder coverage stays dated until an explicit refresh or sync.

## Qualification and next increments

The [work and local validation record](../../validation/mail-bulk-organization-20261122/README.md)
identifies the exact source, captured remote histories, checks, failures and
remaining environment/provider limits. Test source alone is not an execution
claim. No GitHub Actions queue is an acceptance dependency.

The ordered next steps are:

1. A shared connected workspace with coordinated account/folder navigation and
   repository-observed views, preserving these exact identity and command rules.
2. Explicit special-folder discovery and Archive, then tags/categories and
   ordered rule execution with preview and the same durable result handling.
3. Indexed body/provider search and persistent cross-folder conversations, with
   visible coverage and stable actions against original message identities.
4. Provider-side Drafts/Sent reconciliation, controlled background scheduling,
   richer authoring and Office attachment workflows.

Full Outlook, Thunderbird and eM Client parity remains the long-term product
goal. This increment completes visible-selection Move/Delete; it does not imply
server rules, offline mutation queues, background execution, live-provider
interoperability or installed-platform release qualification. Comparison sources
reviewed for the continuation: [Thunderbird filters](https://support.mozilla.org/en-US/kb/organize-your-messages-using-filters),
[Thunderbird quick filters](https://support.mozilla.org/en-US/kb/quick-filter-toolbar),
[eM Client email features](https://www.emclient.com/features-email), and
[Outlook edition comparison](https://support.microsoft.com/en-us/outlook/getstarted/feature-comparison-between-new-outlook-and-classic-outlook).
