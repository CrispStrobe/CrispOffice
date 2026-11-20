# VBA string conformance and Office reconciliation — 20 November 2026

This record covers the next bounded `vba-excel` milestone: `Len`, `Left$`,
`Right$`, and `Mid$`, version 1 conformance fixtures, and the shared
source-to-native-plan/CLI/MCP transaction boundaries. It also records the
reconciliation of incoming presentation work and concurrent remote main.
It is local qualification, with no GitHub Actions queries or waiting.

## Behavior and scope

The four case-insensitive intrinsics accept actual String values and exact
integer numeric arguments. Counts are nonnegative signed-Long values; `Mid$`
uses positive one-based starts and an optional count. Results clamp to available
UTF-16 code units, and arguments are evaluated exactly once in source order.
Substring output units consume the shared work budget before allocation.

The versioned corpus compares complete ordered native operations or exact
diagnostic code/line/column outcomes. The portable runner embeds the same JSON
bytes on the VM and JavaScript, including provenance and native-plan round-trip
checks. Specification-derived expectations, deliberate dialect restrictions,
and actual Office-host observations have separate provenance kinds. The
delivered corpus has no Office-host observations.

A publication probe exposed a concrete Unicode boundary: an isolated surrogate
survived native JSON encoding but became U+FFFD when serialized into XLSX.
The compiler now rejects malformed UTF-16 in every emitted String argument,
including values, formulas, and worksheet selectors. Internal halves remain
valid source values and can be measured or recombined. This prevents returning
a plan that would silently replace that text during workbook publication.
The regression includes native/MCP/CLI output preservation and lossless valid
pair publication. `ClearContents` keeps its existing statement-start diagnostic
location; property writes use their member token.

The committed `string_report.bas` parses three synthetic records through
dynamic arrays and reusable helpers. It emits 28 operations, produces matching
source and worksheet totals of 14, and preserves the supplementary emoji in
the saved workbook. Compilation does not read existing worksheet values.

See [the dialect contract](../../VBA_MACROS.md#string-intrinsics),
[the conformance format](../../VBA_CONFORMANCE.md), and
[the remaining roadmap](../../VBA_PARITY_ROADMAP.md). Numeric `Len`, implicit
coercion, fractional rounding, unsuffixed substring intrinsics, `Empty`/`Null`,
document-aware source evaluation, and Word/PowerPoint VBA object models are
not added by this increment.

## Initial remote reconciliation

The [initial audit](initial-remote-audit.json) captured 12 fork branch heads,
the latest 100 updated PR heads, and all four upstream branch heads. Initial
remote main was `a452efdadc9000c51a8e5e9ba2f16405d4979e2e`; it already contained
the prior VBA milestone `3003272`, PR #220's macOS spaCy qualification, and
the native DOCX revision-formatting work.

| Inventory | Classification at initial audit |
| --- | --- |
| Fork branches | Main, one ancestor, nine exact historical equivalents, one incoming PPTX head |
| Latest 100 PR heads | 98 true ancestors, two exact historical equivalents, no open PRs |
| Upstream branch heads | Four true ancestors |
| Unique incoming source | Four commits on `integrate/recent-pptx`, ending at `f007b245` |

Historical equivalence was freshly verified using the complete changed-path
Git mode/type/blob identity against a previously accepted equivalent commit,
whose ancestry was also checked. The PR exceptions were #152 (`da9c956e` to
accepted `23f3b420`) and #147 (`cee6e263` to accepted `bb5556e8`). The recorded
[audit script](audit_remote.py) is the exact local classification procedure.
No unique initial work was discarded.

The four incoming PPTX commits preserve master/layout decorations, expand font
fallbacks, add block-arrow presets and heading fitting, and improve numeric
text ordering. Their real ancestry was retained in a merge checkpoint, with
conflicts reconciled against main's existing rich-text, inherited-font,
background ownership, secondary-master, and display-color fixes.

Review and regression tests addressed arrow outlines, double font scaling,
numeric multiline/wrapping behavior, decoration/foreground animation ID
collisions, decoration rotation, dark-mode backing inference, and authored
master-shape suppression. The complete original `office_dark_slide_test.dart`
remains byte-identical to initial main; its existing assertions were retained.
An independent review then found a narrower spaced-number multiline ordering
case, which was reproduced separately before correction.

## Incremental remote preservation

