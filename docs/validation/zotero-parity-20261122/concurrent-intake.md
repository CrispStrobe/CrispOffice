# Concurrent intake during Zotero qualification

> Final snapshot: [completed Mail PR #356, complete-tree preservation and zero outstanding incoming branches](concurrent-intake-356.md). Earlier branch dispositions below are historical.

> Later snapshot: [completed Word VBA PR #355 and refreshed branch dispositions](concurrent-intake-355.md). The branch states below describe the earlier captured heads.

Snapshot: 2026-11-22T02:38:48.515870+00:00. This read-only audit records concurrent work
without checking out, merging, committing, changing refs or touching production
files. GitHub Actions was neither queried nor awaited.

## Main to preserve

Remote main advanced from Zotero's intake base
`c522851d165b395a7f60422a1be969dffc39c9ff` to
`bcc55cb6e86e796056e2d75c3fdca50857dbf6e7` through
[Mail PR #354](https://github.com/CrispStrobe/quds_office_suite/pull/354).
GitHub confirms that PR is merged, with source head
`ff30d1064a052abbfbcdc99745ff66f8bc980aea`.

The advance contains **20 commits** (19 implementation/test/documentation
commits plus the merge), **19 changed paths**, **1,280 additions** and
**59 deletions**. All changes are in Mail core/store, Studio Mail or Mail
roadmaps. The complete engine tree, editor library tree and dependency
manifests are unchanged. There are **zero overlapping paths** with Zotero's
published checkpoint `da52f5e9f89918f7e6a9f4c4abaf07bf65ab726a`.
The JSON companion records every changed path, both blob IDs, line counts and
all incoming commit subjects.

The original 380-ref historical intake remains accounted for: its verified
base is an ancestor of this newer main. This does not imply that new unfinished
branch tips have already been incorporated.

## Remaining branch work

Of **19 other non-main fork branches** and **4 upstream branches**, 21 are
already ancestors of current main. The two exceptions are:

| Branch | Captured head | Ahead / behind current main | Disposition |
| --- | --- | ---: | --- |
| `origin/codex/word-vba-cell-formatting-20261122` | `81d6023b30de` | 5 / 0 | Retain unfinished feature branch; fresh qualification pending. |
| `origin/work/mail-folder-search-20261122` | `b0d5f867b3bd` | 4 / 20 | Retain parallel unfinished implementation; reconcile API/schema explicitly before integration. |

At this snapshot, GitHub reports **zero open PRs**, and a direct PR search for
each exceptional branch returns none. Their committed qualification records
explicitly describe validation as in progress. Preserve these remote branches
and every checkpoint; do not treat either unqualified checkpoint as a completed
incoming feature.

The VBA branch already contains the newer Mail main. Its four other commits
extend table-cell font/paragraph formatting and regression coverage. Its
validation record says a final qualification receipt is still forthcoming.

The parallel Mail branch is **not equivalent to merged PR #354**. It calls the
public field `folders` instead of `folderScopes`, permits 1,000 folders instead
of 200, and independently defines schema 11 with a `folder_scope` column where
main uses `has_folder_scope`. Its folder table also has a different foreign key
and an additional `display_name` column. Replaying this as a second schema-11
implementation could leave an existing main-created database incompatible.
A later deliberate reconciliation needs to account for persisted schema 11;
this audit makes no claim that those four divergent commits are absorbed.

## Validation after merging current main

The incoming Mail change gives no source-based reason to rerun the broad
standalone Zotero engine/editor suites. Their source-bound results can be
carried forward after comparing actual input manifests.

**Run the planned Studio Zotero/host-ownership cohort on combined source.**
Its workspace tests compile the changed Mail code through this import path:
`suite_workspace.dart` → `studio_mail.dart` → `studio_mail_native.dart` →
`studio_mail_local_accounts_dialog.dart` → `studio_mail_cached_search_dialog.dart`.
The native Mail adapter also imports the changed Mail core/store libraries.
The four selected files, relative to `packages/quds_office_editor/example`, are:

- `test/studio_zotero_citing_transport_test.dart`
- `test/studio_zotero_shortcuts_test.dart`
- `test/studio_zotero_odt_export_test.dart`
- `test/studio_shortcut_host_ownership_test.dart`

PR #354 explicitly states that its new Dart/Flutter tests were committed but
not executed in its editing environment. A successful Studio Zotero gate would
establish compilation and the covered Zotero workspace behavior; it would not
qualify all new Mail folder-search behavior. Avoid conflating those claims.

If the active VBA work is completed and incorporated later, its changed engine
automation libraries enter through the separate `quds_office_automation.dart`
entry point. Reassess actual source manifests and compiler/automation checks
then; the general engine umbrella does not directly export those libraries. Re-read main and the two branch/PR
states immediately before final publication because this is a concurrent-work
snapshot, not a freeze of remote activity.

Exact SHAs, branch ancestry counts, PR metadata, source comparisons and the
validation rationale are retained in [concurrent-intake.json](concurrent-intake.json).
