# Mail implementation status

Updated **22 November 2026**. This page is the current summary. The detailed
change log and per-feature qualification record is preserved in
[Mail status details](status-details.md).

## Current state

The shared Dart/Flutter Mail module is used by CrispOffice Studio and the
CrispCloud host. Native IMAP, Exchange EWS, Gmail and Microsoft 365 accounts can
browse, synchronize headers, read cached bodies, compose, send and recover
interrupted work.

| Area | Status |
| --- | --- |
| Native IMAP/SMTP | Implemented; explicit foreground sync and resumable folder headers |
| Exchange EWS | Native mail/submission provider; live-server acceptance still open |
| Gmail / Microsoft 365 | Implemented through provider presets; live-account acceptance open |
| Offline store | Durable drafts, Outbox, cached headers/bodies, search journal |
| Scheduled send | Foreground only; UTC deadlines and a short Undo window |
| Search | Local cached headers and saved queries with exact account/folder scope and missing-folder recovery; no body/provider discovery |
| Conversations | Folding of explicitly loaded threaded headers |
| Compose tools | Signatures, Quick Text, attachments and draft recovery |
| Account persistence | Native account store, schema migrations and reconnect |
| Browser store | Implemented path; quota/reload/Web Locks acceptance remains open |

## Latest increment: unified retained-folder navigation

Cached mail now lists saved browsing windows and synchronized folders together
for the selected account. A folder appears once, keeps its two coverage sources
separate, and offers explicit source switching. Synchronized headers have bounded
100-row pages, local refresh and repair when membership changes remove the
displayed last page. Repository updates preserve a matching reader and reject
stale body results after folder, source, page or cleanup changes. EN/DE/AR
controls retain browse-only host compatibility.

See the [workflow and ownership contract](retained-folder-navigation.md) and
[fresh qualification record](../../validation/mail-retained-navigation-20261122/README.md).
This is one account's local navigation. Connected multi-account navigation and
durable move/delete remain subsequent work.

## Previous increment: saved-search folder sets

Studio can select exact local folders across accounts, persist/reopen the scope,
and display each folder's retained-header coverage. Missing folders remain in
the definition with explicit recovery; they never widen the query. Existing
all-folder definitions and published schema-11 definitions migrate compatibly
to schema 12. Scoped paging, refresh
and reader ownership retain identity and stale-operation guards. EN/DE/AR
controls include localized narrow-layout regressions.

**Locally qualified:** 503 core, 970 storage, 89 host/session and 70 UI/dialog
cases pass. The combined Word/Zotero integration and exact source evidence are
recorded in the linked qualification record.

See the [workflow and API contract](folder-saved-search.md) and the
[fresh local qualification record](../../validation/mail-folder-search-20261122/README.md).
Installed platforms, live providers and adoption of this new host UI in
CrispCloud remain separate acceptance work.

## Previous increment: keyboard triage and address search

Loaded mailbox lists now support growing and shrinking checked ranges with
Shift+Up/Down/Home/End, Shift+Space and Shift+click, with English, German and
Arabic help. Synchronized-view header search retains names and addresses for
every visible From/To/Cc entry.

