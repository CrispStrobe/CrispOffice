# Zotero nested research tables — 21 November 2026

## Result and scope

Add Note and Add Annotation now preserve tables nested inside research-note
cells, including active citations, rich paragraphs, lists, pictures, independent
column widths and horizontal/vertical merges. The implementation accepts up to
eight table levels and preserves the note's recursive reading order through
native editing, Refresh, undo/redo and repeated DOCX saving and reopening.

Qualified source: **`ed30a633a96960552d4fab11bd6e3226ee73ca14`**.
The final source-bound local checks record
**2,267 distinct passing cases, eight existing fixture skips, and zero
failures or runtime errors in the accepted application runs**. The separately
reported converter route failure remains a failure; it is not included in this
passing count. [PR #296](https://github.com/CrispStrobe/quds_office_suite/pull/296)
publishes the work on `codex/zotero-parity-20261121-continuation`.

This is a bounded implementation milestone toward Zotero Word/LibreOffice
parity. It does not establish full plugin parity, native ODT editing or
installed-application interoperability. LibreOffice is the current supported
OpenOffice-family comparison; legacy Apache OpenOffice needs separately
identified application, Zotero and plugin versions.

## Reconciled source and incremental publication

The initial main was `4090feb56f308cd3657c5edd1d045ff1197ff79b`. The first intake
captured 347 references: 49 fork branches, 294 PR heads and four upstream heads.
PR #294 landed during that intake and was preserved. The final frozen intake
contains **352 references: 52 fork branches, 296 PR heads and four upstream
heads**. All are accounted for: **328 ancestors, 24 verified historical
equivalents, zero uncovered references**.

The 24 equivalent references use 15 unique proofs: 13 complete-tree equalities
and two changed-path equalities, with every replacement retained as an
ancestor. Old branches were not replayed over newer implementations. The
initial record is [intake.json](intake.json); the final frozen record is
[intake-final.json](intake-final.json). The earlier uncovered snapshot is
retained in the evidence archives, with its original outcome intact.

After the cutoff, published main `f92c0d24f0513c5e13e61ae58507c36e9cf4f1c1` was
also incorporated. Its delta beyond the captured Word head adds 13 validation
files and one nested-table test, with no product-source change. That test is
included in the final engine execution. The supplemental main receipt records
the exact ancestry and changed-path proof in
[main-preservation.json](main-preservation.json).

Published Mail main `c10416d39894031164be68313253db5bbb3a5ad2` was subsequently
incorporated at `ed30a633`. It changes two Studio production files, five Mail
test files and 29 documentation/evidence files. The added mailbox-generation
fence and download cancellation at view changes are included. Zotero engine,
legacy parser and dependency inputs remain byte-identical. The final Mail
qualification is rerun over 11 files, replacing the prior nine-file result.

| Checkpoint | Work preserved |
| --- | --- |
| `f3eb60ad` | Localization/screenshot branch `e6a38e2b`, retaining its ancestry |
| `23903dfe` | Word layout/typing branch `5332c5ff`, retaining its ancestry |
| `7c8923fb` | Initial intake and bounded implementation plan |
| `2914fd3b` | Nested-note parser implementation |
| `6270ec92` | Parser, session, controller and raster regressions; support documentation |
| `dc87bf94` | Main `97cfb09b` and offline Mail head `63f54066` |
| `96a6b1b1` | Word proofing/layout head `75b429e3` and calendar-date correction |
| `b8cdcffe` | Reproducible nested-table transfer qualification tool |
| `a292438e` | Compact Mail reader correction and incoming fixture corrections |
| `c4e1d675` | Published main `f92c0d24`, including its additional nested-table test |
| `718d3bf8` | Raw earlier execution, runtime and converter evidence |
| `574bc02b` | Final incoming Mail fixture corrections and evidence verifier |
| `ed30a633` | Published Mail main `c10416d3`, with verified Quit fixture assertions retained |

Every published checkpoint verifies the exact complete Git tree and updates
the remote branch with an expected-head lease. Original merge parents are
retained. No force push or remote-history rewrite is used. A few local test
receipts name pre-publication commit objects; the audit preserves those names
and supplies exact-tree mappings to the saved remote checkpoints. GitHub
Actions and check statuses were neither queried nor awaited.

## Implementation contract

`WordZoteroNoteText` now tracks an explicit stack of native table/cell owners.
Opening a nested table saves its containing owner; closing it restores the
outer cell before parsing subsequent prose, another nested table or the next
sibling cell. Each table validates its own grid, widths and spans.

Cells accept nested tables at ordinary block boundaries, including ordinary
`div` wrappers. A cell ending in a nested table receives its required native
trailing paragraph **before** final citation/list indexes are mapped. The
flattened paragraph sequence therefore matches the actual native tree,
including generated merge-cell and trailing-cell paragraphs.

Limits are shared by the entire note: eight table levels including the
outermost table, 64 tables, 4,096 native cells including generated vertical
continuations, and 10,000 native paragraphs. Existing payload, link and image
budgets still apply. Nesting does not restart any resource counter.

Detached staging, cancellation, stale-target rejection and a single undo/redo
transaction remain in place for body and authored footnote/endnote targets.
A table-bearing payload still requires a main-flow destination outside an
existing table cell. Tables inside inline paragraphs, links or list items,
header/footer row groups, custom table styles and cross-cell replacement remain
outside this increment. The [support guide](../../zotero-support.md) gives the
complete supported HTML and resource contract.

The engine already had native nested-table modeling, layout and DOCX
serialization. The missing note-parser ownership model was therefore the
appropriate bounded implementation target. Native ODT input requires a
separate reader: the existing ODF path extracts text and exports ODT, but does
not deserialize an ODT document into the editable Word model.

## Final local qualification

The [qualification receipt](qualification.json) independently recounts raw
events, excludes hidden lifecycle events, separates skipped fixtures from
actual passes, checks exact file coverage and excludes replayed cohorts. Case
identities use the repository path, complete test name and verified registration
identity. Four VBA policy registrations have different policy parameters but the
same generated title; their source loop and raw registration IDs are retained.
The 2,267 executed cases therefore have 2,264 unique file/title pairs. Recorded
source hashes are compared with the final inputs; earlier overlapping
executions are not added to the total.

| Accepted scope | Files | Passed | Skipped |
| --- | ---: | ---: | ---: |
| Engine Zotero, nested layout and incoming Word proofing/layout regressions | 55 | 1,359 | 0 |
| Editor Zotero/controller/raster and typing/layout regressions | 16 | 510 | 8 |
| Studio Mail synchronization, durable body retention, native lifecycle, Quit, localization and calendar dates | 11 | 335 | 0 |
| Mail body-download bounds, ownership and cancellation | 1 | 63 | 0 |
| **Distinct accepted total** | **83** | **2,267** | **8** |

The eight skips are preexisting floating-image fixture cases with no editable
paragraph (`no paragraphs to edit`); they are not loading failures or passes.

The Mail core receipt ran before the later editor-only corrections. Its
relevant source and dependency inputs remain byte-identical; the audit records
that retention proof. The 1,359-case engine run and complete engine library
analysis ran at `574bc02b`; the later published Mail changes leave all of their
engine, legacy-parser and dependency inputs unchanged. The final Studio and
editor groups execute the combined `ed30a633` source. Unrelated changed Mail
paths remain explicitly listed in the retention proof.

Complete engine library analysis passes. All eight selected editor/Mail Dart
targets pass analysis with no issues, and all 13 selected feature/incoming Dart
files pass the standard formatter with zero changes. The exact analyzed and
formatted path lists and source comparisons are retained with their receipts.

The new parser/session/controller cases cover owner restoration, rich content,
row/column spans, limits at their exact boundaries, incomplete/cancelled/stale
operations, reversed placeholder-request order, authored notes, Refresh/unlink,
undo/redo, deep layout and pagination. A three-level controller fixture with
five ordered citations has **zero changed rendered pixels** across three
DOCX save/reopen cycles. All four retained PNGs share SHA-256
`2f97ab707e4700de6003ad86d8e630a4be622e19f224902a59e1470f9d78ca82`.
The [retained baseline rendering](nested-note.png) is the actual test output.

### Findings corrected during integration

The first late Studio run found seven errors. The compact reader's uncached or
error state used a non-scrollable column; long translated text overflowed at
small sizes. Its state block is now scrollable, while cached content continues
through the shared message reader. The sync-host fixture now constructs typed
bytes and disposes its old Navigator before reopening retained mail. The Quit
fixture first selected the actual tooltip; the final reconciliation accepts
the incoming typed `StudioAppSwitcher` finder with the same Mail label.
The two draft-lifetime assertions inside the asynchronous save callback now use
Flutter’s callback-safe `expectSync`. A retained diagnostic trace confirmed that
ordinary guarded `expect` raised a test-zone conflict, which the composer caught
as a save failure. The correction preserves the lifetime, approval, pending-save,
retry and ordering assertions without changing production Quit timing or guards.

The failed and diagnostic test runs described here remain in the archives.
Earlier storage exhaustion caused
loader failures; those attempts do not count as successful test execution.
An initial raster fixture used fractional A4 twip geometry and implicit link
styling; the fixture now uses exact 600 × 800-point geometry and explicit
hyperlink styling. No production rendering assertion or pixel tolerance was
weakened. The earlier 1,221 engine passes, composed 510 editor passes/eight
skips, initial 118 incoming cases, and pre-publication 318-case Studio gate
retain their original source attribution and are not added to the final reruns.

## Actual converter qualification

The retained tool,
`packages/quds_office_engine/tool/zotero/nested_table_acceptance.dart`, generates
synthetic note content through the real staged Add Note and transfer callbacks.
It creates three nested tables, a vertical merge, a horizontal merge, four
active citations, a numbered list starting at four, and a PNG displayed at
18 × 13.5 points. Citation formatting callbacks are controlled fixtures.

Actual file conversion used **LibreOfficeDev 26.8.0.0.alpha0**, commit
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.

| Route | Strict outcome |
| --- | --- |
| Quds DOCX carrier → controlled Quds import | Pass |
| Quds ODT carrier → LibreOffice DOCX → controlled Quds import | Pass, including three further Quds saves |
| Quds DOCX carrier → LibreOffice ODT → LibreOffice DOCX → controlled Quds import | **Fail:** list labels become `4., 1.` instead of `4., 5.` |
| Flat-list control with the same original numbering XML | Reproduces the same numbering loss |

The passing route preserves active citation order, source URIs, locators,
Unicode titles, unknown citation/preference metadata, table ownership and
spans, cell shading, visible list labels, and the PNG's pixels, cell ownership
and exact display dimensions. The direct ODT verifier was repeated against the
combined Word source; all 425 recorded engine/parser/tool/configuration inputs
remain identical in the final source.

The failed route's intermediate ODT still has one list starting at four with a
continued second item. The returned DOCX changes the second paragraph to an
independent numbering instance starting at one. A flat control reproduces the
same change without nested tables. Direct Quds ODT carries explicit item starts
four and five and preserves those visible labels through conversion.

The tool's `diagnose` mode completes the other ownership, citation, metadata,
image and save/reopen checks while retaining a failed result and exit code 1.
It does not turn the route into a pass. No Quds reader heuristic merges
independent numbering instances to conceal the converter behavior. The
observation is bound to this route and build; passing visible labels in one
fixture does not establish full target-application list editing equivalence.

These are actual headless file conversions followed by controlled formatting
callbacks. No live Zotero CSL session, Microsoft Word execution, or installed
Word/LibreOffice/Apache OpenOffice plugin acceptance is claimed.

## Evidence and reproduction

[evidence-index.json](evidence-index.json) records archive and member byte
counts and SHA-256 values. Every archive is reopened and every member digest
is checked after creation. Run the retained verifier without extracting or
executing archive members:

```sh
python3 docs/validation/zotero-nested-tables-20261121/verify_evidence.py
```

| Archive | Contents |
| --- | --- |
| [final-qualification.tar.gz](final-qualification.tar.gz) | Final raw events, exact test lists/commands, before/after source manifests, analysis/format output, independent audit, final intake and supplemental main receipts |
| [historical-qualification.tar.gz](historical-qualification.tar.gz) | Earlier source-bound runs, initial incoming checks, raster diagnostics and original failed attempts |
| [converter-qualification.tar.gz](converter-qualification.tar.gz) | Synthetic DOCX/ODT files, converter logs, strict verification, numbering evidence and flat control; isolated LibreOffice profile omitted |
| [runtime-provenance.tar.gz](runtime-provenance.tar.gz) | Runtime/dependency integrity and resolution receipts, reproduction environment and documented storage cleanup |

Extract archives into separate directories when comparing historical and final
snapshots; some evolving receipt paths occur in both. Exact commands are
retained with each run. Relocate the recorded workspace prefix when reproducing
on another checkout.

The local runtime is pinned to **Flutter 3.47.8 / Dart 3.13.7**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`. The official archive and all 202 locked
package archives were SHA-256 verified. Offline dependency resolution enforced
the committed lockfile and left manifests/lockfiles unchanged. Recorded disk
cleanup removed optional SDK artifacts and package test/example/documentation
directories; all 8,731 retained package runtime/configuration/license files
remained byte-identical. No SDK binary or dependency cache is committed here.

From `packages/quds_office_engine`, the retained converter tool accepts:

```sh
dart tool/zotero/nested_table_acceptance.dart generate /absolute/output/directory
dart tool/zotero/nested_table_acceptance.dart verify /absolute/path/carrier.docx
dart tool/zotero/nested_table_acceptance.dart diagnose /absolute/path/carrier.docx
```

The archived converter commands include explicit file filters, output paths
and an isolated LibreOffice profile. The archived test commands use the pinned
Dart test runner or Flutter tools snapshot directly, avoiding an observed
bootstrap stall. Concurrency is bounded and runtime-dependent groups execute
serially on the storage-constrained host.

## Next parity work

The [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) retains the
next implementation and acceptance steps: native ODT reference-mark/preference
input and installed-plugin transfer acceptance; header/footer table groups and
custom styles; compact merged-row height distribution and Notes-pane cell
editing; additional image fidelity; broader structural replacements; and
release-host qualification. Legacy Apache OpenOffice remains a separately
versioned compatibility target.
