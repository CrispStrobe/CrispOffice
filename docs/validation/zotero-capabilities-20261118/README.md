# Zotero capabilities — 18 November 2026

## Starting point and preservation

Work starts at Quds main `c8eca37d1639ac1d20efb83ba2e9da51981a3ad4`,
including merged Office qualification PR #154 and all prior Zotero work.
The working branch is `codex/zotero-capabilities-20261118`.

All fork branch and pull-request heads were fetched before implementation;
upstream branch and pull-request heads were fetched as well. The adjacent
reconciliation inventory records exact identities and dispositions. Open native
spaCy drafts #139 and #153 remain separate, with their source preserved remotely.
Superseded histories are accounted for without reintroducing removed behavior.

Incremental checkpoints use `[skip ci]`, non-forced expected-head updates and
remote readback. GitHub Actions and CI status endpoints are not used.

## Intended improvement

- Add server-side catalog search scope, item-type filtering and sorting for
  online libraries, desktop libraries, collections and desktop saved searches.
- Keep pagination bound to the last submitted query while search text is edited.
- Resolve connected source identities across document-declared URI aliases so
  older local citations can use a proven synced alias during refresh.

Defaults retain the current title/creator/year search and recently modified
ordering. Full-text results depend on Zotero's indexed content. Connected
refresh remains staged and undoable; source identity metadata is retained.

## Validation status

Implementation and local qualification are in progress. This checkpoint does
not claim test success. A genuine pinned Dart/Flutter runtime is being prepared;
new regressions and the existing Zotero suites will run locally before delivery.

## Protocol references

- [Zotero Web API v3: search, sort and pagination](https://www.zotero.org/support/dev/web_api/v3/basics#searching)
- [Zotero Local API: shared endpoints and local identity](https://www.zotero.org/support/dev/web_api/v3/local_api)

The added query options use the documented `qmode`, `itemType`, `sort` and
`direction` parameters. Filtering and ordering happen in Zotero before slicing
pages; they do not rearrange only the currently loaded records.
