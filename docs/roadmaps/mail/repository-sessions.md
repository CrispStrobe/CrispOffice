# Repository-observed mailbox sessions

This increment connects the existing bounded cached folder views to foreground
Mail sessions. It advances M04W after [uncertain-action recovery](flag-recovery.md)
without changing the distinction between a saved browsing window and a fully
synchronized mailbox.

## User-visible behavior

Native IMAP, Exchange EWS, Gmail and Microsoft 365 continue to load their existing
50-message pages, up to the 1,000-header foreground limit. After a successful
save, the active folder observes its durable repository view. Confirmed journal
updates and later explicit flag observations can update the visible read/star
state without another provider fetch. The current message, loaded query and
selection remain open when only the same message's metadata changes.

**Cached mail** observes both the saved-folder catalog and the selected folder.
It updates retained headers and flags as local transactions commit. Its count
explicitly describes unread messages **in this saved view**, and separately
reports headers whose read status is unknown. It does not claim the server's
unread total. The labels are available in English, German and Arabic.

Opening a cached message remains credential-free. If flags change while its
body is loading, the body can still open when the account, folder and full
message identity remain selected. If the message or view disappears, that
selection and its reader are retired. A read failure retains the last valid
view with a visible error; a later valid repository event can recover it.

Switching folders or accounts clears the previous scope immediately. Closing
the workspace invalidates callbacks immediately, then waits for subscription
cancellation before releasing its shared draft/cache owner. A reconnect gets a
fresh session, even if it resolves to the same durable account identity.

## Repository contract

`MailCachedMailboxViews` now exports:

```dart
Stream<MailResult<MailCachedMailboxView?>> watchMailboxView(
  MailMailboxId mailbox,
);
Stream<MailResult<List<MailCachedMailboxSummary>>> watchMailboxViews(
  MailAccountId account, {
  int limit = maxMailboxViews,
});
```

These use the existing bounded `loadMailboxView` and `listMailboxViews` paths.
They emit an initial snapshot and later snapshots after successful domain
commits. They perform no provider requests, fetch no bodies and require no new
schema, dependencies or migration. Failed transactions do not publish a new
committed view. Read failures are typed events, not an empty mailbox.

Events coalesce while a read is in progress or a listener is paused. Cancellation
drains an in-flight read and suppresses its result. Active observers finish when
the repository closes; a new observer of a closed repository receives an
`unavailable` failure and finishes.

A missing view is distinct from a saved empty folder. Stored ordering,
`capturedAt`, revision and `hasMore` remain intact in each observation. A
successful flag journal transaction advances the view's compare-and-swap
revision while retaining its capture time and completeness. An unrelated
transaction may repeat the same view revision; it must not erase independent
foreground flag confirmations.

## Session and identity boundaries

The provider-neutral `StudioMailMailboxSession` owns one selected repository
subscription. Its states distinguish idle, loading, ready, missing, failed and
closed. Failed reads can retain the last good view; a different folder never
inherits it. Selection generations reject late callbacks, including A → B → A.
Asynchronous notifications are checked again at delivery, so an already queued
old snapshot cannot repopulate a switched or closed UI. Subscribers may safely
select another folder or close the session from a notification.

The session checks account, provider, folder, unique local and remote identities,
the 1,000-header bound, and a consistent IMAP UIDVALIDITY generation. Its highest
accepted revision survives an intervening missing-view event. This matches the
repository's existing monotonic revision counter across cleanup and recreation.

Connected sessions do not gain provider authority from cached IDs. The
`StudioMailMailboxCapture` bridge retains the exact original source records for
the last successfully saved window. It projects a repository update only when
the saved account/folder, revision, membership and remote identities
still match that window. Provider calls retain their original session-owned
identities, including IMAP UIDVALIDITY. Unsaved, failed, invalidated or older
windows cannot become action targets.

Foreground fetching remains available if local persistence or observation fails,
with the existing visible cache warning. The application does not present that
fallback as saved or synchronized. Injected one-shot stores retain their
existing behavior through the optional `StudioMailMailboxWatchStore` contract.

## Deliberate scope

This is the first repository-observed foreground session slice. It does not
close M04W or M06. In particular:

- The repository still holds bounded visited-folder windows, not a complete
  account synchronization snapshot or authoritative unread totals.
- Provider cursors and foreground fetch authority remain session-owned. This
  change does not create a background worker or silently replay commands.
- The Studio hosts consume the new session boundary; a complete reusable
  `QudsMailWorkspace` shared with CrispCloud/standalone Office remains open.
- Search remains scoped to loaded/saved headers. Account-wide search,
  conversations, a unified inbox and broader durable commands remain open.
- Native deterministic provider/storage tests do not establish live-provider,
  browser storage or installed desktop/mobile release acceptance.

## Next ordered acceptance boundaries

1. Connect foreground fetching to durable synchronization state: retain scoped
   cursors, reconcile provider resets/deletions and local pending work, and
   represent offline, synchronizing, authentication and capability failures.
   Qualify restart, interrupted paging and concurrent remote edits before
   enabling background work.
2. Add a repository query across selected accounts/folders, with stable
   pagination, explicit partial-cache coverage, deduplication and saved views.
   Build the unified inbox and conversations on that query boundary.
3. Extend durable command/recovery handling to move, archive and delete, with
   provider-specific identity handling and explicit conflict recovery.
4. Continue provider Drafts synchronization, durable undo-send/scheduling,
   rich composition, rules/categories, and Office attachment workflows in the
   [accepted implementation plan](implementation-plan.md).

These priorities retain the explicit feature-level comparison with
[Thunderbird synchronization](https://support.mozilla.org/en-US/kb/imap-synchronization),
[Microsoft's Outlook edition matrix](https://support.microsoft.com/en-us/outlook/getstarted/feature-comparison-between-new-outlook-and-classic-outlook),
and [eM Client email workflows](https://www.emclient.com/features-email), checked
21 November 2026. The products and provider editions have different capabilities;
the target is qualified workflows rather than an undifferentiated parity claim.

The [local work record](../../validation/mail-repository-sessions-20261121/README.md)
records remote checkpoints, incoming-work reconciliation and actual local
qualification. GitHub Actions queue time is not an acceptance dependency.
