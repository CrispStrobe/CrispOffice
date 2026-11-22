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
| Connected account navigation | Four-provider remembered-account chooser; exact non-secret routes, explicit sign-in and guarded foreground handoff |
| Browser store | Implemented path; quota/reload/Web Locks acceptance remains open |

## Latest increment: connected account navigation

Studio now offers one remembered-account chooser across IMAP/SMTP, Exchange
EWS, Gmail and Microsoft 365. It shows exact non-secret routes and opens the
selected provider's explicit sign-in flow. Selecting or refreshing an account
does not perform provider work. Current drafts and uncertain-submission state
remain under their owning account, and a failed draft save prevents the switch.

The foreground handoff drains cached observers, pending journal writes and
owners before opening the destination. Late owner acquisitions and retired
callbacks cannot restore the previous account. Native directory refresh compares
the selected record atomically, so a successful sign-in cannot recreate a
concurrently forgotten or replaced shortcut. Custom directories without that
conditional capability retain their existing metadata.

Native Close continues to hide the mounted Mail pane. Failed owner release
or observer cancellation blocks another sign-in. Native **Retry closing account**
and provider Close/Back preserve the retained release work for an explicit
recovery attempt; a persistent failure may still require a host restart.
Simultaneous background accounts, a unified live Inbox and new secret persistence
are outside this increment.

See the [workflow and continuation](connected-account-navigation.md) and
[current work and qualification record](../../validation/mail-account-workspace-20261122/README.md)
for actual source boundaries and executed acceptance gates. The next sequence is
remembered Archive destinations, categories/rules, body/provider search,
persistent conversations and provider Drafts/Sent reconciliation, then fuller
background multi-account work. M04W and complete desktop-client parity remain open.

The [initial account-navigation continuation](account-navigation.md) and its
development evidence are retained. Its prepared final qualification plan is
not evidence that the final suite ran or passed on this combined source.

## Previous increment: explicit provider Archive

Connected mailbox readers and checked selections now offer a reviewed Archive
action. Gmail removes only the exact message's Inbox label and requires an
explicit valid acknowledgement. IMAP resolves a unique selectable `\Archive`
folder; Microsoft 365 resolves the ordinary well-known Archive folder. EWS and
unavailable discovery require an explicit same-account destination. Folder-based
Archive reuses exact Move intent and identity receipts; Gmail uses a distinct
membership command in schema 16.

Account, folder generation, selected reader and frozen targets remain guarded
across asynchronous discovery and confirmation. Per-message outcomes survive
restart, uncertainty stops later dispatch, and fresh label observations preserve
the original uncertainty. Cached views remain read-only. The existing independent
archive-copy workflow remains available.

See the [provider behavior and continuation](provider-archive.md) and
[local qualification record](../../validation/mail-provider-archive-20261122/README.md).
Local acceptance passed 2,902 distinct Mail cases: 648 core, 612 transport,
1,138 storage, 325 Studio and 179 shared UI. The Studio and shared UI gates ran
again after the incoming Word/Zotero integration; Mail-owned core, transport and
store source remained unchanged. Another 510 incoming engine/editor behavior
cases passed. The qualification record separately retains an existing Word
visual-golden mismatch, reproduced on the pre-integration source with exactly
the same failing pixels.

Connected account navigation is continued above; full desktop parity and
live-provider/platform acceptance remain open.

## Previous increment: durable visible-selection Move/Delete

Connected mailbox lists now expose Move/Delete only for supported provider
actions. A confirmation shows selected count, account and source; Move requires
an explicit exact destination and a separate Apply action. Hosts freeze and
revalidate every selected identity across prompts, then use the existing durable
sequential coordinator. Per-message results, uncertainty, stop-after-current and
restart receipts remain available in Mail activity.

IMAP Delete marks `\Deleted` without expunge; EWS/Graph/Gmail retain their
existing trash semantics. Gmail never exposes folder-style Move. Cached views
remain read-only, and the shared list defaults to its prior four flag actions.
The [workflow and ordered continuation](bulk-organization.md) and
[local qualification record](../../validation/mail-bulk-organization-20261122/README.md)
define the implemented scope and validation status. This does not close M04W or
full desktop-client parity.

Local acceptance passed 257 focused widget cases, including 78 new regressions
and 81 real SQLite host cases. Changed Mail source and tests also passed pinned
formatting and strict analysis. The qualification record retains the exact
runtime, execution adapters, initial failures and remaining platform limits.

## Previous increment: authoritative move identities and atomic cache reconciliation

