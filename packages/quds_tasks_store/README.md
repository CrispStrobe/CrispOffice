# quds_tasks_store

SQLite storage and a resumable pull and push worker for CrispOffice Tasks. Open
a dedicated database in the host application's private data directory. Cached
rows can include full task descriptions and provider payloads.

Call `TaskPullStore.connect(account)` to acquire an account-generation lease.
`saveEdit()` persists a working copy before any network operation. Read cached
server tasks through `tasks(listId)` and use `edits(listId)` for pending
working copies and deletion intents.

```dart
final worker = TaskSyncWorker(store);
await syncCalDavTasks(worker, lease, caldav, caldavList);
await syncGraphTasks(worker, lease, graph, graphList, enableWrites: allowWrites);
```

Pull pages and their cursors commit together. After a complete pull, the worker
reconciles offline edits with the current server snapshot. Conflicting edits
remain available through `edits()`. Resolve a definite conflict with
`resolveEdit()` after the user chooses the working copy or server state.

A write's operation ID and exact local revision are committed before dispatch.
After a restart or an ambiguous response, the worker uses provider reads to
recover the outcome. Acknowledgment records the canonical server task and
preserves edits made during the request. A persisted retry deadline controls
temporary failures and provider backoff across restarts.

Graph writes require the host's explicit opt-in because Graph's atomic
conditional behavior is unqualified. CalDAV uses strong ETags on updates and
deletes. On disconnect, fence outstanding work with `store.disconnect(lease)`
and close the provider transport.
