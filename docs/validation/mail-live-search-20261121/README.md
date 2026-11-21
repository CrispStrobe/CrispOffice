# Saved-mail refresh work record — 21 November 2026

## Repository reconciliation

Captured remote main: `aa861c28e336b17bcd4c259351164380cd6b1438`.
The initial inventory contains all 43 fork branches, the 100 most recent PR
heads (#240–339), the one open draft PR, and all four canonical upstream
branches plus 16 tag commits. It is a bounded recent-work inventory, not an
assertion that every historical PR was re-audited.

Two heads were ahead of captured main: `c0ae75c226b13ae1ec4ab31238004d558ad01531`
and `a7f69313ed2e610f82242c31be8ad5387ae5cea0`. Their production changes were
already on main; the remaining additions were final validation/support records
and two renderer regression suites. Both exact heads are parents of the saved
integration checkpoint `5f1446bc0710f6914de307b5e8904d781eb83c06`. The one shared
README retains both completion sections and the original qualification history.

All 163 captured ref observations (121 unique commits) are actual ancestors of
that checkpoint. [intake.json](intake.json) retains the exact refs and local
`git merge-base --is-ancestor` outcomes. There are zero uncovered captured
heads and no inferred historical-equivalence substitutions. No upstream
production change was missing.

Work branch: `work/mail-live-search-20261121`. Updates use expected-head,
non-forced GitHub ref writes. Local Git tree hashes are matched to the remote
tree before advancing the branch. GitHub Actions, checks and status queues
are neither consulted nor awaited.

### Incremental remote checkpoints

| Checkpoint | Saved result |
| --- | --- |
| `5f1446bc0710f6914de307b5e8904d781eb83c06` | Both outstanding initial branch heads and their complete evidence/test history |
| `b80f5c27a67ece5692dfd8dc916ab5a57736976f` | Refresh collector, foreground UI, localizations, focused regressions and roadmap |
| `1360ead9e080fcf884ccac6cbc87bd6a58efdb5b` | Final whole-scope authority recheck, regression and latest landed main `511df2a0` |

The final scope recheck closes an independently reproduced design gap: account
A can be retired after its last page while account B is still being scanned.
Before publishing, one directory snapshot now revalidates every captured
identity/revision and removes all hits from changed or missing accounts. The
retained reader and automatic updates follow that failure state.

### Later concurrent work

The [publication snapshot](publication-intake.json) records five current fork
branches and the latest 100 PR heads (#243–342). Main `511df2a0` is preserved,
including its paragraph/frame-owner rendering cache. Three other branches
advanced after the initial intake and remain active independent work:

| Captured head | State at capture |
| --- | --- |
| `97538d025b260bd67c559962be9e9f159a6de06e` — Word VBA authoring | Implementation checkpoint; its final source-bound qualification is explicitly pending |
| `f6236ff5588441a24f9c8cc9c1dd4370d77eaddb` — Zotero note layout | Draft PR #342, explicitly work in progress; completion qualification pending |
| `4b33109aa85e077e2798265efa045d640e6ead4e` — Zotero ODT continuation | Draft PR #333; new position guard has no fresh qualification record at capture |

Those later heads remain on their remote branches and are recorded exactly.
Their unfinished source is not promoted by this mail increment. This does not
change the complete ancestry coverage of the initial 163-ref inventory. The
canonical upstream's four heads and sixteen tags were rechecked unchanged.
Only subsequent landed-main changes are reconciled before final publication;
this finite intake does not chase independent draft development indefinitely.

## Increment under qualification

The [workflow contract](../../roadmaps/mail/live-saved-search.md) describes
explicit refresh, opt-in foreground intervals, staged results, fixed scope,
reader preservation, partial coverage and bounded recovery. Source and tests
are checkpointed before final qualification so work is not confined to the
local workspace.

The exact pinned Flutter 3.47.8 / Dart 3.13.7 runtime has been obtained from the
official release archive and its SHA-256 verified. Dependency resolution and
local execution are in progress at this source checkpoint. **No passing test
count is claimed yet.** The final evidence update will replace this pending
status with actual commands, results and source applicability.
