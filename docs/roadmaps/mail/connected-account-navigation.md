# Connected account navigation

## Delivered workflow

Studio offers one remembered-account chooser for native IMAP/SMTP, Exchange
EWS, Gmail and Microsoft 365. The bounded local catalog shows the provider,
mailbox and non-secret server/login details, with a current-account indicator
and English, German and Arabic controls. Choosing or refreshing the catalog
does not sign in, retrieve messages, or send mail.

Choose an account, then **Continue to sign in**. Studio saves the current draft
under its existing account, preserves any uncertain-submission warning, retires
the previous foreground session and opens the selected provider's setup. The
destination requires an explicit connection/sign-in action. Cancelling the
chooser leaves the current account in place; a draft-save failure prevents the
switch. Native **Close** still hides the mounted Mail pane as before; it does
not perform an account switch or destroy that pane's session.

| Provider | Exact route retained by the chooser | Sign-in boundary |
| --- | --- | --- |
| IMAP/SMTP | Incoming server scheme, host and port, login and sender | Reuse one matching existing saved sign-in when available; otherwise choose matching credentials or complete explicit server setup. The local directory does not contain the SMTP route or password. |
| Exchange EWS | HTTPS endpoint, domain/login and sender | Review those settings and sign in explicitly. |
| Gmail | Canonical Gmail API endpoint and mailbox identity | Explicit browser authorization with the required application registration. |
| Microsoft 365 | Canonical Graph endpoint, tenant and mailbox identity | Explicit browser authorization for the selected tenant/account. |

This increment supplies connected navigation in the Studio host. The complete
reusable `QudsMailWorkspace` milestone remains open.

## Identity, ownership and recovery

- Validate the entire catalog, including duplicate IDs, malformed records and
  the 100-record bound. Preserve exact account, provider, endpoint, login and
  sender identity; an edited or substituted route cannot silently connect as
  the selected account.
- Revalidate the selected record across sign-in and asynchronous draft-owner
  acquisition. A removed, replaced or revised shortcut requires a fresh
  selection. Stale provider completions and retired dialog callbacks cannot
  restore a previous account or open another route.
- Keep one active foreground account. Drain saved-mailbox observers, pending
  journal writes and draft-owner release before handing control to another
  provider. A late owner acquisition is fenced and released before another
  owner is admitted.
- Retain an observer or owner whose cancellation/close failed. An explicit
  release retry must finish that work before a new target can acquire ownership.
  Hidden pointer/keyboard input and duplicate or late route callbacks remain
  blocked while a handoff is pending.
- Apply that release boundary to ordinary Disconnect, Refresh and folder
  changes as well as account switching. Disconnect starts observer cancellation
  before waiting for draft restoration, so a pending initial saved-mail view
  cannot prevent cleanup. Storage ownership ends only after both have drained.
- Restore drafts, cached state, Outbox and historical uncertainty only through
  their owning account. Navigation never treats unknown delivery as success
  and never replays a send or mailbox command.
- Refresh a selected native directory record using an atomic comparison of the
  expected saved record inside the store transaction. A concurrent Forget or
  replacement cannot be undone by a late successful sign-in. The additive
  `expectedRecord` contract retains existing unconditional registration callers.
- Custom directories can opt into `StudioMailLocalAccountReconnectStore` for
  that conditional refresh. Without it, a successful reconnect leaves the
  existing directory metadata unchanged; a read followed by an unconditional
  write would not provide the required race protection.

If an observer or owner cannot finish closing, navigation/sign-in remains
blocked. Native **Retry closing account** makes the next release attempt
explicit; EWS/cloud Close and Back preserve the retained draft and release work.
The existing native Close action still hides its mounted pane. Recovery depends
on the host and owner implementation: a persistent close failure may require
restarting the host, and an in-session retry is not guaranteed to succeed.

## Scope and qualification

The chooser persists no new password, OAuth token or application secret. It
reuses the host's existing credential boundary. It does not add simultaneous
background accounts, a unified live Inbox, automatic account reconnection,
cross-account message mutation or a new background sending permission.

The [current work and qualification record](../../validation/mail-account-workspace-20261122/README.md)
records exact source checkpoints, executed tests, runtime provenance and
remaining acceptance gates. The focused coverage includes provider routing,
catalog conflicts, account replacement during sign-in, draft/uncertainty
preservation, observer cancellation, late owner acquisition and conditional
SQLite refresh. Shared Mail regressions and incoming Word work have separate
receipts. No final Studio test count is inferred from those other cohorts.

The [initial account-navigation guide](account-navigation.md) and
[development work record](../../validation/mail-connected-navigation-20261122/README.md)
are retained for provenance, including the incoming owner/observer release
continuation. Its final qualification plan was prepared without execution;
it is not a passing result for the current combined source.

Live-provider, installed-platform and full desktop-client acceptance remain
separate from deterministic local fixtures. GitHub Actions queue completion is
not used as a local qualification gate.

## Comparison targets and next increments

Primary product documentation checked 22 November 2026 establishes useful
workflow targets, rather than identical behavior across product editions:

| Reference workflow | Quds position after this increment |
| --- | --- |
| [Outlook adds and manages accounts through account settings](https://support.microsoft.com/en-us/outlook/getstarted/add-an-email-account-to-outlook-for-windows) | A shared remembered-account entry now reaches all four supported native provider setups with explicit sign-in. Full account/profile management remains broader work. |
| [Thunderbird offers account-folder and unified-folder views](https://support.mozilla.org/en-US/kb/switching-folder-pane-view) | Exact account navigation and retained-folder browsing are available. A live cross-account unified Inbox remains open. |
| [eM Client groups accounts and exposes a combined Inbox for a group](https://www.emclient.com/blog/declutter-your-sidebar-with-account-groups-821) | This increment handles one foreground account at a time. Account groups and concurrently maintained combined views remain open. |

Continue in this order, preserving an explicit user path and recovery contract
for every increment:

1. Remember custom Archive destinations with exact account/folder identity,
   explicit change/clear controls and missing-folder recovery.
2. Add categories/tags and ordered rules with a preview, provider capability
   checks and durable per-message outcomes.
3. Extend indexed body and provider search with visible coverage, bounded
   continuation and cancellation.
4. Persist conversations across folders and reconcile provider Drafts/Sent
   without weakening draft conflicts or uncertain-send recovery.
5. Extend the shared workspace to simultaneous account-owned background work,
   unified live folders and lifecycle/credential scheduling, followed by
   installed-platform and live-provider acceptance.
