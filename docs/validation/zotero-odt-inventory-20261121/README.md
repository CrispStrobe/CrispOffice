# Native ODT Zotero inventory — local qualification

This record covers the read-only inventory implementation captured at
`60e212b0d62f55054a1e77e5b8721564656eaf57` and preserved through
`ce4eca72da1698f1b1ce9d2d494f345dbad32827`. It was independently qualified during
the [Mail integration](../mail-unified-cache-20261121/README.md) and integrated
at `8e62c444feea8afb20a1621858bad899bc7c1d23`.

The older [native-ODT record](../zotero-native-odt-20261121/README.md) describes
its own earlier blocked documentation checkpoint. Its unexecuted status is
historical; it is not a description of the inventory implementation below.

## Actual scope

`OdfZotero.inspect` performs bounded, read-only inspection of native ODT citation
ReferenceMarks, bibliography ReferenceMarks and TextSections, cached text and
original Zotero preferences. It preserves namespace-aware part, story and
structural ownership, paragraph boundaries, UTF-16 offsets and metadata.
Authored footnotes/endnotes and table-cell identities are represented explicitly.

Ambiguous, duplicate, overlapping, protected, linked, repeated or unsupported
structures remain visible with findings and cannot silently become import
candidates. Cumulative paragraph-range work and materialized range records are
bounded, including empty and overlapping content. Unmodeled ODF owners and
ambiguous expanded XML attributes are guarded explicitly.

Inspection preserves its input bytes. It does not activate citation fields,
normalize native preferences into Word fields, contact Zotero or enable editable
ODT loading. Output explicitly reports `editable: false`.

## Executed checks

Runtime: the repository-pinned Flutter **3.47.8**, Dart **3.13.7** and Node
**24.22.3**. Dependencies resolved offline against the unchanged lockfile.

| Check | Result |
| --- | --- |
| Reference-mark, ownership, preferences and resource suites | **149 tests passed** |
| Strict analysis of ten changed Dart files | No issues |
| Strict formatting of those ten files | Zero changes |
| Portable inventory acceptance on Dart VM and compiled Node | Successful; byte-identical JSON |
| Portable fixture | Four fields; stable repeated inventory; source bytes preserved; malformed/budget cases rejected; cross-cell range ineligible |
| Tracked manifests and lockfiles | All 23 unchanged |

The original `0ad43b78` checkpoint passed 134 tests before the additional resource
and ownership cases. The final 149 supersedes that historical count. Portable
execution supplies runtime coverage, not another 149 distinct tests.

All thirteen entries in the focused source/manifest binding remain byte-identical
between qualified `60e212b0` and the captured `ce4eca72` integration head. Every
later changed path in that range was attributed to an exact previously captured
main or Mail blob; there was no new unqualified Zotero implementation delta.

## Evidence and reproduction

The [local evidence archive](../mail-unified-cache-20261121/local-evidence.tar.gz)
contains exact commands, timestamps, exit codes, source hashes, raw logs, CLI
fixtures and portable outputs under `zotero-incoming-20261121/60e212b0/`.
`zotero-incoming-20261121/ce4eca72-audit.json` records the later preservation
proof. Earlier unsuccessful analysis attempts and the superseded test-only
lint patch are retained separately and are not counted as final passes.

With the pinned SDK and locked dependencies available, run from
`packages/quds_office_engine`:

```sh
dart test --reporter expanded \
  test/odf_zotero_reference_marks_test.dart \
  test/odf_zotero_ownership_test.dart \
  test/odf_zotero_preferences_test.dart \
  test/odf_zotero_resource_test.dart
dart run tool/zotero/odt_inventory_acceptance.dart
```

The archived portable receipt includes the exact compiler and Node invocations.
GitHub Actions, check/status queues and workflow runs were neither consulted
nor awaited for this qualification.

## Remaining acceptance boundaries

Rich ODT import/editing, preservation of the complete formatting envelope,
explicit activation and editable round trips remain separate work. Installed
LibreOffice/Zotero acceptance and version-specific interoperability were not
executed here. Current fixtures are synthetic and source-contract-based; they
do not establish installed-host acceptance.
