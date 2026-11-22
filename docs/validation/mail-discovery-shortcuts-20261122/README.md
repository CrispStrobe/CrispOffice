# Mail correspondence-search increment — 2026-11-22

## Intake and source preservation

Started from main `ea7ae724bea2f1e9052aa17f9926eb0659ae4262`.
An exact branch/PR/upstream audit found one remaining fork branch,
`work/mail-connected-navigation-20261122`, with two unique commits and
34 main commits absent from its tip. All 46 other non-main fork branches and
all four upstream branches were already ancestors. No open PRs existed before
this task; the newest 100 PRs were merged.

The reconciliation uses main and incoming `a59e986a12d50c0d115b99c14cd8f746921c6f44`
as ordered merge parents. It imports seven unique historical evidence entries
and the strictly additive historical validation README. Newer main production
and tests are retained. Superseded code, alternate assertions and evidence remain
in the incoming parent; they are not silently discarded or described as current
acceptance results. See [intake.json](intake.json) for every conflict disposition
and exact source blobs.

## Increment boundary

Implement `recipient:` over public To/Cc headers and `participant:` over public
From/To/Cc headers. Reuse the existing bounded query parser, Boolean semantics,
loaded/cached projections and exact saved account/folder scopes. This introduces
no schema, dependency, provider request or send/mutation behavior.

Categories/tags and ordered rules remain the next larger organization increment.
Their storage and lifecycle changes need executable qualification. The branch
was initially named for that planned increment; its actual delivered scope is
the correspondence-search work described here.

## Execution limitation

The fresh checkout succeeded, then every local command failed before process
startup with:

```text
bwrap: Can't create file /workspace/scratch/f3d0bbfa1716/.git: No space left on device
```

The same failure blocked file edits and cleanup through the normal shell.
The automatic permission policy rejected the cleanup escalation because this
session disallows sandbox escalation. The desktop runtime was also unavailable.
No source test, analyzer, formatter or Flutter build has run in this task.
Historical test receipts remain historical and source-bound.

GitHub API reads and atomic Git tree/commit/ref writes remain available. Work is
checkpointed there incrementally, with expected-head guards and both merge
parents retained. No GitHub Actions queue is polled or awaited.

## Qualification to run in an executable workspace

Use the repository-pinned Flutter 3.47.8 and dependency lockfile. Run the core
header-search/saved-search tests, cached-header and saved-search persistence tests,
shared Mail message-list tests, and Studio search-string tests. Run strict
analysis and formatting checks over changed Dart paths. Record actual commands
and outcomes before upgrading this increment's runtime status.
