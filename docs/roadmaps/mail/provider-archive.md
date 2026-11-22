# Explicit Archive in connected mail

This increment adds single-message and checked-selection **Archive** to the
connected mailbox. It builds on [durable bulk organization](bulk-organization.md)
and uses the same frozen identities, durable dispatch markers, sequential
execution and recovery history. It is separate from saving an independent copy
in the [local mail archive](archive-search.md).

## Provider behavior

| Provider | Archive behavior | Destination review |
| --- | --- | --- |
| Gmail | Remove only the message's `INBOX` label. Preserve other labels, read/flag state and message content. Available for the exact connected Inbox view. | Confirm the selected count, account, source and label-removal semantics. There is no invented Archive label and no folder-style Move. |
| IMAP | Move to the unique selectable folder advertised with the RFC 6154 `\\Archive` attribute. Requires the existing MOVE capability. | Show the exact returned folder ID. If authoritative discovery is unavailable or ambiguous, require an explicitly selected same-account destination. Never infer a folder from its display name or `\\All`. |
| Microsoft 365 | Resolve the ordinary well-known `archive` folder, then move to its exact ID. | Review the resolved folder before durable intent. A missing ordinary Archive folder permits explicit folder selection. This does not target an Exchange Online archive mailbox. |
| Exchange EWS | Move to an explicitly selected folder from the connected same-account catalog. | Always require folder selection. EWS online-archive distinguished IDs are not substituted for an ordinary Archive destination. |

Both a selected reader and checked visible rows use the same confirmation path.
The count, account and source remain visible. Folder selection and confirmation
perform no message mutation. Resolved folder IDs remain authoritative even when
the displayed folder catalog is older. An already-selected Archive folder is
reported as such rather than receiving a same-folder move.

The current increment does not remember a custom Archive destination; selecting
one is explicit for each operation. It does not create folders automatically.
Cached views remain read-only.

## Identity, persistence and recovery

Before discovery or a dialog, the host freezes the exact observed message
identities. Account, provider, folder generation, selected reader and every
target are checked again before dispatch. A late resolver response or changed
selection cannot authorize a command in a different context.

Folder Archive becomes an ordinary durable `move` plan with its exact destination;
Mail activity consequently records that move and its destination. IMAP/EWS
authoritative replacement identities and conditional cache projection retain the
existing [identity-transition contract](identity-transitions.md). Graph retains
its existing move acknowledgement behavior.

Gmail uses a distinct `MailArchive` operation and `archive` journal action. The
foreground plan admits only Gmail's exact `INBOX` source and no destination.
The provider sends only `removeLabelIds: ['INBOX']`; it must receive the same
message ID and an explicit valid label array without Inbox before confirming.
Missing, malformed or contradictory acknowledgement metadata remains uncertain
after a possible write.

Schema 16 admits this new persisted command through a transactional,
validation-only migration. Earlier tables, drafts, Outbox payloads and receipts
are preserved. An older database containing unexplained Archive intent is
rejected before migration commits. The newer version also prevents older clients
from interpreting the new action as an existing flag command.

Per-message outcomes remain confirmed, failed, uncertain or unattempted. An
uncertain result stops further dispatch, survives restart and is protected from
cleanup; there is no automatic retry. **Check current location** can record fresh
Gmail label evidence without declaring that the earlier Archive succeeded.
Read/flag checks cannot resolve a membership command.

A generic Gmail acknowledgement does not rewrite retained folder memberships or
invent a fresh cache snapshot. Connected views require an explicit refresh, and
saved views retain their observation dates until refreshed or synchronized.

## Acceptance and remaining parity work

The [local work and qualification record](../../validation/mail-provider-archive-20261122/README.md)
contains the source checkpoints, actual test commands and final publication
receipt. Test source alone is not a passing execution claim. GitHub Actions queue
time is not an acceptance dependency.

This completes an explicit organization workflow. Connected multi-account
navigation remains the next M04W workspace boundary. Subsequent increments include
remembered Archive destinations, tags/categories, previewable ordered rules,
indexed retained-body/provider search, persistent cross-folder conversations,
provider-side Drafts/Sent reconciliation and controlled background execution.
Live-provider and installed-platform qualification remain separate acceptance
gates; full Outlook, Thunderbird or eM Client parity is not claimed.

## Protocol references

Primary references checked 22 November 2026:

- [Gmail message label modification](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/modify).
- [IMAP special-use mailbox attributes, RFC 6154](https://www.rfc-editor.org/rfc/rfc6154.html).
- [Microsoft Graph ordinary Archive folder](https://learn.microsoft.com/en-us/graph/api/resources/mailfolder?view=graph-rest-1.0).
- [EWS distinguished folder IDs](https://learn.microsoft.com/en-us/exchange/client-developer/web-service-reference/distinguishedfolderid-distinguishedfolderidnametype).
