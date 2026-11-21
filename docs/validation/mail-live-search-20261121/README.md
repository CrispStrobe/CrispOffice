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
