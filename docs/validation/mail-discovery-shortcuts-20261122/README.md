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

## Remote checkpoints

| Commit | Purpose |
| --- | --- |
| `138fab37b26d12453bded81ddd5ebf5ab531843b` | History-preserving intake; production and test package tree equals original main |
| `25e93061f640ec381feb45291ccb363401a20bc8` | New predicates and EN/DE/AR help |
| `bb92051a07618b069f8fc03609d1af6863dc52a0` | Core, store, shared UI and locale regression source |
| `6cb1439d64fd18690cf1ac5a3b81936d6fe0e142` | Scope documentation, static-review record and precise test wording |
| `ff7e7cea6cea90c0a99da3f3d0a77b3231e3ad91` | Reconcile newly merged Word work from remote main without production conflicts |

The intake package-tree SHA remains
`6c50da559d4b1b199c36ffd5c3cdef1ae0a5f54c`, matching original main exactly.
Dependency manifests and lockfile are unchanged. Incoming head is an ancestor
of the intake commit, so both unique incoming commits are retained.

## Review and executable acceptance

Independent static review found no correctness blocker in the predicate or help
changes. It checked whitelist/dispatch agreement, exhaustive matching, complete
union negation, unchanged budgets, public-only projections, exact saved scope and
RTL example recognition. An existing punctuation difference between loaded and
cached address rendering remains; examples use names or addresses separately.

Fifteen new regression cases were authored, with further assertions in existing
EN/DE/AR and RTL tests. This is a source inventory, not a passed-test count.
The source-level checks and exact remote readback are recorded in
[static-review.json](static-review.json); they do not substitute for Dart/Flutter
execution.

Run these focused suites after `flutter pub get --enforce-lockfile` succeeds in
an executable checkout using the pinned SDK:

```bash
(cd packages/quds_mail_core && dart test test/header_search_test.dart test/header_search_boolean_test.dart test/header_search_boolean_regression_test.dart test/header_search_people_test.dart test/saved_header_search_test.dart test/saved_header_search_folders_test.dart)
(cd packages/quds_mail_store && dart test test/cached_header_search_test.dart test/cached_header_search_folders_test.dart test/saved_header_searches_test.dart test/saved_header_search_folders_test.dart)
(cd packages/quds_mail_ui && flutter test test/message_list_test.dart test/message_list_bulk_test.dart test/message_list_conversations_test.dart)
(cd packages/quds_office_editor/example && flutter test test/studio_mail_boolean_search_strings_test.dart)
```

Run strict analysis and `dart format --output=none --set-exit-if-changed` on
all changed Dart paths as well. These commands are a resumption plan; they were
not executed here. GitHub Actions was neither awaited nor used as evidence.

## Final publication preparation

Remote main advanced during the task to
`bed699fb8b993e9b4f15896a7be22fdff6349985` through Word PR #389.
The task branch incorporates that exact main as a merge parent, preserving all
Word code, fixtures and reviewed Mail assertions. The sole historical README
overlap was resolved by retaining both additive records. See
[late-intake.json](late-intake.json).

At `ff7e7cea6cea90c0a99da3f3d0a77b3231e3ad91`, the branch is five
commits ahead and zero behind that main. GitHub readback confirms all 17 intended
feature, regression and documentation files exactly match the prepared content.
The production delta relative to refreshed main is limited to the shared query
predicate and its help copy; there is no engine/protocol/storage implementation
delta. See [publication-review.json](publication-review.json).

The concurrent Zotero continuation was still closing out on its own branch at
the last snapshot. Its work is retained there, and main must be refreshed again
immediately before merging this task. No unfinished branch is overwritten.

For the next executable checkout, start sparse so historical evidence archives
do not exhaust the workspace before the pinned runtime is available:

```bash
git clone --filter=blob:none --sparse https://github.com/CrispStrobe/quds_office_suite.git
cd quds_office_suite
git sparse-checkout set packages third_party apps tool tools docs/roadmaps/mail
```

The omitted historical evidence remains in Git and is readable by exact commit.
Qualify the source with the committed regression suites before claiming runtime
acceptance for this increment or beginning the larger storage-backed tag/rule
implementation.
