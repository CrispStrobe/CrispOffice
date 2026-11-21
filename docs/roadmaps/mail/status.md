# Mail implementation status

Updated **21 November 2026**. This page is the current summary. The detailed
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
| Search | Local cached headers and saved queries; no body/provider discovery |
| Conversations | Folding of explicitly loaded threaded headers |
| Compose tools | Signatures, Quick Text, attachments and draft recovery |
| Account persistence | Native account store, schema migrations and reconnect |
| Browser store | Implemented path; quota/reload/Web Locks acceptance remains open |

## Mailbox

- Browse folders with a paginated, account-scoped header view.
- Synchronize one or more folders explicitly and resume from durable
  checkpoints.
- Read retained message bytes without contacting the provider again.
- Mark read/unread and flagged state with recoverable foreground commands.
- Use Conversations for explicitly loaded threaded headers. Subjects alone
  never create a thread.
- Open attachments through the shared attachment workflow.
- Extend or contract checked visible ranges with Shift+arrow/Home/End/Space
  or Shift+click; independent checks and bulk-action boundaries are preserved.

Search covered by the current implementation:

- local cached headers, including account/folder provenance;
- saved, named header searches with fixed account scopes;
- Boolean header expressions and visible From/To/Cc names and addresses;
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
- saved searches and account scope;
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
- [Conversations](conversations.md)
- [Keyboard and range triage](keyboard-triage.md)
- [Compose tools](compose-tools.md)
- [CrispCloud integration](crispcloud-integration.md)

Qualification statements on this page are local unless a specific installed or
live-provider record is linked. Passing unit tests do not establish provider
interoperability or App Store acceptance.
