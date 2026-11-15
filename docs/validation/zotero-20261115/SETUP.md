# Zotero validation receipt — 15 November 2026

Source: `9da9c638bfe3bf932a70b2268dc16ef783fc009a`, including main `c210315bee537776b556ae9885e907483b6df7bd`.
Implementation files were unchanged when these focused suites ran. Documentation may be added afterward without changing the certified source.

| Gate | Result | Evidence |
| --- | ---: | --- |
| Engine Zotero, native field and bibliography regression cohort | 66 passed | [engine.log](engine.log) |
| Shared editor controller, formatting and dialog cohort | 43 passed | [editor.log](editor.log) |
| ODS reader merge regression, counted separately | 78 passed | [ods-reader.log](ods-reader.log) |
| Targeted source analysis with `--fatal-infos` | 9 clean checks | [analysis.json](analysis.json) |

The Zotero/native-field/editor cohort contains 109 passing tests. The separate ODS reader check brings this receipt to 187 passing tests. CrispCloud host checks have their own receipt and are excluded here. Every listed test command exited 0. No GitHub Actions queue was awaited.

## Runtime and resolution

The tests ran on Linux x64 with Flutter 3.47.8 (framework `737ba8f885dc774b53b442759999a312c9461e4e`, engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`) and its bundled Dart 3.13.7.

Dependencies were resolved by real Dart Pub in standalone staging packages. The staging directories symlink the actual canonical source and test directories. No replacement implementation, dependency stub, repository manifest change, or test alteration was used to make the harness pass. The complete canonical workspace `pub get` did not complete and is not claimed.

The four staged package manifests remove `resolution: workspace`. The staged editor additionally carries the actual engine test constraint (`test: ^1.26.0`) and actual sample HTTP constraint (`http: ^1.3.0`) so one resolved graph can analyze shared source and the sample. Exact manifests, the engine and editor lockfiles, source hashes, exact process arguments, environment and analysis configuration origin are embedded in [receipt.json](receipt.json).

The executed Flutter process used the matching prebuilt tools snapshot and an independent SDK cache root with ordinary lock handling. The conventional `flutter test` commands below are equivalent. Flutter tests use `--concurrency=1` to limit temporary disk use.

## Reproduce the staging graph

Check out the certified source revision and obtain the recorded Flutter SDK. Create a disposable staging directory outside the checkout. For each `harness.packages` entry in the JSON receipt:

1. Create a directory named by the package key.
2. Write `manifest_text` to `pubspec.yaml` and, where present, `lockfile_text` to `pubspec.lock`.
3. Create each `source_directory_links` symlink, targeting that relative path in the certified checkout. This includes source, test, and required editor asset directories.

Set `FLUTTER_ROOT` and `PATH` for the SDK; use a writable `TMPDIR` and `PUB_CACHE`. In both staged `quds_office_engine` and staged `quds_office_editor`, run `dart pub get --enforce-lockfile`. A network connection or complete package cache is required. Pub verifies the locked packages; no manual package-config dependency substitutions are needed for running tests.

The exact staging manifests and lockfiles are embedded for reconstruction rather than added as a second maintained workspace. Reports and the legacy parser are path dependencies of the two tested roots and therefore do not have separate staging lockfiles.

## Focused commands

From staged `quds_office_engine`:

```sh
dart test \
  test/word_zotero_test.dart \
  test/word_field_span_test.dart \
  test/inline_field_fidelity_test.dart \
  test/word_bibliography_fidelity_test.dart \
  test/zotero_client_test.dart \
  --reporter expanded
```

From staged `quds_office_editor`:

```sh
flutter test --no-pub --concurrency=1 --reporter expanded \
  test/word_zotero_controller_test.dart \
  test/word_zotero_format_test.dart \
  test/word_zotero_dialog_test.dart
```

From staged `quds_office_engine`, run the additional merge regression independently:

```sh
dart test test/ods_sheet_reader_test.dart --reporter expanded
```

The JSON receipt contains the exact absolute launcher commands and environment used during this run. The editor count consists of 11 controller tests, 24 formatting tests and 8 dialog tests, including the 320 × 640 viewport. The logs retain individual test names.

For targeted canonical analysis, the actual Pub-resolved editor graph was normalized to absolute package URIs and its four Quds package roots mapped to the canonical source directories. This ignored analysis configuration did not change repository dependencies. The nine source-path checks, complete commands and output are retained in `analysis.json`.

## Coverage boundaries

These checks cover field parsing, creation and editing, metadata/cache preservation, malformed and protected-field handling, native field and bibliography fidelity, URI identity, client request/response handling, atomic controller history, revision guards, formatting, import and dialog behaviours. The ODS file checks only the requested reader regression after the main-branch merge.

The DOCX fixtures were independently authored from the protocol. This run does not certify acceptance by a live Microsoft Word/Zotero desktop pair, a full local CSL processor, Connector protocol integration, private-account connectivity, full application builds, every platform, or the whole repository suite. Cached citation text is explicit; the implementation does not claim full CSL style processing. Public live API observations and CrispCloud host evidence, when recorded, remain separate from these test counts.
