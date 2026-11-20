# Incoming Office integration — 20 November 2026

The Mail workspace continuation first fetched the fork heads and PR heads and
reviewed the recent incoming work. No GitHub Actions, workflow run, check or
commit-status endpoint was queried or awaited. The integration keeps original
branch ancestry and does not overwrite or delete concurrent work branches.

A later refresh also integrated the new radial-gradient and PDF-opacity commits.
The [follow-up report](incoming-office-followup.md) records their corrections
and a complete replacement **137-case** Office acceptance cohort. The 116 cases
below remain the earlier stage's evidence and are not added to that later count.

## Captured incoming refs and dispositions

| Source | Captured SHA | Disposition |
| --- | --- | --- |
| Fork main | `c16e121365b7c52c0b66371381c8c58f592e1d8e` | Integration base; already includes the previous Mail recovery merge and subsequent installed-font work |
| PR #234, `feat/crispoffice-rename-20261120` | `afc3524eb896c496475d6763ab4b37dddfe68932` | Ready, non-draft; merged with original ancestry as `b24afa6d`; migration documentation corrected below |
| `feat/android-spacy-grammar-20261120` | `fa8b71b03dcecd583a2056df2358772505bd793e` | Completed recorded Android arm64 grammar qualification; merged as `c11e9f98` |
| `ci/android-spacy-grammar-workflow` | `596fb68f64c447177ed202a40f890c20205a0270` | Its sole workflow file is byte-identical to the feature branch; ancestry retained by content-neutral merge `c768949a` |
| `integrate/recent-pptx` | `0e1d6d8c19087c8861f46565aa8a42b8fc9b9ee7` | New normal-autofit/font-metrics work merged as `1203f033`; concrete defects repaired and locally qualified below |
| PR #227, `codex/vba-variant-conversions-20261120` | `1fe093a217741d228c86bad4e6a5a13f777ed851` | Open draft, 29 commits ahead of captured main; PR and evidence still explicitly describe qualification in progress; fetched and retained separately |
| `codex/zotero-parity-20261120` | `3100725d07a715f230c263f640dbd588c7c75660` | 37 commits ahead of captured main, includes the active VBA work; its embedded-image report is explicitly “In progress”; fetched and retained separately |
| `codex/zotero-research-materials-20261120` | `a31616d3567a43307251e13a9728cf92fd8690c6` | Already an ancestor of main |
| `work/mail-attachments-20261120` | `177f29d3f9450a58f41189b462b0814aad37e45c` | Already an ancestor of main |
| `work/mail-draft-recovery-20261120` | `20b2ecf572f8fd5663a728529da7bf5c7ebbda1d` | Already an ancestor of main |

The seven historical ODS branches still contain the same eight patch-equivalent
commits (`git cherry` reports `-` for all eight). The historical ODT continuation
and union branch retain their previously established aggregate-patch/tree
equivalence to the landed squashes. The exact older heads and equivalence
identities are in [the previous integration audit](../mail-draft-recovery-20261120/integration.md).
They are not replayed over later fixes. This table is a capture, not a claim
that other contributors stopped publishing; the final Mail preflight must
refresh main and active branches again.

## CrispOffice identity change and Mail migration

PR #234 consistently changes native product names and app identities. Static
review found no remaining old executable/bundle identifiers in the current
Studio platform/build files. Five XML/plist/scheme files parse, Android's
namespace/application ID/activity package agree, the macOS product/test-host/
scheme agree, and `bash -n` accepts the build script. The checks are retained
in [platform-static-checks.json](incoming-office/platform-static-checks.json).
The PR author's macOS/Android/iOS build results retain their original source
and platform attribution; those installed-platform builds were not rerun here.

The macOS container changes from `com.quds.qudsOfficeStudio` to
`com.crispstrobe.crispoffice`. Inspection found an omission in the incoming
migration instructions: copying `Application Support/quds_office_studio` alone
preserves proofing/ribbon data, but **does not copy Mail drafts or the archive**.

`openStudioMailDraftStore` and `openStudioMailSqliteArchive` use
`getApplicationSupportDirectory()`. The locked `path_provider_foundation`
2.6.0 implementation appends the current bundle identifier on macOS. The
Mail stores then append `quds_mail` or `quds_mail_archive`. Thus both the
container name and the platform-support subdirectory change. The release
guide and example README now include the separate old-bundle-support to
new-bundle-support copy, with both apps closed and an empty destination.
Complete SQLite directories, including sidecars if present, must stay together.
Reconnecting the same provider/account identity restores its copied draft;
keychain credentials still require re-entry. These paths were established
from host and pinned dependency source, not from a newly installed macOS run.

## Android grammar evidence review

The incoming feature only expands production grammar eligibility for the
recorded Android arm64 native-library digest. It retains explicit emulator,
manual-de-DE and exact-library limits. Its source report describes completed
device replay rather than an unfinished development checkpoint.

The retained Android and macOS control reports were independently compared
again with the incoming `compare_replay_rows.py`:

| Panel | Rows | Fields compared | Differences |
| --- | ---: | ---: | ---: |
| W6 | 86 | 796 | 0 |
| W7 | 96 | 888 | 0 |
| Grammar v2 | 1,221 | 14,958 | 0 |

