# Word VBA shading and text construction — local qualification

## Delivered behavior

Word gains typed `Shading` objects on explicit paragraphs and paragraph-selected
ranges, `BackgroundPatternColor` / `BackgroundPatternColorIndex` setters, and
all 60 named `WdColor` constants. Aliases, nested `With`, required `ByVal Shading`
helpers and named helper arguments retain body or independent header/footer
identity. Empty paragraphs are supported.

Native `docx.paragraphShading` prepares a detached sparse-property snapshot,
preserves earlier plan edits and unowned XML metadata, and publishes once.
Same-value assignments become direct formatting. Automatic backgrounds persist
as explicit `w:fill="auto"` and render as no fill, overriding inheritance.
Relevant patterns/themes and ambiguous source ownership are refused atomically.

All three source adapters gain `Space`/`Space$`, `String`/`String$`,
`ChrW`/`ChrW$`, and `AscW`, with exact numeric arguments, UTF-16 code units,
actual String character operands and shared work/output limits. Constructed
text remains subject to the existing native Unicode/XML publication guards.

See the [shading contract](../../VBA_WORD_MACROS.md#paragraph-background-shading),
[construction contract](../../VBA_MACROS.md#text-construction-and-unicode-code-units),
and complete [shading](../../../packages/quds_office_engine/example/macros/word_shading.bas)
and [construction](../../../packages/quds_office_engine/example/macros/word_text_construction.bas)
BAS examples. The examples perform seven and five native operations respectively.

## Remote reconciliation

Initial fork `main` was `4970f71f983535d045ce263e86835b499db4fda9`.
All 35 other fork heads, four upstream heads and latest 100 PR heads (#233–332)
were already ancestors, with no open PRs. Exact refs and comparisons are in
[remote-intake.json](remote-intake.json); [intake.json](intake.json) is the summary.

Incremental remote checkpoints on `codex/word-vba-format-controls-20261121`
include `2e8f0f38` (intake), `85033b80` (compiler/construction/examples),
`655b2722` (native implementation/contracts), and `37afb04e` (concurrent intake
ancestry). The last normally merges Mail checkpoint `71dc9cc0`, adds exactly
six Zotero planning/audit documents, matches Git's independent merge-tree result,
and changes no production/test source.

Later Zotero source checkpoints `bf54a8e7` and `fac61ecd` appeared after intake.
Both explicitly describe unfinished qualification and overlap in three
reader/writer files. Their implementation remains on its original remote
branches for its owners to reconcile; this record does not qualify it.
The concurrent empty Word tables branch was at initial main.
[final-intake.json](final-intake.json) records exact observations.

GitHub Actions were not awaited or used as the gate. Branches were retained;
history was extended with normal parented commits, without force pushes or
protection changes.

## Executed local checks

Official Dart **3.13.7** was verified against archive SHA-256
`eb99aed266efbcb615c6ae21c12f52cfe935b9f208bccc5fea7f64c21e867229`.
All 56 hosted dependencies match lockfile versions and archive hashes.
An isolated workspace uses byte-identical engine/parser manifests and live
source links. Tracked manifests/lockfiles were not changed. Canonical package
resolution avoids treating symlinked paths as distinct Dart library identities.

| Gate | Executed result |
| --- | --- |
| Broad macro/VBA and affected Word/style/ODT regressions | **5,871 passed in 117 suites**, zero failures/skips |
| Final new-feature tests after lint/format cleanup | **338 passed in four suites**, zero failures/skips |
| Focused breakdown | 125 shading compiler, 48 native, 12 shading integration, 153 construction |
| Strict analysis | Entire engine `lib` plus all new tests/runners: **no issues**, `--fatal-infos` |
| Formatting | All 11 changed Dart files: zero changes required |
| Both actual committed BAS examples | VM and compiled JavaScript pass; complete receipts byte-identical |
| Independent native review probe | Automatic/style refresh, same-value ownership, sparse spacing inheritance and three rebound-prefix roundtrips pass |

Counts overlap and must not be summed. The broad gate precedes six brace-only
lint fixes in the native helper and one test-format correction. The final
338-case gate, strict analysis and both final portable runs use the resulting
source. The later documentation-only ancestry merge does not change that source.

Each final portable run captured **507 source, macro runner, BAS and manifest
hashes**, unchanged before/after execution. Matching VM/JavaScript stdout hashes:

- Shading: `be06f00690b723e264fcf47f5a558f50db3cb9e7f04df0e34f0291fdcc06cd89`.
- Construction: `7649356d36fe1e0869acc2daa8008499b3c76bdb3dc1ed693032561763750f02`.

The shading example independently checks native explicit fills, original text
and run formatting, empty paragraphs, body/header/footer identity, DOCM VBA and
custom XML, validation without publication, repeat execution, recording/replay,
two additional reopens, late rollback and six policy denials. Construction
checks Unicode/unit behavior, rich formatting and opaque VBA preservation,
validation, replay, extra reopens, late rollback and three policy denials.
CLI/MCP integration also checks diagnostics and preservation of existing output
after failure.

Raw final logs, exact commands, runtime/dependency receipts, portable input
inventories and the independent probe are in [execution.tar.gz](execution.tar.gz).
[validation.json](validation.json) contains summaries, archive digest and final
changed-source hashes. Reproducible compiled JS bundles are omitted.

With repository dependencies resolved, the focused gate is:

```sh
cd packages/quds_office_engine
dart test test/office_macro_word_shading_test.dart \
  test/office_vba_word_shading_test.dart \
  test/office_vba_word_shading_integration_test.dart \
  test/office_vba_text_construction_test.dart
```

## Boundaries

This is a bounded source-to-plan extension, without live document reads or
embedded VBA project execution. Texture/foreground and character/table shading,
arbitrary ranges, linked-story propagation and numeric code-page `String`
operands remain unsupported. Full signed `ChrW(-32768)` is a documented Quds
choice preserving `ChrW(AscW(U+8000))`; MS-VBAL's printed lower bound is -32767.

No installed Microsoft Word differential run or Flutter/Studio UI execution was
performed. The actual pure-Dart engine, native serialization/layout, CLI/MCP
transactions and compiled JavaScript paths were executed locally as recorded.
