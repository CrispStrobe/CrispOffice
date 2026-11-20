# Remembered IMAP/SMTP accounts

This M04W increment gives native Studio Mail a bounded account chooser backed
by the explicitly selected credential store. It removes the previous single
remembered-account limitation while retaining explicit connections and
account-scoped local draft recovery.

## Everyday workflow

1. Open Mail. When the selected credential store is available, its last
   selected remembered account fills the setup form. Loading or choosing an
   account does not start a connection.
2. Choose another remembered account, or choose **New account** to enter a new
   configuration. Press **Connect** when ready.
3. Leave **Remember account** enabled to save that account after a successful
   connection. Each selected store's catalog holds up to 20 accounts.
   Updating a password for the same account replaces that record rather than
   adding another account. Session-only storage retains it only for the current
   app session.
4. While connected, choose **Switch account** to save the retained local draft
   and return to account setup. A draft-save failure keeps the current session
   available for recovery. Connect to the next account explicitly.
5. **Forget selected account** removes that account's remembered credentials.
   It does not remove another account, delete server mail, or delete the local
   drafts and independently saved archive messages.

Accounts sharing the same sender and IMAP host show their differing effective
logins, TLS settings or SMTP route. Hover or long-press a choice to inspect its
full sender, IMAP and SMTP logins, servers, ports and TLS modes. The same
description is available to assistive technology and identifies the selected
**Forget** target. Passwords and internal account IDs are never part of these
descriptions; provider presets display the routes they actually use.

English, German and Arabic labels cover the chooser, new-account action,
switching, selected-account removal and catalog failures. Existing single-record
credential-store embedders retain their supported injection interface. The new
credential-storage settings and menu labels currently remain English.

## Credential storage

**Credential storage** selects one backend: the system credential store, a
custom macOS keychain, an encrypted credential vault unlocked with a master
password, or session-only memory. The first three are persistent choices;
custom keychains require macOS. A locked or unavailable selected store reports
failure without silently falling back to another backend.

Session-only accounts intentionally disappear when the app process ends. The
non-secret storage-mode preference can survive a restart; it does not make
session credentials durable. Each backend has its own account catalog.
Changing storage neither copies accounts between stores nor deletes them from
their previous store.

Changing storage clears the previous account selection and Forget association
before reloading. The active connection and editable form remain intact; the
existing session/settings guards decide whether the new catalog may fill setup.
Storage changes are disabled during busy Mail operations, including initial
draft restore, connection attempts and pending credential operations. A backend initialized late remains owned by its original selection
and cannot replace the newly selected store's cached instance.

## Identity, migration and failure behavior

The catalog is one versioned record in the selected store, limited in account
count and encoded size. Account identities exclude passwords. Endpoint and
provider settings distinguish accounts; complete authentication logins and sending
addresses retain their exact case, while hostnames are normalized. Password
rotation does not strand an existing entry.

An existing v1 remembered account in the selected store is migrated only after
the complete v2 replacement has been written and read back exactly. Every v2
catalog write uses this readback check; failure is reported before migration
removes the legacy record. This verifies the selected backend's acknowledged
contents, not installed-OS durability, and session-only storage remains
temporary. The v2 catalog remains authoritative even when empty, preventing an
old record from silently reappearing. Invalid or unreadable catalogs are
reported as failures; they are never treated as an empty catalog that can be
overwritten by a new save.

Catalog operations serialize across store instances in the host isolate and
use one selected backend for each transaction. Selection and Forget target an
explicit saved account identity. Settings revisions and session generations
prevent delayed reads, selection writes and connection callbacks from replacing
a newer form or mailbox session. Storage failure is visible; the UI does not
claim that a failed save or removal succeeded.

The established draft account fingerprint is unchanged. Draft ownership still
uses provider, incoming endpoint, login and sender. Switching closes the prior
draft store and restores the connected identity's draft. Configurations that
differ only in SMTP settings continue to share that existing draft identity;
the new catalog does not silently introduce a different draft namespace.

## Scope and next work

This chooser covers native generic IMAP/SMTP and its existing Yahoo, iCloud
and Fastmail presets. EWS and cloud-provider dialogs retain their existing
authentication lifetime. This increment does not persist OAuth tokens, connect
several accounts simultaneously, or provide a unified/offline inbox.

Earlier status entries describe their original increments. This native
IMAP/SMTP chooser supersedes their statements that only one account could be
remembered or that persistent account switching was unavailable. Historical
validation remains tied to its own source.

The next M04W acceptance boundary is a repository-driven mailbox session:
persist mailbox/folder context beyond the selected sign-in, page cached headers
with stable ordering, expose cached/offline/sync states, and reconcile supported
mutations through durable commands. Then add source-aware unified views, bulk triage and
account-wide search. The existing [ordered parity roadmap](README.md#desktop-mail-parity-ordered-increments)
keeps queued sending, automation, rich authoring and Calendar/People separate.

The [local work and verification record](../../validation/mail-accounts-20261120/README.md)
identifies the exact source, incoming branches, local tests and remaining
platform/provider qualification. Fixture tests do not establish live-provider
interoperability or installed-OS packaging, keychain permissions/unlocking, or
encrypted-vault unlock and durability behavior.
