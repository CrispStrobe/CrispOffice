# Publication cutoff audit

The two inspected incoming tips are integrated in
`8d9d1fe77284f76e71fbd6cb2718d3f6cfb636af`, tree
`86d4b9fa8ed4a04fa73996af69fc6097aacd376e`. Independent local Git checks confirm
that it contains all revisions in the table below. The thirteen mail product
files exactly match the inspected restore/resume implementation. The other GUI
product files and the engine library, tests and tools retain the accepted GUI
checkpoint's contents.

## Exact cutoff

| Role | Commit |
| --- | --- |
| Earlier accepted integration base | `2d7360a217b51c34ccf72eb5ed78c82ccd20bae5` |
| Capture-time local head | `8c6acd04637ef627959fe40f518254ed538ab087` |
| Saved final GUI checkpoint | `2dbd1c58dd724bb2208e06c43a835b220484b1e1` |
| Refreshed main | `caf378f40fd5bda50f504a6816404d01d8bbb8f8` |
| Mail restoration publication | `6275d21246040e03f6264b27171992c88d1474a2` |
| Mail resume head in the 233-reference capture | `9d6cd0504094632825d3a0990a37fffd5c1b2c05` |
| Mail resume implementation supplied from PR 212 metadata | `85c8c55186b8eefd242159ee606b2ad1fa61038f` |
| VBA publication follow-up | `f6b8638d5c78a2d17e5e1c2fb43620c63a23b90c` |

The saved `../remote-publication-capture.json` contains 233 advertised refs.
Root supplied the later exact PR 212 implementation tip separately. This audit
did not chase subsequent draft updates, query Actions, or replace either earlier
capture or audit.

## What changed

- Main `caf378f4` has exactly the same tree as mail publication `6275d212`.
  The publication adds five documentation/evidence paths beyond the previously
  inspected mail tip, with no source or test change.
- Mail resume `9d6cd050` initially adds planning/reconciliation documents. Its
  inherited integration also repairs the editor embedding test host and
  preserves macro qualification records.
- VBA `f6b8638d` adds qualification evidence and braces around one existing
  Settings callback. Those braces are already present in the final GUI
  checkpoint. A virtual merge with the GUI has no product delta; only evidence
  and the embedding test fixture are added.
- Mail resume `85c8c551` adds real functionality: thirteen product files and
  seven test files, plus three documentation/runner files. SQLite schema 2 adds
  bounded restore jobs and completion receipts. Receipts commit atomically with
  originals, index projection and provenance. Resume verifies retained
  destination data before skipping source EML files; full source verification
  remains available. Studio gains resume selection, separate resumed/current-run
  counts, and deliberate progress cleanup in English, German and Arabic.

The implementation checkpoint explicitly describes its local qualification as
in progress. Inherited historical receipts do not qualify its new functionality;
the final local gate run must do so.

Both implementation `85c8c551` and VBA follow-up `f6b8638d` contain the refreshed
main and mail publication, but neither contains the other. Both were therefore
integrated while preserving the current GUI checkpoint.

## Merge checks and preserved GUI evidence

The virtual GUI/VBA merge was clean, with tree
`9d5faf9db2c5b6e999180b286a06b51a8db0e8bf` and no product changes. The virtual
GUI/resume merge had exactly one conflict, in
`packages/quds_office_editor/test/office_dark_slide_test.dart`.

The final integration retains the accepted GUI test blob
`657d07fb25b32c26b19f8aa60e488d6ee7264a02`, SHA-256
`f376ddbeb95ada50e8af7d29b0ef51284d465f2ae0d5705c7979f94163dfabc8`.
That fixture checks exact unchanged light-cell pixels, actual text contrast, and
saved XML colors. The incoming patch widened an older pixel tolerance. Retaining
the accepted fixture preserves the stronger existing assertions and their
acceptance evidence.

The embedding fixture change supplies a MaterialApp Overlay for Word review
tooltips and unmounts widgets before disposing their controllers. Existing
behavioral assertions remain intact. The two incoming tips contain identical
embedding fixture bytes.

All engine `lib`, `test` and `tool` subtree IDs match across the final GUI
checkpoint, both incoming tips and the integrated result. The new cutoff does
not require another VBA test or smoke run. Any already planned smoke gate that
has not yet completed still needs its original acceptance result.

## Additional local acceptance

The exact runnable argument arrays are in `publication-audit.json` under
`additional_local_acceptance.gates`. Execute them serially on the integrated
source, preserving receipts and source identities. Their working directories
are repository-relative.

| Gate | Files |
| --- | --- |
| `resume-scoped-analysis` | Thirteen changed mail product files, six changed mail tests and `packages/quds_office_editor/test/embed_test.dart` — twenty paths. |
| `resume-native` | Seven VM suites listed below. |
| `resume-portable` | `archive_export_manifest_test.dart` and `browser_problem_test.dart` on Node. |
| `resume-studio` | `studio_mail_archive_restore_test.dart`, `studio_mail_archive_portability_visual_test.dart`, and `studio_mail_archive_restore_native_test.dart`. |
| `embed-host-fixture` | `packages/quds_office_editor/test/embed_test.dart`. |

The seven native store suites are:

1. `archive_restore_checkpoint_test.dart` — new receipt, migration, transaction,
   quota and cleanup behavior.
2. `archive_restore_resume_test.dart` — resumed verification, sparse progress,
   destination corruption and exact accounting.
3. `archive_restore_native_test.dart` — genuine native restore, interrupted
   process recovery and the existing restoration contract.
4. `archive_restore_adversarial_test.dart` — existing adversarial source and
   cancellation boundaries.
5. `archive_native_test.dart` — schema ownership, native persistence and repair.
6. `archive_multi_origin_test.dart` — shared atomic provenance-write behavior.
7. `archive_repository_test.dart` — shared repository and quota behavior.

These files are under `packages/quds_mail_store/test`. Native SQLite tests are
not selected for Node. The portability pair checks the public exports and
declared browser boundary after adding the checkpoint models.

## Evidence status

`publication-audit.json` records ancestry, complete path classifications, virtual
merge results, exact product hashes, the retained fixture, unchanged engine
subtrees, runnable gates, and hashes of prior evidence. Its
`merged_result_verification` confirms the actual integrated commit and tree.

This report verifies source integration and selects acceptance gates. It does
not claim those new gates have passed. No compiler or tests were run by this
audit, and no product files, screenshots, working-tree index or Git refs were
modified by its inspection commands.
