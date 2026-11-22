# Word VBA cell paragraphs — local qualification

## Intake and persistence

The 22 November 2026 intake started from remote `main`
`a5b4eb7d329b0700768b1fc72bb63cf58a9f5cd6`. All 23 other observed remote
branch heads were ancestors of that commit, and GitHub reported no open pull
requests. The recent Word, Mail and Zotero changes were already integrated.
No unmerged branch was discarded or replaced. The upstream repository,
`MohammedAsaadAsaad/quds_office_suite`, has main
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`; a direct fetch and ancestry check
confirmed it is also already contained in the intake main. Exact fork branch
heads and the upstream check are recorded in [remote-intake.json](remote-intake.json).

Work is checkpointed incrementally to
`codex/word-vba-compatibility-20261122`. The requested final target is remote
`main`. GitHub Actions are not an acceptance dependency for this change;
qualification runs locally and records actual results here.

Two independent branches appeared after this intake. Mail durable mutations
explicitly remained a checkpoint before host qualification, while Zotero field
recovery contained only intake documentation. Both had no open PR. Their
observed heads and readiness evidence are recorded in `remote-intake.json`;
their ongoing work was preserved on its existing branches. The Word publication
refreshes main again before merging.

## Scope

Expose the existing ordinary paragraph in an explicitly selected table cell
through `Cell.Range.Paragraphs(1)` and `Cell.Range.Paragraphs.Item(1)`, preserving
table, row and column identity through typed aliases, nested `With` and `ByVal`
helpers. Enable the existing bounded paragraph Style and background Shading
contracts on this selected paragraph, alongside its existing text formatting.

The supported native target remains one ordinary paragraph in a direct,
rectangular, unmerged main-story table. Paragraph styles and shading are
distinct from cell/table formatting. Live reads, collection enumeration,
arbitrary text subranges, multiple cell paragraphs, insertion, list operations
and embedded project execution are separate work.

The selected paragraph accepts `Style` / `Range.Style` and `Shading` /
`Range.Shading`, plus its existing Font, ParagraphFormat, tabs and text controls.
The same native cell coordinates survive repeated paragraph projections,
parent-variable rebinding and named `ByVal` helpers. Direct cell-range Style and
Shading still require explicit paragraph selection. Style/background changes
can target an empty paragraph without inserting text; Font writes still require
nonempty current ordinary text.

Known direct and acyclic local cell-paragraph insertion/list operations are
rejected even in inactive source. Generic parameters and mixed or cyclic alias
origins retain actual-selector checks during source evaluation. The compiler's
cell operation allowlist and native selector guards retain the final active
formatting boundary.

## Persisted checkpoints

| Commit | Checkpoint |
| --- | --- |
| `d8cb9eab19517503805b16f25ff95c25754e6c7a` | Intake, remote ancestry and bounded scope |
| `eff93c9f25cf09aef9677bc94892e3ddceb75fe6` | Compiler/native implementation and focused regression tests |
| `708bf4a6cf2651a2f08f900631119f357aef4611` | Static-origin guard, complete BAS, independent corpus, integration/portable checks and reference docs |
| `45a1c0846f3fb78a203f2967e5b80a79fdca2ca9` | Reviewed contracts, semantic portability comparison and source-bound analysis/review/example receipts |

The tested implementation is `708bf4a6`. Later documentation/evidence commits
leave those implementation, test and example bytes unchanged. Final receipts
retain actual checkout provenance and source-file hashes independently of
documentation-only HEAD movement.

## Local verification

The final source uses Dart 3.14.1 and Node 24.22.3. An isolated pure-Dart
workspace resolves the engine and legacy parser while retaining exactly all
56 dependency versions from the repository lockfile. The tracked Flutter
workspace manifests and SDK pin are unchanged. See the
[runtime record](setup-attempt/runtime.json).

Acceptance accounts for all **7,224 cases across 149 test files**: 7,218
original successes plus successful unchanged-source rechecks of all six
original failures. No failures remain unresolved. This is aggregate acceptance,
not a claim of one clean 149-file execution. The complete mapping is in
[failure-resolutions.json](failure-resolutions.json), and the final source
manifest verifies 1,221 unchanged inputs after fixture restoration.

| Check | Evidence |
| --- | --- |
| Broad macro/language/native coverage and resolved rechecks | [aggregate acceptance](acceptance-summary.json), [initial test summary](setup-attempt/tests-summary.json), [149 suite paths](setup-attempt/suites.txt), [exact command](setup-attempt/test-command.json) |
| Strict engine analysis | [analysis receipt](analysis.json) and [stdout](analysis.stdout); `dart analyze --fatal-infos lib test tool` reports no issues |
| Independent cell-paragraph corpus | [Original portable receipts](corpus-summary.json): 32 cases, 14 complete native plans and 18 positioned diagnostics; VM and compiled JavaScript consume the same fixture bytes |
| Actual table-template BAS | [portable receipt](portable-example-receipt.json); eight native operations, recording/replay, DOCM preservation and two additional save/reopen cycles |
| Independent implementation review | [review.json](review.json), including addressed static-origin and workflow findings |

The example's VM and JavaScript receipts compare decoded JSON: integral
spacing values serialize as `6.0` on the VM and `6` in JavaScript. They have
the same numeric meaning. The conformance runner emits canonical receipts
that compare byte-for-byte. The workflow preserves this distinction.

The actual BAS also runs through CLI and MCP tests. These check native
metadata/paragraph styles/backgrounds, retained foreign XML and opaque VBA,
unrelated cells and table geometry, empty paragraphs, named helper rebinding,
policy/allowlist/step/cancellation limits, and unchanged existing output after
both compilation and later native failures. The native style/shading suite
checks detached property ownership and the same-value/automatic-background
serialization contracts.

### Setup attempts and deadline diagnosis

The complete broad run used concurrency four and executed all 149 files with
7,218 visible passes and six failures. Four were missing tracked font fixtures
in the fresh isolated workspace. Two existing section/proofing tests hit their
execution deadlines at nearly the same point in that parallel run. This attempt
is retained separately in [setup-attempt](setup-attempt/). It is not represented
as a clean run; acceptance combines its complete coverage with verified,
unchanged-source rechecks of all six failures.

The tracked fonts were materialized and added to the input manifest. The two
deadline-affected suites then passed sequentially with their original production
and test time limits: 37 visible tests, no failures or skips. Their independent
receipts are retained in [deadline-isolation](deadline-isolation/). The four
font-dependent failures also passed during the sequential rerun once the
tracked font was available. No production or test timeout was relaxed.

After all six failed cases had successful rechecks and no source inputs had
changed, the redundant remainder of the sequential broad rerun was interrupted.
Its actual exit status and partial results are retained. The aggregate
acceptance maps every original failure to a successful recheck and does not
claim a single clean 149-file execution. Successful rechecks are not added to
the original total as additional unique cases. Source manifests distinguish
the restored fixture availability from unchanged implementation/test bytes.

The initial full analysis also needed three tracked PDF example files restored
from sparse checkout so existing imports could resolve. The final analysis
passed without source changes for that setup issue.

## Reproduction

Use a supported Dart/Flutter SDK with the repository dependencies resolved and
the tracked editor fonts available. From `packages/quds_office_engine`:

```bash
dart analyze --fatal-infos lib test tool
dart test --concurrency 1 --reporter json $(cat ../../docs/validation/word-vba-cell-paragraphs-20261122/setup-attempt/suites.txt)
```

The new independent suite can also run by itself:

```bash
dart test test/office_vba_word_cell_paragraphs_conformance_test.dart
```

For the complete BAS, supply an existing supported 2×2 table. The first cell
needs nonempty ordinary text for its Font write; cell `(2, 1)` may be empty.
The template needs primary paragraph style names `Report Label`, `Normal` and
`heading 1`. The latter two must be noncustom native definitions for the built-in
selectors; `Report Label` may be custom. Compile or run it using:

```bash
dart run tool/macros/office_macro.dart compile-word-vba \
  example/macros/word_table_paragraphs.bas prepared.qudsmacro.json
