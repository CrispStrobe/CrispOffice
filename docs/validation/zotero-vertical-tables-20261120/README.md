# Zotero vertical research tables: qualification and reconciliation

The final qualified product source is
`6045998d885cbb045454a993aedfdfc0977714d6`, including incoming main
`329d03914808589d3e7650fa870df15a2408afe2`. The
[final receipt](qualification.json) records **3,644 distinct passes, eight
existing skips and zero failures or errors**. Qualification combines fresh
local executions with exact-input retention proofs; it does not claim that
every case was rerun at this final Git commit.

| Acceptance population | Passed | Skipped | Failed |
| --- | ---: | ---: | ---: |
| Engine, native layout and DOCX | 823 | 0 | 0 |
| Editor, controller and Studio | 598 | 8 | 0 |
| Incoming Word/VBA regressions | 974 | 0 | 0 |
| Mail core | 219 | 0 | 0 |
| Mail transport | 415 | 0 | 0 |
| Mail shared UI | 179 | 0 | 0 |
| Mail hosts | 436 | 0 | 0 |
| **Total** | **3,644** | **8** | **0** |

## Delivered behavior

Add Note and Add Annotation accept bounded vertical merges and combined row/
column spans. HTML `rowspan` maps to native restart/continuation cells; `colspan`
continues to map to native logical column spans. The logical occupancy grid
rejects overlaps, gaps, spans beyond actual rows and crossings between row
groups before any staged insertion reaches the live document. A fully covered
row may contain no authored cells. Empty `tbody` elements still end a direct-row
group and cannot hide an invalid crossing.

The native conversion retains rich text, lists, pictures and active citations
in body, authored-footnote and authored-endnote targets. It remaps citation and
list indexes by native paragraph identity after generated continuation cells
have been inserted. Width vectors reconcile by occupied logical column,
including Zotero's zero value for an unspecified width. Whole-fragment limits
include generated content: 4,096 native cells and 10,000 native paragraphs,
with existing limits of 256 rows per table and 32 logical columns.

The controller preserves one undo/redo transaction, directional replacement
within one paragraph, detached cancellation and stale-target refusal, and
repeated DOCX save/reopen. No failed fragment is partially inserted.

### Native page, selection and DOCX behavior

Merged-cell decoration and source ownership continue onto every occupied
physical page, including note-story slices and tall-row pagination. Visible
fragments resolve clicks and context actions to the originating cell. Separate
physical row geometry retains row-selection bands and correct insertion
indexes, including a continuation page whose first physical row is not row zero.
Hidden continuation frames cannot claim editable paragraph ownership.

Logical and paragraph navigation skip only validated, structurally empty
continuation placeholders. Original model indexes remain stable. Authored
content, zero-width metadata, ordinary empty cells, multiple-block cells and
malformed native merge structures remain reachable. Existing visual/vertical
navigation behavior is preserved.

Explicit top/bottom borders no longer reappear at interior tall-cell page cuts.
DOCX export now preserves the model's per-cell on/off/inherit border flags.
Enabled edges use the table's represented color and width; arbitrary native
per-cell border styles are outside this boolean cell model.

## Word/Zotero acceptance

The complete nonoverlapping acceptance population was executed at published
commit `520d0ca8870c6a169e23603660f2cde96366f9b2`, tree
`464e3e7eb3b4186ebaa1f7a7ff530f41c506b445`.

| Cohort | Original test files | Passed | Skipped | Failed |
| --- | ---: | ---: | ---: | ---: |
| Engine, native layout and DOCX | 39 | 823 | 0 | 0 |
| Editor, controller and Studio | 22 | 598 | 8 | 0 |
| Incoming Word/VBA regressions | 11 | 974 | 0 | 0 |
| **Total** | **72** | **2,395** | **8** | **0** |

All three processes exited zero, produced a single successful terminal event,
completed every started test, reported no error events and had empty stderr.
All **317 Zotero editor command cases passed**. The dedicated additions include
60 vertical-table controller/dialog cases and 31 pointer/navigation/row-handle
cases. The eight skips are existing image-only incremental-layout fixtures
whose guard reports `no paragraphs to edit`; the receipts list every name and
reason. None is a Zotero skip.

