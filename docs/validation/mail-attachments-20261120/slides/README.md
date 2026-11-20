# Slide reconciliation qualification

The final editor cohort passes **78 tests across six complete suites**, including
eight new connector-orientation regressions. Targeted analysis of the affected
editor renderer, controller, clipboard, example alignment code, and all six test
files reports **no issues found**. No declarations were omitted from these suites.
GitHub Actions were neither queried nor awaited.

The exact commands, raw log hashes, source hashes, baseline commit, and source
overrides are in [slide-final-editor-qualification.json](slide-final-editor-qualification.json).
All 23 existing recorded source files match the published product checkpoint
`7c828840700c8f054d286d997176c14fc4b67faf`; the new orientation test is
separately bound by SHA-256. The receipt verified all 17 test-run input files
plus seven additional analyzed files after the successful run. The separate
13-path merge analyzer covering the resolved slide/PDF code and incoming Zotero
client, models, and dialogs also reports no issues.

Final engine/PDF, macro, and Word qualification is recorded separately under
[incoming-office](../incoming-office/). Its results must be read with its own
source identity; the final count in this folder is editor-only.

## Reconciled behavior

This run follows integration of the latest VBA `6b94e195` and Zotero `0aac0e0a`
heads. It includes the incoming connector stroke, clipboard, slide-copy and
morph-painting fixes, shared numeric PDF layout, and new hidden-layout
regressions. The earlier `c23c8171` editor run is retained as historical evidence.

The merge retains master-only `showMasterSp` suppression, the slide flag during
copy/save, and resolved layout decorations. Imported slides mark their decoration
list as resolved, including an empty list, so PDF output cannot revive an
unrelated global master. The renderer continues to keep master/layout decoration
IDs separate from slide animation and morph IDs, preserves decoration rotation,
and accounts for inherited backing when adapting text to dark themes.

The connector consistency pass preserves `flipH` and `flipV` through all identified
transform reconstruction sites: pointer movement, resizing, rotation, group
movement, keyboard nudges, alignment, distribution, clipboard copy/paste, example
alignment controls, automation geometry changes, and morph sampling. The immutable
transform's `copyWith` helper keeps unspecified geometry and orientation properties.
Import accepts both XML boolean spellings `1` and `true`, and save emits the true
flags. Earlier import/copy/save/reopen cases remain in the engine cohort.

The eight new editor tests exercise public controller APIs and pointer gestures:

- Single and grouped connector movement, resizing, and rotation; each checks the
  actual geometry change, retained orientation, one undo step, redo, and PPTX
  save/reopen.
- Keyboard movement and group-mate translation with distinct horizontal and
  vertical flips, including undo/redo and save/reopen.
- Clipboard copy/paste with both flip flags, authored rotation, frozen copied
  geometry despite subsequent source edits, and undo/redo.

Two integration defects were found during final qualification and corrected:

- Concurrent merges left two visibility parser definitions. The retained helper
  recognizes the presentation namespace and slide/layout roots, trims XML boolean
  values, and is defined once. The initial failed compile log is preserved.
- A clean merge passed an unscaled paragraph fallback into the already reconciled
  mixed-text PDF painter. Both existing heading-fit regressions detected it. The
  caller now passes the scaled fallback, while explicit run sizes are scaled once.
  The final editor cohort was rerun after this correction; the engine receipt
  records its complete rerun separately.

## Complete final editor suites

- `slide_render_fidelity_test.dart`
- `slide_incoming_pptx_regression_test.dart`
- `office_dark_slide_test.dart`
- `paint_run_text_unicode_test.dart`
- `slide_arrange_history_test.dart`
- `slide_transform_orientation_test.dart`

The command is reproducible from `packages/quds_office_editor` with the qualified
Flutter/Dart runtime and resolved workspace dependency graph:

```sh
flutter test --no-pub test/slide_render_fidelity_test.dart test/slide_incoming_pptx_regression_test.dart test/office_dark_slide_test.dart test/paint_run_text_unicode_test.dart test/slide_arrange_history_test.dart test/slide_transform_orientation_test.dart --reporter expanded
```

## Historical evidence, excluded from final counts

| Record | Passing tests | Scope |
| --- | ---: | --- |
| `slide-regression-qualification.json` | 98 | Initial PPTX reconciliation: 67 engine and 31 editor cases, before the later branch advances. |
| `slide-vba-merge-qualification.json` | 123 | VBA/PPTX reconciliation: 87 engine and 36 editor cases, before the final Zotero merge. |
| `slide-c23-editor-qualification.json` | 68 | Exact `c23c8171` editor qualification, before the final VBA/Zotero advances. |
| `slide-final-editor-tests-before-pdf-fit-fix.log` | 68 | Editor run before the last PDF call correction; superseded by the final rerun. |
| `slide-final-editor-tests-duplicate-parser-failure.log` | 0 | Compile failure caused by the duplicate visibility helper; no test execution. |

The historical JSON records retain their original source and log hashes, and the
corresponding raw logs are included. The VBA record explicitly corrects a metadata
capture race: the parent checkout advanced while the record was written, so its
parent and incoming identities are pinned to the merge that was actually tested.
The source hashes and test logs were unaffected. The historical counts must not be
added to the final cohort count.

These focused suites qualify the stated import, rendering, editing, and export
behavior. They are not a claim that the entire office workspace or every Office
interoperability scenario was tested.