IMAP and EWS moves can retain the exact destination identities returned by the
server. Schema 15 saves those acknowledgements with the existing durable journal
and conditionally reconciles retained source/destination headers in the same
transaction. Stale local evidence, incompatible generations, identity conflicts
or cache limits preserve the receipt and require refresh.

The coordinator, bounded sync runner and Studio now carry a null-safe repository
snapshot so a page captured before a move cannot restore the old location,
including a first sync with no prior cursor. Provider cursor bytes remain intact.
Studio preserves stable account/canonical message IDs, and Mail activity shows
saved acknowledgement and cache status in English, German and Arabic.

See [the workflow, compatibility contract and continuation](identity-transitions.md)
and [the local qualification record](../../validation/mail-identity-reconciliation-20261122/README.md).
This increment covers IMAP/EWS Move identity evidence. Generic results, deletion
semantics, historical uncertainty and explicit connected-folder refresh remain.
New target headers do not acquire a fabricated cached body. Durable bulk
organization is continued above; complete desktop parity remains open.

## Previous increment: current-location recovery for uncertain Move/Delete

Connected Mail activity offers **Check current location** through a separate
read-only membership observer. IMAP checks the original folder generation and
deletion marker; Gmail records exact labels/Trash; Microsoft 365 and EWS inspect
the original identity's current parent and resolved Deleted Items folder.
Unavailable original IDs never establish a moved destination or historical
success. Opening cached activity performs no provider work.

Schema 14 stores a bounded, repeatable latest observation per uncertain item,
with timestamp and owner/revision/epoch/lease guards. The original command and
uncertainty remain unchanged and protected from cleanup; nothing is replayed.
Cached mailbox observations stay dated until explicit refresh or sync.

See the [workflow and ordered continuation](membership-recovery.md) and
[local qualification record](../../validation/mail-membership-recovery-20261122/README.md).
IMAP/EWS identity-transition capture and guarded cache reconciliation are now
continued above, followed by bulk organization and connected account navigation.

## Previous increment: durable foreground Move/Delete

Connected single-message Move/Delete now commits intent and an applying marker
before provider work, preserves exact destination identity, and keeps restart
receipts in Mail activity. Native IMAP gains capability-checked Move and Mark
deleted controls; EWS/Gmail/Microsoft 365 reuse their existing provider semantics.
Confirmed membership changes require a folder refresh. Interrupted outcomes do
not replay, and uncertain Move/Delete cannot be incorrectly resolved through a
read/flag observation. Schema 13 preserves earlier data with additive migration.

See the [workflow, boundaries and ordered continuation](durable-mutations.md)
and [local qualification record](../../validation/mail-durable-mutations-20261122/README.md).
Current-location evidence is continued above. Authoritative cache reconciliation,
bulk organization and connected account navigation are continued above.

## Previous increment: unified retained-folder navigation

Cached mail now lists saved browsing windows and synchronized folders together
for the selected account. A folder appears once, keeps its two coverage sources
separate, and offers explicit source switching. Synchronized headers have bounded
100-row pages, local refresh and repair when membership changes remove the
displayed last page. Repository updates preserve a matching reader and reject
stale body results after folder, source, page or cleanup changes. EN/DE/AR
controls retain browse-only host compatibility.

**Locally qualified:** 115 cases pass in one run on the combined Mail/Word/Zotero
source, including 64 new regressions. All seven changed Mail Dart files pass
strict analysis and formatting. Earlier host checks and incoming Office
qualification are recorded separately with their exact source bounds.

See the [workflow and ownership contract](retained-folder-navigation.md) and
[fresh qualification record](../../validation/mail-retained-navigation-20261122/README.md).
This is one account's local navigation. Connected multi-account navigation
remains subsequent work; durable single-message Move/Delete is continued above.

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
- Move or delete one connected message with durable intent and receipts;
  authoritative IMAP/EWS moves can update retained folder entries atomically.
  Connected views still require refresh; IMAP marks deleted without expunging.
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

The four-provider navigation directory retains verified non-secret identity
shortcuts. It requires a fresh selection when the chosen record changes during
sign-in and refreshes native records through an atomic expected-record check.
Opening that directory grants no connection authority and stores no new secrets.

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
- recovery journals for interrupted read/flag/move/delete work.

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
- Simultaneous background accounts and a live cross-account unified Inbox.
- Remembered custom Archive destinations and provider-aware categories/rules.
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
- [Connected account navigation](connected-account-navigation.md)
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