dart run tool/macros/office_macro.dart run-word-vba \
  template.docx example/macros/word_table_paragraphs.bas prepared.docx
```

## Qualification boundaries

These checks establish the documented source-to-plan subset and guarded native
document behavior. No installed Microsoft Word host was executed. Live document
reads, multiple paragraphs per cell, merged/nested table semantics, arbitrary
subranges, whole-cell/table shading and embedded VBA execution remain outside
this increment. Existing opaque VBA projects are preserved as package bytes.

## Publication

[PR #362](https://github.com/CrispStrobe/quds_office_suite/pull/362) targets
remote main with a normal merge commit so incremental checkpoints remain in
history. The pre-publication refresh still found main at the original intake
commit. Independently active Mail/Zotero branches were left intact, including
their newer qualification checkpoints. GitHub Actions were not awaited and
branch protection was not changed. The PR carries the definitive merge receipt.

## Primary contracts

- [Range.Paragraphs](https://learn.microsoft.com/en-us/office/vba/api/word.range.paragraphs)
- [Paragraphs.Item](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs.item)
- [Paragraph.Style](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.style)
- [Paragraph.Range](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.range)
- [Paragraph.Shading](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.shading)

These references specify Microsoft APIs. Quds' single-paragraph selectors,
supported style/color subsets and resource limits are explicit dialect
restrictions, not results observed from an installed Microsoft Office host.
