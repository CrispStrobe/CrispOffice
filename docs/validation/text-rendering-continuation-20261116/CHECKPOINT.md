# Continuation checkpoint

## Recovered completed qualification

Implementation checkpoints `deb5531`, `097f615`, and `59b69ac` preserve the
PDF CID encoding and TrueType subset repairs. The later recovered checkpoint
`6bf486ee0bbcd2025c3a42cae7d7003b8c9324a4` preserves the actual engine,
baseline, and independent PDF evidence:

- 169 engine tests passed; strict analysis and formatting passed; recorded
  inputs were unchanged during that run.
- Against baseline `0d19b16`, the same 20 regression probes produced ten
  assertion failures, nine errors, and one success. These expected baseline
  failures demonstrate the old defects, not a passing gate.
- Independent Poppler rendering produced zero differing pixels for the
  encoded shared-glyph fixture versus its identity-glyph reference, and
  preserved the exact authored Unicode scalars on extraction.
- No production dependency or bundled font binary was added. The numeric
  OS/2 coverage transcription retains its MIT notice.

The engine receipt remains attributed to its recorded source and inputs.
The new incoming ODS source/test changes require their own qualification.

## Resumption integration

The pinned snapshot at 2026-11-16 19:37:47 UTC contains 166 fork/upstream
branch and PR heads. Current main `be9eeec9` merged cleanly into the rendering
source. Its six incoming paths include ODS filter predicates, row groups and
geometry outside populated cells, updated documentation, and a font-fixture
path fallback in the PDF viewer tests.

The eight additional feature/documentation/vendor tips contain nine
non-merge commits. All nine match canonical main commits by both stable Git
patch ID and exact full patch bytes after removing only Git index lines.
All affected files match main exactly. The integration retains their
ancestry without reapplying duplicate source changes; the cleaned vendor
test is preserved. See `resume/complete-patch-equivalence.json`, the pinned
`resume/remote-snapshot.json`, and `resume/merge-plan.json`.

## Remaining local qualification at this checkpoint

The first real Flutter editor cohort has completed: all 66 tests, strict
changed-file analysis and formatting passed, with 462 input hashes unchanged.
Its source-bound receipts and rendered fixtures are preserved in `editor/`.
The verified Flutter 3.47.8 / Dart 3.13.7 runtime provenance is in `runtime/`.

The final combined-source qualification passed: **279 engine tests** across
19 files and **66 Flutter tests** across eight files, with strict analysis and
formatting passing in both cohorts. All 399 engine and 462 editor input hashes
stayed unchanged. The final independent PDF check again produced zero differing
pixels and exact authored Unicode extraction. See `README.md`, `engine-final/`,
`editor-final/` and `poppler-final/`. These overlapping final cohorts supersede
the initial qualification for the combined source; their counts are not added
to earlier totals.

The independent merge-tree review in `incoming-merge-review.json` also verifies
that all nine incoming heads yield the same source tree as main-only integration,
`754fd323403c79e822f33421d132cdc9c022b0e4`, after retaining the combined main
contents in four documentation/test conflicts. It found no production conflict.
Both this review and the independently saved `resume/` audit are retained.

A concurrent branch update published this integration as `3a8306e` while a
separately prepared checkpoint `0634236` contained the same production changes
plus runtime/editor evidence. Their reconciliation preserves both commit
histories and audit sets; it introduces no additional production change.

Shared editor/headless shaping remains a separate future integration. The
current export changes fix character-code/glyph-ID aliasing and subset
structure; they do not implement a shared HarfBuzz or Rust shaping backend.

GitHub Actions are not queried, awaited, polled, or rerun. Remote checkpoints
use `[skip ci]`; qualification is local.
