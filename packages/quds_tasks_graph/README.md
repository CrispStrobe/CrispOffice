# quds_tasks_graph

Microsoft Graph v1.0 To Do adapter for the portable CrispOffice task model. The
package implements real HTTP request/response handling, bounded list and task
delta pages, task reads, ordinary task creation, sparse updates, deletion and
read-only recovery of uncertain creates. It is an adapter foundation, not a
complete background sync service or desktop Tasks feature.

The portable entry point imports no Flutter or `dart:io` libraries. Native
hosts can use `quds_tasks_graph_native.dart`; browser hosts provide their own
HTTP transport. All APIs use the global `https://graph.microsoft.com/v1.0/me/todo`
endpoint and delegated user authorization.

## Host integration

The host supplies an account-bound `GraphTaskTokenSource` and a stable
`TaskAccountId`. The account identifier must distinguish users/tenants, rather
than relying on a mutable email address. A token source must always return a
Graph access token for that same account. The adapter neither discovers nor
changes the signed-in account.

Register a Microsoft public-client application and use authorization-code flow
with PKCE. Request delegated `Tasks.ReadWrite` when task sync is enabled, and
`offline_access` for a refreshable user session. A pre-existing mail grant does
not automatically grant task access. A Graph token can be shared with an existing
mail OAuth session after incremental consent; an Outlook IMAP token is not a
Graph token. Token storage and consent UI remain host responsibilities.

```dart
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_graph/quds_tasks_graph_native.dart';

Future<TaskResult<TaskSyncPage>> readOnePage({
  required TaskAccountId account,
  required String remoteListId,
  required GraphTaskTokenSource tokens,
  String? cursor,
}) async {
  final transport = NativeGraphTaskHttpTransport();
  try {
    final provider = GraphTaskProvider(
      account: account,
      tokens: tokens,
      transport: transport,
      dateOnlyTimeZone: 'Europe/Berlin',
    );
    return await provider.pullTaskChanges(
      TaskListId(remoteListId, account: account),
      cursor: cursor,
    );
  } finally {
    transport.close();
  }
}
```

`GraphTaskHttpTransport` is the injectable byte boundary. Implementations must
enforce the timeout and response byte limit while streaming, use verified TLS,
disable redirects, and never replay writes. The optional native transport
enforces these requirements and restricts requests to global Graph To Do paths.
The provider also validates returned response size and restricts continuation
URLs before requesting an access token.

## Public operations

| Method | Behavior |
| --- | --- |
| `listTaskLists` | One list-discovery page; optional browse continuation. |
| `pullListChanges` | One list delta page with upserts, tombstones and continuation/checkpoint. |
| `pullTaskChanges` | One task delta page for an exact account/list. |
| `getTask` | Read one exact task; null means the endpoint returned 404. |
| `createTask` | One POST, including a stable operation marker in an open extension. |
| `updateTask` | One sparse PATCH; status/completion changes first check for recurrence. |
| `deleteTask` | One DELETE; only 204 is acknowledged as success. |
| `findCreateOperation` | One read-only recovery page, matching operation ID and local task ID. |

All operations return core `TaskResult<T>` / `TaskProblem` values. Errors do not
include raw server text, URLs, task content or credentials. A GET returning 404
does not establish historical deletion or authorize replay of a previous write.

### Delta state

Cursors are opaque adapter envelopes containing the complete server URL and
account/operation scope. They are not encrypted and belong in protected host
storage. Each page validates that URLs still target the same Graph collection;
account, list, operation, host, scheme, port and path mismatches fail closed.

Continue every `nextCursor`, including after an empty page. A `checkpoint`
appears only at the end of a delta round. Persist observations and their cursor
atomically; apply pages sequentially and never infer deletions from absent rows.
Within one page, repeated IDs collapse to their final observed event before
splitting upserts and tombstones. A failed or malformed page returns no usable
checkpoint. `cursorExpired` asks the host to establish a new baseline while
preserving its pending local writes.

The provider intentionally reads one page per call rather than buffering an
entire mailbox. `limit` is a server paging hint; `maxResponseItems` and
`maxResponseBytes` are independent hard validation limits. Missing required task
properties and unknown status/importance enum values fail explicitly instead of
being rewritten as defaults. Unsupported task properties remain in
`TaskProviderData` as a complete JSON representation.

### Writes and conflicts

`TaskPatch` distinguishes omitted, changed and cleared fields. A title-only edit
does not write notes, dates, status, recurrence or other provider fields. Clearing
a date sends JSON null. Clearing a reminder also disables it. Plain-text notes
are escaped into HTML for the documented update contract; existing HTML is
preserved unless the host explicitly edits it. Hosts must render HTML safely.

