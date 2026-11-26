# Exchange Server EWS — on-premises priority

The 19 November 2026 scope adds EWS to the existing Quds mail boundary. Exchange
Server is the primary target. CrispOffice now uses the transport for native
Mail, Tasks, and read-only Calendar access. Microsoft cloud work uses Graph.

## Connect

In the native Office Studio Mail screen, choose **Exchange Server (EWS)**.
Supply the EWS HTTPS URL, mailbox email, and login. The normal endpoint is
`https://mail.example.com/EWS/Exchange.asmx`; a different administrator-supplied
path or port is allowed. Login can be `DOMAIN\user` or a UPN. The mailbox SMTP
address is separate from the login, including for explicitly delegated folders.

NTLMv2 is the default. Basic over verified HTTPS is an explicit alternative for
servers where it is enabled. The provider also accepts a current bearer token
from the host vault, including an on-premises AD FS deployment; token acquisition,
refresh and authorization UI belong to that host. No Entra tenant, Microsoft 365
account, Graph endpoint, IMAP/SMTP service or hosted Quds relay is required for
the default on-premises path.

The Studio host keeps its credentials and draft in memory for the foreground
session. It does not yet persist these through the durable mail repository or
provide an OS credential vault. The shared provider supports those host-owned
ports independently. Closing the session invalidates pending work.

For a read-only endpoint check, after resolving the workspace with the pinned
Flutter SDK, run from `packages/quds_mail_transport`:

```sh
dart run example/ews_probe.dart \
  https://mail.example.com/EWS/Exchange.asmx 'DOMAIN\user' user@example.com
```

The probe prompts for the password without terminal echo, checks Inbox access,
lists mail folders, and reads at most ten header changes in one folder. It logs
counts and fixed problem codes rather than credentials or message contents. It
does not send, mark, move or delete messages. The optional third argument selects
a mailbox for distinguished folders; omit it for the authenticated mailbox.

## Calendar in CrispOffice

Save the Exchange EWS connection in Tasks and choose the services that should
use it. To share the sign-in with Mail, enable Mail and provide the mailbox
email address if the login is a Windows username. The saved account appears
when you open Exchange EWS in Mail. Use Accounts to change the enabled services.
Calendar uses the saved endpoint and credential and discovers the default
calendar and appointment folders. Exchange expands
recurring events for the visible date range. Refresh reloads the selected
calendars, including when CalDAV calendars are selected alongside them.

CrispOffice can create, edit and reschedule standalone timed appointments.
It checks folder membership and the current Exchange ChangeKey before editing
and requests conditional updates without meeting notifications. Enable
**Allow deleting Exchange appointments** in the Exchange connection to offer
deletion. It moves an appointment to Deleted Items. Check that your server
enforces the ChangeKey on DeleteItem before enabling this option. A concurrent
edit can otherwise race with the move. Ambiguous results require a refresh
before retrying. Existing all-day events, recurring appointments and meetings
can be viewed.
For all-day events Exchange returns as UTC instants away from midnight, the
adapter derives the dates in the device time zone. These dates can differ
from the original event dates when viewed from a different zone.

The live read probe on 26 November 2026 discovered four calendars over HTTPS
with NTLM and read a 30-day window in each. The default calendar returned 41
events, including four all-day events. The other three returned empty views.
A second probe selected the mailbox explicitly and recovered all 41 events
with a ten-item request cap.