The three newly generated comparison JSON files are under `incoming-office/`.
This verifies the stored cross-library evidence. It is not a fresh Android
emulator run, a hardware-device qualification or a new grammar-quality claim.
Native acceptance remains scoped as described in the
[incoming report](../native-spacy-android-grammar-20261120/README.md).

## PowerPoint autofit corrections

The incoming commit parsed a normal-autofit scale and applied it to some
rendering paths. Review found that native model edits were not projected into
DrawingML, scaled paragraph terminators and line limits could hide fitted text,
and PDF height measurement disagreed with the line advances actually painted.

The reconciled implementation now:

- Reads integer and percentage-string normal-autofit attributes, with finite
  bounded values and DrawingML/text-body scope; table-cell autofit cannot
  overwrite the surrounding shape's settings.
- Retains imported source XML when autofit is unchanged, projects changed
  model values into `bodyPr`, and preserves them through copies into a fresh
  deck and repeated saves. Ordinary newly authored text boxes do not silently
  opt into normal autofit.
- Applies the scale to all rich text runs and paragraph terminators, sizes the
  visible line allowance using the fitted font, and applies spacing reduction
  in plain and rich Flutter painting.
- Records fixed-point paragraph leading separately. Normal-autofit reduction
  applies to percentage leading; fixed-point leading is retained unchanged.
- Uses one PDF paragraph-layout path for both height measurement and painting.
  Numeric, blank, mixed-style, tabbed and wrapped paragraphs use the same line
  advances for vertical anchoring and emitted text. Existing authored font
  scale is considered before the legacy short-box fit heuristic.

The primary reference for normal-autofit semantics is Microsoft's
[NormalAutoFit documentation](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.normalautofit?view=openxml-3.0.1),
including the percentage-string representation and the restriction of line
space reduction to percentage paragraph leading. This is a bounded repair of
the incoming behavior, not complete DrawingML text-layout or native PowerPoint
visual parity.

## Local qualification

The runtime is the repository's pinned Flutter **3.47.8** / Dart **3.13.7**,
with the retained dependency lockfile. No hosted CI was used.

| Disjoint accepted selection | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Engine `slide_import_fidelity_test.dart` | 51 | 0 | 0 |
| Engine `office_pdf_export_test.dart` | 27 | 0 | 0 |
| Editor `slide_render_fidelity_test.dart` | 13 | 0 | 0 |
| Editor `slide_incoming_pptx_regression_test.dart` | 17 | 0 | 0 |
| Editor `slide_transform_orientation_test.dart` | 8 | 0 | 0 |
| **Total** | **116** | **0** | **0** |

These include ten new behavioral cases. Hidden runner loader events are
excluded. The three controls below overlap behavior in this selection and
are **not** added to the accepted total. Strict analysis of all nine changed
Office source/test files reports no issues. Formatting and whitespace checks
passed.

### Regression controls

An isolated engine library tree was reconstructed from unmodified incoming
merge `1203f033efe4f3832337d829da176a4aa35af620`. The same three standalone
probes were executed against that tree and then against the repaired tree:

| Probe | Incoming source | Repaired source |
| --- | --- | --- |
| Numeric/blank centered paragraphs | Fails: first baseline differs by about 11.50 points | Pass |
| Wrapped text followed by another paragraph | Fails: next baseline differs by about 3.30 points | Pass |
| Native model scale survives a save | Fails: `0.75` reopens as `1.0` | Pass |

The control source is retained as `incoming-office/baseline_regression_test.dart`.
Its baseline run exits 1 with three expected assertion failures; its repaired
run exits 0 with three passes. This records actual observable failures, not
only a source-level suspicion.

The first editor attempt failed before any case executed because parallel
Flutter startup exhausted temporary filesystem space. Its loader-error log is
retained as `editor.jsonl.gz`. A serialized retry (`--concurrency=1`) completed
all 38 editor cases successfully; `editor-serial.jsonl.gz` is the accepted run.
This environment failure is not counted as a product test failure or silently
discarded.

### Commands and receipts

With the pinned SDK on `PATH` and `PUB_CACHE` set to the resolved package cache,
the engine command was run from `packages/quds_office_engine`:

```bash
dart --packages=../../.dart_tool/package_config.json \
  "$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart" --reporter=json \
  test/slide_import_fidelity_test.dart test/office_pdf_export_test.dart
```

The editor command was run from `packages/quds_office_editor`:

```bash
flutter test --no-pub --concurrency=1 --reporter=json \
  test/slide_render_fidelity_test.dart \
  test/slide_incoming_pptx_regression_test.dart \
  test/slide_transform_orientation_test.dart
```

`incoming-office/summary.json` enumerates every visible case, process exit,
runner result and original stdout SHA-256. Compressed raw JSON events,
stderr, analysis output and the platform checks are kept alongside it.
`qualified-inputs.json` records publication-comparison hashes for the engine
and editor library/font trees, the five selected test files, SDK pin and
dependency configuration. This manifest was captured after the successful
runs; it is not described as a before/after filesystem snapshot. A later
publication can compare these exact inputs before carrying the receipts
forward.

This gate does not exercise a native PowerPoint application, installed Windows/
macOS/mobile builds, real Mail delivery or a live Zotero service. Mail workspace
validation and the final remote refresh are recorded separately.
