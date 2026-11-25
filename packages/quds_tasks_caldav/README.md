# quds_tasks_caldav

Pure Dart **VTODO codec and CalDAV connection-profile foundation** for
CrispOffice. This package does not yet make HTTP requests, authenticate an
account, synchronize a provider, or add a task UI. No live Nextcloud, ownCloud,
Open-Xchange, or mailbox.org compatibility certification is implied.

## What works

- Parse one VTODO inside an iCalendar 2.0 VCALENDAR, including its timezone
  components and alarms. A no-op returns the exact original source string.
- Project the common fields to `quds_tasks_core`: title, plain-text notes,
  status, priority, start/due date, and completion time. The full original
  resource remains in `TaskProviderData`, separate from the smaller projection.
- Apply explicit core patches to the original resource. Unknown properties,
  unrelated parameters, folded text, alarm components, timezone definitions,
  and UID survive. An unchanged numeric priority such as `3` remains `3`.
- Encode new UTF-8 content lines with CRLF and 75-octet folding. Text escaping
  prevents newlines in task titles from becoming injected content lines.
- Keep DATE, floating DATE-TIME, UTC, and TZID wall time distinct. No implicit
  conversion uses the machine timezone. Fractional seconds are rejected unless
  every fractional digit is zero, because iCalendar cannot represent them.
  Writing a zoned date requires its matching VTIMEZONE to be present in the
  original resource; new tasks use UTC, floating time, or a civil date until
  timezone-definition creation or a negotiated server extension is implemented.
- Keep task-resource identity separate from iCalendar UID. The host supplies
  the account/list-scoped resource ID; the ETag is the `RemoteTask.revision`.

```dart
import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

final original = CalDavTodoDocument.parse(serverCalendarText);
final changed = original.apply(
  const TaskPatch(title: TaskFieldPatch.set('Review the proposal')),
);
final updatedCalendarText = changed.encode();
```

The example deliberately ends at serialization. A future DAV writer must use
the ETag from the read as `If-Match`, handle conflicts, refetch normalized data,
and record the new resource revision only after successful reconciliation.

## Guarded features

The codec can retain advanced data without implementing its semantics. It
refuses every nonempty patch on a resource containing recurrence rules or
exceptions, a duration, participants/organizer, task relationships, or an
unknown status. It also refuses HTML note conversion, reminder edits, and
`waitingOnOthers`/`deferred` status conversion. These refusals prevent a basic
task edit from silently flattening data. Multiple VTODO components, including
series exceptions, are rejected rather than accidentally editing one member.

Alarms and categories are retained in raw data but are not projected into
editable reminder/category fields yet. New task construction requires an
explicit UTC timestamp with whole-second precision. Marking complete aligns
`PERCENT-COMPLETE` to 100; reopening clears a previous completion time unless
the caller explicitly supplied a new value. A completion timestamp is accepted
only with completed task status. Updated DTSTART/DUE must have matching value
types and, when directly comparable without timezone conversion, DUE must be
strictly after DTSTART.

## Input budgets

`CalDavCodecLimits` defines fixed, non-overridable per-resource ceilings:
2,097,152 UTF-16 code units, 16,384 physical lines, 262,144 code units per
unfolded content line, and 16 component nesting levels. Size and physical-line
checks precede splitting; folding uses linear buffer accumulation. Forbidden
raw controls and bare carriage returns are rejected; tabs and valid folds
remain supported. Invalid or oversized input throws a format error and is
never interpreted as a successful empty task result. A future HTTP transport
must separately enforce byte budgets before decoding strings.

## Provider profiles

`CalDavConnectionSettings` stores non-secret configuration. Credentials belong
in the embedding application's credential store and are intentionally absent
from this type. HTTPS is required, except for an explicit loopback-only HTTP
option intended for tests. URL credentials, query strings, fragments, and a
collection on a different origin are rejected.

