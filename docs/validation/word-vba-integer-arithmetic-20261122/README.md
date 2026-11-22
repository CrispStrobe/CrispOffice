# Word VBA integer arithmetic — 22 November 2026

## Scope and checkpoint

This continuation integrates the latest Word suffix and Mail identity branches
before adding shared integer division and signed remainder. Remote checkpoints
are retained on `codex/word-vba-extended-20261122`. GitHub Actions are not an
acceptance gate and have not been queried or awaited.

The implementation adds `\` and `Mod` to the common source compiler. The
complete `word_grouped_report.bas` fills a 2×2 table, appends group labels and
alternates emphasis using existing native operations. The explicit
[arithmetic contract](../../vba-macros-details.md#integer-division-and-remainder)
records rounded Long bounds, strict conversion rules and the signed-remainder
specification discrepancy. Embedded VBA stays inert; installed Office
differential qualification remains separate.

## Qualification in progress

- New arithmetic and existing numeric/Variant gate: **687 passing tests across
  five suites**, zero failures/skips, empty stderr. Dart 3.13.7; source hash
  `0847838044cb18fe844fc2660870a0141a9f8d16b3c9d98f183297afff94d60b`.
- Initial independent corpus/document gate found test-expectation mistakes:
  two static diagnostics point at the invalid operand, and native `run` does
  not record its own expansion. The expectations and recording fixture were
  corrected; that attempt is not a passing gate.
- Local disk exhaustion temporarily blocked sandbox startup and the Mail
  SQLite hook. No test pass is claimed for those failed infrastructure steps.
- Broader source-bound regression, corrected document integration, VM/JS
  equivalence and integrated Mail qualification are still being completed.

This checkpoint is a preservation milestone, not the final acceptance record.
