# Saved-search folder sets — 22 November 2026

Saved-header searches can now keep an explicit set of folders across verified
local accounts. Existing definitions continue to search all retained folders
inside their original account scope. This completes the next discovery
increment selected by the [desktop mail parity plan](README.md).

## User workflow

1. Open **Search saved mail** from the saved-account chooser.
2. Choose one account or all listed accounts, then **Choose folders…**.
3. Turn off **All folders in selected accounts** and check the desired folders.
   Folder names are grouped by account; the exact folder identifier is shown
   when it differs from the display name. Identically named folders remain
   separate choices.
4. Choose **Use this selection**, enter a query, and run **Search**. An empty
   query lists retained headers from the chosen folders.
5. Choose **Save search as…**. Reopening the saved definition runs its current
   query against the same account and folder identities.
6. Expand **Search coverage** for each selected folder's retained browse and
   synchronization counts/times, incomplete observations, and missing folders.

The folder chooser reads only local catalogs. A folder can be known locally
without having any retained headers or an update checkpoint. Connecting and
browsing/synchronizing remains a separate explicit workflow.

Choosing folders stops and releases an active search before reading its
catalog. Cancelling preserves the query and selected scope; run **Search**
again to populate results. Selecting an account scope explicitly resets the
folder choice to all folders within that new account scope. Selecting a fixed
folder set captures only the accounts represented by that set.

**Update saved search…** persists an edited selection with the existing
revision guard. Merely changing the picker does not modify a saved definition.
Deleting a saved search removes the definition, never its underlying mail.
English, German and Arabic labels, RTL and enlarged text are supported.

## Missing folders and recovery

An unavailable selected folder stays in the definition, in search coverage,
and as a checked unavailable row when the chooser reopens. Its last saved
display label is retained; its exact identity remains visible. This means
missing from the local catalog, not proof of deletion at the provider.

Search can show matches from the remaining selected folders, but coverage
stays incomplete and automatic refresh is disabled. If every selected folder
is missing, the result is empty with missing-folder feedback. It never becomes
an account-wide search.

The user can reconnect and restore the local catalog, or use **Choose folders…**
to uncheck the missing folder and choose its replacement. At least one folder
must remain in an explicit set. Switching to all folders is a separate explicit
choice. Use **Update saved search…** to retain the repair.

A missing account continues to block the fixed saved scope through the existing
account-directory checks. The user must explicitly select an available account
scope before changing that definition. A failed catalog read stays visible as
unknown availability; it is not presented as an empty successful catalog.

## Shared model and durable storage

`MailSavedHeaderSearchFolder` uses the exact pair `(accountId, mailboxId)`.
The account ID is the verified host-directory identity; the mailbox ID is the
provider-aware local catalog value. Display labels never resolve identity.
Mailbox whitespace remains significant. Controls, malformed UTF-16, excessive
lengths, duplicates and foreign account references are rejected.

`MailSavedHeaderSearch.folders` is immutable. Null preserves all-folder
semantics. An explicit list must contain 1–200 unique pairs and represent
exactly the definition's account IDs. The optional retained display label is
bounded to 4,096 UTF-16 code units; IDs retain the 1,024-unit boundary. Existing
query, name, account-count and whole-catalog metadata limits also apply.
`copyWith(allFolders: true)` is the explicit API for clearing a fixed folder set.

Schema **12** extends the independently published schema 11 with optional
retained display labels. The published `has_folder_scope` discriminator,
ordered folder identities, revisions and existing 200-folder limit are
preserved. Pre-folder-scope records still migrate as all folders. Updates,
folder replacement and scope clearing remain transactional. Monotonic revision
guards, profile retirement, count/type/byte preflight, quota and corruption
checks include the new rows. Drafts, Outbox, message bytes, memberships and
command journals retain their existing data.

The published `folderScopes` constructor/property/copy API and
`maxFolderScopes` remain available alongside `folders` and `maxFolders`.
Supplying both scope inputs is rejected. The legacy repository `folderIds`
argument retains its explicit unavailable result for missing folders; the
account-bound `mailboxIds` API reports missing-folder coverage with surviving
selected results. Both delegate to the same bounded query implementation.

