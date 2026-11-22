# Incoming Word and Mail exact-head intake

This audit covers the remote heads captured during the Zotero work on 22 November
2026. The parent supplied the remote snapshot and zero-open-PR observation; this
review did not fetch, merge, change remote refs, or query GitHub Actions.

## Captured ancestry

| Role | Exact commit | Status against captured main |
| --- | --- | --- |
| Initial main | `2eecf9aec2c7d1f979064448b911b516d3f56c73` | Ancestor of all captured heads |
| New main | `191ed89b23696c5634689bb90b87119c761f0c85` | Merge of Word branch as PR #359 |
| Word branch | `5f6e8686f1d6ddc1f3e523238808b78ccccc5b51` | Already contained in new main |
| Mail branch | `29fc72a0a7cffa7cfed2abdac2a3f82d2ff17f95` | Four unique commits; not in new main |
| Zotero checkpoint | `e8cc579563f9c2d9a8922ed47bc8fe310f1ed0af` | Four unique commits; not in new main |

Mail has already merged Word implementation/test commit `d16649e9`, the common
ancestor of the captured Mail and new main heads. It lacks only Word's later
qualification commit `5f6e8686` and main's merge commit. Therefore a raw main-to-Mail
tree diff would misleadingly remove final Word evidence. Preserve ancestry with
merges of the captured main and qualified Mail head.

## New behavior and maturity

**Word is completed and merged.** Its single changed production file is
`packages/quds_office_engine/lib/src/automation/office_vba_language.dart`.
It adds bounded `Join` over local allocated String arrays and the direct Word
`Cell.Range` controls `HighlightColorIndex`, `NoProofing`, `LanguageID` and
`LanguageIDOther`, using existing guarded native run-format steps. The branch
includes seven affected test files, two portable harnesses, a versioned Join
corpus, examples, contracts and final evidence. Its README records 6,753 passing
cases and successful VM/JavaScript comparisons. Those are imported receipts;
this audit does not claim to have rerun them.

**Mail was an active checkpoint and now passes this fresh local gate.** The four unique
commits are intake (`0f6be0b5`), catalog/session (`72cb157f`), Studio navigation
(`e6ef3143`) and Word reconciliation (`29fc72a0`). Its validation README still
states that implementation and fresh execution are pending, although source and
three new test suites are committed. No final Mail receipts are present at this
head. Fresh detached-worktree execution has now passed 191 tests across eight
suites, with clean analysis of all four changed source files and three new
tests. No source fixes were needed. [qualification](qualification/README.md)
contains the commands, outcomes and provenance.

All four changed Mail production paths are confined to
`packages/quds_office_editor/example/lib/`:

- `studio_mail_cached_mail.dart`
- `studio_mail_cached_strings.dart`
- `studio_mail_mailbox_session.dart`
- `studio_mail_retained_folders.dart` (new)

The feature combines browsing-window and synchronized-membership folders in one
account-scoped local catalog, offers explicit source choice, and supports bounded
100-row synchronized pages with repair after membership shrink. It guards reader
ownership and stale callbacks across source/folder/page changes, drains owned
observers on cleanup, and adds English/German/Arabic controls. It does not change
shared Mail transport/store APIs, dependencies or schemas. Durable remote
move/delete remains a separate later milestone.

## Merge overlap

Read-only `git merge-tree` previews against the initial main found only
simultaneous leading CHANGELOG additions:

| Candidate with Zotero checkpoint | Text conflicts |
| --- | --- |
| New main | Engine CHANGELOG |
| Mail head | Engine and editor CHANGELOGs |

No production, test or existing validation paths overlap Zotero's checkpoint.
Resolve changelogs by retaining both sets of entries. Parent changes made after
`e8cc5795` still require the normal final merge review. Exact production blob and
SHA-256 identities, complete unique commit/path lists, and ancestry results are
in [audit.json](audit.json).

## Local acceptance scope

The detached Mail worktree uses the captured commit, sparse source checkout and
offline lockfile-enforced dependency resolution. Its package configuration must
resolve workspace packages inside that worktree. Qualification runs all three
new Mail suites plus existing mailbox-session, cached-reader, cached-host,
shortcut-host-ownership and workspace-mail-shortcut coverage. Analyze all four
changed source files and three new tests. Save command, source, test, runtime and
log identities alongside actual results; do not treat prior branch counts as
fresh evidence.

On the final integrated source, run the planned Zotero suites and focused Word
Join/cell-control tests plus native atomicity/structure/table-grid coverage. The
exact proposed Word command is in `audit.json`. If merged Mail source blobs are
unchanged, the detached-head qualification remains applicable; if those paths
change, rerun the affected suites on the integrated result. No GitHub Actions
wait is needed.

## Follow-up: Mail qualification and combined ancestry at `a7006171`

A later parent refresh captured
`a7006171630915bbf91b6ce2ab7c4699bb79f69b`; main remained `191ed89b` and no open
PRs were reported. Read-only ancestry checks confirm that this Mail head now
contains earlier Mail `29fc72a0`, main `191ed89b`, Word `5f6e8686` and Zotero
`e8cc5795`. Its first-parent additions are the Zotero groundwork merge
`14549862`, main merge `c8e09105`, Zotero prompt merge `83974fba`, and qualification
commit `a7006171`.

**Use this combined Mail head instead of separate main and `29fc72a0` merges.**
Preserve newer local Zotero fixes and perform the planned final integrated
regression. This recommendation supersedes the earlier two-merge recommendation;
the original captured-head audit and all qualification receipts remain intact.

All four Mail production files, all three new Mail tests, the five companion
tests executed by this audit, and the recorded manifests have identical Git
blobs at `29fc72a0` and `a7006171`. All 18 explicit qualification inputs were
compared. The only additional Zotero product delta beyond `e8cc5795` is a
formatter correction to two indentation lines in `office_controller.dart`'s
`presentedFieldContext` ternary; its whitespace-ignored diff is empty. Other
Zotero source and test blobs remain unchanged. No new semantic source change
was discovered in this follow-up.

The new incoming Mail record now reports **115 passing cases across five suites**
on integrated source `83974fba`, exit 0, zero failures/skips, and clean strict
analysis of all seven changed Mail Dart files. It retains earlier-source host
limits, unsuccessful/superseded development attempts and earlier missing-exit-code
receipt limits. Its final rerun resolves that exit-code uncertainty. Prior
cleanup/cancellation review findings are covered by the unchanged final Mail
implementation; no material open review finding is reported.

That imported 115-case run overlaps this audit's independent **191-case** run;
the totals must not be added. The 191-case receipt still identifies `29fc72a0`
and has not been relabeled as execution on the newer head. Blob continuity and
the imported integrated evidence are recorded additively in `audit.json` under
`follow_up_snapshots`. No additional test execution or remote operation was
performed for this follow-up.