**Locally qualified.** Fresh native runs passed 272 shared Mail UI cases and
176 Studio cases, including all 48 new regressions. All 23 changed Dart paths
pass strict analysis and formatting. The original executor outage and incomplete
Studio attempt remain in the record. See the [workflow](keyboard-triage.md),
[detailed status](status-details.md#range-selection-and-synchronized-address-search--locally-qualified)
and [work record](../../validation/mail-keyboard-triage-20261121/README.md).

## Mailbox

- Browse folders with a paginated, account-scoped header view.
- Synchronize one or more folders explicitly and resume from durable
  checkpoints.
- Read retained message bytes without contacting the provider again.
- Navigate saved browse windows and synchronized folders in one local catalog,
  with explicit coverage sources and paged synchronized headers.
- Mark read/unread and flagged state with recoverable foreground commands.
- Use Conversations for explicitly loaded threaded headers. Subjects alone
  never create a thread.
- Open attachments through the shared attachment workflow.

Search covered by the current implementation:

- local cached headers, including account/folder provenance;
- saved, named header searches with fixed account scopes and optional exact
  folder sets, per-folder coverage and missing-folder recovery;
- Boolean header expressions;
- explicit selection of a cached result to open retained bytes.

Search does **not** silently fetch bodies or contact providers.

## Composition and sending

- Multiple offline drafts per account.
- Frozen outgoing payloads and a durable Outbox.
- Reply/forward quoting and attachment retention.
- Per-account signatures with separate new/reply defaults.
- Named Quick Text insertions using the Word editor's undoable multiline path.
- **Send later** with fixed UTC deadlines, Pause, Resume and Send now.
- A short pre-submission Undo window for never-attempted queued mail.

Automatic sending requires an open Outbox and an active app. Closing,
suspension or changing accounts revokes permission. Failed or uncertain sends
never retry automatically.

## Accounts and credentials

The native account store retains provider settings, server identity and
credential references. Saved accounts can reconnect after relaunch when the
selected credential store is available. Manual edits during asynchronous
catalog work are preserved.

Credential storage follows the host:

- system keychain/credential store;
- encrypted file vault with a master password;
- session-only credentials.

A login prompt is not proof that saved credentials failed; the restore path
must distinguish loading from a genuinely absent account.

## Storage and recovery

`quds_mail_store` uses SQLite with additive migrations. It retains:

- mailbox pages and synchronization cursors;
- drafts and frozen Outbox payloads;
- saved searches and exact account/folder scope;
- local search indexes;
- recovery journals for interrupted read/flag work.

The current store is **not encrypted**. Process-kill tests do not establish
power-loss durability. Browser persistence and quota behavior remain unqualified.

## CrispCloud integration

CrispCloud embeds Mail as a cached workspace pane and reuses the shared engine.
It keeps the pane mounted while switching between Documents, Writer,
Spreadsheet and Presentation. A saved account restore shows a connecting view
rather than the login form.

Host-specific limits:

- remote images load only after explicit action;
- plain-text MIME is the default, with an HTML toggle;
- message bodies must not leak envelope headers or language-menu chrome;
- switching apps or windows must not discard the account or flash a login form.

## Known gaps

- Server-side or OS-background scheduled send.
- Provider Sent reconciliation after submission.
- Persistent account-wide conversation indexes and cross-folder discovery.
- Indexed body search and server-side discovery.
- Continuous refresh of shared saved views.
- A complete unified Mail workspace across every host.
- Live-provider, installed-platform and browser acceptance for new features.
- Full MailStore parity and encrypted local storage.

## Implementation map

| Package / area | Purpose |
| --- | --- |
| `packages/quds_mail_core` | Models, mailbox and command contracts |
| `packages/quds_mail_mime` | Portable MIME/EML codec |
| `packages/quds_mail_store` | SQLite persistence and recovery |
| `packages/quds_mail_transport` | IMAP, SMTP, EWS and cloud transports |
| `packages/quds_mail_ui` | Shared reader/composer widgets |
| `packages/quds_office_editor/example` | CrispOffice Studio host |

## Related documents

- [Mail roadmap](README.md)
- [Implementation plan](implementation-plan.md)
- [Durable sync](durable-sync.md)
- [Scheduled send](scheduled-send.md)
- [Saved searches](saved-searches.md)
- [Saved-search folder sets](folder-saved-search.md)
- [Unified retained-folder navigation](retained-folder-navigation.md)
- [Conversations](conversations.md)
- [Keyboard triage](keyboard-triage.md)
- [Compose tools](compose-tools.md)
- [CrispCloud integration](crispcloud-integration.md)

Qualification statements on this page are local unless a specific installed or
live-provider record is linked. Passing unit tests do not establish provider
interoperability or App Store acceptance.