All 5,254 source/configuration/fixture inputs remained unchanged during every
run. The independently captured source-manifest SHA-256 is
`187ae0d3d82784498f2be5faa305a2110a652bb7395376360a4ddb3806fe640c`.
The final expanded **75-file** changed-Dart scope passed no-write formatting
and strict analysis with fatal warnings and infos at published source
`6045998d885cbb045454a993aedfdfc0977714d6`. All scoped hashes stayed stable;
see [final Dart verification](dart-validation.json).

The final main followups change Mail implementation and Mail regressions.
Word/Zotero implementation, tests and dependencies are retained by exact source
comparison. The two Studio example suites that compile Mail through the shared
Studio shell were rerun at `fe2c5760`; those 16 cases replace their original
results inside the 598 above and are not added again. The final two-method Mail
chrome update at `6045998d` is separately qualified below.

### Reproduction and independent counting

The genuine runtime is Flutter 3.47.8, revision
`737ba8f885dc774b53b442759999a312c9461e4e`, and Dart 3.13.7. Dependencies use the
workspace lockfile, SHA-256
`0d64a732cd7f6c7cc4e1e01255276f081b59e6f43039636c3d36f6785a958ce2`.

Set `FLUTTER_ROOT`, `PUB_CACHE` and writable temporary/runtime directories, then
run each cohort with [run_acceptance.py](run_acceptance.py):

```sh
python3 docs/validation/zotero-vertical-tables-20261120/run_acceptance.py engine --output-dir /path/to/acceptance
python3 docs/validation/zotero-vertical-tables-20261120/run_acceptance.py editor --output-dir /path/to/acceptance
python3 docs/validation/zotero-vertical-tables-20261120/run_acceptance.py incoming --output-dir /path/to/acceptance
```

[local-validation.tar.gz](local-validation.tar.gz) contains full raw events,
stderr, commands, exit codes, before/after manifests and diagnostic history.
Its [index](local-validation-index.json) records member hashes. After extraction,
[audit_results.py](audit_results.py) independently recounts the acceptance
subdirectory. It excludes loaders/hooks/hidden cases, counts skips separately,
checks source and log hashes, and requires common source, successful processes,
complete event streams and successful terminal events.

The [suite inventory](acceptance-suite-review.json) verifies unique original
test files and calls, with no overlap between the three cohorts. The editor
runner uses 19 aggregate files plus three original files in separate Flutter
isolates; registering Studio fonts in one isolate changes a baseline font
negative-control premise. A minimal reproduction proved that interference.
The original assertions were retained and the complete corrected population
was rerun. The failed 597-pass/8-skip/1-error batch is diagnostic evidence only.

The archive also retains the actual parser row-group, navigation and border
regressions discovered during development. Focused passing reruns are not added
to the final population. [Harness binding](harness-binding.json) proves that
the preceding harness correction changed no product or original test file.

## Reconciliation and preservation

