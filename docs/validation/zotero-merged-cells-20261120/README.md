# Zotero horizontal merged cells and adjacent-citation Refresh

## Status and delivered behavior

This continuation adds horizontal merged research-table cells and native Zotero
Refresh merging for directly touching citations. Current-main source
`180399f99a3898501ab1959e3b845150d7da59fd`, tree
`500931fdbb32699dcce23e3f4eb293b9141168b2`, completed **1,801 passing cases and
eight skipped cases** across the final engine, editor and incoming Word/Mail
processes. All three processes exited zero with a successful terminal event and
zero failures or errors. The eight skips are existing image-only layout fixtures;
all 257 Zotero editor cases executed and passed. Publication targets remote
`main` through the continuation pull request.

This is bounded local qualification. It does not establish complete Zotero
plugin parity, active ODT citation transfer, or a new installed Zotero, Word or
LibreOffice round trip. The [usage guide](../../zotero-support.md) and
[parity roadmap](../../roadmaps/zotero/word-processor-parity.md) describe current
behavior and remaining work.

The [reconciliation account](reconciliation-698.md) records the initial source
preservation and focused scope. The combined qualification is now accepted at
published source `c62338c65571aa399da5592455b651fa5c6a9317`, after the subsequent
main `0a2afc41` reconciliation. The
[final Word/Zotero report](../word-final-integration-20261120/README.md) binds the
470 engine and 257 editor Zotero case identities to that source: 188 engine
and 143 editor cases ran fresh, while 282 engine and 114 editor cases retain
independently audited incoming raw results and exact relevant source inputs.
These are identity-preserving populations, not totals to add to earlier runs.

The earlier `80e240ec` attempt remains historical and unaccepted: its test
commands passed, but a collector path-resolution interruption required a
recount of the original events, and strict analysis then found a missing-braces
lint in the protocol test. The final report preserves that failed receipt and
collector history. Incoming main supplied the braces correction; the final
whole-engine and selected editor fatal-info analyses pass.

### Horizontal merged research tables

Add Note and Add Annotation accept HTML `colspan` values from 1 to 32 and write
native `gridSpan`. Every row must cover the same number of logical columns,
up to 32, even when its authored cell count differs from another row. Rich text,
lists, pictures and active citations stay owned by their native cells and
paragraphs. Body, authored-footnote and authored-endnote targets retain one
undo/redo transaction and DOCX save/reopen behavior.

When supplied, `data-colwidth` contains exactly one entry per logical column
covered by the cell. Integer 0 means unspecified; integers 1–4,000 give CSS-pixel
widths. Explicit widths must agree by logical column across all rows. Remaining
unspecified columns use 120 points, and a cell's native width is the sum of the
grid widths it covers. Total table width remains at most 4,000 points. The
existing limits of 64 tables, 256 rows per table and 4,096 authored cells per
note remain, alongside shared paragraph, link and image budgets.

Vertical merges (`rowspan` greater than 1), nested tables, header/footer row
groups and other unsupported structures remain refused. A table payload still
requires a main-flow destination outside an existing table; surrounding prose,
authored-note markers and the final main-flow caret retain their ownership.
Malformed content refuses the complete staged result.

### Native Refresh citation merging

The HTTP client advertises boolean `supportsCitationMerging`. An enumerated
field's `adjacent` value describes **this field's relationship to the next
enumerated field**, and is true only when their actual native citation packets
directly touch in the same paragraph, story and note. Zotero owns item ordering,
deduplication and final CSL formatting.

Whitespace or zero-width text, bookmarks, comments, controls, ordinary native
fields, bibliographies and paragraph/cell/note boundaries break the chain.
Staged insertion, deletion, unlinking or conversion cannot manufacture a new
merge across intervening content. Equal visible offsets alone are insufficient.
Physical adjacency is checked again before applying the result. A completed
refresh, including its citation and bibliography changes, is one undo/redo
step; an aborted or stale result remains detached.

## Local acceptance and source attribution

The genuine Flutter 3.47.8 / Dart 3.13.7 runtime uses the workspace's locked
dependencies. Aggregate entrypoints invoke the original suites with their
original groups, hooks and assertions; they bound compilation costs without
replacing the underlying tests. The engine aggregate covers 17 suites and the
editor aggregate covers 14 suites, including native tables and citations,
controllers, layout, proofing and return-to-writing behavior.

| Source and acceptance population | Result |
| --- | --- |
| Reconciled baseline `835b8019`: original incoming Word/Mail suites | 724 passed; historical receipt retained |
| Qualified feature source `6a00886f`: engine aggregate | 495 passed |
| Qualified feature source `6a00886f`: editor aggregate | 378 passed; 8 skipped |
| Current-main checkpoint `180399f9`: incoming Word/Mail, 11 suites | 928 passed |
| Current-main checkpoint `180399f9`: engine aggregate | 495 passed; 0 skipped |
| Current-main checkpoint `180399f9`: editor aggregate | 378 passed; 8 skipped |
| **Three final processes at `180399f9` only** | **1,801 passed; 8 skipped; 0 failed/errors** |

