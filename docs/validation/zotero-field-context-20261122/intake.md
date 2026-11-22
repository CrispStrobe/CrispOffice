# Remote intake for native Zotero field context

## Baseline and result

Remote `main` was reconfirmed at **2eecf9aec2c7d1f979064448b911b516d3f56c73** on
22 November 2026 at 05:02:26 UTC. Its Git tree is
`71b98eaa9f636c2e3ed8b581214d2f4ecfd4c550`.

The pre-existing inventory contains **21 fork branches**, **four upstream
branches**, **zero open pull requests**, and the **30 most recently updated
closed pull requests**. Every captured closed PR is merged. GitHub comparisons
show all 20 non-main fork tips and all four upstream tips behind this baseline,
with zero commits ahead and each tip as its own merge base. Independent local
ancestry checks also passed for all 25 captured branch tips (including main)
and all 30 captured PR heads at 2026-11-22T05:02:53.271057+00:00.

**No incoming source or ancestry merge was required.** The new work starts from
that main commit. The parent-created branch
`codex/zotero-field-context-20261122` is a task output, excluded from the
pre-existing inventory. No branch was deleted or force-updated by this audit.

The exact heads, comparison counts, local check results, PR titles, GitHub
timestamps and source endpoints are retained in [intake.json](intake.json).
The initial remote fetches did not capture per-call timestamps; the record
explicitly distinguishes those observations from the timed main/open-PR
recheck and subsequent local ancestry verification. This is a bounded intake,
not a new audit of every historical PR.

## Recent integration order

| PR | Integrated work | Merge commit |
| --- | --- | --- |
| [#353](https://github.com/CrispStrobe/quds_office_suite/pull/353) | Extend Zotero desktop item navigation with safe source identity [skip ci] | `c522851d165b395a7f60422a1be969dffc39c9ff` |
| [#354](https://github.com/CrispStrobe/quds_office_suite/pull/354) | Mail: exact folder-scoped saved searches with safe local recovery | `bcc55cb6e86e796056e2d75c3fdca50857dbf6e7` |
| [#355](https://github.com/CrispStrobe/quds_office_suite/pull/355) | Extend Word VBA formatting for existing table cells | `ceddcd888c37f64e37a8d8d1669daaea31384daf` |
| [#356](https://github.com/CrispStrobe/quds_office_suite/pull/356) | Mail: recoverable saved-search folder sets and combined local qualification | `82659acb0f617c57d4d241c91033338032b5caac` |
| [#357](https://github.com/CrispStrobe/quds_office_suite/pull/357) | Reconcile late Mail picker commits without changing qualified source | `171be42cf92ce875b7d5f6f3df216ff04d0204c5` |
| [#358](https://github.com/CrispStrobe/quds_office_suite/pull/358) | Finalize Zotero writing-position parity and reconciled qualification [skip ci] | `2eecf9aec2c7d1f979064448b911b516d3f56c73` |

PR #356 already incorporated the native Zotero writing-position source and
stale-target guard; #358 published its remaining history and qualification.
PR #357 retained late Mail history while keeping the completed catalog-based
picker. Its replacement deliberately supersedes intermediate picker compile
repairs; those older implementations must not be restored during this work.

## Applicable constraints and scope

No tracked `AGENTS.md` or `CLAUDE.md` was found. Root `.cursorrules` and
`CONTRIBUTING.md` require pure-Dart engine code, RenderBox document surfaces,
fully typed code, complete implementations, relevant behavior tests and
package changelog updates for public or user-visible changes. Flutter is pinned
to 3.47.8; the workspace Dart constraint is `^3.12.0`.

The existing Zotero roadmap identifies visible `Field.select` context and safe
malformed-field recovery as native gaps. Installed Zotero, Word, LibreOffice
and legacy OpenOffice acceptance remains separate from local source tests.

This intake used read-only GitHub and local Git operations. GitHub Actions,
workflow runs and checks were neither queried nor awaited.
