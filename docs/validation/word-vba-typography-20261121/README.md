# Word VBA baseline positioning and integrated rendering qualification

## Delivered behavior

The `vba-word` adapter now supports `Font.Position` on explicitly selected
paragraph text, including typed `Font` aliases, nested `With`, `ByVal` helpers,
named helper arguments and independent header/footer paragraphs. Positive
points raise text, negative points lower it, and an explicit zero overrides an
inherited displacement. Authored text and font size remain intact.

Each assignment compiles to the ordinary `docx.runFormat` operation. Source
values must be exact whole points in **-1584..1584**. This envelope belongs to
the Quds dialect; it does not describe Microsoft's entire accepted range.
Native JSON separately accepts exact half-point increments within that
envelope. DOCX stores signed half-points in `w:position/@w:val`, with sparse
inheritance and explicit-zero ownership. Imported signed-integer values remain
representable independently of the narrower macro-writing envelope.

Automatic and minimum line spacing reserve the visible raised/lowered extents;
exact spacing keeps its fixed line box. Imported
`w:compat/w:noSpaceRaiseLower` suppresses expansion. Existing superscript and
subscript scaling/offsets remain independent. Position survives splitting,
copying, undo/redo, save/reopen, incremental and note layout, PDF extraction,
paint grouping, comparison and stale-operation fingerprints. Unsupported or
ambiguous native ownership refuses before mutation.

