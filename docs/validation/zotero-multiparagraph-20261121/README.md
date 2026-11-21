# Zotero research replacement across paragraphs

**Qualified product checkpoint:** `a4ec5b812cc64c5f738357fdef8779df9b8a8a2b`,
tree `ce69540b51ff3f59e761ed25de0124540b3cd4bf`.

Add Note and Add Annotation now replace consecutive ordinary paragraphs in one
body section or authored footnote/endnote. This completes the ordinary-paragraph
range milestone in the [parity roadmap](../../roadmaps/zotero/word-processor-parity.md).
The implementation, incoming ancestry, fixes, tests and documentation were saved
incrementally on remote branch `codex/zotero-multiparagraph-20261121`.

The [machine-readable qualification](qualification.json),
[remote checkpoints](remote-checkpoints.json) and hashed evidence below separate
current acceptance from retained historical runs. Subsequent publication changes
only documentation and evidence. No GitHub Actions, workflow, check or status
endpoints were queried or awaited; no workflow or dependency policy changed.

## Delivered behavior

- Replace selected ordinary text and paragraph breaks while retaining the rich
  unselected prefix/suffix, hyperlinks and active citation packets.
- Preserve the ending paragraph's formatting when its suffix remains in a
  separate paragraph. A single plain inserted paragraph joins both fragments
  under the starting paragraph's formatting.
- Insert native paragraphs, headings, lists, images and tables with live citation
  ownership through the established detached transaction. Existing payload
  structure and resource bounds remain in force.
- Map both visible Notes-pane endpoints to native paragraph/offset pairs and
  preserve automatic note markers and separators, including raw offset zero
  and an unselected suffix that begins with whitespace.
- Preserve one atomic undo/redo step and the original selection direction on
  undo. Cancellation, moved endpoints, active composition, intervening edits
  and stale document revisions prevent publication of the staged result.
- Retain simple and complex citation packets at untouched endpoints, including
  refreshes that change citation lengths. Quds DOCX save/reopen preserves active
  fields and permits another qualified replacement.

Ranges are limited to **10,000 consecutive ordinary main-flow paragraphs** in
one section or authored note. They cannot cross tables, frames, controls or
section boundaries, or consume protected fields, note references, images,
comments and bookmark boundaries. Paragraph-owned bookmarks, unrepresented
native field flags, zero-width citation packets on consumed boundaries and
shared paragraph objects are guarded. Ordinary citation editing retains its
established single-paragraph behavior. See the [usage guide](../../zotero-support.md)
for the native `insertionEndParagraph` API and content limits.

Independent review identified and verified fixes for paragraph metadata, shared
paragraph ownership, authored-note separator whitespace and native endpoint
packets. Its source-bound findings remain in [review.json](review.json).

## Incoming work and ancestry

The [initial intake](intake/README.md) captured **329 fork/upstream branch and
PR heads**. It proved 304 ancestors and 24 exact historical equivalents, then
integrated the remaining continuation `bbccae1b`. Checkpoint `e5b92405` retains
both original main and that continuation as parents. Thirty incoming evidence
files retain their exact bytes. The initial Mail presentation alias passed
60 affected local cases; that historical run is retained separately.

The [publication snapshot](publication-intake/README.md), captured
**21 November 2026 at 05:36 CET (04:36 UTC)**, contains **330 refs**. Its final
[audit](publication-intake/final-audit.json) accounts for **306 ancestors and
24 verified historical equivalents, with zero uncovered refs**. Fork and
upstream open-PR listings were empty at capture. The two new external heads
were integrated through normal ancestry merges:

| Captured work | Included head | Integration |
| --- | --- | --- |
| Word VBA section PageSetup | `c093f6387fcae69f04c63f4344476e4785906a54` | `420baa07` |
| Mail fresh flag observation and durable reconciliation | `1df5e678906ff1def11deed085586dc733030595` | `6c180d7e` |

Word adds guarded section-specific page geometry writes and sparse native XML
preservation. Mail adds optional fresh read-only provider observations and
explicit SQLite v7 reconciliation of uncertain commands. It does not replay
uncertain commands automatically. Changelogs were combined, the current
presentation alias retained, and the incoming original-problem identity
assertion preserved. Historical evidence that a merge would otherwise delete
was restored byte-for-byte.

Remote main subsequently advanced through **PR #281** to
`3d01815908aeded5862d131109341365de637242`. Checkpoint `a4ec5b81` merges that exact
main as its second parent. The parallel namespace fix was independently reviewed
and reconciled with the qualified shared helper; eleven incoming Word evidence
files retain their exact bytes. Relative to `537d2e7c`, this main reconciliation
changes only twelve documentation/evidence paths. The frozen 330-ref snapshot
is a stated cutoff, not a claim about later unsnapshotted branch updates.

## Current local qualification

| Gate | Executed cases | Result and source |
| --- | ---: | --- |
| Engine, all 36 original Zotero suites, Dart VM | **977** | All pass at `c5cf1ec1`; exact relevant input retention to final product |
| Engine, targeted JavaScript/Node: multiparagraph, document data and child API | **148** | All pass at `c5cf1ec1`; three original suites |
| Editor, twelve selected suites (Zotero plus marker regression) | **400** | All pass at `c5cf1ec1` |
| Studio citing transport | **18** | All pass in a separate process at `c5cf1ec1` |
| Studio shortcuts | **15** | All pass in a separate process at `c5cf1ec1` |
| Incoming Word PageSetup, section clone and roundtrips | **156** | All pass; qualified tree equals published `537d2e7c` |
| Incoming Mail, fourteen original files | **332** | All pass at `6c180d7e`; all 502 scoped inputs identical at final product |

