# Word VBA text columns — 21 November 2026

## Change and scope

This increment adds explicit `Section.PageSetup.TextColumns` selectors, typed
aliases and required `ByVal` helpers, `SetCount NumColumns:=n`, `Spacing` and
`LineBetween`. The guarded `docx.textColumns` operation changes one uniform
section, preserves unrelated native XML and validates resulting geometry before
publication. The complete BAS example lives at
[`word_text_columns.bas`](../../../packages/quds_office_engine/example/macros/word_text_columns.bas).

The [contract](../../VBA_WORD_MACROS.md#uniform-section-text-columns) records
numeric bounds, method forms, property ownership and unsupported scope. No
live document reads, unequal-column conversion, full VBA runtime or installed
Microsoft Word differential acceptance is claimed.

## Recent-work intake

The initial remote main was `08fe271f945dfc915dc817febb756ca111baed73`.
All 33 advertised branches were inspected; 29 non-main tips were already
ancestors. The outstanding Mail test branch merged as PR #317 during intake,
advancing main to `f3a0a64a8ea2995221e262d65950283a6049dfb4`.
All pull-request head refs were fetched, and the open-PR list was empty after
that merge.

The integration checkpoint `db364268d5034fa4a66d482534c6912ce2f559d9` retains
that main and both outstanding branch histories:

- `fix/goldens-about-20261121` at
  `90736bdcf07feb64b8e1c2a76c8a80d9decf0ccb`: running app version/build in About,
  deterministic About tests and dependency/platform lock updates; additionally,
  preserve the authored PPTX transition oracle when no duration was authored.
- `ci/golden-attrib-20261121` at
  `3bae324bbc56d7fa49089100eace3dd3c4798153`: retain ancestry while omitting
  `.github/workflows/tmp-golden-attribution.yml`, whose own header requires
  removal before merge. The original diagnostic remains recoverable from its
  remote branch/history.

The source adapter and example were saved next in
`e33a81c68bd4271d71270d5ebc0de73bb28e4fe3` on
`codex/word-vba-next-20261121`. Further native, regression and qualification
checkpoints follow on the same branch. GitHub Actions are not an acceptance
gate for this work, as requested; all execution described here is local.

## Local environment and qualification in progress

The official Flutter 3.47.8 archive was restored and SHA-256 verified; its Dart
SDK is 3.13.7. The workspace and Flutter-tool dependencies resolve offline with
the checked-in lockfiles enforced. No source manifests were changed for setup.

Completed intake checks:

| Check | Result |
| --- | --- |
| Existing Word conformance smoke | 46 tests passed |
| Existing native AllCaps editor smoke | 7 tests passed |
| Incoming Studio About tests | 11 tests passed |
| Analysis of incoming About source and tests | No issues |
| Incoming authored-transition Python oracle checks | Source compiled; 14 positive/negative subtree checks passed |

The Python oracle checks target the exact changed transition assertions and
actual fixture subtrees. They are not a full generated PPTX export qualification.
Native macOS/iOS builds and installed Microsoft Office are not executed here.

The new source suite initially passed 78 cases. Independent review identified
and corrected a missing static scalar-Variant/object guard; additional unused
helper and dead-branch cases now exercise that boundary. Native integration
also exposed a pre-existing nested-namespace capture bug; its original failing
fixture is retained as a preservation regression. Final combined results and
source-bound receipts will be added after these checks complete.
