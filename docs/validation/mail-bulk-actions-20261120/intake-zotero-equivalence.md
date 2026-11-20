# Captured Zotero merge equivalence

The captured Zotero tip `835b8019cbb873c72424e63d4df292174edd3c3e` adds historical intake evidence and reconciles already-retained Word fixture names. It introduces **no new Zotero product behavior** relative to accepted `65468fdff43c3acec20fd0d7fd8d4ae9d254d572`.

## History and product proof

Only the octopus merge itself is absent from the accepted ancestry; all five of its parents are already ancestors. The entire engine and editor `lib` trees are identical, and all **112 Zotero package paths** have identical modes and Git blobs. The only package production differences against the accepted tree are older Mail implementations, which must remain superseded by the accepted Mail source.

The [machine-readable proof](intake-zotero-equivalence.json) contains every compared Zotero blob, both full product tree IDs, all parent ancestry results and the explicit Word normalization rules. It was computed from the existing captured objects without fetching refs, editing product/tests, compiling, or querying CI.

## Retained Word coverage

Paths in this table are relative to `packages/quds_office_engine/`.

| Incoming path | Retained canonical path | Proof |
| --- | --- | --- |
| `example/macros/word_measurements.bas` | `example/macros/word_named_measurements.bas` | Exact bytes |
| `example/macros/word_measurements_positional.bas` | `example/macros/word_measurements.bas` | Exact bytes |
| `test/office_vba_word_measurements_test.dart` | `test/office_vba_word_named_measurements_test.dart` | Exact bytes |
| `test/office_vba_word_measurements_integration_test.dart` | `test/office_vba_word_named_measurements_integration_test.dart` | Exact after the listed filename/define normalization |
| `test/office_vba_word_measurements_positional_test.dart` | `test/office_vba_word_measurements_test.dart` | Exact bytes |
| `test/office_vba_word_measurements_positional_integration_test.dart` | `test/office_vba_word_measurements_integration_test.dart` | Exact after the listed filename/define normalization |
| `tool/macros/web_vba_word_measurements_smoke.dart` | `tool/macros/web_vba_word_named_measurements_smoke.dart` | Exact after the listed filename/define normalization |
| `tool/macros/web_vba_word_measurements_positional_smoke.dart` | `tool/macros/web_vba_word_measurements_smoke.dart` | Exact bytes |
| `test/office_vba_word_unit_conversions_test.dart` | `test/office_vba_word_unit_conversions_test.dart` | Retained suite adds one overflow regression |
| `test/office_vba_word_unit_conversions_integration_test.dart` | `test/office_vba_word_unit_conversions_integration_test.dart` | Exact bytes |

The filename changes distinguish the named-argument fixture from the positional fixture. The portable named driver uses `WORD_NAMED_MEASUREMENTS_BAS_BASE64`; the positional driver retains `WORD_MEASUREMENTS_BAS_BASE64`. The positional integration import differs additionally by one formatter-only line wrap. No test assertion is dropped. The accepted unit-conversion suite also retains its extra large-scalar overflow regression.

## Exact historical documents to retain

- `docs/validation/zotero-merged-cells-20261120/intake.json`
- `docs/validation/zotero-merged-cells-20261120/intake.md`

Preserve these two files byte-for-byte from the captured tip. Their 316-ref cutoff and intermediate local checkpoint belong to that historical intake; their partial qualification statements are not final acceptance evidence for the current tree. Keep the current canonical VBA and Mail documentation. Omit the incoming `*_positional*` aliases because the corresponding content and assertions already exist under the canonical paths above.

## Merge and validation decision

Preserve the captured tip as an ancestor, retain the accepted current product/test tree, and add only those two historical documents alongside this proof. Verify the resulting merge's ancestry and changed-path list. No additional Zotero Flutter run is required because the implementation and its test inputs are unchanged. Existing source-bound qualification remains applicable; the separately captured Word update must be reviewed and qualified independently.
