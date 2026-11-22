# Account navigation with explicit sign-in

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
entry points stay blocked until release succeeds. Selected-target store admission
also temporarily disables Disconnect so an unfinished store opener cannot be
abandoned in favor of another account. EWS and cloud recovery retains the owner
behind their explicit Close path.

## Acceptance boundary and ordered continuation

This is cross-provider navigation with explicit reconnection. It does not
complete M04W, retain several simultaneous live sessions, provide a unified
inbox, synchronize provider Drafts/Sent, or qualify installed OS credentials and
live provider accounts. The next workspace increment should introduce an
account-owned session coordinator with an explicit active/inactive lifecycle,
bounded connection retention, per-account folder/selection state, and an
account-aware unified view over repository observations. It must preserve the
ownership and no-replay guarantees established here.

The remaining ordered product work is:

1. Retained multi-account sessions and the repository-driven unified workspace.
2. Remembered custom Archive destinations, then categories/tags and ordered
   rules with a preview and recoverable partial outcomes.
3. Indexed local body search, explicit provider-search coverage, and persistent
   cross-folder conversations.
4. Provider-side Drafts and Sent reconciliation, followed by account-owned
   background synchronization and sending.
5. Rich message alternatives, Office attachment editing, Calendar/People,
   encryption/signatures where supported, and installed/live-provider acceptance.

The comparison targets support account-aware navigation and sending context.
Thunderbird documents [account and unified folder presentations](https://support.mozilla.org/en-US/kb/switching-folder-pane-view).
eM Client explains [default sending accounts and account ordering](https://www.emclient.com/faq-popular?search=default).
Outlook documents [the account used for new messages and replies](https://support.microsoft.com/en-us/outlook/change-the-account-used-to-send-email-messages).
These sources were checked on 22 November 2026; behavior differs between
product editions. They guide the workflow target and do not establish parity
for this increment.

Actual source checkpoints, fresh local commands, results and remaining limits
are recorded in the [qualification record](../../validation/mail-connected-navigation-20261122/README.md).
