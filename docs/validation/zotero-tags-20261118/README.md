# Zotero tag filtering — 18 November 2026

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
remain applicable. Optional spaCy/native-spelling drafts #139, #153 and #155
and the alternate Office continuations remain separate; none changes Zotero
paths. No incoming branch was rewritten or deleted.

Changes are saved incrementally to the remote continuation branch with
`[skip ci]` and non-forced updates requiring the observed branch head.
No GitHub Actions, check or CI status endpoints are queried or awaited.

## Implemented increment

Add literal tag filters to the Library search options. Multiple tags require
every tag and apply in Zotero before pagination, across libraries, collections
and desktop saved searches. Preserve selected sources and the last submitted
query while adding/removing filters or changing pages. Reject tag names that
the upstream search syntax cannot represent literally.

The client accepts optional `tags` on `items` and `savedSearchItems` and exposes
the shared `normalizeZoteroTags` validator. The dialog adds removable tag chips,
inline errors, clear-all and a collapsed active-count indicator. Names with an
initial hyphen remain literal; `||` and an initial literal `\-` are refused
because the upstream parsers interpret those as search syntax.

Focused development checks have passed: 14 new engine cases, 26 existing engine
catalog/saved-search cases and 20 new widget cases. The first widget attempt had
two test-harness failures, corrected by settling caret scrolling before taps
and testing a control character that Flutter's single-line field preserves.
No product code was changed for those test corrections. These overlapping
development counts will not be added to the complete acceptance cohort.

Complete regression validation is in progress. The preceding PR's test counts
remain attributed to its original report; they are not new executions here.

## Protocol references

- [Zotero Web API v3 search syntax](https://www.zotero.org/support/dev/web_api/v3/basics#search_syntax)
- [Pinned official documentation](https://github.com/zotero/zotero-docs/blob/11138a639ff8b137e8a7ba85a8bd8a69960ef25c/content/dev/web_api/v3/basics.md)
- [Pinned desktop search parser](https://github.com/zotero/zotero/blob/045d5204410f1abfd80910e1cd0aa92dceec741b/chrome/content/zotero/xpcom/server/server_localAPI.js)
- [Pinned online search parser](https://github.com/zotero/dataserver/blob/78a00c686a26a2914f83ffbb6e4451d48223ef72/model/API.inc.php)
