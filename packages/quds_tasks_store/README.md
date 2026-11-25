# quds_tasks_store

SQLite storage and a resumable pull worker for CrispOffice Tasks. Store the
database in the host application's private data directory. Cached rows can
include full task descriptions and provider payloads. The host owns the database
connection and should use a storage isolate for large collections.

Open a dedicated database and call `TaskPullStore.connect(account)` when
activating a task account. The returned lease identifies that account's active
generation. Pass it to `TaskPullWorker.refresh()` with the selected list and a
provider callback.

```dart
// CalDAV, where list is the discovered CalDavTaskList.
await worker.refresh(lease, list.id, (position) => caldav.pull(
  list,
  cursor: position.cursor,
  knownRevisions: position.knownRevisions,
));

// Microsoft To Do, where listId is the discovered TaskListId.
await worker.refresh(lease, listId, (position) => graph.pullTaskChanges(
  listId,
  cursor: position.cursor,
));
```

The worker returns a typed error, a completed round, or an unfinished round at
the page limit. The host can schedule another call with the same lease. Each
successful page commits its remote rows and cursor in one transaction. The
worker retains cached rows while a replacement baseline is incomplete. Only a
complete baseline can remove unseen cached tasks. Explicit remote tombstones
apply with their page.

Read stored snapshots with `store.tasks(listId)`. When disconnecting, call
`store.disconnect(lease)` and close the provider's client. The persisted
generation prevents a late response from applying through another handle after
disconnect. The same account can resume its cached state when reconnected.

This package currently covers inbound synchronization. Local edits, conflict
resolution, outbox and durable retry scheduling are planned.
