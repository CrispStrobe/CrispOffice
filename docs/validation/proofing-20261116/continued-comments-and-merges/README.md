# Comment proofing inheritance and incoming engine integration

Validated locally on 2026-11-16 with Dart 3.13.7 from Flutter 3.47.8. No GitHub Actions were used or awaited.

## Results

- Full engine `dart analyze --fatal-infos`: no issues found.
- Ten focused engine test files at concurrency 1: **212 tests passed**.
- The current hyphenation generator reproduced its checked-in output byte for byte, including the incoming license notice whitespace. It uses the reviewed 36,709-pattern source.
- The engine library sources, selected tests, pattern inputs, generator, and package manifest did not change during the checks. See `receipt.json` and `source-manifest.json` for the exact source hashes.

The four new comment regressions exercise document default language and `noProof`, inherited paragraph and character style settings, direct run overrides, three consecutive DOCX saves and imports, changing the document proofing language, and refreshing a character style. They exposed and now cover a merge bug where `<w:noProof/>` retained an inherited `w:val="0"` attribute instead of enabling the direct override.

The other tests cover existing comment import/export, style cascade and styleless document preservation, hyphenation, Zotero client and identity responses, the incoming source identity and backoff behavior, and the incoming ODS formula reader fixes.

## Commands

From `packages/quds_office_engine`, after sourcing the workspace toolchain environment:

```bash
dart analyze --fatal-infos
dart test --concurrency=1 --reporter expanded \
  test/word_comment_proofing_styles_test.dart \
  test/word_comment_test.dart \
  test/style_cascade_test.dart \
  test/styleless_import_fidelity_test.dart \
  test/proofing_hyphenation_test.dart \
  test/zotero_client_test.dart \
  test/zotero_identity_client_test.dart \
  test/word_zotero_source_identity_test.dart \
  test/zotero_backoff_state_test.dart \
  test/ods_sheet_reader_test.dart
python3 tool/proofing/generate_hyphenation.py
```

`generator-receipt.json` records equal before and after SHA-256 values of `fdd6a9520d9dc26a240d69f01c74eb879659b21ec2431784a4660fe6db87a3e4` for the generated Dart pattern data. `analysis.log`, `tests.log`, and `generator.log` contain the command output. The earlier failing comment assertions are retained separately in `tests-before-no-proof-fix.log` for diagnosis; the receipt references only the final successful validation.

This is a source-bound local check of the merged engine changes. It does not claim a live Zotero service request or an external office application round trip.