No mutation is automatically retried, even on a 401. Safe GETs may refresh a token
once after an explicit 401. Throttling returns `retryAfter` rather than sleeping
or spinning. Transport failures after possible dispatch, 5xx write failures and
unreadable successful write responses set `mutationMayHaveOccurred: true`.

`conditionalWrites` is **not** advertised. ETags are retained, but To Do's atomic
`If-Match` behavior has not been qualified against a live account. Supplying
`expectedRevision` to update/delete returns `unsupported`; it is never silently
ignored. Hosts must compare a saved base with current local and remote values,
retain conflicts, and acknowledge that an unconditional read followed by a write
still has a race window. This package does not claim atomic conflict prevention.

Completing/reopening a recurring task can generate another occurrence. Before
changing `status` or `completedAt`, the adapter reads the exact task and rejects
any non-null recurrence. This prevents known recurring tasks from entering an
unqualified completion flow; the same read/write race remains. Other supported
fields can be patched without replacing recurrence data.

### Recovering an uncertain create

Graph To Do has no documented task-creation idempotency key. A tracing
`client-request-id` would not make a second POST safe.

1. The host durably saves a unique operation ID and its local task ID before
   calling `createTask`, and records that the operation is being attempted.
2. The adapter includes those values in the static
   `com.crispoffice.taskSync.v1` open extension in the **same POST** as the task.
   The extension name stays constant; it is not allocated per operation.
3. On success, the host saves the remote identity and acknowledges only the local
   revision represented by that operation.
4. On uncertainty, the host calls `findCreateOperation` and follows every page.
   One matching task can be bound to the existing local task. Multiple matches
   remain a conflict. An empty result does not prove that the earlier write was
   rejected or authorize another POST; visibility may lag or metadata may change.

This package exposes the recovery mechanism but does not own a durable outbox,
automatically schedule recovery, or make exactly-once delivery claims.

## Date and capability boundaries

Graph `dateTimeTimeZone` values are parsed as the original wall-time string plus
Windows/IANA zone name. No machine-local conversion or UTC date truncation occurs.
When a host writes a civil `TaskDate`, the adapter sends midnight in the explicit
`dateOnlyTimeZone` (default `UTC`). Reads remain `TaskDateTime` because Graph's
representation does not prove that a value originally came from a civil date.
Floating times without a zone are unsupported. Date-only display parity in the
Microsoft To Do clients still requires live acceptance testing with the intended
account timezone, including daylight-saving and day-boundary cases.

Supported capabilities cover basic task reads/CRUD, delta, notes/HTML, start/due
dates and reminders. Recurrence editing, checklist steps, attachments, shared-list
management, My Day, Planner tasks, list creation/renaming and arbitrary nesting
are outside this increment. The built-in flagged-email list is exposed as read
only in discovery. Hosts must respect that metadata when choosing write targets;
IDs alone do not carry permissions. Shared-list metadata is retained without
claiming qualified sharing behavior.

A durable coordinator/store, protected token persistence, desktop UI,
background scheduling, account-disconnect fencing and local-revision-aware
acknowledgment remain host integration work. The core package's pure merge
decisions can be used by that coordinator.

## Validation

The deterministic suite uses fake transports and covers pagination/checkpoints,
duplicate delta events, tombstones, credential-origin boundaries, sparse fields,
date/HTML preservation, recurrence completion guards, lost-response recovery,
token refresh, throttling, expired cursors, uncertain writes and byte/item budgets.
The portable import is also suitable for `dart compile js`.

No real Microsoft account was used for this increment. Live acceptance gates are:
create/open-extension expansion, ordinary complete/reopen, date-only UI round
trips, personal/work account behavior, and conditional-write semantics before
enabling `conditionalWrites`.

## API references

- [To Do API overview](https://learn.microsoft.com/en-us/graph/api/resources/todo-overview?view=graph-rest-1.0)
- [Task resource and fields](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0)
- [Task delta](https://learn.microsoft.com/en-us/graph/api/todotask-delta?view=graph-rest-1.0)
- [List delta](https://learn.microsoft.com/en-us/graph/api/todotasklist-delta?view=graph-rest-1.0)
- [Create an open extension with a resource](https://learn.microsoft.com/en-us/graph/api/opentypeextension-post-opentypeextension?view=graph-rest-1.0)
- [Get and expand open extensions](https://learn.microsoft.com/en-us/graph/api/opentypeextension-get?view=graph-rest-1.0)
- [Update To Do task](https://learn.microsoft.com/en-us/graph/api/todotask-update?view=graph-rest-1.0)
- [Date/time/timezone contract](https://learn.microsoft.com/en-us/graph/api/resources/datetimetimezone?view=graph-rest-1.0)
- [OAuth authorization code with PKCE](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow)
