# Zotero capabilities — 18 November 2026

## Delivered source

Product commit: **`1ccf329da190d47720962bd9d8c65c90acf562db`**.
Branch: **`codex/zotero-capabilities-20261118`**.
Later commits preserve documentation and evidence without changing the qualified
implementation or tests. Machine-readable acceptance is in [status.json](status.json).

The increment adds catalog search controls and makes connected refresh and API
bibliography preparation resolve document-declared source aliases. All **641
substantive tests** in the selected engine, editor and Studio cohorts pass with
zero skips or errors. GitHub Actions and CI status endpoints were not used.

## User-visible changes

### Catalog search and paging

The sliders button beside the Library search box opens **Search options**:

- Keep title/creator/year search, or choose **Include full text**.
- Filter to books, book sections, journal articles, conference papers, theses,
  reports or web pages, or return to all reference types.
- Sort by modification date, date added, title, creator, publication date or
  reference type, in either direction.

Zotero receives the options before pagination for libraries, collections and
desktop saved searches. Existing callers keep their original defaults. Full-text
matches depend on the connected library's indexed content; local and online
quick searches can differ.

Typing a draft query no longer changes **Next page** or **Previous page**. Both
continue the last submitted query. Submitting a search or changing an option or
catalog scope starts at the first page. Selection survives paging and filtering.
The compact default layout retains visible paging controls; expanded controls
are tested at 320, 360 and 420 pixels and retain state across reconnecting.

### Connected source aliases

The resolver reads validated Zotero URIs explicitly declared together anywhere
in document citations, then resolves late and transitive relationships before
requesting metadata. An older local-only citation can use a synced numeric alias
declared by a later citation, including a custom/native citation without its own
embedded CSL snapshot.

Basic refresh changes only basic citations. Citation IDs, item IDs, URI arrays,
locators, labels, prefixes, suffixes and unknown metadata remain intact. Unrelated
libraries and local profiles stay separate even when item keys match. Requests
still verify returned source identities and stage all updates before one undoable
application. Failed, missing, mismatched or stale responses leave the document
unchanged.

Each component uses its first numeric identity online or its first declared
identity on desktop. There is no speculative fallback after a failed request.
The existing limits count resolved sources: 1,000 for basic refresh and 50 for one
globally formatted API bibliography. The resolver separately bounds the complete
document input to 10,000 unique validated URI aliases. Native CSL processing and
individual catalog previews retain their existing contracts.

## Incoming work and remote preservation

The starting point is current main **`c8eca37d`**, including merged Office
qualification #154 and every previous Zotero branch head. The initial audit
fetched and classified **353 incoming refs**: 191 fork branches, 154 fork PR
heads, four upstream branches and four upstream PR heads. None remained
unresolved. [The reconciliation report](RECONCILIATION.md) and
[complete frozen inventory](reconciliation.json) record exact source identities,
full-tree equivalence and reviewed successor decisions.

The later native-spelling branch and draft PR #155 were also fetched and
classified in [the final frontier](local/review/final-frontier.json), bringing
the final inventory to **355 incoming refs and 231 distinct heads**. Main remained unchanged.
Drafts #139, #153 and #155 and the older alternate Office/spaCy continuation stay
separate, with their original histories and evidence preserved remotely.

Implementation, tests and evidence were saved incrementally with `[skip ci]`,
non-forced updates requiring the observed branch head, and byte-for-byte remote
readback. No original branch was rewritten or deleted.

## Accepted local validation

| Cohort | Suites | Substantive passes | Skips / errors |
| --- | ---: | ---: | ---: |
| [Engine Zotero](local/engine/README.md) | 20 | 408 | 0 |
| [Editor Zotero](local/editor/README.md) | 16 | 215 | 0 |
| [Studio Zotero transport](local/studio/README.md) | 1 | 18 | 0 |
| **Disjoint total** | **37** | **641** | **0** |

The increment adds **47 regression cases**: 18 engine query controls, 11 catalog
widget cases and 18 alias resolver/connected-operation cases. The final totals
include them once. Setup smokes, overlapping focused runs, hidden suite-loading
events and the rejected first editor run are excluded.

Strict analysis with `--fatal-infos`, declared-language Dart 3.12 formatting and
Git whitespace checks pass for all eight changed Dart targets. The final
[check receipt](local/checks/summary.json) binds their exact unchanged hashes.
The genuine pinned runtime is Flutter **3.47.8** with Dart **3.13.7**;
[runtime provenance](local/runtime/runtime-ready.json) retains official package
archive hashes, the exact workspace lock and setup records.

Before/after guards passed for source, tests, fixtures/assets, dependencies,
runtime, workspace configuration and test selection. The engine run's 416 source
inputs also [match the final product commit exactly](local/engine/final-source-equivalence.json).
The [independent review](local/review/review.json) passes **148 checks**, verifies
44 indexed evidence artifacts and binds 632 distinct source files to the final
product commit. It reconstructs outcomes from retained test events without
rerunning the product.

### Preserved rejected attempts

The [first full editor attempt](local/editor/attempt-1-f57fde45/README.md) recorded
214 successes and one pagination failure. It exposed the extra collapsed header
pushing **Next page** out of the existing viewport. That attempt also retains the
reporter's original machine-envelope parsing limitation and explicitly unknown
child exit. It is not accepted or added to the final total. The compact control
fix was followed by a complete clean editor run with zero missed-tap warnings.

The earlier strict-analysis attempt is retained under
`local/attempts/checks-before-compact-search/`; a deprecated test-only finder
description was replaced before the complete accepted checks.

## Reproduction and scope

Use the recorded exact runtime and dependency graph. The cohort READMEs provide
commands and preserved runners; raw compressed events, per-case results, process
exit receipts and hash inventories are included beside each summary. The external
validation workspace uses current production source with unchanged manifests.

This acceptance covers synthetic documents, mocked Zotero responses and the
Studio transport's local HTTP controls. It establishes client request routing,
UI behavior, metadata preservation, DOCX round-trip regressions and atomic
updates. It does not establish live search relevance, current private-account
or desktop-picker acceptance, a complete compiled application build, or new
Microsoft Word/LibreOffice interoperability acceptance. Historical live Zotero
results keep their original source attribution in [the validation history](../../zotero-validation.md).

## Protocol references

- [Zotero Web API v3: search, sort and pagination](https://www.zotero.org/support/dev/web_api/v3/basics#searching)
- [Zotero Local API: shared endpoints and local identity](https://www.zotero.org/support/dev/web_api/v3/local_api)

The added query options use the documented `qmode`, `itemType`, `sort` and
`direction` parameters. Filtering and ordering happen in Zotero before slicing
pages; they do not rearrange only the currently loaded records.
