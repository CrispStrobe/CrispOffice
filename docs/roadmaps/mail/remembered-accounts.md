# Remembered IMAP/SMTP accounts

This M04W increment gives native Studio Mail a bounded account chooser backed
by the existing platform keychain. It removes the previous single remembered
account limitation while retaining explicit connections and account-scoped
local draft recovery.

## Everyday workflow

1. Open Mail. The last selected remembered account fills the setup form. No
   connection is started by loading or choosing an account.
2. Choose another remembered account, or choose **New account** to enter a new
   configuration. Press **Connect** when ready.
3. Leave **Remember account** enabled to save that account after a successful
   connection. Up to 20 accounts can be remembered. Updating a password for the
   same account replaces that record rather than adding another account.
4. While connected, choose **Switch account** to save the retained local draft
   and return to account setup. A draft-save failure keeps the current session
   available for recovery. Connect to the next account explicitly.
5. **Forget selected account** removes that account's remembered credentials.
   It does not remove another account, delete server mail, or delete the local
   drafts and independently saved archive messages.

English, German and Arabic labels cover the chooser, new-account action,
switching, selected-account removal and catalog failures. Existing single-record
credential-store embedders retain their supported injection interface.

## Identity, migration and failure behavior

The catalog is one versioned keychain record, limited in account count and
encoded size. Account identities exclude passwords. Endpoint and provider
settings distinguish accounts; case-sensitive login and address local parts
remain distinct. Password rotation does not strand an existing entry.

An existing v1 remembered account is migrated without removing the old record
before its replacement is durable. The v2 catalog remains authoritative even
when empty, preventing an old record from silently reappearing. Invalid or
unreadable catalogs are reported as failures; they are never treated as an
empty catalog that can be overwritten by a new save.

Keychain operations serialize across store instances. Selection and Forget
target an explicit saved account identity. Settings revisions and session
generations prevent delayed reads, selection writes and connection callbacks
from replacing a newer form or mailbox session. Keychain failure is visible;
the UI does not claim that a failed save or removal succeeded.

The established draft account fingerprint is unchanged. Draft ownership still
uses provider, incoming endpoint, login and sender. Switching closes the prior
draft store and restores only the new account's draft after connection.

## Scope and next work

This chooser covers native generic IMAP/SMTP and its existing Yahoo, iCloud
and Fastmail presets. EWS and cloud-provider dialogs retain their existing
authentication lifetime. This increment does not persist OAuth tokens, connect
several accounts simultaneously, or provide a unified/offline inbox.

The next M04W acceptance boundary is a repository-driven mailbox session:
persist account/folder context, page cached headers with stable ordering,
expose cached/offline/sync states, and reconcile supported mutations through
durable commands. Then add source-aware unified views, bulk triage and
account-wide search. The existing [ordered parity roadmap](README.md#desktop-mail-parity-ordered-increments)
keeps queued sending, automation, rich authoring and Calendar/People separate.

The [local work and verification record](../../validation/mail-accounts-20261120/README.md)
identifies the exact source, incoming branches, local tests and remaining
platform/provider qualification. Fixture tests do not establish live-provider
interoperability or installed-platform keychain behavior.
