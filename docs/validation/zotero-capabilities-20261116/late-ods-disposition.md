# Late ODS branch disposition

This review accounts for the additional ODS and documentation refs fetched
after the first continuation PR was created. The frozen observed main is
`47aa74ab2c45a5ce514343b44296a1a14fa3ae95`, following the ODS implementation
checkpoint `7edb096d3328263c75dc0229ff43bb77183e1ad3`.

**None of these seven late branch tips contains a unique unintegrated
implementation change.** Corresponding feature and vendor commits have
identical stable patch IDs. Six branch trees exactly match their merged
counterparts. The remaining vendor-filter tree differs only in two older
documentation files, because it omits the already merged metadata-documentation
update.

The preceding full audit is preserved unchanged in
[pre-pr-incoming-refs.json](pre-pr-incoming-refs.json) and
[pre-pr-incoming-work.md](pre-pr-incoming-work.md). This source comparison
does not overwrite that cutoff or claim a new test execution.

## Exact comparisons

| Advertised branch and shared PR head | Exact branch tip | Merged counterpart | Result |
| --- | --- | --- | --- |
| `feat/ods-outline`, PR #60 | `988f423b9b95037d8f5273ee368b58ceedab0667` | `0969b2203a6758116bf42b53d7348898cc79d7ea` | Entire tree identical; same patch ID |
| `vendor/ods-outline` | `33a0508a502f5809aa997928e8428bdec3e02503` | `0969b2203a6758116bf42b53d7348898cc79d7ea` | Entire tree identical; same patch ID |
| `feat/ods-filter-predicates`, PR #62 | `089e53fce443ca2169fc44f3700e1b23780d2c95` | `7edb096d3328263c75dc0229ff43bb77183e1ad3` | Entire tree identical; same patch ID |
| `vendor/ods-filter-predicates` | `a53a37b0b5c1b55aff20d581f80f1b2027bf3ddb` | `7edb096d3328263c75dc0229ff43bb77183e1ad3` | Production/test blobs identical; same patch ID; older documentation only |
| `docs/metadata-complete`, PR #61 | `b23ee557ea121774833c7a188a49189e4f80ce70` | `3624a9702054f6f64f7132b374bbcf827bfcf232` | Entire tree identical; same patch ID |
| `vendor/ods-hyperlinks-current` | `be6aa3cf2fca1b775c2b1352881e2ca3f9134c13` | `14b13980e0005f4a56e0d0790ed3a2c1fa4798e2` | Entire tree identical; same patch ID |
| `docs/filters-closed`, PR #64 | `4a122b3b71ddc539f8ffda5541b7e6ab0f1dce8f` | `47aa74ab2c45a5ce514343b44296a1a14fa3ae95` | Entire tree identical; same patch ID |

The matching tree IDs are:

| Counterpart | Tree |
| --- | --- |
| Hyperlinks `14b13980` | `91a4926e888cf4107f480e802b38da53653b3cbf` |
| Outline `0969b220` | `496a4a3ba8e4125d82cd1c4e40ac7a8bae6ca8a3` |
| Metadata documentation `3624a970` | `2a7326ccf552612bbb0930bfb254a25778172625` |
| Filters `7edb096d` | `259cfb041bd534757db93c3faf5993eb376801e4` |
| Final documentation `47aa74ab` | `08e54aba5a5507ac9a72c662286475e28776c5fe` |

`vendor/ods-filter-predicates` has tree
`4859ede5b27c50ef6ce29d930acb697ab0d0e23b`. Its only whole-tree differences
from merged `7edb096d` are `docs/office-remaining-gaps.md` and
`packages/quds_office_engine/CHANGELOG.md`. Its three changed production/test
files have exactly these same blobs as merged main:

| Path | Identical blob |
| --- | --- |
| `packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_reader.dart` | `6dd86cf3e68d0e8b1057b9985eb08df85dd9a1dc` |
| `packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart` | `e2a79c8683980da5ecc445fdf7b86410611130ed` |
| `packages/quds_office_engine/test/ods_sheet_reader_test.dart` | `f0a85b25f0e6276a82457bbcf76fe795bc7cc31d` |

## Stable patch identities

| Change | `git patch-id --stable` |
| --- | --- |
| Current hyperlinks | `2c78beb7b81a65c220f2a81aa2d10bb88503c0a3` |
| Outline groups | `cffd59b544ca78407a50eb983b2744f0ae4c3707` |
| Metadata/hyperlink documentation | `18bc8b9e412ce7222d92a418a8e7b78396ba51b9` |
| Filter predicates | `513c83711631c5fc732f450f1f533c599fa215a1` |
| Final metadata/validation documentation | `41e92c47dc6ff791a310727c48265cc7fd84e48e` |

`git cherry -v` against the merged counterparts reports only `-` for the
reviewed side commits. Exact tree/blob comparisons independently confirm the
scope of each match. These late refs require patch-equivalence dispositions,
not an inference that their implementation is merely behaviorally superseded.
The older `vendor/ods-hyperlinks` tip `95debbc...` is a separate historical
ref from `vendor/ods-hyperlinks-current`; the full current audit records its
actual final ancestry separately.

## Main source delta

Main from `14b13980` through `7edb096d` changes these production paths:

- `packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_reader.dart`
- `packages/quds_office_engine/lib/src/sheet/model/sml_workbook.dart`
- `packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart`

Its corresponding test update is
`packages/quds_office_engine/test/ods_sheet_reader_test.dart`. Documentation
changes are confined to `docs/office-remaining-gaps.md` and
`packages/quds_office_engine/CHANGELOG.md`.

The subsequent `47aa74ab` / PR #64 changes only those two documentation files;
it adds no production or test delta over `7edb096d`.

## Reproduction and scope

For any branch SHA and merged counterpart in the table, compare their exact
trees and the stable patch IDs:

```bash
git rev-parse '<branch-sha>^{tree}' '<merged-sha>^{tree}'
git diff --name-status <merged-sha> <branch-sha>
git show --format= <branch-sha> | git patch-id --stable
git show --format= <merged-sha> | git patch-id --stable
git cherry -v 47aa74ab2c45a5ce514343b44296a1a14fa3ae95 <branch-sha>
```

This review uses already fetched refs and local Git objects. It runs no Dart,
Flutter or CI tests, makes no code or commit changes, and performs no additional
full-ref fetch. Final combined-source qualification belongs to its separately
recorded published source pin.
