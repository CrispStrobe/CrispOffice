# Incoming Office follow-up — radial gradients and PDF opacity

The final incoming-work refresh found two additional commits on
`integrate/recent-pptx`: `162ff418e9ce5813d381422c6f4e69e07f9a7626`
(PDF alpha states) and `20573cabfd4dcae091e4c705fd58277cc6372075`
(radial fills). They were merged with their original ancestry into the Mail
work branch. The resulting integration base for this repair is
`ffb8cee3acec878cdbe3c27e0bb82f228468a30f`.

This report supplements [the earlier incoming Office report](incoming-office.md).
Its **137 passing cases replace the overlapping 116-case acceptance selection**;
they are not added to that earlier total. No hosted CI was queried or awaited.

This is a historical stage receipt. The subsequent concurrent-main
reconciliation is qualified in [the 300-case Office gate](main-office.md), which
replaces this overlapping selection and adds support for an omitted circle
focus as the default center.

## Defects found and corrections

The incoming picture painter emitted PDF `/GS… gs` operators, but Office
export never copied the canvas's graphics-state resources into its `PdfPage`.
Thus the authored picture opacity had no resolvable resource in exported
Word, workbook or slide pages. The painter also reset opacity to one rather
than restoring the caller's state, and applied picture opacity to the border.

The page sink now carries every referenced alpha state into the page resource
dictionary. Picture pixels use a saved graphics state, restored before the
border. PNG soft-mask alpha and constant picture opacity combine. The canvas
rejects non-finite alpha, and the writer accepts only the canonical generated
state names `GS0` through `GS1000` instead of emitting malformed resources or
silently treating invalid names as opaque.

The incoming radial parser added a second `path` branch after an existing
branch with the same condition, so its new assignment was unreachable. The
model's radial flag also never reached shape serialization or Flutter painting.

The reconciled implementation supports **explicit centered circle gradients
with the default fill tile** in shapes and imported backgrounds. Their radial
flag survives copies, fresh-deck serialization and repeated saves. Shape fill
parsing resets radial state between fills. Flutter and PDF use the circle
circumscribing the shape bounds, with the first stop at the center. PDF uses
the incoming 72-ring approximation; Flutter uses its radial shader.

This scope follows Microsoft's [focus rectangle definition](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.filltorectangle?view=openxml-3.0.1)
and the Microsoft Open Specifications team's [description of radial geometry](https://learn.microsoft.com/en-us/answers/questions/2248059/non-preset-a-tilerect-behaves-strange-in-case-of-g).
An explicit `fillToRect` with all four edges at 50% is the supported center
point. Rectangular/shape paths, missing or off-center focus rectangles, and
custom fill tiles retain the prior first-stop solid fallback. Full path-gradient
geometry, Office's special gamma interpolation and exact custom-path bounds
remain outside this bounded repair; this is not full PowerPoint visual parity.

## Acceptance on the combined source

The repository-pinned Flutter **3.47.8** / Dart **3.13.7** runtime and retained
dependency lockfile were used. All seven selections below were rerun after
the new incoming commits and corrections, including the previous autofit,
text-layout, shadow, connector and orientation regressions.

| Selection | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Engine `slide_import_fidelity_test.dart` | 51 | 0 | 0 |
| Engine `office_pdf_export_test.dart` | 27 | 0 | 0 |
| Engine `slide_gradient_merge_test.dart` | 6 | 0 | 0 |
| Engine `slide_radial_opacity_test.dart` | 14 | 0 | 0 |
| Editor `slide_render_fidelity_test.dart` | 14 | 0 | 0 |
| Editor `slide_incoming_pptx_regression_test.dart` | 17 | 0 | 0 |
| Editor `slide_transform_orientation_test.dart` | 8 | 0 | 0 |
| **Total** | **137** | **0** | **0** |

The 14 new engine cases cover parsing and cross-shape isolation, explicit
fallbacks, model copying and round trips, imported backgrounds, concentric
PDF geometry, all three Office PDF exporters, PNG alpha multiplication,
caller-state restoration, border opacity, and invalid state input. One new
Flutter pixel case checks the center, matching radii, corners and clipping in
both ordinary and background shapes. Hidden runner loader events are excluded.

All **1,494 captured Office source, asset, selected-test and dependency/config
inputs** remained byte-identical between the start and completion of these
cohorts. The full SHA-256 inventories and empty change list are retained in
`incoming-office-followup/inputs-before.json` and `inputs-after.json`.
Strict analysis of all ten changed source/test files reports no issues;
formatting and whitespace checks pass.

## Regression controls and iteration record

The engine library from unmodified incoming merge
`ffb8cee3acec878cdbe3c27e0bb82f228468a30f` was materialized separately. The
same final 14-case test file was run with only the `quds_office_engine` package
mapping redirected to that library. It produces **eight assertion failures
and six passes**. Failures establish unreachable radial import, radial loss on
native save, missing background support, ineffective picture opacity in all
three exporters, opacity leakage into the border, and acceptance of invalid
alpha input. The repaired tree passes all 14 cases inside the 98-case engine
cohort above. These controls are not additional acceptance cases.

An initial development probe had 13 passes and one incorrect test expectation:
the PDF display-list interpreter already returns top-left coordinates, whereas
the new ring-center assertion expected bottom-left coordinates. The assertion
was corrected from `pageHeight - 25` to `25`, with no product change. Its log
is retained as `probe.jsonl.gz`; only the later complete cohorts are accepted.

`incoming-office-followup/summary.json` records visible case names, outcomes,
process exit codes, errors and raw stdout hashes. Compressed raw events and
stderr are retained for the engine, editor, baseline and initial probe.

## Reproduction

From `packages/quds_office_engine`, with the pinned SDK on `PATH` and
`PUB_CACHE` pointing to the resolved cache:

```bash
dart --packages=../../.dart_tool/package_config.json \
  "$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart" --reporter=json \
  test/slide_import_fidelity_test.dart test/office_pdf_export_test.dart \
  test/slide_gradient_merge_test.dart test/slide_radial_opacity_test.dart
```

From `packages/quds_office_editor`:

```bash
flutter test --no-pub --concurrency=1 --reporter=json \
  test/slide_render_fidelity_test.dart \
  test/slide_incoming_pptx_regression_test.dart \
  test/slide_transform_orientation_test.dart
```

For the negative control, reconstruct the engine `lib/` from the integration
base with `git archive`, copy the resolved package configuration using absolute
package roots, and redirect only `quds_office_engine` to the reconstructed
package directory. Run `test/slide_radial_opacity_test.dart` with that package
configuration; exit 1 and the eight recorded failures are expected.

The acceptance establishes local source/model/rendering behavior. No installed
Windows/macOS/mobile or native PowerPoint comparison is claimed by this follow-up.
