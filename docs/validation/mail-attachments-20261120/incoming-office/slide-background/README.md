# PPTX background integration repair

The final focused fidelity suite passed **42 tests, 0 failures, 0 skips**, with a successful JSON `done` event and all **416** recorded source/dependency inputs unchanged during the run. Strict `dart analyze --fatal-infos` passed on the three edited sources and the test file. The exact accepted source hashes are in `serialization-analysis-receipt.json`; the broader 416-file snapshots are in `serialization-inputs.json` and `serialization-inputs-after.json`.

## Behavior repaired

Background fill is selected once in slide, layout, then owning-master order. The selected image is behind ordinary master/layout decorations and is independent of `showMasterSp`, which controls master shapes. Explicit local/layout solid, gradient and noFill backgrounds suppress inherited image fills. Local background images work without a resolved layout relationship. Gradient fallback uses the correct slide/layout/secondary-master color resolver.

The import-only repair exposed a save/reopen defect: the DrawingML writer omitted the authored `p:bg`, so an imported slide image was replaced by its layout image after save. The final repair retains the original local background XML with namespace bindings, serializes it before the shape tree, and updates its image relationship when a copied slide is written to a new part. Original gradient stops and noFill survive saving. Assigning an explicit solid background clears the retained fill and selected imported picture while retaining ordinary decorations; clearing that assignment allows the existing layout background to resolve on reopening. Copying retains independent XML and picture objects.

## Captured stages

| Stage | Result | Meaning |
| --- | --- | --- |
| `incoming` | 30 passed / 8 failed | Existing tests passed; all eight incoming inheritance regressions failed before behavior repair. |
| `repaired` | 37 passed / 1 failed | Import repair fixed inheritance; authored image save/reopen still failed. Not acceptance. |
| `retained` | Compile failed | A new regression used an incorrect PackagePart getter; corrected before acceptance. |
| `serialization` | 42 passed / 0 failed | All original tests plus the twelve targeted regression cases passed. |
| `serialization-analysis` | Exit 0, no issues | Strict analysis of all edited sources and tests passed. |

The directory also preserves the earlier merge compile failure (duplicate named argument) and the interrupted automatic-pub runner attempt. These are diagnostic evidence, not successful acceptance receipts. The final test used the pinned Dart VM directly with the resolved package:test entry point; `run_background.py` records the command and hashes.

## Scope and primary sources

Gradients still render with the incoming feature's first-stop **solid approximation**; this repair does not claim full gradient rendering. The authored gradient XML is retained without discarding later stops. Full engine/editor cohorts are coordinated by the parent task.

The selection, drawing order and distinction between background fills and master-shape visibility were checked against these primary Microsoft OpenXML/PowerPoint references:

- https://learn.microsoft.com/en-us/office/open-xml/presentation/working-with-slide-layouts
- https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.background?view=openxml-3.0.1
- https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.backgroundproperties?view=openxml-3.0.1
- https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slide.followmasterbackground

Production edits are complete in `pml_presentation.dart`, `slide_serial.dart`, `drawingml.dart`, and `slide_import_fidelity_test.dart`. The subagent performed no staging, commits or remote writes.
