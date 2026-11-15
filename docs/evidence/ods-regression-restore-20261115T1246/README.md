# Restored ODS regression qualification

Source checkpoint: `9bb71983a4ae6bc7bb3372fd931e724ddd102fc8`, based on observed `6e4c3b16b4310f2c21b6d8b5e412af9850eb17ea`. The only source-checkpoint change restores the exact three qualified predecessor tests for native column geometry, currency symbols and inherited styled-padding sparsity. New covered-cell and comment-count bounds are unchanged.

## First recorded runtime attempt

`ods-suite-path-binding-attempt/` preserves the original raw command, machine stream and unchanged source/input snapshots. All 70 visible tests passed, with zero failures, errors or skips and process exit 0. The strict receipt checker correctly kept qualification incomplete: the engine-cwd test path was reported as `test/ods_sheet_reader_test.dart` while the repository-relative requested manifest used `packages/quds_office_engine/test/ods_sheet_reader_test.dart`. This is a recording-path mismatch, not a behavioral test failure. The attempt is retained unchanged; a follow-up command uses an absolute suite path.

The explicit derived package graph retains the settled 55-package host engine development dependency versions, changes only engine/parser source roots to the canonical checkouts, and performs no dependency solver run or app mutation. `setup/derived-graph.json` records all URI bindings. Scope is the focused ODS suite; no GitHub Actions run is awaited.
