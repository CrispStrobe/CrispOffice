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
| `d30c473102fddf422413440eda46e184190cb649` | Compact EN/DE/AR controls, actual-font visual test and finite local qualification runner |
| `1dd6912549c473b1d31f35d7cc00b28bae7acf3d` | Report and pause cancelled cleanup failures, explicit recovery regression, and lazy-list test navigation correction |
| `2af7b938ff2bbb44e865ee970df1583bb7d4f3ef` | Complete accepted Mail qualification, raw execution archive and twelve visual captures |
| `3d49a13d9e3d01db2a273d43affd36140475b467` | Later landed main `e5940c79`, including completed Word numeric authoring and its independent evidence |

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

These are states at that capture. Word numeric authoring subsequently completed
its qualification and landed on main as `e5940c79`. The Mail branch incorporates
that exact main and its Word head in `3d49a13d`; its only new production change
is the bounded numeric-intrinsic dispatch. The two later Zotero draft heads
remain independent and were not promoted by this Mail increment.

The [final main reconciliation](main-reconciliation.json) replays all 163
initial observations with zero uncovered heads, preserves the complete engine
tree from landed main, and verifies that all Mail/editor production and active
dependency manifests are unchanged from the accepted Mail source. The only
merge conflict was the order of identical complete sections in the Zotero
README; every heading and section was compared before retaining main's order.
The canonical upstream's four heads and sixteen tags were rechecked unchanged.
This finite intake reconciles landed main without chasing independent draft
development indefinitely.

## Delivered increment

The [workflow contract](../../roadmaps/mail/live-saved-search.md) describes
explicit refresh, opt-in foreground intervals, staged results, fixed scope,
reader preservation, partial coverage and bounded recovery. Source and tests
are checkpointed before final qualification so work is not confined to the
local workspace.

The exact pinned Flutter 3.47.8 / Dart 3.13.7 runtime was obtained from the
official release archive and its SHA-256 verified. Dependency resolution used
the existing workspace lockfile without changing manifests or lockfiles.

The first finite gate at `d30c4731` passed strict analysis/format, all 57 store
cases and all 16 renderer cases. Studio completed 126 cases: 124 passed and
two compact-layout navigation cases failed because their lazy result rows had
not yet been materialized before `ensureVisible`. The corrected cases scroll
the actual results surface before retaining their sender-direction and layout
assertions. This failed attempt is preserved and is not the final Studio gate.

Independent review also found a cleanup error hidden by a cancelled refresh
epoch. The corrective checkpoint reports failed retired-owner closure while
the route remains current, pauses automatic work even during suspension, and
retains ownership for explicit Refresh or Close. A new regression covers the
failed closure, no retry after resume, and successful explicit recovery.
The affected Studio changes passed the corrected gate at `1dd69125`.

## Accepted local qualification

| Cohort | Accepted cases | Executed source | Applicability |
| --- | ---: | --- | --- |
| Studio cached search, refresh, saved searches and account chooser — seven suites | 127 | `1dd69125` | Final corrected source; includes native SQLite, cancellation, account revocation, selected reader retention, timing, close failure and explicit recovery |
| Mail store header search and saved definitions — two suites | 57 | `d30c4731` | Store source, tests, dependencies and lockfile unchanged by the final dialog-only correction |
| Word text/picture cache and frame-wrap regression — three suites | 16 | `d30c4731` | Incoming renderer source and its tests unchanged by the final dialog-only correction |
| Actual-font EN desktop, EN/DE/AR compact visual cases | 4 | `d30c4731` | Twelve result/reader/partial captures; final correction changes cleanup handling only, with no layout, strings, theme, fonts or visual fixture changes |

**200 automated regression cases plus four visual cases passed.** There are no
skips, unfinished accepted cases, runtime error events or stderr in the accepted
automated cohorts. Strict analysis (`--fatal-infos --fatal-warnings`) and format
verification pass for all eight changed/test/visual Dart files. Both finite
execution attempts capture 5,974 source inputs before and after each step; each
attempt's inputs stayed unchanged. The original failed Studio attempt is kept
separately and contributes no passing cases to this accepted total.

The visual gate uses the actual bundled fonts, Studio theme and native SQLite
adapter. At 360 × 640 with 1.3× text it checks for overflow, requires at least
180 logical pixels of reader viewport, and verifies that the first body
paragraph fits after normal reader scrolling. Existing compact tests also
retain 360 × 600 at 1.4× text and sender-direction assertions. These are local
widget/renderer/store checks; no live provider credentials, real server
downloads, platform installation or background-delivery qualification is
claimed by this increment.

### Later main integration gate

After main advanced to `e5940c79`, the combined checkpoint `3d49a13d` passed
all **204 cases across the three incoming numeric VBA suites**: 133 intrinsic,
59 conformance and 12 integration cases. These are additional distinct cases,
separate from the accepted 200 Mail/store/renderer cases above. Strict analysis
and formatting were repeated on the combined tree for 13 Mail/numeric Dart
paths and passed. All 5,980 captured source inputs remained unchanged, with
zero failed/skipped cases, runtime error events or stderr.

The [main integration receipt](main-integration.json) records this finite
merged-source acceptance and exact unchanged Mail applicability. The
[archive index](main-integration-index.json) verifies every entry in the
[main integration archive](main-integration.tar.xz), including the runner,
raw streams, SDK receipts and complete before/after source inventories. The
imported broader Word qualification stays in its own record; its historical
cases are not added to this task's totals.

Across these explicitly scoped local runs, **404 distinct automated regression
cases and four visual configurations passed**. Source identities and earlier
failed attempts remain separate; this is not a claim of one uninterrupted full
repository test run.

### Evidence

- [Qualification and source applicability](qualification.json) selects the
  accepted attempts, exact counts and unchanged dependency scopes.
- [Runtime provenance](runtime-provenance.json) records the official SDK archive
  digest, Flutter/Dart/native SQLite versions and unchanged locked resolution.
- [Evidence index](evidence-index.json) hashes every archived raw record and
  explains visual-source applicability without relabelling an earlier run.
- [Local execution archive](local-execution.tar.xz) retains raw event streams,
  command/exit receipts, source inventories, earlier failed attempts and the
  corrected accepted attempt. Archive contents were re-read and hash-verified.
- [Visual receipt](visual/visual-receipt.json) retains exact invocation, actual
  configurations, post-run source hashes and the twelve PNG hashes. The hashes
  are explicitly post-run; an uncaptured absolute execution timestamp is not
  invented.

Representative captures: [English results](visual/en-desktop-results.png),
[German compact reader](visual/de-compact-reader.png),
[Arabic compact reader](visual/ar-compact-reader.png), and
[German partial coverage](visual/de-compact-partial.png).

### Reproduce

Use the repository's pinned Flutter 3.47.8 / Dart 3.13.7 and existing lockfile.
Set `CI=true`, `FLUTTER_SUPPRESS_ANALYTICS=true` and
`DART_SUPPRESS_ANALYTICS=true` before starting Flutter. These supported SDK
settings keep the local runner out of cloud-metadata startup detection and
analytics. Resolve dependencies with `flutter pub get --enforce-lockfile`,
then from the repository root run:

```sh
python docs/validation/mail-live-search-20261121/run_local.py \
  --output /absolute/path/to/a-new-evidence-directory
```

The runner refuses to overwrite an existing evidence directory, executes the
selected finite suites serially with `--no-pub`, audits visible test lifecycles,
and records commands, SDK versions, stderr, source changes and output hashes.
It never waits for GitHub Actions. See the visual receipt for the separately
executed screenshot command.