All three final processes reported `done.success: true` and exit code 0.
Before/after hashes remained stable for all 769 captured engine inputs and 904
captured editor inputs. All 257 Zotero editor cases, including every new case,
executed and passed; none of the skips belongs to a Zotero suite.

The eight skips come from `word_incremental_layout_equivalence_test.dart` and
its existing `no paragraphs to edit` guard for these image-only fixtures in
`legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/`:
`floating-both.docx`, `floating-control.docx`, `floating-horizontal.docx`,
`floating-margin-quarter.docx`, `floating-negative-quarter.docx`,
`floating-outline-shadow.docx`, `floating-quarter.docx` and
`floating-vertical.docx`. Their skipped paths are not qualified by this run.
The same eight cases were skipped in the initial `6a00886f` editor run.

The earlier editor tally counted Flutter `testDone` events with
`result: success` even when `skipped: true`. The corrected accounting separates
those eight skip events from the 378 actual passes at both checkpoints. This
corrects the result classification; it does not represent additional execution.

A final formatting check identified four canonical incoming Word test/driver
files from main. Formatting changed only whitespace, wrapping and trailing
commas. Their **405 affected cases passed again** with unchanged names and
expectations; those cases are already included in the 928 incoming total.
The evidence records all four before/after hashes and the targeted rerun.
All 33 changed Dart files pass the final formatting check. The 14 changed
Zotero Dart targets and incoming layout, deserializer and font targets pass
scoped analysis. Zotero production and test inputs remain unchanged from
`180399f9`; the engine manifest's three later test-file differences are exactly
those recorded formatting changes.

The [machine receipt](qualification.json) indexes all 48 archive members by
size and SHA-256. To independently recount the final logs, extract
[local-validation.tar.gz](local-validation.tar.gz) and run
`python audit_results.py /path/to/local-validation` using the included
[audit script](audit_results.py). It classifies `skipped: true` before counting
successes and refuses failed, malformed or unfinished result streams.

The current-main Word/Mail population is recorded explicitly:

| Original suite | Passed |
| --- | ---: |
| Canonical Word measurements | 197 |
| Canonical Word measurement integration | 6 |
| Preserved positional measurements | 197 |
| Preserved positional measurement integration | 6 |
| Word unit conversions | 202 |
| Word unit-conversion integration | 6 |
| Word line spacing | 103 |
| Word line-spacing integration | 23 |
| Mail bulk flags | 31 |
| Preserved named measurements | 147 |
| Preserved named measurement integration | 10 |
| **Completed cases in this run** | **928** |

These are source-specific executions. The 724-case baseline and 928-case
current-main run overlap; the final engine/editor runs repeat earlier
acceptance. Earlier runs are not added to the 1,801 final passes. Loading/setup
entries and skipped cases are not product passes.

The [incoming validation receipt](incoming-validation.json) retains the complete
baseline source binding and raw incoming results. The
[continuation qualification receipt](qualification.json) and
[raw validation archive](local-validation.tar.gz) retain terminal results,
source hashes, analysis logs and failed attempts, including the explicit skip
classification.
Earlier [research-table evidence](../zotero-research-tables-20261120/README.md)
keeps its original source and acceptance attribution.

### Diagnostic failures and corrections

An initial incoming Word run completed 693 cases with 685 passes and eight
failures from one repeated fixture. Its nonnumeric-Variant case declared a
variable after an executable assignment, so the declaration-order guard ran
before the intended numeric check. Moving that declaration preserved every
original expected `vba_type_error` assertion. The corrected 724-case baseline
subsequently passed.

The first complete engine attempt retained 494 passes and one stale-fixture
failure: a table fixture still expected horizontal `colspan` to be rejected.
The fixture now tests unsupported vertical `rowspan`; the corrected engine
aggregate passed 495 cases. The original failing run remains part of the
record and is not counted as a successful complete gate.

Runner startup also exposed a missing `/tmp`; a writable workspace `TMPDIR`
resolved it before test execution. An optional Flutter metadata probe met an
automatic approval-review rejection. The normal supported `BOT=true`, `CI=true`,
`--suppress-analytics`, `--no-version-check` and `--no-pub` settings avoided that
optional metadata work while retaining the genuine Flutter test runner and
locked dependencies. No GitHub Actions, workflow, check, status or queue
endpoint was called or awaited.

## Reconciliation and checkpoints

The [intake account](intake.md) and [machine-readable intake](intake.json)
cover a fixed initial snapshot: 37 fork branches, 271 fork PR heads, four
upstream branches and four upstream PR heads, totaling 316 refs. Reconciliation
left 293 refs covered by ancestry and 23 refs covered by 14 independently
verified historical equivalents, with **zero uncovered captured refs**.
The four maximal incoming tips listed in the intake are preserved as actual
merge parents. The deliberately retired temporary workflow remains deleted.

| Remote checkpoint | Purpose |
| --- | --- |
| `835b8019cbb873c72424e63d4df292174edd3c3e` | Reconciled incoming baseline and passing incoming acceptance |
| `6e20c7bff9ce88821c316f126ce16367caa0847c` | Horizontal spans and native Refresh merging |
| `6a00886f2c7f2ceddf859fcc1ccb99fbfcbb989a` | Corrected fixture and qualified feature source |
| `180399f99a3898501ab1959e3b845150d7da59fd` | Current-main reconciliation and updated documentation |