## Query and lifecycle contract

`searchCachedHeaders(mailboxIds: ...)` filters both retained browse and sync
memberships before counting, scanning or paging. It returns only selected-folder
provenance and coverage. A stored message under two selected labels occurs once;
distinct stored messages with the same RFC Message-ID remain distinct.

Continuations bind the repository owner/revision, account, query and canonical
folder set. Reordering the same set is compatible; adding or removing a folder
rejects the old cursor. Changed repository data requires a replacement scan.
Existing limits remain 100 matches / 500 inspected candidates per Studio page,
with a 1,000-visible-result cap. Scope filtering does not bypass metadata or
candidate budgets.

`MailCachedHeaderSearchPage.missingMailboxIds` identifies exact selected IDs
absent from the current catalog. A known empty folder is not marked missing.
`listCachedSearchMailboxes` provides a bounded, validated catalog without reading
bodies or contacting providers.

Studio adds the optional `StudioMailFolderScopedHeaderSearchStore` capability.
An older custom adapter can continue all-folder searches; an explicit scope
returns unsupported rather than delegating to an unscoped query. Catalog
discovery owns one account store at a time, retains per-account errors, and caps
the complete chooser at 2,000 entries / 2 Mi UTF-16 metadata units. Failed close
retains ownership for an explicit retry before another store can open.

The published `StudioMailScopedHeaderSearchStore` string-ID port and session
`folderScopes` input remain compatible. The native adapter implements both
ports, rejecting ambiguous simultaneous inputs. Legacy adapters keep their
existing strict missing-folder contract; the active Studio UI uses the richer
typed scope and catalog capability. The earlier picker remains available to
existing direct consumers, while this route uses one canonical chooser.

Directory identity/revision and folder provenance are revalidated on pages.
Final scoped manual scans and staged refreshes recheck folder availability after
earlier account stores have closed. A later-page failure removes that account's
previously shown/staged hits; initially missing-only scopes retain healthy
selected-folder hits with incomplete coverage. Reader opening rejects a scoped
result whose observed folders are no longer locally available. Query, scope,
host, disposal and refresh generations continue fencing delayed operations.

## Qualification and next milestone

The [work record](../../validation/mail-folder-search-20261122/README.md)
records the exact source checkpoints, official runtime provenance, commands,
initial fixture/navigation failures and corrected local runs. It includes
model/store migrations and process-kill regressions, native host/session tests,
save/reopen/repair UI flows and localized narrow layouts. GitHub Actions are not
used as an acceptance dependency.

This remains retained-header discovery. It does not establish indexed body or
server search, continuously synchronized virtual folders, background account
work, installed-platform/live-provider acceptance, or this UI's integration
into another host. No new provider traffic or mail sending is introduced.

Next, complete repository-observed unified navigation and durable move/delete
with intent journaling, explicit provider capability boundaries and uncertain
outcome recovery. Then build broader categories/rules on those command and
scope contracts. Richer composition, provider Sent reconciliation, persistent
cross-folder conversations and Calendar/People remain parallel later milestones.

## Workflow references

Official product documentation checked 22 November 2026 informed the scope:

- [Thunderbird saved searches](https://support.mozilla.org/en-US/kb/using-saved-searches)
  documents choosing folders across accounts and separating virtual views from
  underlying messages.
- [Outlook Search Folders](https://support.microsoft.com/en-us/outlook/mail/use-search-folders-to-find-messages-or-other-outlook-items)
  describes virtual views and version-dependent search-folder criteria.
- [eM Client Search Folders](https://www.emclient.com/webdocumentation/en/10.0/emclient/Content/Favorite%20Folders/About%20Search%20Folders.htm)
  describes named reusable views and editable search properties.

These are workflow comparison references, not a claim of complete product parity.
The implementation and fixtures were authored independently in Quds.
