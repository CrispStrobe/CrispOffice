# Saved-search folder sets — work and qualification record

**Locally qualified, 22 November 2026 (Europe/Berlin).** The Mail increment has
**1,632 distinct passing cases**. The integrated Word and Zotero regression
gates add **1,107**, for **2,739 distinct passing cases**, plus Word VM/JavaScript
checks and strict analysis/formatting. This is scoped local qualification, not
whole-product or live-provider acceptance.

Qualified source is `96b3e57c6c10f4419ed86ce4aa132e5d3c79c851`, tree
`f360334ae8ba3d43a90c77fbe936f9ec9f1ebcdd`. Subsequent Zotero evidence integration
`02f66ee686ad196a0fe162da9394b5b016739abd` changes documentation and evidence only;
all package and lock files remain identical. The exact per-stage working-file
identities and any formatter-only transition are retained below.

## Repository intake and integration

Work began from fork `main` at
`c522851d165b395a7f60422a1be969dffc39c9ff`, on branch
`work/mail-folder-search-20261122`. The GitHub branch, pull-request and comparison
endpoints were inspected before implementation. There were zero open pull
requests; all 16 non-main fork branches had zero commits ahead of main.
Upstream `MohammedAsaadAsaad/quds_office_suite:main` at
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` was already an ancestor. Existing
branches were retained.

The baseline already contained saved-search foreground refresh (#345), range
selection/address search (#349), combined-source qualification (#352), and
Zotero desktop navigation (#353). Earlier receipts were not treated as proof
of this increment.

Several branches advanced during the work. All were reconciled, including:

| Incoming work | Included head or merge |
| --- | --- |
| Independent Mail folder scopes, PR #354 | `bcc55cb6e86e796056e2d75c3fdca50857dbf6e7` |
| Word VBA cell formatting | `49f43824196c4d373f991e442fac2e73e68c5f9f` |
| Main after Word PR #355 | `ceddcd888c37f64e37a8d8d1669daaea31384daf` |
| Zotero writing-position source and stale-state correction | `b7758d482a0381c5c3ad526675321de80989465e` |
| Latest Zotero qualification records | `3660a9d94e3100885e61b244f9dba7bdc5403cfb` |
| Original upstream main | `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` |

The Mail merge preserved published schema 11 instead of rewriting it. Additive
schema 12 retains the published `has_folder_scope` flag, folder rows, revisions
and 200-folder limit, and adds only optional display-label snapshots. Literal
published-v11 fixtures verify migration, rollback, retry and corruption refusal.
The `folderScopes`, `maxFolderScopes`, repository `folderIds` and legacy Studio
scope port remain compatible with the new typed API.

The final recorded intake has zero unincorporated fetched branch commits and
zero open PRs before creation of this work's PR. See [exact refs](remote-intake.json).
Merge commits preserve the original branch histories. Changelog conflicts were
resolved by retaining both feature entries; no incoming feature was dropped.

## Acceptance boundary and resulting behavior

- Persist an immutable, bounded set of exact account/mailbox identities.
- Keep existing all-folder definitions and revision-guarded updates.
- Filter retained browse and sync memberships before counting/paging; bind
  continuations to the canonical set and deduplicate stored message identity.
- Retain selected-folder provenance, including explicit missing-folder coverage.
  A missing or empty explicit scope never becomes an all-folder query.
- Preserve healthy selected-folder matches with incomplete coverage, disable
  automatic refresh while coverage is incomplete, and offer explicit repair.
- Provide local choose/search/save/reopen/update/reset paths with English,
  German and Arabic labels, RTL, narrow layouts and enlarged text.
- Recheck scope at final publication and refresh; remove an account's earlier
  hits after later-page failure, and reject stale scoped reader openings.
- Preserve exclusive repository ownership, close/retry recovery and identity
  fencing. Discovery reads retained headers only, without provider traffic.

The [workflow and API guide](../../roadmaps/mail/folder-saved-search.md) describes
the interaction, quotas, compatibility and recovery contracts.

## Successful local gates

| Gate | Distinct passing cases | Result |
| --- | ---: | --- |
| Complete `quds_mail_core` suite | 503 | Exit 0 |
| Complete `quds_mail_store` suite | 970 | Exit 0 |
| Studio native host/session, four suites | 89 | Exit 0 |
| Studio picker/search/save/refresh/lifecycle, seven suites | 70 | Exit 0 |
| Word cell-formatting and adjacent regressions, 13 suites | 715 | Exit 0 |
| Zotero engine, six suites | 180 | Exit 0 |
| Zotero editor, seven suites | 209 | Exit 0 |
| Direct stale-host note-target regressions | 3 | Exit 0 |
| **Total** | **2,739** | **All final gates pass** |

Focused subsets and reruns are counted once. Core/store coverage includes real
SIGKILL recovery, legacy migrations, literal schema-11 migration, unavailable
folder behavior, bounded paging and saved-definition replacement.

The actual committed `word_table_formatting.bas` also ran on Dart VM and compiled
JavaScript under Node. Both performed 52 operations, replayed 52 recorded steps
and completed two additional save/reopen cycles. Structured results matched,
including boolean-versus-number distinctions. Assertions cover neighboring XML
semantics, opaque/VBA bytes, metadata apart from normal save timestamps, and
late-failure rollback. Raw number spelling can differ (`14.0` versus `14`).

All 45 changed Dart files pass `dart analyze --fatal-infos --fatal-warnings` and
the read-only pinned formatter. Complete Mail core/store analysis is also clean.
Six imported files were normalized late with the pinned formatter; both sides
parse without errors and have identical AST `toSource()` output. Three equivalent
string interpolations fixed five infos in the retained compatibility picker
and its test; all three picker cases passed afterward. These are recorded source
transitions, not a claim that earlier logs executed byte-identical later files.

Final host/session and Zotero runs record working-file hashes before and after;
those hashes stayed unchanged while Git publication identities advanced. The
core/store package trees are byte-identical to the fully tested reconciliation
trees. The two-file Zotero follow-up leaves the engine and its six suites
unchanged; the editor and three stale-host cases were rerun after integration.

## Runtime and reproducibility

The genuine runtime is Flutter **3.47.8** / Dart **3.13.7**, with SQLite **3.54.1**
and FTS5, and Node **24.22.3**. The official Flutter archive SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
All 204 hosted dependency archives were verified and workspace resolution used
`--offline --enforce-lockfile`. The tracked lockfile remains
`2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.

