# Slide-table text-color correction

The incoming dark-slide test reached an unchanged export assertion after its raster fixture was corrected. The table writer emitted each cell's text color, but the DrawingML reader assigned a cell's `txBody` fill to the containing `PmlShape.textColor`. As a result, reopening the presentation left every `PmlTableCell.textColor` empty.

The production correction routes a pending text fill to the active table cell when one exists. It preserves the cell model's first nonempty representative run color. Ordinary shape text assignment, table-cell background precedence, and shape fill/stroke handling remain unchanged.

## Retained failure and corrected checks

The `before` run used the exact parser from commit `f6b8638d5c78a2d17e5e1c2fb43620c63a23b90c`:

- Git blob: `7c5c13518a28ae53a0cb267745d86ef7e548dab5`.
- SHA-256: `db979f21e10238a4c87731f35e29c267bda82891b0809c8c27ed206a83c8da37`.
- Both new regressions failed, reporting empty cell colors instead of explicit black and a distinct RGB/theme color.

The identical regression tests then passed with the parser correction. The full focused run passed **33 distinct cases**: 20 in `slide_test.dart`, seven in `slide_import_fidelity_test.dart`, and six in `slide_text_fidelity_test.dart`. Strict analysis of the changed production and test files and the formatting check passed.

The direct XML test exercises a black first run followed by a contrasting run, a theme-resolved cell, an automatic-color cell, three background fills, and a neighboring ordinary shape with separate text, fill, and stroke colors. The second regression checks three complete PPTX save/reopen cycles with black, distinct RGB, and automatic colors. No production writer change was needed.

Each run captured the same 352 input paths before and after execution and found them stable. Comparing the two runs, only `lib/src/slide/shapes/drawingml.dart` changed; the new regression test file was identical. The snapshots include all engine library Dart files, the three selected test files, and applicable package/workspace manifests and analysis configuration. Receipts also hash the resolved dependency configuration and lockfile. This focused run does not represent a complete engine or repository test run.

## Reproduction and evidence

`run-focused.py` writes raw reporter output, command lines, working directories, exit codes, input snapshots, and the exact two-file patch. It refuses to overwrite an existing phase receipt. Copy it into an empty evidence directory to repeat a run. Supply the repository, reduced validation workspace, Dart executable, pub cache, and temporary directory paths, and choose `--phase before` or `--phase after`.

To reproduce the original failure, use an isolated checkout of the recorded commit and apply `before-source.diff`, which adds only the two regression tests. The `after-source.diff` includes both those tests and the narrow production correction. The baseline receipt explicitly records that its parser matched the original Git blob even though the new tests had not yet been committed.

Both failed reporter events are retained in `before-tests.stdout.log`. `after-tests.stdout.log`, the analysis/format logs, and both receipts preserve the corrected results. `artifacts-sha256.json` hashes every retained file except the manifest itself. The full macro and JavaScript qualification after this engine correction is recorded separately under `engine-publication/`.
