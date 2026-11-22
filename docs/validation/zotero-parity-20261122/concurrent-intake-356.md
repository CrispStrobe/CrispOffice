# Final concurrent intake — completed Mail reconciliation PR #356

Final observed snapshot: 2026-11-22T02:58:22.950491+00:00.
This addendum supersedes the outstanding-branch dispositions in the
[initial intake](concurrent-intake.md) and [PR #355 addendum](concurrent-intake-355.md).
Those earlier snapshots remain intact as historical evidence.

## Completed incoming work

GitHub confirms [PR #356](https://github.com/CrispStrobe/quds_office_suite/pull/356),
**Mail: recoverable saved-search folder sets and combined local qualification**,
is closed and merged. Its completed branch head is
`f8b3857fca9e120be61c861baa786ff04c822ebe`; remote main is
`82659acb0f617c57d4d241c91033338032b5caac`.

The advance from `ceddcd888c37f64e37a8d8d1669daaea31384daf` contains
**21 commits**, **132 changed paths**,
**16,397 text additions** and **844 text deletions**.
These counts include retained Zotero implementation/evidence ancestry and the
final Mail qualification artifacts; they do not describe 21 independent Mail
feature commits.

The completed Mail record incorporates the original Zotero work through
`3660a9d94e3100885e61b244f9dba7bdc5403cfb`, including writing-position mapping,
controller selection preservation, regression tests and the stale-document
error-contract correction. **Those implementation changes have already landed
in remote main through PR #356.** Final Zotero publication principally retains
combined-source qualification, evidence and merge history.

## Exact preservation in the final integration

The local combined merge is
`ff45b281ca1d93c463d801ccf008d5a755e14cfb`; its canonical published equivalent is
`fce7a97f297181f3524b31e90e7a49ce061b0954`.
Both have the same **complete Git tree** as incoming main:

`3a728f96ac95588e45c9ab0c7d12e0881f702783`

Independent comparisons show no differing path between either merge tree and
`82659acb0f617c57d4d241c91033338032b5caac`. **All 132 incoming changed paths are
preserved exactly**, as is the rest of main's content. This equality covers
production, tests, manifests, applications, third-party code and documentation,
not only a selected production subset. Later final-evidence documentation
additions are recorded separately.

The merge base with our previously qualified source
`99a285c07ad2c08999ae64a68785376123bed4f3` is
`3660a9d94e3100885e61b244f9dba7bdc5403cfb`. Our only changed path after that common
ancestor was `studio_mail_cached_search_dialog.dart`.

### Why the incoming Mail dialog is retained intact

Our interim repair added the mailbox-store import and explicit guarded casts
needed by the older inline folder chooser. The completed Mail implementation
replaces that chooser with `StudioMailCachedSearchSession.loadFolderCatalog()`,
the new picker and localized labels. It removes all three old mailbox-store
type references, their casts and the direct-owner lifecycle from the dialog.

The incoming dialog therefore supersedes the temporary repair. Its catalog
implementation imports the mailbox-store types in the module where they are
now used. Retaining the entire incoming dialog avoids resurrecting the older
flow or leaving an unused import. Its blob matches main exactly.

## Imported-source impact and final checks

Relative to `99a285c0`, thirteen production libraries change:

| Area | Changed libraries | Consequence |
| --- | ---: | --- |
| Mail core/store | 4 | Shared Studio Mail model, persistence and session dependencies change. |
| Studio Mail | 8 | Folder selection/recovery behavior and workspace compilation dependencies change. |
| Engine automation | 1 | Existing function call receives line wrapping and a trailing argument comma; it is outside the Zotero import graph. |

The native Word and Zotero engine trees, complete editor library, applications,
third-party tree and dependency manifests are byte-identical to the previously
qualified source. All **56 engine**, **53 editor** and **4 Studio** selected
Zotero test entrypoint files are also unchanged. Two non-Zotero VBA test files
have formatting changes; no new engine behavior was found in the single
production formatting patch.

Standalone engine/editor Zotero execution can therefore be carried forward
with this source attribution. Whole-workspace manifests are not claimed to be
identical: Mail and automation files did change.

Studio's shared-workspace dependencies require fresh integration verification.
The parent reports the final canonical source
`fce7a97f297181f3524b31e90e7a49ce061b0954` passed **55 Studio cases**, plus strict
analysis and formatting of the **five-file scope**. The four Studio test files
are the existing citing-transport, Zotero shortcuts, ODT export and shortcut
host-ownership suites. Exact execution receipts remain in the main work record;
this audit independently verifies source preservation and does not claim a
second execution of those tests.

PR #356's own record reports 2,739 distinct cases across Mail, Word and selected
Zotero cohorts, on pinned Flutter 3.47.8 / Dart 3.13.7. Those incoming results
retain their original attribution and are not added to this task's fresh
Zotero counts.

## Final branch disposition

All **19 other non-main fork branch tips** and **four upstream branch tips**
are now ancestors of incoming main: **23 accounted for, zero ahead**. The
formerly unfinished Mail head is completed and merged through #356. GitHub
reports **zero open PRs** at the captured observation time.

There is no remaining unique fetched branch work outside main, apart from this
task's own final publication/history continuation. Earlier qualification-pending
and schema-conflict descriptions apply only to their earlier recorded heads.
This audit stops at the stated observation timestamp and does not poll branches
or GitHub Actions further.

## Evidence boundary

Only intake documentation was written by this audit. No source edit, checkout,
merge, commit, ref update, test execution or GitHub Actions query was performed
by the audit agent. The parent performed and published the integration.

[concurrent-intake-356.json](concurrent-intake-356.json) retains exact PR
metadata, all 21 commit subjects, every incoming path/blob pair, the comparison
with the prior qualified work, the full-tree proof, selected test entrypoints,
all branch ancestry counts and final gate attribution.