Every checkpoint uses immutable Git blobs and trees whose returned SHA is
compared with the local Git object identity before creating a commit. Branch
updates are non-forced and use the expected previous remote head. All source
and documentation commits carry `[skip ci]` because GitHub Actions are not the
qualification gate for this work. Direct Git push was unavailable in this
workspace; the connected GitHub API provides authenticated writes, followed
by fetching and verifying the exact remote checkpoint locally.

The main advance `33370cbfc290389cc663913a9efcfa5f71e112b0` contributed four DOCX
validation/evidence documents and was merged without changing implementation
bytes. The PPTX branch then advanced by two commits, `ea75285d` and `9e647ae5`,
adding Noto Emoji fallback and flipped connectors. These were brought in with
real ancestry, followed by targeted preservation fixes so connector direction
survives serialization, geometry edits, cloning, and morph transformations.

The [concurrent branch review](concurrent-branch-review.json) distinguishes work
that arrived after the initial cutoff. The new Zotero research-materials branch
explicitly recorded implementation and final acceptance in progress, and the
mail-attachments branch contained plumbing without its planned compose caller.
Neither had an open PR at this refresh. Their independent remote checkpoints
were preserved; their partial application workflows were not published as part
of the VBA milestone. Their overlapping alternate PPTX changes were compared
and are not wholesale replacements for the reconciled local fixes. Current
main and PR readiness are checked again before publication.

Further refreshes and final source bindings are recorded with the completed
qualification evidence below.

## Runtime

Local checks use the repository pin, Flutter 3.47.8 with Dart 3.13.7. The official
Linux archive was verified with SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
Pinned hosted dependency archives were checked against the existing lockfiles;
dependency resolution did not upgrade versions. Tests invoke the installed
`test` runner with the repository's explicit package configuration to avoid
unnecessary resolution at startup; real CLI tests execute actual Dart
subprocesses. JavaScript programs execute locally in Node.

The previous dynamic-array record's prose contained a mistyped archive digest;
its archived runtime receipt already held the correct digest. Only that prose
was corrected to match the verified archive and retained receipt.

## Final reconciliation

Remote main subsequently advanced through `930074b8` and `b5b32d24`. The only
implementation change was the Word revision serializer's guard against
ambiguous or missing empty formatting targets. Its original commits, tests,
and evidence were merged into checkpoint `6b94e195`; the incoming files were
preserved exactly. The final portable run restarted all six existing programs
and the shared string corpus against that reconciled engine.

Two new native macro tests exercise this guard through the application's normal
DOCX package and settings. Ambiguous history reaches the real save boundary
and fails with `document_error`; `run`, detached `validate`, and recorded
`callTool` retain the original bytes, session revision, and empty recording.
A companion with one valid empty formatting run validates and publishes a
heading edit while preserving its revision history. No protection or tracking
flag is overridden. The tests are included in the macro workflow.

Remote main then advanced to `f9128aba`, merging the six PPTX commits already
contained in this branch. Checkpoint `50fb2ded` retains that actual main parent
and its five evidence/document updates. Comparing the two merge resolutions
showed that the incoming `size / fitScale` caller adjustment was an alternative
to the already-qualified callee correction; applying both would incorrectly
enlarge inherited mixed-run text. The qualified caller/callee pair was retained,
as were the master-suppression, numeric layout, decoration, and connector
repairs. The incoming dark-test change only weakened a passing original opaque
pixel assertion. The original complete test file and stronger assertion remain
unchanged. No new incoming import assertion was absent from this branch.
Consequently this final main reconciliation changed **no qualified production
or test bytes**.

The [later remote snapshot](remote-refresh-final.json) captures 15 fork branches,
100 recent PR heads and the same four upstream heads. At that snapshot mail
PR #221 remained a draft. Zotero PR #223 had become ready for review, but its
body explicitly still described combined-source qualification in progress.
Those concurrently developed feature branches retained their own remote
checkpoints; they were not treated as accepted application releases merely
because they had advanced. The exact main reference is checked again at the
final non-forced expected-head update.

## Local qualification

