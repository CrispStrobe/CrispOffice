# Disposition of the older ODS hyperlink vendor branch

Reviewed on 2026-11-16 using the already fetched local objects. **The ODS hyperlink feature on `origin/vendor/ods-hyperlinks` is fully represented in merged main. No vendor-unique source change remains to integrate.** Retain main's newer reader, serializer, and tests. This is a finding of behavioral supersession, not whole-branch patch equivalence.

## Exact source identities

| Role | Commit |
| --- | --- |
| Older vendor head | `95debbcce02c1e24d6e8159cd1f524bbf68afeba` |
| Vendor parent | `388a1c76339507d493bab577424affd80732446c` |
| Feature head | `e5daa20587e10971e8cb97d82a5495584b5c1553` |
| Main containing PR #59 | `14b13980e0005f4a56e0d0790ed3a2c1fa4798e2` |

The vendor commit changes five files (110 insertions, three deletions). All five files are byte-identical between the feature head and merged main. Both model files are also byte-identical to the older vendor version; only the reader, serializer, and test file differ from the vendor snapshot.

Paths below are relative to `packages/quds_office_engine/`.

| File | Vendor blob | Feature/main blob |
| --- | --- | --- |
| `lib/src/sheet/legacy/ods_sheet_reader.dart` | `be1f8cb330db07d7e474f4d88951dbfdce9a4e01` | `af0a2dea9c0f34d5157fb3be12188b7e7f126d1c` |
| `lib/src/sheet/model/sml_analysis.dart` | `6bc81f6ca7292709df4ef82d64b37152e97d48ea` | same |
| `lib/src/sheet/model/sml_workbook.dart` | `4fea33d8830650094df7c89c7d65a90ca775a5eb` | same |
| `lib/src/sheet/serial/sheet_serial.dart` | `818f6d18c47704f75e27e17e4faf4768fa0ba616` | `0ac3ebaac42576bf797bceb5129c5303d3ce3a45` |
| `test/ods_sheet_reader_test.dart` | `74b19eae6080466f77bc7ba461efff7e794d2ad1` | `9f6240846c0823cef80f4d0d9e6a80a79e67e8e9` |

## Every vendor feature is retained

The original patch was reviewed against its parent and then against the feature/main versions of all five files:

| Vendor behavior | Evidence in feature/main |
| --- | --- |
| Read an ODS text hyperlink, retain an external destination, and convert `#Data.A1` into the internal location `Data!A1` | `_readHyperlink` is byte-identical. `_OdsCellContent`, `_readCellContent`, and `_readCell` retain the hyperlink, including a linked cell with no value. |
| Preserve the hyperlink while repeating/copying imported cells and cloning the model | `_copyCell` copies `source.hyperlink`; `SmlCell.hyperlink` and the `SmlAnalysis` clone addition are retained. Both model files have identical blobs. |
| Write XLSX external relationships or internal locations | `_writeHyperlinks` is byte-identical; its invocation remains after data validations. It reuses a matching external hyperlink relationship or creates one and writes `r:id`, or writes an internal `location`. |
| Exercise external and internal hyperlink export | The existing test `ODS external and internal hyperlinks survive XLSX` retains the same fixture and assertions: imported A1/B1 destinations, saved worksheet hyperlink elements/relationship ID/internal location, and external relationship target. Its differences are formatting only. |

For independently comparable method evidence, the reader's complete `_readHyperlink` block through the blank line before `_readImages` is 412 bytes with SHA-256 `44e7a3cc88a34dbe2fcb36add1b7171915255b3bfa55a77efa746db03d5e3749`. The complete serializer `_writeHyperlinks` block through the blank line before `_writeSheetFormat` is 1,506 bytes with SHA-256 `f82ec265226350558d8dc147c8fc93928786473d1c2aa8c0023294ccc7588509`. Each block matches exactly in vendor and main.

## Why the three differing main files must be retained

**Reader:** Main reads spreadsheet-level validation definitions and combines them with table-local definitions, with the local table taking precedence. It preserves validation references on blank input cells and charges their repeated expansion to the existing cell budget and grid limits. The older vendor snapshot lacks these additions. The vendor-to-main reader diff removes no hyperlink behavior.

**Serializer:** Main declares the worksheet `r` namespace before writing the `sheetPr` child. The vendor version tries to declare that namespace after the tab-color child has already been written. Keeping main preserves correct namespace placement when tab color coexists with drawings or external hyperlinks; the hyperlink writer itself is unchanged.

**Tests:** Main registers the existing `imageTests()` suite and adds `ODS tab colour and picture survive save together`, which checks tab color plus saved/reopened PNG bytes and dimensions. It also adds six validation regressions covering blank numeric input cells across XLSX save/reopen, repetition/grid limits, shared definitions on multiple sheets, range lists referencing a later sheet, local overrides and isolation, and rejection of foreign-namespace validation containers. Aside from formatting, these are the only test-file differences. The vendor hyperlink test remains present.

## Reproduction and limits

These read-only comparisons reproduce the disposition:

```sh
git show --stat 95debbcce02c1e24d6e8159cd1f524bbf68afeba
git show 95debbcce02c1e24d6e8159cd1f524bbf68afeba -- \
  packages/quds_office_engine/lib/src/sheet \
  packages/quds_office_engine/test/ods_sheet_reader_test.dart
git diff --exit-code e5daa20587e10971e8cb97d82a5495584b5c1553 \
  14b13980e0005f4a56e0d0790ed3a2c1fa4798e2 -- \
  packages/quds_office_engine/lib/src/sheet \
  packages/quds_office_engine/test/ods_sheet_reader_test.dart
git diff --ignore-all-space 95debbcce02c1e24d6e8159cd1f524bbf68afeba \
  14b13980e0005f4a56e0d0790ed3a2c1fa4798e2 -- \
  packages/quds_office_engine/lib/src/sheet \
  packages/quds_office_engine/test/ods_sheet_reader_test.dart
```

This report records static patch, blob, and regression-source review. It does not add runtime test results or establish broader ODS conformance beyond the compared behavior. No new fetch, merge, ref update, source edit, commit, or CI operation was performed for this review; only this report was written. Runtime qualification is recorded separately.