The [initial inventory](intake-initial.json) captured 322 references: 38 fork
branches, 276 fork PR heads, four upstream branches and four upstream PR heads.
Starting main was `698209aaa6e7f1350b6541df5eb192b7b233443d` (PR #276).

The later [publication snapshot](publication-intake.json) captured 324
references, adding only this branch and PR #277. Its external continuations
include Word `80e240ec`, Mail actions `1584a2da`, Mail flags `44f3f61f`, and the
then-current main `0a2afc41`. All were integrated. The subsequent main-only
freshness check found PR #275 and `5e7e4d24`; that reader/session work is also
included, with focused corrections and qualification rather than replacement
of our stronger accepted Mail union. A subsequent two-file main update,
`329d0391`, adjusts the Home tab and New-account control. Its widget methods
and account fixture are also preserved, with a focused 95-case replacement gate.

| Captured snapshot | Ancestors | Verified equivalent refs | Uncovered |
| --- | ---: | ---: | ---: |
| Initial | 298 | 24 | 0 |
| Publication | 300 | 24 | 0 |

The [replay script](audit_intake.py) independently verifies 15 replacement
proofs: 13 complete Git trees and two exact changed-path sets. It also requires
each replacement to be an ancestor. See [initial coverage](intake-reconciled.json),
[publication coverage](publication-reconciled.json) and
[proof definitions](historical-equivalents.json). Equivalence is not inferred
from an old narrative claim.

Incoming histories retain both bulk-Mail API contracts and regression sets,
the later Word conversion evidence, bookmark performance documentation, and
ancestry for an already retired temporary workflow without restoring that
workflow. The original positional Word BAS example, both regression files and
portable smoke driver are byte-identical to starting main. Source-specific
historical qualification files remain available, including the original
PR #276 receipt and separately named incoming Word records.

### Latest-main Mail continuation

The final freshness merge preserves the incoming Mail ribbon, warm-session
behavior and explicit remote-image action. Its focused corrections retain
inline word separation, keep image batches and reader selection/search state
consistent, enforce existing cumulative reader budgets, bound HTTP image bytes
and time, and prevent stale readers or saved-settings callbacks from applying.
The existing bulk-action identity, cancellation, API-alias and scope guards are
retained. See the [incoming-main review](latest-main-review.json),
[union decisions](late-mail-union-resolution.json), and the source-specific
Mail qualification records in this directory.

The earlier complete Mail union qualified 1,173 distinct cases at `e8edb90a`
(with exact-source reuse for transport/shared UI). That population is preserved
in [mail-final-evidence.tar.gz](mail-final-evidence.tar.gz). It does not claim to
qualify the later reader/session source. The final continuation requalifies the
affected Mail UI and native host paths and explicitly attributes any unchanged
cohorts; old core/host runs and overlapping reruns are never added twice.

The accepted continuation has **1,249 Mail passes**: 219 core, 415 transport,
179 shared-UI and 436 host cases. Core and transport retain their original
execution receipts with exact-input applicability proofs. The shared-UI run
is bound to its actual captured source, including its dependencies; all 436
host cases ran at `fe2c5760`. See the
[continuation qualification](post-main-qualification.json),
[source applicability](source-applicability-summary.json), and
[post-main-evidence.tar.gz](post-main-evidence.tar.gz).

After incorporating main `329d0391`, the final **95-case** gate passed at
`6045998d`: 22 account, 60 native-workspace and 13 visual cases. These replace
the same cases inside the 436-host population. Both affected widget methods
and the account fixture match incoming main exactly; all other native bytes
and 5,520 protected inputs remain unchanged. The
[final source bridge](freshness-tail-source-binding.json),
[qualification](freshness-tail-qualification.json), and
[independent recount](freshness-tail-independent-recount.json) record this
boundary. The successful process exited zero, completed all started cases and
kept all 2,659 run inputs and runtime fingerprints stable.

[freshness-tail-evidence.tar.gz](freshness-tail-evidence.tar.gz) contains the
raw final events, full source bridge, final 75-file static gate and the
5,257-input [publication source seal](publication-source-seal.json). Its
[index](freshness-tail-evidence-index.json) and
[integrity receipt](freshness-tail-evidence-integrity.json) verify all 31
members. An earlier interrupted run has no terminal receipt and an unknown
process exit; it is preserved only as a diagnostic. The isolated diagnostic
and successful complete rerun required no source changes and do not inflate
the accepted population. The [final receipt](qualification.json) records the
hashes of all four evidence archives.

## Publication and remaining parity work

Publication uses [PR #277](https://github.com/CrispStrobe/quds_office_suite/pull/277)
and branch `codex/zotero-vertical-tables-20261120`. The
[checkpoint ledger](checkpoints.json) records incremental remote saves. Every
published tree is compared with its local Git tree, and ref updates use an
expected head. GitHub Actions, workflow runs, check runs and status endpoints
were neither queried nor awaited.

The row-height policy remains conservative: the origin's content contributes
to its first physical row. Compact Word-style distribution across merged rows
remains a fidelity milestone. Nested research tables, additional row groups and
custom styles, direct table-cell editing in the Notes pane, replacement beyond
one paragraph, active ODT citation transfer and cross-processor import/export
remain explicit work. Installed Zotero/Word/LibreOffice/OpenOffice and platform
release interoperability are not inferred from local protocol/model/controller/
layout tests. The [parity roadmap](../../roadmaps/zotero/word-processor-parity.md)
keeps those acceptance boundaries visible.

## Protocol and format references

- Zotero's [HTTP Citing Protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
  defines rich HTML insertion and later conversion of citation placeholder links.
- The pinned [Zotero note-editor schema](https://github.com/zotero/note-editor/blob/bdf61e0c275e483c3068ce4fcb86b44691b22afc/src/core/schema/nodes.js)
  uses ProseMirror table nodes with block content in cells.
- The pinned [ProseMirror table schema](https://github.com/ProseMirror/prosemirror-tables/blob/a99f70855f2b3e2433bc77451fedd884305fda5b/src/schema.ts)
  models row/column spans and column widths independently and permits rows with
  no authored cells when preceding cells occupy their grid positions.
