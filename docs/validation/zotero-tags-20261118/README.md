# Zotero tag filtering — 18 November 2026

## Delivered product

Qualified product and tests: **`4e06d42d20521f56164303aa6c135d5580ea0948`**.
All **675 substantive tests across 39 suites** pass, with zero skips or errors.
This product includes current main `1ffcf91a3443caf9a6e8b45a3e6cab3f041831ae`,
including the concurrent PR #155 merge and its native spaCy histories. The full
Zotero cohorts were rerun after the merge and exact workspace refresh. Earlier
qualification is preserved as a separate baseline and is not added to these
totals. Machine-readable acceptance is in [status.json](status.json).

## Starting point and preservation

PR [#156](https://github.com/CrispStrobe/quds_office_suite/pull/156) was reviewed
and merged into `main` as `c60fce9c37ca960eb64dd06c7ffc55b2fdbb2ed7`.
The continuation branch is `codex/zotero-tags-20261118`.

Before changing product code, all fork and upstream branch and pull-request
heads were fetched: **357 refs / 232 distinct heads**. The
[incoming inventory](incoming.json) freezes that pre-merge frontier. All 355
refs recorded in the previous
[final frontier](../zotero-capabilities-20261118/local/review/final-frontier.json)
still have identical SHAs. The only additions are PR #156 and its branch,
both at `f4aa218c87293527b3e2b7514500a28d13bd8f70`.

The previous [reconciliation decisions](../zotero-capabilities-20261118/RECONCILIATION.md)
were applicable at the initial fetch. At that point, optional spaCy/native-spelling
drafts #139, #153 and #155 and the alternate Office continuations were separate.
No incoming branch was rewritten or deleted.

A [late re-fetch](final-frontier.json) found concurrent PR #155 merged into main,
including the spaCy histories previously kept separate. It changes no Zotero
path, but changes shared spelling sources and adds a workspace package. The
continuation incorporated that main in the qualified merge commit and passed
new qualification against its actual 110-package graph. The
[integration record](integration.json) and [merge review](postmerge/merge-review.json)
retain the ancestry and conflict decisions. Both sets of changelog additions
were kept; no product source conflict occurred. Current main contains the heads
of PRs #139, #153, #155 and #156, regardless of historical PR draft labels.

Changes are saved incrementally to the remote continuation branch with
`[skip ci]` and non-forced updates requiring the observed branch head.
No GitHub Actions, check or CI status endpoints are queried or awaited.

## Implemented increment

Open **Library → Search options → Filter by tag**, enter a name and press Enter
or **+**. Add multiple tags to require every tag. Zotero applies them before
pagination across libraries, collections and desktop saved searches. Removing a
chip or choosing **Clear tags** returns to page one of the last submitted search.
Selected sources remain selected and draft query/tag text does not change paging.

The client accepts optional `tags` on `items` and `savedSearchItems` and exposes
the shared `normalizeZoteroTags` validator. The dialog adds removable tag chips,
inline errors, clear-all and a collapsed active-count indicator. Names with an
initial hyphen remain literal; `||` and an initial literal `\-` are refused
because the upstream parsers interpret those as search syntax. Tag filters are
bounded to 20 names, 256 UTF-16 code units per name and 2,048 total. Invalid input
shows an inline error without a request. Case and internal spaces are retained;
Zotero determines matching. Filters survive scope changes and reconnection in the
current dialog, and never change the document or remote library.

See the [user guide](../../zotero-support.md#filter-by-tags) for behavior and limits.

## Accepted current local validation

| Cohort | Suites | Substantive passes | Skips / errors |
| --- | ---: | ---: | ---: |
| [Engine Zotero](postmerge/engine/README.md) | 21 | 422 | 0 |
| [Editor Zotero](postmerge/editor/README.md) | 17 | 235 | 0 |
| [Studio transport](postmerge/studio/README.md) | 1 | 18 | 0 |
| **Disjoint total** | **39** | **675** | **0** |

The total includes **34 new cases** once: 14 engine and 20 widget regressions.
They cover literal syntax, Unicode, bounds, pre-request rejection, complete-scope
routing, pagination, selection, retry, reconnecting, late responses and twenty
tags at 320, 360 and 420 pixels. There are no missed-tap warnings in accepted runs.

[Strict analysis, Dart 3.12 formatting and whitespace checks](postmerge/checks/summary.json)
pass for all five changed Dart targets. The [independent source review](local/review.md)
confirmed literal semantics against both upstream implementations and caught the
matching-wording correction applied before final editor qualification.

The genuine [runtime](postmerge/runtime/README.md) is pinned Flutter 3.47.8 / Dart
3.13.7 with all 11 manifests matching the current source. The incoming spaCy
package brings the graph to 110 packages while preserving all 109 prior package
entries and the exact hosted lock. Every cohort has before/after source,
dependency, runtime, workspace and test-selection guards. All 418 engine,
536 editor and 616 Studio source inputs match the qualified merge commit
exactly; these overlapping source counts are not test totals.

Each cohort retains exact commands, actual exits, raw compressed events,
per-case outcomes and inventories. Hidden suite-loading events are excluded.

### Excluded attempts and setup

Focused development checks have passed: 14 new engine cases, 26 existing engine
catalog/saved-search cases and 20 new widget cases. The first widget attempt had
two test-harness failures, corrected by settling caret scrolling before taps
and testing a control character that Flutter's single-line field preserves.
No product code was changed for those test corrections. The first complete
editor attempt was interrupted for the wording correction; its Flutter child
exit is explicitly unknown, and it is not accepted. The later full run passes.
These attempts and the overlapping focused runs are retained under
`local/editor/attempts` and excluded from the totals above. The runtime's
31-test setup smoke and an earlier stopped, silent engine launcher are also
excluded. The complete 675-pass pre-merge baseline remains under `local/`,
qualified at `270a38ad` and saved remotely in `3ff67153`; it is not added to
the new 675-pass result. The preceding PR's counts keep their original source
attribution. Baseline artifact bytes remain unchanged.

## Scope

This qualification covers synthetic documents, controlled Zotero responses,
real Flutter widgets and local HTTP transport. It does not claim a new live
Zotero account or desktop-picker acceptance, a full application build or new
Microsoft Word/LibreOffice acceptance. No GitHub Actions, check or status
endpoint was queried, awaited or rerun.

## Protocol references

- [Zotero Web API v3 search syntax](https://www.zotero.org/support/dev/web_api/v3/basics#search_syntax)
- [Pinned official documentation](https://github.com/zotero/zotero-docs/blob/11138a639ff8b137e8a7ba85a8bd8a69960ef25c/content/dev/web_api/v3/basics.md)
- [Pinned desktop search parser](https://github.com/zotero/zotero/blob/045d5204410f1abfd80910e1cd0aa92dceec741b/chrome/content/zotero/xpcom/server/server_localAPI.js)
- [Pinned online search parser](https://github.com/zotero/dataserver/blob/78a00c686a26a2914f83ffbb6e4451d48223ef72/model/API.inc.php)
