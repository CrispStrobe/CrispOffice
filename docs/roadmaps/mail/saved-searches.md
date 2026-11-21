# Saved cached-header searches — 21 November 2026

## User workflow

Open **Search saved mail** from the native saved-account chooser. Select one
account or all listed accounts, enter a query, and choose **Save search as…**.
An empty query means all retained headers in the selected accounts. Give the
search a name; saving does not move or copy any messages.

The **Saved searches** chooser reopens a definition after an application
restart. Selecting it resolves its original account IDs against the current
verified directory and starts a fresh, bounded search. **Search** reruns the
current criteria; **Search more** continues the existing local snapshot.
Use **Update saved search…** to change the name, current query or explicitly
chosen account scope. **Save search as…** creates an independent definition.
**Delete saved search** removes only that definition after a confirmation;
messages, drafts, queued Outbox bytes and retained bodies remain available.

The native account directory implements the saved-search port automatically.
Custom hosts can supply `StudioMailSavedSearchStore` to the search dialog;
hosts without this capability retain their existing read-only search route.

## Scope and failure behavior

- Saving **All listed accounts** captures those exact account IDs. Accounts
  added later do not silently join a previously saved search.
- Definitions refer to accounts, not display names or RFC Message-ID values.
  A removed, redirected or provider-filtered account prevents that saved
  scope from running. Choose a new scope explicitly before updating it.
- Opening uses current directory identities and current local data; old
  directory revisions, result lists and continuation cursors are not saved.
- Changing a query or scope invalidates pending search/body work. Editing
  while a saved scope is being resolved also fences the old selection.
  Close drains pending persistence and account-resolution work.
- Concurrent edits compare the exact displayed revision. A conflict or a
  duplicate name cannot overwrite another definition. Reload the definitions
  and select the current one before editing again.
- A failed write/close can have an uncertain outcome. The UI asks the user to
  reload and inspect the current state rather than claiming success or that
  the previous definition necessarily survived.

Search still covers saved headers across retained browsed and synchronized
folder memberships. It reuses the existing Boolean grammar, account/folder
provenance, partial-coverage display, 100-result pages, 500-candidate page scans
and 1,000-visible-result cap. It does not query a provider, acquire credentials,
search message bodies or attachments, or download missing bodies. Explicitly
opening a result can read an already retained body through the same guarded
cached-mail session.

## Shared data and persistence contract

`quds_mail_core` exports immutable `MailSavedHeaderSearch` with a stable ID,
name, query, ordered account IDs and revision. Names admit at most 128 UTF-16
code units; IDs at most 1,024; scopes at most 100 distinct, nonempty IDs.
The existing header-query parser enforces its own bounded syntax. Names are
unique under Dart's locale-independent lowercase comparison; no accent folding
or Unicode normalization is implied.

The `MailSavedHeaderSearches` extension on `SqliteMailRepository` provides
`listSavedHeaderSearches`, `saveSavedHeaderSearch` and
`deleteSavedHeaderSearch`. A create uses revision zero and no expected revision.
An update supplies the original revision in both the record and
`expectedRevision`; a deletion also requires the original revision. The
repository returns the next persisted revision. The profile counter remains
monotonic across deletion/recreation so old callbacks cannot affect a new
definition that reused an ID.

Schema 9 is an additive transactional migration from schemas 1–8. Definitions
and ordered scope rows have their own tables in the host directory profile,
with a 100-definition ceiling and metadata budgets. Scope IDs intentionally
have no foreign key into that database's account table: each real mailbox
profile owns its separate store. Studio verifies those IDs through its native
account directory before a save and again before a search. Invalid stored
types, lengths, query syntax, revision counters or scope gaps fail explicitly
instead of silently replacing the catalog. Existing profile retirement also
clears its definitions.

## Qualification and remaining parity

The [work record](../../validation/mail-client-next-20261121/README.md) contains
the locally executed model, complete store/migration, native-host and Flutter
dialog results. Tests cover restart, fixed scope, forgotten/redirected accounts,
stale and concurrent updates, failed writes, pending-close behavior, and actual
message/draft/Outbox preservation after deletion. English, German and Arabic
controls are tested at enlarged text sizes.

This completes reusable saved queries over current retained mail. Continuous
subscription-driven refresh, arbitrary folder-set selection, persistent unified
navigation, indexed body search and provider-capability-gated server search
remain open. They should extend the same exact scope and revision contracts.

Primary comparator references checked on 21 November 2026:

- [Thunderbird saved searches](https://support.mozilla.org/en-US/kb/using-saved-searches).
- [Outlook Search Folders](https://support.microsoft.com/en-us/outlook/mail/use-search-folders-to-find-messages-or-other-outlook-items).
- [eM Client Search Folders](https://www.emclient.com/webdocumentation/en/10.0/emclient/Content/Favorite%20Folders/About%20Search%20Folders.htm).

Those products provide broader virtual-folder workflows. The completed Quds
increment refreshes explicitly over available local headers; it does not claim
continuous whole-mailbox parity.
