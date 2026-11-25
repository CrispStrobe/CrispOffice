# Quds Tasks core

Portable Dart values, sparse edits and conflict-aware task reconciliation for
CrispOffice. The package has no runtime dependencies, Flutter imports, network
access, storage, credentials or background scheduler.

## Implemented contract

- Provider/account/list/task identities with value equality and explicit scope.
- Common title, notes, status, priority, start, due, reminder and completion fields.
- Separate civil dates and wall times. Provider timezone names and exact raw
  representations remain available; no machine-local timezone conversion occurs.
- Explicit unchanged/set/clear patches so an unrelated edit cannot clear a field
  merely because it was absent from a request.
- Immutable list/task change pages, opaque continuation/checkpoint values,
  explicit tombstones, provider capabilities and typed failures.
- Pure three-way reconciliation for already bound remote tasks, including
  independent edits, same-field conflicts and local/remote deletion conflicts.

This is a shared implementation foundation. It does not connect an account or
make task synchronization visible in Studio. Graph and CalDAV implementations
belong to their respective adapter packages; persistence and UI are subsequent
host work. There is no successful empty provider implementation here.

## Sparse edits

```dart
import 'package:quds_tasks_core/quds_tasks_core.dart';

final before = TaskFields(
  title: 'Review document',
  due: TaskDate(2026, 12, 1),
  notes: const TaskText('Keep this note'),
);
const patch = TaskPatch(
  title: TaskFieldPatch.set('Review revised document'),
  due: TaskFieldPatch.clear(),
);
final after = patch.applyTo(before);
// Notes survive. The due date is intentionally cleared.
```

An empty title is distinct from clearing the required title field. Clearing
title, status or priority is invalid. Optional empty notes are distinct from
absent notes. `TaskPatch.between(before, after)` returns only changed fields.

## Date fidelity

`TaskDate(2026, 12, 1)` is a date, without midnight or a timezone.
`TaskDateTime('2026-12-01T09:30:00', timeZone: 'Europe/Berlin')` is a wall time with
a retained timezone identifier. Use `timeZone: 'UTC'` for UTC and null for a
floating time. ISO strings must include seconds and must not contain a Z/offset;
up to nine fractional digits are supported. Invalid calendar dates are rejected,
not normalized. The original datetime string is retained while equality ignores
insignificant trailing fractional zeros.

Windows and IANA zone names are not silently equated. Timezone conversion,
ambiguous/nonexistent local-time resolution, recurrence and provider-specific
date-only mappings belong to adapters/hosts with explicit rules.

## Reconciliation and persistence

Keep the last acknowledged `RemoteTask` as the base, a local working `TaskFields`
value, and a monotonically managed local revision. `TaskSyncSnapshot.local ==
null` means an intentional local deletion. New unbound drafts use a create flow
and acquire their remote identity from a confirmed result.

```dart
final plan = reconcileTask(
  snapshot: TaskSyncSnapshot(
    base: lastAcknowledgedRemote,
    local: localWorkingCopy,
    localRevision: capturedRevision,
  ),
  remote: freshlyObservedRemote,
  expectedLocalRevision: capturedRevision,
);
```

For every common field, an unchanged local value accepts the remote value, an
unchanged remote value retains the local value, and identical concurrent edits
converge. Divergent edits to one field produce an explicit conflict. Conflicts
expose no executable patch. Deleting an otherwise changed task also conflicts,
including a changed retained provider payload or revision such as an unknown
checklist or attachment update even when common fields are identical. Without
retained payloads, deletion requires an unchanged non-null revision. Coupled
status/completion-time and comparable start/due fields are checked before a
merged write is proposed: a merge cannot reopen a task while retaining a
completion timestamp or make a task due before its start. Ordering is compared
only between civil dates or wall times with the exact same zone identifier;
other comparisons require explicit provider/host rules.
Fresh remote revision/payload metadata is retained in the returned plan.

Pass a null remote value only for an authoritative tombstone or an explicit
confirmed absence. Missing pages, expired cursors and failed network reads do
not prove deletion. The returned plan performs no write and is not an
acknowledgement: the host must compare the captured local revision again in the
transaction that applies it, persist received records with their cursor, and
advance the base after confirmed provider outcomes. A write that may have been
accepted needs reconciliation before retry; it must not be blindly replayed.

Only the common field projection is merged. `TaskProviderData` preserves the
exact complete provider payload for adapter use; unknown fields are not guessed
or normalized by core. Adapters must patch only explicitly changed fields and
reject an edit that would discard unsupported semantics.

## Verification

From this package after workspace dependency resolution:

```sh
dart format --output=none --set-exit-if-changed lib test
dart analyze
dart test
dart compile js test/compile/portable_import.dart -o /path/to/task-core-smoke.js
```

The portable entry executes a real reconciliation check and can also run under
Node after compilation. These checks do not qualify browser storage, OAuth,
provider accounts or installed desktop applications.