The ordinary `dart test` bootstrap stalled and was interrupted; that attempt is
not a pass. Native pure-Dart suites used a verified compiled `package:test`
launcher with an explicit workspace package configuration. Flutter suites used
`flutter test --no-pub`. Exact argument arrays, working directories, exits and
log hashes are in the receipts, rather than reconstructed shell transcripts.

- [Machine-readable qualification](qualification.json) maps each gate to its
  archived receipt and states the source-continuity and counting rules.
- [Runtime provenance](runtime-provenance.json) records SDK, archive, dependency,
  test-runner and native SQLite identities.
- [Source manifest](source-manifest.json.gz) inventories tracked Dart/BAS/config
  files in the four affected packages. It does not imply exhaustive coverage of
  every inventoried file.
- [Raw evidence archive](raw-evidence.tar.gz) contains commands, logs, failed
  attempts, final receipts, formatter snapshots/diffs and the portable runner.
  Its [index](raw-evidence-index.json) and inner `SHA256SUMS` bind every member.
- [SHA256SUMS](SHA256SUMS) verifies this record and its accompanying files.

## Earlier attempts and resolved findings

The first completed implementation at `b0d5f867...` had 1,609 distinct passing
cases before reconciliation. That total is historical and is not added to the
final 2,739. Its full storage run initially exposed two obsolete schema-v7
fixture failures; rebuilding that fixture now also removes the newly introduced
child table, and all 23 synchronization cases passed afterward.

During integration, incoming fixtures needed an unambiguous matcher import and
a required account profile. UI fixtures needed to scroll virtualized rows into
view and wait for focus-driven scrolling before actual hit-tested taps. The
first aggregate UI attempt was stopped after a separate failure and is not
counted. Mounted-guard/formatting/interpolation findings were corrected, and
the final strict analysis gate is clean.

The first Zotero editor gate passed 208 cases and found one invalid new TOC
fixture: it supplied an item without entries, so normal TOC rebuilding removed
that item before the tested operation. A temporary local fixture repair passed
209 cases; its patch remains historical evidence. Incoming `b7758d482` provided
the stronger real-heading/generated-item fixture and an early stale-document
check. Those incoming versions are the final source and passed the repeated
209-case gate plus the three direct stale-host cases.

Initial launcher issues, unsuccessful analysis/format checks and historical
reruns remain in the archive. Successful reruns do not erase failed attempts.

## Incremental remote preservation

The remote work branch retains checkpoints for intake, core/store, host/session,
UI/docs, schema/API reconciliation, Word/Zotero integration, latest main ancestry,
the Zotero follow-up, final normalization and incoming qualification records.
Full SHA identities are in `qualification.json`. Publication verifies each
remote blob and tree against the local Git object and uses expected-head leases;
merge commits retain all incoming parents.

GitHub Actions were neither queried nor awaited. Checkpoint messages use
`[skip ci]`; local evidence is the acceptance gate. The final publication uses
a merge commit to retain the branch/checkpoint ancestry.

## Remaining parity work

This completes one discovery milestone, not Outlook/Thunderbird/eM Client parity.
Next are repository-observed unified navigation and durable move/delete with
intent journaling, provider capability boundaries and uncertain-outcome recovery.
Broader categories/rules can build on those commands and exact saved scopes.
Richer composition, provider Sent reconciliation, persistent cross-folder
conversations, indexed body/provider search and Calendar/People remain later
milestones. Installed-platform, browser and live-provider acceptance are still
separate work; these tests do not establish them.

## Post-merge branch reconciliation

PR #356 merged this increment into main at
`82659acb0f617c57d4d241c91033338032b5caac`. The verification fetch then observed
Zotero branch commits `067ca3a47` and `ad965773b`, which repair imports and
guarded interface casts in the earlier dialog-owned Mail picker. The qualified
implementation already replaces that method with the typed catalog session
and its ownership/recovery checks. Reconciliation therefore preserves the
qualified dialog byte for byte and records both incoming commits as merge
ancestors. No production or test source changes are introduced.

The [late integration record](late-integration.json) contains the exact incoming
heads, resolved file hash, original delta and zero-diff verification. It extends
the earlier intake snapshot without rewriting that snapshot or adding duplicate
test counts. The prior 2,739-case gate and strict 45-file analysis/format gate
remain applicable.
