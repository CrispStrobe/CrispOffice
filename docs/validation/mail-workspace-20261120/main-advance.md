# Main advance after the first Mail qualification — 20 November 2026

Remote main advanced from `5e38de19ab5af8d6811d601c7317cba7f69d516b` to
**`860c807bfd1385899eed130abfb8940f95bda113`** while the Mail publication was
being prepared. The new main incorporates the previously separate VBA and
Zotero feature heads through another contributor's Office integration, plus
the completed GitHub merge of Android PR #236. Those feature heads are now
part of main's ancestry. Their earlier in-progress validation reports retain
their original scope and are not a newly established combined-source gate.

This follow-up supersedes the earlier **current disposition** of the heads
listed below. The [09:10 UTC reference audit](remote-refresh.md) remains an
unchanged historical capture of what was actually observed then.

## Exact scope and time

The source comparison was captured at **2026-11-20T09:35:11.214884+00:00**;
the detailed Mail/configuration/progress-report checks were captured at
**2026-11-20T09:35:50.796682+00:00**. The PR metadata was read during this same follow-up.
No GitHub Actions, workflow runs, checks or commit statuses were queried.
No tests, merges, commits or product edits were performed by this audit.

| Object | Exact identity |
| --- | --- |
| Previous main | `5e38de19ab5af8d6811d601c7317cba7f69d516b` |
| Newly captured main | `860c807bfd1385899eed130abfb8940f95bda113` |
| Qualified Mail source used for comparison | `44abcfa10367c8cf586ad3cf826feb3cb1de6dab` |
| Task head observed before the parent's merge completed | `ba1800f6556484dd9d4e89e1b0b38a512c44a6a0` |
| Common merge base, Mail side | `ffb8cee3acec878cdbe3c27e0bb82f228468a30f` |
| Common merge base, Android side | `67a4917b33dcd578333adabac1c50db0fc2a62b6` |

The parent task was resolving the new-main merge concurrently. Every source
comparison in this document names committed inputs, so intermediate index or
working-tree edits do not affect these results. The full raw tree differences,
old/new blob identities, file modes, statuses, ancestry observations and
first-parent history are in [source-delta.json](main-advance/source-delta.json).

## What has now landed in main

| Formerly captured work | Exact head | Status at `860c807b` |
| --- | --- | --- |
| Older VBA checkpoint | `1fe093a217741d228c86bad4e6a5a13f777ed851` | Ancestor of main through the Office integration. |
| Latest captured VBA PR #227 head | `1ceae221d37e733f0195d35622a05f896a2d13a1` | Ancestor of main through merge `3d67261b7d6ad6fd3f6103fd651b57707137cdb3`. |
| Zotero embedded-image head | `3100725d07a715f230c263f640dbd588c7c75660` | Ancestor of main through the Zotero continuation. |
| Zotero list/image continuation | `aa51b5700a4791db088a2d47b66ff521540b42e0` | Ancestor of main through the later continuation head. |
| Later Zotero continuation | `a4ed68f2c78e0f41013c2af160fe84e27d9d84ad` | Ancestor of main through merge `ec69fab12e32cd714bbe130f2c0a21a10300ba98`. |
| Initial shared Mail workspace implementation | `ffb8cee3acec878cdbe3c27e0bb82f228468a30f` | Ancestor of main through merge `daf8bf6f03a5aeb06f7933561a9e6ffdab1886c3`. |
| CrispOffice app identities | `afc3524eb896c496475d6763ab4b37dddfe68932` | Ancestor of main. |
| Captured PPTX radial/alpha work | `20573cabfd4dcae091e4c705fd58277cc6372075` | Ancestor of main, along with later integration head `1eddb91495bd405a1dfb3b1e8734e93e85b04b1d`. |
| Android PR #236, newer evidence head | `7319b220ab2e64b440e6f63d299eb747366a24d3` | Ancestor of main through PR merge `7c562b635f932372a310b78a78eb20bdb9df626d`. |

The final main commit `860c807b` merges then-current remote main into the
`fix/word-line-boxes-20261120` aggregate. Its first parent is
`7c82a286e22a4e37e58b79edafa4c5a8c089fc41`; its second parent is the Android PR
merge `7c562b635f932372a310b78a78eb20bdb9df626d`.