[Microsoft EWS calendar views](https://learn.microsoft.com/en-us/exchange/client-developer/exchange-web-services/how-to-get-appointments-and-meetings-by-using-ews-in-exchange)

## Shared API

```dart
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';

final provider = createMailEwsProvider(
  configuration: MailEwsConfiguration(
    account: account,
    endpoint: Uri.parse('https://mail.example.com/EWS/Exchange.asmx'),
    username: r'EXAMPLE\user',
    mailboxAddress: 'user@example.com',
    credential: MailCredentialReference(account: account, key: 'exchange'),
  ),
  credentialStore: hostVault,
);
final lease = accountSession.begin(cancellation: cancellation.token);
final folders = await provider.listMailboxes(lease);
```

`account`, `hostVault`, `accountSession` and `cancellation` above are host-owned
objects from the existing core ports. Vault bytes contain only the UTF-8 password
or current bearer token, not configuration JSON. The provider performs a fresh
vault read for each operation and never persists or logs its secret.

The factory returns `MailEwsProvider`, implementing both `MailProvider` and
`MailSubmissionProvider`. Existing repository/coordinator/outbox contracts apply.
Persist a submission attempt before calling `submit`; do not automatically
resubmit an `uncertain` result. Do not treat success as recipient delivery.

## Implemented behavior

| Area | Behavior |
| --- | --- |
| Endpoint and TLS | Explicit HTTPS only; normal certificate and hostname validation, including internal DNS/IP endpoints. Credentials never follow redirects. Install the organization's CA into the platform trust store. No public certificate bypass. |
| NTLM | NTLMv2 only, with MIC, service principal and RFC 5929 TLS channel binding. Authentication uses body-free HEAD requests before SOAP. One operation owns one connection; no automatic reconnect or SOAP replay. |
| Authentication alternatives | Explicit Basic over TLS; bearer token supplied by the host. No silent downgrade between mechanisms. |
| Folders | Paged deep `FindFolder` under the selected mailbox root. Ordinary mail folders are exposed; search/calendar/contact/task folders are not advertised as synchronizable mailboxes. |
| Browsing | `FindItem` IDs followed by full `GetItem` header properties. Offset cursors are browsing aids; use `pullChanges` for synchronization. |
| Synchronization | `SyncFolderItems` with create/update/delete/read-state handling; final change per ItemId wins within a page. Complete headers are fetched only for surviving changed items. |
| Cursors | Account/profile/host/endpoint/login/mailbox-scoped opaque SyncState plus a monotonically increasing local revision. Empty pages advance the revision too. Page and cursor commit atomically through the existing repository. |
| Expired state | Only explicit `ErrorInvalidSyncStateData` starts a new initial sync. Its first page carries `resetRequired`; other errors never silently clear cached mail. |
| Item identity | Exact, case-sensitive Exchange ItemId in `MailOpaqueIdentity(provider: ews)`. ChangeKey is freshly read before conditional mutations; moves can produce a new ItemId and require destination synchronization. |
| Message reading | `GetItem` MIME is base64-decoded with a caller budget, then passed to the shared bounded MIME codec. Attachments follow its existing byte/part budgets. The exact bytes returned by Exchange are retained. |
| Mutations | Read/unread and flags use `NeverOverwrite` and observed confirmation. Move confirms original-ID disappearance. Delete requests `MoveToDeletedItems`, never hard deletion. Unconfirmed attempted writes return `conflict` for reconciliation. |
| Sending | `CreateItem` with `SendAndSaveCopy`. Prepared MIME plus explicit To/Cc/Bcc preserve envelope-only hidden recipients. Sender and visible recipients must agree with the frozen envelope. No fabricated per-recipient SMTP results. |
| Failure and cancellation | Typed, content-free errors; HTTP/SOAP throttling hints; finite operation timeout; abort on cancellation/session retirement. A lost response after possible submission is `uncertain`, without an automatic retry. |
| Browser | Public imports compile to JavaScript. All EWS operations return `unsupported` without calling the supplied vault or MIME codec. No direct browser NTLM or implied relay. |

The default schema is `Exchange2013_SP1`, with `Exchange2016` explicitly
selectable. These are EWS schema identifiers, not Microsoft product-support
claims. The intended current on-premises product is Exchange Server Subscription
Edition; older compatible installations require their own acceptance checks.

## Bounds and deployment requirements

Defaults are 100 changes/items per page (maximum 512), 1,000 discovered folders,
64 MiB cumulative HTTP response work per operation, 64 MiB request bodies,
256 KiB headers, 8 KiB opaque SyncState, 100,000 XML events, depth 64, and a
30-second total operation timeout. Configuration validates every bound. DTDs,
malformed XML, unexpected IDs, incomplete result sets and excess work fail the
operation; they never become partial success or invented sync tombstones.

Exchange `GetItem` can synthesize MIME from its internal item representation.
Retaining those returned bytes does **not** establish byte-identical preservation
of the original SMTP message or cryptographic signed-mail fidelity.

NTLM requires the endpoint to allow HEAD authentication and persistent connection
authentication. A same-origin HTTP 302 from the final authentication HEAD can
establish the session when the server confirms `Persistent-Auth: true` and
supplies no new authentication challenge. SOAP goes to the configured EWS
endpoint on the same TLS connection. Explicit `Persistent-Auth: false` is
refused before SOAP. A server or load balancer that closes the authenticated
connection causes a typed failure. The adapter skips retry if the server
might have accepted the request. Generic HTTP proxies,
Kerberos/Negotiate and client-certificate authentication are outside this version.

Extended Protection should remain enabled. The NTLM client includes TLS channel
binding; unknown certificate-signature algorithms fail explicitly. Loopback TLS
fixtures validate transport behavior, but do not certify every IIS policy,
reverse-proxy topology, operating-system trust store or Exchange CU combination.

## Qualification and remaining boundaries

The focused [validation record](../../validation/mail-ews-20261119/README.md)
records actual source-bound native, JavaScript, storage, protocol and Studio
checks. A later live check with the configured Exchange endpoint verified
native NTLM access to the Tasks folder, mail folder discovery, and a bounded
read-only page of message headers. Installed-platform acceptance remains pending.

Automatic Autodiscover, OAuth acquisition, Kerberos, folder-hierarchy delta sync,
push subscriptions, server drafts, archive/public folders, full delegation,
impersonation, calendars, contacts and protected-message workflows are not
advertised. The new Studio view is session-only; the broader repository-driven
mailbox and durable outbox host milestones remain open.

Original implementation is MIT. XML 7.1.0 and Pointy Castle 4.0.0 were already
locked transitive dependencies and become direct transport dependencies without
version or archive-hash changes. Their MIT-family notices remain in the packages.
That EWS increment left the reviewed MPL MIME fork unchanged; the later
[attachment increment](attachments.md) separately records its scoped
quoted-printable encoder correction.

## Primary references

- [EWS service URL](https://learn.microsoft.com/en-us/exchange/client-developer/exchange-web-services/how-to-set-the-ews-service-url-by-using-the-ews-managed-api)
- [On-premises Modern Authentication](https://learn.microsoft.com/en-us/exchange/plan-and-deploy/post-installation-tasks/enable-modern-auth-in-exchange-server-on-premises)
- [Exchange Extended Protection](https://learn.microsoft.com/en-us/exchange/plan-and-deploy/post-installation-tasks/security-best-practices/exchange-extended-protection)
- [EWS mailbox synchronization](https://learn.microsoft.com/en-us/exchange/client-developer/exchange-web-services/mailbox-synchronization-and-ews-in-exchange)
- [EWS identifiers](https://learn.microsoft.com/en-us/exchange/client-developer/exchange-web-services/ews-identifiers-in-exchange)
- [EWS sending](https://learn.microsoft.com/en-us/exchange/client-developer/exchange-web-services/how-to-send-email-messages-by-using-ews-in-exchange)
- [MS-NLMP protocol](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/)
- [RFC 5929 channel bindings](https://www.rfc-editor.org/rfc/rfc5929.html)
