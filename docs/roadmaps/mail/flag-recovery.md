# Checking uncertain mail actions

Native Studio Mail can explicitly check the current state of an interrupted
read/unread or flag/unflag action. This completes the historical-uncertainty
recovery step of the [command journal](command-journal.md). Repository-driven
sessions, background synchronization and broader mailbox commands remain the
next M04W boundaries.

## User workflow

1. Connect the account used for the original action and open **Mail activity**.
2. Open a completed receipt with an uncertain result and choose **Check current
   status**. Merely opening history does not contact the server.
3. Review the later observation and its time alongside the original outcome.
   **Stop checking**, closing the dialog or retiring the account prevents a
   late response from publishing a result.
4. Refresh the folder before another live change. The foreground list may have
   an older observation even when the stored activity has just been checked.

The original command is never resent. An observation can establish the state
at the time of the check; it cannot prove which action produced that state or
whether the earlier request succeeded. The original Confirmed, Failed,
Uncertain and Not attempted results, subjects and failure evidence remain
unchanged.

| Later observation | Meaning |
| --- | --- |
| Matches | The requested read/flag value was observed on the exact message. |
| Differs | The opposite value was observed. The app records it without retrying the action. |
| Message unavailable | The exact provider message identity was absent. This does not prove that a user deleted it or that it is absent under every other identity. |
| Folder reset/replaced | IMAP returned a different UIDVALIDITY. The old UID cannot identify a message in the new generation. |

Authentication, network, unsupported-operation, malformed-response and storage
errors keep the action unresolved. A stale account, receipt, cache or command
revision requires a new explicit check. Any earlier completed checks remain
saved. There is no automatic retry, resume or network work on reconnect.

**Cached mail** can display both original receipts and saved observations
without credentials, provider creation or message-body reads. It explains that
checking unresolved actions requires connecting the same account. The controls
and outcomes are available in English, German and Arabic.

## Fresh provider observations

The optional `MailFlagObserver` port leaves existing `MailProvider` consumers
compatible. Each call is bound to an account and a current operation lease.
It returns an exact identity with either observed flags, explicit absence, or
an invalidated IMAP generation. It never derives identity from a list position,
subject, RFC Message-ID or the currently loaded folder window.

| Provider | Read operation | Definitive unavailable result |
| --- | --- | --- |
| IMAP | Select the original folder, verify UIDVALIDITY, fetch the exact UID with bounded `BODY.PEEK` headers and explicit FLAGS | Empty exact-UID fetch, or changed UIDVALIDITY |
| Exchange EWS | `GetItem` with a narrow flag projection and explicit required flag fields | `ErrorItemNotFound` for that exact item |
| Gmail | Message GET with `format=minimal` and `fields=id,labelIds` | HTTP 404 from that message GET after account verification |
| Microsoft 365 | Graph message GET with `$select=id,isRead,isDraft,flag` | HTTP 404 from that message GET after account verification |

Responses with a mismatched identity or omitted required flag data fail closed.
HTTP 410, account-verification failure and transport errors do not establish
absence. Provider response budgets and existing credential/TLS boundaries
remain in force. The check uses no message-body, attachment, send or flag-write
operation. Browser factories return explicit unsupported results.

Primary protocol references: [Gmail messages.get](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/get),
[Gmail formats](https://developers.google.com/workspace/gmail/api/reference/rest/v1/Format),
[Graph Get message](https://learn.microsoft.com/en-us/graph/api/message-get?view=graph-rest-1.0),
and [EWS GetItem](https://learn.microsoft.com/en-us/exchange/client-developer/web-service-reference/getitem-operation).

## Persistence and concurrency

Schema v7 adds per-item observation evidence and a monotonic observation epoch.
Migrations retain existing versions 1–6, including uncertain receipts, drafts,
Outbox entries, cached messages and synchronization state. The original journal
tables and result meanings are preserved.

Before contacting the provider, the repository issues an opaque handle for one
completed, unresolved uncertain item. The handle binds the exact message,
account, batch revision, repository owner, lease and observation epoch. The
result transaction checks those bindings again, including immediately before
commit. Account lifecycle, cache, pending-command or journal writes advance the
epoch. This intentionally conservative fence may reject a check after an
unrelated write; a new explicit check is safe. Reopening storage or reusing a
retired lease cannot adopt an earlier handle.

A successful transaction stores one immutable observation, advances the receipt
revision, and updates only the requested read/flag bit of an existing known
cache snapshot. Unrelated bits and wholly unknown snapshots are preserved.
Affected cached-view revisions advance to reject an older writer. Missing or
replaced message identities do not remove cached messages, bodies or folders.
Storage failure rolls back the observation and its cache projection together.

The 100-unresolved-batch limit now counts only running or still-unchecked
uncertainty. Once every uncertain item has a definitive saved observation, a
completed receipt is eligible for ordinary bounded retention and explicitly
confirmed **Clear completed receipts**. Its historical action result is still
uncertain until the receipt is removed. Unchecked or running work is never
pruned to admit a new command. Observation metadata participates in the existing
account quota and corrupt-record checks.

## Qualification and next increments

The [local qualification record](../../validation/mail-flag-recovery-20261121/README.md)
binds the actual test results and visual checks to source hashes, and records
the incoming branch/PR audit and incremental remote checkpoints. Provider tests
use controlled protocol fixtures; native storage tests use Linux SQLite.
These checks do not establish live-account interoperability, installed
macOS/Windows/mobile acceptance, or browser persistence.

Continue in this order:

1. Drive foreground account/folder sessions from the durable repository, with
   explicit completeness, reconnect and synchronization ownership.
2. Add indexed account-wide/unified search, saved views and conversations.
3. Extend desired-state durability to archive/move/delete and broader bulk
   actions, then ordered rules with previews and recovery.
4. Continue signatures/templates, rich composition and Office attachment flows;
   scheduling, provider-side Drafts/Sent, Calendar/People and shared mailboxes
   retain their own provider and installed-platform acceptance gates.
