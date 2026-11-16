# Scoped license and source audit

Date: **16 November 2026**. Integrated base:
[`0d19b16e10c6bc8492f47880321df2d9f2561223`](https://github.com/CrispStrobe/quds_office_suite/commit/0d19b16e10c6bc8492f47880321df2d9f2561223).
Audited implementation:
[`097f6153906e246d33a72382bfc5454fd8e40b9d`](https://github.com/CrispStrobe/quds_office_suite/commit/097f6153906e246d33a72382bfc5454fd8e40b9d).

## Result and boundary

The audited delta adds **no GPL/LGPL component, package dependency, native library,
native binding, or font binary**. The five changed production files remain Dart
code. The only newly attributed third-party material is a numeric OpenType
coverage-table transcription from **MIT-licensed FontTools 4.61.1**, with its
copyright and complete license retained.

All **nine package/workspace manifests**, all **14 bundled font binaries**, and
both existing font notices are byte-for-byte unchanged between the two exact
Git revisions. Their working-tree bytes also matched the audited revision.
The current root lockfile exactly matches the inherited committed lock snapshot,
as detailed below.

This is a review of the stated delta and preserved inputs, **not a certification
of the entire inherited repository or its complete dependency/license closure**.
No test suite, analyzer, GitHub Actions job, check, or status was run or queried
for this audit. Runtime qualification is recorded separately.

## Comparison method

The inventory came from `git ls-tree -r --name-only` at both revisions, and
contents were read with `git show REV:PATH`. Equality checks compared actual
bytes, then recorded identifiers below. Manifest and bundled-font path sets
also matched, so the comparison did not merely overlook an added file.

The complete delta contains 15 paths: five production Dart files, Dart tests
and support code, documentation/validation tooling, a changelog, and one MIT
notice. No build configuration, package manifest, tracked lockfile, native
source, native binary, or font binary changed. Review of new production imports
found no new external package import, FFI binding, process execution, or runtime
download. The one added source URL is a specification citation in a comment.

### Nine unchanged manifests

The following Git blob is shared by the base and audited revision for each path:

| Path | Identical Git blob |
| --- | --- |
| `apps/quds_report_studio/pubspec.yaml` | `ac479981a30f9917e0817de6c79f2392b6f4bf87` |
| `packages/legacy_doc_parser/pubspec.yaml` | `f0389f352656d281988db1d853d6e86df67b51e7` |
| `packages/quds_office_editor/example/pubspec.yaml` | `3c4a4bc74976e5c4800e6bc20346a175538f385b` |
| `packages/quds_office_editor/pubspec.yaml` | `b5ce396826a085e04308a9917693ff33b47f795a` |
| `packages/quds_office_engine/example/pubspec.yaml` | `9e7cc2d8f24500c0403d39cd88ed1e9649d650df` |
| `packages/quds_office_engine/pubspec.yaml` | `b8df6a55e457b42e258a3cc7724df1be087464fb` |
| `packages/quds_proofing_harper/pubspec.yaml` | `21617bc027119539ebe87a94a97b622499d48c98` |
| `packages/quds_reports/pubspec.yaml` | `206c04007457d37895bac387ddb78ff4813b9511` |
| `pubspec.yaml` | `c46e3c83272694b8cda24431ce5f89159798540e` |

### Root lockfile

`pubspec.lock` is ignored/untracked in the repository, so it is **not** described
as a tracked-file Git comparison. Its current bytes were compared directly with
the base revision's committed snapshot:

- Snapshot: `docs/validation/text-rendering-20261116/resolved-dependencies.yaml`
- Snapshot Git blob: `bafa332db4f09903cbd975e0f9b48fe12df35b6d`
- Current root lock and snapshot SHA-256: `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`
- Result: **exact byte equality**.

That is also the lock hash recorded by the prior rendering qualification.
This source audit does not substitute for the current runtime's separately
recorded enforced dependency resolution.

### Fourteen unchanged bundled fonts

All paths below are under `packages/quds_office_editor/fonts/`. Each SHA-256
identifies identical bytes in the base, audited revision, and checked working
tree.

| Font | Shared SHA-256 |
| --- | --- |
| `LiberationMono-Bold.ttf` | `50464e64aaadea741fb9516748aee296d570439406be11d63df22294e77ba867` |
| `LiberationMono-BoldItalic.ttf` | `291872531f0e8013df602c412fc570241860e41b1fa1b7972537c27a19024d4d` |
| `LiberationMono-Italic.ttf` | `35c3116d4366eb0e58494d8e432d4ee0c60c5735c7f775ffc096008bd2907c74` |
| `LiberationMono-Regular.ttf` | `d18235f1e874771f4eaec3ddd6ddb4db849d334bdc6930c5c2185d9344834e62` |
| `LiberationSans-Bold.ttf` | `b72c65e551d653b54217ffad0d1454ce0657e4e8d4a28bcc79e0acd2598f4bf3` |
| `LiberationSans-BoldItalic.ttf` | `64263238517af60213cdb469165fc7e9acd0c09c35f4155f924a379f97125a57` |
| `LiberationSans-Italic.ttf` | `4ccb79043bd3a6d131b5a53901abb21261b1417f6052b38a9fa9716a4e5a3d81` |
| `LiberationSans-Regular.ttf` | `075e71be4c58beda172ecb574a799308f04c3d054c6a5b7434954d3b0f1b28d8` |
| `LiberationSerif-Bold.ttf` | `bb033fae52dcbf67a55494a08829aaa788324624d72a195af7f93da3061c928f` |
| `LiberationSerif-BoldItalic.ttf` | `10ec0fa22bc6f12a239d600c051752884d155997aafd19ebc24c4f4a8d2b98d0` |
| `LiberationSerif-Italic.ttf` | `c1882fbb05e78537b9c39dad3c07c4f231c987a3747b20c8745737aed50cd488` |
| `LiberationSerif-Regular.ttf` | `350f4ffd773cae53560c63dca3d89a5070595614fde12f772bf43feb63d81064` |
| `NotoNaskhArabic-Bold.ttf` | `b5cbcb561b4b540ff11d7b6934577dbbbbb9e1d152d47f6f31f19176d58ff39c` |
| `NotoNaskhArabic-Regular.ttf` | `8c67eaa2f0086872628fc3f7f760386f83c8be5c5e9a1ba3a38891237b2ac7cb` |

The existing Liberation and Noto notices both declare **SIL Open Font License
1.1** and retain their original copyright statements. Neither notice changed:

| Notice | Shared SHA-256 |
| --- | --- |
| `LICENSE-Liberation` | `a0c060f758d33ee59a674cd7b45914a560d0a5935968af5e87b0c6981fd89ddc` |
| `LICENSE-NotoNaskhArabic` | `07d7ff7e09c8b10fe6f1cb6c659d7a9cab691253abfc0b72794e70c598f06a1d` |

No generated diagnostic font is introduced as a shipped asset by this delta.

## FontTools transcription provenance

The `_unicodeRanges` constant contains **168 sorted, nonoverlapping numeric
intervals and their OpenType OS/2 bit assignments**. A source-data comparison
found exact equality with this normalization of FontTools 4.61.1's
`OS2_UNICODE_RANGES`: flatten named intervals, retain the numeric endpoints and
bit index, omit bit 57, and sort by scalar range. Bit 57 is handled separately
for supplementary Unicode scalars. The lookup and subset-metadata update code
are independent Dart implementation.

The original source is
[`Lib/fontTools/ttLib/tables/O_S_2f_2.py` at tag 4.61.1](https://github.com/fonttools/fonttools/blob/4.61.1/Lib/fontTools/ttLib/tables/O_S_2f_2.py).
The installed file used for transcription has the same Git blob identity as
that primary tagged source:

- Primary and local source Git blob: `9a7e5f70bb99a37ad5f1260d62b7406df9361771`
- Local source-file SHA-256: `d4fab65eee2860e25e3d31c2fe14ca8374487ca7a5cb78fa4f5bbf94c4c4a43f`
- Normative assignments: [OpenType OS/2 Unicode-range fields](https://learn.microsoft.com/en-us/typography/opentype/spec/os2#ulunicoderange1).

FontTools 4.61.1's [tagged LICENSE](https://github.com/fonttools/fonttools/blob/4.61.1/LICENSE)
is MIT, copyright **2017 Just van Rossum**. It was checked against the installed
distribution, and the complete MIT text within the new Quds notice matches
that installed license exactly:

- Upstream LICENSE Git blob: `cc633905d333c4b42c1a0c8b34e9f734adeb6e1e`
- Original MIT text SHA-256: `6787208f83f659ccbc2223b2fde952ffa6f7e8aca62f1a8a2bf5bc51bb1b2383`
- Quds provenance/notice: [`third_party/fonttools/LICENSE`](../../../packages/quds_office_engine/third_party/fonttools/LICENSE)
- Complete Quds notice SHA-256: `0b9d2e1458441c63e9f139b2a1d43e6ec22a06ea119911d47447d8ce9bcffc90`

The attribution is preserved conservatively even though the transcription
consists of numeric specification facts. No Python implementation, FontTools
package, or new runtime dependency is bundled for this operation.

## Production source binding and static review

The reviewed working-tree production bytes matched these exact files at the
audited implementation revision:

| Changed production file | SHA-256 |
| --- | --- |
| `packages/quds_office_engine/lib/src/fonts/font_subsetter.dart` | `57537f5ad63b488a7ffb8e3234e5387bc25543742a0404554f8ff586c2d08077` |
| `packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart` | `38e5042ec2f552027fc8c8f3a35555280c35e2b4a9c6abc0a18aad0287fd6432` |
| `packages/quds_office_engine/lib/src/pdf/pdf_canvas.dart` | `d65559b9e31e1c7b4e940741451092430a1764a6cf28dd1b2c5f0cb786d64cc1` |
| `packages/quds_office_engine/lib/src/pdf/pdf_document.dart` | `a9114581caf59635c538a7eb0b337bf1907a6bdd4ff2b6419cd1551ff150ae81` |
| `packages/quds_office_engine/lib/src/pdf/pdf_font.dart` | `d0c309b3091e9b6f245cafcc144d88d93e4b9f8b7e4887bd10f0c3c550351f67` |

The static review covered the independent CID/Unicode/glyph mapping, its
immutable encoding collections, matching-subset validation, font-resource
splitting at 65,535 character mappings, CIDToGIDMap stream allocation, and
the subsetter's glyph alignment, bounded component processing, structural
checks and metadata handling. No additional material licensing or correctness
issue was identified within this review's scope.

The following boundaries remain explicit:

- This is still a code-point-based export path. It does not establish shared
  positioned-glyph shaping between Flutter and headless export, or complete
  complex-script/ligature/source-cluster handling.
- The subset's OS/2 Unicode coverage and character extrema are recomputed.
  Code-page flags are conservatively cleared for partial subsets; this can
  understate legacy code-page compatibility while the cmap retains exact
  character mappings.
- Preserving font metadata is not a general determination of a user's rights
  to embed an arbitrary supplied font. The existing bundled fonts and their
  licenses are unchanged.
- Static source inspection does not establish general SFNT/PDF conformance,
  platform equivalence, raster equality, or measured performance. The
  regression and integration receipts provide the separately observed results.

## External validation tools

Already-installed **Poppler command-line executables** are used only as external
validation tools. This delta neither links nor bundles Poppler, adds it as a
package/native dependency, nor copies its GPL implementation into the fork.
The no-GPL finding above concerns shipped material in the audited delta, not
the licensing of every independent development executable available on the host.

The Python cmap diagnostic similarly uses existing FontTools, Matplotlib and
FreeType as diagnostic tooling. Its receipt records Matplotlib's bundled
**FreeType 2.6.1**. The experiment demonstrates cmap-sensitive auto-hinting in
that runtime; it is **not proof of Flutter 3.47.8's exact native rasterization
cause** and does not justify an original-font/subset bitmap-parity claim.
