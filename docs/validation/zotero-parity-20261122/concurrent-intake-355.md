# Concurrent intake addendum — completed Word VBA PR #355

> Final snapshot: [completed Mail PR #356, complete-tree preservation and zero outstanding incoming branches](concurrent-intake-356.md). Earlier branch dispositions below are historical.

This addendum updates [the earlier concurrent intake](concurrent-intake.md).
The earlier branch heads and dispositions remain historical observations;
they are not a claim about current remote status. Addendum snapshot:
2026-11-22T02:46:59.325378+00:00.

## Newly completed incoming main

GitHub confirms [PR #355](https://github.com/CrispStrobe/quds_office_suite/pull/355),
**Extend Word VBA formatting for existing table cells**, is closed and merged.
Its completed head is `49f43824196c4d373f991e442fac2e73e68c5f9f`; main advances
from `bcc55cb6e86e796056e2d75c3fdca50857dbf6e7` to
`ceddcd888c37f64e37a8d8d1669daaea31384daf`.

This advance contains **7 commits**, **73 changed paths**, **3,846 text
additions** and **64 text deletions**. Most paths are the feature's documentation,
tests and retained qualification artifacts. Its four production changes are:

- `packages/quds_office_engine/lib/src/automation/office_operations.dart`
- `packages/quds_office_engine/lib/src/automation/office_vba_language.dart`
- `packages/quds_office_engine/lib/src/automation/operations/word_steps.dart`
- `packages/quds_office_engine/lib/src/automation/operations/word_table_cell_text_steps.dart`

The native Word model tree, entire editor/Studio tree and dependency manifests
are unchanged by this advance. Against pre-integration Zotero checkpoint
`b7758d482a0381c5c3ad526675321de80989465e`, the sole changed-path overlap is
`packages/quds_office_engine/CHANGELOG.md`. Both feature entries should remain.
Canonical combined source is
`d4b4392fe538473a3accd15294288347e8bc2b56`. Independent blob comparison confirms
**72 incoming paths match main exactly**. The sole difference is the engine
changelog, where both feature additions are retained. The parent qualified
that combined source; evidence checkpoint
`3660a9d94e3100885e61b244f9dba7bdc5403cfb` changes documentation only.
This audit verifies that content preservation and documentation-only delta;
it does not independently rerun the parent's tests.

The completed VBA record reports **6,614 distinct source-equivalent passing
cases across 129 files**, plus strict scoped analysis, VM/JavaScript and CLI
checks. It explicitly distinguishes the broad execution from a corrected
integration rerun. Those results belong to the incoming VBA qualification;
this audit neither replays nor adds them to fresh Zotero execution counts.

## Effect on Zotero validation

These changes enter through the separate `quds_office_automation.dart` public
API. The general `quds_office_engine.dart` library does not export that API.
A repository-local import/export/part closure audit of the actual selected
Zotero cohorts finds **none of the four changed production files**:

| Cohort | Entry points | Repository-local files | Changed VBA files reachable |
| --- | ---: | ---: | ---: |
| Engine Zotero | 56 | 442 | 0 |
| Editor Zotero | 53 | 552 | 0 |
| Studio Zotero/host ownership | 4 | 970 | 0 |

All local URIs resolve. The conservative traversal includes every conditional
URI, uses the existing package configuration, and excludes SDK/external-package
source traversal. The exact roots, directive expression and sorted-path-list
hashes are recorded in the JSON companion. Its checkout observation is
`a08e25d0d417f90db3d328356bcf4b59cb71f2e0`.

PR #355 therefore introduces no source-based reason for another broad Zotero
runtime rerun. Whole-engine or whole-workspace manifests **do change** when the
new automation source/tests arrive; do not call those complete manifests
byte-identical. Attribute carried execution using the bounded dependency
exclusion and actual unchanged Zotero inputs.

The earlier PR #354 Mail-to-Studio dependency finding still applies. The
planned Studio cohort should be run, or matched to a qualifying combined-source
run, after that Mail integration. PR #355 adds no further changed Studio
production dependency.

## Refreshed outstanding-branch disposition

Of the same **23 captured non-own branches** (19 fork plus four upstream),
**22 are now ancestors** of current main. The VBA branch's completed
`49f43824196c4d373f991e442fac2e73e68c5f9f` head is incorporated through #355.
GitHub again reports zero open PRs.

The remaining branch is `work/mail-folder-search-20261122`, now at
`936ea62ae9be603830e8e13ee3cb90a03f3be554` (**13 ahead, 0 behind** current main).
It has incorporated #354, #355 and the earlier Zotero checkpoint
`d1c9673c7caa24a3dc41f9255d2916846d6cdbaf`. It does not yet contain the latest
pre-integration Zotero checkpoint used above. Some of its ahead commits are
those retained Zotero ancestors, not additional Mail implementation.

**The earlier schema incompatibility finding has been addressed in this
branch's new source.** It now keeps published schema 11 intact, introduces
additive schema 12 for folder-label metadata, preserves the 200-folder bound,
and retains the `folderScopes` constructor/property compatibility surface.
The earlier four-commit head is not the current implementation.

Its latest committed qualification record nevertheless explicitly says the
worktree is not merge-qualified while combined reconciliation is in progress.
There is still no PR for this branch at the captured observation time. Retain
the active branch and checkpoints as qualification-pending. This bounded audit
stops at that timestamp; it does not continuously follow unfinished work. Do
not call its new source already absorbed or carry its pre-reconciliation test
counts forward as qualification of the combined tree.

## Audit boundary

No checkout, merge, commit, ref update, production edit, test execution or
GitHub Actions query was performed by this audit. Only its intake artifacts
were written. Exact PR metadata, every incoming file/blob pair, all commit
subjects, branch counts and the dependency evidence are in
[concurrent-intake-355.json](concurrent-intake-355.json).