The [complete contract](../../VBA_WORD_MACROS.md#baseline-position-without-resizing-text)
and [native mapping](../../MACROS.md) describe the exact boundaries. The
[BAS example](../../../packages/quds_office_engine/example/macros/word_font_position.bas)
requires three existing body paragraphs and an independent primary header; its
five operations exercise positive, negative and zero positions and preserve an
unrelated bold assignment.

```vb
Sub Main()
    ActiveDocument.Paragraphs(1).Range.Font.Position = 3
    ActiveDocument.Paragraphs(2).Range.Font.Position = -2
    ActiveDocument.Paragraphs(3).Range.Font.Position = 0
End Sub
```

## Integration and retained history

Work was saved incrementally on `codex/word-vba-typography-20261121` using normal
merge parents and expected-head branch updates. The captured frontier contains
**43 fork heads and four upstream heads**, all ancestors of the final code
checkpoint. The refresh also fetched **339 PR heads**: 325 are ancestors, while
14 unchanged historical non-ancestor refs remain explicitly recorded. Newly
captured work is incorporated; historical refs were not treated as new work.

Intake includes the concurrent Mail/main changes, Zotero picture and uppercase
round trips, native note-style validation, converter qualification, and the
page text cache from PR339. Documentation conflicts retained both work streams
and their latest qualification limits. The original branch histories remain
available. [Remote accounting](remote-intake.json) records exact heads, and the
archive retains the fetch and semantic-review receipts.

The original core gates used tree `479bfb1adc542c5f46be270e6d35c3f5c0be1b4d`, published as
`5ebd69bacd789c89e2ee6d06a9807ecf22cac764`. The final code checkpoint is
[`0705336aa52b299e06cf7efabc61228e8e22d662`](https://github.com/CrispStrobe/quds_office_suite/commit/0705336aa52b299e06cf7efabc61228e8e22d662),
tree `416ff798516bbaf51cb07f790bfd0915073d6b0f`. This record is a subsequent documentation-only
addition. The later main documentation commit `0de92d6f42b3b2d1f2df43ef56a7af8e0f49d059`
was also merged; it changes only the existing typing-performance roadmap.
[Publication follow-up](publication-follow-up.json) verifies all final editor
inputs remain identical. GitHub Actions were not awaited.

## Rendering correction during final intake

Review of the incoming page-text cache found adaptive ink depended on mutable
selection and story state absent from the cache identity. Six retained-versus-
fresh pixel comparisons reproduced the defect: table-band selection, mutation
of one caret across cells, and entering/leaving header and footer editing.
Each failing comparison had **688 differing pixels**.

The corrected cache stores one picture per page with an immutable snapshot of
its ink inputs. It includes selected table/band, normalized spanning paragraph
selection, selection fill, header/footer mode and active-story membership when
colors adapt to the theme. It disposes replaced pictures. Collapsed and
same-paragraph caret changes preserve cache reuse. The six mismatches disappear
and all nine focused tests pass, including Position relayout and caret controls.

Code review also found overlay proofing could enter the static body picture.
Both overlay paths now honor the proofing flag, with body overlay findings in
the dynamic clipped pass. The bounded TOC fixtures passed before and after this
correction; no separately reproduced proofing failure is claimed. Raw red and
green evidence, reviewed patches, exact source snapshots and the final combined
renderer run are preserved in the archive.

## Executed local checks

All final execution used **Flutter 3.47.8 and bundled Dart 3.13.7**, matching the
repository pin. Dependencies retain the repository lockfile. Initial Dart
3.14.1 setup/development runs are not presented as the pinned qualification.

| Check | Result | Source binding |
| --- | --- | --- |
| Word/native/compiler/layout regressions | **998 passed**, 31 suites; zero failures/skips | 1,151 engine/test/tool/config inputs unchanged during execution |
| Incoming ODT/Zotero/Word regressions | **716 passed**, 25 suites; zero failures/skips | 981 inputs unchanged during execution |
| Final combined editor/rendering cohort | **75 passed**, 9 suites; zero failures | 584 inputs unchanged at the final code tree |
| Formatter correction follow-up | **33 passed**, strict analysis and format checks passed | Only call wrapping and an optional trailing comma changed |
| Final ODT style matcher follow-up | **46 passed**, zero failures/skips | Equivalent assertion/name/comment update; engine production bytes unchanged |
| Independent ownership/spacing probes | **14 passed** | Pinned runtime and relevant production hashes retained |
| Committed BAS example on VM and JavaScript | **Identical successful receipts** | Five native operations, recording/replay, validation-only behavior, late rollback, three policy refusals and preserved inert parts |
| Versioned Position corpus on VM and JavaScript | **12 cases; identical receipts** | Independently authored expectations and positioned diagnostics |
| Strict analysis and formatting | **Passed** | Engine library, new tests, portable runner and changed renderer; original format failure retained with its successful resolution |

The final editor cohort repeats the earlier 31-case editor run. The formatter,
ODT matcher, focused cache, corpus and cross-runtime runs also repeat relevant
cases; their counts must not be summed into a unique-test total or VBA parity
percentage. [validation.json](validation.json) is the compact machine-readable
result.

## Final-source equivalence

After the broad frozen gates, engine production files remained byte-identical.
Two engine test files changed: the pinned formatter normalized one call, and an
incoming ODT commit clarified an equivalent exception assertion. Their complete
affected suites were rerun successfully. The portable runner, BAS, corpus and
engine inputs also stayed identical; its broad inventory additionally notices
the renderer change, covered by the final editor run.

[source-binding.json](source-binding.json) checks every captured input against
the final checkout and identifies those exact differences. Final editor inputs
match the final code checkpoint byte-for-byte. Changes after that checkpoint
are confined to documentation/evidence, including the incoming main roadmap note.

## Reproduction and evidence

The archive contains exact commands, runtime/config identities, JSONL test
events, per-case results, source inventories before/after, patches and harness
source. It excludes installed SDKs, package caches and generated JavaScript.
[archive-manifest.json](archive-manifest.json) enumerates payload sizes and
SHA-256 digests; [SHA256SUMS](SHA256SUMS) covers this published record.

Use the pinned Flutter installation and the repository's locked dependency
resolution. From `packages/quds_office_engine`, the new engine suites are:

```bash
dart test test/office_macro_word_position_test.dart \
  test/office_vba_word_position_test.dart \
  test/office_vba_word_position_conformance_test.dart \
  test/office_vba_word_position_integration_test.dart \
  test/word_position_test.dart
```

The complete 31-file and 25-file lists are in the archived command receipts.
The workflow in `.github/workflows/office-macros.yml` retains future native and
portable coverage. The portable harness supplies the actual committed BAS with
`WORD_POSITION_BAS_BASE64` and the versioned corpus with
`VBA_CONFORMANCE_BASE64`; VM and JavaScript receipts are compared byte-for-byte.

## Compatibility limits and primary references

This is the existing bounded source-to-plan dialect. It adds no live Position
reads, arbitrary Selection/subranges, document-dependent VBA evaluation or
embedded VBA execution. Embedded DOCM project bytes remain inert and preserved.
No new ODT/RTF Position interchange or installed Microsoft Word differential run
is claimed. Empty text keeps the existing run-format refusal. The imported
compatibility flag qualifies spacing suppression, not complete Word clipping
or font-metric parity.

Primary contracts: Microsoft [Font.Position](https://learn.microsoft.com/en-us/office/vba/api/word.font.position),
[OOXML Position](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.position),
and [NoSpaceRaiseLower](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.nospaceraiselower).
