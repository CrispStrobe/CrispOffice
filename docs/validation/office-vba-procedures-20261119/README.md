# VBA procedures and functions — 19 November 2026

## Implementation checkpoint

This directory records the incremental extension of the existing `vba-excel`
compiler with in-module procedures, scalar functions, explicit `ByVal`
arguments, isolated call frames, and `Exit Sub`/`Exit Function`/`Exit For`.
Final combined acceptance results will replace this checkpoint status before
the branch is merged.

- Initial remote main: `81ae98688860599f118748afca19bdb2ec45da37`.
- The prior macro/MCP PR #201 and VBA PR #202 code were already in that main.
- The [remote audit](remote-audit.json) covers all current branches and older
  merged or superseded work. A concurrent language-ID test update at
  `ff71fa44c693ee2a30fb0372eac206af257c8477` was integrated by
  `f0ce86842452ee7397afcf21b93c73e126d7d07e` before the extension.
- Its only new source-tree change makes the native smoke assertion follow
  `identifier.topK`; the runtime implementation already used a default of 5.
- [Environment and setup](environment.json): pinned Dart 3.13.7, reduced
  engine/legacy-parser/example workspace, copied manifests, and live source
  links. Tracked dependency manifests and lockfiles remain unchanged.
- Remote checkpoints are saved through the GitHub connector. Each published
  tree is compared with the local Git tree; updates require the previously
  observed branch head and preserve merge ancestry.
- GitHub Actions are not awaited. The user requested local validation because
  the hosted queue is starved. Checkpoint commits use `[skip ci]`.

The [dialect guide](../../VBA_MACROS.md) describes the supported source and
limits. The [procedural report](../../../packages/quds_office_engine/example/macros/procedural_report.bas)
is the reproducible six-item example used by the integration tests.

This checkpoint is not a claim of final acceptance. Development checks have
passed the existing compiler tests, new procedure tests, boundary tests, and
CLI/MCP integration tests. The final receipt will record one combined run,
strict engine analysis, portable JavaScript checks, source hashes, and limits
of the verification scope.
