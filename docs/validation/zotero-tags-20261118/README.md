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

## Planned increment

Add literal tag filters to the Library search options. Multiple tags require
every tag and apply in Zotero before pagination, across libraries, collections
and desktop saved searches. Preserve selected sources and the last submitted
query while adding/removing filters or changing pages. Reject tag names that
the upstream search syntax cannot represent literally.

Implementation and validation are in progress. The preceding PR's test counts
remain attributed to its original report; they are not new executions here.
