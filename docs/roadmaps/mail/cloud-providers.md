# Gmail, Microsoft 365 and additional mail providers

Implemented for the native desktop Studio on 19 November 2026. Cloud accounts
use the Gmail API or Microsoft Graph with system-browser OAuth and PKCE. Existing
Exchange Server EWS and IMAP/SMTP accounts remain available. No relay is needed.

## Provider choices

| Studio entry | Connection | Foreground mail behavior |
| --- | --- | --- |
| Gmail | Gmail API, Google Desktop OAuth registration | Labels, paged headers, MIME bodies/attachments, read/unread, star/unstar, Trash, compose/reply/forward/send |
| Microsoft 365 / Outlook | Microsoft Graph, native public-client registration | Nested folders, paged headers, MIME bodies/attachments, read/unread, flags, moves, Deleted Items, compose/reply/forward/send |
| Exchange Server (EWS) | Explicit HTTPS endpoint, NTLMv2 by default | Direct on-premises Exchange; see [EWS guide](exchange-ews.md) |
| Yahoo Mail | IMAP 993 TLS, SMTP 465 TLS | Existing IMAP/SMTP workflow with an app password |
| iCloud Mail | IMAP 993 TLS, SMTP 587 required STARTTLS | Existing IMAP/SMTP workflow with an app-specific password |
| Fastmail | IMAP 993 TLS, SMTP 465 TLS | Existing IMAP/SMTP workflow with an app password and third-party-access plan |
| Other IMAP/SMTP | Secure discovery or manual settings | Existing generic account workflow |

Gmail labels are multiple memberships, not exclusive folders. The shared
`MailMove` operation lacks a source label, so Gmail does not advertise Move.
Read/star changes preserve unrelated labels; Trash is recoverable. Neither cloud
adapter permanently deletes messages. Shared/delegated mailboxes, remote draft
editing, label/folder creation, Calendar and contacts are outside this change.

The shared providers implement synchronization: Gmail initial pages plus history
catch-up and Microsoft Graph per-folder delta. Studio uses bounded foreground
browsing; this does not add background synchronization or a durable outbox.

## Google Gmail registration

1. Enable **Gmail API** in a Google Cloud project. Configure the OAuth consent
   screen for your intended internal/external audience and add test users while
   the application is in testing.
2. Create an OAuth client with application type **Desktop app**. A web client,
   API key or service-account key is not a substitute.
3. Open **Mail → Gmail** in Studio. Enter the mailbox and Desktop client ID. If
   the issued Desktop registration requires its optional client secret, enter
   that registration metadata in the optional field. Do not supply a server/web
   application's confidential secret.
4. Sign in in the system browser to the same mailbox and approve mail access.

The scope is `https://www.googleapis.com/auth/gmail.modify`, permitting reading,
sending and non-permanent changes. Google classifies it as restricted. The
deployment owner must satisfy the consent/verification rules for its audience;
Workspace policy may require administrator approval.

The desktop flow uses fresh state and S256 PKCE, with a random-port callback at
`http://127.0.0.1:<port>/oauth2/callback`. Tokens are exchanged only with Google's
fixed HTTPS endpoint. No Google password is entered in CrispOffice.

## Microsoft 365 / Outlook.com registration

1. Create an Entra application registration for the intended organizational
   and/or personal Microsoft account audience.
2. Add a **Mobile and desktop applications** platform with redirect
   **`http://localhost`**. Use a public/native registration, not an SPA or
   confidential web-client redirect. No client secret is used.
3. Grant delegated Graph **Mail.ReadWrite**, **Mail.Send**, and **User.Read**.
   Sign-in also requests **offline_access** for token refresh. Apply your
   tenant's user/admin-consent policy.
4. Open **Mail → Microsoft 365 / Outlook**. Enter the mailbox, client ID and
   tenant. The default `common` permits the account types allowed by the app
   registration. Use `organizations`, `consumers`, or a tenant identifier when
   required by your deployment.
5. Sign in in the system browser. The mailbox must match the address or principal
   returned by the authenticated profile.

The callback is `http://localhost:<random-port>/`; Microsoft's localhost redirect
matching ignores the port. The listener binds only to IPv4 loopback. The same
tenant is used for authorization and token redemption. MFA and consent stay in
the provider's browser page. Only Microsoft's global endpoints are configured;
national-cloud endpoints are not guessed.