GitHub now reports [PR #227](https://github.com/CrispStrobe/quds_office_suite/pull/227)
as **closed and merged**, at **09:32:04 UTC**. The returned metadata still
contains `draft: true` and the unchanged qualification-in-progress description;
the observed merged state and exact ancestor commit establish that its source
has landed, without changing what its historical evidence claims.
[PR #236](https://github.com/CrispStrobe/quds_office_suite/pull/236) is **closed
and merged**, at **09:31:28 UTC**, with head `7319b220`. The exact metadata is
retained in [pr-metadata.json](main-advance/pr-metadata.json).

### The separate Word/PowerPoint VBA reconciliation branch

`b9e4f1d4bc691714f68e3685dbf729b09ccb0449` remains **not an ancestor** of the
new main and the branch is retained separately. It has no unique non-merge
commits relative to `860c807b`, but three reconciliation merge commits remain
unique: `c224a66a`, `54d07bc3`, and `b9e4f1d4`. This does **not** establish that
its merge-resolution tree is equivalent to main or that its exact head has
been integrated. Its previously inherited VBA/Zotero feature commits being
reachable from main is a narrower, independently verified fact.

## Direct product-tree difference from qualified Mail

Comparing the two committed tips yields **205 changed tracked paths**, of
which **105 are under `packages/` or `apps/`**. Of those, **44 are implementation
paths under package `lib/`, Studio `example/lib/`, or the Arabic web worker**.
The remaining package paths contain tests, fixtures, tools, examples,
changelogs or documentation.

| Package or area | All package paths that differ | Implementation paths that differ | Principal affected area |
| --- | ---: | ---: | --- |
| `quds_arabic_morph` | 10 | 6 | Native/stub/web lifecycle and worker behavior, with regression controls. |
| `quds_mail_ui` | 1 | 0 | README only; no implementation change. |
| `quds_office_editor` | 36 | 20 | Installed fonts, shared rendering/controller paths, Zotero controls, Studio theme/menus/gallery/Arabic host, and associated tests. |
| `quds_office_engine` | 58 | 18 | VBA/macro integration, PDF/PPTX rendering, Word/Zotero images and lists, serialization, tests and tools. |
| **Total** | **105** | **44** | |

[product-paths.tsv](main-advance/product-paths.tsv) lists every one of the 105
paths with its status and exact blob identity on both sides. The complete list
of 44 implementation paths is included below for review.

A direct tip comparison also includes Mail-side improvements that the new main
has not yet inherited. In particular, `slide_radial_opacity_test.dart` is present
in qualified Mail and absent from the new main, and several shared PDF/rendering
files differ on both sides. Their appearance in this list is a reconciliation
requirement, not evidence that the new main intentionally removed the Mail
repairs. The parent's merge must retain the qualified changes and regression
coverage while reconciling the incoming implementation.

### Mail implementation and configuration identity

All **122 selected Mail implementation and manifest paths** are identical
between `44abcfa` and `860c807b`. The selection includes all Mail-package
`lib/` files and Pub manifests/locks, and the Studio `studio_mail*` and
`studio_saved_mail*` implementation files. The exact selection and empty change
result are retained in
[scope-and-provenance.json](main-advance/scope-and-provenance.json).

The only Mail-specific package/test differences in the complete tree comparison
are:

- `packages/quds_mail_ui/README.md`, where the new main lacks later Mail
  documentation from the qualified checkpoint.
- `packages/quds_office_editor/example/test/studio_mail_test.dart`, where the
  new main omits one negative assertion for the generic `noMessages` label.
  Both sides retain the positive assertion for the shared list's `noMatches`
  label. This audit does not modify either test.

Shared Studio dependencies still change, including the theme, strings, fonts,
menus, files and workspace composition. Mail implementation identity alone
does not establish that previously executed Studio results apply unchanged to
that new combined source. The parent's planned affected Office and Studio gate
must record its own resulting source identities and actual outcomes.

### Dependency, toolchain and build configuration

No Pub manifest or lockfile changes were found in either
`5e38de19..860c807b` or `44abcfa..860c807b`. The same whole-tree check found no
changes to `.fvmrc`, analysis-options files, Melos configuration, Rust toolchain
or Cargo manifests/locks, or npm manifests/locks. Root `.fvmrc`, `pubspec.yaml`,
`pubspec.lock`, and `analysis_options.yaml` additionally match exact Git blob
identities, recorded in the scope receipt.

The only workflow difference relative to qualified Mail is
`.github/workflows/office-macros.yml`, inherited with the VBA work. No workflow
was executed or queried here. The only other changed root-level path is
`README.md`. There are no package/app platform build configuration paths in
the 105-path source difference.

### Newly landed Android evidence

Relative to the already incorporated Android head `67a4917b`, newer head
`7319b220` changes only:

- `docs/validation/native-spacy-android-grammar-20261120/README.md`
- `docs/validation/native-spacy-android-grammar-20261120/ci-x86_64-gate.json`

These are another author's committed execution/provenance records. They do
not add product or workflow changes to the Mail source comparison. This audit
records their presence without opening their Actions links, querying their
runs, or claiming to have reproduced their platform results.

## Qualification attribution

At the new main commit, the VBA evidence README still says **Work in progress**
and distinguishes its development receipts from the final combined-source gate.
The Zotero image README still says **In progress**; its continuation README
retains a **Remaining publication gate**. Their exact current blobs and marker
lines are recorded in `scope-and-provenance.json`. These documents are retained
as historical records; main ancestry supersedes their earlier branch-disposition
statements, not their execution scope.

This audit contributes **zero executed tests** and does not convert another
author's work-in-progress receipts into final qualification. The original
Mail and Office runs keep their recorded input scope. The follow-up gate and
publication report must separately identify the combined tree, changed-input
coverage, actual commands and results, and any remaining platform limits.

## Exact implementation paths that differ

- `packages/quds_arabic_morph/lib/src/camel_arabic_morphology.dart`
- `packages/quds_arabic_morph/lib/src/morph_transport.dart`
- `packages/quds_arabic_morph/lib/src/morph_transport_native.dart`
- `packages/quds_arabic_morph/lib/src/morph_transport_stub.dart`
- `packages/quds_arabic_morph/lib/src/morph_transport_web.dart`
- `packages/quds_arabic_morph/web/arabic_morph_worker.mjs`
- `packages/quds_office_editor/example/lib/sample_library.dart`
- `packages/quds_office_editor/example/lib/studio_arabic_morph_host_web.dart`
- `packages/quds_office_editor/example/lib/studio_de_strings.dart`
- `packages/quds_office_editor/example/lib/studio_desktop_menu.dart`
- `packages/quds_office_editor/example/lib/studio_files.dart`
- `packages/quds_office_editor/example/lib/studio_fonts.dart`
- `packages/quds_office_editor/example/lib/studio_material_theme.dart`
- `packages/quds_office_editor/example/lib/studio_pdf_gallery.dart`
- `packages/quds_office_editor/example/lib/studio_pdf_office.dart`
- `packages/quds_office_editor/example/lib/studio_strings.dart`
- `packages/quds_office_editor/example/lib/suite_workspace.dart`
- `packages/quds_office_editor/lib/src/editor_slide/render_slide_stage.dart`
- `packages/quds_office_editor/lib/src/editor_word/paint_run_text.dart`
- `packages/quds_office_editor/lib/src/embed/office_controller.dart`
- `packages/quds_office_editor/lib/src/embed/office_editors.dart`
- `packages/quds_office_editor/lib/src/embed/office_host_fonts.dart`
- `packages/quds_office_editor/lib/src/embed/office_system_font_validation.dart`
- `packages/quds_office_editor/lib/src/embed/office_system_fonts_io.dart`
- `packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart`
- `packages/quds_office_editor/lib/src/visual/paint_office_visual.dart`
- `packages/quds_office_engine/lib/quds_office_automation.dart`
- `packages/quds_office_engine/lib/src/automation/office_macro_language.dart`
- `packages/quds_office_engine/lib/src/automation/office_macro_mcp.dart`
- `packages/quds_office_engine/lib/src/automation/office_vba_language.dart`
- `packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart`
- `packages/quds_office_engine/lib/src/pdf/office_pdf_visuals.dart`
- `packages/quds_office_engine/lib/src/pdf/pdf_canvas.dart`
- `packages/quds_office_engine/lib/src/pdf/pdf_document.dart`
- `packages/quds_office_engine/lib/src/slide/model/pml_presentation.dart`
- `packages/quds_office_engine/lib/src/slide/serial/slide_serial.dart`
- `packages/quds_office_engine/lib/src/slide/shapes/drawingml.dart`
- `packages/quds_office_engine/lib/src/slide/shapes/slide_rich_text.dart`
- `packages/quds_office_engine/lib/src/word/model/word_lists.dart`
- `packages/quds_office_engine/lib/src/word/model/word_zotero_citing.dart`
- `packages/quds_office_engine/lib/src/word/model/word_zotero_note.dart`
- `packages/quds_office_engine/lib/src/word/model/word_zotero_note_image.dart`
- `packages/quds_office_engine/lib/src/word/serial/word_deserializer.dart`
- `packages/quds_office_engine/lib/src/word/serial/word_property_io.dart`

## Reproduction

The checks use immutable commits and ordinary read-only Git operations:

```bash
git merge-base --all 44abcfa10367c8cf586ad3cf826feb3cb1de6dab \
  860c807bfd1385899eed130abfb8940f95bda113
git diff --raw --no-abbrev \
  44abcfa10367c8cf586ad3cf826feb3cb1de6dab \
  860c807bfd1385899eed130abfb8940f95bda113
git merge-base --is-ancestor <captured-feature-head> \
  860c807bfd1385899eed130abfb8940f95bda113
git log --first-parent --format='%H %P %s' \
  5e38de19ab5af8d6811d601c7317cba7f69d516b..860c807bfd1385899eed130abfb8940f95bda113
git log --no-merges --format='%H %s' \
  860c807bfd1385899eed130abfb8940f95bda113..b9e4f1d4bc691714f68e3685dbf729b09ccb0449
```
