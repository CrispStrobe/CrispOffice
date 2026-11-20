# Offline drafts for previously connected accounts

## What is available

Studio Mail now retains the non-secret identity of a successfully opened native
mail account. **Drafts for connected accounts** on connection setup lists these
accounts and opens their existing local draft catalog without authentication,
a provider connection, account discovery or sending.

This extends the [multiple-draft workflow](multiple-drafts.md) to autodiscovered
IMAP, on-premises Exchange EWS, Gmail and Microsoft 365. Explicit-server and
preset IMAP accounts work too; their older remembered-account **Local drafts**
entry remains available.

## Everyday use

1. Connect the account normally once after this increment. Its local draft
   catalog must open successfully before its verified identity is registered.
2. Disconnect, or restart Studio and open Mail. Choose **Drafts for connected
   accounts** before connecting. The main Mail setup shows all supported
   providers; the EWS and cloud setup surfaces filter to their own provider.
3. Select the provider and sender. Server endpoint and effective login are shown
   to distinguish custom ports, domains, tenants and similarly named accounts.
4. Create, resume, edit, save or delete local drafts with the existing chooser.
   Recipients, immutable attachments, reply headers and unresolved-send warnings
   remain attached to the original draft.
5. Close the local workspace and reconnect normally when ready to send. The
   local workspace is save-only: Send is disabled and refused in the action
   handler, and Queue in Outbox is unavailable.

Older installations cannot reconstruct missing discovery results safely. An
older autodiscovered, EWS or cloud account needs one successful reconnect to
create its shortcut. This does not move or replace its existing drafts. If no
accounts appear, the chooser explains this prerequisite.

**Remove from list** asks for confirmation and removes only the shortcut. It
does not delete drafts, Outbox entries, remembered credentials, server mail or
the account's local store. A later successful connection adds it again. A
reconnect invalidates an older removal confirmation even if the clock has not
advanced. Refresh the list before making another removal attempt.

## Identity and persistence

The directory stores provider, canonical endpoint, effective login, sender,
last successful connection time and a monotonic connection revision allocated
from a persistent profile counter. Removing and re-adding a shortcut cannot
reuse an older revision, including after process restart. It uses
the existing `StudioMailDraftAccount` fingerprint unchanged. For IMAP this
includes the resolved scheme, custom port and effective discovery login. EWS
retains its HTTPS endpoint, domain and user; Microsoft 365 retains its tenant
and mailbox. Case-sensitive login/sender components keep their historical
meaning. A stored record whose reconstructed fingerprint differs is refused.

The native directory has its own SQLite profile inside Studio's application
support directory. It is independent of the credential backend and the draft
profiles, and is available without unlocking credentials or obtaining an OAuth
token. Like the existing local draft store, these local files are **not
encrypted**. The chooser explains that account addresses and server settings
are saved locally; passwords, OAuth tokens and message content are not stored
in this directory. Clearing a credential backend does not clear these local
shortcuts or draft stores.

The additive shared-store migration advances schema v1/v2/v3 to v4. It creates
one directory table without changing existing account fingerprints, mail rows,
drafts, blobs, Outbox payloads, cached flags or search indexes. Migration and
registration failures roll back. Directory removal has no foreign-key cascade
to message content. Profile removal clears its directory rows as well.

The production adapter serializes short-lived native directory ownership. The
selected draft store remains exclusively owned until the offline workspace
finishes closing. Connected hosts also await a previous store close before
opening another one. Dialog and session guards reject stale asynchronous
callbacks; selection re-reads the directory before acquiring a draft store.

## Bounds and failure behavior

- At most 100 account shortcuts may be admitted. Existing accounts remain
  refreshable at capacity. Remove an unused shortcut, then reconnect the new
  account to register it. Each account retains the existing independent
  100-active-draft admission limit and paginated draft catalog.
- Metadata has bounded fields and host metadata budgets. Oversized or corrupt
  stored rows produce an explicit failure, never a silently empty directory.
- An existing account ID cannot be redirected to another endpoint/login/sender.
  Removal compares the full identity, timestamp and connection revision.
- A directory save failure shows a separate warning while leaving the connected
  mailbox and an already-open local draft usable. It cannot hide an
  interrupted-send warning or falsely promise an offline shortcut.
- Storage errors never substitute an in-memory production directory. Retry
  through Refresh or reconnect after the underlying storage problem is fixed.
- Hosts with custom draft storage opt in with a matching local-account store;
  they are not silently indexed into Studio's unrelated native storage.

## Qualification and remaining work

Tests cover persisted reopen for all four providers, exact account identity,
custom discovered ports/logins, successful-connection registration, no-provider
and no-authorization offline entry, uncertainty retention, save failure,
ownership, removal races, limits, corrupt records and additive migration
rollback. English, German and Arabic chooser layouts are checked at narrow
window sizes. See the [source-bound qualification record](../../validation/mail-offline-accounts-20261120/README.md)
for the accepted commands, counts, source hashes and retained diagnostics.

This is local composition access. It does not restore credentials or connected
sessions, show an offline inbox, synchronize provider Drafts folders, reconnect
automatically, send in the background, or manage the Outbox while offline.
Browser storage execution, installed platform packages and live-provider
interoperability still require separate qualification.

The next parity boundary is a repository-backed account/folder workspace with
durable synchronization commands and cached mailbox reads. Provider Drafts
synchronization can then reuse stable draft identities and explicit conflict
handling. Rich HTML, signatures/templates, durable undo-send and scheduling
remain separate ordered composition and sending increments.
