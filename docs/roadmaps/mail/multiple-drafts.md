# Multiple local drafts and offline composition

This increment advances recoverable composition in M07. It builds on the
existing durable draft and Outbox stores without changing provider transports,
account fingerprints or the Word body editor.

## Everyday use

In a connected IMAP/SMTP, Exchange EWS, Gmail or Microsoft 365 session, open
**Drafts**. The list shows each message's subject, recipients, attachment count
and any unresolved earlier-send warning. **New draft** creates another local
message; choosing a row resumes that message. **Compose** continues the draft
selected in the current session. Reply, Reply all and both Forward commands
create a separate draft when the production catalog is available, preserving
other unfinished messages.

The existing composer autosaves, reports storage failures and flushes on
**Save and close**. Recipient text can remain incomplete while editing. Each
draft retains its own reply headers, immutable file snapshots and uncertainty
state. Merely listing, selecting or reopening drafts never sends a message.

**Delete draft** names the selected message and asks for confirmation. Deleting
one draft retains the others. A draft with uncertain earlier submission has an
additional warning: deleting the local copy neither recalls a message nor
establishes whether it was delivered. Sending or queuing one draft moves only
that revision into the existing Outbox; its siblings remain editable.

## Offline entry

Before connecting, select a remembered IMAP account configured with explicit
servers or a supported provider preset, then choose **Local drafts**. The account
settings must still match the saved selection. Drafts can be created, reopened,
edited, saved and deleted without discovery, provider construction or a network
connection. Send is disabled and also refused by the composer action handler.
Close local drafts before connecting to send through the ordinary mailbox.

The local workspace holds the account's store lease until it finishes closing.
A pending open or close prevents a competing connection/account operation.
Callbacks remain bound to the original account, credential-backend revision,
draft ID and selection generation. A changed account or retired dialog cannot
redirect an old save into another message.

Historical autodiscovery records omit the exact discovered port and effective
login, so this increment does not guess an offline account fingerprint for
them. They still expose their drafts after reconnecting. Offline entry for
those accounts, EWS and cloud accounts needs durable verified connection and
session metadata in a subsequent increment. A locked credential backend can
also prevent selecting a remembered account. This is local draft access, not an
offline inbox or provider-side Drafts synchronization.

## Storage and recovery contract

- Preserve the existing `studio-foreground-compose` row. No destructive
  migration or account-key change is performed.
- Assign a new random ID to each new message and retain independent revision
  comparisons. Selection/deletion is pinned to account, ID and listed revision.
- Serialize writes and reject operations captured before a selection change,
  including A → B → A. Composer callbacks additionally check the captured
  selection generation before invoking storage.
- Keep revision tombstones after discard and Outbox transfer. An old editor
  cannot recreate content after that state change.
- Enforce at most 100 active drafts for new admission inside the same SQLite
  transaction as the write. Existing messages remain editable at capacity.
- List at most 100 metadata rows per page with explicit continuation. Existing
  externally created catalogs above the admission cap remain navigable.
  Listing does not resolve attachment blobs; opening a draft verifies them.
- Skip canonical cleared rows in SQL. Validate other metadata and report
  unsupported/corrupt content without silently replacing it.
- If the host cannot read the selection after closing the draft chooser, retire
  its store and selected snapshot before allowing another edit. A previous
  message must never be saved into an unknown newly selected ID.
- Preserve the existing attachment quotas and transactional blob collection.
  No password, access token or refresh token is stored in a draft.

Selection is a session state. Reopening a store retains the legacy Compose
behavior; all additional saved drafts are available through **Drafts**. Stored
mail remains local and unencrypted under the existing native store policy.
The saved indicator describes a completed write, not arbitrary power-loss or
installed-platform durability. Unsaved edits can still be lost if a process
ends before a save completes.

## Qualification and next work

The [source and local validation record](../../validation/mail-multiple-drafts-20261120/README.md)
records intake, incremental remote checkpoints, focused failure/recovery tests
and broader regression results. No GitHub Actions queue is required.

The next ordered boundaries are verified offline account metadata for the
remaining providers, repository-driven mailbox/folder streams and durable
commands, unified/offline inbox, provider-side draft synchronization, and the
remaining Outbox undo/scheduling workflows. [Outbox review and management](outbox-management.md) now adds atomic edit-copy, exact export and explicit uncertain closure. Rich HTML, signatures,
templates, conversations, full-account search, rules, Calendar/People and
installed/live-provider qualification remain open. This increment does not
claim M04W, all of M07 or full desktop-client parity.
