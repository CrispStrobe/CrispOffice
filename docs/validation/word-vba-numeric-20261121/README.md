# Word VBA numeric authoring continuation

## Implementation checkpoint

This continuation adds shared source-known `Abs`, `Int`, `Fix` and `Sgn`
calculations to the Word, Excel and PowerPoint VBA adapters. No native operation,
renderer, document format or tracked dependency manifest changes are needed.
The exact [numeric contract](../../VBA_MACROS.md#numeric-intrinsics) distinguishes
negative floor/truncation, Empty/Null behavior, explicit conversion requirements
and the existing portable numeric envelope from full VBA numeric subtype rules.

The executable
[Word numeric report](../../../packages/quds_office_engine/example/macros/word_numeric_report.bas)
requires three body paragraphs and one independent primary-header paragraph.
It emits nine ordinary native operations through typed helpers and computed
selectors, preserves unrelated rich text and inert VBA project bytes, and keeps
the existing validation, recording, rollback and permission boundaries.

The first remote implementation checkpoint is
`f3e93e7ba7a847f6e90ed7afbf8b618ddee19867`. Its focused compiler and canonical
corpus suites pass 192 cases. The completed DOCX/DOCM/CLI/MCP integration suite
passes another 12 cases. The actual BAS produces identical VM/JavaScript
receipts. These development results will be superseded by the final source-bound
regression and portability qualification below; they are not added twice.

## Preserved intake

The initial captured frontier contains 45 fork heads, all 339 pull-request heads
and four original upstream heads. Both outstanding Zotero continuations are
incorporated with real merge ancestry. Their production fixes were already in
initial main `aa861c28e336b17bcd4c259351164380cd6b1438`; the intake adds their
separate qualification evidence and both page-cache regression test files.
The one documentation conflict retains both independently scoped narratives.

Remote intake checkpoint `80cc132f57367a9cfe607ed6c510e3175a24e17c` preserves
`c0ae75c226b13ae1ec4ab31238004d558ad01531` and
`a7f69313ed2e610f82242c31be8ad5387ae5cea0` as parents. Its replay accounts for
all 388 captured refs: **374 actual ancestors and 14 verified historical
replacements**, with no uncovered refs. Thirteen replacements have identical
complete Git trees; one has identical blob/mode changes on every touched path. See
[the intake record](intake/README.md), exact inventory, proofs and replay script.

## Local qualification procedure

Use the pinned Dart 3.13.7 and the existing dependency lock. Resolve the normal
workspace with its pinned Flutter SDK, or reproduce the isolated pure-Dart
engine harness described in `independent/README-runtime-and-numeric-review.md`.
The harness creates only an ignored package config and keeps all tracked
manifests/locks unchanged. No GitHub Actions/check/status queue is queried.

```sh
python3 docs/validation/word-vba-numeric-20261121/run_local.py \
  --dart /path/to/dart-sdk/bin/dart --phase regression --output /path/to/results/regression
python3 docs/validation/word-vba-numeric-20261121/run_local.py \
  --dart /path/to/dart-sdk/bin/dart --phase static --output /path/to/results/static
python3 docs/validation/word-vba-numeric-20261121/run_local.py \
  --dart /path/to/dart-sdk/bin/dart --phase portable --output /path/to/results/portable
```

The runner retains process exits, compressed raw stdout/stderr, case identities,
source snapshots before/after, SDK/package-config identities and complete native
receipts. The portability phase uses the exact BAS and fixture bytes, checks
VM/JavaScript equality, and includes the existing Variant composition/conversion
corpora because numeric functions compose with nullable expressions.

The independent numeric review separately passes 81 checks on both VM and
JavaScript, with identical receipts and unchanged compiler source. It covers
negative zero, subnormals, both numeric bounds, static refusals, single helper
evaluation and typed alias identity. Those supplemental checks are retained
separately from regression totals.

## Scope

This is bounded source-to-native-plan compatibility. It does not add document
reads, embedded VBA execution, locale-dependent implicit coercions, complete
VBA numeric subtype fidelity or an installed Microsoft Word differential run.
The inherited renderer tests are preserved; this source-only change does not
claim a new Flutter/UI or installed Office qualification.