The interactive helper supports Linux, macOS and Windows desktop registrations.
It returns typed unsupported on mobile/web. Native embedding hosts may supply
their own token source for other supported environments.

The macOS Studio release entitlement includes incoming network connections for
the ephemeral OAuth listener, matching the existing debug entitlement. The
implementation binds only to loopback and closes the listener on completion or
cancellation. Installed signing/sandbox acceptance remains a deployment check.

### Optional Microsoft task consent

The transport exposes `MailOAuthConfiguration(includeTasks: true, ...)` for
Microsoft registrations when a host explicitly enables To Do integration. It
adds delegated Graph `Tasks.ReadWrite` to the mail scopes and retains that scope
during refresh. The default remains mail-only. A host must run a new
authorization/consent flow; toggling configuration does not upgrade an existing
token or provision an Entra application permission by itself. Explicit token
responses missing the requested task scope are rejected.

This option is a public authorization boundary for the
[Tasks roadmap](../tasks/README.md). It does not add a Tasks screen, durable
credentials, background synchronization, or a tasks-only OAuth setup to the
current Studio mail dialog. Those are separate milestones.

### Preconfigure the client IDs

Both fields can be entered at setup or supplied to a desktop build:

```sh
flutter run \
  --dart-define=CRISPOFFICE_GOOGLE_CLIENT_ID=YOUR_DESKTOP_CLIENT_ID \
  --dart-define=CRISPOFFICE_MICROSOFT_CLIENT_ID=YOUR_APPLICATION_CLIENT_ID
```

These identify the deployment's own registrations. No client ID is invented or
provisioned by this change. Live acceptance requires real registrations and test
mailboxes.

## Yahoo, iCloud and Fastmail presets

Choose the named provider and use its app password. A separate primary login can
be entered when the visible address is an alias or custom-domain address.
Presets pin official hosts and TLS settings; they do not discover alternatives
or fall back to plaintext. Changing presets clears the previous password.

| Provider | IMAP host | SMTP host | Login notes |
| --- | --- | --- | --- |
| Yahoo | `imap.mail.yahoo.com` | `smtp.mail.yahoo.com` | Full primary address and generated app password |
| iCloud | `imap.mail.me.com` | `smtp.mail.me.com` | Short incoming username by default; explicit full-address fallback. SMTP uses the full primary address. |
| Fastmail | `imap.fastmail.com` | `smtp.fastmail.com` | Primary account and app password; Basic plans exclude third-party IMAP/SMTP |

Native IMAP/SMTP setup also has a **Remember account** option backed by the
platform's secure storage. It remembers the selected preset, primary login and
iCloud login mode together with the account credentials. Failed saves and
failed Forget operations are shown explicitly; a save failure does not close a
connected mailbox. This option does not persist cloud OAuth tokens, EWS
credentials, downloaded messages or unsent drafts. Actual installed keychain
integration still requires a deployment acceptance check.

## Shared API and lifecycle

Import `package:quds_mail_transport/quds_mail_transport.dart`. Create a host-owned
`MailAccountId` and `MailAccountSession`, then call `authorizeMailCloud` with
`MailOAuthConfiguration`, a current lease and an `openBrowser(Uri)` callback.
The callback opens the system browser; do not print or persist its authorization
URI in diagnostics. Pass the returned `MailCloudTokenSource` with
`MailCloudConfiguration` to `createMailCloudProvider`.

The result implements `MailProvider` and `MailSubmissionProvider`. On disconnect,
dispose/invalidate the account session, dispose the provider and separately
dispose its host-owned token source. Disposal is idempotent.

The built-in cloud token source keeps tokens in memory only. It refreshes before
expiry, coalesces simultaneous refreshes, adopts rotated refresh tokens
atomically, retains an omitted replacement and forgets revoked credentials. A
durable host can implement the token-source port using a platform vault. Cloud
tokens never enter ordinary account rows or logs. Closing the cloud dialog
forgets credentials, downloaded messages and unsent drafts.

Every operation verifies mailbox/profile ownership and the current lease before
mail IO. A profile 401 permits one refresh and one profile read. No send or
mutation is automatically replayed.

## Synchronization and failure handling

- Case-sensitive identities are scoped to host/profile/account/provider.
  Cursors additionally bind mailbox address, mailbox/label and purpose. Every
  returned cursor increments a local revision, including empty completed rounds.
- Gmail begins with a pre-snapshot history ID and catches up after listing.
  Pagination and bounded pending details preserve that checkpoint until a round
  completes. Label removals are membership tombstones, retaining other labels.
  Expired history requests a reset of that mailbox.