| Gate | Accepted result | Scope and source binding |
| --- | --- | --- |
| Macro milestone | **901 passed**, 29 files, no failures, skips, or retries | Full selected macro/command cohort, including 102 string unit, 113 conformance/schema, and 11 string integration cases |
| Word revision/native macro follow-up | **34 passed**, no failures or skips | 32 revision/guard cases plus existing transaction rollback and protection cases, after the Word main advance |
| Presentation engine/PDF | **129 passed**, eight files | Final connector, numeric layout, inherited decoration, import and PDF cohort |
| Presentation editor | **51 passed**, four files | Includes all 11 original dark-slide cases and both new presentation regression files across the engine/editor selections |
| Existing portable programs | **Six JavaScript programs passed** | Fresh compilation with `-O1` and local Node execution on reconciled `6b94e195` |
| Shared string corpus | **69 VM and 69 JavaScript cases matched** | Same canonical fixture; complete output receipts are byte-identical |
| Static validation | **Clean** | Final whole-engine `dart analyze --fatal-infos`; 14 affected presentation files and four Word files analyzed separately; applicable formatting and whitespace checks |

These selections overlap and are not added into a single inflated test total.
The 901-case run completed before the final Word serializer advance. The fresh
34-case Word/native follow-up, final whole-engine analysis, and complete fresh
portable replay qualify that concrete later delta. The subsequent PPTX main
merge preserved their implementation bytes. The workflow now selects 30 macro
test files because it also includes the two newly qualified Word save-guard
tests; the recorded large run remains a 29-file, 901-case result.

The broad source capture for the 901-case run records one during-run change:
`packages/quds_office_editor/example/lib/suite_workspace.dart`. Its receipt
deliberately retains `inputsUnchanged: false`. A conservative recursive
import/export/part traversal of all selected tests and macro CLI/web entry
points includes 432 repository files and excludes this Studio UI file. No
imported input changed during that run. The Studio change received separate
editor qualification. The later Word source change is explicitly distinguished
from that unrelated concurrent UI change in the dependency records.

The authoritative fresh portable run guarded **945 inputs**, all unchanged,
and recorded 17 successful commands including runtime version checks. The
Word follow-up guarded **6,225 inputs**, all unchanged. The final presentation
gates each guarded their exact source bytes; independent comparison after the
main merge confirms those bytes still match. The only post-portable workflow
edit adds the separately qualified Word test to the future test selection;
the portable programs and command definitions are unchanged.

The canonical corpus SHA-256 is
`a1f82c1931e78212fe9beddb47e5fcca098ffa09c133e91ab8d3819d268f9151`.
The identical VM/JavaScript receipt SHA-256 is
`a873a66a08bd5632adaea09491476b48ae1dc71a7274c57101af71a6153357c4`.
The final VBA compiler SHA-256 is
`a220206dd7fe42e60a0b0f0be6a4e8adfc19571e095f7bd75b11c8683056a914`.
See [source bindings](source-bindings.json), [remote checkpoints](checkpoints.json),
and the [evidence archive index](evidence/archive-index.json) for exact identities,
commands, raw logs, source manifests, independent reviews, and supersession.

### Retained development attempts

The accepted gates above are distinct from earlier development checks. Original
logs remain available for the initial wrong local test-runner path, an expectation correction
for the existing `ClearContents` diagnostic location, the numeric multiline
failures and unsuccessful directional-mark experiment, and a connector raster
threshold corrected after observing antialiasing. The final test selections
use the corrected source and expectations. The isolated-surrogate XLSX
replacement probe's source is archived. The observed native-plan code unit
was 55357 and the reloaded workbook code unit was 65533; this prose records
that observation because its separate original stdout was not saved.

Two earlier portable attempts stopped on source guards: first the announced
Studio UI edit, then the incoming Word serializer change. The compiler-generated
dependency lists show Word in all six program graphs and Studio in none. The
authoritative final portable run restarted every program on the reconciled
source; the earlier stops were not runtime assertion failures.

The first synthetic Word fixture omitted the native settings part and was
correctly refused by the existing change-tracking admission check. The retained
accepted fixture instead starts with the application's ordinary native DOCX
builder and changes only document XML, so it tests the intended save boundary
through normal admission. Both original and accepted fixture sources and logs
are retained.

### Practical limits

The new VBA expectations are specification-derived or explicit dialect
contracts, without a new Microsoft Office host differential run. Existing
native Word-host fixtures remain preserved, but do not establish VBA parity.
Imported presentation decorations are resolved snapshots rather than a live
master-editing object model. The Studio alignment and duplicate-slide callbacks
received scoped analysis and model/controller/deep-copy coverage; the existing
UI tests do not invoke those callbacks directly. No live mail/Zotero service
acceptance or new application VBA object model is claimed by this milestone.

No GitHub Actions, workflow runs, checks, or commit-status endpoints were
queried or awaited. All qualification described here ran locally.