| Profile | Connection and capability position |
| --- | --- |
| Generic CalDAV | User supplies a server or DAV discovery URL. Discover VTODO support and each collection's permissions. |
| Nextcloud Tasks | App password or future Login Flow v2 integration. Typical DAV root is `remote.php/dav/` beneath the installation. Subtasks and incremental tokens are documented by Nextcloud; this codec does not yet implement subtask mutations or network sync. |
| ownCloud | Identify Classic versus Infinite Scale and the deployed version. Do not infer groupware/task support from file WebDAV. As of 25 November 2026, ownCloud describes `ocis-groupware` as work in progress. |
| Open-Xchange | User supplies the host. Conservative task defaults disable recurrence, participants, shared/public lists, subtasks, and attachments pending deployment validation. |
| mailbox.org / Open-Xchange | Default discovery root `https://dav.mailbox.org/`; main mailbox email as username; dedicated CalDAV/CardDAV app credential. The exact task-list URL can be copied from its Properties dialog and is treated as opaque. |

The OX CalDAV documentation is marked deprecated and describes only simple,
personal tasks. Current OX UI documentation also discusses task-list DAV
selection. Consequently, the conservative defaults are a starting policy,
not a universal assertion about every current OX installation. mailbox.org's
published DAV support does not establish support for arbitrary third-party
native OX HTTP clients or OAuth registrations.

## Next functional increment

Add an injected HTTP DAV client with same-origin credential handling, principal
and calendar-home discovery, VTODO component filtering, paged reads, ETags,
conditional PUT/DELETE, and a retry policy that distinguishes reads from
ambiguous writes. Add advertised `sync-collection` support with ETag fallback
and invalid-token reconciliation. A durable outbox and account generation
checks must precede automatic background writes. Collection creation, advanced
task semantics, and browser CORS behavior require separate implementation.

Before enabling a provider, live-test two-way create/edit/complete/reopen/delete
in a dedicated test list, credential revocation, DST and all-day dates,
server normalization, simultaneous edits, delete-versus-edit conflicts,
incremental deletion reporting, and token invalidation. Test recurrence,
delegation, shared lists, attachments, and relationships separately before
enabling those features.

## Verification

```sh
dart analyze packages/quds_tasks_caldav
dart test packages/quds_tasks_caldav/test
dart compile js packages/quds_tasks_caldav/test/compile/portable_import.dart -o packages/quds_tasks_caldav/.dart_tool/portable_import.js
node packages/quds_tasks_caldav/.dart_tool/portable_import.js
```

Tests exercise exact preservation, explicit clear-versus-unchanged edits,
escaped/folded Unicode, malformed and ambiguous resources, date distinctions,
completion/reopening, unsupported-feature guards, scoped identity and ETag
projection, provider defaults, and credential-free URL constraints.
The portability smoke performs an actual VTODO parse/patch/serialize round trip
and date projection after JavaScript compilation.

## Primary sources

- [iCalendar, RFC 5545](https://www.rfc-editor.org/rfc/rfc5545)
- [CalDAV, RFC 4791](https://www.rfc-editor.org/rfc/rfc4791)
- [WebDAV synchronization, RFC 6578](https://www.rfc-editor.org/rfc/rfc6578)
- [Nextcloud Tasks](https://github.com/nextcloud/tasks)
- [Nextcloud Login Flow v2](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/LoginFlow/index.html)
- [Nextcloud CalDAV and token retention](https://docs.nextcloud.com/server/stable/admin_manual/groupware/calendar.html)
- [ownCloud Classic and oCIS groupware status, 19 November 2026](https://owncloud.com/blogs/oc-classic-10-reaches-end-of-support-on-31-december-2026-your-two-paths-forward/)
- [mailbox.org task discovery](https://kb.mailbox.org/en/private/addressbook-and-calendar/caldav-korganizer/)
- [mailbox.org direct task-list URLs](https://kb.mailbox.org/en/private/addressbook-and-calendar/caldav-in-thunderbird/)
- [mailbox.org application passwords](https://kb.mailbox.org/en/private/security-and-privacy/application-passwords-for-external-programs/)
- [OX CalDAV task limitations (deprecated documentation)](https://documentation.open-xchange.com/8/middleware/miscellaneous/caldav_carddav/caldav_clients.html)
- [Current OX task-list and DAV selection UI](https://documentation.open-xchange.com/ui/8.55.2/features/tasks/lists-and-delegation.html)

Implementation and tests are original MIT-licensed code. No provider's GPL or
AGPL implementation was copied into this package.
