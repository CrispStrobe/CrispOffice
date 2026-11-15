# Saved comments failure baseline

Exact test-only source: [`9fbf25b1f54afd535b8633ce96122c6727c6608b`](https://github.com/CrispStrobe/quds_office_suite/commit/9fbf25b1f54afd535b8633ce96122c6727c6608b). Production bytes remain those of `6e4c3b16b4310f2c21b6d8b5e412af9850eb17ea`.

The two comments suites ran **14 tests: 3 controls passed and 11 failed**, with no skips. Failures reproduce missing SpreadsheetML namespace, bare text instead of CT_Rst `t` children, inability to import/edit a relocated comments relationship, and resurrection after comments are cleared. The original author-table tests and the legacy fixed-name import control passed.

The saved-source generator emitted three actual XLSX packages with six comments each. **Openpyxl 3.1.5 read all five nonempty texts as empty on every cycle**, while author identities survived. The independent ZIP/XML oracle also rejected missing namespaces and text containers. Its positive control uses independent openpyxl-authored packages; its negative controls mutate namespace and text shape. These controls and raw results are retained.

`artifacts.tar.xz` contains raw test events, commands, all three generated failing workbooks, before/after source/resolution snapshots, executable/module hashes, the independent oracle and its controls, the primary-source review, and dependency setup. `artifacts-manifest.json` records every member; inventory, sizes and SHA-256 values were verified after archiving. All source-bound gates record unchanged source, commit identity, resolution inputs and tools; the oracle records unchanged workbook bytes.

Canonical workspace package resolution created an ignored local lock without changing tracked declarations or committed locks. The captured graph is separate from the host app graph. This evidence establishes the recorded failures only; it makes no broad OOXML schema or native Excel rendering claim. No GitHub Actions run was awaited.

The original runner compared package-relative Dart event paths with repository-relative inventory paths, so its original missing/unexpected suite fields show a prefix mismatch. `baseline-accounting-review.json` inside the archive re-parses the unchanged raw stream using the recorded working directory: both requested suites were observed, with no missing or unexpected suites, and the same 14/3/11 counts. The original summary and runner are preserved; `record_gate-cwd.py` records the correction for subsequent gates.