The 148 Node cases overlap native engine cases and are **not added** to a
combined unique-case total. All listed accepted test processes exited zero,
completed their started cases, and had zero failed, skipped or error events.
The Word BAS smoke runs on VM and compiled JavaScript produced identical output;
they are additional smoke evidence, not another unit-case count. Nine changed
Zotero Dart files and three changed Word files passed fatal-infos analysis and
no-write formatting with explicit Dart language version 3.12.

Mail acceptance includes **83 actual native SQLite cases**: 42 reconciliation,
15 migration and 26 journal cases. SQLite 3.54.1 and FTS5 readiness were verified
using the pinned official native artifact. Provider cases use controlled
synthetic responses. The six JavaScript-only unsupported-provider cases ran on
Node; VM platform exclusions are not counted as coverage.

Runtime: official **Flutter 3.47.8**, revision
`737ba8f885dc774b53b442759999a312c9461e4e`, **Dart 3.13.7**, Node 24.22.3, Linux x64.
The SDK archive and official dependency archives were hash-verified. An isolated
validation workspace used unchanged manifests and the pinned lockfile. Exact
commands, runtime hashes, complete case inventories, subprocess exits and
before/after source manifests are retained in the evidence archives.

### Source applicability

The combined Zotero runs bind to `c5cf1ec1`. At final product `a4ec5b81`, every
executed Zotero test, implementation, configuration, dependency and asset input
is unchanged. The sole differing recorded non-document input is the unrelated
`office_macro_word_page_setup_test.dart`: five formatter-only call reflows and
optional trailing commas. That formatted Word test was separately qualified at
`537d2e7c`; its entire non-document tree is unchanged by the refreshed-main
merge. Mail's 494 repository inputs and eight runtime inputs match its accepted
snapshot exactly. The source-applicability reports state their scopes explicitly.

### Findings corrected during qualification

1. Two image-flow expectations still asserted the old blanket single-paragraph
   restriction. They now check cross-section, table and native-field refusals
   for both research commands. A third assertion now checks the updated tooltip.
   The corrected full editor
   run passes all 400 cases; earlier failures remain in the archive.
2. The initial full Node run completed 965 cases: **964 passed and one failed**.
   A malformed API fixture used `12.0`, which JavaScript serializes as integer
   `12`. The fixture now uses `12.5`; both runtimes reject it without any parser
   change. The complete child-API suite passes in both accepted current runs.
   This targeted rerun is not represented as a new complete 36-suite Node run.
3. Incoming Word repeated edits duplicated namespace declarations because the
   XML reader and writer represented declaration namespaces differently. The
   shared helper matches the declaration's qualified name without overwriting
   ordinary attributes such as `w:w`. The existing 50-repeat test and a new
   collision/three-save regression pass. The original failure is retained.

The initial broad Node run excluded exactly twelve filesystem-dependent cases:
eight XML-fixture, three citeproc-fixture and one protocol-fixture case. All
executed successfully on VM. Their exact names and reasons are retained. The
23 platform-dependent hashCode-derived test labels are mapped explicitly in a
separate population comparison; raw names and the numeric-fixture failure are
not hidden. The first VM reporting-parser attempt is retained as diagnostic
only, because it lacked a complete process-exit receipt.

## Evidence and reproduction

The `evidence` directory contains four current-gate archives and one initial-intake/review archive, member hash indexes
and source-applicability reports. `qualification.json` records archive hashes
and authoritative summaries; `SHA256SUMS` verifies the retained files. Archives
contain the exact commands and runners, raw events, completed named cases,
source/runtime manifests and clearly separated prior failures. SDK binaries and
exported source workspaces are not duplicated in the repository.

For a normal development checkout with the declared dependencies resolved, use
Dart VM test execution for all `packages/quds_office_engine/test/*zotero*.dart`
suites, Flutter test execution for the twelve selected editor suites (Zotero plus marker regression) and the two
separate Studio suites, and Node for the three targeted engine suites. The
receipts supply exact file lists, platform filters and working directories.
The native SQLite probe and Mail commands are in the Mail archive. Source-ref
coverage can be replayed without contacting hosted CI:

```sh
python3 docs/validation/zotero-multiparagraph-20261121/publication-intake/audit_intake.py \
  --head a4ec5b812cc64c5f738357fdef8779df9b8a8a2b \
  --output /tmp/zotero-intake-replay.json
```

## Remaining parity work

Local protocol, model, serializer and controller tests do not establish live
Zotero or installed Word/LibreOffice/OpenOffice interoperability. The next
priority is **active document transfer**: actual Zotero export/import handshakes,
ODT active fields and cross-application fixtures containing citations,
bibliographies, authored notes, tables and images. Subsequent work covers
remaining table layout/structure, additional image formats, structural selection
ownership and release-host acceptance. These are tracked in the
[ordered roadmap](../../roadmaps/zotero/word-processor-parity.md#next-implementation-and-acceptance-steps).

LibreOffice is the current supported comparison application in Zotero's
[requirements](https://www.zotero.org/support/system_requirements) and
[troubleshooting guidance](https://www.zotero.org/support/word_processor_plugin_troubleshooting).
Historical Apache OpenOffice compatibility requires identified application,
Zotero and plugin versions and separate acceptance. Complete plugin parity is
not claimed by this increment.