Current main `e975cec13b289fe067ef406cd3044701ecc44744` is the second parent of
`180399f9`. Its table padding, header logos, table styles and deserializer work
are retained; Zotero implementation files are unchanged. The Word compiler is
byte-identical to that main tip. Canonical measurement fixtures follow main,
while both earlier originals remain available under named and positional
names. Main's large-scalar regression remains included, and the inherited
Dim-order fixture correction preserves its assertions.

The exact `integrate/recent-pptx` patch at
`ec70b9423febefcb9b104629d2ad48b0c96e9082` has all three changed blobs identical
to `e975cec1`. A bounded post-intake ref refresh also observed unfinished Mail
draft PR #273; the initial Mail core is included, but the ongoing UI/provider
continuation is not claimed. Later unit branch
`cb5909fefe6dd41db0f9c38207db83166072dcaf` lies outside the initial snapshot and
remains preserved remotely without being swept into this Zotero milestone.
The [publication snapshot](publication-intake.json) records all 320 observed
refs: 292 ancestors, the 23 original verified equivalents, one equivalent
rendering patch and four references to later continuations. These boundaries
do not assert coverage of every concurrent future push.

## Reproduce the focused acceptance

Use a genuine Flutter 3.47.8 / Dart 3.13.7 installation, the locked workspace
resolution and its real package cache. From the repository root, prepare a
writable temporary directory:

```sh
QUDS_REPO_ROOT="$(pwd)"
QUDS_QA_TMP="$QUDS_REPO_ROOT/.dart_tool/zotero-acceptance-tmp"
mkdir -p "$QUDS_QA_TMP"
export TMPDIR="$QUDS_QA_TMP"
export BOT=true CI=true
```

Run the engine aggregate through the locked `test` 1.31.1 source compiler:

```sh
cd "$QUDS_REPO_ROOT/packages/quds_office_engine"
dart --packages="$QUDS_REPO_ROOT/.dart_tool/package_config.json" \
  "$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart" \
  --compiler=source --concurrency=1 --reporter=json \
  tool/zotero/research_target_acceptance.dart
```

Run the editor aggregate through the normal Flutter CLI:

```sh
cd "$QUDS_REPO_ROOT/packages/quds_office_editor"
flutter --suppress-analytics --no-version-check test \
  --no-pub --concurrency=1 --reporter=json \
  tool/zotero/research_target_acceptance.dart
```

`PUB_CACHE` identifies the resolved genuine dependency cache. Preserve complete
stdout/stderr, terminal exit status and before/after source hashes when
reproducing; partial console output does not establish a passing gate.
The incoming receipt retains its original aggregate and invocation. The final
archive retains the current-main runner and full suite accounting.

## Acceptance boundary and next milestones

Current Zotero comparison targets are Word and LibreOffice, as named in its
[requirements](https://www.zotero.org/support/system_requirements). Zotero's
[troubleshooting guidance](https://www.zotero.org/support/word_processor_plugin_troubleshooting)
explicitly excludes Apache OpenOffice from supported applications. Historical
plugin compatibility needs its own application, Zotero and plugin versions.

The remaining milestones are to qualify release-host picker, merged-table
and Refresh behavior in installed Zotero,
Word and LibreOffice; then extend vertical merges,
nested tables, deliberate Notes-pane cell editing and broader structural
replacement ranges. Active ODT fields and Zotero's cross-word-processor
transfer/import/export handshake still require a dedicated implementation and
acceptance. This continuation does not remove those boundaries.

## Primary implementation references

- [Pinned Zotero integration and native Refresh merging](https://github.com/zotero/zotero/blob/98f6486db71115d4198d1f746f487aef45805a2b/chrome/content/zotero/xpcom/integration.js)
- [Pinned HTTP integration capability and field contract](https://github.com/zotero/zotero/blob/98f6486db71115d4198d1f746f487aef45805a2b/chrome/content/zotero/xpcom/httpIntegrationClient.js)
- [Pinned Zotero note-editor image and table schema](https://github.com/zotero/note-editor/blob/bdf61e0c275e483c3068ce4fcb86b44691b22afc/src/core/schema/nodes.js)
- [Pinned ProseMirror span and width schema](https://github.com/ProseMirror/prosemirror-tables/blob/a99f70855f2b3e2433bc77451fedd884305fda5b/src/schema.ts)
- [Pinned ProseMirror table column sizing](https://github.com/ProseMirror/prosemirror-tables/blob/a99f70855f2b3e2433bc77451fedd884305fda5b/src/tableview.ts)
- [Pinned ProseMirror column resizing](https://github.com/ProseMirror/prosemirror-tables/blob/a99f70855f2b3e2433bc77451fedd884305fda5b/src/columnresizing.ts)
- [Zotero HTTP citing protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [Zotero cross-word-processor transfer guidance](https://www.zotero.org/support/kb/moving_documents_between_word_processors)
