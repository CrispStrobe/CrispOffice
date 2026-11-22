# Account navigation with explicit sign-in

> **Initial increment and release-recovery continuation.** The canonical
> combined contract and current delivery order are in
> [Connected account navigation](connected-account-navigation.md), which also
> records atomic selected-record refresh and late-owner fences. This guide and
> its original development evidence remain linked for provenance. The incoming
> final qualification plan was prepared, not executed; it does not establish a
> final pass on the combined source.

## Everyday workflow

Use **Choose an account** from the Mail toolbar to browse accounts that have
previously connected successfully. The chooser includes IMAP/SMTP, Exchange EWS,
Gmail and Microsoft 365 identities. Each row shows the sender, provider, incoming
endpoint and login or tenant. The currently connected account is identified and
cannot be selected as a redundant transition. The chooser supports keyboard
selection, compact windows, and English, German and Arabic.

**Continue to sign in** selects a destination. Mail saves the retained current
draft, including any unresolved submission warning, and drains the previous
session's repository observers and store ownership. A failed draft save leaves
the old connected account and its recovery draft available. No provider mail is
moved or deleted by account navigation.

The destination opens its own setup. Press **Connect** or the provider's
browser sign-in button explicitly. Merely opening, refreshing or selecting an
account does not connect, synchronize, send, replay a journal operation, or open
its draft store. After sign-in, the established provider host restores the
account's existing drafts, Outbox and cached-mail access through the unchanged
account identity. This increment uses one connected account at a time.

EWS and cloud hosts return the next destination to the root Mail pane. A change
from EWS to Gmail, Microsoft 365 or IMAP replaces the previous provider route;
it does not accumulate connected dialogs. Close and Back on these hosts also
preserve a retained draft and wait for the account owner to drain.

Provider Close remains available while work is pending. It immediately stops
the remaining bulk sequence, and later draft-marker completions cannot start
a new send after that Close request, including when the retained-draft save
fails. Submissions already dispatched keep their existing outcome and
uncertainty handling.

## Sign-in data and routing

| Provider | Reused non-secret settings | Still required |
| --- | --- | --- |
| IMAP/SMTP | Exact incoming endpoint, socket mode, login and sender; a uniquely matching saved credential route may fill the form | Explicit Connect; complete SMTP settings or an explicit saved-route choice when multiple SMTP variants share the incoming identity |
| Exchange EWS | Exact HTTPS endpoint, domain, username and mailbox sender | Authentication method/password and explicit Connect |
| Gmail | Exact Gmail provider route and sender | OAuth client registration and explicit browser sign-in |
| Microsoft 365 | Exact Graph provider route, tenant and sender | OAuth client registration and explicit browser sign-in |

The existing local account directory contains no passwords, access tokens,
refresh tokens, SMTP route, EWS authentication method or OAuth client registration.
It is never treated as a substitute credential store. Existing provider setup
paths remain available for new accounts. The native **New account** action
explicitly clears a selected destination constraint.

Opening new Gmail, Microsoft 365 or EWS setup does not depend on completion of
the unrelated IMAP credential catalog. A late catalog result cannot overwrite
the active provider setup or trigger an IMAP connection behind it.

IMAP accounts that share an incoming draft identity but use different SMTP
routes remain distinct entries in the remembered sign-in chooser. When more
than one route matches, Mail leaves credentials and SMTP settings unselected,
explains the required choice, and does not pick a route by list order.

## Identity and ownership contract

`StudioMailAccountNavigationTarget` validates the existing
`MailLocalAccountRecord` and reconstructs its exact `StudioMailDraftAccount`.
The account fingerprint and existing draft/cache namespaces do not change.
The directory is bounded to 100 identities. Duplicate entries, invalid routing,
malformed structured login data, or a removed/revised destination are explicit
failures. A bad catalog is not treated as an empty account list.

Every selected destination carries its original identity and revision. The
picker rereads that record before returning it. Hosts revalidate after draft
persistence and during asynchronous connection setup. A mismatch in provider,
endpoint, login, tenant or sender prevents adoption of a different account.
Pending connection callbacks cannot continue into folder/header/store work
after the selected record becomes stale. A successful verified connection
fulfills the initial selection intent; a later explicit reconnect does not
reuse the obsolete directory revision from before that successful connection.
The combined continuation refreshes a selected native directory row only when
its expected saved record still matches inside the same transaction. Custom
directories without conditional refresh keep their existing metadata. See the
[current identity and recovery contract](connected-account-navigation.md#identity-ownership-and-recovery).

The selected shortcut's successful-connection refresh compares its identity,
revision and connection timestamp in the same repository transaction as the
write. A shortcut forgotten or replaced while sign-in waits cannot be recreated
by a late refresh. The selected connection intent is fulfilled only after that
comparison succeeds; revoked setup retains and drains any already acquired
owner and its observers. Custom directories without the optional atomic refresh
capability retain their existing metadata instead of falling back to an
unconditional write.

While a transition is pending, the underlying native Mail pane accepts neither
pointer nor keyboard edits. Each provider route can return a destination once,
and only while that exact route is current. Delayed or duplicate callbacks from
a closed route cannot dismiss or redirect a newer account's setup.

The old account's retained draft must save before retirement. Pending receipts,
mailbox observers and the draft/cache owner settle before the next host acquires
ownership. A failed owner release does not authorize a new target. Existing
provider session generations and leases continue to reject stale message,
folder, compose and mutation callbacks. Navigation introduces no background
execution policy or new database schema.

When native Mail cannot finish releasing the previous owner, it displays
**Retry closing account**. Connection, provider setup and local-account/draft
entry points stay blocked until release succeeds. Native Close is also blocked
while admission or owner cleanup is pending. Selected-target store admission
temporarily disables Disconnect so an unfinished store opener cannot be
abandoned in favor of another account. EWS and cloud Close retire the provider
before awaiting admission and keep the dialog alive until cleanup succeeds.
A failed late candidate close remains held for a separate explicit retry; the
same Close request cannot silently retry it and open the next route.

## Acceptance boundary and ordered continuation

This is cross-provider navigation with explicit reconnection. It does not
complete M04W, retain several simultaneous live sessions, provide a unified
inbox, synchronize provider Drafts/Sent, or qualify installed OS credentials and
live provider accounts. Completing the shared workspace still requires an
account-owned session coordinator with an explicit active/inactive lifecycle,
bounded connection retention, per-account folder/selection state, and an
account-aware unified view over repository observations. It must preserve the
ownership and no-replay guarantees established here.

Follow the [current ordered continuation](connected-account-navigation.md#comparison-targets-and-next-increments):
remembered Archive destinations, categories/rules, body/provider search,
persistent conversations and provider Drafts/Sent reconciliation, then fuller
background multi-account work. Rich authoring, Office attachments, Calendar/People
and platform qualification retain their broader roadmap dependencies.

The comparison targets support account-aware navigation and sending context.
Thunderbird documents [account and unified folder presentations](https://support.mozilla.org/en-US/kb/switching-folder-pane-view).
eM Client explains [default sending accounts and account ordering](https://www.emclient.com/faq-popular?search=default).
Outlook documents [the account used for new messages and replies](https://support.microsoft.com/en-us/outlook/change-the-account-used-to-send-email-messages).
These sources were checked on 22 November 2026; behavior differs between
product editions. They guide the workflow target and do not establish parity
for this increment.

The [initial qualification record](../../validation/mail-connected-navigation-20261122/README.md)
retains its actual development commands, source checkpoints and unexecuted final
plan. Use the [combined work record](../../validation/mail-account-workspace-20261122/README.md)
for subsequent integrated acceptance and source boundaries.