- Graph requests immutable IDs on every call and traverses nested folders under
  a count/request budget. Delta completes partial metadata before upserts.
  Continuations must retain the exact folder and collection, name `me` or the
  verified user, and stay on the fixed HTTPS Graph host.
- Defaults: 30-second operations, 256 HTTP requests, 100 records/page, 1,000
  folders, 48 MiB response bytes, 32 MiB encoded request bytes, 256 KiB header
  metadata and 16,000 cursor bytes. MIME obeys its separate `MailReadBudget`.
  Limits return typed failures, never a successful truncated prefix.
- Native HTTP owns both request and response-stream lifetimes. Cancellation,
  deadlines, silent/oversized streams and late responses release resources.
  Redirects never forward bearer tokens. Parsing and host failures are caught.
- Authentication, permissions, throttling, limits, conflicts and unavailable
  service have distinct `MailProblem` codes. Retry delays are returned when
  available and shown with fixed localized Studio feedback. Scheduling belongs
  to the host; failed operations do not start background retry loops.

Persist page data and cursors atomically with `MailSyncCoordinator` and
`commitSyncPage`. SQLite regressions check rollback, stale replay rejection and
cross-label preservation.

## Sending and diagnostics

Submission validates frozen MIME against the sender/recipient envelope and
rejects ambiguous duplicate, Resent, Sender or preexisting Bcc delivery headers.
Validated hidden recipients are added only to the submitted API MIME; prepared
bytes remain unchanged. No extra Sent-folder append is made.

Gmail returns a confirmed message response. Graph's empty HTTP 202 means accepted
for processing, not delivered. Definite rejections remain rejected. A possibly
accepted request followed by lost response, cancellation, timeout, malformed
acknowledgment or ambiguous server failure is **uncertain**. Studio retains the
immutable draft, including selected attachment bytes, in the current foreground
session and requires delivery-check acknowledgment before another attempt.
Disconnecting clears that session draft. There is no automatic resend, composer
autosave or durable Studio outbox integration.

Enable **Verbose diagnostics** during cloud setup for structured JSON events:
service, operation, stage, HTTP status, request count, duration, byte/item counts
and normalized error/retry fields. The type has no free-text field, excluding
tokens, OAuth state/codes/verifiers, URLs, addresses, IDs, subjects, bodies,
attachments and raw exception text. Sink failures cannot change results. Tests
check sentinel secrets and message content against emitted events.

## Read-only live probe

After dependency resolution and a real desktop registration:

```sh
cd packages/quds_mail_transport
dart run example/cloud_probe.dart gmail YOUR_CLIENT_ID you@example.com
dart run example/cloud_probe.dart microsoft365 YOUR_CLIENT_ID you@example.com common
```

The probe opens the browser, verifies the account, lists folder counts and reads
up to five headers. It never sends or modifies mail or prints message content.
It requests the same scopes as the full client. Optional Google Desktop metadata
may be provided in `CRISPOFFICE_GOOGLE_DESKTOP_CLIENT_SECRET`, never command
arguments. Ctrl+C cancels; exit discards tokens.

Local mocks, actual loopback callbacks, Node boundaries and widget tests do not
establish live provider or installed-desktop acceptance. No real registration or
mailbox credentials were supplied. See the [validation report](../../validation/mail-providers-20261119/README.md)
for exact tested sources, commands and results.

## Official references

- [Google desktop OAuth/PKCE](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes), [synchronization](https://developers.google.com/workspace/gmail/api/guides/sync), [sending](https://developers.google.com/workspace/gmail/api/guides/sending)
- [Microsoft authorization code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow), [redirect URI restrictions](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url)
- [Graph immutable IDs](https://learn.microsoft.com/en-us/graph/outlook-immutable-id), [delta](https://learn.microsoft.com/en-us/graph/delta-query-messages), [sendMail](https://learn.microsoft.com/en-us/graph/api/user-sendmail?view=graph-rest-1.0), [throttling](https://learn.microsoft.com/en-us/graph/throttling)
- [Apple settings](https://support.apple.com/en-ie/102525), [Yahoo settings](https://help.yahoo.com/kb/imap-settings-sln4075.html), [Fastmail settings](https://www.fastmail.help/hc/en-us/articles/1500000278342-Server-names-and-ports)
- [Apple network listener entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server)
