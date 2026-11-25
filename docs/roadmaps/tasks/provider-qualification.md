# Task providers: evidence and qualification

Reviewed 2026-11-25. These links document available APIs and constraints; they
do not certify an implementation or a particular user account. Current source
progress and executed checks are recorded in [progress](progress.md).

## Microsoft To Do / Graph

Use stable v1.0 task resources with delegated `Tasks.ReadWrite`. Personal accounts
and eligible Microsoft 365 work/school accounts are supported; an on-premises
Exchange mailbox alone is not a To Do account. List/task delta APIs are present.
The current overview includes application permissions, while create-task docs
still mark application access unsupported: validate endpoint-level parity.

Sources:

- [To Do API overview](https://learn.microsoft.com/en-us/graph/api/resources/todo-overview?view=graph-rest-1.0)
- [Task schema](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0)
- [Checklist schema](https://learn.microsoft.com/en-us/graph/api/resources/checklistitem?view=graph-rest-1.0)
- [Create task and permissions](https://learn.microsoft.com/en-us/graph/api/todotasklist-post-tasks?view=graph-rest-1.0)
- [Task delta](https://learn.microsoft.com/en-us/graph/api/todotask-delta?view=graph-rest-1.0)
- [List delta](https://learn.microsoft.com/en-us/graph/api/todotasklist-delta?view=graph-rest-1.0)
- [Update task](https://learn.microsoft.com/en-us/graph/api/todotask-update?view=graph-rest-1.0)
- [Permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference#tasksreadwrite)
- [Account requirements](https://support.microsoft.com/en-us/outlook/which-accounts-can-i-use-microsoft-to-do-with)
- [Graph standard API licensing](https://learn.microsoft.com/en-us/graph/metered-api-overview)
- [Current metered APIs](https://learn.microsoft.com/en-us/graph/metered-api-list)
- [Task change notifications](https://learn.microsoft.com/en-us/graph/api/subscription-post-subscriptions?view=graph-rest-1.0)
- [Planner-assigned tasks](https://learn.microsoft.com/en-us/graph/api/planneruser-list-tasks?view=graph-rest-1.0)

Live gates: intended personal and work/school account types; incremental consent;
create/edit/complete/reopen/delete; dates and HTML notes; shared-list permissions;
delta deletions and invalid cursors; stale ETag behavior; uncertain-create marker
recovery; token persistence/revocation. My Day UI parity is not established.

A Microsoft personal account can use a mailbox.org email address as its sign-in
name. Register the desktop app in an Entra directory the project controls and
select an audience that includes personal Microsoft accounts. Both accounts can
consent separately to the same public-client app via the `common` authority.
The registration needs the `http://localhost` desktop redirect and delegated
`Tasks.ReadWrite`. Account owners handle MFA in Microsoft's sign-in page.
Microsoft documents [personal-account tenant setup](https://learn.microsoft.com/en-us/troubleshoot/entra/entra-id/app-integration/error-code-AADSTS50020-user-account-identity-provider-does-not-exist)
and [app registration audiences](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app).

## Gmail / Google Tasks

Studio requests `https://www.googleapis.com/auth/tasks.readonly` by default.
**Allow Google task edits** requests `https://www.googleapis.com/auth/tasks`
through the same desktop OAuth flow. Enable the Google Tasks API for the
client's Google Cloud project and add the account under test users if the
project uses an external testing audience. Gmail mail keeps its existing
scope. The Tasks API supplies list and task page tokens. Each complete
Studio snapshot reconciles removals in the local cache.

The writer checks the current task revision and assignment before it sends
a sparse patch or delete with `If-Match`. Tasks assigned through Docs or Chat
are read-only in Studio. A lost insert response keeps the local attempt
unconfirmed because Google assigns the task ID and the API exposes no
client operation ID. The worker can reconcile ambiguous updates and deletes
against complete later snapshots. Live stale-write and field-clear behavior
still need qualification.

- [Google Tasks scopes](https://developers.google.com/workspace/tasks/auth)
- [Google desktop client setup](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Google task listing and visibility](https://developers.google.com/workspace/tasks/reference/rest/v1/tasks/list)

## CalDAV / Nextcloud

Build against VTODO-capable collections and conditional resource operations.
Nextcloud Tasks documents CalDAV interoperability, task properties and subtasks.
Login Flow v2 provides browser-based per-client credential provisioning.

Sources:

- [Nextcloud Tasks](https://github.com/nextcloud/tasks)
- [Nextcloud Login Flow v2](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/LoginFlow/index.html)
- [CalDAV client discovery, VTODO queries, ETags and synchronization](https://sabre.io/dav/building-a-caldav-client/)
- [Nextcloud calendar synchronization maintenance](https://docs.nextcloud.com/server/stable/admin_manual/groupware/calendar.html)
- [iCalendar specification](https://www.rfc-editor.org/rfc/rfc5545)
- [WebDAV collection synchronization](https://www.rfc-editor.org/rfc/rfc6578)

Live gates: discovery with installation prefixes; app-password revocation;
VTODO filtering; ETag/412 behavior; resource deletion; sync-token expiry and
fallback; preserved properties; all-day/floating/TZID dates; recurring/subtask
round trips; permissions on shared collections.

The prepared VPS instance ran Nextcloud 33.0.11. A disposable account and
VTODO list passed creation, UID recovery, update, server-side HTTP 412 for a
stale If-Match, incremental sync and a deletion tombstone. The test runner
verified collection absence and the temporary account was deleted. Cleanup
bypassed Nextcloud's calendar trash only for the ownership-verified fixture.
See the [Nextcloud calendar trash documentation](https://docs.nextcloud.com/server/stable/admin_manual/groupware/calendar.html#trash-bin).

## mailbox.org / Open-Xchange


A live mailbox.org run passed basic VTODO discovery and CRUD on an isolated
collection, including UID recovery, HTTP 412 for a stale If-Match, a sync-token
delta and a deletion tombstone. It also verified removal of the test list.
Open-Xchange assigned canonical hrefs to new objects and returned bare ETags
in multistatus reports. The mailbox profile normalizes these tags and omits
the client-specified sync result limit.

On 25 November 2026, the Calendar adapter discovered a live mailbox.org
VEVENT calendar and completed Day, Week and Month reports. A disposable
VEVENT calendar returned both overlapping appointments and a two-day
all-day event in each range. The server returned one unexpanded daily series
even though each request included `calendar-data/expand`. Studio displayed
the unexpanded-series count and omitted that series from the agenda and grid.
The server accepted deletion of that disposable calendar. Authenticated
discovery again returned only the original calendar.

A follow-up live test confirmed the local recurrence fallback. mailbox.org
returned a daily series without expansion. CrispOffice produced the two
expected occurrences within a three-day report and honored the excluded date.
The disposable calendar was deleted and its absence verified by discovery.
Named-timezone and more complex rules still depend on server expansion.

mailbox.org explicitly documents bidirectional task synchronization over CalDAV.
Use `https://dav.mailbox.org/` or the exact task-list Properties URL. Recommend a
dedicated DAV app password; this is required when 2FA is enabled.

Sources:

- [mailbox calendar and task setup](https://kb.mailbox.org/en/private/addressbook-and-calendar/caldav-korganizer/)
- [mailbox exact calendar/task-list URL](https://kb.mailbox.org/en/private/addressbook-and-calendar/caldav-in-thunderbird/)
- [mailbox application passwords](https://kb.mailbox.org/en/private/security-and-privacy/application-passwords-for-external-programs/)
- [mailbox synchronization overview](https://kb.mailbox.org/en/business/account/data-synchronisation-overview/)
- [OX CalDAV client limitations, marked deprecated](https://documentation.open-xchange.com/8/middleware/miscellaneous/caldav_carddav/caldav_clients.html)
- [Current OX task lists and delegation](https://documentation.open-xchange.com/ui/8.55.2/features/tasks/lists-and-delegation.html)
- [OX HTTP Tasks API](https://documentation.open-xchange.com/components/middleware/http/develop/index.html)
- [OX OAuth client guide](https://documentation.open-xchange.com/7.10.5/middleware/login_and_sessions/oauth_2.0_provider/02_client_developer_guide.html)

Conservative initial matrix:

| Feature | mailbox.org CalDAV | Native OX HTTP |
| --- | --- | --- |
| Personal basic task CRUD | Documented | Documented API; host access required |
| Title, notes, start/due, priority, status | Documented mapping | Documented fields |
| Progress/categories/reminders | Round-trip before enabling editing | Documented fields; qualify deployment |
| Recurrence/participants/shared task lists | Disabled until deployed-server evidence | API support still requires auth/ACL and behavior checks |
| Subtasks/attachments/URLs | Do not infer support from calendar objects | Task-specific workflow needs verification |
| Incremental updates | Advertised DAV sync tokens, otherwise ETags | Timestamp updates, include deletions with `ignore=false` |
| Authentication | DAV app credential | Host-supported session or OAuth registration |

The older OX CalDAV document describes simple personal tasks and discarded
unsupported properties. Current deployments may differ. Preserve local data,
refetch writes, and detect losses; do not equate raw preservation with guaranteed
server fidelity. Generic OX HTTP documentation does not prove that mailbox.org
supports arbitrary third-party native API clients or accepts DAV app credentials
for that API.

Live gates: all generic DAV checks, mailbox task-list discovery, dedicated app
password and revocation, Europe/Berlin DST cases, progress/category/reminder
normalization, then separate recurrence/shared/participant experiments. Keep the
native OX adapter gated on an explicitly supported host and authentication mode.

## ownCloud and lightweight DAV servers

The ownCloud announcement on 19 November 2026 describes `ocis-groupware` as work
in progress and reverses the former plan not to add CalDAV/CardDAV to Infinite
Scale. Classic 11 exists; Classic 10 support ends on 31 December 2026. Therefore
detect and qualify the actual deployed edition rather than hard-code an
ownCloud-wide support claim.

- [ownCloud current migration and groupware status](https://owncloud.com/blogs/oc-classic-10-reaches-end-of-support-on-31-december-2026-your-two-paths-forward/)
- [ownCloud Infinite Scale groupware](https://github.com/owncloud/ocis-groupware)
- [Radicale](https://radicale.org/v3.html)
- [Baikal](https://sabre.io/baikal/)

Qualification is per server/version and requires advertised VTODO, basic CRUD,
auth, dates, conflicts and sync recovery. Do not promise a specific ownCloud
Tasks web app works with an untested release.

A disposable ownCloud Classic 10.15.0 container on the VPS passed the same
basic task round trip and fixture deletion checks. The existing 10.15.0 site
was disabled and its configured PHP 7.4 FPM socket was absent. The test used
the official matching image and fresh storage. The container, data and image
were removed afterward. See the [official ownCloud server image](https://hub.docker.com/r/owncloud/server).

## Exchange Server / EWS

The configured Exchange host accepted the supplied credentials over NTLM.
A read-only `GetFolder` for the distinguished `tasks` folder returned
`NoError` through CrispOffice's native EWS transport after fixing its
authenticated HEAD handling. The endpoint confirms persistent authentication
and returns a same-origin HTTP 302 for the final HEAD. The transport sends SOAP
to the configured service endpoint on the established TLS connection.
Studio discovers task folders and synchronizes incoming changes over this
transport. The default-folder read probe used a durable checkpoint and saw
no new changes. Studio stages outgoing creates and sparse updates in the
task outbox. Updates send the saved Exchange ChangeKey with
`ConflictResolution=NeverOverwrite`. Creates carry a named property so an
unconfirmed write can be matched after a pull without reissuing it. Changes
that can advance a recurring task series remain disabled. Studio can enable
deletion per account. The adapter verifies the current revision and
nonrecurring status first, then asks Exchange to move the task to Deleted
Items. The live server accepted a raw DeleteItem with an outdated ChangeKey,
so the adapter's check can race with another client's edit. The Studio
connection dialog makes remote deletion an explicit choice. On a disposable
folder, the live server rejected a raw stale update with
`ErrorIrresolvableConflict`. Adapter creation, notes, due date, completion,
deletion and incremental change tracking passed. The test removed the test
folder and its fixtures. Microsoft To Do uses a
separate Graph OAuth grant.

Run the read-only probe from `packages/quds_mail_transport` with
`dart run example/ews_tasks_probe.dart [credential-file]`. It reads
`EWS_SERVER`, `EWS_ACCOUNT` and `EWS_PW` from the file or environment and
reports counts only.


- [Exchange Online EWS retirement timeline and on-premises distinction](https://techcommunity.microsoft.com/blog/exchange/exchange-online-ews-your-time-is-almost-up/4492361)
- [EWS task folders/items](https://learn.microsoft.com/en-us/exchange/client-developer/exchange-web-services/folders-and-items-in-ews-in-exchange)
- [Existing CrispOffice on-premises EWS implementation](../mail/exchange-ews.md)

The cloud retirement is not an instruction to remove the on-premises provider.
Add explicit task folder/property mapping, ChangeKey conflict tests, move-ID
handling and appropriate host authentication. Require real Exchange acceptance;
existing mail fixtures do not qualify task synchronization.

## Vikunja and optional bridges

- [Vikunja REST v2](https://vikunja.io/docs/api-v2/)
- [Vikunja CalDAV limitations](https://vikunja.io/help/caldav/)

Use REST v2 for a native integration. A Microsoft-to-CalDAV bridge is an
additional feature implemented above both providers, with explicit list pairing,
loop prevention, mapping storage and deletion/conflict policy. Merely connecting
two accounts does not enable copying between them.

## Deployment record template

For each actual acceptance run record: date, source commit, app/runtime version,
server product/version, account type (without personal identity), enabled scopes,
capabilities exercised, disposable-list authorization, redacted commands/tests,
pass/fail/blocked results, and remaining limitations. Never commit credentials
or personal task contents. Retire capability claims when a deployment changes.
